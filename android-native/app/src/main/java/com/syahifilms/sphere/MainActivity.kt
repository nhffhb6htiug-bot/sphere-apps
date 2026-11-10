package com.syahifilms.sphere

import android.annotation.SuppressLint
import android.webkit.JavascriptInterface
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.webkit.CookieManager
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
import androidx.activity.result.contract.ActivityResultContracts
import androidx.lifecycle.lifecycleScope
import com.syahifilms.sphere.data.GoogleAuth
import kotlinx.coroutines.launch

/**
 * Website parity shell: use the same production UI, icons, transitions and themes.
 * The previous native Compose screens remain in the project for a future offline/native build.
 */
class MainActivity : ComponentActivity() {
    private lateinit var browser: WebView
    private var pendingAuthUrl: String? = null
    private var googleLoginInProgress = false

    private fun trustedSpherePage(): Boolean {
        if (!::browser.isInitialized) return false
        val page = runCatching { Uri.parse(browser.url ?: "") }.getOrNull() ?: return false
        return page.scheme == "https" && page.host in setOf(
            "sphere-live.onrender.com", "sphere.syahi.online"
        )
    }

    /** Only the app's Supabase Google OAuth URL may be replaced by native sign-in. */
    private fun sphereGoogleOAuthUrl(uri: Uri): Boolean {
        if (uri.scheme != "https" || uri.getQueryParameter("provider") != "google") return false
        if (uri.path?.endsWith("/auth/v1/authorize") != true) return false
        return uri.host in setOf(
            "sphere-live.onrender.com",
            "sphere-api.niteshkumarmatho37.workers.dev",
            "pwcchgjsgkwrsvbzqspp.supabase.co"
        )
    }

    private fun openBrowser(url: String) {
        val uri = runCatching { Uri.parse(url) }.getOrNull() ?: return
        if (uri.scheme !in setOf("https", "http", "mailto", "tel")) return
        try {
            startActivity(Intent(Intent.ACTION_VIEW, uri))
        } catch (_: Exception) {
            android.widget.Toast.makeText(this, "No browser found to open this link", android.widget.Toast.LENGTH_LONG).show()
        }
    }

    /**
     * The live website calls SphereAndroid.openExternal() with its Google
     * authorize URL. Intercept that one request and use Android Credential
     * Manager, then sign in to the WebView's Supabase session directly.
     * Other outbound links continue to open in the user's chosen app.
     */
    inner class SphereBridge {
        @JavascriptInterface fun openExternal(url: String) {
            runOnUiThread {
                val uri = runCatching { Uri.parse(url) }.getOrNull()
                if (uri != null && sphereGoogleOAuthUrl(uri)) {
                    startNativeGoogleLogin(url)
                } else {
                    openBrowser(url)
                }
            }
        }
        @JavascriptInterface fun requestNativeGoogleLogin() {
            runOnUiThread { startNativeGoogleLogin(null) }
        }
    }

    private fun startNativeGoogleLogin(browserFallbackUrl: String?) {
        if (googleLoginInProgress) return
        if (!trustedSpherePage()) {
            android.widget.Toast.makeText(this, "Open the official Sphere app to sign in", android.widget.Toast.LENGTH_LONG).show()
            return
        }
        googleLoginInProgress = true
        lifecycleScope.launch {
            try {
                val google = GoogleAuth.getIdToken(this@MainActivity)
                if (google != null) {
                    // JSONObject.quote ensures a token cannot escape its JS string.
                    val idToken = org.json.JSONObject.quote(google.idToken)
                    val nonce = org.json.JSONObject.quote(google.rawNonce)
                    if (trustedSpherePage()) {
                        browser.evaluateJavascript(
                            """
                            (async function(){
                              try {
                                if(typeof sb === 'undefined' || typeof fetchAndSetCurrentUser !== 'function'){
                                  throw new Error('Sphere login screen is still loading. Please try again.');
                                }
                                const result = await sb.auth.signInWithIdToken({
                                  provider:'google', token:$idToken, nonce:$nonce
                                });
                                if(result.error) throw result.error;
                                const user = await fetchAndSetCurrentUser();
                                if(user) await nav(sphereEntryScreen(user));
                                else {
                                  const res = await sb.auth.getUser();
                                  if(res.error || !res.data.user) throw res.error || new Error('No Google user session');
                                  pendingAuthUser = res.data.user;
                                  await nav('chooseRole');
                                }
                              }catch(e){
                                alert('Google login failed: ' + (e && e.message ? e.message : String(e)));
                              }
                            })();
                            """.trimIndent(), null
                        )
                    }
                } // User closed the account picker; do not force an external login.
            } catch (e: Exception) {
                if (browserFallbackUrl != null) {
                    android.widget.Toast.makeText(
                        this@MainActivity,
                        "Google account picker unavailable; trying Chrome",
                        android.widget.Toast.LENGTH_LONG
                    ).show()
                    openBrowser(browserFallbackUrl)
                } else {
                    android.widget.Toast.makeText(
                        this@MainActivity,
                        "Google sign-in unavailable. Check Google Play services and app signing, or log in with email.",
                        android.widget.Toast.LENGTH_LONG
                    ).show()
                }
            } finally {
                googleLoginInProgress = false
            }
        }
    }

