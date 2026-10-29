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

/**
 * Website parity shell: use the same production UI, icons, transitions and themes.
 * The previous native Compose screens remain in the project for a future offline/native build.
 */
class MainActivity : ComponentActivity() {
    private lateinit var browser: WebView
    private var pendingAuthUrl: String? = null
    inner class SphereBridge {
        @JavascriptInterface fun openExternal(url: String) {
            runOnUiThread {
                try { startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) }
                catch (_: Exception) { android.widget.Toast.makeText(this@MainActivity, "Unable to open browser", android.widget.Toast.LENGTH_SHORT).show() }
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
        pendingAuthUrl?.let { url -> browser.postDelayed({ deliverAuth(url) }, 1500); pendingAuthUrl = null }
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
