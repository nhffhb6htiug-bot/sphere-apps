package com.syahifilms.sphere.ui

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.navigation.NavHostController
import coil.compose.AsyncImage
import com.syahifilms.sphere.data.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

@Composable
fun ProfilePhotoControl(me:Profile) {
    val ctx=LocalContext.current
    val scope=rememberCoroutineScope()
    var busy by remember { mutableStateOf(false) }
    val picker=rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if(uri!=null && !busy) scope.launch {
            busy=true
            try { NativePortfolio.avatar(ctx,uri); AppState.refreshMe(); toast(ctx,"Profile photo updated") }
            catch(e:CancellationException){throw e}
            catch(e:Exception){toast(ctx,e.message ?: "Photo upload failed")}
            finally {busy=false}
        }
    }
    TextButton(enabled=!busy,onClick={picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))}) {
        Text(if(busy) "Uploading…" else "Change profile photo")
    }
}

@Composable
fun EditorCompletionPanel(me:Profile) {
    val items=load(me.id,me.portfolio,me.sample,me.bio) { NativePortfolio.items(me.id) }
    CardBox {
        Text("Profile completion",fontWeight=FontWeight.Bold)
        val rows=items.data
        if(items.error!=null) ErrorBox(items.error){items.reload()}
        else if(rows==null) Loading()
        else {
            Text(NativePortfolio.completion(me,rows),fontWeight=FontWeight.Bold)
            MutedText((if(me.bio.isNotBlank()) "✓" else "○")+" Bio")
            MutedText((if(me.skills.any{it.isNotBlank()}) "✓" else "○")+" Skills")
            MutedText((if(me.portfolio.isNotBlank() || me.sample.isNotBlank() || rows.any{it.video.isNotBlank()}) "✓" else "○")+" Portfolio / sample video")
        }
        MutedText("Separate from your verified badge.")
    }
}

@Composable
private fun PortfolioList(rows:List<PortfolioItem>,onRemove:((PortfolioItem)->Unit)?=null) {
    val ctx=LocalContext.current
    var filter by remember { mutableStateOf("All") }
    Dropdown("Category",filter,(listOf("All")+rows.map{it.displayCategory}).distinct()) {filter=it}
    val shown=rows.filter{filter=="All" || it.displayCategory==filter}
    if(shown.isEmpty()) MutedText("No work samples in this category.")
    shown.forEach { item ->
        CardBox {
            val photo=if(item.imagePath.isNotBlank()) Api.publicUrl("sphere-media",item.imagePath) else NativePortfolio.thumbnail(item.video)
            if(photo.isNotBlank()) AsyncImage(model=photo,contentDescription="Work sample",modifier=Modifier.fillMaxWidth().height(170.dp).clip(RoundedCornerShape(12.dp)),contentScale=ContentScale.Crop)
            Text(item.title,fontWeight=FontWeight.Bold)
            MutedText(item.displayCategory)
            if(item.video.isNotBlank() && NativePortfolio.validLink(item.video)) SecondaryButton("Watch video"){openUrl(ctx,item.video)}
            if(onRemove!=null) TextButton(onClick={onRemove(item)}){Text("Remove",color=Danger)}
        }
    }
}

@Composable
fun PublicPortfolioPanel(editorId:String) {
    val rows=load(editorId){NativePortfolio.items(editorId)}
    SectionTitle("Portfolio")
    when {
        rows.error!=null -> ErrorBox(rows.error){rows.reload()}
        rows.data==null -> Loading()
        else -> PortfolioList(rows.data)
    }
}

@Composable
fun NativePortfolioScreen(nav:NavHostController) {
    val me=AppState.me ?: return
    val ctx=LocalContext.current
    val scope=rememberCoroutineScope()
    val rows=load(me.id){NativePortfolio.items(me.id)}
    var title by remember { mutableStateOf("") }
    var category by remember { mutableStateOf(Config.CATEGORIES.first()) }
    var video by remember { mutableStateOf("") }
    var photo by remember { mutableStateOf<Uri?>(null) }
    var busy by remember { mutableStateOf(false) }
    var remove by remember { mutableStateOf<PortfolioItem?>(null) }
    val picker=rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()){photo=it}
    Page("Portfolio",onBack={nav.popBackStack()}) {
        if(me.role !in setOf("editor","admin")) { MutedText("Portfolio is available to editors."); return@Page }
        Avatar(me.avatarUrl,me.name,64.dp)
        Text(me.name,fontWeight=FontWeight.Bold)
        EditorCompletionPanel(me)
        SecondaryButton("Edit editor profile"){nav.go("editorDetails")}
        if(me.portfolio.isNotBlank() && NativePortfolio.validLink(me.portfolio)) SecondaryButton("Open portfolio link"){openUrl(ctx,me.portfolio)}
        if(me.sample.isNotBlank() && NativePortfolio.validLink(me.sample)) SecondaryButton("Open sample video"){openUrl(ctx,me.sample)}
        SectionTitle("Add work sample")
        CardBox {
            MutedText("Photos and YouTube links are visible to clients. Do not upload private client material without permission.")
            Field(title,{title=it.take(80)},"Title")
            Dropdown("Category",category,Config.CATEGORIES){category=it}
            Field(video,{video=it.take(1000)},"YouTube video link (optional)")
            if(photo!=null) AsyncImage(model=photo,contentDescription="Selected photo",modifier=Modifier.fillMaxWidth().height(150.dp),contentScale=ContentScale.Fit)
            SecondaryButton(if(photo==null) "Choose photo" else "Change photo"){if(!busy)picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))}
            if(photo!=null) TextButton(enabled=!busy,onClick={photo=null}){Text("Remove selected photo")}
            PrimaryButton(if(busy) "Uploading…" else "Add to portfolio",enabled=!busy && rows.data!=null && (rows.data?.size ?: 12)<12) {
                scope.launch {
                    busy=true
                    try {
                        NativePortfolio.add(ctx,title,category,photo,video.trim())
                        title="";video="";photo=null;rows.reload();toast(ctx,"Portfolio item added")
                    }catch(e:CancellationException){throw e}
                    catch(e:Exception){toast(ctx,e.message ?: "Could not add item");rows.reload()}
                    finally{busy=false}
                }
            }
        }
        SectionTitle("My work (${rows.data?.size ?: 0}/12)")
        when {
            rows.error!=null -> ErrorBox(rows.error){rows.reload()}
            rows.data==null -> Loading()
            else -> PortfolioList(rows.data){if(!busy)remove=it}
        }
    }
    remove?.let { item ->
        AlertDialog(onDismissRequest={remove=null},title={Text("Remove this work sample?")},text={Text(item.title)},
            confirmButton={TextButton(enabled=!busy,onClick={
                remove=null;scope.launch{
                    busy=true
                    try{NativePortfolio.remove(item.id);rows.reload()}
                    catch(e:CancellationException){throw e}
                    catch(e:Exception){toast(ctx,e.message ?: "Could not remove")}
                    finally{busy=false}
                }
            }){Text("Remove")}},dismissButton={TextButton(onClick={remove=null}){Text("Cancel")}})
    }
}