    private fun deliverAuth(url: String) {
        if (!::browser.isInitialized) { pendingAuthUrl = url; return }
        val quoted = org.json.JSONObject.quote(url)
        browser.evaluateJavascript("(async()=>{try{const u=new URL($quoted);const h=new URLSearchParams(u.hash.slice(1));const q=u.searchParams;const at=h.get('access_token')||q.get('access_token');const rt=h.get('refresh_token')||q.get('refresh_token');let error;if(at&&rt){({error}=await sb.auth.setSession({access_token:at,refresh_token:rt}));}else if(q.get('code')){({error}=await sb.auth.exchangeCodeForSession(q.get('code')));}else{throw Error(q.get('error_description')||h.get('error_description')||'No authentication tokens returned');}if(error)throw error;const user=await fetchAndSetCurrentUser();if(user)nav(sphereEntryScreen(user));else{const res=await sb.auth.getUser();pendingAuthUser=res.data.user;nav('chooseRole');}}catch(e){alert('Google login failed: '+e.message)}})();", null)
    }
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        intent.data?.takeIf { it.scheme == "sphereapp" && it.host == "auth" }?.let { deliverAuth(it.toString()) }
    }
    private var fileCallback: ValueCallback<Array<Uri>>? = null
    private val filePicker = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        val uris = if (result.resultCode == RESULT_OK) {
            WebChromeClient.FileChooserParams.parseResult(result.resultCode, result.data)
        } else null
        fileCallback?.onReceiveValue(uris)
        fileCallback = null
    }

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.statusBarColor = android.graphics.Color.rgb(232, 237, 249)
        window.navigationBarColor = android.graphics.Color.WHITE
        browser = WebView(this).apply {
            layoutParams = FrameLayout.LayoutParams(-1, -1)
            settings.javaScriptEnabled = true
            addJavascriptInterface(SphereBridge(), "SphereAndroid")
            settings.domStorageEnabled = true
            settings.databaseEnabled = true
            settings.allowFileAccess = false
            settings.allowContentAccess = true
            settings.javaScriptCanOpenWindowsAutomatically = false
            settings.setSupportMultipleWindows(false)
            settings.mediaPlaybackRequiresUserGesture = true
            settings.userAgentString = settings.userAgentString + " SphereApp/2.3 SphereAndroid/2.3"
            isVerticalScrollBarEnabled = false
            webViewClient = object : WebViewClient() {
                override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                    val url = request.url
                    if (url.scheme == "https" && (url.host == "sphere-live.onrender.com" ||
                        url.host?.endsWith(".supabase.co") == true)) return false
                    if (url.scheme == "https" || url.scheme == "http" || url.scheme == "mailto" ||
                        url.scheme == "tel" || url.scheme == "intent") {
                        try { startActivity(Intent(Intent.ACTION_VIEW, url)) } catch (_: Exception) {}
                        return true
                    }
                    return false
                }
            }
            webChromeClient = object : WebChromeClient() {
                override fun onShowFileChooser(
                    webView: WebView?, filePathCallback: ValueCallback<Array<Uri>>?,
                    fileChooserParams: FileChooserParams?
                ): Boolean {
                    fileCallback?.onReceiveValue(null)
                    fileCallback = filePathCallback
                    return try {
                        filePicker.launch(fileChooserParams?.createIntent() ?: Intent(Intent.ACTION_GET_CONTENT).apply {
                            type = "*/*"; addCategory(Intent.CATEGORY_OPENABLE)
                        })
                        true
                    } catch (_: ActivityNotFoundException) {
                        fileCallback = null
                        filePathCallback?.onReceiveValue(null)
                        false
                    }
                }
            }
        }
        CookieManager.getInstance().setAcceptCookie(true)
        CookieManager.getInstance().setAcceptThirdPartyCookies(browser, true)
        setContentView(browser)
        if (savedInstanceState != null) browser.restoreState(savedInstanceState)
        else browser.loadUrl("https://sphere-live.onrender.com/?source=app")
        intent?.data?.takeIf { it.scheme == "sphereapp" && it.host == "auth" }?.let { pendingAuthUrl = it.toString() }
        pendingAuthUrl?.let { url -> browser.postDelayed({ deliverAuth(url) }, 2500); pendingAuthUrl = null }
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                // Let Sphere's SPA navigation handle the Android back key first.
                browser.evaluateJavascript(
                    "if(window.history.length>1){window.history.back();'back'}else{'root'}"
                ) { result ->
                    if (result == "\"root\"" && browser.canGoBack()) browser.goBack()
                    else if (result == "\"root\"") moveTaskToBack(true)
                }
            }
        })
    }
    override fun onSaveInstanceState(outState: Bundle) {
        browser.saveState(outState)
        super.onSaveInstanceState(outState)
    }
    override fun onDestroy() {
        fileCallback?.onReceiveValue(null)
        fileCallback = null
        browser.destroy()
        super.onDestroy()
    }
}
