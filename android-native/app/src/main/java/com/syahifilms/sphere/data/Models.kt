package com.syahifilms.sphere.data

import org.json.JSONArray
import org.json.JSONObject
import java.time.LocalDate
import java.time.ZoneId

/** org.json returns "null" for JSON nulls — this returns "" instead. */
fun JSONObject.str(key: String): String = if (isNull(key)) "" else optString(key, "")
fun JSONObject.numOrNull(key: String): Double? = if (isNull(key)) null else optDouble(key).takeIf { !it.isNaN() }
fun JSONArray?.strings(): List<String> {
    if (this == null) return emptyList()
    val out = ArrayList<String>()
    for (i in 0 until length()) { val v = optString(i, ""); if (v.isNotBlank() && v != "null") out.add(v) }
    return out
}

fun todayIST(): String = LocalDate.now(ZoneId.of("Asia/Kolkata")).toString()

fun money(v: Double?): String {
    if (v == null) return "-"
    return if (v % 1.0 == 0.0) "₹" + v.toLong() else "₹" + String.format("%.2f", v)
}

/** Commission % set by the admin (Admin Panel → Settings). */
object Fees { @Volatile var percent: Double = Config.FEE_PERCENT.toDouble() }

fun feeLabel(): String = if (Fees.percent % 1.0 == 0.0) Fees.percent.toLong().toString() else Fees.percent.toString()

fun editorShare(amount: Double?): Double =
    Math.round((amount ?: 0.0) * (100 - Fees.percent)) / 100.0

/** Valid Indian mobile -> "+91XXXXXXXXXX", otherwise null (same rules as the website). */
fun cleanIndianPhone(raw: String?): String? {
    var d = (raw ?: "").filter { it.isDigit() }
    if (d.length == 12 && d.startsWith("91")) d = d.substring(2)
    if (d.length == 11 && d.startsWith("0")) d = d.substring(1)
    if (!Regex("^[6-9][0-9]{9}$").matches(d)) return null
    if (d.all { it == d[0] }) return null
    if (d in listOf("6789012345", "7890123456", "8901234567", "9012345678", "9876543210")) return null
    return "+91$d"
}

data class Profile(
    val id: String,
    val role: String,            // client | editor | admin
    val name: String,
    val email: String,
    val phone: String,
    val categories: List<String>,
    val languages: List<String>,
    val skills: List<String>,
    val experience: Int?,
    val price: String,
    val sample: String,
    val portfolio: String,
    val verified: Boolean,
    val code: String,
    val avatarPath: String,
    var rating: Double = 0.0,
    var reviews: Int = 0
) {
    val category: String get() = categories.firstOrNull() ?: ""
    val categoriesLabel: String get() = categories.joinToString(", ").ifBlank { "-" }
    val languagesLabel: String get() = languages.joinToString(", ").ifBlank { "-" }
    val avatarUrl: String get() =
        if (avatarPath.isBlank()) "" else "${Config.SUPABASE_URL}/storage/v1/object/public/sphere-media/$avatarPath"
    val firstName: String get() = name.trim().split(" ").firstOrNull()?.ifBlank { null } ?: "there"
    val priceNumber: Int get() = price.filter { it.isDigit() }.toIntOrNull() ?: 0

    companion object {
        fun from(o: JSONObject) = Profile(
            id = o.str("id"),
            role = o.str("role").lowercase(),
            name = o.str("full_name").ifBlank { "User" },
            email = o.str("email"),
            phone = o.str("phone"),
            categories = o.optJSONArray("categories").strings(),
            languages = o.optJSONArray("languages").strings(),
            skills = o.optJSONArray("skills").strings(),
            experience = if (o.isNull("experience_years")) null else o.optInt("experience_years"),
            price = o.str("price_range"),
            sample = o.str("sample_video_url"),
            portfolio = o.str("portfolio_url"),
            verified = o.optBoolean("is_verified", false),
            code = o.str("verification_code"),
            avatarPath = o.str("avatar_url")
        )
    }
}

data class Job(
    val id: String,
    val clientId: String,
    val category: String,
    val description: String,
    val budget: Double?,
    val deadline: String,
    val filesLink: String,
    val status: String,
    val assignedEditor: String,
    val proposedAmount: Double?,
    val proposedBy: String,
    val lockedAmount: Double?,
    val payment: String,
    val deliveryLink: String,
    val editorAmount: Double?,
    val payoutStatus: String,
    val language: String,
    val createdAt: String
) {
    val expired: Boolean get() = status == "open" && deadline.isNotBlank() && deadline.take(10) < todayIST()
    val finalAmount: Double? get() = lockedAmount ?: budget

    companion object {
        fun from(o: JSONObject) = Job(
            id = o.str("id"),
            clientId = o.str("client_id"),
            category = o.str("category"),
            description = o.str("description"),
            budget = o.numOrNull("budget"),
            deadline = o.str("deadline"),
            filesLink = o.str("files_link"),
            status = o.str("status"),
            assignedEditor = o.str("assigned_editor"),
            proposedAmount = o.numOrNull("proposed_amount"),
            proposedBy = o.str("proposed_by"),
            lockedAmount = o.numOrNull("locked_amount"),
            payment = o.str("payment_status"),
            deliveryLink = o.str("delivery_link"),
            editorAmount = o.numOrNull("editor_amount"),
            payoutStatus = o.str("payout_status"),
            language = o.str("language"),
            createdAt = o.str("created_at")
        )
    }
}

data class Bid(
    val id: String, val jobId: String, val editorId: String,
    val message: String, val amount: Double?, val status: String
) {
    companion object {
        fun from(o: JSONObject) = Bid(o.str("id"), o.str("job_id"), o.str("editor_id"),
            o.str("message"), o.numOrNull("bid_amount"), o.str("status"))
    }
}

data class ChatMessage(val id: String, val senderId: String, val receiverId: String, val text: String, val createdAt: String) {
    companion object {
        fun from(o: JSONObject) = ChatMessage(o.str("id"), o.str("sender_id"), o.str("receiver_id"), o.str("text"), o.str("created_at"))
    }
}

data class Notice(val id: String, val title: String, val body: String, val read: Boolean, val createdAt: String) {
    companion object {
        fun from(o: JSONObject) = Notice(o.str("id"), o.str("title"), o.str("body"), o.optBoolean("is_read", false), o.str("created_at"))
    }
}

fun <T> JSONArray.mapObjects(f: (JSONObject) -> T): List<T> {
    val out = ArrayList<T>(length())
    for (i in 0 until length()) out.add(f(getJSONObject(i)))
    return out
}
