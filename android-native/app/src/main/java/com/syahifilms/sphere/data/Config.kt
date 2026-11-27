package com.syahifilms.sphere.data

/** Public settings (same as the website). Secret keys are NEVER stored in the app. */
object Config {
    private val previewRef = Regex("^https://([a-z0-9]{20})\\.supabase\\.co$").matchEntire(com.syahifilms.sphere.BuildConfig.PREVIEW_URL)?.groupValues?.get(1)
    // A JWT is a public legacy anon key only if its claims match the isolated project.
    // This is a build/runtime guard, not a signature verification or authorization boundary.
    val previewConfigured: Boolean = runCatching {
        val ref = previewRef ?: return@runCatching false
        if (ref == "pwcchgjsgkwrsvbzqspp") return@runCatching false
        val parts = com.syahifilms.sphere.BuildConfig.PREVIEW_ANON.split('.')
        if (parts.size != 3) return@runCatching false
        val claims = org.json.JSONObject(String(android.util.Base64.decode(parts[1],android.util.Base64.URL_SAFE or android.util.Base64.NO_WRAP),Charsets.UTF_8))
        claims.optString("role") == "anon" && claims.optString("ref") == ref
    }.getOrDefault(false)
    fun requirePreviewBackend() {
        if (!previewConfigured) throw ApiException(503,"Isolated testing backend is not configured.")
    }
    val SUPABASE_URL: String get() { requirePreviewBackend(); return com.syahifilms.sphere.BuildConfig.PREVIEW_URL }
    val SUPABASE_KEY: String get() { requirePreviewBackend(); return com.syahifilms.sphere.BuildConfig.PREVIEW_ANON }
    val GOOGLE_WEB_CLIENT_ID: String get() = com.syahifilms.sphere.BuildConfig.PREVIEW_GOOGLE
    const val WEBSITE = "https://sphere-live.onrender.com"
    const val FEE_PERCENT = 5   // default only; real value comes from Admin Panel → Settings
    const val FREE_WORKS = 3          // paid works an editor can do before verification
    const val VERIFY_FEE = 29         // ₹ verification fee
    const val FEE_PHONE = "8708712986"
    const val FEE_UPI = "8708712986-1@nyes"
    const val FEE_UPI_NAME = "NEERAJ KUMAR MEHTO"
    const val VERIFY_MSG = "You have finished 3 paid works. Get verified (✔ tick, ₹29 fee) to keep getting new work. See Profile → Verification status."
    const val WHATSAPP = "917739363798"
    val SUPPORT_PHONES = listOf("7739363798", "9468289750", "8708712986")
    val LANGUAGES = listOf(
        "Hindi", "English", "Hinglish", "Punjabi", "Haryanvi", "Bhojpuri", "Rajasthani", "Marathi",
        "Gujarati", "Bengali", "Tamil", "Telugu", "Kannada", "Malayalam", "Urdu", "Other"
    )
    val CATEGORIES = listOf(
        "Vlog Editing", "Cinematic", "Gaming Edits", "Reels & Shorts",
        "Podcast Editing", "Color Grading & VFX", "Motion Graphics", "Ads & Commercial", "AI Video Editor"
    )
}
