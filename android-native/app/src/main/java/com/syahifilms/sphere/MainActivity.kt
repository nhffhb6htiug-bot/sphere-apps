package com.syahifilms.sphere

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.core.content.FileProvider
import com.syahifilms.sphere.data.Api
import com.syahifilms.sphere.ui.SphereNav
import com.syahifilms.sphere.ui.SphereTheme

class SphereCaptureProvider : FileProvider()

/** Native Compose development preview. Production release is blocked until parity passes. */
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Api.init(applicationContext)
        setContent { SphereTheme { SphereNav() } }
    }
}
