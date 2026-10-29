package com.syahifilms.sphere.ui

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.platform.LocalContext
import androidx.navigation.NavHostController
import com.syahifilms.sphere.data.Api
import com.syahifilms.sphere.data.Profile
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.util.UUID

/** Uses the same Supabase RPC, fixed ranks and private screenshot bucket as Sphere Web. */
data class NativeEditorOffer(
    val rank: Int?,
    val isFree: Boolean,
    val bannerVisible: Boolean,
    val remaining: Int,
    val proofVideo: String = "",
    val proofScreenshot: String = "",
    val feeStatus: String = ""
)

suspend fun fetchNativeEditorOffer(): NativeEditorOffer {
    val offer = JSONObject(Api.rpc("sp_editor_offer_status", JSONObject()))
    val myId = Api.userId ?: throw IllegalStateException("Please log in")
    val p = Api.selectOne("profiles?id=eq.$myId&select=proof_video_url,proof_screenshot_path,verification_fee_status")
    return NativeEditorOffer(
        rank = offer.optInt("editor_rank", 0).takeIf { it in 1..50 },
        isFree = offer.optBoolean("is_free", false),
        bannerVisible = offer.optBoolean("show_banner", false),
        remaining = offer.optInt("remaining", 0).coerceAtLeast(0),
        proofVideo = p?.takeUnless { it.isNull("proof_video_url") }?.optString("proof_video_url") ?: "",
        proofScreenshot = p?.takeUnless { it.isNull("proof_screenshot_path") }?.optString("proof_screenshot_path") ?: "",
        feeStatus = p?.takeUnless { it.isNull("verification_fee_status") }?.optString("verification_fee_status") ?: ""
    )
}

private fun editorRankSuffix(n: Int): String = when {
    n % 100 in 11..13 -> "th"
    n % 10 == 1 -> "st"
    n % 10 == 2 -> "nd"
    n % 10 == 3 -> "rd"
    else -> "th"
}

@Composable
fun NativeEditorOfferBanner(offer: NativeEditorOffer?, nav: NavHostController) {
    if (offer?.isFree != true || !offer.bannerVisible) return
    val rank = offer.rank ?: return
    GlassPanel(Modifier.fillMaxWidth(), onClick = { nav.go("verification") }) {
        Text("🎉 First 50 Editors — FREE Verification",
            fontWeight = FontWeight.ExtraBold, color = WebsiteColors.Plum, fontSize = 15.sp)
        Text(buildAnnotatedString {
            pushStyle(SpanStyle(textDecoration = TextDecoration.LineThrough, color = WebsiteColors.Muted))
            append("₹29")
            pop()
            pushStyle(SpanStyle(color = Color(0xFF15803D), fontWeight = FontWeight.ExtraBold))
            append("  FREE")
            pop()
            append("  ·  Promo video + editing screenshot")
        }, fontSize = 12.sp, modifier = Modifier.padding(vertical = 5.dp))
        Text("You are the ${rank}${editorRankSuffix(rank)} editor! · ${offer.remaining} slots left",
            fontSize = 12.sp, color = WebsiteColors.Plum, fontWeight = FontWeight.SemiBold)
        Spacer(Modifier.height(5.dp))
        Text("Submit your proof  →", color = WebsiteColors.Violet,
            fontSize = 13.sp, fontWeight = FontWeight.Bold)
    }
}

@Composable
fun NativeEditorVerificationFee(me: Profile, offer: NativeEditorOffer?, failed: Boolean = false) {
    if (offer == null) {
        CardBox(border = Blue) {
            Text("Verification fee", fontWeight = FontWeight.Bold)
            MutedText(if (failed) "Could not check your first-50 offer. Reopen this screen to retry before paying."
                      else "Checking your first-50 free eligibility…")
        }
        return
    }
    if (!offer.isFree) {
        VerifyFeeCard(me)
        return
    }
    CardBox(border = Success) {
        Text(buildAnnotatedString {
            append("💳 Verification fee: ")
            pushStyle(SpanStyle(textDecoration = TextDecoration.LineThrough, color = Muted))
            append("₹29")
            pop()
            pushStyle(SpanStyle(fontWeight = FontWeight.ExtraBold, color = Color(0xFF15803D)))
            append("  FREE")
            pop()
        }, fontSize = 18.sp, fontWeight = FontWeight.Bold)
        MutedText("Only first 50 editors · Editor #${offer.rank ?: "—"}", 12)
        Spacer(Modifier.height(6.dp))
        MutedText(if (offer.feeStatus == "confirmed") "Your previous payment is already recorded. This promotion does not refund past payments."
            else "No ₹29 payment needed. Send the Sphere promo video and your editing-timeline screenshot.")
        Spacer(Modifier.height(6.dp))
        Text("${if (offer.proofVideo.isNotBlank()) "✅" else "⬜"} Promo video    ${if (offer.proofScreenshot.isNotBlank()) "✅" else "⬜"} Screenshot",
            fontSize = 13.sp)
        if (offer.proofVideo.isNotBlank() && offer.proofScreenshot.isNotBlank())
            Text("Our team will review your work before issuing the verified badge.", color = Success, fontSize = 12.sp)
    }
}

