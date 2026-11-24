package com.syahifilms.sphere

import android.annotation.SuppressLint
import android.webkit.JavascriptInterface
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.ClipData
import android.app.AlertDialog
import android.provider.MediaStore
import android.widget.Toast
import androidx.core.content.FileProvider
import java.io.File
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
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
class SphereCaptureProvider : FileProvider()

class MainActivity : ComponentActivity() {
    private lateinit var browser: WebView
    private lateinit var splashOverlay: FrameLayout
    private lateinit var splashProgress: ProgressBar
    private lateinit var splashMessage: TextView
    private lateinit var splashRetry: Button
    private var primaryPageFailed = false
    private var pendingAuthUrl: String? = null
    private var googleLoginInProgress = false
    private var googleBrowserFallbackUrl: String? = null

    private fun createSplashOverlay(): FrameLayout {
        val purple = Color.rgb(117, 57, 233)
        val bg = GradientDrawable(
            GradientDrawable.Orientation.TL_BR,
            intArrayOf(Color.rgb(231, 197, 248), Color.rgb(255, 231, 218), Color.rgb(238, 220, 255))
        )
        return FrameLayout(this).apply {
            background = bg
            isClickable = true
            val stack = LinearLayout(this@MainActivity).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER
                setPadding(24, 24, 24, 24)
            }
            splashProgress = ProgressBar(
                this@MainActivity, null, android.R.attr.progressBarStyle
            ).apply {
                isIndeterminate = true
                indeterminateTintList = ColorStateList.valueOf(purple)
            }
            stack.addView(splashProgress, LinearLayout.LayoutParams(72.dp(), 72.dp()).apply {
                bottomMargin = 24.dp()
            })
            val name = TextView(this@MainActivity).apply {
                text = "Sphere"
                textSize = 38f
                setTextColor(purple)
                gravity = Gravity.CENTER
                setTypeface(null, android.graphics.Typeface.BOLD)
            }
            stack.addView(name, LinearLayout.LayoutParams(-2, -2))
            val subtitle = TextView(this@MainActivity).apply {
                text = "Connecting Editors & Clients"
                textSize = 15f
                setTextColor(Color.rgb(102, 113, 136))
                gravity = Gravity.CENTER
            }
            stack.addView(subtitle, LinearLayout.LayoutParams(-2, -2).apply { topMargin = 10.dp() })
            splashMessage = TextView(this@MainActivity).apply {
                textSize = 13f
                setTextColor(Color.rgb(102, 86, 129))
                gravity = Gravity.CENTER
            }
            stack.addView(splashMessage, LinearLayout.LayoutParams(-1, -2).apply { topMargin = 18.dp() })
            splashRetry = Button(this@MainActivity).apply {
                text = "Try again"
                visibility = View.GONE
                setOnClickListener {
                    primaryPageFailed = false
                    splashMessage.text = ""
                    splashRetry.visibility = View.GONE
                    splashProgress.visibility = View.VISIBLE
                    browser.reload()
                }
            }
            stack.addView(splashRetry, LinearLayout.LayoutParams(-2, -2).apply { topMargin = 8.dp() })
            addView(stack, FrameLayout.LayoutParams(-1, -2, Gravity.CENTER))
        }
    }

    private fun showSplashNetworkError() {
        if (!::splashOverlay.isInitialized || isFinishing || isDestroyed) return
        splashOverlay.visibility = View.VISIBLE
        splashProgress.visibility = View.GONE
        splashMessage.text = "Couldn't load Sphere. Check your internet and try again."
        splashRetry.visibility = View.VISIBLE
    }

    private fun Int.dp(): Int = (this * resources.displayMetrics.density).toInt()


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
                    googleBrowserFallbackUrl = url
                    startNativeGoogleLogin(url)
                } else {
                    openBrowser(url)
                }
            }
        }
        @JavascriptInterface fun requestNativeGoogleLogin() {
            runOnUiThread { startNativeGoogleLogin(googleBrowserFallbackUrl) }
        }
        @JavascriptInterface fun reportGoogleLoginError(message: String) {
            runOnUiThread {
                if (trustedSpherePage()) showGoogleError(message)
            }
        }
    }

    private fun showGoogleError(detail: String) {
        if (isFinishing || isDestroyed) return
        val explanation = detail.take(320).ifBlank { "Google sign-in could not finish." } +
            "\n\nYou can try signing in through Chrome, or use your email and password."
        val builder = android.app.AlertDialog.Builder(this)
            .setTitle("Sphere Google login")
            .setMessage(explanation)
            .setNegativeButton("Close", null)
        val fallback = googleBrowserFallbackUrl
        if (fallback != null) {
            builder.setPositiveButton("Open in Chrome") { _, _ -> openBrowser(fallback) }
        }
        builder.show()
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
                                const reason = e && e.message ? e.message : String(e);
                                if(window.SphereAndroid && window.SphereAndroid.reportGoogleLoginError)
                                  window.SphereAndroid.reportGoogleLoginError(reason);
                                else alert('Google login failed: ' + reason);
                              }
                            })();
                            """.trimIndent(), null
                        )
                    }
                } else {
                    // Some devices return Cancellation when selecting a Google
                    // account fails. Never silently return to the same screen.
                    showGoogleError("The Google account picker closed without a sign-in result. Your app's Android signing certificate may not match the Google Cloud OAuth settings.")
                }
            } catch (e: Exception) {
                showGoogleError(
                    "Android Google sign-in failed: " + (e.message ?: "Unknown error") +
                    "\nCheck Google Play services and the APK signing SHA-1 in Google Cloud."
                )
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
    private var pickingDocuments = false
    private var captureFile: File? = null
    private var captureUri: Uri? = null

    // Bypass the legacy mixed-media gallery (which can show empty tiles on
    // older Android/WebView builds). DocumentsUI handles images and videos
    // through explicit MIME filters and grants access only to chosen files.
    private fun acceptedTypes(params: WebChromeClient.FileChooserParams?): List<String> =
        params?.acceptTypes.orEmpty().flatMap { it.split(",") }
            .map { it.trim().lowercase() }.filter { it.isNotEmpty() }.distinct()

    private fun mediaDocumentsIntent(params: WebChromeClient.FileChooserParams?): Intent? {
        if (params == null) return null
        val types = acceptedTypes(params)
        if (types.isEmpty() || types.any { !it.startsWith("image/") && !it.startsWith("video/") }) return null
        return Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = if (types.size == 1) types.first() else "*/*"
            if (types.size > 1) putExtra(Intent.EXTRA_MIME_TYPES, types.toTypedArray())
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, params.mode == WebChromeClient.FileChooserParams.MODE_OPEN_MULTIPLE)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
    }

    private fun finishFilePicker(uris: Array<Uri>?) {
        val callback = fileCallback
        fileCallback = null
        pickingDocuments = false
        callback?.onReceiveValue(uris)
    }

    private fun selectedContentUris(data: Intent?): Array<Uri>? {
        val selected = linkedSetOf<Uri>()
        data?.data?.let { selected.add(it) }
        data?.clipData?.let { clip ->
            for (i in 0 until clip.itemCount) clip.getItemAt(i).uri?.let { selected.add(it) }
        }
        return selected.filter { it.scheme == "content" }.toTypedArray().takeIf { it.isNotEmpty() }
    }

    private val filePicker = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        val captured = captureFile
        val uri = captureUri
        captureFile = null
        captureUri = null
        val uris = when {
            result.resultCode != RESULT_OK -> null
            captured != null && uri != null && captured.length() > 0L -> arrayOf(uri)
            captured != null || pickingDocuments -> selectedContentUris(result.data)
            else -> WebChromeClient.FileChooserParams.parseResult(result.resultCode, result.data)
        }
        if (captured != null && (uris == null || uri !in uris)) captured.delete()
        if (uri != null) revokeUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        finishFilePicker(uris)
    }

    private fun browseFiles(params: WebChromeClient.FileChooserParams?, documents: Intent?) {
        if (documents != null) {
            try {
                pickingDocuments = true
                filePicker.launch(documents)
                return
            } catch (_: ActivityNotFoundException) {
                pickingDocuments = false
            } catch (_: SecurityException) {
                pickingDocuments = false
            }
        }
        try {
            filePicker.launch(params?.createIntent() ?: Intent(Intent.ACTION_GET_CONTENT).apply {
                type = "*/*"; addCategory(Intent.CATEGORY_OPENABLE)
            })
        } catch (_: Exception) {
            Toast.makeText(this, "Unable to open files.", Toast.LENGTH_SHORT).show()
            finishFilePicker(null)
        }
    }

    private fun captureMedia(video: Boolean) {
        var created: File? = null
        var output: Uri? = null
        try {
            val directory = File(cacheDir, "sphere-capture")
            directory.mkdirs()
            // Expire only old temporary captures, not the current selection.
            directory.listFiles()?.filter { it.lastModified() < System.currentTimeMillis() - 7L * 24 * 60 * 60 * 1000 }
                ?.forEach { it.delete() }
            val file = File.createTempFile("capture_", if (video) ".mp4" else ".jpg", directory)
            created = file
            val uri = FileProvider.getUriForFile(this, packageName + ".capture", file)
            output = uri
            captureFile = file
            captureUri = uri
            val action = if (video) MediaStore.ACTION_VIDEO_CAPTURE else MediaStore.ACTION_IMAGE_CAPTURE
            filePicker.launch(Intent(action).apply {
                putExtra(MediaStore.EXTRA_OUTPUT, uri)
                clipData = ClipData.newRawUri("Sphere capture", uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            })
        } catch (_: Exception) {
            created?.delete()
            output?.let { revokeUriPermission(it, Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION) }
            captureFile = null
            captureUri = null
            Toast.makeText(this, "Camera unavailable. Try Browse instead.", Toast.LENGTH_SHORT).show()
            finishFilePicker(null)
        }
    }

    private fun openFilePicker(params: WebChromeClient.FileChooserParams?) {
        val documents = mediaDocumentsIntent(params)
        val types = acceptedTypes(params)
        val photo = types.any { it == "image/*" || it == "image/jpeg" }
        val video = types.any { it == "video/*" || it == "video/mp4" }
        if (documents == null || (!photo && !video)) {
            browseFiles(params, documents)
            return
        }
        if (params?.isCaptureEnabled == true && photo != video) {
            captureMedia(video)
            return
        }
        val labels = mutableListOf("Browse photos and videos")
        val actions = mutableListOf<() -> Unit>({ browseFiles(params, documents) })
        if (photo) { labels.add("Take photo"); actions.add { captureMedia(false) } }
        if (video) { labels.add("Record video"); actions.add { captureMedia(true) } }
        AlertDialog.Builder(this)
            .setTitle("Add media")
            .setItems(labels.toTypedArray()) { _, which -> actions[which]() }
            .setNegativeButton("Cancel") { _, _ -> finishFilePicker(null) }
            .setOnCancelListener { finishFilePicker(null) }
            .show()
    }

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.statusBarColor = Color.rgb(248, 220, 230)
        window.navigationBarColor = Color.rgb(255, 231, 218)
        window.decorView.setBackgroundColor(Color.rgb(253, 233, 225))
        browser = WebView(this).apply {
            layoutParams = FrameLayout.LayoutParams(-1, -1)
            setBackgroundColor(Color.rgb(253, 233, 225))
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
                override fun onPageCommitVisible(view: WebView, url: String) {
                    super.onPageCommitVisible(view, url)
                    if (!primaryPageFailed && ::splashOverlay.isInitialized) {
                        // Page contains its own static Sphere splash before app JS runs.
                        splashOverlay.visibility = View.GONE
                    }
                }
                override fun onReceivedError(view: WebView, request: WebResourceRequest, error: android.webkit.WebResourceError) {
                    super.onReceivedError(view, request, error)
                    if (request.isForMainFrame) {
                        primaryPageFailed = true
                        showSplashNetworkError()
                    }
                }
                override fun onReceivedHttpError(view: WebView, request: WebResourceRequest, response: android.webkit.WebResourceResponse) {
                    super.onReceivedHttpError(view, request, response)
                    if (request.isForMainFrame && response.statusCode >= 500) {
                        primaryPageFailed = true
                        showSplashNetworkError()
                    }
                }
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
                    if (filePathCallback == null) return false
                    // Never replace a pending callback with a second picker request.
                    if (fileCallback != null) {
                        filePathCallback.onReceiveValue(null)
                        return true
                    }
                    fileCallback = filePathCallback
                    pickingDocuments = false
                    try {
                        openFilePicker(fileChooserParams)
                    } catch (_: Exception) {
                        finishFilePicker(null)
                    }
                    return true
                }
            }
        }
        CookieManager.getInstance().setAcceptCookie(true)
        CookieManager.getInstance().setAcceptThirdPartyCookies(browser, true)
        splashOverlay = createSplashOverlay()
        val surface = FrameLayout(this).apply {
            addView(browser, FrameLayout.LayoutParams(-1, -1))
            addView(splashOverlay, FrameLayout.LayoutParams(-1, -1))
        }
        setContentView(surface)
        if (savedInstanceState != null) {
            browser.restoreState(savedInstanceState)
            // Restored WebViews do not always fire onPageCommitVisible again.
            browser.postDelayed({ if (!primaryPageFailed) splashOverlay.visibility = View.GONE }, 2500)
        } else {
            browser.loadUrl("https://sphere-live.onrender.com/?source=app")
        }
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
        finishFilePicker(null)
        browser.destroy()
        super.onDestroy()
    }
}
