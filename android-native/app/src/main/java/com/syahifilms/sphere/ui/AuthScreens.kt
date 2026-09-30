@file:OptIn(ExperimentalMaterial3Api::class)

package com.syahifilms.sphere.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavHostController
import com.syahifilms.sphere.R
import com.syahifilms.sphere.data.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.json.JSONObject

@Composable
fun SplashScreen(nav: NavHostController) {
    var error by remember { mutableStateOf<String?>(null) }
    var attempt by remember { mutableIntStateOf(0) }
    LaunchedEffect(attempt) {
        error = null
        delay(500)
        if (!Api.isLoggedIn) { nav.resetTo("welcome"); return@LaunchedEffect }
        try { routeAfterLogin(nav) } catch (e: Exception) { error = "No internet connection" }
    }
    Box(
        Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Color(0xFF0F3FCC), Blue))),
        contentAlignment = Alignment.Center
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Image(painterResource(R.drawable.logo), null, Modifier.size(96.dp).clip(CircleShape).background(Color.White).padding(14.dp))
            Spacer(Modifier.height(14.dp))
            Text("Sphere", color = Color.White, fontSize = 30.sp, fontWeight = FontWeight.ExtraBold)
            Text("by Syahi Films", color = Color.White.copy(alpha = 0.85f), fontSize = 13.sp)
            if (error != null) {
                Spacer(Modifier.height(20.dp))
                Text(error ?: "", color = Color.White)
                TextButton(onClick = { attempt++ }) { Text("Try again", color = Color.White, fontWeight = FontWeight.Bold) }
            }
        }
    }
}

@Composable
fun WelcomeScreen(nav: NavHostController) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var busy by remember { mutableStateOf(false) }
    Column(
        Modifier.fillMaxSize().background(Bg).verticalScroll(rememberScrollState()).padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Spacer(Modifier.height(48.dp))
        Image(painterResource(R.drawable.logo), null, Modifier.size(90.dp))
        Spacer(Modifier.height(12.dp))
        Text("Sphere", fontSize = 32.sp, fontWeight = FontWeight.ExtraBold, color = Blue)
        Text("Hire verified video editors — or find editing work", color = Muted, textAlign = TextAlign.Center)
        Spacer(Modifier.height(36.dp))
        PrimaryButton(if (busy) "Please wait…" else "Continue with Google", enabled = !busy) {
            scope.launch {
                busy = true
                try {
                    if (GoogleAuth.signIn(ctx)) routeAfterLogin(nav)
                } catch (e: Exception) { toast(ctx, e.message ?: "Google sign-in failed") }
                busy = false
            }
        }
        SecondaryButton("Log in with email") { nav.go("login") }
        SecondaryButton("Create an account") { nav.go("signup") }
        Spacer(Modifier.height(20.dp))
        Row {
            TextButton(onClick = { openUrl(ctx, Config.WEBSITE + "/terms.html") }) { Text("Terms", color = Muted) }
            TextButton(onClick = { openUrl(ctx, Config.WEBSITE + "/privacy.html") }) { Text("Privacy", color = Muted) }
            TextButton(onClick = { openUrl(ctx, Config.WEBSITE + "/refund.html") }) { Text("Refund", color = Muted) }
        }
    }
}

@Composable
fun LoginScreen(nav: NavHostController) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var email by remember { mutableStateOf("") }
    var pass by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    Page("Log in", onBack = { nav.popBackStack() }) {
        Field(email, { email = it.trim() }, "Email", keyboard = KeyboardType.Email)
        OutlinedTextField(
            value = pass, onValueChange = { pass = it }, label = { Text("Password") },
            visualTransformation = PasswordVisualTransformation(),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
            singleLine = true, modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp)
        )
        TextButton(onClick = {
            if (email.isBlank()) { toast(ctx, "Enter your email first"); return@TextButton }
            scope.launch {
                try { Api.resetPassword(email); toast(ctx, "We sent a password reset link to $email (check Spam too)") }
                catch (e: Exception) { toast(ctx, e.message ?: "Could not send the link") }
            }
        }) { Text("Forgot password?") }
        PrimaryButton(if (busy) "Logging in…" else "Log in", enabled = !busy) {
            if (email.isBlank() || pass.isBlank()) { toast(ctx, "Enter your email and password"); return@PrimaryButton }
            scope.launch {
                busy = true
                try { Api.signInWithPassword(email, pass); routeAfterLogin(nav) }
                catch (e: Exception) { toast(ctx, e.message ?: "Login failed") }
                busy = false
            }
        }
        TextButton(onClick = { nav.go("signup") }, modifier = Modifier.fillMaxWidth()) { Text("New here? Create an account") }
    }
}

