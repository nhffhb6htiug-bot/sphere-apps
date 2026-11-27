package com.syahifilms.sphere.ui

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import android.widget.VideoView
import androidx.compose.animation.core.*
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import com.syahifilms.sphere.data.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.time.Instant
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter

private fun instant(s:String)=runCatching{OffsetDateTime.parse(s).toInstant()}.getOrNull()
private fun date(s:String)=instant(s)?.atZone(ZoneId.of("Asia/Kolkata"))?.format(DateTimeFormatter.ofPattern("dd MMM, HH:mm 'IST'"))?:s.ifBlank{"—"}
private fun timer(seconds:Long):String {
    val n=seconds.coerceAtLeast(0)
    return "%02d:%02d:%02d".format(n/3600,n/60%60,n%60)
}
private fun link(s:String)=s.isNotBlank() && s.length<=500 && NativePortfolio.validLink(s)

@Composable
fun NativeDeliveryPanel(job:Job,me:Profile,onRefresh:()->Unit) {
    val ctx=LocalContext.current
    val scope=rememberCoroutineScope()
    val client=job.clientId==me.id
    val editor=job.assignedEditor==me.id
    if(!client && !editor)return
    val loaded=load(job.id,job.status,job.reviewState){NativeDelivery.load(job)}
    var busy by remember {mutableStateOf(false)}
    var error by remember {mutableStateOf("")}
    var confirm by remember {mutableStateOf<Pair<String,suspend ()->Unit>?>(null)}
    var video by remember {mutableStateOf<String?>(null)}
    var progress by remember {mutableStateOf("")}
    var selectedPreview by remember(job.id){mutableStateOf<Uri?>(null)}
    var selectedChanges by remember(job.id){mutableStateOf<List<Uri>>(emptyList())}
    var attachmentIds by remember(job.id){mutableStateOf<List<String>>(emptyList())}
    val previewPicker=rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()){selectedPreview=it}
    val changePicker=rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()){uris->
        if(uris.size+attachmentIds.size<=ProjectMedia.MAX_FILES)selectedChanges=uris else error="Choose up to five attachments."
    }
    var now by remember {mutableLongStateOf(Instant.now().epochSecond)}
    LaunchedEffect(job.id){while(true){delay(1000);now=Instant.now().epochSecond}}
    fun act(block:suspend ()->Unit){
        if(busy)return
        scope.launch{
            busy=true;error=""
            try{block();loaded.reload();onRefresh()}
            catch(e:CancellationException){throw e}
            catch(e:Exception){error=e.message?:"Action not confirmed. Refresh before retrying."}
            finally{busy=false;progress=""}
        }
    }
    SectionTitle("Project workflow")
    TextButton(enabled=!busy,onClick={loaded.reload();onRefresh()}){Text("Refresh status")}
    if(loaded.error!=null){ErrorBox(loaded.error){loaded.reload()};return}
    val d=loaded.data
    if(d==null){Loading();return}
    val w=d.work
    val phase=w?.str("phase").orEmpty()
    val active=job.status=="in-progress"
    val pendingExtension=d.extensions.firstOrNull{it.str("status")=="pending"}
    val due=instant(w?.str("due_at").orEmpty())?.epochSecond
    val grace=w?.optInt("grace_hours",0)?:0
    if(w!=null && active){
        CardBox{
            Text("Delivery clock",fontWeight=FontWeight.Bold)
            KeyValue("Stage",phase)
            KeyValue("Deadline",date(w.str("due_at")))
            if(w.optInt("extended_hours")>0)KeyValue("Extra time",w.optInt("extended_hours").toString()+" hours")
            KeyValue("Grace period","$grace hours")
            if(phase=="active" && due!=null){
                val graceEnd=due+grace*3600L
                val message=when{now<due->"Time left: "+timer(due-now);now<graceEnd->"Grace time left: "+timer(graceEnd-now);else->"Late by: "+timer(now-graceEnd)}
                Text(message,fontWeight=FontWeight.Bold)
                d.setting("late_fee_per_hour")?.let{MutedText("Late deduction: ₹$it/hour after grace. Actual settlement is calculated by the server.")}
            }
        }
        if(phase=="active"){
            var hours by remember{mutableStateOf("12")}
            var reason by remember{mutableStateOf("")}
            CardBox{
                Text("Deadline extension",fontWeight=FontWeight.Bold)
                if(pendingExtension!=null){
                    Text("Requested: +"+pendingExtension.optInt("hours")+" hours")
                    MutedText(pendingExtension.str("reason"))
                    if(client){
                        PrimaryButton("Approve extension",enabled=!busy){confirm="Approve additional time?" to {NativeDelivery.answerTime(job,true)}}
                        SecondaryButton("Decline extension"){if(!busy)confirm="Decline the request?" to {NativeDelivery.answerTime(job,false)}}
                    }else MutedText("Waiting for the client.")
                }else{
                    Dropdown("Extra hours",hours,if(client)listOf("2","6","12","24","48") else listOf("2","6","12","24","48","72")){hours=it}
                    Field(reason,{reason=it.take(300)},if(client)"Optional note" else "Reason",minLines=2)
                    PrimaryButton(if(client)"Give more time" else "Request extension",enabled=!busy && (client||reason.trim().length>=5)){
                        confirm="Confirm deadline request?" to {if(client)NativeDelivery.giveTime(job,hours.toInt(),reason.trim()) else NativeDelivery.requestTime(job,hours.toInt(),reason.trim())}
                    }
                }
            }
        }
    }
    if(d.previews.isNotEmpty()){
        CardBox{
            Text("Preview versions",fontWeight=FontWeight.Bold)
            d.previews.forEach{f->
                KeyValue("Preview v"+f.optInt("version"),date(f.str("created_at")))
                if(f.str("note").isNotBlank())MutedText(f.str("note"))
                SecondaryButton("Watch v"+f.optInt("version")){
                    if(!busy)scope.launch{
                        busy=true
                        try{
                            if(f.str("source")=="upload")video=Api.deliveryPreviewUrl(job.id,f.str("storage_path"))
                            else if(link(f.str("external_url"))) {
                                val u=Uri.parse(f.str("external_url"))
                                if(u.path.orEmpty().endsWith(".mp4",true)||u.path.orEmpty().endsWith(".webm",true))video=u.toString()
                                else {error="External provider cannot play natively here. Open only the pre-watermarked preview.";openUrl(ctx,u.toString())}
                            }
                        }catch(e:CancellationException){throw e}
                        catch(e:Exception){error="Preview unavailable"}
                        finally{busy=false}
                    }
                }
            }
            if(client && active && phase=="preview" && !d.openRevision && !d.openChange){
                val sent=instant(w?.str("preview_at").orEmpty())
                val approved=instant(w?.str("preview_approved_at").orEmpty())
                if(sent!=null && (approved==null || approved.isBefore(sent)))PrimaryButton("Approve preview",enabled=!busy){
                    confirm="Approve this preview?" to {Repo.approvePreview(job)}
                }else MutedText("Preview approved.")
            }
        }
    }
    if(editor && active && phase in setOf("active","preview")){
        var url by remember{mutableStateOf("")};var note by remember{mutableStateOf("")};var marked by remember{mutableStateOf(false)}
        CardBox{
            Text("Send watermarked preview",fontWeight=FontWeight.Bold)
            val minutes=d.setting("preview_max_minutes")
            val maxMb=d.setting("file_max_mb")?.coerceAtMost(50)
            MutedText("Select a video to export a separate MP4 with a moving SPHERE watermark. Your original will not be uploaded.")
            if(minutes!=null && maxMb!=null)MutedText("Limit: $minutes minutes, $maxMb MB per file.")
            TextButton(enabled=!busy,onClick={previewPicker.launch(arrayOf("video/*"))}){Text(if(selectedPreview==null)"Choose preview video" else "Change selected video")}
            if(selectedPreview!=null) {
                MutedText("Video selected")
                TextButton(enabled=!busy,onClick={selectedPreview=null}){Text("Remove video")}
            }
            PrimaryButton("Encode & upload preview",enabled=!busy && selectedPreview!=null && minutes!=null && maxMb!=null){
                val uri=selectedPreview
                if(uri!=null && minutes!=null && maxMb!=null) confirm="Export and submit watermarked preview?" to {
                    val original=ProjectMedia.stage(ctx,uri,true)
                    try {
                        val encoded=PreviewEncoder.encode(ctx,original,minutes,maxMb){p->progress=p}
                        try {
                            progress="Uploading watermarked preview…"
                            NativeDelivery.uploadEncodedPreview(job,encoded,note.trim())
                            selectedPreview=null;note=""
                        } finally {encoded.media.file.delete()}
                    } finally {original.file.delete()}
                }
            }
            MutedText("Or use an already watermarked HTTPS link.")
            Field(url,{url=it.take(500)},"HTTPS preview link")
            Field(note,{note=it.take(500)},"Optional note")
            Row(verticalAlignment=Alignment.CenterVertically){Checkbox(marked,{marked=it});Text("Video already has the SPHERE watermark")}
            PrimaryButton("Submit preview",enabled=!busy && marked && link(url)){confirm="Send this preview to the client?" to {NativeDelivery.preview(job,url.trim(),note.trim());url="";note="";marked=false}}
        }
    }
    if(active || d.revisions.isNotEmpty() || d.changes.isNotEmpty()){
        CardBox{
            Text("Revisions & changes",fontWeight=FontWeight.Bold)
            val free=d.setting("free_revisions");val fee=d.setting("revision_fee")
            if(free!=null)KeyValue("Free revisions used","${minOf(d.freeUsed,free)}/$free")
            if(free!=null && fee!=null)KeyValue("Next revision",if(d.freeUsed<free)"Free" else "₹$fee")
            d.revisions.forEach{r->
                Text("Revision #"+r.optInt("number")+" · "+r.str("status"),fontWeight=FontWeight.SemiBold)
                MutedText(r.str("notes"))
                if(r.str("new_due_at").isNotBlank())MutedText("Due: "+date(r.str("new_due_at")))
                if(r.str("status")=="awaiting_payment"){
                    MutedText("Fee: "+money(r.numOrNull("fee"))+" · Payment unavailable in this preview.")
                    if(client && active)TextButton(enabled=!busy,onClick={confirm="Cancel unpaid revision?" to {NativeDelivery.cancelRevision(job,r.str("id"))}}){Text("Cancel revision")}
                }
            }
            if(client && active && phase=="preview" && !d.openRevision && free!=null && fee!=null){
                var notes by remember{mutableStateOf("")}
                Field(notes,{notes=it.take(2000)},"What should change?",minLines=3)
                PrimaryButton("Request revision",enabled=!busy && notes.trim().length>=5){
                    confirm=(if(d.freeUsed<free)"Request free revision?" else "Create unpaid revision request of ₹$fee? No payment will be made.") to {NativeDelivery.revision(job,notes.trim());notes=""}
                }
            }
            d.changes.forEach{r->
                Text("Change request · "+r.str("status"),fontWeight=FontWeight.Bold)
                MutedText(r.str("details"));KeyValue("Extra price",money(r.numOrNull("extra_price")));KeyValue("Extra time",r.optInt("extra_hours").toString()+" hours")
                if(link(r.str("link")))TextButton(onClick={openUrl(ctx,r.str("link"))}){Text("Open reference")}
                val ids=r.optJSONArray("file_ids")
                if(ids!=null)for(i in 0 until ids.length()){
                    val f=d.files.firstOrNull{it.str("id")==ids.optString(i) && it.str("kind")=="client_file" && it.str("status")=="ready"}
                    if(f!=null)TextButton(enabled=!busy,onClick={scope.launch{
                        busy=true
                        try{openUrl(ctx,Api.deliveryFileUrl(job.id,f.str("storage_path")))}
                        catch(e:CancellationException){throw e}
                        catch(e:Exception){error="Attachment unavailable"}
                        finally{busy=false}
                    }}){Text("Open "+f.str("file_name").ifBlank{"attachment"})}
                }
                if(r.str("editor_note").isNotBlank())MutedText(r.str("editor_note"))
                if(active && editor && r.str("status")=="pending"){
                    var note by remember(r.str("id")){mutableStateOf("")}
                    Field(note,{note=it.take(300)},"Optional response")
                    PrimaryButton("Accept change",enabled=!busy){confirm="Accept the stated changes?" to {NativeDelivery.answerChange(job,r.str("id"),true,note)}}
                    SecondaryButton("Reject change"){if(!busy)confirm="Reject change?" to {NativeDelivery.answerChange(job,r.str("id"),false,note)}}
                }
                if(active && client && r.str("status") in setOf("pending","accepted_awaiting_payment"))TextButton(enabled=!busy,onClick={confirm="Cancel change request?" to {NativeDelivery.cancelChange(job,r.str("id"))}}){Text("Cancel change")}
                if(r.str("status")=="accepted_awaiting_payment")MutedText("Waiting for payment. Checkout is disabled in this preview.")
            }
            if(client && active && !d.openChange){
                var details by remember{mutableStateOf("")};var price by remember{mutableStateOf("0")};var hours by remember{mutableStateOf("0")};var ref by remember{mutableStateOf("")}
                Field(details,{details=it.take(2000)},"New requirements",minLines=3)
                Field(price,{price=it.filter{c->c.isDigit()}.take(7)},"Extra price (₹)")
                Dropdown("Extra hours",hours,listOf("0","12","24","48","72")){hours=it}
                Field(ref,{ref=it.take(500)},"Reference link (optional)")
                val maxMb=d.setting("file_max_mb")?.coerceAtMost(50)
                TextButton(enabled=!busy && attachmentIds.size<5,onClick={changePicker.launch(arrayOf("image/*","video/*"))}){Text("Choose photo/video attachments")}
                if(selectedChanges.isNotEmpty())TextButton(enabled=!busy,onClick={selectedChanges=emptyList()}){Text("Remove selected files (${selectedChanges.size})")}
                if(attachmentIds.isNotEmpty())MutedText("${attachmentIds.size} uploaded project files will be attached when you retry.")
                MutedText("Maximum 5 files; ${maxMb ?: 50} MB each. Other file types can be shared with a link.")
                PrimaryButton("Send change request",enabled=!busy && details.trim().length>=10 && (price.toLongOrNull()?.let{it in 0L..1000000L}==true) && (ref.isBlank()||link(ref)) && (selectedChanges.isEmpty()||maxMb!=null)){
                    confirm="Send these new requirements to the editor?" to {
                        while(selectedChanges.isNotEmpty()){
                            val uri=selectedChanges.first()
                            val item=ProjectMedia.stage(ctx,uri,false)
                            try {
                                require(item.size <= (maxMb ?: 0)*1048576L){"Attachment exceeds the current file limit"}
                                progress="Uploading change attachment ${attachmentIds.size+1}…"
                                val id=NativeDelivery.uploadChangeAttachment(job,item)
                                attachmentIds=attachmentIds+id
                                selectedChanges=selectedChanges.drop(1)
                            }finally{item.file.delete()}
                        }
                        NativeDelivery.change(job,details.trim(),price.toLong(),hours.toInt(),ref.trim(),attachmentIds)
                        attachmentIds=emptyList();details="";ref=""
                    }
                }
            }
        }
    }
    if(editor && active && phase=="preview" && !d.openRevision && !d.openChange && d.previews.isNotEmpty()){
        var finalLink by remember{mutableStateOf("")};var note by remember{mutableStateOf("")}
        val latest=d.previews.first()
        CardBox{
            Text("Final submission",fontWeight=FontWeight.Bold)
            MutedText("Final preview v"+latest.optInt("version")+". The clean video link is held by the server until payment is released.")
            Field(finalLink,{finalLink=it.take(500)},"Clean final HTTPS link")
            Field(note,{note=it.take(500)},"Optional note")
            PrimaryButton("Submit for final approval",enabled=!busy && link(finalLink)){
                confirm="Submit final for client review?" to {NativeDelivery.final(job,latest.str("id"),finalLink.trim(),note.trim());finalLink="";note=""}
            }
        }
    }
    if(job.status=="delivered"){
        CardBox{
            Text("Final review",fontWeight=FontWeight.Bold)
            MutedText(when(job.reviewState){"disputed"->"Dispute opened — Sphere team reviewing";"team_review"->"Sphere team reviewing";else->"Waiting for client decision"})
            if(job.reviewState=="awaiting_client")instant(job.decisionDueAt)?.let{Text("Decision time left: "+timer(it.epochSecond-now))}
            if(client)MutedText("Clean final link remains locked. Payment release is disabled in this development preview until payment compliance testing. A local simulation is available in Payments.")
        }
    }
    val lateNoPreview=active && phase=="active" && w?.optBoolean("is_late")==true && w.str("preview_at").isBlank()
    if(client && !d.openDispute && (job.status=="delivered" || lateNoPreview)){
        val cats=if(lateNoPreview)listOf("not_delivered") else listOf("quality","not_as_asked","missing","late","other")
        var category by remember(lateNoPreview){mutableStateOf(cats.first())};var details by remember{mutableStateOf("")}
        CardBox{
            Text(if(lateNoPreview)"Request refund review" else "Not satisfied?",fontWeight=FontWeight.Bold)
            MutedText("Sphere team reviews your case. A request is not a completed refund.")
            Dropdown("Reason",category,cats){category=it}
            Field(details,{details=it.take(2000)},"Explain the problem (at least 20 characters)",minLines=3)
            PrimaryButton("Send to Sphere team",enabled=!busy && details.trim().length>=20){
                confirm="Submit this case for review?" to {NativeDelivery.dispute(job,category,details.trim());details=""}
            }
        }
    }
    d.disputes.forEach{r->CardBox{Text("Case · "+r.str("status"),fontWeight=FontWeight.Bold);MutedText(r.str("details"));if(r.str("decision_note").isNotBlank())MutedText(r.str("decision_note"))}}
    d.refunds.forEach{r->CardBox{Text("Refund · "+r.str("status"),fontWeight=FontWeight.Bold);KeyValue("Amount",money(r.numOrNull("amount")))}}
    if(job.status in setOf("approved","closed"))MutedText("Project closed for in-app disputes and refunds. Contact support for further help.")
    d.settlement?.let{s->CardBox{
        Text("Earnings & settlement",fontWeight=FontWeight.Bold)
        KeyValue("Status",s.str("status"));KeyValue("Base",money(s.numOrNull("base")));KeyValue("Extras",money(s.numOrNull("extras")));KeyValue("Bonus",money(s.numOrNull("bonus")));KeyValue("Late deduction",money(s.numOrNull("late_deduction")));KeyValue("Total",money(s.numOrNull("total")))
        listOf("early" to "Early delivery","rating" to "Rating +3","revisions" to "At most one revision, no dispute","quality" to "Clean project").forEach{(k,label)->MutedText((if(s.optBoolean(k))"✓ " else "○ ")+label)}
    }}
    var showEvents by remember{mutableStateOf(false)}
    TextButton(onClick={showEvents=!showEvents}){Text(if(showEvents)"Hide timeline" else "Project timeline (${d.events.size})")}
    if(showEvents)d.events.forEach{e->CardBox{Text(e.str("title"),fontWeight=FontWeight.Bold);MutedText(date(e.str("at")));MutedText(e.str("details"))}}
    if(progress.isNotBlank()){LinearProgressIndicator(modifier=Modifier.fillMaxWidth());MutedText(progress)}
    if(error.isNotBlank())Text(error,color=Danger)
    confirm?.let{(question,action)->AlertDialog(onDismissRequest={confirm=null},title={Text(question)},confirmButton={TextButton(onClick={confirm=null;act(action)}){Text("Confirm")}},dismissButton={TextButton(onClick={confirm=null}){Text("Cancel")}})}
    video?.let{WatermarkedPlayer(it,job.id.take(8)){video=null}}
}

