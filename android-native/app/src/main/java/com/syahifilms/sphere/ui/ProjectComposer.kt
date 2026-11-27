package com.syahifilms.sphere.ui

import android.net.Uri
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.os.Build
import android.widget.MediaController
import android.widget.VideoView
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.core.content.FileProvider
import androidx.navigation.NavHostController
import coil.compose.AsyncImage
import com.syahifilms.sphere.data.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File
import java.util.UUID

private val formats = listOf("Any","9:16 (Reel / Short)","16:9 (YouTube)","1:1 (Square)","4:5 (Feed)","Other")

@Composable
fun PostJobScreen(nav: NavHostController, presetEditor: String?, draftId: String? = null) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val me = AppState.me ?: return
    if (!AppState.clientSide) { Page("Post project", onBack = { nav.popBackStack() }) { MutedText("Switch to Client mode to post a project.") }; return }
    var step by rememberSaveable { mutableIntStateOf(1) }
    var currentDraft by rememberSaveable { mutableStateOf(draftId) }
    var requestId by rememberSaveable { mutableStateOf(UUID.randomUUID().toString()) }
    var loaded by rememberSaveable { mutableStateOf(draftId == null) }
    var loadError by remember { mutableStateOf<String?>(null) }
    var retry by remember { mutableIntStateOf(0) }
    var title by rememberSaveable { mutableStateOf("") }
    var category by rememberSaveable { mutableStateOf(Config.CATEGORIES.first()) }
    var details by rememberSaveable { mutableStateOf("") }
    var budget by rememberSaveable { mutableStateOf("") }
    var deadline by rememberSaveable { mutableStateOf("") }
    var link by rememberSaveable { mutableStateOf("") }
    var languageText by rememberSaveable { mutableStateOf("") }
    val languages = languageText.split(",").map { it.trim() }.filter { it.isNotBlank() }
    var videoLength by rememberSaveable { mutableStateOf("") }
    var videoFormat by rememberSaveable { mutableStateOf("Any") }
    var styleNotes by rememberSaveable { mutableStateOf("") }
    var referenceLinks by rememberSaveable { mutableStateOf("") }
    var audience by rememberSaveable { mutableStateOf("all") }
    var aiAssisted by rememberSaveable { mutableStateOf(false) }
    var media by remember { mutableStateOf<List<LocalProjectMedia>>(emptyList()) }
    var busy by remember { mutableStateOf(false) }
    var progress by remember { mutableStateOf("") }
    var note by remember { mutableStateOf("") }
    var attempted by rememberSaveable { mutableStateOf(false) }
    var discard by remember { mutableStateOf(false) }
    var preview by remember { mutableStateOf<LocalProjectMedia?>(null) }
    var capturePath by rememberSaveable { mutableStateOf<String?>(null) }
    var captureReference by rememberSaveable { mutableStateOf(false) }
    val latestMedia by rememberUpdatedState(media)
    DisposableEffect(Unit) { onDispose { latestMedia.forEach { it.file.delete() } } }

    LaunchedEffect(draftId, retry) {
        if (!loaded && draftId != null) {
            loadError = null
            try {
                val draft = NativeProjects.getDraft(draftId) ?: error("Draft not found")
                val d = draft.data
                title = d.str("title")
                category = d.str("category").takeIf { it in Config.CATEGORIES } ?: Config.CATEGORIES.first()
                details = d.str("description")
                budget = d.numOrNull("budget")?.let { if (it % 1.0 == 0.0) it.toLong().toString() else it.toString() }.orEmpty()
                deadline = d.str("deadline")
                link = d.str("files_link")
                languageText = d.str("language").split(",").map { it.trim() }.filter { it in Config.LANGUAGES }.distinct().take(4).joinToString(", ")
                videoLength = d.str("video_length")
                videoFormat = d.str("video_format").ifBlank { "Any" }
                styleNotes = d.str("style_notes")
                referenceLinks = d.str("reference_links")
                audience = d.str("audience").ifBlank { "all" }
                aiAssisted = d.optBoolean("ai_assisted", false)
                loaded = true
            } catch (e: CancellationException) { throw e }
            catch (e: Exception) { loadError = "Could not open this draft." }
        }
    }
    fun fields() = JSONObject().put("title", title.trim()).put("category", category)
        .put("description", details.trim()).put("budget", budget.toDoubleOrNull() ?: JSONObject.NULL)
        .put("deadline", deadline.ifBlank { null } ?: JSONObject.NULL).put("files_link", link.trim())
        .put("language", languageText).put("video_length", videoLength.trim())
        .put("video_format", videoFormat.takeUnless { it == "Any" }.orEmpty())
        .put("style_notes", styleNotes.trim()).put("reference_links", referenceLinks.trim())
        .put("audience", audience).put("ai_assisted", aiAssisted)

    fun validHttps(value: String): Boolean = value.isBlank() || runCatching {
        val parsed = Uri.parse(value.trim())
        parsed.scheme.equals("https", true) && !parsed.host.isNullOrBlank() && parsed.userInfo == null
    }.getOrDefault(false)
    fun problem(): String? = when {
        details.trim().length < 10 -> "Please write at least 10 characters of project details."
        budget.toDoubleOrNull()?.let { it in 1.0..10000000.0 } != true -> "Enter a valid budget (₹1–10,000,000)."
        deadline.isNotBlank() && deadline < todayIST() -> "Deadline cannot be in the past."
        !validHttps(link) || referenceLinks.lineSequence().any { !validHttps(it) } -> "Use valid HTTPS links."
        audience == "premium" -> "Premium drafts are not supported for posting in this preview. Choose normal posting explicitly or continue on web."
        else -> null
    }
    fun finish(id: String) {
        toast(ctx, "Project posted")
        nav.resetTo("jobs")
        nav.go("project/$id")
    }
    fun add(uris: List<Uri>, reference: Boolean, captureMime: String? = null, captureFile: File? = null) {
        if (uris.isEmpty()) { captureFile?.delete(); return }
        if (busy || attempted || media.size + uris.size > ProjectMedia.MAX_FILES) {
            captureFile?.delete()
            toast(ctx, "Attach up to five files total.")
            return
        }
        scope.launch {
            busy = true
            progress = "Preparing selected media…"
            val added = mutableListOf<LocalProjectMedia>()
            try {
                for (uri in uris) added.add(ProjectMedia.stage(ctx, uri, reference, captureMime))
                media = media + added
                note = ""
            } catch (e: CancellationException) { added.forEach { it.file.delete() }; throw e }
            catch (e: Exception) { added.forEach { it.file.delete() }; note = e.message ?: "Could not read media." }
            finally { captureFile?.delete(); busy = false; progress = "" }
        }
    }
    val rawPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { add(it, false) }
    val refPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { add(it, true) }
    val galleryRaw = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(5)) { add(it, false) }
    val galleryRef = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(5)) { add(it, true) }

    fun captured(success: Boolean, mime: String) {
        val path = capturePath
        capturePath = null
        val file = path?.let { File(it) } ?: return
        if (!success || file.length() == 0L) { file.delete(); return }
        val uri = FileProvider.getUriForFile(ctx, ctx.packageName + ".capture", file)
        add(listOf(uri), captureReference, mime, file)
    }
    val camera = rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()) { captured(it, "image/jpeg") }
    val camcorder = rememberLauncherForActivityResult(ActivityResultContracts.CaptureVideo()) { captured(it, "video/mp4") }
    fun capture(video: Boolean, reference: Boolean) {
        if (busy || attempted || media.size >= ProjectMedia.MAX_FILES) return
        try {
            val dir = File(ctx.cacheDir, "sphere-capture").apply { mkdirs() }
            val file = File.createTempFile("capture-", if (video) ".mp4" else ".jpg", dir)
            capturePath = file.absolutePath
            captureReference = reference
            val uri = FileProvider.getUriForFile(ctx, ctx.packageName + ".capture", file)
            if (video) camcorder.launch(uri) else camera.launch(uri)
        } catch (e: Exception) {
            capturePath?.let { File(it).delete() }; capturePath = null
            note = "No compatible camera app was found."
        }
    }
    fun back() {
        if (busy) return
        if (attempted) { discard = true; return }
        if (step > 1) step-- else discard = true
    }
    BackHandler { back() }
    if (discard) AlertDialog(onDismissRequest = { discard = false }, title = { Text("Leave project form?") },
        text = { Text(if (attempted) "Posting was not confirmed. Check My Projects before starting another post." else "Unsaved changes and selected files will be lost. Save a draft first if needed.") },
        confirmButton = { TextButton(onClick = { discard = false; nav.popBackStack() }) { Text("Leave") } },
        dismissButton = { TextButton(onClick = { discard = false }) { Text("Stay") } })
    preview?.let { item -> MediaPreview(item.name, Uri.fromFile(item.file).toString(), item.mime) { preview = null } }

    Page(if (presetEditor == null) "Post a project" else "Hire editor", onBack = { back() }) {
        if (!loaded) {
            if (loadError == null) Loading() else ErrorBox(loadError ?: "") { retry++ }
            return@Page
        }
        Text("Step $step of 3", fontWeight = FontWeight.Bold)
        LinearProgressIndicator(progress = { step / 3f }, modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp))
        if (presetEditor != null) MutedText("Direct hire · the editor will propose a price.")
        if (attempted) {
            CardBox { Text("Posting not confirmed"); MutedText("Check the same project ID first to prevent a duplicate.") }
            PrimaryButton("Check posting status", enabled = !busy) {
                scope.launch {
                    busy = true
                    try {
                        val existing = Repo.job(requestId)
                        if (existing?.clientId == me.id) {
                            currentDraft?.let { try { NativeProjects.deleteDraft(it) } catch (_: Exception) { } }
                            finish(existing.id)
                        } else { note = "No matching project was found. You can retry the same form or check My Projects."; attempted = false }
                    } catch (e: CancellationException) { throw e }
                    catch (_: Exception) { note = "Status unavailable. Try checking again." }
                    finally { busy = false }
                }
            }
        } else when (step) {
            1 -> {
                SectionTitle("Project details")
                Field(title, { title = it.take(80) }, "Project title (optional)")
                Dropdown("Category", category, Config.CATEGORIES) { category = it }
                Field(details, { details = it.take(2000) }, "Project details", minLines = 4)
                Field(budget, { budget = it.filter { c -> c.isDigit() }.take(8) }, "Budget (₹)", keyboard = KeyboardType.Number)
                DeadlinePicker(deadline) { deadline = it }
                TextButton(onClick = { deadline = "" }) { Text("No deadline") }
                MultiPick("Video languages (${languages.size}/4)", Config.LANGUAGES, languages) { selected ->
                    if (selected.size <= 4) languageText = selected.joinToString(", ") else toast(ctx, "Choose up to 4 languages")
                }
                Field(videoLength, { videoLength = it.take(40) }, "Video length (optional)", "60 sec / 5 min")
                Dropdown("Video format", videoFormat, (formats + videoFormat).distinct()) { videoFormat = it }
                Field(styleNotes, { styleNotes = it.take(500) }, "Style notes", minLines = 2)
                if (audience == "premium") {
                    MutedText("This is a premium draft. Premium checkout is not yet available in this build.")
                    SecondaryButton("Change to normal project") { audience = "all" }
                }
                PrimaryButton("Next · Attachments", enabled = !busy) { step = 2 }
            }
            2 -> {
                SectionTitle("Raw files")
                MutedText("Photos or videos · ${media.size}/5 files total · 50 MB each")
                OutlinedButton(onClick = { rawPicker.launch(arrayOf("image/*","video/*")) }, enabled = !busy && media.size < 5) { Text("Browse files +") }
                OutlinedButton(onClick = { galleryRaw.launch(androidx.activity.result.PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageAndVideo)) }, enabled = !busy && media.size < 5) { Text("Gallery +") }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(onClick = { capture(false, false) }, enabled = !busy && media.size < 5) { Text("Camera") }
                    OutlinedButton(onClick = { capture(true, false) }, enabled = !busy && media.size < 5) { Text("Record video") }
                }
                media.filter { !it.reference }.forEach { item ->
                    LocalMediaRow(item, !busy, { preview = item }) { media = media - item; item.file.delete() }
                }
                Field(link, { link = it.take(2000) }, "Raw files link", "Google Drive / WeTransfer")
                SectionTitle("Reference videos")
                MutedText("Reference uploads must be videos.")
                OutlinedButton(onClick = { refPicker.launch(arrayOf("video/*")) }, enabled = !busy && media.size < 5) { Text("Browse reference +") }
                OutlinedButton(onClick = { galleryRef.launch(androidx.activity.result.PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.VideoOnly)) }, enabled = !busy && media.size < 5) { Text("Reference gallery +") }
                OutlinedButton(onClick = { capture(true, true) }, enabled = !busy && media.size < 5) { Text("Record reference video") }
                media.filter { it.reference }.forEach { item ->
                    LocalMediaRow(item, !busy, { preview = item }) { media = media - item; item.file.delete() }
                }
                Field(referenceLinks, { referenceLinks = it.take(2000) }, "Reference video links", "HTTPS links, one per line", minLines = 2)
                MutedText("For videos larger than 50 MB, use a Drive or WeTransfer link.")
                PrimaryButton("Done · Review", enabled = !busy) {
                    val issue = problem()
                    if (issue != null) note = issue else { note = ""; step = 3 }
                }
            }
            else -> {
                SectionTitle("Review project")
                CardBox {
                    Text(title.ifBlank { category }, fontWeight = FontWeight.Bold)
                    Text(details)
                    KeyValue("Budget", money(budget.toDoubleOrNull()))
                    KeyValue("Category", category)
                    KeyValue("Deadline", deadline.ifBlank { "No deadline" })
                    if (languageText.isNotBlank()) KeyValue("Languages", languageText)
                    if (videoLength.isNotBlank()) KeyValue("Length", videoLength)
                    if (videoFormat != "Any") KeyValue("Format", videoFormat)
                    if (styleNotes.isNotBlank()) KeyValue("Style", styleNotes)
                    if (link.isNotBlank()) KeyValue("Raw link", link)
                    if (referenceLinks.isNotBlank()) KeyValue("Reference links", referenceLinks)
                    KeyValue("Attachments", "${media.count { !it.reference }} raw · ${media.count { it.reference }} reference")
                }
                media.forEach { item -> LocalMediaRow(item, false, { preview = item }) {} }
                PrimaryButton("Post project", enabled = !busy) {
                    val issue = problem()
                    if (issue != null) { note = issue; return@PrimaryButton }
                    scope.launch {
                        busy = true
                        attempted = true
                        note = ""
                        try {
                            val id = NativeProjects.publish(me, requestId, fields(), presetEditor, media) { progress = it }
                            currentDraft?.let { try { NativeProjects.deleteDraft(it) } catch (_: Exception) { } }
                            finish(id)
                        } catch (e: CancellationException) { throw e }
                        catch (e: Exception) { note = e.message ?: "Posting not confirmed. Check status." }
                        finally { busy = false; progress = "" }
                    }
                }
            }
        }
        if (progress.isNotBlank()) { LinearProgressIndicator(modifier = Modifier.fillMaxWidth()); MutedText(progress) }
        if (note.isNotBlank()) Text(note, color = Danger)
        if (!attempted && presetEditor == null) OutlinedButton(onClick = {
            if (title.isBlank() && details.isBlank() && budget.isBlank()) { note = "Write something first."; return@OutlinedButton }
            scope.launch {
                busy = true
                try {
                    currentDraft = NativeProjects.saveDraft(currentDraft, fields())
                    toast(ctx, if (media.isEmpty()) "Draft saved" else "Draft saved. Add media again when posting.")
                    nav.resetTo("jobs")
                    nav.go("projectDrafts")
                } catch (e: CancellationException) { throw e }
                catch (e: Exception) { note = e.message ?: "Could not save draft." }
                finally { busy = false }
            }
        }, enabled = !busy) { Text("Save as draft") }
        if (step > 1 && !attempted) TextButton(onClick = { step-- }, enabled = !busy) { Text("Back") }
    }
}