@Composable
fun RolePicker(role: String, onPick: (String) -> Unit) {
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.padding(vertical = 6.dp)) {
        FilterChip(selected = role == "client", onClick = { onPick("client") }, label = { Text("I want to hire (Client)") })
        FilterChip(selected = role == "editor", onClick = { onPick("editor") }, label = { Text("I edit videos (Editor)") })
    }
}

@Composable
fun SignupScreen(nav: NavHostController) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var name by remember { mutableStateOf("") }
    var email by remember { mutableStateOf("") }
    var phone by remember { mutableStateOf("") }
    var pass by remember { mutableStateOf("") }
    var role by remember { mutableStateOf("client") }
    var busy by remember { mutableStateOf(false) }
    Page("Create account", onBack = { nav.popBackStack() }) {
        Field(name, { name = it }, "Full name")
        Field(email, { email = it.trim() }, "Email", keyboard = KeyboardType.Email)
        PhoneField(phone, { phone = it })
        OutlinedTextField(
            value = pass, onValueChange = { pass = it }, label = { Text("Password (min 6 characters)") },
            visualTransformation = PasswordVisualTransformation(), singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
            modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp)
        )
        MutedText("I am a…", 12)
        RolePicker(role) { role = it }
        PrimaryButton(if (busy) "Creating…" else "Create account", enabled = !busy) {
            val p = cleanIndianPhone(phone)
            when {
                name.isBlank() || email.isBlank() || pass.isBlank() -> toast(ctx, "Please fill in all fields")
                p == null -> toast(ctx, "Number is not correct. Enter a valid 10-digit mobile number.")
                pass.length < 6 -> toast(ctx, "Password must be at least 6 characters")
                else -> scope.launch {
                    busy = true
                    try {
                        val meta = JSONObject().put("full_name", name.trim()).put("role", role.uppercase()).put("phone", p)
                        if (Api.signUp(email, pass, meta)) {
                            val me = AppState.refreshMe()
                            if (me?.role == "editor") nav.resetTo("editorDetails") else routeAfterLogin(nav)
                        } else {
                            toast(ctx, "Account created! Check your email to confirm, then log in.")
                            nav.resetTo("login")
                        }
                    } catch (e: Exception) { toast(ctx, e.message ?: "Could not create the account") }
                    busy = false
                }
            }
        }
    }
}

/** After Google login (or an incomplete profile): choose Client/Editor + mobile number. */
@Composable
fun ChooseRoleScreen(nav: NavHostController) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val existing = AppState.me
    var name by remember { mutableStateOf(existing?.name?.takeIf { it != "User" } ?: Api.userMeta.str("full_name").ifBlank { Api.userMeta.str("name") }) }
    var phone by remember { mutableStateOf((existing?.phone ?: "").filter { it.isDigit() }.takeLast(10)) }
    var role by remember { mutableStateOf(if (existing?.role == "editor") "editor" else "client") }
    var busy by remember { mutableStateOf(false) }
    Page("Welcome to Sphere") {
        Text("How do you want to use Sphere?", fontWeight = FontWeight.Bold, fontSize = 18.sp)
        Spacer(Modifier.height(6.dp))
        RolePicker(role) { role = it }
        Field(name, { name = it }, "Your name")
        PhoneField(phone, { phone = it })
        PrimaryButton(if (busy) "Saving…" else "Continue", enabled = !busy) {
            val p = cleanIndianPhone(phone)
            if (name.isBlank()) { toast(ctx, "Enter your name"); return@PrimaryButton }
            if (p == null) { toast(ctx, "Number is not correct. Enter a valid 10-digit mobile number."); return@PrimaryButton }
            scope.launch {
                busy = true
                try {
                    Repo.saveRoleAndPhone(role, name.trim(), p)
                    val me = AppState.refreshMe()
                    if (me?.role == "editor" && !me.verified) nav.resetTo("editorDetails") else nav.resetTo("home")
                } catch (e: Exception) { toast(ctx, e.message ?: "Could not save") }
                busy = false
            }
        }
        TextButton(onClick = { scope.launch { Api.signOut(); nav.resetTo("welcome") } }) { Text("Log out") }
    }
}

