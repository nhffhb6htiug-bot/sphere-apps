@file:OptIn(ExperimentalMaterial3Api::class)

package com.syahifilms.sphere.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.horizontalScroll
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
import androidx.activity.compose.BackHandler
import org.json.JSONObject
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.FileProvider
import android.net.Uri
import java.io.File
import java.util.UUID
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
fun PostJobScreen(nav: NavHostController, presetEditor: String?, draftId: String? = null) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val me = AppState.me ?: return
    var category by remember { mutableStateOf(Config.CATEGORIES.first()) }
    var details by remember { mutableStateOf("") }
    var budget by remember { mutableStateOf("") }
    var deadline by remember { mutableStateOf("") }
    var link by remember { mutableStateOf("") }
    var languages by remember { mutableStateOf(emptyList<String>()) }
    var title by remember { mutableStateOf("") }
    var videoLength by remember { mutableStateOf("") }
    var videoFormat by remember { mutableStateOf("") }
    var styleNotes by remember { mutableStateOf("") }
    var referenceLinks by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var picking by remember { mutableStateOf(false) }
    var uploadStatus by remember { mutableStateOf("") }
    var attachments by remember { mutableStateOf(emptyList<PickedProjectFile>()) }
    var reviewing by remember { mutableStateOf(false) }
    val requestId = remember(draftId) { draftId ?: UUID.randomUUID().toString() }
    var draftReady by remember(draftId) { mutableStateOf(draftId == null) }
    var draftError by remember(draftId) { mutableStateOf("") }
    var draftAttempt by remember { mutableIntStateOf(0) }
    LaunchedEffect(draftId, draftAttempt) {
        if (draftId != null) {
            try {
                val d = Repo.draft(draftId)?.data ?: throw ApiException(404, "Draft not found")
                category = d.str("category").takeIf { it in Config.CATEGORIES } ?: Config.CATEGORIES.first()
                title = d.str("title"); details = d.str("description"); budget = d.str("budget").substringBefore(".")
                deadline = d.str("deadline"); link = d.str("files_link"); videoLength = d.str("video_length")
                videoFormat = d.str("video_format"); styleNotes = d.str("style_notes"); referenceLinks = d.str("reference_links")
                languages = d.str("language").split(",").map { it.trim() }.filter { it in Config.LANGUAGES }.distinct().take(4)
                draftReady = true
            } catch (e: Exception) { draftError = e.message ?: "Could not load draft" }
        }
    }
    BackHandler(enabled = busy || reviewing) { if (!busy) reviewing = false }
    val cameraDir = remember { File(ctx.cacheDir, "project-camera/$requestId").apply { mkdirs() } }
    var cameraFile by remember { mutableStateOf<File?>(null) }
    var cameraUri by remember { mutableStateOf<Uri?>(null) }
    DisposableEffect(cameraDir) { onDispose { cameraDir.deleteRecursively() } }

    fun addFiles(uris: List<Uri>, reference: Boolean) {
        if (uris.isEmpty() || busy || picking) return
        picking = true
        scope.launch {
            try {
                val unique = uris.distinct().filter { u -> attachments.none { it.uri == u } }
                require(attachments.size + unique.size <= MAX_PROJECT_FILES) { "Up to 5 raw/reference files combined." }
                attachments = attachments + unique.map { describeProjectFile(ctx, it, reference) }
            } catch (e: Exception) { toast(ctx, e.message ?: "Could not select file") }
            finally { picking = false }
        }
    }
    val rawPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { addFiles(it, false) }
    val refPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { addFiles(it, true) }
    fun finishCamera(ok: Boolean) {
        val uri = cameraUri
        if (ok && uri != null) addFiles(listOf(uri), false) else cameraFile?.delete()
        cameraFile = null
        cameraUri = null
    }
    val photoCamera = rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()) { finishCamera(it) }
    val videoCamera = rememberLauncherForActivityResult(ActivityResultContracts.CaptureVideo()) { finishCamera(it) }
    fun capture(video: Boolean) {
        if (attachments.size >= MAX_PROJECT_FILES) { toast(ctx, "Up to 5 files"); return }
        try {
            val f = File.createTempFile("capture-", if (video) ".mp4" else ".jpg", cameraDir)
            cameraFile = f
            val u = FileProvider.getUriForFile(ctx, ctx.packageName + ".projectfiles", f)
            cameraUri = u
            if (video) videoCamera.launch(u) else photoCamera.launch(u)
        } catch (_: Exception) {
            cameraFile?.delete(); cameraFile = null; cameraUri = null
            toast(ctx, "No camera app available")
        }
    }
    val hired = if (presetEditor != null) load(presetEditor) { Repo.profile(presetEditor) }.data else null
    Page(if (presetEditor != null) "Hire editor" else "Post a job", onBack = { if (!busy) { if (reviewing) reviewing = false else nav.popBackStack() } }) {
        if (!draftReady) {
            if (draftError.isBlank()) Loading() else ErrorBox(draftError) { draftError = ""; draftAttempt++ }
            return@Page
        }
        if (!reviewing) {
        if (hired != null) CardBox { Text("Hiring ${hired.name} directly", fontWeight = FontWeight.Bold); MutedText("They will propose a price, then you confirm.", 12) }
        Dropdown("Category", category, Config.CATEGORIES) { category = it }
        Field(title, { title = it.take(60) }, "Project title (optional)")
        Field(details, { details = it }, "Project details", "Video type, length, style, references…", minLines = 4)
        Field(budget, { budget = it.filter { c -> c.isDigit() }.take(7) }, "Budget (₹)", keyboard = KeyboardType.Number)
        Field(videoLength, { videoLength = it.take(40) }, "Video length (optional)", "60 sec / 5 min")
        Dropdown("Video format (optional)", videoFormat.ifBlank { "Any" }, listOf("Any", "9:16 (Reel / Short)", "16:9 (YouTube)", "1:1 (Square)", "4:5 (Feed)", "Other")) { videoFormat = if (it == "Any") "" else it }
        MultiPick("Video languages (optional)", Config.LANGUAGES, languages) { next ->
            if (next.size <= 4) languages = next else toast(ctx, "You can select up to 4 video languages.")
        }
        MutedText("${languages.size} / 4 selected" + if (languages.isEmpty()) " · Any language" else "", 12)
        Field(styleNotes, { styleNotes = it.take(1500) }, "Style / special requirements", "Music, captions, colours, transitions", minLines = 3)
        Field(referenceLinks, { referenceLinks = it.take(1000) }, "Reference video links (optional)", "YouTube / Google Drive / WeTransfer", minLines = 2)
        DeadlinePicker(deadline) { deadline = it }
        Field(link, { link = it.trim() }, "Raw files link (optional)", "Google Drive / WeTransfer link")
        MutedText("Tip: share big raw videos as a Google Drive link.", 12)
        CardBox {
            Text("Raw footage & photos", fontWeight = FontWeight.Bold)
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                OutlinedButton(enabled = !picking && !busy, onClick = { rawPicker.launch(arrayOf("image/*", "video/*")) }) { Text("Browse") }
                OutlinedButton(enabled = !picking && !busy, onClick = { capture(false) }) { Text("Camera") }
            }
            OutlinedButton(enabled = !picking && !busy, onClick = { capture(true) }) { Text("Record video") }
            Text("Reference video upload", fontWeight = FontWeight.Bold)
            OutlinedButton(enabled = !picking && !busy, onClick = { refPicker.launch(arrayOf("video/*")) }) { Text("Browse reference videos") }
            MutedText("${attachments.size} / 5 files · 50 MB maximum per file", 12)
            attachments.forEach { item ->
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    LocalProjectThumbnail(item)
                    Column(Modifier.weight(1f).padding(8.dp)) {
                        Text(item.name, maxLines = 2)
                        MutedText(if (item.reference) "Reference video" else "Raw file", 11)
                    }
                    TextButton(enabled = !busy, onClick = { attachments = attachments.filterNot { it.uri == item.uri } }) { Text("Remove") }
                }
            }
        }
        if (picking) LinearProgressIndicator(Modifier.fillMaxWidth())
        if (presetEditor == null) OutlinedButton(enabled = !busy && !picking, modifier = Modifier.fillMaxWidth(), onClick = {
            if (title.isBlank() && details.isBlank() && budget.isBlank()) toast(ctx, "Write something first") else scope.launch {
                busy = true
                try {
                    Repo.saveDraft(requestId, JSONObject().put("title", title).put("category", category).put("description", details)
                        .put("budget", budget.toDoubleOrNull() ?: JSONObject.NULL).put("deadline", deadline.ifBlank { null } ?: JSONObject.NULL)
                        .put("language", languages.joinToString(", ")).put("video_length", videoLength).put("video_format", videoFormat)
                        .put("style_notes", styleNotes).put("reference_links", referenceLinks).put("files_link", link).put("ai_assisted", false).put("audience", "all"))
                    toast(ctx, if (attachments.isEmpty()) "Draft saved" else "Draft saved. Attach files again before posting.")
                    nav.popBackStack(); nav.go("drafts")
                } catch (e: Exception) { toast(ctx, e.message ?: "Could not save draft") } finally { busy = false }
            }
        }) { Text(if (busy) "Saving…" else "Save as draft") }
        PrimaryButton("Review job →", enabled = !busy && !picking) {
            val b = budget.toDoubleOrNull()
            when {
                details.trim().length < 10 || b == null || b < 1 || b > 10000000 -> toast(ctx, "Please add at least 10 characters of project details and a valid budget")
                deadline.isNotBlank() && deadline < todayIST() -> toast(ctx, "Deadline cannot be in the past")
                link.isNotBlank() && !link.startsWith("https://", ignoreCase = true) -> toast(ctx, "Link must start with https://")
                !validProjectReferenceLinks(referenceLinks) -> toast(ctx, "Use HTTPS YouTube, Google Drive or WeTransfer reference links only.")
                else -> reviewing = true
            }
        }
        } else {
            CardBox {
                Text(title.ifBlank { category }, fontWeight = FontWeight.Bold)
                Text(details)
                KeyValue("Budget", "₹$budget")
                KeyValue("Deadline", deadline.ifBlank { "No deadline" })
                KeyValue("Languages", languages.joinToString(", ").ifBlank { "Any" })
                if (videoLength.isNotBlank()) KeyValue("Length", videoLength)
                if (videoFormat.isNotBlank()) KeyValue("Format", videoFormat)
                if (styleNotes.isNotBlank()) Text(styleNotes)
                if (referenceLinks.isNotBlank()) Text(referenceLinks)
                if (link.isNotBlank()) Text(link)
                KeyValue("Raw / reference files", "${attachments.count { !it.reference }} / ${attachments.count { it.reference }}")
            }
            if (busy) { LinearProgressIndicator(Modifier.fillMaxWidth()); MutedText(uploadStatus) }
            PrimaryButton(if (busy) "Posting…" else if (presetEditor != null) "Send to editor" else "Post job", enabled = !busy) {
                scope.launch {
                    busy = true
                    var uploaded = emptyList<ProjectAttachment>()
                    try {
                        val existing = Api.selectOne("sp_jobs?id=eq.$requestId&client_id=eq.${me.id}&select=id")
                        val id = if (existing != null) requestId else {
                            uploaded = uploadProjectFiles(ctx, me.id, attachments) { uploadStatus = it }
                            uploadStatus = "Saving project…"
                            Repo.postJob(me, category, details.trim(), budget.toDouble(), deadline.ifBlank { null }, link, presetEditor, languages.joinToString(", "), title.trim(), videoLength.trim(), videoFormat, styleNotes.trim(), referenceLinks.trim(), uploaded, requestId)
                        }
                        if (draftId != null) try { Repo.deleteDraft(draftId) } catch (_: Exception) { }
                        toast(ctx, "Job posted ✅")
                        nav.popBackStack()
                        nav.go("project/$id")
                    } catch (e: Exception) {
                        if (e is ApiException && e.status in listOf(400, 401, 403, 404, 422)) {
                            try { Api.removeOwnPrivateFiles("sphere-raw", uploaded.map { it.path }) } catch (_: Exception) { }
                        }
                        toast(ctx, e.message ?: "Could not confirm posting. Check My Projects before retrying.")
                    } finally { busy = false; uploadStatus = "" }
                }
            }
            OutlinedButton(enabled = !busy, onClick = { reviewing = false }, modifier = Modifier.fillMaxWidth()) { Text("Edit") }
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
                OutlinedButton(onClick = { nav.go("drafts") }, modifier = Modifier.fillMaxWidth()) { Text("Saved drafts") }
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
        val stage = if (j != null && j.status == "in-progress" && (j.clientId == me.id || j.assignedEditor == me.id))
            Repo.previewStage(j.id) else null
        listOf(j, other, bids, rated, stage)
    }
    var busy by remember { mutableStateOf(false) }
    var releaseJob by remember { mutableStateOf<Job?>(null) }
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
        val stage = d[4] as Repo.PreviewStage?
        val isClient = job.clientId == me.id
        val isEditor = job.assignedEditor == me.id
        val stepIndex = STEPS.indexOfFirst { it.first == job.status }

        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(job.title.ifBlank { job.category }, fontSize = 22.sp, fontWeight = FontWeight.ExtraBold, modifier = Modifier.weight(1f))
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
            if (isEditor && job.lockedAmount != null) KeyValue("You receive", money(job.editorAmount ?: editorShare(job.lockedAmount)) + " (${feeLabel()}% fee)")
            KeyValue("Deadline", if (job.deadline.isBlank()) "-" else prettyDate(job.deadline))
            if (job.language.isNotBlank()) KeyValue("Language", job.language)
            if (job.videoLength.isNotBlank()) KeyValue("Length", job.videoLength)
            if (job.videoFormat.isNotBlank()) KeyValue("Format", job.videoFormat)
            if (job.styleNotes.isNotBlank()) KeyValue("Style", job.styleNotes)
            if ((isClient || isEditor) && job.referenceLinks.isNotBlank()) {
                Text("Reference video links", fontWeight = FontWeight.SemiBold)
                Text(job.referenceLinks, fontSize = 13.sp)
            }
            Spacer(Modifier.height(6.dp))
            Text(job.description, fontSize = 14.sp)
            if (job.filesLink.isNotBlank() && (isClient || isEditor)) TextButton(onClick = { openUrl(ctx, job.filesLink) }) { Text("📂 Raw files") }
            if (isClient || isEditor) {
                job.attachments.groupBy { it.reference }.forEach { (ref, files) ->
                    Text(if (ref) "Reference videos" else "Raw footage & photos", fontWeight = FontWeight.SemiBold)
                    files.forEach { f -> PrivateMediaPreview("sphere-raw", f.path, f.name, f.type) }
                }
            }
            if ((isClient || isEditor) && job.deliveryLink.isNotBlank()) TextButton(onClick = { openUrl(ctx, job.deliveryLink) }) { Text("🎬 Open delivered video") }
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
                else if (!me.verified && me.role != "admin") {
                    val works = load(Unit) { Repo.paidWorks() }
                    val done = works.data ?: 0
                    if (works.data != null && done >= Config.FREE_WORKS) {
                        CardBox(border = Danger) {
                            Text("🔒 Verification needed", fontWeight = FontWeight.Bold)
                            MutedText(Config.VERIFY_MSG, 12)
                        }
                        VerifyFeeCard(me)
                    } else {
                        CardBox {
                            Text("Paid works before verification: $done of ${Config.FREE_WORKS}", fontWeight = FontWeight.Bold)
                            MutedText("After ${Config.FREE_WORKS} paid works, the ✔ tick (₹${Config.VERIFY_FEE}) is needed to keep getting new work.", 12)
                        }
                        BidForm(job, busy) { amount, msg -> act { Repo.placeBid(me, job, amount, msg); toast(ctx, "Bid sent ✅") } }
                    }
                }
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
            job.status == "in-progress" && isEditor -> {
                when {
                    stage == null -> Loading()
                    stage.approved -> {
                        CardBox(border = Success) {
                            Text("✅ Client approved your preview", fontWeight = FontWeight.Bold)
                            MutedText("Send the clean final video to begin the client's review period.")
                        }
                        DeliverBox(busy, "Send clean final video") { link ->
                            act { Repo.submitFinal(job, stage.previewId, link); toast(ctx, "Final video submitted ✅") }
                        }
                    }
                    else -> {
                        if (stage.sent) {
                            CardBox(border = Blue) {
                                Text("👀 Preview sent — waiting for client approval", fontWeight = FontWeight.Bold)
                                MutedText("You can update the preview below if necessary.", 12)
                            }
                        }
                        DeliverBox(busy, "Send watermarked preview") { link ->
                            act { Repo.submitPreview(job, link); toast(ctx, "Preview sent ✅") }
                        }
                    }
                }
            }
            job.status == "in-progress" && isClient -> {
                if (stage?.sent == true) {
                    CardBox(border = Blue) {
                        Text("👀 Your editor sent a preview", fontWeight = FontWeight.Bold)
                        if (stage.previewUrl.startsWith("https://") || stage.previewUrl.startsWith("http://")) {
                            SecondaryButton("Watch watermarked preview") { openUrl(ctx, stage.previewUrl) }
                        }
                        if (!stage.approved) {
                            MutedText("Approve this preview only when you're satisfied. The editor will then send the clean final video.", 12)
                            PrimaryButton(if (busy) "Approving…" else "✅ Approve preview", enabled = !busy) {
                                act { Repo.approvePreview(job); toast(ctx, "Preview approved ✅") }
                            }
                        } else MutedText("Preview approved. Waiting for the clean final video.", 12)
                    }
                } else MutedText("Your editor is working on it. You will get a notification when a preview is ready.")
            }
            job.status == "delivered" && isClient -> {
                PrimaryButton(if (busy) "Please wait…" else "✅ Review & release payment", enabled = !busy) {
                    releaseJob = job
                }
            }
            job.status == "delivered" && isEditor -> MutedText("Final submitted ✅ Waiting for client review. For any issue, contact support.")
            job.status == "approved" && isClient && !rated -> RateBox(busy) { stars, review -> act { Repo.rate(job, stars, review); toast(ctx, "Thank you for your review!") } }
        }
        if ((isClient || isEditor) && job.status != "open") {
            SecondaryButton("🚩 Report a problem", Danger) { nav.go("report?job=${job.id}") }
        }
    }
    if (releaseJob != null) {
        AlertDialog(
            onDismissRequest = { releaseJob = null },
            title = { Text("Release payment?") },
            text = { Text("Only confirm after reviewing the final video. This releases the editor's payment and can close the refund and complaint window.") },
            confirmButton = {
                TextButton(onClick = {
                    val chosen = releaseJob
                    releaseJob = null
                    if (chosen != null) act {
                        Repo.approve(chosen)
                        toast(ctx, "Approval submitted ✅")
                    }
                }) { Text("Confirm release") }
            },
            dismissButton = { TextButton(onClick = { releaseJob = null }) { Text("Cancel") } }
        )
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
        if (a != null) MutedText("You will receive ${money(editorShare(a))} (${feeLabel()}% Sphere fee)", 12)
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
private fun DeliverBox(busy: Boolean, title: String, onDeliver: (String) -> Unit) {
    val ctx = LocalContext.current
    var link by remember { mutableStateOf("") }
    CardBox(border = Blue) {
        Text(title, fontWeight = FontWeight.Bold)
        MutedText("Use a secure shareable HTTPS link. Do not send passwords or account details.", 12)
        Field(link, { link = it.trim() }, "Video link", "https://drive.google.com/…")
        PrimaryButton(if (busy) "Sending…" else title, enabled = !busy) {
            if (!link.startsWith("https://", ignoreCase = true))
                toast(ctx, "Link must start with https://")
            else onDeliver(link)
        }
    }
}

@Composable
private fun RateBox(busy: Boolean, onRate: (Int, String) -> Unit) {
    var score by remember { mutableIntStateOf(0) }
    var review by remember { mutableStateOf("") }
    CardBox(border = Success) {
        Text("Rate your editor (−3 to +3)", fontWeight = FontWeight.Bold)
        MutedText("−3 means very poor, 0 is neutral, +3 is excellent.", 12)
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(5.dp)) {
            (-3..3).forEach { n ->
                FilterChip(selected = score == n, onClick = { score = n }, label = { Text(if (n > 0) "+$n" else "$n") })
            }
        }
        Field(review, { review = it }, "Review (optional)", minLines = 2)
        PrimaryButton(if (busy) "Sending…" else "Submit rating", enabled = !busy) { onRate(score, review) }
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
