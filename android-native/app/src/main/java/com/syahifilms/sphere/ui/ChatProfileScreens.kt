@file:OptIn(ExperimentalMaterial3Api::class)

package com.syahifilms.sphere.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
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

@Composable
fun ChatsScreen(nav: NavHostController) {
    val data = load(Unit) {
        val convs = Repo.conversations()
        convs to Repo.profilesByIds(convs.map { it.otherId })
    }
    Page("Messages", bottomBar = { MainBottomBar(nav, "chats") }) {
        SupportCard()
        val d = data.data
        when {
            data.error != null -> ErrorBox(data.error) { data.reload() }
            d == null -> Loading()
            d.first.isEmpty() -> MutedText("No conversations yet. Open an editor's profile or a project to start chatting.")
            else -> d.first.forEach { c ->
                val p = d.second[c.otherId]
                CardBox(onClick = { nav.go("chat/${c.otherId}") }) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Avatar(p?.avatarUrl ?: "", p?.name ?: "User", 44.dp)
                        Spacer(Modifier.width(10.dp))
                        Column(Modifier.weight(1f)) {
                            Text(p?.name ?: "User", fontWeight = FontWeight.Bold)
                            Text(c.last.text, color = Muted, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun ChatScreen(nav: NavHostController, otherId: String) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val me = AppState.me ?: return
    var other by remember { mutableStateOf<Profile?>(null) }
    var messages by remember { mutableStateOf<List<ChatMessage>>(emptyList()) }
    var text by remember { mutableStateOf("") }
    var sending by remember { mutableStateOf(false) }
    val listState = rememberLazyListState()

    LaunchedEffect(otherId) {
        try { other = Repo.profile(otherId) } catch (e: Exception) { }
        while (true) {                       // refresh every 4 seconds while this screen is open
            try { messages = Repo.thread(otherId) } catch (e: Exception) { }
            delay(4000)
        }
    }
    LaunchedEffect(messages.size) { if (messages.isNotEmpty()) listState.animateScrollToItem(messages.size - 1) }

    Scaffold(
        containerColor = Bg,
        topBar = { SphereTopBar(other?.name ?: "Chat", onBack = { nav.popBackStack() }) },
        bottomBar = {
            Row(
                Modifier.fillMaxWidth().background(Color.White).navigationBarsPadding().imePadding().padding(8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                OutlinedTextField(
                    value = text, onValueChange = { text = it.take(2000) },
                    placeholder = { Text("Type a message…") },
                    modifier = Modifier.weight(1f), shape = RoundedCornerShape(24.dp), maxLines = 4
                )
                IconButton(enabled = !sending && text.isNotBlank(), onClick = {
                    val t = text.trim()
                    scope.launch {
                        sending = true
                        try { Repo.sendMessage(me, otherId, t); text = ""; messages = Repo.thread(otherId) }
                        catch (e: Exception) { toast(ctx, e.message ?: "Message not sent") }
                        sending = false
                    }
                }) { Icon(Icons.AutoMirrored.Filled.Send, "Send", tint = Blue) }
            }
        }
    ) { pad ->
        LazyColumn(
            state = listState,
            modifier = Modifier.padding(pad).fillMaxSize().padding(horizontal = 12.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
            contentPadding = PaddingValues(vertical = 10.dp)
        ) {
            items(messages, key = { it.id }) { m ->
                val mine = m.senderId == me.id
                Box(Modifier.fillMaxWidth(), contentAlignment = if (mine) Alignment.CenterEnd else Alignment.CenterStart) {
                    Text(
                        m.text,
                        color = if (mine) Color.White else Color.Black,
                        modifier = Modifier.widthIn(max = 290.dp)
                            .clip(RoundedCornerShape(16.dp))
                            .background(if (mine) Blue else Color.White)
                            .padding(horizontal = 12.dp, vertical = 8.dp)
                    )
                }
            }
        }
    }
}

@Composable
fun NotificationsScreen(nav: NavHostController) {
    val data = load(Unit) { Repo.notifications() }
    Page("Notifications", onBack = { nav.popBackStack() }) {
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
    Page("Profile", bottomBar = { MainBottomBar(nav, "profile") }) {
        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
            Avatar(me.avatarUrl, me.name, 84.dp)
            Spacer(Modifier.height(8.dp))
            Text(me.name, fontSize = 20.sp, fontWeight = FontWeight.ExtraBold)
            MutedText(me.email)
            MutedText(me.phone)
            if (me.role == "editor") {
                Text(
                    if (AppState.editorSide) "Editor mode" else "Client mode",
                    color = Blue, fontWeight = FontWeight.Bold, fontSize = 12.sp,
                    modifier = Modifier.padding(top = 6.dp).clip(RoundedCornerShape(12.dp)).background(BlueSoft).padding(horizontal = 10.dp, vertical = 4.dp)
                )
                if (me.verified) MutedText("✔ ${me.code} · ${me.category}", 12)
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
            "admin" -> MenuRow("🛡️", "Admin Panel (website)", "Verify editors, reports, payouts") { openUrl(ctx, Config.WEBSITE) }
        }
        MenuRow("🚪", "Logout", color = Danger) { confirmLogout = true }
    }
    if (confirmLogout) AlertDialog(
        onDismissRequest = { confirmLogout = false },
        title = { Text("Log out?") },
        confirmButton = { TextButton(onClick = { confirmLogout = false; scope.launch { Api.signOut(); AppState.me = null; nav.resetTo("welcome") } }) { Text("Log out") } },
        dismissButton = { TextButton(onClick = { confirmLogout = false }) { Text("Cancel") } }
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
fun ReportScreen(nav: NavHostController, jobId: String?) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val reasons = if (AppState.editorSide)
        listOf("Client is not releasing payment", "Client is not responding", "Client is asking for extra work", "Bad behaviour", "Something else")
    else listOf("Editor did not deliver", "Video quality is not good", "Editor is not responding", "Bad behaviour", "Something else")
    var reason by remember { mutableStateOf(reasons.first()) }
    var details by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    Page("Report a problem", onBack = { nav.popBackStack() }) {
        Dropdown("What is the problem?", reason, reasons) { reason = it }
        Field(details, { details = it.take(2000) }, "Describe the issue", "What happened, since when, and what you need…", minLines = 5)
        PrimaryButton(if (busy) "Sending…" else "Submit report", enabled = !busy) {
            if (details.trim().length < 10) { toast(ctx, "Please add a few more details"); return@PrimaryButton }
            scope.launch {
                busy = true
                try { Repo.report(jobId, reason, details.trim()); toast(ctx, "Report submitted ✅ The Sphere team will contact you soon."); nav.popBackStack() }
                catch (e: Exception) { toast(ctx, e.message ?: "Could not send the report") }
                busy = false
            }
        }
        MutedText("Urgent? Call ${Config.SUPPORT_PHONES.joinToString(" / ")}", 12)
    }
}
