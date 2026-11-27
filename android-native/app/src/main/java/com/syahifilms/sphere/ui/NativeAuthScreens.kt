package com.syahifilms.sphere.ui

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.navigation.NavHostController
import com.syahifilms.sphere.data.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** Guard authenticated destinations before composing their contents and recheck periodically.
 * Backend RLS/RPCs still enforce authorization; this is an additional navigation guard.
 */
@Composable
fun NativeAccountGate(nav: NavHostController, content: @Composable () -> Unit) {
    var ready by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var retry by remember { mutableIntStateOf(0) }
    LaunchedEffect(retry) {
        ready = false
        error = null
        while (true) {
            try {
                val uid = Api.userId
                if (uid == null) { AppState.me = null; nav.resetTo("welcome"); return@LaunchedEffect }
                val status = NativeAuth.accountStatus()
                if (uid != Api.userId) return@LaunchedEffect
                if (status?.optBoolean("suspended") == true) { ready = false; nav.resetTo("suspended"); return@LaunchedEffect }
                val me = AppState.me
                if (me == null || status == null || !NativeAuth.matchesAccount(me, status)) {
                    ready = false
                    nav.resetTo("splash")
                    return@LaunchedEffect
                }
                if (me.role != "admin" && NativeAuth.phoneRequired()) {
                    ready = false
                    nav.resetTo("verifyPhone")
                    return@LaunchedEffect
                }
                if (uid != Api.userId) return@LaunchedEffect
                ready = true
                delay(60000)
            } catch (e: CancellationException) { throw e }
            catch (e: Exception) {
                ready = false
                error = "Could not verify your account. Please try again."
                break
            }
        }
    }
    if (ready) content()
    else Page("Checking account") {
        if (error == null) Loading()
        else ErrorBox(error ?: "") { retry++ }
        NativeLogout(nav)
    }
}

@Composable
private fun NativeLogout(nav: NavHostController) {
    val scope = rememberCoroutineScope()
    TextButton(onClick = { scope.launch {
        Api.signOut()
        AppState.me = null
        nav.resetTo("welcome")
    } }) { Text("Log out") }
}

@Composable
fun NativeSuspendedScreen(nav: NavHostController) {
    val scope = rememberCoroutineScope()
    val ctx = LocalContext.current
    Page("Account suspended") {
        CardBox(border = Danger) {
            Text("Your account is suspended")
            MutedText("Messages, projects and bidding are unavailable. Contact support if this is a mistake.")
        }
        PrimaryButton("Check account status") { scope.launch {
            try { routeAfterLogin(nav) } catch (e: Exception) { toast(ctx, "Could not check status") }
        } }
        SecondaryButton("Help & Support") { nav.go("support") }
        NativeLogout(nav)
    }
}

