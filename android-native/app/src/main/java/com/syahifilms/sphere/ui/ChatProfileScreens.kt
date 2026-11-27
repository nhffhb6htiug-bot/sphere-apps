@file:OptIn(ExperimentalMaterial3Api::class)

package com.syahifilms.sphere.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavHostController
import com.syahifilms.sphere.data.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

internal fun timeOf(iso: String): String = try {
    val t = java.time.OffsetDateTime.parse(iso).atZoneSameInstant(java.time.ZoneId.of("Asia/Kolkata"))
    val h = t.hour % 12; "${if (h == 0) 12 else h}:${t.minute.toString().padStart(2, '0')} ${if (t.hour < 12) "am" else "pm"}"
} catch (e: Exception) { "" }

internal fun dayOf(iso: String): String = try {
    val d = java.time.OffsetDateTime.parse(iso).atZoneSameInstant(java.time.ZoneId.of("Asia/Kolkata")).toLocalDate()
    val today = java.time.LocalDate.now(java.time.ZoneId.of("Asia/Kolkata"))
    when (d) { today -> "Today"; today.minusDays(1) -> "Yesterday"; else -> prettyDate(d.toString()) }
} catch (e: Exception) { "" }

internal fun roleLine(p: Profile?): String = when {
    p == null -> ""
    p.role == "admin" -> "Sphere team"
    p.role == "editor" -> if (p.verified) "Editor · ✔ ${p.code}" else "Editor"
    else -> "Client"
}

@Composable
internal fun Ticks(m: ChatMessage, onDark: Boolean) {
    val (t, c) = when {
        m.readAt.isNotBlank() -> "✓✓" to Color(0xFF7EE3FF)
        m.deliveredAt.isNotBlank() -> "✓✓" to (if (onDark) Color.White.copy(alpha = 0.75f) else Muted)
        else -> "✓" to (if (onDark) Color.White.copy(alpha = 0.75f) else Muted)
    }
    Text(t, color = c, fontSize = 11.sp, fontWeight = FontWeight.Bold, letterSpacing = (-2).sp, modifier = Modifier.padding(start = 3.dp))
}

