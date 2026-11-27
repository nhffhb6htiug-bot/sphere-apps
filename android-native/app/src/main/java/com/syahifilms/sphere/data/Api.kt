package com.syahifilms.sphere.data

import android.content.Context
import android.content.SharedPreferences
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.RequestBody.Companion.asRequestBody
import java.io.File
import org.json.JSONArray
import org.json.JSONObject
import java.net.URLEncoder
import java.io.IOException
import java.util.concurrent.TimeUnit

/** Error from the server, with a message that is safe to show to the user. */
class ApiException(val status: Int, message: String, val pgCode: String = "") : Exception(message)

/**
 * Talks to Supabase over plain HTTPS (same backend and security rules as the website).
 * Keeps the login session in private app storage and refreshes it automatically.
 */
object Api {
    private val http = OkHttpClient.Builder()
        .connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(90, TimeUnit.SECONDS)
        .writeTimeout(90, TimeUnit.SECONDS)
        .retryOnConnectionFailure(false)
        .followRedirects(false)
        .followSslRedirects(false)
        .build()
    private val JSON_TYPE = "application/json; charset=utf-8".toMediaType()
    private var prefs: SharedPreferences? = null
    private var appContext: Context? = null
    // Protect account changes against a refresh response arriving after logout/login.
    private val sessionWriteLock = Any()
    private var encryptedSession: SessionVault? = null
    @Volatile private var sessionJson: String? = null
    @Volatile private var sessionEpoch: Long = 0

    fun init(context: Context) = synchronized(sessionWriteLock) {
        if (prefs != null) return@synchronized
        appContext = context.applicationContext
        prefs = context.getSharedPreferences("sphere_session", Context.MODE_PRIVATE)
        // Never migrate old plaintext tokens. Force a fresh login once.
        prefs?.edit()?.remove("session")?.commit()
        encryptedSession = SessionVault(context.applicationContext)
        sessionJson = encryptedSession?.read()
    }

    // ---------------- session ----------------
    private fun session(): JSONObject? = sessionJson?.let { runCatching { JSONObject(it) }.getOrNull() }

    private fun beginLogin(): Long = synchronized(sessionWriteLock) {
        clearSession()
        sessionEpoch
    }
    private fun finishLogin(o:JSONObject,epoch:Long) = synchronized(sessionWriteLock) {
        if (sessionEpoch != epoch) throw ApiException(401,"Login was superseded. Try again.")
        if (o.optJSONObject("user")?.optString("id").isNullOrBlank()) throw ApiException(401,"Login identity missing.")
        saveSession(o)
    }

    private fun saveSession(o: JSONObject) = synchronized(sessionWriteLock) {
        val now = System.currentTimeMillis() / 1000
        val s = JSONObject()
        s.put("access_token", o.getString("access_token"))
        s.put("refresh_token", o.getString("refresh_token"))
        s.put("expires_at", if (o.has("expires_at")) o.getLong("expires_at") else now + o.optLong("expires_in", 3600))
        val user = o.optJSONObject("user")
        s.put("user_id", user?.optString("id") ?: session()?.optString("user_id") ?: "")
        s.put("email", user?.optString("email") ?: session()?.optString("email") ?: "")
        s.put("phone", user?.optString("phone") ?: session()?.optString("phone") ?: "")
        s.put("meta", user?.optJSONObject("user_metadata") ?: JSONObject())
        if (session()?.optString("user_id") != s.optString("user_id")) {
            appContext?.let { SpherePush.clearLocalAlerts(it) }
        }
        val encoded = s.toString()
        try {
            val vault = encryptedSession ?: error("Session storage unavailable")
            vault.write(encoded)
            sessionJson = encoded
        } catch (_: Exception) {
            clearSession()
            throw ApiException(503,"Secure session storage unavailable. Please sign in again.")
        }
    }

