package com.syahifilms.sphere.data

import kotlinx.coroutines.CancellationException
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

object NativeProjects {
    data class Draft(val id: String, val data: JSONObject, val updatedAt: String)
    private fun uid(): String = Api.userId ?: throw ApiException(401, "Please log in")
    private fun draft(row: JSONObject) = Draft(row.str("id"), row.optJSONObject("data") ?: JSONObject(), row.str("updated_at"))

    suspend fun drafts(): List<Draft> =
        Api.select("sp_job_drafts?client_id=eq.${uid()}&order=updated_at.desc&select=id,data,updated_at").mapObjects { draft(it) }
    suspend fun getDraft(id: String): Draft? =
        Api.selectOne("sp_job_drafts?id=eq.${Api.enc(id)}&client_id=eq.${uid()}&select=id,data,updated_at")?.let { draft(it) }
    suspend fun saveDraft(id: String?, fields: JSONObject): String {
        val owner = uid()
        val row = JSONObject().put("data", fields)
        val saved = if (id == null) Api.insert("sp_job_drafts", row.put("client_id", owner))
            else Api.updateReturning("sp_job_drafts?id=eq.${Api.enc(id)}&client_id=eq.$owner", row)
        return saved?.str("id")?.takeIf { it.isNotBlank() } ?: error("Draft was not saved. Try again.")
    }
    suspend fun deleteDraft(id: String) {
        Api.delete("sp_job_drafts?id=eq.${Api.enc(id)}&client_id=eq.${uid()}")
    }

    /** A stable request UUID prevents a duplicate project if the response was lost.
     * Never delete uploaded objects after an ambiguous job insert response.
     */
    suspend fun publish(me: Profile, requestId: String, fields: JSONObject, presetEditor: String?, files: List<LocalProjectMedia>,
                        progress: (String) -> Unit): String {
        require(me.id == uid())
        UUID.fromString(requestId)
        val existing = Repo.job(requestId)
        if (existing != null) {
            require(existing.clientId == me.id)
            return existing.id
        }
        require(fields.str("audience") != "premium") { "Premium posting is not available in this preview." }
        ProjectMedia.validate(files)
        val paths = mutableListOf<String>()
        val rawFiles = JSONArray()
        try {
            for ((index, file) in files.withIndex()) {
                require(me.id == uid())
                progress("Uploading ${index + 1} of ${files.size}: ${file.name}")
                val path = ProjectMedia.storagePath(me.id, file.mime)
                paths.add(path)
                Api.uploadProjectFile(me.id, path, file.file, file.mime)
                val item = JSONObject().put("path", path).put("name", file.name.take(80))
                    .put("type", file.mime).put("size", file.size)
                if (file.reference) item.put("kind", "reference")
                rawFiles.put(item)
            }
        } catch (e: CancellationException) { throw e }
        catch (e: Exception) {
            try { Api.removeProjectFiles(me.id, paths) } catch (_: Exception) { }
            throw e
        }
        require(me.id == uid())
        val row = JSONObject(fields.toString()).put("id", requestId).put("client_id", me.id)
            .put("raw_files", rawFiles).put("revisions_expected", JSONObject.NULL)
            .put("status", if (presetEditor == null) "open" else "negotiating")
            .put("assigned_editor", presetEditor ?: JSONObject.NULL)
        // Native-only draft metadata must never become a database column.
        row.remove("native_preset_editor")
        for (key in listOf("title","video_length","video_format","style_notes","reference_links","files_link","language")) {
            if (row.str(key).isBlank()) row.put(key, JSONObject.NULL)
        }
        progress("Posting project…")
        val created = try { Api.insert("sp_jobs", row) }
        catch (e: CancellationException) { throw e }
        catch (e: Exception) {
            // The request may have committed. Reconcile on the same ID; never delete its media.
            val committed = try { Repo.job(requestId) } catch (_: Exception) { null }
            if (committed?.clientId == me.id) return committed.id
            throw ApiException(503, "Posting not confirmed. Check My Projects before retrying this form.")
        }
        val id = created?.str("id")?.takeIf { it == requestId } ?: error("Posting not confirmed. Check My Projects.")
        // Notification failure must not turn a successful insert into a second posting.
        try {
            val label = fields.str("title").ifBlank { fields.str("category") }
            if (presetEditor != null) Repo.notify(listOf(presetEditor), "You were hired directly!", "$label — propose your price.")
            else {
                val editors = Repo.verifiedEditors(fields.str("category"))
                Repo.notify(editors.map { it.id }, "New Job Posted", "$label — Budget " + money(fields.numOrNull("budget")))
            }
        } catch (e: CancellationException) { throw e }
        catch (_: Exception) { }
        return id
    }
}