@Composable
fun ChatsScreen(nav: NavHostController) {
    val data = load(Unit) {
        val convs = Repo.conversations()
        Repo.markDelivered()
        Triple(convs, Repo.profilesByIds(convs.map { it.otherId }), Repo.unreadByUser())
    }
    val meId = AppState.me?.id ?: ""
    var search by remember { mutableStateOf("") }
    LaunchedEffect(meId) {
        while (true) { delay(10000); data.reload() }
    }
    Page("Messages", bottomBar = { MainBottomBar(nav, "chats") }) {
        Field(search, { search = it.take(100) }, "Search conversations")
        SupportCard()
        val d = data.data
        when {
            data.error != null -> ErrorBox(data.error) { data.reload() }
            d == null -> Loading()
            d.first.isEmpty() -> MutedText("No conversations yet. Open an editor's profile or a project to start chatting.")
            else -> d.first.filter { c -> search.isBlank() ||
                d.second[c.otherId]?.name.orEmpty().contains(search, true) || c.last.preview.contains(search, true)
            }.forEach { c ->
                val p = d.second[c.otherId]
                val unread = d.third[c.otherId] ?: 0
                CardBox(onClick = { nav.go("chat/${c.otherId}") }) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Avatar(p?.avatarUrl ?: "", p?.name ?: "User", 46.dp)
                        Spacer(Modifier.width(10.dp))
                        Column(Modifier.weight(1f)) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(p?.name ?: "User", fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                                Text(timeOf(c.last.createdAt), fontSize = 11.sp, color = if (unread > 0) Color(0xFF25D366) else Muted)
                            }
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                if (c.last.senderId == meId) Ticks(c.last, false)
                                Text(c.last.preview, color = Muted, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis,
                                    modifier = Modifier.weight(1f).padding(start = 4.dp))
                                if (unread > 0) Text("$unread", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold,
                                    modifier = Modifier.clip(RoundedCornerShape(10.dp)).background(Color(0xFF25D366)).padding(horizontal = 7.dp, vertical = 2.dp))
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun NotificationsScreen(nav: NavHostController) {
    val data = load(Unit) { Repo.notifications() }
    Page("Notifications", onBack = { nav.popBackStack() }) {
        NativePushSettings()
        val list = data.data
        when {
            data.error != null -> ErrorBox(data.error) { data.reload() }
            list == null -> Loading()
            list.isEmpty() -> MutedText("No notifications yet.")
            else -> list.forEach { n ->
                CardBox {
                    Row {
                        Text(if (n.read) "🔔" else "🔴", modifier = Modifier.padding(end = 10.dp))
                        Column {
                            Text(n.title, fontWeight = FontWeight.Bold)
                            Text(n.body, color = Muted, fontSize = 13.sp)
                            Text(prettyDate(n.createdAt), color = Muted, fontSize = 11.sp)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun MenuRow(emoji: String, title: String, sub: String = "", color: Color = Color.Black, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().padding(vertical = 5.dp).clip(RoundedCornerShape(16.dp)).background(Color.White)
            .clickable { onClick() }.padding(14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(emoji, fontSize = 20.sp, modifier = Modifier.padding(end = 12.dp))
        Column(Modifier.weight(1f)) {
            Text(title, fontWeight = FontWeight.SemiBold, color = color)
            if (sub.isNotBlank()) Text(sub, color = Muted, fontSize = 12.sp)
        }
        Text("›", fontSize = 22.sp, color = Muted)
    }
}

@Composable
fun ProfileScreen(nav: NavHostController) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val me = AppState.me ?: return
    var confirmLogout by remember { mutableStateOf(false) }
    var confirmEditor by remember { mutableStateOf(false) }
    var editName by remember { mutableStateOf(false) }
    var newName by remember { mutableStateOf(me.name) }
    Page("Profile", bottomBar = { MainBottomBar(nav, "profile") }) {
        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
            Avatar(me.avatarUrl, me.name, 84.dp)
            Spacer(Modifier.height(8.dp))
            Text(me.name, fontSize = 20.sp, fontWeight = FontWeight.ExtraBold)
            TextButton(onClick = { editName = true }) { Text("✏️ Edit name") }
            MutedText(me.email)
            MutedText(me.phone)
            if (me.role == "editor" || me.role == "admin") {
                Text(
                    if (AppState.editorSide) "Editor mode" else if (me.role == "admin") "Admin mode" else "Client mode",
                    color = Blue, fontWeight = FontWeight.Bold, fontSize = 12.sp,
                    modifier = Modifier.padding(top = 6.dp).clip(RoundedCornerShape(12.dp)).background(BlueSoft).padding(horizontal = 10.dp, vertical = 4.dp)
                )
                if (me.verified) MutedText("✔ ${me.code} · ${me.categoriesLabel}", 12)
            }
        }
        Spacer(Modifier.height(10.dp))
        if (me.role == "editor" && !me.verified) MenuRow("⏳", "Verification status", "Our team will call you to verify") { nav.go("verification") }
        if (me.role == "editor") MenuRow("✏️", "Edit editor details") { nav.go("editorDetails") }
        MenuRow("📁", "My projects") { nav.go("jobs") }
        MenuRow("🔔", "Notifications") { nav.go("notifications") }
        MenuRow("🆘", "Help, Support & Policies") { nav.go("support") }
        when (me.role) {
            "editor" -> if (AppState.editorSide)
                MenuRow("🔄", "Switch to Client", "Hire editors and post jobs", Blue) { AppState.switchMode(true); nav.resetTo("home") }
            else
                MenuRow("🔄", "Switch to Editor", "Find work and place bids", Blue) { AppState.switchMode(false); nav.resetTo("home") }
            "client" -> MenuRow("⭐", "Become an Editor", "Earn by editing videos on Sphere", Blue) { confirmEditor = true }
            "admin" -> {
                if (AppState.editorSide) {
                    MenuRow("✏️", "Editor details", "Your categories and languages") { nav.go("editorDetails") }
                    MenuRow("🔄", "Switch to Admin mode", "Back to hiring and the Admin Panel", Blue) { AppState.switchMode(true); nav.resetTo("home") }
                } else {
                    MenuRow("🔄", "Switch to Editor", "See available work and place bids", Blue) { AppState.switchMode(false); nav.resetTo("home") }
                }
                MenuRow("🛡️", "Admin Panel (website)", "Verify editors, reports, payouts") { openUrl(ctx, Config.WEBSITE) }
            }
        }
        MenuRow("🚪", "Logout", color = Danger) { confirmLogout = true }
    }
    if (confirmLogout) AlertDialog(
        onDismissRequest = { confirmLogout = false },
        title = { Text("Log out?") },
        confirmButton = { TextButton(onClick = { confirmLogout = false; scope.launch { Api.signOut(); AppState.me = null; nav.resetTo("welcome") } }) { Text("Log out") } },
        dismissButton = { TextButton(onClick = { confirmLogout = false }) { Text("Cancel") } }
    )
    if (editName) AlertDialog(
        onDismissRequest = { editName = false },
        title = { Text("Your name") },
        text = { OutlinedTextField(value = newName, onValueChange = { newName = it.take(60) }, singleLine = true) },
        confirmButton = {
            TextButton(onClick = {
                val n = newName.trim()
                if (n.length < 2) { toast(ctx, "Name must be at least 2 characters"); return@TextButton }
                editName = false
                scope.launch {
                    try { Repo.updateName(n); AppState.refreshMe(); toast(ctx, "Name updated ✅") }
                    catch (e: Exception) { toast(ctx, e.message ?: "Could not update") }
                }
            }) { Text("Save") }
        },
        dismissButton = { TextButton(onClick = { editName = false }) { Text("Cancel") } }
    )
    if (confirmEditor) AlertDialog(
        onDismissRequest = { confirmEditor = false },
        title = { Text("Become an Editor?") },
        text = { Text("You will stay a Client too — switch anytime from Profile.") },
        confirmButton = {
            TextButton(onClick = {
                confirmEditor = false
                scope.launch {
                    try { Repo.becomeEditor(); AppState.refreshMe(); AppState.switchMode(false); nav.go("editorDetails") }
                    catch (e: Exception) { toast(ctx, e.message ?: "Could not update") }
                }
            }) { Text("Yes") }
        },
        dismissButton = { TextButton(onClick = { confirmEditor = false }) { Text("Cancel") } }
    )
}

private val FAQ = listOf(
    "How does payment work?" to "The client pays inside Sphere. The money stays in escrow until the editor delivers and the client approves. After approval, the editor gets paid.",
    "What is a verified editor?" to "The Sphere team checks every editor on a call and reviews their sample work. Approved editors get a code like SF-EDT-1234 and a ✔ badge.",
    "How do I choose an editor?" to "Post a job — verified editors in that category send bids. Compare profiles and prices, then select one. Or tap Hire on any editor profile.",
    "How do I send raw footage?" to "Add a Google Drive / WeTransfer link when posting the job.",
    "How do I become an editor?" to "Tap “Become an Editor” in Profile, fill in your details and sample link. Our team will call you to verify."
)

@Composable
fun SupportScreen(nav: NavHostController) {
    val ctx = LocalContext.current
    Page("Help & Support", onBack = { nav.popBackStack() }) {
        SupportCard()
        MenuRow("🚩", "Report a problem") { nav.go("report") }
        SectionTitle("Frequently asked questions")
        FAQ.forEach { (q, a) ->
            var open by remember { mutableStateOf(false) }
            CardBox(onClick = { open = !open }) {
                Text(q, fontWeight = FontWeight.Bold)
                if (open) Text(a, color = Muted, fontSize = 13.sp, modifier = Modifier.padding(top = 6.dp))
            }
        }
        SectionTitle("Policies")
        MenuRow("📄", "Terms & Conditions") { openUrl(ctx, Config.WEBSITE + "/terms.html") }
        MenuRow("🔒", "Privacy Policy") { openUrl(ctx, Config.WEBSITE + "/privacy.html") }
        MenuRow("💸", "Refund Policy") { openUrl(ctx, Config.WEBSITE + "/refund.html") }
        MenuRow("📍", "Contact Us") { openUrl(ctx, Config.WEBSITE + "/contact.html") }
    }
}

@Composable
fun ReportScreen(nav: NavHostController, jobId: String?, reportedUserId: String? = null) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val reasons = if (AppState.editorSide)
        listOf("Client is not releasing payment", "Client is not responding", "Client is asking for extra work", "Bad behaviour", "Something else")
    else listOf("Editor did not deliver", "Video quality is not good", "Editor is not responding", "Bad behaviour", "Something else")
    var reason by remember { mutableStateOf(reasons.first()) }
    var details by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    Page(if (reportedUserId.isNullOrBlank()) "Report a problem" else "Report user", onBack = { nav.popBackStack() }) {
        Dropdown("What is the problem?", reason, reasons) { reason = it }
        Field(details, { details = it.take(2000) }, "Describe the issue", "What happened, since when, and what you need…", minLines = 5)
        PrimaryButton(if (busy) "Sending…" else "Submit report", enabled = !busy) {
            if (details.trim().length < 10) { toast(ctx, "Please add a few more details"); return@PrimaryButton }
            scope.launch {
                busy = true
                try { Repo.report(jobId, reason, details.trim(), reportedUserId); toast(ctx, "Report submitted ✅ The Sphere team will contact you soon."); nav.popBackStack() }
                catch (e: Exception) { toast(ctx, e.message ?: "Could not send the report") }
                busy = false
            }
        }
        MutedText("Urgent? Call ${Config.SUPPORT_PHONES.joinToString(" / ")}", 12)
    }
}
