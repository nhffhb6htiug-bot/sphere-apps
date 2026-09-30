@file:OptIn(ExperimentalMaterial3Api::class)

package com.syahifilms.sphere.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavHostController
import com.syahifilms.sphere.data.*
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset

/** Date picker that does not allow past dates (India date). Returns yyyy-MM-dd. */
@Composable
fun DeadlinePicker(value: String, onPick: (String) -> Unit) {
    var open by remember { mutableStateOf(false) }
    OutlinedButton(onClick = { open = true }, modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp).height(52.dp)) {
        Icon(Icons.Filled.DateRange, null)
        Spacer(Modifier.width(8.dp))
        Text(if (value.isBlank()) "Choose deadline" else "Deadline: ${prettyDate(value)}")
    }
    if (open) {
        val today = LocalDate.parse(todayIST())
        val state = rememberDatePickerState(
            selectableDates = object : SelectableDates {
                override fun isSelectableDate(utcTimeMillis: Long): Boolean =
                    !Instant.ofEpochMilli(utcTimeMillis).atZone(ZoneOffset.UTC).toLocalDate().isBefore(today)
            }
        )
        DatePickerDialog(
            onDismissRequest = { open = false },
            confirmButton = {
                TextButton(onClick = {
                    state.selectedDateMillis?.let { onPick(Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate().toString()) }
                    open = false
                }) { Text("OK") }
            },
            dismissButton = { TextButton(onClick = { open = false }) { Text("Cancel") } }
        ) { DatePicker(state = state) }
    }
}

@Composable
fun PostJobScreen(nav: NavHostController, presetEditor: String?) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val me = AppState.me ?: return
    var category by remember { mutableStateOf(Config.CATEGORIES.first()) }
    var details by remember { mutableStateOf("") }
    var budget by remember { mutableStateOf("") }
    var deadline by remember { mutableStateOf("") }
    var link by remember { mutableStateOf("") }
    var language by remember { mutableStateOf("Any") }
    var busy by remember { mutableStateOf(false) }
    val hired = if (presetEditor != null) load(presetEditor) { Repo.profile(presetEditor) }.data else null
    Page(if (presetEditor != null) "Hire editor" else "Post a job", onBack = { nav.popBackStack() }) {
        if (hired != null) CardBox { Text("Hiring ${hired.name} directly", fontWeight = FontWeight.Bold); MutedText("They will propose a price, then you confirm.", 12) }
        Dropdown("Category", category, Config.CATEGORIES) { category = it }
        Field(details, { details = it }, "Project details", "Video type, length, style, references…", minLines = 4)
        Field(budget, { budget = it.filter { c -> c.isDigit() }.take(7) }, "Budget (₹)", keyboard = KeyboardType.Number)
        Dropdown("Video language (optional)", language, listOf("Any") + Config.LANGUAGES) { language = it }
        DeadlinePicker(deadline) { deadline = it }
        Field(link, { link = it.trim() }, "Raw files link (optional)", "Google Drive / WeTransfer link")
        MutedText("Tip: share big raw videos as a Google Drive link.", 12)
        PrimaryButton(if (busy) "Posting…" else "Post job", enabled = !busy) {
            val b = budget.toDoubleOrNull()
            when {
                details.isBlank() || b == null || b <= 0 -> toast(ctx, "Please add project details and a budget")
                deadline.isNotBlank() && deadline < todayIST() -> toast(ctx, "Deadline cannot be in the past")
                link.isNotBlank() && !link.startsWith("http") -> toast(ctx, "Link must start with https://")
                else -> scope.launch {
                    busy = true
                    try {
                        val id = Repo.postJob(me, category, details.trim(), b, deadline.ifBlank { null }, link, presetEditor, if (language == "Any") "" else language)
                        toast(ctx, "Job posted ✅")
                        if (id.isNotBlank()) { nav.popBackStack(); nav.go("project/$id") } else nav.resetTo("jobs")
                    } catch (e: Exception) { toast(ctx, e.message ?: "Could not post the job") }
                    busy = false
                }
            }
        }
    }
}

