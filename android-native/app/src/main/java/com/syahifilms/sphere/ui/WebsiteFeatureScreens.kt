package com.syahifilms.sphere.ui

import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavHostController
import com.syahifilms.sphere.data.*
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

// Native counterparts to the most-used website-only shortcuts.
// All network I/O uses the Android Supabase client, never a WebView.

@Composable
fun SavedEditorsScreen(nav: NavHostController) {
    val me = AppState.me ?: return
    val data = load(me.id) {
        val rows = Api.select("sp_saved?user_id=eq.${me.id}&select=editor_id&order=created_at.desc")
        val ids = rows.mapObjects { it.str("editor_id") }
        val users = Repo.profilesByIds(ids)
        ids.mapNotNull { users[it] }
    }
    Page("Saved Editors", onBack = { nav.popBackStack() }) {
        MutedText("Editors you saved on Sphere")
        when {
            data.error != null -> ErrorBox(data.error) { data.reload() }
            data.data == null -> Loading()
            data.data.isEmpty() -> {
                GlassPanel(Modifier.fillMaxWidth()) {
                    Text("No saved editors yet", fontWeight = FontWeight.Bold)
                    MutedText("Browse verified editors and save profiles you like.")
                    SecondaryButton("Browse editors") { nav.go("editors") }
                }
            }
            else -> data.data.forEach { p ->
                EditorCard(p) { nav.go("editor/${p.id}") }
            }
        }
    }
}

@Composable
fun VerifiedPcScreen(nav: NavHostController) {
    val data = load(Unit) {
        Api.select("sp_public_profiles?edit_device=in.(pc,both)&is_verified=eq.true&select=*")
            .mapObjects { Profile.from(it) }
    }
    Page("Verified PC", onBack = { nav.popBackStack() }) {
        MutedText("Verified editors who edit on PC or laptop")
        when {
            data.error != null -> ErrorBox(data.error) { data.reload() }
            data.data == null -> Loading()
            data.data.isEmpty() -> MutedText("No verified PC editors available yet.")
            else -> data.data.forEach { e -> EditorCard(e) { nav.go("editor/${e.id}") } }
        }
    }
}

@Composable
fun VaultNativeScreen(nav: NavHostController) {
    val ctx = LocalContext.current
    val me = AppState.me ?: return
    val data = load(me.id, AppState.role) {
        if (AppState.editorSide) Repo.myEditorJobs() else Repo.myClientJobs()
    }
    Page("Project Vault", onBack = { nav.popBackStack() }) {
        MutedText("Your raw files, project links and delivered videos")
        when {
            data.error != null -> ErrorBox(data.error) { data.reload() }
            data.data == null -> Loading()
            data.data.none { it.filesLink.isNotBlank() || it.deliveryLink.isNotBlank() } ->
                GlassPanel(Modifier.fillMaxWidth()) {
                    Text("No files yet", fontWeight = FontWeight.Bold)
                    MutedText("Raw files and final video links appear here when attached to your projects.")
                }
            else -> data.data.filter { it.filesLink.isNotBlank() || it.deliveryLink.isNotBlank() }.forEach { j ->
                CardBox {
                    Text(j.category, fontWeight = FontWeight.Bold)
                    StatusChip(j.status)
                    if (j.filesLink.startsWith("https://") || j.filesLink.startsWith("http://"))
                        TextButton(onClick = { openUrl(ctx, j.filesLink) }) { Text("📂 Open raw files") }
                    if (j.deliveryLink.startsWith("https://") || j.deliveryLink.startsWith("http://"))
                        TextButton(onClick = { openUrl(ctx, j.deliveryLink) }) { Text("🎬 Open delivered video") }
                    SecondaryButton("View project") { nav.go("project/${j.id}") }
                }
            }
        }
    }
}

@Composable
fun NativePaymentsScreen(nav: NavHostController) {
    val me = AppState.me ?: return
    val data = load(me.id, AppState.role) {
        if (AppState.editorSide) Repo.myEditorJobs() else Repo.myClientJobs()
    }
    Page("Payments", onBack = { nav.popBackStack() }) {
        MutedText("Track the payment status of your Sphere projects")
        when {
            data.error != null -> ErrorBox(data.error) { data.reload() }
            data.data == null -> Loading()
            data.data.isEmpty() -> MutedText("No project payments to show yet.")
            else -> data.data.forEach { j ->
                CardBox(onClick = { nav.go("project/${j.id}") }) {
                    Text(j.category, fontWeight = FontWeight.Bold)
                    KeyValue("Project", money(j.finalAmount))
                    KeyValue("Payment status", j.payment.ifBlank { "Not paid" })
                    if (AppState.editorSide)
                        KeyValue("Payout status", j.payoutStatus.ifBlank { "Pending" })
                    MutedText("Open project for details", 11)
                }
            }
        }
    }
}

