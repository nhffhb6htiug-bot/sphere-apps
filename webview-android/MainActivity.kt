package com.syahifilms.sphere.webview

import android.app.Activity
import android.annotation.SuppressLint
import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.FileProvider
import androidx.credentials.CredentialManager
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.lifecycle.lifecycleScope
import androidx.webkit.WebViewAssetLoader
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import com.google.android.libraries.identity.googleid.GetSignInWithGoogleOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest
import java.util.UUID

/**
 * Sphere Android WebView — bundles the LIVE website frontend as local Android assets.
 * UI works without Render; auth/jobs/chat/payment still require Supabase + connectivity.
 *
 * Everything displayed inside the WebView has the normal Android look of the
 * official website. No desktop/iOS navigation or separate Compose screens.
 */
class MainActivity : ComponentActivity() {
    private companion object {
        const val HOST = "sphere.syahi.online"
        const val ENTRY = "https://sphere.syahi.online/index.html?source=app&platform=android"
        const val WEB_CLIENT_ID = "258192736968-ocmgvgkm00t0sglunn6tqgodpf6d4ak2.apps.googleusercontent.com"
    }

    private lateinit var browser: WebView
    private lateinit var assets: WebViewAssetLoader
    private var fileCallback: ValueCallback<Array<Uri>>? = null
    private var cameraFile: Uri? = null

