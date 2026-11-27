package com.syahifilms.sphere.data

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import com.syahifilms.sphere.MainActivity

/** Receive only generic data-only events for the currently opted-in authenticated account.
 * Configuration and trusted server dispatch are separate release gates.
 */
object SpherePush {
    private const val PREFS = "sphere_native_push"
    private const val CHANNEL = "sphere_messages"
    fun configured(context: Context): Boolean = runCatching {
        FirebaseApp.getApps(context).isNotEmpty() || FirebaseApp.initializeApp(context) != null
    }.getOrDefault(false)
    fun enabled(context: Context, owner: String): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString("owner", null) == owner
    fun setEnabled(context: Context, owner: String, enable: Boolean) {
        require(Api.userId == owner)
        val prefs = context.getSharedPreferences(PREFS,Context.MODE_PRIVATE)
        if (enable) prefs.edit().putString("owner",owner).apply()
        else {
            prefs.edit().remove("owner").apply()
            context.getSystemService(NotificationManager::class.java).cancelAll()
        }
    }
    fun post(context: Context, owner: String, noticeId: String) {
        if (Api.userId != owner || !enabled(context,owner) || !NativeChat.validId(noticeId)) return
        if (Build.VERSION.SDK_INT >= 33 && ContextCompat.checkSelfPermission(context,Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
        val manager = context.getSystemService(NotificationManager::class.java)
        if (!manager.areNotificationsEnabled()) return
        manager.createNotificationChannel(NotificationChannel(CHANNEL,"Sphere messages",NotificationManager.IMPORTANCE_DEFAULT))
        val launch = Intent(context,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val intent = PendingIntent.getActivity(context,0,launch,PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val notification = NotificationCompat.Builder(context,CHANNEL)
            .setSmallIcon(android.R.drawable.ic_dialog_email).setContentTitle("Sphere")
            .setContentText("You have a new notification. Open Sphere to view it.")
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE).setAutoCancel(true).setContentIntent(intent).build()
        manager.notify(noticeId.hashCode(),notification)
    }
}

class SpherePushReceiver : FirebaseMessagingService() {
    override fun onMessageReceived(message: RemoteMessage) {
        Api.init(applicationContext)
        if (message.data["kind"] != "sphere_notice") return
        val owner = message.data["owner"] ?: return
        val noticeId = message.data["notice_id"] ?: return
        SpherePush.post(applicationContext,owner,noticeId)
    }
    // No token logging or upload until authenticated device registration is configured.
    override fun onNewToken(token: String) { }
}