@Composable
fun NativeEscrowScreen(nav: NavHostController) {
    Page("SafePay Escrow", onBack = { nav.popBackStack() }) {
        GlassPanel(Modifier.fillMaxWidth()) {
            Text("🛡️ SafePay Escrow",fontWeight=FontWeight.ExtraBold,fontSize=22.sp)
            Spacer(Modifier.height(7.dp))
            MutedText("Projects and payments stay connected to the same secured Sphere backend.")
            Text("1 · Agree on the project amount",modifier=Modifier.padding(top=12.dp),fontWeight=FontWeight.SemiBold)
            Text("2 · Pay through the project's verified payment flow",modifier=Modifier.padding(top=8.dp),fontWeight=FontWeight.SemiBold)
            Text("3 · Review delivery and confirm completion",modifier=Modifier.padding(top=8.dp),fontWeight=FontWeight.SemiBold)
            Text("4 · Follow the project status for payout or dispute",modifier=Modifier.padding(top=8.dp),fontWeight=FontWeight.SemiBold)
        }
        SecondaryButton("My projects") { nav.go("jobs") }
        SecondaryButton("Help & Support") { nav.go("support") }
    }
}

@Composable
fun NativePremiumScreen(nav: NavHostController) {
    val ctx = LocalContext.current
    Page("Sphere Premium", onBack = { nav.popBackStack() }) {
        GlassPanel(Modifier.fillMaxWidth()) {
            Text("💎 Get Premium",fontSize=23.sp,fontWeight=FontWeight.ExtraBold)
            MutedText("Find verified talent and manage premium jobs with Sphere.")
            Spacer(Modifier.height(10.dp))
            Text("Premium options and availability depend on your project.",fontWeight=FontWeight.SemiBold)
            MutedText("Subscription/payment checkout is not yet built into this native APK. Do not pay from an unverified link.",12)
        }
        SecondaryButton("Browse editors") { nav.go("editors") }
        SecondaryButton("Help & Support") { nav.go("support") }
    }
}

@Composable
fun NativePortfolioScreen(nav: NavHostController) {
    val me = AppState.me ?: return
    val ctx = LocalContext.current
    Page("Portfolio", onBack = { nav.popBackStack() }) {
        GlassPanel(Modifier.fillMaxWidth()) {
            Row(verticalAlignment=Alignment.CenterVertically) {
                Avatar(me.avatarUrl,me.name,64.dp)
                Spacer(Modifier.width(13.dp))
                Column {
                    Text(me.name,fontSize=19.sp,fontWeight=FontWeight.Bold)
                    MutedText(me.categoriesLabel,12)
                }
            }
        }
        WebsiteSectionTitle("My portfolio")
        CardBox {
            if(me.portfolio.isBlank() && me.sample.isBlank()) MutedText("No portfolio links added yet.")
            if(me.portfolio.startsWith("https://") || me.portfolio.startsWith("http://"))
                SecondaryButton("Open portfolio") { openUrl(ctx,me.portfolio) }
            if(me.sample.startsWith("https://") || me.sample.startsWith("http://"))
                SecondaryButton("View sample video") { openUrl(ctx,me.sample) }
        }
        SecondaryButton("Edit editor details") { nav.go("editorDetails") }
    }
}

@Composable
fun NativeEarningsScreen(nav: NavHostController) {
    val me = AppState.me ?: return
    val data = load(me.id) { Repo.myEditorJobs() }
    Page("Earnings", onBack = { nav.popBackStack() }) {
        MutedText("Payout status of your assigned projects — not a bank balance")
        when {
            data.error != null -> ErrorBox(data.error) { data.reload() }
            data.data == null -> Loading()
            data.data.isEmpty() -> MutedText("Earnings will show when you get paid projects.")
            else -> data.data.forEach { j ->
                CardBox(onClick = { nav.go("project/${j.id}") }) {
                    Text(j.category,fontWeight=FontWeight.Bold)
                    KeyValue("Project amount",money(j.finalAmount))
                    KeyValue("Payout status",j.payoutStatus.ifBlank { "Pending" })
                }
            }
        }
    }
}

@Composable
fun NativeSettingsScreen(nav: NavHostController) {
    val me = AppState.me
    Page("Settings",onBack={nav.popBackStack()}) {
        GlassPanel(Modifier.fillMaxWidth()) {
            Text("⚙️ Sphere Settings",fontWeight=FontWeight.ExtraBold,fontSize=19.sp)
            MutedText("Native app • Pink, peach & purple")
            if(me!=null) MutedText("Account: ${me.email}",12)
        }
        CardBox(onClick={nav.go("notifications")}) { Text("🔔 Notifications",fontWeight=FontWeight.SemiBold) }
        CardBox(onClick={nav.go("profile")}) { Text("👤 My account",fontWeight=FontWeight.SemiBold) }
        CardBox(onClick={nav.go("support")}) { Text("🆘 Help & Support",fontWeight=FontWeight.SemiBold) }
        MutedText("More appearance and notification controls can be added in a later native release.",12)
    }
}

