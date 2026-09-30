@file:OptIn(ExperimentalMaterial3Api::class)

package com.syahifilms.sphere.ui

import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.Notifications
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
import kotlinx.coroutines.launch

@Composable
fun BellAction(nav: NavHostController) {
    val unread = load(Unit) { Repo.unreadCount() }
    IconButton(onClick = { nav.go("notifications") }) {
        BadgedBox(badge = { if ((unread.data ?: 0) > 0) Badge { Text("${unread.data}") } }) {
            Icon(Icons.Filled.Notifications, "Notifications")
        }
    }
}

@Composable
fun HomeScreen(nav: NavHostController) {
    val me = AppState.me
    if (me == null) { LaunchedEffect(Unit) { nav.resetTo("splash") }; return }
    Page("Sphere", bottomBar = { MainBottomBar(nav, "home") }, actions = { BellAction(nav) }) {
        if (AppState.editorSide) EditorHome(nav, me) else ClientHome(nav, me)
    }
}

@Composable
private fun QuickAction(label: String, emoji: String, modifier: Modifier, onClick: () -> Unit) {
    Column(
        modifier.clip(RoundedCornerShape(16.dp)).background(Color.White).clickable { onClick() }.padding(14.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(emoji, fontSize = 26.sp)
        Spacer(Modifier.height(4.dp))
        Text(label, fontWeight = FontWeight.SemiBold, fontSize = 13.sp)
    }
}

@Composable
private fun ClientHome(nav: NavHostController, me: Profile) {
    val ctx = LocalContext.current
    Text("Hi, ${me.firstName} 👋", fontSize = 22.sp, fontWeight = FontWeight.ExtraBold)
    MutedText("Find the right verified editor for your video")
    if (me.role == "admin") {
        CardBox(onClick = { openUrl(ctx, Config.WEBSITE) }, border = Orange) {
            Text("🛡️ Admin panel", fontWeight = FontWeight.Bold)
            MutedText("Verify editors, reports and payouts on the website (Profile → Admin Panel).", 12)
        }
    }
    Spacer(Modifier.height(10.dp))
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        QuickAction("Post a Job", "📝", Modifier.weight(1f)) { nav.go("postJob") }
        QuickAction("All Editors", "🎬", Modifier.weight(1f)) { nav.go("editors") }
    }
    Spacer(Modifier.height(10.dp))
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        QuickAction("My Projects", "📁", Modifier.weight(1f)) { nav.go("jobs") }
        QuickAction("Messages", "💬", Modifier.weight(1f)) { nav.go("chats") }
    }
    SectionTitle("Categories")
    Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Config.CATEGORIES.forEach { c ->
            SuggestionChip(onClick = { nav.go("editors?cat=" + Uri.encode(c)) }, label = { Text(c) })
        }
    }
    SectionTitle("Top verified editors")
    val eds = load(Unit) { Repo.verifiedEditors().sortedByDescending { it.rating * 10 + it.reviews } }
    when {
        eds.error != null -> ErrorBox(eds.error) { eds.reload() }
        eds.data == null -> Loading()
        eds.data.isEmpty() -> MutedText("No verified editors yet.")
        else -> Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            eds.data.take(10).forEach { e ->
                Column(
                    Modifier.width(130.dp).clip(RoundedCornerShape(16.dp)).background(Color.White)
                        .clickable { nav.go("editor/${e.id}") }.padding(12.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Avatar(e.avatarUrl, e.name, 56.dp)
                    Spacer(Modifier.height(6.dp))
                    Text(e.name, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    MutedText(e.categoriesLabel, 11)
                    Text(if (e.reviews > 0) "⭐ ${e.rating}" else "New", fontSize = 12.sp)
                    if (e.price.isNotBlank()) Text("₹${e.price}", fontWeight = FontWeight.Bold, color = Blue, fontSize = 13.sp)
                }
            }
        }
    }
    Spacer(Modifier.height(8.dp))
    SupportCard()
}

@Composable
private fun EditorHome(nav: NavHostController, me: Profile) {
    Text("Hi, ${me.firstName} 👋", fontSize = 22.sp, fontWeight = FontWeight.ExtraBold)
    if (me.role == "admin") CardBox(onClick = { nav.go("profile") }, border = Blue) {
        Text("🛡️ Admin · Editor mode", fontWeight = FontWeight.Bold)
        MutedText("You can bid on work. Switch back from Profile.", 12)
    } else CardBox(onClick = { nav.go("verification") }, border = if (me.verified) Success else Blue) {
        if (me.verified) {
            Text("✅ Verified editor", fontWeight = FontWeight.Bold)
            MutedText("Editor code: ${me.code} · ${me.categoriesLabel}", 12)
        } else {
            Text("⏳ Verification pending", fontWeight = FontWeight.Bold)
            MutedText("Our team will call you on ${me.phone.ifBlank { "your number" }} · View status", 12)
        }
    }
    SectionTitle("Available work")
    val open = load(Unit) { Repo.openJobs() }
    when {
        open.error != null -> ErrorBox(open.error) { open.reload() }
        open.data == null -> Loading()
        else -> WorkList(me, open.data) { j -> nav.go("project/${j.id}") }
    }
    if (!me.verified && me.role != "admin") MutedText("You can bid once the Sphere team verifies your profile.", 12)
    SectionTitle("Your projects")
    val mine = load(Unit) { Repo.myEditorJobs().filter { it.status !in listOf("closed", "refunded") } }
    when {
        mine.error != null -> ErrorBox(mine.error) { mine.reload() }
        mine.data == null -> Loading()
        mine.data.isEmpty() -> MutedText("No active projects yet.")
        else -> mine.data.forEach { j -> JobCard(j) { nav.go("project/${j.id}") } }
    }
    SupportCard()
}

