package com.syahifilms.sphere.data

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File
import java.util.UUID

data class LocalProjectMedia(val file: File, val name: String, val mime: String, val reference: Boolean) {
    val size: Long get() = file.length()
}
data class ProjectAttachment(val path: String, val name: String, val mime: String, val size: Long, val reference: Boolean) {
    companion object {
        fun from(row: JSONObject) = ProjectAttachment(row.str("path"), row.str("name"), row.str("type"),
            row.optLong("size"), row.str("kind") == "reference")
    }
}

object ProjectMedia {
    const val MAX_FILES = 5
    const val MAX_BYTES = 50L * 1024 * 1024
    private val extensions = mapOf(
        "image/jpeg" to "jpg", "image/png" to "png", "image/webp" to "webp", "image/gif" to "gif",
        "image/heic" to "heic", "image/heif" to "heif",
        "video/mp4" to "mp4", "video/webm" to "webm", "video/quicktime" to "mov",
        "video/x-matroska" to "mkv", "video/x-msvideo" to "avi", "video/mpeg" to "mpg"
    )
    fun allowedMime(mime: String): Boolean = mime in extensions
    fun extension(mime: String): String = extensions[mime] ?: throw IllegalArgumentException("Unsupported media format")

    /** Copy only the user-selected file into private temporary storage; bound actual bytes. */
    suspend fun stage(context: Context, uri: Uri, reference: Boolean, captureMime: String? = null): LocalProjectMedia = withContext(Dispatchers.IO) {
        val resolver = context.contentResolver
        val mime = (captureMime ?: resolver.getType(uri)).orEmpty().lowercase()
        require(allowedMime(mime) && (!reference || mime.startsWith("video/"))) {
            if (reference) "Choose a supported reference video." else "Choose a supported photo or video."
        }
        var name = "attachment." + extension(mime)
        if (captureMime == null) resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use {
            if (it.moveToFirst()) {
                val ni = it.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (ni >= 0 && !it.isNull(ni)) name = it.getString(ni).take(80)
                val si = it.getColumnIndex(OpenableColumns.SIZE)
                if (si >= 0 && !it.isNull(si)) require(it.getLong(si) <= MAX_BYTES) { "File is larger than 50 MB. Use a Drive link." }
            }
        }
        val dir = File(context.cacheDir, "sphere-project-media").apply { mkdirs() }
        val output = File.createTempFile("picked-", "." + extension(mime), dir)
        try {
            resolver.openInputStream(uri)?.use { input ->
                output.outputStream().use { out ->
                    val buffer = ByteArray(64 * 1024)
                    var total = 0L
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        total += count
                        require(total <= MAX_BYTES) { "File is larger than 50 MB. Use a Drive link." }
                        out.write(buffer, 0, count)
                    }
                    require(total > 0) { "Empty file" }
                }
            } ?: error("Could not read selected file")
            LocalProjectMedia(output, name, mime, reference)
        } catch (e: Throwable) { output.delete(); throw e }
    }

    fun validate(files: List<LocalProjectMedia>) {
        require(files.size <= MAX_FILES) { "Attach up to five files total." }
        require(files.all { it.size in 1L..MAX_BYTES && allowedMime(it.mime) &&
            (!it.reference || it.mime.startsWith("video/")) }) { "Invalid attachment. Choose it again." }
    }

    fun storagePath(owner: String, mime: String): String = "$owner/raw/${UUID.randomUUID()}.${extension(mime)}"
}