    fun clearSession() = synchronized(sessionWriteLock) {
        sessionEpoch++
        sessionJson = null
        encryptedSession?.clear()
        prefs?.edit()?.remove("session")?.commit()
        appContext?.let { SpherePush.clearLocalAlerts(it) }
    }

    val userId: String? get() = session()?.optString("user_id")?.takeIf { it.isNotBlank() }
    val email: String get() = session()?.optString("email") ?: ""
    val authPhone: String get() = session()?.optString("phone") ?: ""
    val userMeta: JSONObject get() = session()?.optJSONObject("meta") ?: JSONObject()
    val isLoggedIn: Boolean get() = session() != null

    fun getPref(key: String): String? = prefs?.getString(key, null)
    fun setPref(key: String, value: String?) {
        val e = prefs?.edit() ?: return
        if (value == null) e.remove(key) else e.putString(key, value)
        e.apply()
    }

    // Token rotation must happen once when multiple Compose screens load together.
    // Supabase refresh tokens are single-use; concurrent refreshes can sign a user out.
    private val refreshMutex = Mutex()

    /** Returns a valid access token, sharing one refresh across concurrent requests. */
    private suspend fun token(): String? {
        val current = session() ?: return null
        val epoch = sessionEpoch
        val now = System.currentTimeMillis() / 1000
        if (current.optLong("expires_at", 0) - now > 60) return current.getString("access_token")
        return refreshMutex.withLock {
            // Recheck after waiting: another coroutine might have refreshed already.
            if (epoch != sessionEpoch) throw ApiException(401,"Session changed. Please retry.")
            val latest = session() ?: throw ApiException(401, "Session expired. Please log in again")
            if (latest.optLong("expires_at", 0) - System.currentTimeMillis() / 1000 > 60) {
                return@withLock latest.getString("access_token")
            }
            val refreshToken = latest.getString("refresh_token")
            try {
                val updated = JSONObject(raw("POST", "/auth/v1/token?grant_type=refresh_token",
                    JSONObject().put("refresh_token", refreshToken).toString(),
                    useUserToken = false))
                synchronized(sessionWriteLock) {
                    // A signed-out or newly signed-in account must not inherit
                    // the old account's late network response.
                    if (epoch != sessionEpoch || session()?.optString("refresh_token") != refreshToken) {
                        throw ApiException(401, "Session changed. Please retry.")
                    }
                    saveSession(updated)
                }
                updated.getString("access_token")
            } catch (e: ApiException) {
                if (e.status in listOf(400, 401, 403, 422)) {
                    synchronized(sessionWriteLock) {
                        // A failed OLD refresh must not sign out a NEW session.
                        if (epoch == sessionEpoch && session()?.optString("refresh_token") == refreshToken) clearSession()
                    }
                    throw ApiException(401, "Session expired. Please log in again")
                }
                throw e
            }
        }
    }

    // ---------------- low level ----------------
    private suspend fun raw(
        method: String,
        path: String,
        body: String? = null,
        useUserToken: Boolean = true,
        headers: Map<String, String> = emptyMap()
    ): String = withContext(Dispatchers.IO) {
        // Anonymous requests are allowed before login, never as a silent substitute
        // for an expired/failed authenticated session.
        Config.requirePreviewBackend()
        val expectedOwner = if (useUserToken) userId else null
        val expectedEpoch = sessionEpoch
        val bearer = if (useUserToken) token() ?: Config.SUPABASE_KEY else Config.SUPABASE_KEY
        fun checkOwner() {
            if (useUserToken && (expectedOwner != userId || expectedEpoch != sessionEpoch)) throw ApiException(401,"Session changed. Please retry.")
        }
        checkOwner()
        val b = Request.Builder()
            .url(Config.SUPABASE_URL + path)
            .header("apikey", Config.SUPABASE_KEY)
            .header("Content-Type", "application/json")
        if (bearer.startsWith("ey")) b.header("Authorization", "Bearer $bearer")
        for ((k, v) in headers) b.header(k, v)
        val reqBody = body?.toRequestBody(JSON_TYPE)
        when (method) {
            "GET" -> b.get()
            "POST" -> b.post(reqBody ?: "{}".toRequestBody(JSON_TYPE))
            "PATCH" -> b.patch(reqBody ?: "{}".toRequestBody(JSON_TYPE))
            "DELETE" -> b.delete(reqBody)
            else -> b.method(method, reqBody)
        }
        val request = b.build()
        fun executeOnce(): String {
            checkOwner()
            return http.newCall(request).execute().use { res ->
                val text = res.body?.string() ?: ""
                checkOwner()
                if (res.code !in 200..299) throw toError(res.code, text)
                text
            }
        }

        // Only a read-only GET may be retried. Never resend payments, messages,
        // uploads, token rotations or other write operations after a timeout.
        if (method != "GET") return@withContext executeOnce()
        try {
            executeOnce()
        } catch (e: IOException) {
            // Recovered network blips; no retry loops or hammering the API.
            delay(350L)
            executeOnce()
        } catch (e: ApiException) {
            if (e.status !in listOf(502, 503, 504)) throw e
            delay(350L)
            executeOnce()
        }
    }

