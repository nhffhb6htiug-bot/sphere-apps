package com.syahifilms.sphere

import android.annotation.SuppressLint
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
            settings.domStorageEnabled = true
            settings.databaseEnabled = true
            settings.allowFileAccess = false
            settings.allowContentAccess = true
            settings.javaScriptCanOpenWindowsAutomatically = false
            settings.setSupportMultipleWindows(false)
            settings.mediaPlaybackRequiresUserGesture = true
            settings.userAgentString = settings.userAgentString + " SphereAndroid/2.3"
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