@Composable
private fun LocalMediaRow(item: LocalProjectMedia, removable: Boolean, onPreview: () -> Unit, onRemove: () -> Unit) {
    Row(Modifier.fillMaxWidth().padding(vertical = 5.dp), verticalAlignment = Alignment.CenterVertically) {
        MediaThumb(Uri.fromFile(item.file).toString(), item.mime, Modifier.size(80.dp).clickable(onClick = onPreview))
        Column(Modifier.weight(1f).padding(horizontal = 8.dp)) {
            Text(item.name, maxLines = 2)
            MutedText((if (item.reference) "Reference · " else "") + "${(item.size + 1023) / 1024} KB", 11)
            TextButton(onClick = onPreview) { Text("Preview") }
        }
        if (removable) TextButton(onClick = onRemove) { Text("Remove", color = Danger) }
    }
}

@Composable
internal fun MediaThumb(source: String, mime: String, modifier: Modifier) {
    val ctx = LocalContext.current
    val video = mime.startsWith("video/")
    var frame by remember(source) { mutableStateOf<Bitmap?>(null) }
    LaunchedEffect(source, mime) {
        if (video) frame = withContext(Dispatchers.IO) {
            val reader = MediaMetadataRetriever()
            try {
                if (source.startsWith("https://")) reader.setDataSource(source, emptyMap<String,String>())
                else reader.setDataSource(ctx, Uri.parse(source))
                if (Build.VERSION.SDK_INT >= 27) reader.getScaledFrameAtTime(100000, MediaMetadataRetriever.OPTION_CLOSEST_SYNC, 192, 192)
                else null // avoid decoding unbounded 4K frames on API 26
            } catch (_: Exception) { null } finally { runCatching { reader.release() } }
        }
    }
    Box(modifier.clip(RoundedCornerShape(12.dp)).background(BlueSoft), contentAlignment = Alignment.Center) {
        if (video) {
            val bmp = frame
            if (bmp != null) Image(bmp.asImageBitmap(), "Video frame", Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
            Text("▶", color = androidx.compose.ui.graphics.Color.White,
                modifier = Modifier.background(androidx.compose.ui.graphics.Color.Black.copy(alpha = .55f)).padding(5.dp))
        } else AsyncImage(model = source, contentDescription = "Photo preview", modifier = Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
    }
}

@Composable
internal fun MediaPreview(name: String, source: String, mime: String, onClose: () -> Unit) {
    var player by remember(source) { mutableStateOf<VideoView?>(null) }
    var error by remember(source) { mutableStateOf(false) }
    DisposableEffect(source) { onDispose { player?.stopPlayback() } }
    Dialog(onDismissRequest = onClose) {
        Surface(shape = RoundedCornerShape(18.dp)) {
            Column(Modifier.padding(12.dp)) {
                Text(name, fontWeight = FontWeight.Bold, maxLines = 2)
                if (mime.startsWith("video/")) {
                    AndroidView(factory = { context ->
                        VideoView(context).apply {
                            val controls = MediaController(context)
                            controls.setAnchorView(this)
                            setMediaController(controls)
                            setOnPreparedListener { seekTo(1) }
                            setOnErrorListener { _, _, _ -> error = true; true }
                            setVideoURI(Uri.parse(source))
                            player = this
                        }
                    }, modifier = Modifier.fillMaxWidth().height(250.dp))
                    if (error) MutedText("This video could not be played on this device.")
                    else Row {
                        TextButton(onClick = { player?.start() }) { Text("Play") }
                        TextButton(onClick = { player?.pause() }) { Text("Pause") }
                    }
                } else AsyncImage(model = source, contentDescription = name, modifier = Modifier.fillMaxWidth().height(280.dp), contentScale = ContentScale.Fit,
                    onError = { error = true })
                if (error && !mime.startsWith("video/")) MutedText("Could not load this photo.")
                TextButton(onClick = onClose) { Text("Done") }
            }
        }
    }
}

@Composable
fun ProjectAttachments(items: List<ProjectAttachment>) {
    var preview by remember { mutableStateOf<Pair<ProjectAttachment,String>?>(null) }
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var opening by remember { mutableStateOf(false) }
    SectionTitle("Project attachments")
    for (item in items.take(ProjectMedia.MAX_FILES)) {
        if (!ProjectMedia.allowedMime(item.mime)) continue
        val url = load(item.path) { Api.projectMediaUrl(item.path) }
        Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            if (url.data != null) MediaThumb(url.data, item.mime, Modifier.size(72.dp))
            else Box(Modifier.size(72.dp).background(BlueSoft), contentAlignment = Alignment.Center) { Text(if (item.mime.startsWith("video/")) "▶" else "Photo") }
            Column(Modifier.weight(1f).padding(horizontal = 8.dp)) {
                Text(item.name, maxLines = 2)
                MutedText(if (item.reference) "Reference video" else "Raw file", 11)
                TextButton(enabled = !opening, onClick = {
                    scope.launch {
                        opening = true
                        try { preview = item to Api.projectMediaUrl(item.path) }
                        catch (e: CancellationException) { throw e }
                        catch (_: Exception) { toast(ctx, "Attachment unavailable or access denied.") }
                        finally { opening = false }
                    }
                }) { Text("Preview") }
            }
        }
    }
    preview?.let { (item,url) -> MediaPreview(item.name, url, item.mime) { preview = null } }
}

@Composable
fun ProjectDraftsScreen(nav: NavHostController) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    if (!AppState.clientSide) { Page("Drafts", onBack = { nav.popBackStack() }) { MutedText("Switch to Client mode.") }; return }
    val drafts = load(Unit) { NativeProjects.drafts() }
    var removing by remember { mutableStateOf<NativeProjects.Draft?>(null) }
    var busy by remember { mutableStateOf(false) }
    Page("Project drafts", onBack = { nav.popBackStack() }) {
        MutedText("Private drafts synced with your Sphere account. Selected files are not saved.")
        when {
            drafts.error != null -> ErrorBox(drafts.error) { drafts.reload() }
            drafts.data == null -> Loading()
            drafts.data.isEmpty() -> MutedText("No saved drafts.")
            else -> drafts.data.forEach { draft ->
                CardBox {
                    Text(draft.data.str("title").ifBlank { draft.data.str("category").ifBlank { "Untitled draft" } }, fontWeight = FontWeight.Bold)
                    MutedText(draft.data.str("description").take(120))
                    MutedText("Saved " + prettyDate(draft.updatedAt), 11)
                    PrimaryButton("Continue", enabled = !busy) { nav.go("postJob?draft=" + draft.id) }
                    TextButton(enabled = !busy, onClick = { removing = draft }) { Text("Delete", color = Danger) }
                }
            }
        }
        PrimaryButton("New project", enabled = !busy) { nav.go("postJob") }
    }
    removing?.let { draft ->
        AlertDialog(onDismissRequest = { removing = null }, title = { Text("Delete draft?") },
            text = { Text("This will remove the saved project draft from your account.") },
            confirmButton = { TextButton(enabled = !busy, onClick = {
                removing = null
                scope.launch {
                    busy = true
                    try { NativeProjects.deleteDraft(draft.id); drafts.reload() }
                    catch (e: CancellationException) { throw e }
                    catch (_: Exception) { toast(ctx, "Could not delete draft.") }
                    finally { busy = false }
                }
            }) { Text("Delete") } }, dismissButton = { TextButton(onClick = { removing = null }) { Text("Cancel") } })
    }
}