    private fun toError(status: Int, text: String): ApiException {
        return try {
            val o = JSONObject(text)
            val msg = listOf("error_description", "msg", "message", "error")
                .map { if (o.has(it) && !o.isNull(it)) o.optString(it) else "" }
                .firstOrNull { it.isNotBlank() } ?: "Something went wrong ($status)"
            ApiException(status, friendly(msg), if (o.has("code")) o.optString("code") else "")
        } catch (e: Exception) {
            ApiException(status, if (status >= 500) "Server is busy, please try again" else "Something went wrong ($status)")
        }
    }

    private fun friendly(msg: String): String {
        val m = msg.lowercase()
        return when {
            "invalid login" in m -> "Wrong email or password"
            "already registered" in m -> "An account with this email already exists. Please log in."
            "email not confirmed" in m -> "Please confirm your email first"
            "password should be" in m -> "Password must be at least 6 characters"
            "rate limit" in m -> "Too many attempts. Please try again later."
            else -> msg
        }
    }

    fun enc(v: String): String = URLEncoder.encode(v, "UTF-8").replace("+", "%20")

    // ---------------- auth ----------------
    suspend fun signInWithPassword(email: String, password: String) {
        val epoch = beginLogin()
        val o = JSONObject(raw("POST", "/auth/v1/token?grant_type=password",
            JSONObject().put("email", email).put("password", password).toString(), useUserToken = false))
        finishLogin(o,epoch)
    }

    /** Returns true when the user is logged in right away (email confirmation is off). */
    suspend fun signUp(email: String, password: String, meta: JSONObject): Boolean {
        val epoch = beginLogin()
        val o = JSONObject(raw("POST", "/auth/v1/signup",
            JSONObject().put("email", email).put("password", password).put("data", meta).toString(), useUserToken = false))
        return if (o.has("access_token")) { finishLogin(o,epoch); true } else false
    }

    suspend fun signInWithIdToken(idToken: String, rawNonce: String) {
        val epoch = beginLogin()
        val o = JSONObject(raw("POST", "/auth/v1/token?grant_type=id_token",
            JSONObject().put("provider", "google").put("id_token", idToken).put("nonce", rawNonce).toString(),
            useUserToken = false))
        finishLogin(o,epoch)
    }

    suspend fun requestPhoneOtp(phone: String, channel: String) {
        require(channel == "whatsapp" || channel == "sms")
        require(cleanIndianPhone(phone) == phone)
        // Preference is advisory; the existing server hook chooses the actual channel.
        try { rpc("sp_otp_prefer", JSONObject().put("p_phone", phone.takeLast(10)).put("p_channel", channel)) }
        catch (e: kotlinx.coroutines.CancellationException) { throw e }
        catch (_: Exception) { }
        raw("POST", "/auth/v1/otp", JSONObject().put("phone", phone)
            .put("create_user", true).put("channel", "sms").toString(), useUserToken = false)
    }