    private val pickFile = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        val pending = fileCallback ?: return@registerForActivityResult
        fileCallback = null
        val values = if (result.resultCode == Activity.RESULT_OK) {
            WebChromeClient.FileChooserParams.parseResult(result.resultCode, result.data)
                ?: cameraFile?.let { arrayOf(it) }
        } else null
        pending.onReceiveValue(values)
        cameraFile = null
    }

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.statusBarColor = Color.rgb(242, 215, 245)
        window.navigationBarColor = Color.WHITE
        WebView.setWebContentsDebuggingEnabled(false)

        assets = WebViewAssetLoader.Builder()
            .setDomain(HOST)
            .addPathHandler("/", WebViewAssetLoader.AssetsPathHandler(this))
            .build()

        browser = WebView(this).apply {
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT
            )
            setBackgroundColor(Color.rgb(250, 227, 242))
            settings.apply {
                javaScriptEnabled = true
                domStorageEnabled = true
                databaseEnabled = true
                allowFileAccess = false
                allowContentAccess = true
                javaScriptCanOpenWindowsAutomatically = false
                setSupportMultipleWindows(false)
                mediaPlaybackRequiresUserGesture = true
                mixedContentMode = android.webkit.WebSettings.MIXED_CONTENT_NEVER_ALLOW
                userAgentString = userAgentString + " SphereApp/3.0 Android"
            }
            CookieManager.getInstance().setAcceptCookie(true)
            CookieManager.getInstance().setAcceptThirdPartyCookies(this, true)
            webViewClient = object : WebViewClient() {
                override fun shouldInterceptRequest(view: WebView, req: WebResourceRequest): WebResourceResponse? {
                    return if (req.url.host == HOST) assets.shouldInterceptRequest(req.url) else null
                }
                override fun shouldOverrideUrlLoading(view: WebView, req: WebResourceRequest): Boolean {
                    if (!req.isForMainFrame) return false
                    val uri = req.url
                    if (uri.scheme == "https" && uri.host == HOST) {
                        if (uri.path.isNullOrBlank() || uri.path == "/") {
                            view.loadUrl(ENTRY)
                            return true
                        }
                        return false
                    }
                    openExternal(uri.toString())
                    return true
                }
            }
            webChromeClient = object : WebChromeClient() {
                override fun onShowFileChooser(
                    view: WebView, callback: ValueCallback<Array<Uri>>,
                    params: FileChooserParams
                ): Boolean {
                    fileCallback?.onReceiveValue(null)
                    fileCallback = callback
                    return try {
                        val fileIntent = Intent(Intent.ACTION_GET_CONTENT).apply {
                            type = "*/*"
                            addCategory(Intent.CATEGORY_OPENABLE)
                            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, params.mode == FileChooserParams.MODE_OPEN_MULTIPLE)
                            putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("image/*", "video/*", "application/pdf", "audio/*"))
                        }
                        val extras = mutableListOf<Intent>()
                        val camera = Intent(MediaStore.ACTION_IMAGE_CAPTURE)
                        if (camera.resolveActivity(packageManager) != null) {
                            val dir = File(cacheDir, "camera").apply { mkdirs() }
                            val out = File.createTempFile("sphere_", ".jpg", dir)
                            cameraFile = FileProvider.getUriForFile(
                                this@MainActivity, "$packageName.fileprovider", out
                            )
                            camera.putExtra(MediaStore.EXTRA_OUTPUT, cameraFile)
                            camera.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                            extras.add(camera)
                        }
                        val chooser = Intent.createChooser(fileIntent, "Choose file or photo")
                        chooser.putExtra(Intent.EXTRA_INITIAL_INTENTS, extras.toTypedArray())
                        pickFile.launch(chooser)
                        true
                    } catch (e: Exception) {
                        fileCallback?.onReceiveValue(null)
                        fileCallback = null
                        false
                    }
                }
            }
            setDownloadListener { url, _, _, _, _ -> openExternal(url) }
        }

        // Origin-scoped messaging; unlike addJavascriptInterface this cannot be called by untrusted iframes.
        if (WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER)) {
            WebViewCompat.addWebMessageListener(
                browser, "SphereNative", setOf("https://$HOST")
            ) { _, message, sourceOrigin, isMainFrame, _ ->
                if (!isMainFrame || sourceOrigin.scheme != "https" || sourceOrigin.host != HOST) {
                    return@addWebMessageListener
                }
                try {
                    val data = JSONObject(message.data ?: return@addWebMessageListener)
                    when (data.optString("action")) {
                        "external" -> runOnUiThread { openExternal(data.optString("url")) }
                        "google" -> runOnUiThread { nativeGoogleSignIn() }
                    }
                } catch (_: Exception) {}
            }
        }
        setContentView(browser)
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                browser.evaluateJavascript(
                    "(function(){ return typeof window.sphereBack === 'function' ? window.sphereBack() : false; })()"
                ) { answer -> if (answer == "false" || answer == "null") finish() }
            }
        })
        if (savedInstanceState != null) browser.restoreState(savedInstanceState)
        else loadAuthCallback(intent.data)
    }

    private fun loadAuthCallback(uri: Uri?) {
        if (uri?.scheme == "sphereapp" && uri.host == "auth") {
            val query = uri.encodedQuery?.let { "&$it" } ?: ""
            val hash = uri.encodedFragment?.let { "#$it" } ?: ""
            browser.loadUrl(ENTRY + query + hash)
        } else browser.loadUrl(ENTRY)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        loadAuthCallback(intent.data)
    }

    override fun onSaveInstanceState(outState: Bundle) {
        browser.saveState(outState)
        super.onSaveInstanceState(outState)
    }

    private fun openExternal(raw: String) {
        try {
            val uri = Uri.parse(raw)
            val scheme = uri.scheme?.lowercase() ?: return
            if (scheme !in setOf("http", "https", "tel", "mailto", "sms", "upi", "whatsapp", "intent")) return
            val intent = if (scheme == "intent") {
                Intent.parseUri(raw, Intent.URI_INTENT_SCHEME)
            } else Intent(Intent.ACTION_VIEW, uri)
            intent.addCategory(Intent.CATEGORY_BROWSABLE)
            intent.component = null
            intent.selector = null
            startActivity(intent)
        } catch (_: Exception) {
            Toast.makeText(this, "No app available to open this link", Toast.LENGTH_SHORT).show()
        }
    }

    private fun nativeGoogleSignIn() {
        lifecycleScope.launch {
            try {
                val rawNonce = UUID.randomUUID().toString()
                val hashedNonce = MessageDigest.getInstance("SHA-256")
                    .digest(rawNonce.toByteArray(Charsets.UTF_8))
                    .joinToString("") { "%02x".format(it) }
                val option = GetSignInWithGoogleOption.Builder(WEB_CLIENT_ID)
                    .setNonce(hashedNonce).build()
                val request = GetCredentialRequest.Builder()
                    .addCredentialOption(option).build()
                val result = CredentialManager.create(this@MainActivity)
                    .getCredential(this@MainActivity, request)
                val c = result.credential
                if (c !is CustomCredential ||
                    c.type != GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL
                ) throw IllegalStateException("Google did not return an account")
                val token = GoogleIdTokenCredential.createFrom(c.data).idToken
                val payload = JSONObject().put("token", token).put("nonce", rawNonce)
                browser.evaluateJavascript("window.sphereNativeGoogleResult($payload)", null)
            } catch (_: GetCredentialCancellationException) {
                // User cancelled without making an auth attempt.
            } catch (e: Exception) {
                val payload = JSONObject().put(
                    "error", "Google sign-in unavailable. Check your Google OAuth Android client and app signing SHA-1."
                )
                browser.evaluateJavascript("window.sphereNativeGoogleResult($payload)", null)
            }
        }
    }

    override fun onDestroy() {
        fileCallback?.onReceiveValue(null)
        browser.destroy()
        super.onDestroy()
    }
}
