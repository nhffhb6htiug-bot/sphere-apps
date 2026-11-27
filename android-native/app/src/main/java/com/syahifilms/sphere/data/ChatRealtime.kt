package com.syahifilms.sphere.data

import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONArray
import org.json.JSONObject
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.delay
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.TimeUnit

/** Realtime changes are invalidation signals only; refetch via RLS rather than trust event data. */
object ChatRealtime {
    private val client = OkHttpClient.Builder().pingInterval(20, TimeUnit.SECONDS).build()
    fun changes(owner: String) = callbackFlow<Unit> {
        val access = Api.realtimeToken(owner)
        val seq = AtomicInteger()
        val topic = "realtime:native-chat-$owner"
        fun envelope(topic: String,event: String,payload: JSONObject) =
            JSONObject().put("topic",topic).put("event",event).put("payload",payload).put("ref",seq.incrementAndGet().toString()).toString()
        val base = Config.SUPABASE_URL.replaceFirst("https://","wss://")
        val request = Request.Builder().url("$base/realtime/v1/websocket?apikey=${Api.enc(Config.SUPABASE_KEY)}&vsn=1.0.0").build()
        val socket = client.newWebSocket(request,object: WebSocketListener() {
            override fun onOpen(ws: WebSocket,response: Response) {
                if (Api.userId != owner) { ws.cancel(); return }
                val filters = JSONArray()
                for (field in listOf("sender_id","receiver_id")) filters.put(JSONObject().put("event","*").put("schema","public").put("table","sp_messages").put("filter","$field=eq.$owner"))
                filters.put(JSONObject().put("event","INSERT").put("schema","public").put("table","sp_notifications").put("filter","user_id=eq.$owner"))
                ws.send(envelope(topic,"phx_join",JSONObject().put("access_token",access)
                    .put("config",JSONObject().put("broadcast",JSONObject().put("self",false))
                        .put("presence",JSONObject().put("key","")).put("postgres_changes",filters).put("private",false))))
            }
            override fun onMessage(ws: WebSocket,text: String) {
                if (Api.userId != owner) { ws.cancel(); return }
                val event = runCatching { JSONObject(text).str("event") }.getOrDefault("")
                if (event == "postgres_changes" || event == "phx_reply") trySend(Unit)
            }
            override fun onFailure(ws: WebSocket,t: Throwable,response: Response?) { close() }
            override fun onClosed(ws: WebSocket,code: Int,reason: String) { close() }
        })
        val beat = launch {
            while (true) {
                delay(25000)
                if (Api.userId != owner) { socket.cancel(); break }
                socket.send(envelope("phoenix","heartbeat",JSONObject()))
            }
        }
        awaitClose { beat.cancel(); socket.cancel() }
    }
}
