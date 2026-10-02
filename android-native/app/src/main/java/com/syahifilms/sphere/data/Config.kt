package com.syahifilms.sphere.data

/** Public settings (same as the website). Secret keys are NEVER stored in the app. */
object Config {
    // All traffic goes through Sphere's Cloudflare proxy (works even where ISPs block *.supabase.co)
    const val SUPABASE_URL = "https://sphere-api.niteshkumarmatho37.workers.dev"
    const val SUPABASE_KEY = "sb_publishable_M8dweSjU8gW45msJ_Gt4Lw_eAm3RALW"
    const val GOOGLE_WEB_CLIENT_ID = "258192736968-ocmgvgkm00t0sglunn6tqgodpf6d4ak2.apps.googleusercontent.com"
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
        "Podcast Editing", "Color Grading & VFX", "Motion Graphics", "Ads & Commercial"
    )
}