    suspend fun verifyPhoneOtp(phone: String, code: String) {
        val epoch = beginLogin()
        require(cleanIndianPhone(phone) == phone && Regex("^[0-9]{6}$").matches(code))
        val result = JSONObject(raw("POST", "/auth/v1/verify", JSONObject()
            .put("phone", phone).put("token", code).put("type", "sms").toString(), useUserToken = false))
        finishLogin(result,epoch)
    }

    suspend fun resetPassword(email: String) {
        // A verified staging recovery redirect has not been configured. Never send recovery to the live website.
        throw ApiException(503,"Password recovery is unavailable until the testing redirect is configured.")
    }

    suspend fun signOut() {
        val owner = userId
        val epoch = sessionEpoch
        try { if (owner != null) raw("POST", "/auth/v1/logout", "{}") }
        catch (e: kotlinx.coroutines.CancellationException) { throw e }
        catch (_: Exception) { }
        finally { synchronized(sessionWriteLock) { if (userId == owner && epoch == sessionEpoch) clearSession() } }
    }

    // ---------------- database (PostgREST) ----------------
    /** GET /rest/v1/<pathAndQuery>, e.g. select("profiles?id=eq.123&select=*") */
    suspend fun select(pathAndQuery: String): JSONArray = JSONArray(raw("GET", "/rest/v1/$pathAndQuery").ifBlank { "[]" })

    suspend fun selectOne(pathAndQuery: String): JSONObject? {
        val a = select(pathAndQuery)
        return if (a.length() > 0) a.getJSONObject(0) else null
    }

    suspend fun insert(table: String, row: JSONObject): JSONObject? {
        val t = raw("POST", "/rest/v1/$table", row.toString(), headers = mapOf("Prefer" to "return=representation"))
        val a = JSONArray(t.ifBlank { "[]" })
        return if (a.length() > 0) a.getJSONObject(0) else null
    }

    suspend fun insertMany(table: String, rows: JSONArray) {
        raw("POST", "/rest/v1/$table", rows.toString(), headers = mapOf("Prefer" to "return=minimal"))
    }

    suspend fun upsert(table: String, row: JSONObject, onConflict: String) {
        raw("POST", "/rest/v1/$table?on_conflict=$onConflict", row.toString(),
            headers = mapOf("Prefer" to "resolution=merge-duplicates,return=minimal"))
    }

    /** PATCH /rest/v1/<table>?<filter> */
    suspend fun update(tableAndFilter: String, fields: JSONObject) {
        raw("PATCH", "/rest/v1/$tableAndFilter", fields.toString(), headers = mapOf("Prefer" to "return=minimal"))
    }

    suspend fun delete(tableAndFilter: String) {
        raw("DELETE", "/rest/v1/$tableAndFilter")
    }

    suspend fun rpc(fn: String, args: JSONObject): String = raw("POST", "/rest/v1/rpc/$fn", args.toString())

    /** Uploads a file to Supabase Storage (bucket/path). */
    suspend fun uploadBytes(bucket: String, path: String, bytes: ByteArray, contentType: String) = withContext(Dispatchers.IO) {
        val owner = userId ?: throw ApiException(401, "Please log in again")
        val t = realtimeToken(owner)
        val req = Request.Builder()
            .url("${Config.SUPABASE_URL}/storage/v1/object/$bucket/$path")
            .header("apikey", Config.SUPABASE_KEY)
            .header("Authorization", "Bearer $t")
            .header("x-upsert", "false")
            .post(bytes.toRequestBody(contentType.toMediaType()))
            .build()
        http.newCall(req).execute().use { res ->
            if (res.code !in 200..299) throw toError(res.code, res.body?.string() ?: "")
        }
    }