@Composable
fun NativeSearchScreen(nav: NavHostController, initial: String) {
    var term by remember(initial) { mutableStateOf(initial.takeIf { it != "editors" && it != "jobs" } ?: "") }
    val editors = load(Unit) { Repo.verifiedEditors() }
    val jobs = load(Unit) { Repo.openJobs() }
    Page("Search Sphere",onBack={nav.popBackStack()}) {
        OutlinedTextField(value=term,onValueChange={term=it},singleLine=true,
            label={Text("Search editors, jobs, skills…")},
            modifier=Modifier.fillMaxWidth(),shape=RoundedCornerShape(18.dp),
            keyboardOptions=KeyboardOptions(imeAction=ImeAction.Search))
        WebsiteSectionTitle("Editors")
        when {
            editors.error != null -> ErrorBox(editors.error) { editors.reload() }
            editors.data == null -> Loading()
            else -> {
                val results = editors.data.filter {
                    term.isBlank() || it.name.contains(term,true) || it.categoriesLabel.contains(term,true)
                        || it.skills.any { skill -> skill.contains(term,true) }
                }
                if(results.isEmpty()) MutedText("No matching editors")
                results.take(20).forEach { p -> EditorCard(p) { nav.go("editor/${p.id}") } }
            }
        }
        WebsiteSectionTitle("Available jobs")
        when {
            jobs.error != null -> ErrorBox(jobs.error) { jobs.reload() }
            jobs.data == null -> Loading()
            else -> {
                val results = jobs.data.filter { term.isBlank() || it.category.contains(term,true)
                    || it.description.contains(term,true) }
                if(results.isEmpty()) MutedText("No matching jobs")
                results.take(20).forEach { j -> JobCard(j) { nav.go("project/${j.id}") } }
            }
        }
    }
}

@Composable
fun NativeSphereAIScreen(nav: NavHostController) {
    val ctx=LocalContext.current
    val scope=rememberCoroutineScope()
    val me=AppState.me
    var input by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf("") }
    val messages=remember { mutableStateListOf<Pair<String,String>>() }
    val send: () -> Unit = {
        val prompt=input.trim()
        if(prompt.isNotEmpty() && !busy) {
            input=""
            messages.add("user" to prompt)
            scope.launch {
                busy=true
                error=""
                try {
                    val chat=JSONArray()
                    messages.takeLast(12).forEach { (role,text) ->
                        chat.put(JSONObject().put("role",role).put("text",text))
                    }
                    val response=Api.function("sphere-ai",JSONObject().put("messages",chat))
                    val reply=response.str("reply")
                    if(reply.isBlank()) error=response.str("error").ifBlank{"Sphere AI could not respond right now"}
                    else messages.add("model" to reply)
                }catch(e:Exception){error=e.message?:"Sphere AI is unavailable"}
                finally{busy=false}
            }
        }
    }
    Page("Sphere AI ✨",onBack={nav.popBackStack()}) {
        GlassPanel(Modifier.fillMaxWidth()) {
            Text("Hi ${me?.firstName ?: "there"}! 👋",fontWeight=FontWeight.Bold)
            MutedText("Ask about editing, portfolios, project descriptions and hiring.")
        }
        messages.forEach { (role,text) ->
            CardBox {
                Text(if(role=="user") "You" else "Sphere AI",fontWeight=FontWeight.Bold,
                    color=WebsiteColors.Violet,fontSize=11.sp)
                Text(text,fontSize=14.sp)
            }
        }
        if(error.isNotBlank()) Text(error,color=Color(0xFFB4254E),fontSize=12.sp)
        if(busy) LinearProgressIndicator(Modifier.fillMaxWidth())
        Spacer(Modifier.height(12.dp))
        OutlinedTextField(value=input,onValueChange={input=it},singleLine=false,maxLines=3,
            placeholder={Text("Ask Sphere AI…")},modifier=Modifier.fillMaxWidth(),
            shape=RoundedCornerShape(20.dp),
            keyboardOptions=KeyboardOptions(imeAction=ImeAction.Send),
            keyboardActions=KeyboardActions(onSend={send()}))
        PrimaryButton(if(busy) "Thinking…" else "Send message",enabled=!busy) { send() }
        MutedText("AI can make mistakes. Never share OTPs, passwords or bank details.",11)
    }
}
