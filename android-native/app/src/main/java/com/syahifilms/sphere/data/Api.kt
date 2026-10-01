package com.syahifilms.sphere.data

import android.content.Context
import android.content.SharedPreferences
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.net.URLEncoder
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

    fun init(context: Context) {
        prefs = context.getSharedPreferences("sphere_session", Context.MODE_PRIVATE)
    }

    // ---------------- session ----------------
    private fun session(): JSONObject? = prefs?.getString("session", null)?.let {
        try { JSONObject(it) } catch (e: Exception) { null }
    }

    private fun saveSession(o: JSONObject) {
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

    fun clearSession() { prefs?.edit()?.remove("session")?.apply() }

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

    /** Returns a fresh access token (refreshes it if it is about to expire). */
    private suspend fun token(): String? {
        val s = session() ?: return null
        val now = System.currentTimeMillis() / 1000
        if (s.optLong("expires_at", 0) - now > 60) return s.getString("access_token")
        return try {
            val o = JSONObject(raw("POST", "/auth/v1/token?grant_type=refresh_token",
                JSONObject().put("refresh_token", s.getString("refresh_token")).toString(), useUserToken = false))
            saveSession(o)
            o.getString("access_token")
        } catch (e: ApiException) {
            if (e.status in 400..499) clearSession()   // refresh token no longer valid -> logged out
            null
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
        http.newCall(b.build()).execute().use { res ->
            val text = res.body?.string() ?: ""
            if (res.code !in 200..299) throw toError(res.code, text)
            text
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
