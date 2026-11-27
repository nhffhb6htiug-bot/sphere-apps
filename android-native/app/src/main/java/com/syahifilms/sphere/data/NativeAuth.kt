package com.syahifilms.sphere.data

import org.json.JSONObject

/** Uses the current Sphere backend contracts. Never treats local UI checks as authorization. */
object NativeAuth {
    data class Settings(val otpLogin: Boolean, val waRequired: Boolean, val waNumber: String)

    suspend fun settings(): Settings {
        val rows = Api.select("sp_settings?key=in.(otp_login,wa_verify_required,wa_verify_number)&select=key,value")
        val values = mutableMapOf<String, String>()
        for (i in 0 until rows.length()) {
            val row = rows.getJSONObject(i)
            values[row.str("key")] = row.str("value")
        }
        if (values["otp_login"] !in setOf("0", "1") || values["wa_verify_required"] !in setOf("0", "1"))
            throw ApiException(503, "Could not load login settings. Please retry.")
        return Settings(values["otp_login"] == "1", values["wa_verify_required"] == "1",
            values["wa_verify_number"].orEmpty().filter { it.isDigit() }.takeLast(10))
    }

    suspend fun accountStatus(): JSONObject? {
        val raw = Api.rpc("sp_core_whoami", JSONObject())
        return if (raw.isBlank() || raw.trim() == "null") null else JSONObject(raw)
    }

    fun matchesAccount(profile: Profile, status: JSONObject): Boolean =
        profile.id == Api.userId && status.str("id") == profile.id &&
            status.str("role").lowercase() == profile.role &&
            profile.role in setOf("client", "editor", "admin") && status.has("suspended")

    suspend fun phoneStatus(): JSONObject {
        val raw = Api.rpc("sp_phone_verify_status", JSONObject())
        val status = JSONObject(raw)
        if (!status.has("required") || !status.has("verified"))
            throw ApiException(503, "Could not check phone verification")
        return status
    }

    suspend fun phoneRequired(): Boolean {
        val status = phoneStatus()
        return status.getBoolean("required") && !status.getBoolean("verified")
    }

    suspend fun beginPhoneVerification(phone: String): String {
        require(cleanIndianPhone(phone) == phone)
        val uid = Api.userId ?: throw ApiException(401, "Please log in")
        val settings = settings()
        if (!settings.waRequired || !Regex("^[6-9][0-9]{9}$").matches(settings.waNumber))
            throw ApiException(503, "WhatsApp verification is not configured")
        val current = Repo.loadMe() ?: throw ApiException(403, "Complete your profile first")
        if (cleanIndianPhone(current.phone) != phone) Api.update("profiles?id=eq.$uid", JSONObject().put("phone", phone))
        val result = JSONObject(Api.rpc("sp_phone_verify_start", JSONObject().put("p_phone", phone.takeLast(10))))
        val code = result.str("code")
        if (!Regex("^SPH-[0-9]{6}$").matches(code)) throw ApiException(503, "Could not start verification")
        return "https://wa.me/91" + settings.waNumber + "?text=" + Api.enc(code)
    }

    fun passwordProblem(password: String): String? = when {
        password.length < 8 -> "Password must be at least 8 characters."
        !Regex("[A-Za-z]").containsMatchIn(password) || !Regex("[0-9]").containsMatchIn(password) ->
            "Password must include a letter and a number."
        password.lowercase() in setOf("12345678", "password1", "qwerty12", "abcd1234") ->
            "This password is too easy to guess."
        else -> null
    }
}