@Composable
private fun WatermarkedPlayer(url:String,code:String,close:()->Unit){
    var player by remember(url){mutableStateOf<VideoView?>(null)}
    var error by remember{mutableStateOf(false)}
    val transition=rememberInfiniteTransition(label="preview watermark")
    val position by transition.animateFloat(initialValue=0f,targetValue=1f,animationSpec=infiniteRepeatable(tween(3500,easing=LinearEasing),RepeatMode.Reverse),label="watermark movement")
    DisposableEffect(url){onDispose{player?.stopPlayback()}}
    Dialog(onDismissRequest=close){Surface{
        Column(Modifier.padding(12.dp)){
            Text("SPHERE PREVIEW · $code",fontWeight=FontWeight.Bold)
            BoxWithConstraints(Modifier.fillMaxWidth().height(220.dp).background(Color.Black)){
                AndroidView(factory={c->VideoView(c).apply{setVideoURI(Uri.parse(url));setOnPreparedListener{seekTo(1)};setOnErrorListener{_,_,_->error=true;true};player=this}},modifier=Modifier.fillMaxSize())
                Text("SPHERE",color=Color.White.copy(alpha=.65f),fontWeight=FontWeight.Bold,modifier=Modifier.offset(x=(maxWidth-90.dp).coerceAtLeast(0.dp)*position,y=140.dp*position))
            }
            if(error)MutedText("Unable to play this video on your device.")
            Row{TextButton(onClick={player?.start()}){Text("Play")};TextButton(onClick={player?.pause()}){Text("Pause")};TextButton(onClick=close){Text("Done")}}
            MutedText("Playback watermark is a visual overlay, not guaranteed copy protection.")
        }
    }}
}