    /** Stream a bounded private project file rather than loading the entire video into RAM. */
    suspend fun uploadProjectFile(owner: String, path: String, file: File, mime: String) = withContext(Dispatchers.IO) {
        require(owner == userId && path.startsWith("$owner/raw/"))
        require(file.length() in 1L..ProjectMedia.MAX_BYTES && ProjectMedia.allowedMime(mime))
        val access = token() ?: throw ApiException(401, "Please log in again")
        require(owner == userId)
        val req = Request.Builder()
            .url("${Config.SUPABASE_URL}/storage/v1/object/sphere-raw/$path")
            .header("apikey", Config.SUPABASE_KEY)
            .header("Authorization", "Bearer $access")
            .header("x-upsert", "false")
            .post(file.asRequestBody(mime.toMediaType())).build()
        http.newCall(req).execute().use { res ->
            if (!res.isSuccessful) throw toError(res.code, res.body?.string().orEmpty())
        }
    }

    suspend fun removeProjectFiles(owner: String, paths: List<String>) {
        if (paths.isEmpty()) return
        require(owner == userId && paths.all { it.startsWith("$owner/raw/") })
        raw("DELETE", "/storage/v1/object/sphere-raw", JSONObject().put("prefixes", JSONArray(paths)).toString())
    }

    /** The private bucket is accessed only by expiring signed URLs authorized by storage RLS. */
    suspend fun realtimeToken(owner: String): String {
        require(owner == userId)
        val access = token() ?: throw ApiException(401, "Please log in again")
        require(owner == userId)
        return access
    }

    suspend fun adminProofUrl(owner:String,editor:String,path:String):String {
        NativeAdmin.authorize(owner)
        require(NativeChat.validId(editor) && path.startsWith("$editor/"))
        require(Regex("^[0-9a-fA-F-]{36}/[0-9a-fA-F-]{36}\\.(jpg|jpeg|png|webp)$",RegexOption.IGNORE_CASE).matches(path))
        val result=JSONObject(raw("POST","/storage/v1/object/sign/sphere-editor-proof/$path",JSONObject().put("expiresIn",90).toString()))
        require(userId==owner)
        val relative=result.str("signedURL").ifBlank{result.str("signedUrl")}
        return when {
            relative.startsWith("/object/sign/sphere-editor-proof/")->Config.SUPABASE_URL+"/storage/v1"+relative
            relative.startsWith("/storage/v1/object/sign/sphere-editor-proof/")->Config.SUPABASE_URL+relative
            else->throw ApiException(503,"Proof unavailable")
        }
    }

    suspend fun chatMediaUrl(path: String): String {
        require(userId != null && Regex("^[0-9a-fA-F-]{36}/chat/[A-Za-z0-9_.-]+$").matches(path))
        val result = JSONObject(raw("POST", "/storage/v1/object/sign/sphere-chat/$path", JSONObject().put("expiresIn", 300).toString()))
        val relative = result.str("signedURL").ifBlank { result.str("signedUrl") }
        return when {
            relative.startsWith("/object/sign/sphere-chat/") -> Config.SUPABASE_URL + "/storage/v1" + relative
            relative.startsWith("/storage/v1/object/sign/sphere-chat/") -> Config.SUPABASE_URL + relative
            else -> throw ApiException(503, "Could not open attachment")
        }
    }

    suspend fun uploadChatFile(owner: String, path: String, file: File, mime: String) = withContext(Dispatchers.IO) {
        require(owner == userId && path.startsWith("$owner/chat/"))
        require(file.length() in 1L..ProjectMedia.MAX_BYTES && ProjectMedia.allowedMime(mime))
        val access = realtimeToken(owner)
        val req = Request.Builder().url("${Config.SUPABASE_URL}/storage/v1/object/sphere-chat/$path")
            .header("apikey", Config.SUPABASE_KEY).header("Authorization", "Bearer $access")
            .header("x-upsert", "false").post(file.asRequestBody(mime.toMediaType())).build()
        http.newCall(req).execute().use { res -> if (!res.isSuccessful) throw toError(res.code, res.body?.string().orEmpty()) }
    }

