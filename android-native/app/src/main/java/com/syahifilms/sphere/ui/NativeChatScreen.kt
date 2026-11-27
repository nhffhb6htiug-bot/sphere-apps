@file:OptIn(ExperimentalMaterial3Api::class)
package com.syahifilms.sphere.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavHostController
import com.syahifilms.sphere.data.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.collect
import java.util.UUID

@Composable
fun ChatScreen(nav: NavHostController, otherId: String) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val me = AppState.me ?: return
    if (!NativeChat.validId(otherId) || otherId == me.id) {
        Page("Chat", onBack = { nav.popBackStack() }) { MutedText("Invalid conversation.") }
        return
    }
    val outbox = remember(me.id) { ChatOutbox(ctx.applicationContext, me.id) }
    var queued by remember(me.id,otherId) { mutableStateOf<List<PendingChat>>(emptyList()) }
    var queueReady by remember(me.id) { mutableStateOf(false) }
    var messages by remember(otherId) { mutableStateOf<List<ChatMessage>>(emptyList()) }
    var other by remember(otherId) { mutableStateOf<Profile?>(null) }
    var text by remember(otherId) { mutableStateOf("") }
    var reply by remember(otherId) { mutableStateOf<ChatMessage?>(null) }
    var search by remember { mutableStateOf("") }
    var searchOpen by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var blocked by remember { mutableStateOf(true) }
    var blockKnown by remember { mutableStateOf(false) }
    var connection by remember { mutableStateOf("Connecting…") }
    var note by remember { mutableStateOf("") }
    var seen by remember { mutableStateOf("") }
    var ownSeen by remember { mutableStateOf<Boolean?>(null) }
    var menu by remember { mutableStateOf(false) }
    var confirmClear by remember { mutableStateOf(false) }
    var confirmBlock by remember { mutableStateOf(false) }
    var preview by remember { mutableStateOf<Pair<ChatMessage,String>?>(null) }
    var media by remember { mutableStateOf<LocalProjectMedia?>(null) }
    var pendingMedia by remember { mutableStateOf<PendingChat?>(null) }
    var refresh by remember { mutableIntStateOf(0) }
    val list = rememberLazyListState()
    val latestMedia by rememberUpdatedState(media)
    DisposableEffect(otherId) { onDispose { latestMedia?.file?.delete() } }

    fun persist(entries: List<PendingChat>): Boolean = try {
        // Preserve pending items for other conversations under the same account.
        val otherEntries = outbox.read().filter { it.peer != otherId }
        outbox.write(otherEntries + entries)
        queued = entries
        true
    } catch (_: Exception) { note = "Could not save the secure message queue."; false }

    LaunchedEffect(me.id,otherId) {
        try {
            queued = outbox.read().filter { it.peer == otherId }
            queueReady = true
        } catch (_: Exception) { note = "Secure offline queue unavailable. Retry after reopening chat." }
        try { other = Repo.profile(otherId) } catch (e: CancellationException) { throw e } catch (_: Exception) { }
        try { ownSeen = NativeChat.showSeen() } catch (e: CancellationException) { throw e } catch (_: Exception) { }
    }
    // Reconnect periodically for rotated access tokens. Never trust event text.
    LaunchedEffect(me.id) {
        while (Api.userId == me.id) {
            try {
                kotlinx.coroutines.withTimeout(240000) { ChatRealtime.changes(me.id).collect { refresh++ } }
            } catch (e: kotlinx.coroutines.TimeoutCancellationException) { }
            catch (e: CancellationException) { throw e }
            catch (_: Exception) { }
            delay(5000)
        }
    }
    // Serialize REST refreshes; also poll as a fallback when websocket is unavailable.
    LaunchedEffect(otherId,refresh) {
        try {
            val rows = Repo.thread(otherId)
            if (Api.userId != me.id) return@LaunchedEffect
            messages = rows
            Repo.markRead(otherId)
            val state = Api.select("sp_blocks?blocker_id=eq.${me.id}&blocked_id=eq.$otherId&select=blocked_id")
            blocked = state.length() > 0
            blockKnown = true
            connection = "Connected"
        } catch (e: CancellationException) { throw e }
        catch (_: Exception) { connection = "Reconnecting…"; blockKnown = false }
    }
    LaunchedEffect(otherId) {
        while (true) { delay(5000); refresh++ }
    }
    LaunchedEffect(otherId) {
        while (Api.userId == me.id) {
            try { NativeChat.seenPing(); seen = NativeChat.seen(otherId) }
            catch (e: CancellationException) { throw e }
            catch (_: Exception) { seen = "" }
            delay(30000)
        }
    }
    val filtered = messages.filter { search.isBlank() || it.preview.contains(search,true) }
    val count = filtered.size + if (search.isBlank()) queued.count { q -> messages.none { it.id == q.id } } else 0
    var lastCount by remember { mutableIntStateOf(0) }
    LaunchedEffect(count,search) {
        if (search.isBlank() && count > 0 && (lastCount == 0 || (list.layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: 0) >= lastCount - 3))
            list.animateScrollToItem(count - 1)
        lastCount = count
    }
    // Only retry transient failures automatically, at most once each refresh interval.
    LaunchedEffect(refresh,queueReady,blocked,blockKnown,queued.firstOrNull { !it.failed }?.id) {
        val next = queued.firstOrNull { !it.failed } ?: return@LaunchedEffect
        if (!queueReady || busy || blocked || !blockKnown || Api.userId != me.id) return@LaunchedEffect
        delay(350)
        if (busy) return@LaunchedEffect
        busy = true
        try {
            val saved = NativeChat.send(me.id,next)
            messages = (messages.filterNot { it.id == saved.id } + saved).sortedBy { it.createdAt }
            persist(queued.filterNot { it.id == next.id })
            note = ""
        } catch (e: CancellationException) { throw e }
        catch (e: Exception) {
            if (!NativeChat.transient(e)) persist(queued.map { if (it.id == next.id) it.copy(failed = true) else it })
            else note = "Message queued. It will retry while this chat is open."
        } finally { busy = false }
    }

    fun enqueue() {
        val value = text.trim()
        if (!queueReady || blocked && blockKnown || value.isBlank() || busy || media != null) return
        val item = PendingChat(UUID.randomUUID().toString(),otherId,value,reply?.id.orEmpty(),java.time.Instant.now().toString())
        if (persist(queued + item)) { text = ""; reply = null; note = "" }
    }

    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null && !busy && pendingMedia == null) scope.launch {
            busy = true
            try { val selected = ProjectMedia.stage(ctx,uri,false); media?.file?.delete(); media = selected }
            catch (e: CancellationException) { throw e }
            catch (e: Exception) { note = e.message ?: "Could not read attachment." }
            finally { busy = false }
        }
    }

    fun sendAttachment() {
        val item = media ?: return
        if (busy || blocked || !blockKnown || pendingMedia != null) return
        val pending = PendingChat(UUID.randomUUID().toString(),otherId,text.trim(),reply?.id.orEmpty(),java.time.Instant.now().toString())
        pendingMedia = pending
        scope.launch {
            busy = true
            try {
                val kind = if (item.mime.startsWith("image/")) "image" else "video"
                val path = "${me.id}/chat/${pending.id}.${ProjectMedia.extension(item.mime)}"
                Api.uploadChatFile(me.id,path,item.file,item.mime)
                val saved = NativeChat.send(me.id,pending,path,kind,item.name)
                messages = (messages.filterNot { it.id == saved.id } + saved).sortedBy { it.createdAt }
                item.file.delete(); media = null; pendingMedia = null; text = ""; reply = null; note = ""
            } catch (e: CancellationException) { throw e }
            catch (_: Exception) { note = "Media delivery not confirmed. Check its status before sending again." }
            finally { busy = false }
        }
    }

    Scaffold(containerColor = Bg, topBar = {
        TopAppBar(title = {
            Column {
                Text(other?.name ?: "Chat",fontWeight = FontWeight.Bold)
                val age = runCatching { java.time.Duration.between(java.time.OffsetDateTime.parse(seen).toInstant(),java.time.Instant.now()).seconds }.getOrNull()
                Text(if (seen.isBlank()) connection else if (age != null && age in 0..90) "Recently active" else "Last seen " + dayOf(seen) + " " + timeOf(seen),fontSize = 12.sp)
            }
        }, navigationIcon = { TextButton(onClick = { nav.popBackStack() }) { Text("‹ Back") } }, actions = {
            TextButton(onClick = { searchOpen = !searchOpen; if (!searchOpen) search = "" }) { Text("Search") }
            Box {
                TextButton(onClick = { menu = true }) { Text("⋮") }
                DropdownMenu(expanded = menu,onDismissRequest = { menu = false }) {
                    DropdownMenuItem(text = { Text(if (ownSeen == false) "Show last seen" else "Hide last seen") },enabled = ownSeen != null,onClick = {
                        menu = false; scope.launch {
                            try { val new = ownSeen == false; NativeChat.setShowSeen(new); ownSeen = new; seen = "" }
                            catch (e: CancellationException) { throw e }
                            catch (_: Exception) { note = "Could not update privacy setting." }
                        }
                    })
                    DropdownMenuItem(text = { Text("Clear chat") },onClick = { menu = false; confirmClear = true })
                    DropdownMenuItem(text = { Text(if (blocked) "Unblock" else "Block") },enabled = blockKnown,onClick = { menu = false; confirmBlock = true })
                    DropdownMenuItem(text = { Text("Report user") },onClick = { menu = false; nav.go("report?user=$otherId") })
                }
            }
        })
    }, bottomBar = {
        Column(Modifier.fillMaxWidth().background(Color.White).navigationBarsPadding().imePadding().padding(8.dp)) {
            if (note.isNotBlank()) MutedText(note,12)
            if (reply != null) Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Reply: " + reply?.preview.orEmpty().take(90),Modifier.weight(1f))
                TextButton(onClick = { reply = null }) { Text("Cancel") }
            }
            if (media != null) {
                val item = media!!
                Row(verticalAlignment = Alignment.CenterVertically) {
                    MediaThumb(android.net.Uri.fromFile(item.file).toString(),item.mime,Modifier.size(56.dp))
                    Text(item.name,Modifier.weight(1f))
                    if (pendingMedia == null) TextButton(enabled = !busy,onClick = { item.file.delete(); media = null }) { Text("Remove") }
                }
            }
            if (pendingMedia != null) {
                PrimaryButton("Check media status", enabled = !busy) {
                    val pending = pendingMedia ?: return@PrimaryButton
                    scope.launch {
                        busy = true
                        try {
                            val saved = NativeChat.existing(me.id,otherId,pending.id)
                            if (saved != null) {
                                messages = (messages.filterNot { it.id == saved.id } + saved).sortedBy { it.createdAt }
                                media?.file?.delete(); media = null; pendingMedia = null; text = ""; reply = null; note = ""
                            } else note = "No confirmed message yet. Recheck later; leaving this chat discards the local selection."
                        } catch (e: CancellationException) { throw e }
                        catch (_: Exception) { note = "Status unavailable." }
                        finally { busy = false }
                    }
                }
            } else if (blocked && blockKnown) MutedText("You blocked this contact. Unblock from the menu to message.")
            else Row(verticalAlignment = Alignment.CenterVertically) {
                TextButton(enabled = !busy && blockKnown && !blocked,onClick = {
                    picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageAndVideo))
                }) { Text("+") }
                OutlinedTextField(value = text,onValueChange = { text = it.take(2000) },modifier = Modifier.weight(1f),
                    placeholder = { Text("Message") },maxLines = 4,enabled = pendingMedia == null)
                TextButton(enabled = !busy && (if (media != null) blockKnown && !blocked else queueReady && text.isNotBlank()),
                    onClick = { if (media != null) sendAttachment() else enqueue() }) { Text("Send") }
            }
        }
    }) { pad ->
        Column(Modifier.padding(pad).fillMaxSize()) {
            if (searchOpen) OutlinedTextField(value = search,onValueChange = { search = it.take(100) },label = { Text("Search loaded messages") },modifier = Modifier.fillMaxWidth().padding(8.dp))
            LazyColumn(state = list,modifier = Modifier.weight(1f).fillMaxWidth(),contentPadding = PaddingValues(10.dp),verticalArrangement = Arrangement.spacedBy(6.dp)) {
                items(filtered,key = { it.id }) { msg ->
                    val mine = msg.senderId == me.id
                    Box(Modifier.fillMaxWidth(),contentAlignment = if (mine) Alignment.CenterEnd else Alignment.CenterStart) {
                        Column(Modifier.widthIn(max = 300.dp).background(if (mine) BlueSoft else Color.White,RoundedCornerShape(16.dp)).padding(10.dp)) {
                            if (msg.replyTo.isNotBlank()) {
                                val quoted = messages.find { it.id == msg.replyTo }
                                Text("Reply · " + (quoted?.preview?.take(100) ?: "Original message"),color = Muted,fontWeight = FontWeight.SemiBold)
                            }
                            if (msg.mediaPath.isNotBlank() && msg.mediaType in listOf("image","video","audio")) {
                                val signed = load(msg.mediaPath) { Api.chatMediaUrl(msg.mediaPath) }
                                val mime = if (msg.mediaType == "image") "image/jpeg" else "video/mp4"
                                if (signed.data != null && msg.mediaType != "audio") MediaThumb(signed.data,mime,Modifier.size(150.dp))
                                TextButton(onClick = {
                                    scope.launch {
                                        try { preview = msg to Api.chatMediaUrl(msg.mediaPath) }
                                        catch (e: CancellationException) { throw e }
                                        catch (_: Exception) { note = "Media unavailable." }
                                    }
                                }) { Text(if (msg.mediaType == "audio") "Voice message" else "Preview attachment") }
                            }
                            if (msg.text.isNotBlank()) Text(msg.text)
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(timeOf(msg.createdAt),color = Muted)
                                if (mine) Ticks(msg,false)
                                TextButton(onClick = { reply = msg }) { Text("Reply") }
                            }
                        }
                    }
                }
                if (search.isBlank()) items(queued.filter { q -> messages.none { it.id == q.id } },key = { "pending-" + it.id }) { item ->
                    Box(Modifier.fillMaxWidth(),contentAlignment = Alignment.CenterEnd) {
                        Column(Modifier.widthIn(max = 300.dp).background(BlueSoft,RoundedCornerShape(16.dp)).padding(10.dp)) {
                            Text(item.text)
                            MutedText(if (item.failed) "Not sent" else "Queued / sending",11)
                            Row {
                                if (item.failed) TextButton(enabled = !busy,onClick = { persist(queued.map { if (it.id == item.id) it.copy(failed = false) else it }); refresh++ }) { Text("Retry") }
                                TextButton(enabled = !busy,onClick = { persist(queued.filterNot { it.id == item.id }) }) { Text("Remove from queue") }
                            }
                        }
                    }
                }
            }
        }
    }
    preview?.let { (msg,url) -> MediaPreview(if (msg.mediaType == "audio") "Voice message" else "Attachment",url,if (msg.mediaType == "image") "image/jpeg" else "video/mp4") { preview = null } }
    if (confirmBlock) AlertDialog(onDismissRequest = { confirmBlock = false },title = { Text(if (blocked) "Unblock contact?" else "Block contact?") },
        text = { Text("This changes messaging access for this contact.") },
        confirmButton = { TextButton(onClick = { confirmBlock = false; scope.launch {
            try { Repo.setBlocked(otherId,!blocked); blocked = !blocked; refresh++ }
            catch (e: CancellationException) { throw e } catch (_: Exception) { note = "Could not update block." }
        } }) { Text("Confirm") } },dismissButton = { TextButton(onClick = { confirmBlock = false }) { Text("Cancel") } })
    if (confirmClear) AlertDialog(onDismissRequest = { confirmClear = false },title = { Text("Clear chat for you?") },
        text = { Text("This hides existing messages on your account. Pending messages are kept separately.") },
        confirmButton = { TextButton(onClick = { confirmClear = false; scope.launch {
            try { Repo.clearChat(otherId); messages = emptyList(); refresh++ }
            catch (e: CancellationException) { throw e } catch (_: Exception) { note = "Could not clear chat." }
        } }) { Text("Clear") } },dismissButton = { TextButton(onClick = { confirmClear = false }) { Text("Cancel") } })
}