@Composable
fun JobsScreen(nav: NavHostController) {
    val me = AppState.me ?: return
    val client = AppState.clientSide
    Scaffold(
        containerColor = Bg,
        topBar = { SphereTopBar(if (client) "My projects" else "Jobs") },
        bottomBar = { MainBottomBar(nav, "jobs") },
        floatingActionButton = {
            if (client) ExtendedFloatingActionButton(onClick = { nav.go("postJob") }, icon = { Icon(Icons.Filled.Add, null) }, text = { Text("Post a job") })
        }
    ) { pad ->
        Column(Modifier.padding(pad).fillMaxSize().padding(horizontal = 16.dp).verticalScroll(rememberScrollState())) {
            if (client) {
                val jobs = load(Unit) { Repo.myClientJobs() }
                when {
                    jobs.error != null -> ErrorBox(jobs.error) { jobs.reload() }
                    jobs.data == null -> Loading()
                    jobs.data.isEmpty() -> MutedText("You have not posted any jobs yet. Tap “Post a job”.")
                    else -> jobs.data.forEach { j -> JobCard(j) { nav.go("project/${j.id}") } }
                }
            } else {
                SectionTitle("Available work")
                val open = load(Unit) { Repo.openJobs() }
                when {
                    open.error != null -> ErrorBox(open.error) { open.reload() }
                    open.data == null -> Loading()
                    else -> WorkList(me, open.data) { j -> nav.go("project/${j.id}") }
                }
                SectionTitle("My projects")
                val mine = load(Unit) { Repo.myEditorJobs() }
                when {
                    mine.error != null -> ErrorBox(mine.error) { mine.reload() }
                    mine.data == null -> Loading()
                    mine.data.isEmpty() -> MutedText("No projects yet.")
                    else -> mine.data.forEach { j -> JobCard(j) { nav.go("project/${j.id}") } }
                }
            }
            Spacer(Modifier.height(80.dp))
        }
    }
}

private val STEPS = listOf("open" to "Posted", "negotiating" to "Price", "payment-pending" to "Payment",
    "in-progress" to "Editing", "delivered" to "Delivered", "approved" to "Approved")