@Composable
fun NativeEditorProofPanel(offer: NativeEditorOffer?, onRefresh: () -> Unit) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var videoLink by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var selectedUri by remember { mutableStateOf<Uri?>(null) }
    val pickScreenshot = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        selectedUri = uri
    }

    CardBox(border = Blue) {
        Text("🎬 Sphere promo video", fontWeight = FontWeight.Bold)
        MutedText("Create a 20–60 second promo video and share a YouTube (unlisted) or Google Drive link.", 12)
        if (offer?.proofVideo?.isNotBlank() == true)
            Text("✅ Video received — you can send a replacement link", fontSize = 12.sp, color = Success)
        OutlinedTextField(videoLink, onValueChange = { videoLink = it },
            label = { Text("Promo video URL") }, singleLine = true,
            modifier = Modifier.fillMaxWidth())
        Spacer(Modifier.height(8.dp))
        Button(onClick = {
            val link = videoLink.trim()
            if (!link.startsWith("https://")) { toast(ctx, "Paste the full https:// video link"); return@Button }
            busy = true
            scope.launch {
                try {
                    Api.rpc("sp_submit_proof_video", JSONObject().put("p_url", link))
                    if (offer?.isFree == true) Api.rpc("sp_claim_free_verification", JSONObject())
                    videoLink = ""
                    toast(ctx, "Promo video submitted ✅")
                    onRefresh()
                } catch (e: Exception) { toast(ctx, e.message ?: "Could not send promo video") }
                finally { busy = false }
            }
        }, enabled = !busy && videoLink.isNotBlank()) {
            Text(if (busy) "Submitting…" else "Send promo video")
        }
    }
    if (offer?.isFree == true) {
        CardBox(border = Blue) {
            Text("📸 Editing-timeline screenshot", fontWeight = FontWeight.Bold)
            MutedText("Required for first-50 FREE verification. Upload a PNG, JPG or WebP screenshot (max 4 MB). Only the Sphere verification team can review it.", 12)
            if (offer.proofScreenshot.isNotBlank())
                Text("✅ Screenshot received", color = Success, fontSize = 12.sp)
            Spacer(Modifier.height(8.dp))
            SecondaryButton("Choose screenshot") { pickScreenshot.launch("image/*") }
            if (selectedUri != null) MutedText("Screenshot selected", 12)
            Spacer(Modifier.height(6.dp))
            Button(onClick = {
                val uri = selectedUri ?: return@Button
                busy = true
                scope.launch {
                    try {
                        val mime = ctx.contentResolver.getType(uri) ?: ""
                        val ext = when (mime) {
                            "image/jpeg" -> "jpg"
                            "image/png" -> "png"
                            "image/webp" -> "webp"
                            else -> throw IllegalArgumentException("Select PNG, JPG or WebP")
                        }
                        val bytes = withContext(Dispatchers.IO) {
                            ctx.contentResolver.openInputStream(uri)?.use { input ->
                                val out = ByteArrayOutputStream()
                                val buffer = ByteArray(8192)
                                while (true) {
                                    val read = input.read(buffer)
                                    if (read == -1) break
                                    if (out.size() + read > 4 * 1024 * 1024) throw IllegalArgumentException("Image must be under 4 MB")
                                    out.write(buffer, 0, read)
                                }
                                out.toByteArray()
                            } ?: throw IllegalArgumentException("Cannot open screenshot")
                        }
                        if (bytes.isEmpty()) throw IllegalArgumentException("Empty image")
                        val id = Api.userId ?: throw IllegalStateException("Please log in")
                        val path = "$id/${UUID.randomUUID()}.$ext"
                        Api.uploadBytes("sphere-editor-proof", path, bytes, mime)
                        Api.rpc("sp_submit_proof_screenshot", JSONObject().put("p_path", path))
                        Api.rpc("sp_claim_free_verification", JSONObject())
                        selectedUri = null
                        toast(ctx, "Screenshot received ✅ No ₹29 fee for your slot")
                        onRefresh()
                    } catch (e: Exception) { toast(ctx, e.message ?: "Screenshot failed") }
                    finally { busy = false }
                }
            }, enabled = selectedUri != null && !busy) {
                Text(if (busy) "Uploading…" else "Upload screenshot")
            }
        }
    }
}
