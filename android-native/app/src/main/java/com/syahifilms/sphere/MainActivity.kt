package com.syahifilms.sphere

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import com.syahifilms.sphere.data.Api
import com.syahifilms.sphere.ui.SphereNav
import com.syahifilms.sphere.ui.SphereTheme

/**
 * Real native Sphere Android entry point.
 *
 * All screens are implemented in Kotlin + Jetpack Compose (SphereNav).
 * This activity does not create a WebView or load the Sphere website.
 * The Supabase HTTPS API remains the source for accounts, projects and chat.
 */
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Api.init(applicationContext)

        @Suppress("DEPRECATION")
        window.statusBarColor = android.graphics.Color.rgb(232, 237, 249)
        @Suppress("DEPRECATION")
        window.navigationBarColor = android.graphics.Color.WHITE

        setContent {
            SphereTheme {
                SphereNav()
            }
        }
    }
}
