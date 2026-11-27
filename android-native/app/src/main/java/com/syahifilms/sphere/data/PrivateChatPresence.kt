package com.syahifilms.sphere.data

import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.delay
import okhttp3.*
import org.json.JSONObject
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicInteger

/** Private per-conversation channel. Only ephemeral booleans, never message content.
 * The backend RLS policy must be installed before this can join. No public fallback.
 */
object PrivateChatPresence {
    data class State(val online: Boolean,val typing: Boolean)
    private val client = OkHttpClient.Builder().followRedirects(false).followSslRedirects(false).retryOnConnectionFailure(false).pingInterval(20,TimeUnit.SECONDS).build()
    fun events(owner: String,peer: String,typing: () -> Boolean) = callbackFlow<State> {
        require(NativeChat.validId(owner) && NativeChat.validId(peer) && owner != peer)
        val access = Api.realtimeToken(owner)
        val topic = "realtime:sphere-private-chat-" + listOf(owner,peer).sorted().joinToString(":")
        val seq = AtomicInteger()
        val joined = AtomicBoolean(false)
        val last = AtomicLong(0)
        val typed = AtomicBoolean(false)
        val joinRef = seq.incrementAndGet().toString()
        fun packet(target: String,event: String,payload: JSONObject,ref: String = seq.incrementAndGet().toString()) =
            JSONObject().put("topic",target).put("event",event).put("payload",payload).put("ref",ref).toString()
        val base = Config.SUPABASE_URL.replaceFirst("https://","wss://")
        val request = Request.Builder().url("$base/realtime/v1/websocket?apikey=${Api.enc(Config.SUPABASE_KEY)}&vsn=1.0.0").build()
        val socket = client.newWebSocket(request,object: WebSocketListener() {
            override fun onOpen(ws: WebSocket,response: Response) {
                if (Api.userId != owner) { ws.cancel(); return }
                ws.send(packet(topic,"phx_join",JSONObject().put("access_token",access)
                    .put("config",JSONObject().put("private",true)
                        .put("broadcast",JSONObject().put("ack",false).put("self",false))
                        .put("presence",JSONObject().put("key","")).put("postgres_changes",org.json.JSONArray())),joinRef))
            }
            override fun onMessage(ws: WebSocket,text: String) {
                if (Api.userId != owner) { ws.cancel(); return }
                val msg = runCatching { JSONObject(text) }.getOrNull() ?: return
                if (msg.str("topic") != topic) return
                val payload = msg.optJSONObject("payload") ?: return
                if (msg.str("event") == "phx_reply" && msg.str("ref") == joinRef) {
                    if (payload.str("status") == "ok") joined.set(true) else ws.close(1000,"private join denied")
                }
                if (msg.str("event") in listOf("phx_error","phx_close")) { joined.set(false); ws.cancel(); close(); return }
                if (joined.get() && msg.str("event") == "broadcast" && payload.str("event") == "activity") {
                    val data = payload.optJSONObject("payload") ?: return
                    if (data.str("from") != peer) return
                    last.set(android.os.SystemClock.elapsedRealtime())
                    typed.set(data.optBoolean("typing"))
                }
            }
            override fun onFailure(ws: WebSocket,t: Throwable,response: Response?) { close() }
            override fun onClosed(ws: WebSocket,code: Int,reason: String) { close() }
        })
        val worker = launch {
            var tick = 0
            while (true) {
                delay(1000)
                if (Api.userId != owner) { socket.cancel(); break }
                tick++
                if (tick >= 10 && !joined.get()) { socket.cancel(); close(); break }
                if (joined.get() && tick % 2 == 0) {
                    socket.send(packet(topic,"broadcast",JSONObject().put("type","broadcast").put("event","activity")
                        .put("payload",JSONObject().put("from",owner).put("typing",typing()))))
                }
                if (tick % 25 == 0) socket.send(packet("phoenix","heartbeat",JSONObject()))
                val stamp = last.get()
                val online = joined.get() && stamp > 0 && android.os.SystemClock.elapsedRealtime()-stamp < 6500
                trySend(State(online,online && typed.get()))
            }
        }
        awaitClose { worker.cancel(); socket.cancel() }
    }
}