@Composable
fun EditorDetailsScreen(nav: NavHostController) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val me = AppState.me
    var phone by remember { mutableStateOf((me?.phone ?: "").filter { it.isDigit() }.takeLast(10)) }
    var categories by remember { mutableStateOf(me?.categories ?: emptyList()) }
    var languages by remember { mutableStateOf(me?.languages ?: emptyList()) }
    var skills by remember { mutableStateOf(me?.skills?.joinToString(", ") ?: "") }
    var exp by remember { mutableStateOf(me?.experience?.toString() ?: "") }
    var price by remember { mutableStateOf(me?.price ?: "") }
    var portfolio by remember { mutableStateOf(me?.portfolio ?: "") }
    var sample by remember { mutableStateOf(me?.sample ?: "") }
    var busy by remember { mutableStateOf(false) }
    Page("Editor application", onBack = if (nav.previousBackStackEntry != null) ({ nav.popBackStack(); Unit }) else null) {
        MutedText("Tell us about your work. Our team will call you to verify your profile.")
        Spacer(Modifier.height(8.dp))
        PhoneField(phone, { phone = it }, "Mobile number (our team will call you on this)")
        MultiPick("Categories you work in (choose one or more)", Config.CATEGORIES, categories) { categories = it }
        MultiPick("Languages you edit in (choose one or more)", Config.LANGUAGES, languages) { languages = it }
        Field(skills, { skills = it }, "Skills / Software", "Premiere Pro, After Effects…")
        Field(exp, { exp = it.filter { c -> c.isDigit() }.take(2) }, "Experience (years)", keyboard = KeyboardType.Number)
        Field(price, { price = it.filter { c -> c.isDigit() }.take(6) }, "Starting price (₹ per video)", keyboard = KeyboardType.Number)
        Field(portfolio, { portfolio = it.trim() }, "Portfolio link (YouTube / Drive)")
        Field(sample, { sample = it.trim() }, "Sample video link (unlisted YouTube)")
        PrimaryButton(if (busy) "Submitting…" else "Submit for verification", enabled = !busy) {
            val p = cleanIndianPhone(phone)
            when {
                p == null -> toast(ctx, "Number is not correct. Enter a valid 10-digit mobile number.")
                categories.isEmpty() -> toast(ctx, "Choose at least one category")
                languages.isEmpty() -> toast(ctx, "Choose at least one language")
                price.isBlank() -> toast(ctx, "Enter your starting price")
                sample.isNotBlank() && !sample.startsWith("http") -> toast(ctx, "Sample link must start with https://")
                else -> scope.launch {
                    busy = true
                    try {
                        Repo.saveEditorDetails(p, categories, languages, skills, exp.toIntOrNull(), price, portfolio, sample)
                        val updated = AppState.refreshMe()
                        nav.resetTo(if (updated?.role == "admin") "home" else "verification")
                    } catch (e: Exception) { toast(ctx, e.message ?: "Could not save") }
                    busy = false
                }
            }
        }
    }
}

@Composable
fun VerificationScreen(nav: NavHostController) {
    val ctx = LocalContext.current
    val me = AppState.me ?: return
    Page("Verification", onBack = { if (!nav.popBackStack()) nav.resetTo("home") }) {
        if (me.verified) {
            CardBox(border = Success) {
                Text("✅ You're a verified editor", fontWeight = FontWeight.Bold, fontSize = 18.sp)
                KeyValue("Editor code", me.code)
                KeyValue("Categories", me.categoriesLabel)
                KeyValue("Languages", me.languagesLabel)
            }
            PrimaryButton("Find work") { nav.resetTo("home") }
            return@Page
        }
        CardBox(border = Blue) {
            Text("Application submitted ✅", fontWeight = FontWeight.Bold, fontSize = 18.sp)
            Spacer(Modifier.height(6.dp))
            MutedText("Our verification team will call you on")
            Text(me.phone.ifBlank { "your number" }, fontSize = 22.sp, fontWeight = FontWeight.ExtraBold)
            MutedText("Usually within 24–48 hours · 10 AM – 7 PM", 12)
        }
        CardBox {
            Text("Verification progress", fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(6.dp))
            Text("✔  Application submitted", color = Success)
            Text("●  Verification call — experience, software, sample video", color = Blue)
            Text("○  Verified badge & editor code", color = Muted)
        }
        CardBox {
            Text("Your application", fontWeight = FontWeight.Bold)
            KeyValue("Categories", me.categoriesLabel)
            KeyValue("Languages", me.languagesLabel)
            KeyValue("Experience", me.experience?.let { "$it years" } ?: "-")
            KeyValue("Skills", me.skills.joinToString(", ").ifBlank { "-" })
            KeyValue("Starting price", if (me.price.isBlank()) "-" else "₹${me.price} / video")
            if (me.sample.isNotBlank()) TextButton(onClick = { openUrl(ctx, me.sample) }) { Text("▶ Open sample video") }
            SecondaryButton("Edit application") { nav.go("editorDetails") }
        }
        SupportCard()
        PrimaryButton("Go to Home") { nav.resetTo("home") }
    }
}
