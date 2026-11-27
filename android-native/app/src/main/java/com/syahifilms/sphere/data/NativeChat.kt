package com.syahifilms.sphere.data

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import kotlinx.coroutines.CancellationException
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.security.KeyStore
import java.util.UUID
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Pending TEXT only. Account-scoped encryption and stable IDs; no automatic replay of ambiguous media uploads. */
data class PendingChat(val id: String, val peer: String, val text: String, val reply: String, val created: String, val failed: Boolean = false) {
    fun json() = JSONObject().put("id",id).put("peer",peer).put("text",text).put("reply",reply).put("created",created).put("failed",failed)
    companion object { fun from(o: JSONObject) = PendingChat(o.str("id"),o.str("peer"),o.str("text"),o.str("reply"),o.str("created"),o.optBoolean("failed")) }
}
class ChatOutbox(context: Context, private val owner: String) {
    private val prefs = context.getSharedPreferences("sphere_chat_outbox_v1", Context.MODE_PRIVATE)
    private val alias = "sphere.chat.outbox.$owner"
    private fun key(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        return (ks.getKey(alias,null) as? SecretKey) ?: KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES,"AndroidKeyStore").run {
            init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
            generateKey()
        }
    }
    fun read(): List<PendingChat> {
        require(Api.userId == owner)
        val saved = prefs.getString(owner,null) ?: return emptyList()
        val parts = saved.split(":")
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE,key(),GCMParameterSpec(128,Base64.decode(parts[0],Base64.NO_WRAP)))
        return JSONArray(String(cipher.doFinal(Base64.decode(parts[1],Base64.NO_WRAP)),Charsets.UTF_8)).mapObjects { PendingChat.from(it) }
    }
    fun write(entries: List<PendingChat>) {
        require(Api.userId == owner && entries.size <= 100)
        if (entries.isEmpty()) { check(prefs.edit().remove(owner).commit()); return }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE,key()) }
        val body = JSONArray(entries.map { it.json() }).toString().toByteArray(Charsets.UTF_8)
        val encrypted = cipher.doFinal(body)
        check(prefs.edit().putString(owner,Base64.encodeToString(cipher.iv,Base64.NO_WRAP)+":"+Base64.encodeToString(encrypted,Base64.NO_WRAP)).commit())
    }
}
object NativeChat {
    fun validId(id: String) = runCatching { UUID.fromString(id).toString().equals(id,true) }.getOrDefault(false)
    suspend fun seenPing() { Api.rpc("sp_seen_ping",JSONObject()) }
    suspend fun seen(peer: String): String {
        require(validId(peer))
        val row = JSONObject(Api.rpc("sp_last_seen",JSONObject().put("p_other",peer)))
        return if (row.optBoolean("visible")) row.str("last_seen_at") else ""
    }
    suspend fun showSeen(): Boolean = Api.rpc("sp_my_show_last_seen",JSONObject()).trim() == "true"
    suspend fun setShowSeen(show: Boolean) { Api.rpc("sp_set_show_last_seen",JSONObject().put("p_show",show)) }
    suspend fun existing(owner: String, peer: String, id: String): ChatMessage? {
        require(Api.userId == owner && validId(peer) && validId(id))
        return Api.selectOne("sp_messages?id=eq.$id&sender_id=eq.$owner&receiver_id=eq.$peer&select=*")?.let { ChatMessage.from(it) }
    }
    suspend fun send(owner: String, pending: PendingChat, mediaPath: String = "", mediaType: String = "", mediaName: String = ""): ChatMessage {
        require(Api.userId == owner && validId(pending.id) && validId(pending.peer) && pending.peer != owner)
        require(pending.text.length <= 2000 && (pending.text.isNotBlank() || mediaPath.isNotBlank()))
        existing(owner,pending.peer,pending.id)?.let { return it }
        val row = JSONObject().put("id",pending.id).put("sender_id",owner).put("receiver_id",pending.peer).put("text",pending.text)
        if (pending.reply.isNotBlank()) { require(validId(pending.reply)); row.put("reply_to",pending.reply) }
        if (mediaPath.isNotBlank()) row.put("media_path",mediaPath).put("media_type",mediaType).put("media_name",mediaName.take(80))
        val saved = try { Api.insert("sp_messages",row)?.let { ChatMessage.from(it) } ?: error("Message not confirmed") }
        catch (e: CancellationException) { throw e }
        catch (e: Exception) {
            existing(owner,pending.peer,pending.id)?.let { return it }
            throw e
        }
        // Do not copy raw, possibly moderated text into notification payloads.
        if (Api.userId == owner) Repo.notify(listOf(pending.peer),"New Message","You have a new Sphere message.")
        return saved
    }
    fun transient(e: Exception) = e is IOException || e is ApiException && e.status in listOf(408,429,502,503,504)
}
