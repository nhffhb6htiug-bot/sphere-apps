plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

// The preview remains buildable without Firebase resources. Enable only with the owner's
// matching Android app configuration. The service account key must never be in the APK.
if (file("google-services.json").isFile) {
    apply(plugin = "com.google.gms.google-services")
}

// Preview uses an explicitly configured, separate Supabase project. Never fall back to production.
val previewUrl = System.getenv("SPHERE_PREVIEW_SUPABASE_URL").orEmpty().trim()
val previewKey = System.getenv("SPHERE_PREVIEW_SUPABASE_ANON_KEY").orEmpty().trim()
val previewGoogle = System.getenv("SPHERE_PREVIEW_GOOGLE_CLIENT_ID").orEmpty().trim()
require(previewUrl.isEmpty() || Regex("https://[a-z0-9]{20}\\.supabase\\.co").matches(previewUrl)) { "Preview URL must be a direct Supabase project URL." }
require(previewKey.isEmpty() || Regex("[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+").matches(previewKey)) { "Use a staging legacy anon JWT, never an admin key." }
require(previewGoogle.isEmpty() || Regex("[0-9]+-[A-Za-z0-9_-]+\\.apps\\.googleusercontent\\.com").matches(previewGoogle)) { "Invalid preview OAuth client ID." }
require(previewUrl.isEmpty() == previewKey.isEmpty()) { "Set both staging URL and staging anon key, or neither." }
require(previewUrl != "https://pwcchgjsgkwrsvbzqspp.supabase.co") { "Production backend is forbidden in preview builds." }
if (previewKey.isNotEmpty()) {
    // Reject privileged/mismatched keys BEFORE embedding anything in BuildConfig.
    val payload = runCatching {
        val bytes = java.util.Base64.getUrlDecoder().decode(previewKey.split('.')[1])
        groovy.json.JsonSlurper().parseText(String(bytes, Charsets.UTF_8)) as? Map<*, *>
    }.getOrNull()
    require(payload?.get("role") == "anon" && payload?.get("ref") == previewUrl.removePrefix("https://").removeSuffix(".supabase.co")) {
        "Only an anon key for the isolated testing project is allowed."
    }
}

android {
    namespace = "com.syahifilms.sphere"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.syahifilms.sphere"
        minSdk = 26
        targetSdk = 36
        versionCode = 12
        versionName = "2.2.8"
        buildConfigField("String","PREVIEW_URL","\"$previewUrl\"")
        buildConfigField("String","PREVIEW_ANON","\"$previewKey\"")
        buildConfigField("String","PREVIEW_GOOGLE","\"$previewGoogle\"")
    }

    // Release bundle is signed only when the OWNER configures all four
    // SPHERE_RELEASE_* environment variables in GitHub Actions secrets.
    val releaseKeyFile = System.getenv("SPHERE_RELEASE_KEYSTORE_PATH")
    val releaseStorePassword = System.getenv("SPHERE_RELEASE_STORE_PASSWORD")
    val releaseKeyAlias = System.getenv("SPHERE_RELEASE_KEY_ALIAS")
    val releaseKeyPassword = System.getenv("SPHERE_RELEASE_KEY_PASSWORD")
    val hasReleaseSigning = listOf(
        releaseKeyFile, releaseStorePassword, releaseKeyAlias, releaseKeyPassword
    ).all { !it.isNullOrBlank() }

    signingConfigs {
        if (hasReleaseSigning) {
            create("sphereRelease") {
                storeFile = file(releaseKeyFile!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        debug {
            applicationIdSuffix = ".preview"
            versionNameSuffix = "-preview"
        }
        release {
            isMinifyEnabled = false
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("sphereRelease")
            }
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
}

dependencies {
    testImplementation("junit:junit:4.13.2")
    val composeBom = platform("androidx.compose:compose-bom:2024.10.01")
    implementation(composeBom)
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-core")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.compose.ui:ui-tooling-preview")
    debugImplementation("androidx.compose.ui:ui-tooling")

    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
    implementation("androidx.navigation:navigation-compose:2.8.4")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")

    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("androidx.media3:media3-transformer:1.5.1")
    implementation("androidx.media3:media3-effect:1.5.1")
    implementation("com.google.firebase:firebase-messaging:24.1.2")
    implementation("io.coil-kt:coil-compose:2.7.0")
    implementation("io.coil-kt:coil-svg:2.7.0")

    implementation("androidx.credentials:credentials:1.3.0")
    implementation("androidx.credentials:credentials-play-services-auth:1.3.0")
    implementation("com.google.android.libraries.identity.googleid:googleid:1.1.1")
}

// Block production packaging while native parity and security gates remain open.
tasks.configureEach {
    if (name == "preReleaseBuild") {
        doFirst { throw GradleException("Native parity preview: production release is blocked until parity and security gates pass.") }
    }
}