@Composable
fun NativeOtpScreen(nav: NavHostController) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val mode = load(Unit) { NativeAuth.settings() }
    var phone by remember { mutableStateOf("") }
    var sentTo by remember { mutableStateOf<String?>(null) }
    var code by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var wait by remember { mutableIntStateOf(0) }
    var accepted by remember { mutableStateOf(false) }
    LaunchedEffect(wait) { if (wait > 0) { delay(1000); wait-- } }
    LaunchedEffect(mode.data) { if (mode.data?.otpLogin == false) nav.resetTo("welcome") }

    fun send(channel: String) {
        val number = sentTo ?: cleanIndianPhone(phone)
        if (busy || wait > 0 || number == null || !accepted) return
        scope.launch {
            busy = true
            try {
                if (!NativeAuth.settings().otpLogin) { nav.resetTo("welcome"); return@launch }
                Api.requestPhoneOtp(number, channel)
                sentTo = number
                code = ""
                wait = 30
                toast(ctx, "Verification code requested")
            } catch (e: CancellationException) { throw e }
            catch (e: Exception) { toast(ctx, "Could not request the code. Please retry.") }
            finally { busy = false }
        }
    }

    Page("Phone login") {
        if (mode.error != null) { ErrorBox(mode.error) { mode.reload() }; return@Page }
        if (mode.data?.otpLogin != true) { Loading(); return@Page }
        if (sentTo == null) {
            PhoneField(phone, { phone = it }, "Your mobile number")
            Row { Checkbox(accepted, { accepted = it }); Text("I accept the Terms and Privacy Policy.") }
            TextButton(onClick = { openUrl(ctx, Config.WEBSITE + "/terms.html") }) { Text("Read Terms") }
            TextButton(onClick = { openUrl(ctx, Config.WEBSITE + "/privacy.html") }) { Text("Read Privacy Policy") }
            PrimaryButton("Send verification code", enabled = !busy && accepted && cleanIndianPhone(phone) != null && wait == 0) { send("whatsapp") }
            MutedText("Delivery channel depends on the configured verification provider.")
        } else {
            MutedText("Enter the 6-digit code sent to your number ending in " + sentTo.orEmpty().takeLast(4))
            Field(code, { code = it.filter { ch -> ch.isDigit() }.take(6) }, "Verification code", keyboard = KeyboardType.Number)
            PrimaryButton("Verify & continue", enabled = !busy && code.length == 6) {
                scope.launch {
                    busy = true
                    try {
                        val number = sentTo ?: return@launch
                        Api.verifyPhoneOtp(number, code)
                        code = ""
                        routeAfterLogin(nav)
                    } catch (e: CancellationException) { throw e }
                    catch (e: Exception) {
                        if (Api.isLoggedIn) nav.resetTo("splash")
                        else toast(ctx, "Wrong or expired code, or connection failed. Try again.")
                    } finally { busy = false }
                }
            }
            if (wait > 0) MutedText("You can ask again in ${wait}s")
            else {
                TextButton(enabled = !busy, onClick = { send("sms") }) { Text("Send by SMS") }
                TextButton(enabled = !busy, onClick = { send("whatsapp") }) { Text("Try WhatsApp again") }
            }
            TextButton(enabled = !busy, onClick = { sentTo = null; code = "" }) { Text("Change number") }
        }
        SecondaryButton("Help & Support") { nav.go("support") }
    }
}

@Composable
fun NativePhoneVerifyScreen(nav: NavHostController) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val status = load(Unit) { NativeAuth.phoneStatus() }
    var phone by remember { mutableStateOf(AppState.me?.phone.orEmpty().filter { it.isDigit() }.takeLast(10)) }
    var pending by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var note by remember { mutableStateOf("") }
    LaunchedEffect(status.data) {
        if (status.data?.let { !it.getBoolean("required") || it.getBoolean("verified") } == true) {
            try { routeAfterLogin(nav) } catch (e: Exception) { note = "Could not load account. Check again." }
        }
    }
    LaunchedEffect(pending) {
        if (!pending) return@LaunchedEffect
        repeat(120) {
            delay(3000)
            try {
                if (!NativeAuth.phoneRequired()) {
                    routeAfterLogin(nav)
                    return@LaunchedEffect
                }
            } catch (e: CancellationException) { throw e }
            catch (_: Exception) { }
        }
        pending = false
        note = "Automatic checking stopped. Tap Check verification to try again."
    }
    Page("Verify mobile number") {
        if (status.error != null) ErrorBox(status.error) { status.reload() }
        PhoneField(phone, { phone = it }, "Your WhatsApp number")
        MutedText("Sphere opens WhatsApp with your own verification message. Send it, return here and check verification.")
        PrimaryButton("Verify on WhatsApp", enabled = !busy && !pending && status.data != null && cleanIndianPhone(phone) != null) {
            scope.launch {
                busy = true
                try {
                    val number = cleanIndianPhone(phone) ?: return@launch
                    val url = NativeAuth.beginPhoneVerification(number)
                    openUrl(ctx, url)
                    pending = true
                    note = "Waiting for confirmation from Sphere."
                } catch (e: CancellationException) { throw e }
                catch (e: Exception) { note = "Could not start verification. Contact support or try again." }
                finally { busy = false }
            }
        }
        TextButton(enabled = !busy, onClick = {
            scope.launch {
                busy = true
                try {
                    if (!NativeAuth.phoneRequired()) routeAfterLogin(nav)
                    else note = "Not verified yet. Send the verification message and try again."
                } catch (e: Exception) { note = "Could not check verification. Retry." }
                finally { busy = false }
            }
        }) { Text("Check verification") }
        if (pending) TextButton(onClick = { pending = false }) { Text("Start again") }
        if (note.isNotBlank()) MutedText(note)
        SecondaryButton("Help & Support") { nav.go("support") }
        NativeLogout(nav)
    }
}
