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
        .build()
    private val JSON_TYPE = "application/json; charset=utf-8".toMediaType()
    private var prefs: SharedPreferences? = null
    // Protect account changes against a refresh response arriving after logout/login.
    private val sessionWriteLock = Any()

    fun init(context: Context) {
        prefs = context.getSharedPreferences("sphere_session", Context.MODE_PRIVATE)
    }

    // ---------------- session ----------------
    private fun session(): JSONObject? = prefs?.getString("session", null)?.let {
        try { JSONObject(it) } catch (e: Exception) { null }
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
        s.put("meta", user?.optJSONObject("user_metadata") ?: JSONObject())
        prefs?.edit()?.putString("session", s.toString())?.apply()
    }

    fun clearSession() = synchronized(sessionWriteLock) { prefs?.edit()?.remove("session")?.apply() }

    val userId: String? get() = session()?.optString("user_id")?.takeIf { it.isNotBlank() }
    val email: String get() = session()?.optString("email") ?: ""
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
        val now = System.currentTimeMillis() / 1000
        if (current.optLong("expires_at", 0) - now > 60) return current.getString("access_token")
        return refreshMutex.withLock {
            // Recheck after waiting: another coroutine might have refreshed already.
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
                    if (session()?.optString("refresh_token") != refreshToken) {
                        throw ApiException(401, "Session changed. Please retry.")
                    }
                    saveSession(updated)
                }
                updated.getString("access_token")
            } catch (e: ApiException) {
                if (e.status in listOf(400, 401, 403, 422)) {
                    synchronized(sessionWriteLock) {
                        // A failed OLD refresh must not sign out a NEW session.
                        if (session()?.optString("refresh_token") == refreshToken) clearSession()
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
        val bearer = if (useUserToken) token() ?: Config.SUPABASE_KEY else Config.SUPABASE_KEY
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
        fun executeOnce(): String = http.newCall(request).execute().use { res ->
            val text = res.body?.string() ?: ""
            if (res.code !in 200..299) throw toError(res.code, text)
            text
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
        val o = JSONObject(raw("POST", "/auth/v1/token?grant_type=password",
            JSONObject().put("email", email).put("password", password).toString(), useUserToken = false))
        saveSession(o)
    }

    /** Returns true when the user is logged in right away (email confirmation is off). */
    suspend fun signUp(email: String, password: String, meta: JSONObject): Boolean {
        val o = JSONObject(raw("POST", "/auth/v1/signup",
            JSONObject().put("email", email).put("password", password).put("data", meta).toString(), useUserToken = false))
        return if (o.has("access_token")) { saveSession(o); true } else false
    }

    suspend fun signInWithIdToken(idToken: String, rawNonce: String) {
        val o = JSONObject(raw("POST", "/auth/v1/token?grant_type=id_token",
            JSONObject().put("provider", "google").put("id_token", idToken).put("nonce", rawNonce).toString(),
            useUserToken = false))
        saveSession(o)
    }

    suspend fun resetPassword(email: String) {
        raw("POST", "/auth/v1/recover",
            JSONObject().put("email", email).put("redirect_to", Config.WEBSITE).toString(), useUserToken = false)
    }

    suspend fun signOut() {
        try { raw("POST", "/auth/v1/logout", "{}") } catch (e: Exception) { }
        clearSession()
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
        val t = token() ?: throw ApiException(401, "Please log in again")
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

    fun publicUrl(bucket: String, path: String) = "${Config.SUPABASE_URL}/storage/v1/object/public/$bucket/$path"

    /** Calls a Supabase Edge Function (release-payout, sphere-ai, ...). */
    suspend fun function(name: String, body: JSONObject): JSONObject {
        val t = raw("POST", "/functions/v1/$name", body.toString())
        return if (t.isBlank()) JSONObject() else JSONObject(t)
    }
}