@Composable
fun ProjectScreen(nav: NavHostController, id: String) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val me = AppState.me ?: return
    val loaded = load(id) {
        val j = Repo.job(id)
        val other = if (j == null) null else {
            val otherId = if (j.clientId == me.id) j.assignedEditor else j.clientId
            if (otherId.isBlank()) null else Repo.profile(otherId)
        }
        val bids = if (j != null && j.clientId == me.id && j.status == "open") Repo.bids(j.id).size else 0
        val rated = if (j != null && j.status == "approved") Repo.hasRated(j.id) else false
        listOf(j, other, bids, rated)
    }
    var busy by remember { mutableStateOf(false) }
    fun act(block: suspend () -> Unit) {
        scope.launch {
            busy = true
            try { block(); loaded.reload() } catch (e: Exception) { toast(ctx, e.message ?: "Something went wrong") }
            busy = false
        }
    }
    Page("Project", onBack = { nav.popBackStack() }) {
        val d = loaded.data
        if (loaded.error != null) { ErrorBox(loaded.error) { loaded.reload() }; return@Page }
        if (d == null) { Loading(); return@Page }
        val job = d[0] as Job?
        if (job == null) { MutedText("This project is not available."); return@Page }
        val other = d[1] as Profile?
        val bidCount = d[2] as Int
        val rated = d[3] as Boolean
        val isClient = job.clientId == me.id
        val isEditor = job.assignedEditor == me.id
        val stepIndex = STEPS.indexOfFirst { it.first == job.status }

        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(job.category, fontSize = 22.sp, fontWeight = FontWeight.ExtraBold, modifier = Modifier.weight(1f))
            StatusChip(job.status, job.expired)
        }
        Row(Modifier.fillMaxWidth().padding(vertical = 10.dp), horizontalArrangement = Arrangement.SpaceBetween) {
            STEPS.forEachIndexed { i, s ->
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(if (i <= stepIndex) "●" else "○", color = if (i <= stepIndex) Blue else Muted)
                    Text(s.second, fontSize = 10.sp, color = if (i <= stepIndex) Blue else Muted)
                }
            }
        }
        if (job.status == "refunded") CardBox(border = Orange) { Text("💸 This project has been refunded.", fontWeight = FontWeight.Bold) }

        CardBox {
            KeyValue("Budget", money(job.budget))
            if (job.lockedAmount != null) KeyValue("Final amount (locked)", money(job.lockedAmount))
            if (isEditor && job.lockedAmount != null) KeyValue("You receive", money(job.editorAmount ?: editorShare(job.lockedAmount)) + " (${Config.FEE_PERCENT}% fee)")
            KeyValue("Deadline", if (job.deadline.isBlank()) "-" else prettyDate(job.deadline))
            if (job.language.isNotBlank()) KeyValue("Language", job.language)
            Spacer(Modifier.height(6.dp))
            Text(job.description, fontSize = 14.sp)
            if (job.filesLink.isNotBlank() && (isClient || isEditor)) TextButton(onClick = { openUrl(ctx, job.filesLink) }) { Text("📂 Raw files") }
            if (job.deliveryLink.isNotBlank()) TextButton(onClick = { openUrl(ctx, job.deliveryLink) }) { Text("🎬 Open delivered video") }
        }
        if (other != null && (isClient || isEditor)) {
            CardBox(onClick = { if (isClient) nav.go("editor/${other.id}") }) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Avatar(other.avatarUrl, other.name, 42.dp)
                    Spacer(Modifier.width(10.dp))
                    Column(Modifier.weight(1f)) {
                        Text(other.name, fontWeight = FontWeight.Bold)
                        MutedText(if (isClient) "Your editor" else "Your client", 12)
                    }
                    TextButton(onClick = { nav.go("chat/${other.id}") }) { Text("💬 Chat") }
                }
            }
        }

        // ---------- actions by status ----------
        when {
            // editor: place a bid
            job.status == "open" && !isClient && AppState.editorSide -> {
                if (job.expired) MutedText("This job expired on ${prettyDate(job.deadline)}. Bidding is closed.")
                else if (!me.verified && me.role != "admin") MutedText("You can bid once the Sphere team verifies your profile.")
                else BidForm(job, busy) { amount, msg -> act { Repo.placeBid(me, job, amount, msg); toast(ctx, "Bid sent ✅") } }
            }
            // client: bids / reopen
            job.status == "open" && isClient -> {
                if (job.expired) {
                    CardBox(border = Orange) {
                        Text("This job expired on ${prettyDate(job.deadline)}", fontWeight = FontWeight.Bold)
                        MutedText("Editors can no longer see it. Pick a new deadline to reopen it.", 12)
                        DeadlinePicker("") { date -> act { Repo.extendDeadline(job, date); toast(ctx, "Job reopened ✅") } }
                    }
                } else PrimaryButton("View bids ($bidCount)") { nav.go("bids/${job.id}") }
            }
            // price negotiation
            job.status == "negotiating" && (isClient || isEditor) -> {
                NegotiateBox(job, me, isClient, busy,
                    onAccept = { act { Repo.acceptAmount(job); toast(ctx, "Price locked 🔒") } },
                    onPropose = { amt -> act { Repo.proposeAmount(me, job, amt, isClient); toast(ctx, "Price sent") } })
            }
            job.status == "payment-pending" && isClient -> CardBox(border = Blue) {
                Text("Pay ${money(job.finalAmount)} to start", fontWeight = FontWeight.Bold)
                MutedText("In-app payment is coming in the next app update. For now, please pay from the Sphere website (same account).", 12)
                SecondaryButton("Open Sphere website") { openUrl(ctx, Config.WEBSITE) }
            }
            job.status == "payment-pending" && isEditor -> MutedText("Waiting for the client's payment…")
            job.status == "in-progress" && isEditor -> DeliverBox(busy) { link -> act { Repo.deliver(job, link); toast(ctx, "Delivered ✅ Waiting for approval") } }
            job.status == "in-progress" && isClient -> MutedText("Your editor is working on it. You will get a notification when the video is delivered.")
            job.status == "delivered" && isClient -> {
                PrimaryButton(if (busy) "Please wait…" else "✅ Approve & release payment", enabled = !busy) {
                    act {
                        val payout = Repo.approve(job)
                        toast(ctx, if (payout == "released") "Approved ✅ Payment released to the editor." else "Approved ✅ Syahi Films will pay the editor.")
                    }
                }
            }
            job.status == "delivered" && isEditor -> MutedText("Delivered ✅ Waiting for the client to approve. No reply in 7 days? Report it.")
            job.status == "approved" && isClient && !rated -> RateBox(busy) { stars, review -> act { Repo.rate(job, stars, review); toast(ctx, "Thank you for your review!") } }
        }
        if ((isClient || isEditor) && job.status != "open") {
            SecondaryButton("🚩 Report a problem", Danger) { nav.go("report?job=${job.id}") }
        }
    }
}

@Composable
private fun BidForm(job: Job, busy: Boolean, onSubmit: (Double, String) -> Unit) {
    val ctx = LocalContext.current
    var amount by remember { mutableStateOf("") }
    var msg by remember { mutableStateOf("") }
    CardBox(border = Blue) {
        Text("Place your bid", fontWeight = FontWeight.Bold)
        MutedText("Client's budget: ${money(job.budget)}", 12)
        Field(amount, { amount = it.filter { c -> c.isDigit() }.take(7) }, "Your price (₹)", keyboard = KeyboardType.Number)
        val a = amount.toDoubleOrNull()
        if (a != null) MutedText("You will receive ${money(editorShare(a))} (${Config.FEE_PERCENT}% Sphere fee)", 12)
        Field(msg, { msg = it }, "Message to the client", "Why you're a good fit…", minLines = 3)
        PrimaryButton(if (busy) "Sending…" else "Submit bid", enabled = !busy) {
            if (a == null || a <= 0) toast(ctx, "Enter your price") else onSubmit(a, msg)
        }
    }
}

