@file:OptIn(ExperimentalMaterial3Api::class)

package com.syahifilms.sphere.ui

import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavHostController
import com.syahifilms.sphere.R
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
    if (me == null) {
        LaunchedEffect(Unit) { nav.resetTo("splash") }
        return
    }
    Page("Sphere", bottomBar = { MainBottomBar(nav, "home") }, hideTopBar = true) {
        WebsiteHomeHeader(nav, AppState.editorSide)
        if (AppState.editorSide) EditorHome(nav, me) else ClientHome(nav, me)
    }
}

@Composable
private fun WebsiteSearchBar(nav: NavHostController, editor: Boolean = false) {
    var term by remember { mutableStateOf("") }
    val submit = {
        nav.go("search/" + Uri.encode(term.ifBlank { if (editor) "jobs" else "editors" }))
    }
    TextField(
        value = term,
        onValueChange = { term = it },
        placeholder = {
            Text(
                if(editor) "Search jobs, skills, projects…" else "Search editors, jobs, projects…",
                maxLines = 1, fontSize = 13.sp
            )
        },
        leadingIcon = { Icon(Icons.Outlined.Search, "Search") },
        trailingIcon = {
            IconButton(onClick = submit) { Icon(Icons.AutoMirrored.Filled.ArrowForward, "Find") }
        },
        singleLine = true,
        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
        keyboardActions = KeyboardActions(onSearch = { submit() }),
        modifier = Modifier.fillMaxWidth().padding(vertical = 12.dp)
            .clip(RoundedCornerShape(28.dp)),
        shape = RoundedCornerShape(28.dp),
        colors = TextFieldDefaults.colors(
            focusedContainerColor = Color.White,
            unfocusedContainerColor = Color(0xF5FFFFFF),
            focusedIndicatorColor = Color.Transparent,
            unfocusedIndicatorColor = Color.Transparent
        )
    )
}

@Composable
private fun ClientHome(nav: NavHostController, me: Profile) {
    WebsitePremium { nav.go("premium") }
    WebsiteWelcome(me)
    GlassPanel(Modifier.fillMaxWidth(), onClick = { nav.go("postJob") }) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("Get started",fontWeight=FontWeight.ExtraBold,fontSize=19.sp,
                modifier=Modifier.weight(1f),color=WebsiteColors.Plum)
            Box(Modifier.size(44.dp).clip(RoundedCornerShape(22.dp))
                .background(WebsiteColors.Accent),contentAlignment=Alignment.Center) {
                Text("+",color=Color.White,fontWeight=FontWeight.Bold,fontSize=28.sp)
            }
        }
    }
    WebsiteSectionTitle("Explore",onAll={nav.go("editors")})
    WebsiteExploreRow { route -> nav.go(route) }
    Spacer(Modifier.height(14.dp))
    WebsiteToolGrid { route -> nav.go(route) }
    Spacer(Modifier.height(14.dp))
    WebsiteServiceGrid { route -> nav.go(route) }
    WebsiteSearchBar(nav)
    if (me.role == "admin") {
        CardBox(onClick = { nav.go("profile") }, border = Orange) {
            Text("🛡️ Admin account",fontWeight=FontWeight.Bold)
            MutedText("Manage your Sphere account from Profile.",12)
        }
    }
    SupportCard()
    Spacer(Modifier.height(20.dp))
}

