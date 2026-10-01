@file:OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)

package com.syahifilms.sphere.ui

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavHostController
import coil.compose.AsyncImage
import com.syahifilms.sphere.data.*

// ---------------- theme ----------------
val Blue = Color(0xFF1657FF)
val BlueSoft = Color(0xFFEEF3FF)
val Bg = Color(0xFFE8EDF9)
val Muted = Color(0xFF6B7280)
val Danger = Color(0xFFC62828)
val Success = Color(0xFF2E7D32)
val Orange = Color(0xFFE67E22)

@Composable
fun SphereTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = lightColorScheme(
            primary = Blue, onPrimary = Color.White, secondary = Blue,
            background = Bg, surface = Color.White, surfaceVariant = BlueSoft
        ),
        content = content
    )
}

// ---------------- global state ----------------
object AppState {
    var me by mutableStateOf<Profile?>(null)
    var mode by mutableStateOf("")   // editors can switch to "client" mode

    /** client | editor | admin — what the app shows right now */
    val role: String
        get() {
            val p = me ?: return ""
            return when {
                p.role == "editor" && mode == "client" -> "client"
                p.role == "admin" && mode == "editor" -> "editor"   // admins can also work as editors
                else -> p.role
            }
        }
    val clientSide: Boolean get() = role == "client" || role == "admin"
    val editorSide: Boolean get() = role == "editor"

    suspend fun refreshMe(): Profile? {
        val p = Repo.loadMe()
        Repo.loadFee()
        me = p
        mode = Api.getPref("mode_" + (p?.id ?: "")) ?: ""
        return p
    }

    fun switchMode(toClient: Boolean) {
        mode = if (toClient) "client" else "editor"
        Api.setPref("mode_" + (me?.id ?: ""), mode)
    }
}

// ---------------- navigation helpers ----------------
fun NavHostController.go(route: String) = navigate(route) { launchSingleTop = true }

fun NavHostController.resetTo(route: String) {
    val start = graph.id
    navigate(route) { popUpTo(start) { inclusive = true }; launchSingleTop = true }
}

suspend fun routeAfterLogin(nav: NavHostController) {
    val me = AppState.refreshMe()
    when {
        !Api.isLoggedIn -> nav.resetTo("welcome")
        Repo.needsOnboarding(me) -> nav.resetTo("chooseRole")
        else -> nav.resetTo("home")
    }
}

// ---------------- small helpers ----------------
fun toast(ctx: Context, msg: String) = Toast.makeText(ctx, msg, Toast.LENGTH_LONG).show()

fun openUrl(ctx: Context, url: String) {
    try { ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) } catch (e: Exception) { toast(ctx, "No app found to open this") }
}

fun dial(ctx: Context, phone: String) = openUrl(ctx, "tel:+91$phone")

fun whatsapp(ctx: Context, text: String) =
    openUrl(ctx, "https://wa.me/${Config.WHATSAPP}?text=" + Uri.encode(text))

fun prettyDate(iso: String): String = try {
    val d = java.time.LocalDate.parse(iso.take(10))
    "${d.dayOfMonth} ${d.month.name.take(3).lowercase().replaceFirstChar { it.uppercase() }} ${d.year}"
} catch (e: Exception) { iso.take(10) }

// ---------------- loading pattern ----------------
class Loaded<T>(val data: T?, val error: String?, val reload: () -> Unit)

@Composable
fun <T> load(vararg keys: Any?, block: suspend () -> T): Loaded<T> {
    var data by remember(*keys) { mutableStateOf<T?>(null) }
    var error by remember(*keys) { mutableStateOf<String?>(null) }
    var tick by remember { mutableIntStateOf(0) }
    LaunchedEffect(tick, *keys) {
        error = null
        try { data = block() } catch (e: Exception) { error = e.message ?: "Something went wrong" }
    }
    return Loaded(data, error) { tick++ }
}