@Composable
private fun NegotiateBox(job: Job, me: Profile, isClient: Boolean, busy: Boolean, onAccept: () -> Unit, onPropose: (Double) -> Unit) {
    val ctx = LocalContext.current
    var amount by remember { mutableStateOf("") }
    CardBox(border = Blue) {
        Text("Agree on the final price", fontWeight = FontWeight.Bold)
        if (job.proposedAmount != null) {
            val mine = job.proposedBy == me.id
            Text(
                if (mine) "You proposed ${money(job.proposedAmount)} — waiting for the other side."
                else "${if (isClient) "Editor" else "Client"} proposed ${money(job.proposedAmount)}",
                modifier = Modifier.padding(vertical = 6.dp)
            )
            if (!isClient) MutedText("At ${money(job.proposedAmount)} you receive ${money(editorShare(job.proposedAmount))}.", 12)
            if (!mine) PrimaryButton(if (busy) "Please wait…" else "Accept ${money(job.proposedAmount)}", enabled = !busy) { onAccept() }
        } else MutedText(if (isClient) "Waiting for the editor's price." else "Propose your price for this project.")
        Field(amount, { amount = it.filter { c -> c.isDigit() }.take(7) }, "Propose a different amount (₹)", keyboard = KeyboardType.Number)
        SecondaryButton("Send price") {
            val a = amount.toDoubleOrNull()
            if (a == null || a <= 0) toast(ctx, "Enter an amount") else { onPropose(a); amount = "" }
        }
    }
}

@Composable
private fun DeliverBox(busy: Boolean, onDeliver: (String) -> Unit) {
    val ctx = LocalContext.current
    var link by remember { mutableStateOf("") }
    CardBox(border = Blue) {
        Text("Deliver the final video", fontWeight = FontWeight.Bold)
        Field(link, { link = it.trim() }, "Delivery link", "https://drive.google.com/…")
        PrimaryButton(if (busy) "Sending…" else "Submit final video", enabled = !busy) {
            if (!link.startsWith("http")) toast(ctx, "Link must start with https://") else onDeliver(link)
        }
    }
}

@Composable
private fun RateBox(busy: Boolean, onRate: (Int, String) -> Unit) {
    var stars by remember { mutableIntStateOf(5) }
    var review by remember { mutableStateOf("") }
    CardBox(border = Success) {
        Text("Rate your editor", fontWeight = FontWeight.Bold)
        Row {
            (1..5).forEach { s ->
                TextButton(onClick = { stars = s }, contentPadding = PaddingValues(4.dp)) {
                    Text(if (s <= stars) "★" else "☆", fontSize = 28.sp, color = if (s <= stars) Orange else Muted)
                }
            }
        }
        Field(review, { review = it }, "Review (optional)", minLines = 2)
        PrimaryButton(if (busy) "Sending…" else "Submit review", enabled = !busy) { onRate(stars, review) }
    }
}

@Composable
fun BidsScreen(nav: NavHostController, jobId: String) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val data = load(jobId) {
        val job = Repo.job(jobId)
        val bids = Repo.bids(jobId)
        Triple(job, bids, Repo.profilesByIds(bids.map { it.editorId }))
    }
    var busy by remember { mutableStateOf(false) }
    Page("Bids", onBack = { nav.popBackStack() }) {
        val d = data.data
        when {
            data.error != null -> ErrorBox(data.error) { data.reload() }
            d == null -> Loading()
            d.first == null -> MutedText("Job not found.")
            d.second.isEmpty() -> MutedText("No bids yet. Verified editors in this category have been notified.")
            else -> d.second.forEach { b ->
                val e = d.third[b.editorId]
                CardBox {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Avatar(e?.avatarUrl ?: "", e?.name ?: "Editor", 44.dp)
                        Spacer(Modifier.width(10.dp))
                        Column(Modifier.weight(1f)) {
                            Text(e?.name ?: "Editor", fontWeight = FontWeight.Bold)
                            MutedText((e?.categoriesLabel ?: "") + (if ((e?.reviews ?: 0) > 0) " · ⭐ ${e?.rating}" else ""), 12)
                        }
                        Text(money(b.amount), color = Blue, fontWeight = FontWeight.ExtraBold, fontSize = 18.sp)
                    }
                    if (b.message.isNotBlank()) Text(b.message, color = Muted, fontSize = 13.sp, modifier = Modifier.padding(vertical = 6.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        OutlinedButton(onClick = { nav.go("editor/${b.editorId}") }) { Text("Profile") }
                        OutlinedButton(onClick = { nav.go("chat/${b.editorId}") }) { Text("Chat") }
                        Button(enabled = !busy, onClick = {
                            val job = d.first ?: return@Button
                            scope.launch {
                                busy = true
                                try { Repo.selectEditor(job, b.editorId, b.amount); nav.popBackStack(); toast(ctx, "Editor selected ✅") }
                                catch (ex: Exception) { toast(ctx, ex.message ?: "Could not select") }
                                busy = false
                            }
                        }) { Text("Select") }
                    }
                }
            }
        }
    }
}