@Composable
private fun EditorHome(nav: NavHostController, me: Profile) {
    val promo = load(me.id) { fetchNativeEditorOffer() }
    NativeEditorOfferBanner(if (!me.verified) promo.data else null, nav)
    WebsiteWelcome(me, "Find work and manage your creative projects")
    WebsiteSearchBar(nav, editor = true)
    if (me.role == "admin") {
        CardBox(onClick = { nav.go("profile") }, border = Blue) {
            Text("🛡️ Admin · Editor mode", fontWeight = FontWeight.Bold)
            MutedText("You can bid on work. Switch back from Profile.",12)
        }
    } else {
        GlassPanel(Modifier.fillMaxWidth(),onClick={nav.go("verification")}) {
            Row(verticalAlignment=Alignment.CenterVertically) {
                EditorWebsiteSvg("verification","Verification",Modifier.size(60.dp))
                Spacer(Modifier.width(12.dp))
                Column {
                    Text(if(me.verified) "Verified editor" else "Verification pending",
                        fontSize=16.sp,fontWeight=FontWeight.ExtraBold,color=WebsiteColors.Plum)
                    Text(if(me.verified) "✔ ${me.code} · View status" else
                        (if (promo.data?.isFree == true) "🎉 First 50 editors · ₹29 FREE · Send promo video + screenshot"
                         else if (promo.data == null) "Checking verification offer…"
                         else "${Config.FREE_WORKS} paid works free, then ✔ tick (₹${Config.VERIFY_FEE})"),
                        fontSize=12.sp,color=WebsiteColors.Muted)
                }
            }
        }
    }
    EditorShortcutGrid(nav)
    WebsiteSectionTitle("Explore Categories",onAll={nav.go("jobs")})
    val cats = listOf(
        Triple("Vlog Editing",R.drawable.category_vlog,""),
        Triple("Cinematic",R.drawable.category_cinematic,""),
        Triple("Gaming Edits",R.drawable.category_gaming,""),
        Triple("Reels & Shorts",R.drawable.category_reels,""),
        Triple("Podcast Editing",R.drawable.category_podcast,""),
        Triple("Color Grading & VFX",R.drawable.category_color,""),
        Triple("Motion Graphics",R.drawable.category_motion,""),
        Triple("Ads & Commercial",R.drawable.category_ads,""),
        Triple("AI Video Editor",0,"ai-video-editor")
    )
    Row(
        Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
        horizontalArrangement=Arrangement.spacedBy(9.dp)
    ) {
        cats.forEach { (label,art,svg) ->
            Column(Modifier.width(94.dp).clip(RoundedCornerShape(20.dp))
                .background(Color(0xEFFFFFFF)).clickable { nav.go("jobs") }
                .padding(6.dp),horizontalAlignment=Alignment.CenterHorizontally) {
                if(svg.isNotBlank())
                    EditorWebsiteSvg(svg,label,Modifier.fillMaxWidth().height(77.dp))
                else
                    WebsiteArt(art,label,Modifier.fillMaxWidth().height(77.dp))
                Text(label,fontSize=10.sp,lineHeight=12.sp,fontWeight=FontWeight.SemiBold,
                    maxLines=2,overflow=TextOverflow.Ellipsis,color=WebsiteColors.Plum,
                    textAlign=TextAlign.Center)
            }
        }
    }
    WebsiteSectionTitle("Available Work",onAll={nav.go("jobs")})
    val open = load(Unit) { Repo.openJobs() }
    when {
        open.error != null -> ErrorBox(open.error) { open.reload() }
        open.data == null -> Loading()
        else -> WorkList(me, open.data) { j -> nav.go("project/${j.id}") }
    }
    WebsiteSectionTitle("Your Projects",onAll={nav.go("jobs")})
    val mine = load(Unit) { Repo.myEditorJobs().filter { it.status !in listOf("closed","refunded") } }
    when {
        mine.error != null -> ErrorBox(mine.error) { mine.reload() }
        mine.data == null -> Loading()
        mine.data.isEmpty() -> GlassPanel(Modifier.fillMaxWidth()) {
            Text("No active projects yet",fontWeight=FontWeight.SemiBold)
            MutedText("Find a job that suits your skills and start working.",12)
        }
        else -> mine.data.forEach { j -> JobCard(j) { nav.go("project/${j.id}") } }
    }
    SupportCard()
    Spacer(Modifier.height(16.dp))
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
