package com.syahifilms.sphere.ui

import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.provider.OpenableColumns
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import coil.request.CachePolicy
import coil.request.ImageRequest
import com.syahifilms.sphere.data.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.launch
import java.io.File
import java.util.UUID

internal const val MAX_PROJECT_FILES = 5
internal const val MAX_PROJECT_BYTES = 50L * 1024 * 1024
internal data class PickedProjectFile(val uri: Uri, val name: String, val type: String, val reference: Boolean)

internal suspend fun describeProjectFile(ctx: Context, uri: Uri, reference: Boolean): PickedProjectFile = withContext(Dispatchers.IO) {
    val resolver = ctx.contentResolver
    val type = resolver.getType(uri) ?: throw ApiException(400, "File type could not be identified")
    require(if (reference) type.startsWith("video/") else type.startsWith("image/") || type.startsWith("video/")) {
        if (reference) "Reference uploads must be videos." else "Select photos or videos."
    }
    var name = if (type.startsWith("video/")) "Video" else "Photo"
    resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use { c ->
        if (c.moveToFirst()) {
            val n = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            val z = c.getColumnIndex(OpenableColumns.SIZE)
            if (n >= 0 && !c.isNull(n)) name = c.getString(n)
            if (z >= 0 && !c.isNull(z) && c.getLong(z) > MAX_PROJECT_BYTES)
                throw ApiException(400, "File exceeds 50 MB. Use a Drive link instead.")
        }
    }
    PickedProjectFile(uri, name.take(80), type, reference)
}

internal suspend fun uploadProjectFiles(ctx: Context, owner: String, items: List<PickedProjectFile>, onProgress: (String) -> Unit): List<ProjectAttachment> {
    require(items.size <= MAX_PROJECT_FILES && Api.userId == owner)
    val uploaded = mutableListOf<ProjectAttachment>()
    val attempted = mutableListOf<String>()
    try {
        items.forEachIndexed { index, item ->
            require(Api.userId == owner)
            onProgress("Uploading ${index + 1} / ${items.size}")
            val ext = android.webkit.MimeTypeMap.getSingleton().getExtensionFromMimeType(item.type)
                ?.filter { it.isLetterOrDigit() }?.take(5)?.ifBlank { "bin" } ?: "bin"
            val path = "$owner/raw/${UUID.randomUUID()}.$ext"
            val file = withContext(Dispatchers.IO) {
                val tmp = File.createTempFile("sphere-project-", ".tmp", ctx.cacheDir)
                try {
                    ctx.contentResolver.openInputStream(item.uri)?.use { input ->
                        tmp.outputStream().use { out ->
                            val buffer = ByteArray(64 * 1024)
                            var total = 0L
                            while (true) {
                                val n = input.read(buffer)
                                if (n < 0) break
                                total += n
                                require(total <= MAX_PROJECT_BYTES) { "File exceeds 50 MB. Use a Drive link instead." }
                                out.write(buffer, 0, n)
                            }
                            require(total > 0) { "Empty file" }
                        }
                    } ?: throw ApiException(400, "File could not be opened")
                    tmp
                } catch (e: Exception) { tmp.delete(); throw e }
            }
            try {
                attempted.add(path)
                Api.uploadPrivateFile("sphere-raw", path, file, item.type)
                uploaded.add(ProjectAttachment(path, item.name, item.type, file.length(), item.reference))
            } finally { withContext(kotlinx.coroutines.NonCancellable + Dispatchers.IO) { file.delete() } }
        }
        return uploaded
    } catch (e: Exception) {
        withContext(kotlinx.coroutines.NonCancellable) {
            try { Api.removeOwnPrivateFiles("sphere-raw", attempted) } catch (_: Exception) { }
        }
        throw e
    }
}

@Composable
internal fun LocalProjectThumbnail(item: PickedProjectFile) {
    val ctx = LocalContext.current
    if (item.type.startsWith("image/")) {
        AsyncImage(model = ImageRequest.Builder(ctx).data(item.uri).size(220).diskCachePolicy(CachePolicy.DISABLED).memoryCachePolicy(CachePolicy.DISABLED).build(),
            contentDescription = item.name, modifier = Modifier.size(68.dp), contentScale = ContentScale.Crop)
    } else {
        val frame by produceState<Bitmap?>(null, item.uri) {
            value = withContext(Dispatchers.IO) {
                if (android.os.Build.VERSION.SDK_INT < 27) null
                else try {
                    val r = MediaMetadataRetriever()
                    try { r.setDataSource(ctx, item.uri); r.getScaledFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST_SYNC, 180, 180) }
                    finally { r.release() }
                } catch (_: Exception) { null }
            }
        }
        val bitmap = frame
        if (bitmap != null) Image(bitmap.asImageBitmap(), item.name, Modifier.size(68.dp), contentScale = ContentScale.Crop)
        else Text("▶ Video", modifier = Modifier.width(68.dp))
    }
}

@Composable
internal fun PrivateMediaPreview(bucket: String, path: String, name: String, type: String) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val user = Api.userId
    val url by produceState<String?>(null, bucket, path, user, type) {
        value = if (type.startsWith("image/")) try { Api.privateSignedUrl(bucket, path) } catch (_: Exception) { null } else null
    }
    var opening by remember(path, user) { mutableStateOf(false) }
    if (url != null && type.startsWith("image/")) {
        AsyncImage(model = ImageRequest.Builder(ctx).data(url).size(480).diskCachePolicy(CachePolicy.DISABLED).memoryCachePolicy(CachePolicy.DISABLED).build(),
            contentDescription = name, modifier = Modifier.fillMaxWidth().heightIn(max = 180.dp), contentScale = ContentScale.Fit)
    }
    TextButton(enabled = !opening, onClick = {
        opening = true
        scope.launch {
            try { val fresh = Api.privateSignedUrl(bucket, path); if (Api.userId == user) openUrl(ctx, fresh) }
            catch (_: Exception) { toast(ctx, "File could not be opened. Check your access or connection.") }
            finally { opening = false }
        }
    }) { Text(if (opening) "Opening…" else if (type.startsWith("video/")) "▶ $name" else name) }
}