@Composable
fun JobCard(j: Job, onClick: () -> Unit) = JobCardUi(j, onClick)

@Composable
fun JobCardUi(j: Job, onClick: () -> Unit) {
    CardBox(onClick = onClick) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(j.category, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
            StatusChip(j.status, j.expired)
        }
        if (j.language.isNotBlank()) MutedText("🗣 ${j.language}", 12)
        Text(j.description, color = Muted, fontSize = 13.sp, maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(vertical = 4.dp))
        Text(
            "Budget ${money(j.finalAmount)}" + (if (j.deadline.isNotBlank()) " • Due ${prettyDate(j.deadline)}" else ""),
            fontSize = 13.sp, fontWeight = FontWeight.SemiBold
        )
    }
}

@Composable
fun EditorCard(e: Profile, onClick: () -> Unit) {
    CardBox(onClick = onClick) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Avatar(e.avatarUrl, e.name, 52.dp)
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(e.name, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                    Spacer(Modifier.width(6.dp))
                    if (e.verified) VerifiedBadge(e.code)
                }
                MutedText("${e.categoriesLabel} · ${e.experience ?: 0} yrs exp", 12)
                Text(if (e.reviews > 0) "⭐ ${e.rating} (${e.reviews})" else "New editor", fontSize = 12.sp)
            }
            if (e.price.isNotBlank()) Text("₹${e.price}", color = Blue, fontWeight = FontWeight.Bold)
        }
    }
}

@Composable
fun EditorsScreen(nav: NavHostController, initialCategory: String?) {
    var cat by remember { mutableStateOf(initialCategory ?: "") }
    Page("Verified editors", onBack = { nav.popBackStack() }) {
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FilterChip(selected = cat.isBlank(), onClick = { cat = "" }, label = { Text("All") })
            Config.CATEGORIES.forEach { c -> FilterChip(selected = cat == c, onClick = { cat = c }, label = { Text(c) }) }
        }
        Spacer(Modifier.height(6.dp))
        val eds = load(cat) { Repo.verifiedEditors(cat.ifBlank { null }) }
        when {
            eds.error != null -> ErrorBox(eds.error) { eds.reload() }
            eds.data == null -> Loading()
            eds.data.isEmpty() -> MutedText("No verified editors in this category yet. Post a job — new editors will apply.")
            else -> eds.data.forEach { e -> EditorCard(e) { nav.go("editor/${e.id}") } }
        }
    }
}

@Composable
fun EditorProfileScreen(nav: NavHostController, id: String) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val ed = load(id) { Repo.profile(id) }
    var saved by remember { mutableStateOf(false) }
    LaunchedEffect(id) { try { saved = Repo.isSaved(id) } catch (e: Exception) { } }
    Page("Editor", onBack = { nav.popBackStack() }, actions = {
        if (AppState.clientSide) IconButton(onClick = {
            scope.launch {
                try { Repo.setSaved(id, !saved); saved = !saved } catch (e: Exception) { toast(ctx, e.message ?: "Could not save") }
            }
        }) { Icon(if (saved) Icons.Filled.Favorite else Icons.Filled.FavoriteBorder, "Save", tint = if (saved) Danger else Muted) }
    }) {
        val e = ed.data
        when {
            ed.error != null -> ErrorBox(ed.error) { ed.reload() }
            e == null -> Loading()
            else -> {
                Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                    Avatar(e.avatarUrl, e.name, 88.dp)
                    Spacer(Modifier.height(8.dp))
                    Text(e.name, fontSize = 22.sp, fontWeight = FontWeight.ExtraBold)
                    if (e.verified) VerifiedBadge(e.code)
                    MutedText("${e.categoriesLabel} · ${e.experience ?: 0} years experience")
                    MutedText("🗣 ${e.languagesLabel}", 12)
                    Text(if (e.reviews > 0) "⭐ ${e.rating} · ${e.reviews} reviews" else "New editor — no reviews yet", fontSize = 13.sp)
                }
                CardBox {
                    KeyValue("Starting price", if (e.price.isBlank()) "-" else "₹${e.price} / video")
                    KeyValue("Skills", e.skills.joinToString(", ").ifBlank { "-" })
                    if (e.sample.startsWith("http")) TextButton(onClick = { openUrl(ctx, e.sample) }) { Text("▶ Watch sample video") }
                    if (e.portfolio.startsWith("http")) TextButton(onClick = { openUrl(ctx, e.portfolio) }) { Text("📂 Open portfolio") }
                }
                if (AppState.clientSide && e.id != AppState.me?.id) {
                    PrimaryButton("Hire ${e.firstName}") { nav.go("postJob?editor=${e.id}") }
                    SecondaryButton("💬 Chat") { nav.go("chat/${e.id}") }
                }
            }
        }
    }
}