// ---------------- layout ----------------
@Composable
fun SphereTopBar(title: String, onBack: (() -> Unit)? = null, actions: @Composable RowScope.() -> Unit = {}) {
    TopAppBar(
        title = { Text(title, fontWeight = FontWeight.Bold, maxLines = 1) },
        navigationIcon = {
            if (onBack != null) IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") }
        },
        actions = actions,
        colors = TopAppBarDefaults.topAppBarColors(containerColor = Bg)
    )
}

/** Standard page: top bar + scrolling column (+ optional bottom bar). */
@Composable
fun Page(
    title: String,
    onBack: (() -> Unit)? = null,
    bottomBar: @Composable () -> Unit = {},
    actions: @Composable RowScope.() -> Unit = {},
    content: @Composable ColumnScope.() -> Unit
) {
    Scaffold(
        containerColor = Bg,
        topBar = { SphereTopBar(title, onBack, actions) },
        bottomBar = bottomBar
    ) { pad ->
        Column(
            Modifier.padding(pad).fillMaxSize().verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp, vertical = 8.dp),
            content = content
        )
    }
}

@Composable
fun MainBottomBar(nav: NavHostController, current: String) {
    val items = listOf<Triple<String, String, ImageVector>>(
        Triple("home", "Home", Icons.Filled.Home),
        Triple("chats", "Chat", Icons.Filled.Email),
        Triple("jobs", "Jobs", Icons.AutoMirrored.Filled.List),
        Triple("profile", "Profile", Icons.Filled.Person)
    )
    NavigationBar(containerColor = Color.White) {
        items.forEach { (route, label, icon) ->
            NavigationBarItem(
                selected = current == route,
                onClick = { if (current != route) nav.navigate(route) { popUpTo("home"); launchSingleTop = true } },
                icon = { Icon(icon, label) },
                label = { Text(label) }
            )
        }
    }
}

@Composable
fun CardBox(onClick: (() -> Unit)? = null, border: Color? = null, content: @Composable ColumnScope.() -> Unit) {
    var m = Modifier.fillMaxWidth().padding(vertical = 6.dp).clip(RoundedCornerShape(16.dp))
    if (onClick != null) m = m.clickable { onClick() }
    Card(
        modifier = m,
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(containerColor = Color.White),
        border = border?.let { androidx.compose.foundation.BorderStroke(1.5.dp, it) }
    ) { Column(Modifier.padding(14.dp), content = content) }
}

@Composable
fun SectionTitle(text: String) {
    Text(text, fontWeight = FontWeight.Bold, fontSize = 17.sp, modifier = Modifier.padding(top = 14.dp, bottom = 6.dp))
}

@Composable
fun MutedText(text: String, size: Int = 13) { Text(text, color = Muted, fontSize = size.sp) }

