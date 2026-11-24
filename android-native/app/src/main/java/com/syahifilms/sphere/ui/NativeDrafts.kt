package com.syahifilms.sphere.ui

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.navigation.NavHostController
import com.syahifilms.sphere.data.*
import kotlinx.coroutines.launch

@Composable
fun NativeDraftsScreen(nav: NavHostController) {
    val me = AppState.me ?: return
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val drafts = load(me.id) { Repo.drafts() }
    var delete by remember { mutableStateOf<JobDraft?>(null) }
    var busy by remember { mutableStateOf(false) }
    Page("Saved drafts", onBack = { nav.popBackStack() }) {
        val list = drafts.data
        when {
            drafts.error != null -> ErrorBox(drafts.error) { drafts.reload() }
            list == null -> Loading()
            list.isEmpty() -> MutedText("No saved drafts")
            else -> list.forEach { d ->
                CardBox {
                    Text(d.data.str("title").ifBlank { d.data.str("category").ifBlank { "Untitled draft" } }, fontWeight = FontWeight.Bold)
                    MutedText(d.data.str("description").take(180))
                    MutedText("Updated ${prettyDate(d.updatedAt)}", 12)
                    Row {
                        TextButton(enabled = !busy, onClick = { nav.go("draft/${d.id}") }) { Text("Continue editing") }
                        TextButton(enabled = !busy, onClick = { delete = d }) { Text("Delete") }
                    }
                }
            }
        }
    }
    val selected = delete
    if (selected != null) AlertDialog(onDismissRequest = { delete = null }, title = { Text("Delete draft?") },
        text = { Text("Only the saved draft will be removed.") },
        confirmButton = { TextButton(enabled = !busy, onClick = { delete = null; scope.launch {
            busy = true
            try { Repo.deleteDraft(selected.id); drafts.reload() } catch (e: Exception) { toast(ctx, e.message ?: "Could not delete draft") }
            finally { busy = false }
        } }) { Text("Delete") } }, dismissButton = { TextButton(onClick = { delete = null }) { Text("Cancel") } })
}
