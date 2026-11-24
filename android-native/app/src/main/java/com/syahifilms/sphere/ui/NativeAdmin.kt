package com.syahifilms.sphere.ui

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.navigation.NavHostController
import com.syahifilms.sphere.data.*
import org.json.JSONObject
import org.json.JSONArray

private fun adminProfilesState(p: JSONObject?, videos: Set<String>): String {
    if (p == null) return "Unknown"
    val bio = p.str("bio").isNotBlank()
    val skills = p.optJSONArray("skills")?.strings()?.any { it.isNotBlank() } ?: p.str("skills").takeUnless { it == "[]" }.orEmpty().isNotBlank()
    val portfolio = p.str("portfolio_url").isNotBlank() || p.str("sample_video_url").isNotBlank() || p.str("id") in videos
    return if (bio && skills && portfolio) "Complete" else if (bio || skills || portfolio) "Partial" else "Incomplete"
}

/** Read-only native dashboard. Existing server RPCs enforce admin authorization. No privileged changes are performed here. */
@Composable
fun NativeAdminScreen(nav: NavHostController) {
    val me = AppState.me
    if (me?.role != "admin") {
        Page("Access denied", onBack = { nav.popBackStack() }) { MutedText("This page is for admins only.") }
        return
    }
    var tab by remember(me.id) { mutableStateOf("Overview") }
    var role by remember { mutableStateOf("Everyone") }
    var query by remember { mutableStateOf("") }
    var search by remember { mutableStateOf("") }
    var completeness by remember { mutableStateOf("All") }
    var verification by remember { mutableStateOf("All") }
    var queue by remember { mutableStateOf("New") }
    Page("Admin Panel", onBack = { nav.popBackStack() }) {
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            listOf("Overview", "Users", "Verification").forEach { t -> FilterChip(selected = tab == t, onClick = { tab = t }, label = { Text(t) }) }
        }
        MutedText("Read-only native dashboard. Admin changes still require the authorized web workflow and PIN.", 12)
        if (tab == "Overview" || tab == "Users") {
            val stats = load(me.id) { JSONObject(Api.rpc("sp_admin_overview", JSONObject())) }
            when {
                stats.error != null -> ErrorBox(stats.error) { stats.reload() }
                stats.data == null -> Loading()
                else -> {
                    val ov = stats.data!!
                    CardBox {
                        listOf("users" to "Total users", "clients" to "Clients", "editors" to "Editors", "verified_editors" to "Verified editors",
                            "active_projects" to "Active projects", "completed" to "Completed projects", "pending_payments" to "Waiting for payment",
                            "pending_refunds" to "Refunds in progress").forEach { (key, label) -> KeyValue(label, ov.str(key).ifBlank { "Unavailable" }) }
                    }
                }
            }
        }
        if (tab == "Users") {
            Dropdown("Role", role, listOf("Everyone", "Clients", "Editors", "Admins")) { role = it; completeness = "All"; verification = "All" }
            Field(query, { query = it.take(100) }, "Search users", "Name, email or phone")
            PrimaryButton("Search") { search = query.trim() }
            val rows = load(me.id, role, search) {
                val roleKey = when(role) { "Clients" -> "CLIENT"; "Editors" -> "EDITOR"; "Admins" -> "ADMIN"; else -> "all" }
                val list = JSONArray(Api.rpc("sp_admin_users", JSONObject().put("p_search", search.ifBlank { null } ?: JSONObject.NULL).put("p_role", roleKey).put("p_limit", 200))).mapObjects { it }
                if (role != "Editors") Triple(list, emptyMap<String,JSONObject>(), emptySet<String>())
                else {
                    val profiles = JSONArray(Api.rpc("sp_admin_profiles", JSONObject().put("p_role", "EDITOR").put("p_verified", JSONObject.NULL))).mapObjects { it }.associateBy { it.str("id") }
                    val videos = Api.select("sp_portfolio?select=editor_id,video_url&video_url=not.is.null&limit=2000").mapObjects { it }.filter { it.str("video_url").isNotBlank() }.map { it.str("editor_id") }.toSet()
                    Triple(list, profiles, videos)
                }
            }
            if (role == "Editors") {
                Dropdown("Profile completeness", completeness, listOf("All", "Complete", "Partial", "Incomplete")) { completeness = it }
                Dropdown("Verification", verification, listOf("All", "Verified", "Unverified")) { verification = it }
            }
            val data = rows.data
            when {
                rows.error != null -> ErrorBox(rows.error) { rows.reload() }
                data == null -> Loading()
                else -> {
                    val filtered = data.first.filter { u ->
                        val profile = data.second[u.str("id")]
                        val state = adminProfilesState(profile, data.third)
                        val verified = profile?.optBoolean("is_verified", false) ?: u.optBoolean("verified", false)
                        (role != "Editors" || completeness == "All" || state == completeness) &&
                            (role != "Editors" || verification == "All" || verified == (verification == "Verified"))
                    }
                    MutedText("Showing ${filtered.size} of ${data.first.size} loaded users (limit 200)")
                    if (filtered.isEmpty()) MutedText("No matching users")
                    filtered.forEach { u -> CardBox {
                        Text(u.str("name").ifBlank { "User" }, fontWeight = FontWeight.Bold)
                        MutedText(u.str("role") + if (u.optBoolean("verified", false)) " · Verified" else "")
                        if (role == "Editors") KeyValue("Profile", adminProfilesState(data.second[u.str("id")], data.third))
                        KeyValue("Projects", u.str("projects").ifBlank { "—" })
                    } }
                }
            }
        }
        if (tab == "Verification") {
            val queues = load(me.id) {
                val list = JSONArray(Api.rpc("sp_admin_verifications", JSONObject())).mapObjects { it }
                val outreach = JSONArray(Api.rpc("sp_admin_editor_outreach_list", JSONObject())).mapObjects { it.str("id") }.toSet()
                val verified = JSONArray(Api.rpc("sp_admin_profiles", JSONObject().put("p_role", "EDITOR").put("p_verified", true))).mapObjects { it }
                Triple(list, outreach, verified)
            }
            val data = queues.data
            when {
                queues.error != null -> ErrorBox(queues.error) { queues.reload() }
                data == null -> Loading()
                else -> {
                    val items = data.first
                    val tabs = linkedMapOf(
                        "New" to items.filter { it.str("status") != "rejected" && it.str("id") !in data.second },
                        "Messaged" to items.filter { it.str("status") != "rejected" && it.str("id") in data.second },
                        "Paid" to items.filter { it.str("status") != "rejected" && it.str("fee_status") == "confirmed" },
                        "Promo video" to items.filter { it.str("status") != "rejected" && it.str("id") !in data.second && it.str("proof_video").isNotBlank() },
                        "Rejected" to items.filter { it.str("status") == "rejected" },
                        "Verified" to data.third)
                    Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        tabs.forEach { (key, value) -> FilterChip(selected = queue == key, onClick = { queue = key }, label = { Text("$key (${value.size})") }) }
                    }
                    MutedText("Confirmed fee does not mean verification is approved.", 12)
                    val shown = tabs[queue].orEmpty()
                    if (shown.isEmpty()) MutedText("No editors in this queue")
                    shown.forEach { u -> CardBox {
                        Text(u.str("name").ifBlank { u.str("full_name").ifBlank { "Editor" } }, fontWeight = FontWeight.Bold)
                        if (queue != "Verified") { KeyValue("Status", u.str("status")); KeyValue("Fee", u.str("fee_status")) }
                        else MutedText("Verified editor")
                    } }
                }
            }
        }
    }
}