@Composable
fun Loading() {
    Box(Modifier.fillMaxWidth().padding(40.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
}

@Composable
fun ErrorBox(msg: String, onRetry: () -> Unit) {
    CardBox(border = Danger) {
        Text(msg, color = Danger)
        TextButton(onClick = onRetry) { Text("Try again") }
    }
}

@Composable
fun Avatar(url: String, name: String, size: Dp = 48.dp) {
    if (url.isBlank()) {
        Box(
            Modifier.size(size).clip(CircleShape).background(BlueSoft),
            contentAlignment = Alignment.Center
        ) { Text(name.trim().take(1).uppercase().ifBlank { "?" }, color = Blue, fontWeight = FontWeight.Bold, fontSize = (size.value / 2.4).sp) }
    } else {
        AsyncImage(
            model = url, contentDescription = null, contentScale = ContentScale.Crop,
            modifier = Modifier.size(size).clip(CircleShape).background(BlueSoft)
        )
    }
}

@Composable
fun StatusChip(status: String, expired: Boolean = false) {
    val (label, color) = when {
        expired -> "expired" to Color(0xFF9AA0A6)
        status == "open" -> "open" to Color(0xFF9AA0A6)
        status == "approved" || status == "closed" -> status to Success
        status == "refunded" -> status to Orange
        else -> status to Blue
    }
    Text(
        label, color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold,
        modifier = Modifier.clip(RoundedCornerShape(10.dp)).background(color).padding(horizontal = 8.dp, vertical = 3.dp)
    )
}

@Composable
fun VerifiedBadge(code: String) {
    Text(
        "✔ $code", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold,
        modifier = Modifier.clip(RoundedCornerShape(10.dp)).background(Blue).padding(horizontal = 8.dp, vertical = 3.dp)
    )
}

@Composable
fun PrimaryButton(text: String, enabled: Boolean = true, onClick: () -> Unit) {
    Button(
        onClick = onClick, enabled = enabled,
        modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp).height(50.dp),
        shape = RoundedCornerShape(25.dp)
    ) { Text(text, fontWeight = FontWeight.Bold) }
}

@Composable
fun SecondaryButton(text: String, color: Color = Blue, onClick: () -> Unit) {
    OutlinedButton(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp).height(48.dp),
        shape = RoundedCornerShape(24.dp),
        border = androidx.compose.foundation.BorderStroke(1.dp, color)
    ) { Text(text, color = color, fontWeight = FontWeight.SemiBold) }
}

@Composable
fun Field(
    value: String, onChange: (String) -> Unit, label: String,
    placeholder: String = "", keyboard: KeyboardType = KeyboardType.Text, minLines: Int = 1
) {
    OutlinedTextField(
        value = value, onValueChange = onChange,
        label = { Text(label) },
        placeholder = { if (placeholder.isNotEmpty()) Text(placeholder) },
        keyboardOptions = KeyboardOptions(keyboardType = keyboard),
        minLines = minLines,
        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
        shape = RoundedCornerShape(12.dp)
    )
}

/** Mobile number with a fixed +91 in front (10 digits only). */
@Composable
fun PhoneField(value: String, onChange: (String) -> Unit, label: String = "Mobile number") {
    OutlinedTextField(
        value = value,
        onValueChange = { v -> onChange(v.filter { it.isDigit() }.take(10)) },
        label = { Text(label) },
        prefix = { Text("+91 ", fontWeight = FontWeight.Bold) },
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone),
        singleLine = true,
        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
        shape = RoundedCornerShape(12.dp)
    )
}

@Composable
fun Dropdown(label: String, value: String, options: List<String>, onSelect: (String) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxWidth().padding(vertical = 4.dp)) {
        MutedText(label, 12)
        Box {
            OutlinedButton(
                onClick = { open = true },
                modifier = Modifier.fillMaxWidth().height(52.dp),
                shape = RoundedCornerShape(12.dp)
            ) {
                Text(value.ifBlank { "Choose" }, color = Color.Black, modifier = Modifier.weight(1f))
                Icon(Icons.Filled.ArrowDropDown, null, tint = Muted)
            }
            DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
                options.forEach { o -> DropdownMenuItem(text = { Text(o) }, onClick = { onSelect(o); open = false }) }
            }
        }
    }
}

/** Tap-to-select chips (choose one or more). */
@Composable
fun MultiPick(label: String, options: List<String>, selected: List<String>, onChange: (List<String>) -> Unit) {
    Column(Modifier.fillMaxWidth().padding(vertical = 6.dp)) {
        MutedText(label, 12)
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            options.forEach { o ->
                val on = o in selected
                FilterChip(
                    selected = on,
                    onClick = { onChange(if (on) selected - o else selected + o) },
                    label = { Text(o) }
                )
            }
        }
    }
}