    suspend fun uploadDeliveryFile(owner: String, job: String, path: String, file: File, mime: String) = withContext(Dispatchers.IO) {
        require(owner == userId && NativeChat.validId(job) && path.startsWith("$job/"))
        require(Regex("^[0-9a-fA-F-]{36}/(preview|client)/[0-9a-fA-F-]{36}\\.[A-Za-z0-9]{1,5}$").matches(path))
        require(file.length() in 1L..ProjectMedia.MAX_BYTES && ProjectMedia.allowedMime(mime))
        val access = realtimeToken(owner)
        val req = Request.Builder().url("${Config.SUPABASE_URL}/storage/v1/object/sphere-project/$path")
            .header("apikey", Config.SUPABASE_KEY).header("Authorization", "Bearer $access")
            .header("x-upsert", "false").post(file.asRequestBody(mime.toMediaType())).build()
        http.newCall(req).execute().use { res -> if (!res.isSuccessful) throw toError(res.code, res.body?.string().orEmpty()) }
    }

    suspend fun deliveryPreviewUrl(job: String, path: String): String {
        require(path.startsWith("$job/preview/"))
        return deliveryFileUrl(job,path)
    }

    suspend fun deliveryFileUrl(job: String, path: String): String {
        require(userId != null && NativeChat.validId(job) &&
            path.startsWith("$job/") &&
            Regex("^[0-9a-fA-F-]{36}/(preview|client)/[0-9a-fA-F-]{36}\\.[A-Za-z0-9]{1,5}$").matches(path))
        val result = JSONObject(raw("POST", "/storage/v1/object/sign/sphere-project/$path",
            JSONObject().put("expiresIn", 300).toString()))
        val relative = result.str("signedURL").ifBlank { result.str("signedUrl") }
        return when {
            relative.startsWith("/object/sign/sphere-project/") -> Config.SUPABASE_URL + "/storage/v1" + relative
            relative.startsWith("/storage/v1/object/sign/sphere-project/") -> Config.SUPABASE_URL + relative
            else -> throw ApiException(503, "Preview unavailable")
        }
    }

    suspend fun projectMediaUrl(path: String): String {
        require(userId != null && Regex("^[0-9a-fA-F-]{36}/raw/[A-Za-z0-9_.-]+$").matches(path))
        val result = JSONObject(raw("POST", "/storage/v1/object/sign/sphere-raw/$path",
            JSONObject().put("expiresIn", 300).toString()))
        val relative = result.str("signedURL").ifBlank { result.str("signedUrl") }
        return when {
            relative.startsWith("/object/sign/sphere-raw/") -> Config.SUPABASE_URL + "/storage/v1" + relative
            relative.startsWith("/storage/v1/object/sign/sphere-raw/") -> Config.SUPABASE_URL + relative
            else -> throw ApiException(503, "Could not open this attachment")
        }
    }

    suspend fun updateReturning(tableAndFilter: String, fields: JSONObject): JSONObject? {
        val data = JSONArray(raw("PATCH", "/rest/v1/$tableAndFilter", fields.toString(),
            headers = mapOf("Prefer" to "return=representation")).ifBlank { "[]" })
        return if (data.length() == 1) data.getJSONObject(0) else null
    }

    fun publicUrl(bucket: String, path: String) = "${Config.SUPABASE_URL}/storage/v1/object/public/$bucket/$path"

    /** Calls a Supabase Edge Function (release-payout, sphere-ai, ...). */
    suspend fun function(name: String, body: JSONObject): JSONObject {
        // Payment operations are deliberately blocked in all preview builds.
        // This is a client-side safety guard, not a substitute for backend authorization.
        require(name !in setOf("create-razorpay-order","verify-razorpay-payment","release-payout","refund-payment","sphere-extra-payment","razorpay-webhook")) {
            "Real payment operations are unavailable in this preview."
        }
        val t = raw("POST", "/functions/v1/$name", body.toString())
        return if (t.isBlank()) JSONObject() else JSONObject(t)
    }
}
