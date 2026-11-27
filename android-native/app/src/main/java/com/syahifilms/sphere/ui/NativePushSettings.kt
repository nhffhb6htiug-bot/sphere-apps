package com.syahifilms.sphere.ui

import android.Manifest
import android.os.Build
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.ContextCompat
import com.syahifilms.sphere.data.*

@Composable
fun NativePushSettings() {
    val context = LocalContext.current
    val owner = AppState.me?.id ?: return
    var enabled by remember(owner) { mutableStateOf(SpherePush.enabled(context,owner)) }
    val configured = remember { SpherePush.configured(context) }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted && Api.userId == owner) { SpherePush.setEnabled(context,owner,true); enabled = true }
    }
    CardBox {
        Text("Android notifications")
        if (!configured) MutedText("Native push is not configured for this development build.")
        else {
            MutedText("Delivery still requires the Sphere server to register this device. No chat content is shown on the lock screen.")
            if (!enabled) PrimaryButton("Allow notification alerts") {
                if (Build.VERSION.SDK_INT >= 33 && ContextCompat.checkSelfPermission(context,Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED)
                    permission.launch(Manifest.permission.POST_NOTIFICATIONS)
                else { SpherePush.setEnabled(context,owner,true); enabled = true }
            } else SecondaryButton("Turn off alerts") { SpherePush.setEnabled(context,owner,false); enabled = false }
        }
    }
}
