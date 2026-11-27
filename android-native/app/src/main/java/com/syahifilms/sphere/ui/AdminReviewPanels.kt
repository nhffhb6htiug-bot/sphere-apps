package com.syahifilms.sphere.ui

import android.net.Uri
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import coil.request.ImageRequest
import coil.request.CachePolicy
import com.syahifilms.sphere.data.*
import kotlinx.coroutines.delay

@Composable
fun AdminProofPanel(owner:String,row:NativeAdmin.VerificationRow){
    var open by remember(row.id){mutableStateOf(false)}
    TextButton(onClick={open=true}){Text("Review proof / WhatsApp draft")}
    if(open){
        val ctx=LocalContext.current
        val loaded=load(owner,row.id){NativeAdmin.proof(owner,row.id)}
        var expired by remember(row.id){mutableStateOf(false)}
        val proof=loaded.data
        LaunchedEffect(proof?.screenshot){if(!proof?.screenshot.isNullOrBlank()){expired=false;delay(85000);expired=true}}
        AlertDialog(onDismissRequest={open=false},title={Text("Verification "+(row.number?.toString()?:"")+" · "+row.name)},
            text={Column(Modifier.heightIn(max=480.dp).verticalScroll(rememberScrollState())){
                if(loaded.error!=null)ErrorBox("Proof could not be loaded.",loaded.reload)
                else if(proof==null)Loading()
                else{
                    if(proof.screenshot.isNotBlank()&&!expired){
                        AsyncImage(model=ImageRequest.Builder(ctx).data(proof.screenshot)
                            .diskCachePolicy(CachePolicy.DISABLED).memoryCachePolicy(CachePolicy.DISABLED)
                            .networkCachePolicy(CachePolicy.DISABLED).build(),contentDescription="Private timeline proof",
                            modifier=Modifier.fillMaxWidth().height(220.dp),contentScale=ContentScale.Fit)
                    }else if(expired)TextButton(onClick={loaded.reload()}){Text("Refresh expired proof")}
                    else MutedText("No screenshot submitted.")
                    val video=Uri.parse(proof.video)
                    if(video.scheme=="https" && video.userInfo==null && video.host?.lowercase() in setOf("youtube.com","www.youtube.com","m.youtube.com","youtu.be","drive.google.com"))
                        SecondaryButton("Open promo video"){openUrl(ctx,proof.video)}
                    else if(proof.video.isNotBlank())MutedText("Video link uses an unsupported provider.")
                    val digits=proof.phone.filter{it in '0'..'9'}
                    val phone=when{
                        Regex("^[6-9][0-9]{9}$").matches(digits)->"91"+digits
                        Regex("^91[6-9][0-9]{9}$").matches(digits)->digits
                        else->""
                    }
                    if(phone.isNotBlank() && row.status!="rejected"){
                        val serial=row.number?.let{"Verification $it"}?:"Verification"
                        val name=proof.name.trim().take(100).ifBlank{"Editor"}
                        val draft="Hi $name,\n\n$serial — Sphere Editor Verification\n\nThis is the Sphere team (Syahi Films). We are contacting you about your editor verification request. Please reply when you are available for verification and keep your editing work/proof ready.\n\nThank you,\nSphere Team"
                        MutedText("Opens a draft only. Review before sending. Outreach is not marked automatically.")
                        SecondaryButton("Open WhatsApp draft"){openUrl(ctx,"https://wa.me/$phone?text="+Api.enc(draft))}
                    }
                }
            }},confirmButton={TextButton(onClick={open=false}){Text("Done")}})
    }
}

@Composable
fun AdminDetailPanel(owner:String,id:String,project:Boolean){
    var open by remember(id){mutableStateOf(false)}
    TextButton(onClick={open=true}){Text(if(project)"Project details" else "User details")}
    if(open){
        val data=load(owner,id,project){if(project)NativeAdmin.projectDetail(owner,id) else NativeAdmin.userDetail(owner,id)}
        AlertDialog(onDismissRequest={open=false},title={Text(if(project)"Project summary" else "Account summary")},
            text={Column(Modifier.heightIn(max=420.dp).verticalScroll(rememberScrollState())){
                if(data.error!=null)ErrorBox("Could not load details.",data.reload)
                else if(data.data==null)Loading()
                else data.data?.let{r->
                    val keys=if(project)listOf("status","review_state","flag","note","extensions","disputes","refunds") else listOf("name","role","verified","status","projects","strikes")
                    keys.forEach{k->KeyValue(k.replace('_',' '),r.str(k).ifBlank{"—"})}
                }
            }},confirmButton={TextButton(onClick={open=false}){Text("Done")}})
    }
}

@Composable
fun AdminActionPanel(actions:List<AdminReviewAction>){
    if(actions.isEmpty())return
    var menu by remember{mutableStateOf(false)}
    var action by remember{mutableStateOf<AdminReviewAction?>(null)}
    var reason by remember{mutableStateOf("")}
    var hours by remember{mutableStateOf("24")}
    var result by remember{mutableStateOf("")}
    Box{
        TextButton(onClick={menu=true}){Text("Management actions · dry-run")}
        DropdownMenu(expanded=menu,onDismissRequest={menu=false}){
            actions.forEach{a->DropdownMenuItem(text={Text(a.label)},onClick={menu=false;action=a;reason="";hours="24";result=""})}
        }
    }
    if(result.isNotBlank())MutedText(result)
    action?.let{a->
        AlertDialog(onDismissRequest={action=null},title={Text(a.label+" (simulation)")},text={Column{
            MutedText("No real user or project will be changed. No PIN or payment is needed for this local test.")
            if(a.reasonRequired)OutlinedTextField(value=reason,onValueChange={reason=it.take(500)},label={Text("Reason")},minLines=2)
            if(a.hoursRequired)OutlinedTextField(value=hours,onValueChange={hours=it.filter{c->c.isDigit()}.take(3)},label={Text("Extra hours (1–168)")},singleLine=true)
        }},confirmButton={TextButton(enabled=(!a.reasonRequired||reason.trim().length>=5)&&(!a.hoursRequired||hours.toIntOrNull()?.let{it in 1..168}==true),onClick={
            result=AdminDryRun.simulate(a,reason,hours.toIntOrNull());action=null;reason=""
        }){Text("Simulate")}},dismissButton={TextButton(onClick={action=null;reason=""}){Text("Cancel")}})
    }
}