/** Available work with a filter: All / My categories / each category. */
@Composable
fun WorkList(me: Profile, jobs: List<Job>, onOpen: (Job) -> Unit) {
    var filter by remember { mutableStateOf("All") }
    Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        (listOf("All", "My categories") + Config.CATEGORIES).forEach { c ->
            FilterChip(selected = filter == c, onClick = { filter = c }, label = { Text(c) })
        }
    }
    val list = jobs.filter { j ->
        when (filter) {
            "All" -> true
            "My categories" -> j.category in me.categories
            else -> j.category == filter
        }
    }
    if (list.isEmpty()) MutedText("No open jobs ${if (filter == "All") "" else "in $filter "}right now. We will notify you when new work is posted.")
    list.forEach { j -> JobCardUi(j) { onOpen(j) } }
}

@Composable
fun KeyValue(key: String, value: String) {
    Row(Modifier.fillMaxWidth().padding(vertical = 5.dp)) {
        Text(key, color = Muted, fontSize = 13.sp, modifier = Modifier.weight(1f))
        Text(value, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
    }
}

/** ₹29 verification fee: pay by UPI to the number, send the screenshot on WhatsApp. */
@Composable
fun VerifyFeeCard(me: Profile) {
    val ctx = androidx.compose.ui.platform.LocalContext.current
    CardBox(border = Blue) {
        Text("💳 Verification fee: ₹${Config.VERIFY_FEE}", fontWeight = FontWeight.Bold)
        Spacer(Modifier.height(6.dp))
        MutedText("1. Pay ₹${Config.VERIFY_FEE} with any UPI app (button below)")
        MutedText("2. Send the payment screenshot on WhatsApp to ${Config.FEE_PHONE}")
        MutedText("3. Our team calls you and gives your ✔ tick")
        Spacer(Modifier.height(8.dp))
        PrimaryButton("Pay ₹${Config.VERIFY_FEE} now") {
            openUrl(ctx, "upi://pay?pa=" + Uri.encode(Config.FEE_UPI) + "&pn=" + Uri.encode(Config.FEE_UPI_NAME) +
                "&am=${Config.VERIFY_FEE}&cu=INR&tn=" + Uri.encode("Sphere verification"))
        }
        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
            androidx.compose.foundation.Image(
                androidx.compose.ui.res.painterResource(com.syahifilms.sphere.R.drawable.fee_qr), "UPI QR code",
                Modifier.width(180.dp).clip(RoundedCornerShape(12.dp))
            )
            MutedText("UPI ID: ${Config.FEE_UPI} · ${Config.FEE_UPI_NAME}", 12)
        }
        Spacer(Modifier.height(8.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            AssistChip(onClick = {
                val cm = ctx.getSystemService(Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager
                cm.setPrimaryClip(android.content.ClipData.newPlainText("UPI ID", Config.FEE_UPI))
                toast(ctx, "UPI ID copied: ${Config.FEE_UPI}")
            }, label = { Text("📋 Copy UPI ID") })
            AssistChip(onClick = {
                openUrl(ctx, "https://wa.me/91${Config.FEE_PHONE}?text=" + Uri.encode(
                    "Hi Sphere team, I paid the ₹${Config.VERIFY_FEE} verification fee. My Sphere account: ${me.email}. Screenshot attached."))
            }, label = { Text("💬 Send screenshot") })
        }
    }
}

@Composable
fun SupportCard() {
    val ctx = androidx.compose.ui.platform.LocalContext.current
    CardBox(border = Blue) {
        Text("🆘 Sphere Support", fontWeight = FontWeight.Bold)
        MutedText("Problem with a payment, a delivery or another user? Call or WhatsApp us. (10 AM – 7 PM, Mon–Sat)", 12)
        Spacer(Modifier.height(8.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Config.SUPPORT_PHONES.forEach { p ->
                AssistChip(onClick = { dial(ctx, p) }, label = { Text("📞 $p") })
            }
        }
        AssistChip(onClick = { whatsapp(ctx, "Hi Sphere Support, I need help with:") }, label = { Text("💬 WhatsApp") })
    }
}
