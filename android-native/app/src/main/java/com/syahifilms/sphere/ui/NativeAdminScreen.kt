@file:OptIn(ExperimentalMaterial3Api::class)
package com.syahifilms.sphere.ui

import android.app.Activity
import android.view.WindowManager
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.navigation.NavHostController
import com.syahifilms.sphere.data.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.json.JSONObject

@Composable
fun NativeAdminScreen(nav:NavHostController){
    val me=AppState.me
    val ctx=LocalContext.current
    if(me==null || me.role!="admin"){
        Page("Access denied",onBack={nav.popBackStack()}){MutedText("Admin accounts only.")}
        return
    }
    val owner=me.id
    val activity=ctx as? androidx.activity.ComponentActivity
    var foreground by remember(owner){mutableStateOf(false)}
    var allowed by remember(owner){mutableStateOf(false)}
    var error by remember(owner){mutableStateOf(false)}
    var attempt by remember{mutableIntStateOf(0)}
    DisposableEffect(activity){
        val window=activity?.window
        val flag=WindowManager.LayoutParams.FLAG_SECURE
        val already=window?.attributes?.flags?.let{it and flag != 0}?:false
        window?.addFlags(flag)
        val lifecycle=activity?.lifecycle
        foreground=lifecycle?.currentState?.isAtLeast(Lifecycle.State.RESUMED)==true
        val observer=LifecycleEventObserver{_,_->
            foreground=lifecycle?.currentState?.isAtLeast(Lifecycle.State.RESUMED)==true
            if(!foreground)allowed=false
        }
        lifecycle?.addObserver(observer)
        onDispose{
            lifecycle?.removeObserver(observer)
            if(!already)window?.clearFlags(flag)
        }
    }
    LaunchedEffect(owner,foreground,attempt){
        allowed=false;error=false
        if(!foreground)return@LaunchedEffect
        while(Api.userId==owner){
            try{NativeAdmin.authorize(owner);allowed=true}
            catch(e:CancellationException){throw e}
            catch(_:Exception){allowed=false;error=true;break}
            delay(15000)
        }
        allowed=false
    }
    if(!allowed || !foreground || Api.userId!=owner){
        Page("Admin Panel",onBack={nav.popBackStack()}){
            if(error)ErrorBox("Admin access could not be verified. No private data is available."){attempt++}
            else Loading()
        }
    }else key(owner){AdminContent(nav,owner)}
}

@Composable
private fun AdminContent(nav:NavHostController,owner:String){
    var tab by remember{mutableStateOf(NativeAdmin.Tab.OVERVIEW)}
    var menu by remember{mutableStateOf(false)}
    Page("Admin Panel",onBack={nav.popBackStack()},actions={
        Box{
            IconButton(onClick={menu=true}){Icon(Icons.Filled.MoreVert,"Admin sections")}
            DropdownMenu(expanded=menu,onDismissRequest={menu=false}){
                NativeAdmin.Tab.entries.forEach{t->DropdownMenuItem(text={Text(t.label)},onClick={tab=t;menu=false})}
            }
        }
    }){
        MutedText("Sphere by Syahi Films · Restricted admin view")
        Dropdown("Admin section",tab.label,NativeAdmin.Tab.entries.map{it.label}){label->tab=NativeAdmin.Tab.entries.first{it.label==label}}
        when(tab){
            NativeAdmin.Tab.OVERVIEW->AdminOverview(owner){tab=it}
            NativeAdmin.Tab.VERIFICATION->AdminVerification(owner)
            NativeAdmin.Tab.USERS->AdminUsers(owner)
            NativeAdmin.Tab.PROJECTS->AdminProjects(owner)
            NativeAdmin.Tab.DISPUTES->AdminDisputes(owner)
            NativeAdmin.Tab.PAYMENTS->AdminPayments(owner)
            NativeAdmin.Tab.MODERATION->AdminModeration(owner)
            NativeAdmin.Tab.AUDIT->AdminAudit(owner)
        }
        MutedText("Preview: financial approvals, account changes and case decisions are not available here.",12)
    }
}

@Composable
private fun <T> AdminLoaded(loaded:Loaded<T>,content:@Composable (T)->Unit){
    TextButton(onClick=loaded.reload){Text("Refresh")}
    val data=loaded.data
    when{
        loaded.error!=null->ErrorBox("Could not load this admin section. Check access and retry.",loaded.reload)
        data==null->Loading()
        else->content(data)
    }
}

@Composable
private fun AdminOverview(owner:String,go:(NativeAdmin.Tab)->Unit){
    val loaded=load(owner){NativeAdmin.overview(owner)}
    AdminLoaded(loaded){d->
        val o=d.values
        CardBox{
            Text("Admin security",fontWeight=FontWeight.Bold)
            KeyValue("Server role","Admin")
            KeyValue("Admin PIN",if(d.pinConfigured)"Configured" else "Not configured")
            MutedText("Changes require additional confirmation. Configure security through your authorized admin setup.")
        }
        val stats=listOf("users" to "Total users","clients" to "Clients","editors" to "Editors",
            "verified_editors" to "Verified editors","active_projects" to "Active projects","completed" to "Completed",
            "pending_payments" to "Waiting for payment","pending_refunds" to "Refunds in progress")
        stats.chunked(2).forEach{group->
            Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.spacedBy(8.dp)){
                group.forEach{(k,label)->
                    GlassPanel(Modifier.weight(1f)){
                        Text(o.str(k).ifBlank{"—"},fontWeight=FontWeight.ExtraBold)
                        MutedText(label)
                    }
                }
            }
            Spacer(Modifier.height(8.dp))
        }
        o.optJSONObject("revenue")?.let{r->CardBox{
            Text("Internal revenue summary",fontWeight=FontWeight.Bold)
            listOf("projects" to "Projects","extras" to "Revisions / changes","verification" to "Verification","pro" to "Editor Pro","total" to "Total").forEach{(k,l)->KeyValue(l,money(r.numOrNull(k)))}
        }}
        o.optJSONObject("pending")?.let{p->CardBox{
            Text("Pending admin actions",fontWeight=FontWeight.Bold)
            listOf(Triple("verifications","Verification",NativeAdmin.Tab.VERIFICATION),Triple("disputes","Disputes",NativeAdmin.Tab.DISPUTES),
                Triple("held_messages","Held messages",NativeAdmin.Tab.MODERATION),Triple("payouts","Payouts",NativeAdmin.Tab.PAYMENTS),
                Triple("refunds","Refunds",NativeAdmin.Tab.PAYMENTS),Triple("reports","Reports",NativeAdmin.Tab.MODERATION)).forEach{(k,l,t)->
                TextButton(onClick={go(t)}){Text("$l · "+p.str(k).ifBlank{"—"})}
            }
        }}
    }
}

@Composable
private fun AdminVerification(owner:String){
    val loaded=load(owner){NativeAdmin.verification(owner)}
    val scope=rememberCoroutineScope()
    var queue by remember{mutableStateOf("New")}
    var action by remember{mutableStateOf<NativeAdmin.VerificationRow?>(null)}
    var pin by remember{mutableStateOf("")}
    var busy by remember{mutableStateOf(false)}
    var note by remember{mutableStateOf("")}
    AdminLoaded(loaded){d->
        val queues=mapOf("New" to d.rows.filter{it.status!="rejected"&&!it.contacted},
            "Messaged" to d.rows.filter{it.status!="rejected"&&it.contacted},"Rejected" to d.rows.filter{it.status=="rejected"})
        Row(Modifier.horizontalScroll(rememberScrollState()),horizontalArrangement=Arrangement.spacedBy(6.dp)){
            (listOf("New","Messaged","Rejected","Verified")).forEach{q->
                val n=if(q=="Verified")d.verified.size else queues[q]?.size?:0
                FilterChip(selected=queue==q,onClick={queue=q},label={Text("$q ($n)")})
            }
        }
        if(queue=="Verified"){
            if(d.verified.isEmpty())MutedText("No verified editors.")
            d.verified.forEach{r->CardBox{
                Text(r.str("name").ifBlank{"Editor"},fontWeight=FontWeight.Bold)
                KeyValue("Status","Verified")
                KeyValue("Verified at",r.str("verified_at").ifBlank{"—"})
            }}
        }else{
            val rows=queues[queue].orEmpty()
            if(rows.isEmpty())MutedText("No editors in this queue.")
            rows.forEach{r->CardBox{
                Text((r.number?.let{"Verification $it · "}?:"")+r.name.ifBlank{"Editor"},fontWeight=FontWeight.Bold)
                KeyValue("Application",r.status)
                KeyValue("Fee status",r.fee)
                if(r.freeRank>0)MutedText("First 50 offer · #"+r.freeRank)
                KeyValue("Promo video",if(r.proofVideo)"Submitted" else "Missing")
                KeyValue("Timeline screenshot",if(r.proofPhoto)"Submitted" else "Missing")
                if(r.categories.isNotBlank())KeyValue("Categories",r.categories)
                if(r.note.isNotBlank())MutedText(r.note)
                if(r.status!="rejected")TextButton(enabled=!busy,onClick={pin="";action=r}){
                    Text(if(r.contacted)"Move to New" else "Mark already messaged")
                }
            }}
        }
        SectionTitle("Editor detail update requests (${d.requests.size})")
        d.requests.forEach{r->CardBox{Text(r.str("name").ifBlank{"Editor"});MutedText(r.str("at"))}}
        MutedText("Approve, reject, reopen and proof review require further backend and device testing. No fee confirmation is offered.",12)
    }
    if(note.isNotBlank())MutedText(note)
    action?.let{r->
        AlertDialog(onDismissRequest={if(!busy){action=null;pin=""}},title={Text(if(r.contacted)"Move to New?" else "Confirm message was sent?")},
            text={Column{
                Text(if(r.contacted)"This removes the outreach marker only." else "Only mark after you actually contacted this editor. This action does not send a message.")
                OutlinedTextField(value=pin,onValueChange={pin=it.take(128)},label={Text("Your existing admin PIN")},visualTransformation=PasswordVisualTransformation(),singleLine=true,enabled=!busy)
            }},confirmButton={TextButton(enabled=!busy&&pin.isNotBlank(),onClick={
                val entered=pin
                pin="";action=null
                scope.launch{
                    busy=true
                    try{NativeAdmin.outreach(owner,r.id,!r.contacted,entered);note="Outreach status updated.";loaded.reload()}
                    catch(e:CancellationException){throw e}
                    catch(_:Exception){note="Action not confirmed. Refresh before trying again. Check your admin PIN and access."}
                    finally{busy=false}
                }
            }){Text("Confirm")}},dismissButton={TextButton(enabled=!busy,onClick={action=null;pin=""}){Text("Cancel")}})
    }
}

@Composable
private fun AdminUsers(owner:String){
    var role by remember{mutableStateOf("all")}
    var input by remember{mutableStateOf("")}
    var query by remember{mutableStateOf("")}
    var completion by remember{mutableStateOf("All")}
    var verified by remember{mutableStateOf("All")}
    Dropdown("Role",role,listOf("all","CLIENT","EDITOR","ADMIN")){role=it;completion="All";verified="All"}
    Field(input,{input=it.take(100)},"Search users")
    PrimaryButton("Search"){query=input.trim()}
    val loaded=load(owner,role,query){NativeAdmin.users(owner,role,query)}
    AdminLoaded(loaded){d->
        if(role=="EDITOR"){
            Text("Editor profiles · ${d.total} signups",fontWeight=FontWeight.Bold)
            MutedText("Complete = Bio + Skills + Portfolio link or sample/uploaded video. Verification is independent.")
            Row(Modifier.horizontalScroll(rememberScrollState()),horizontalArrangement=Arrangement.spacedBy(6.dp)){
                listOf("All","Complete","Partial","Incomplete").forEach{v->
                    FilterChip(selected=completion==v,onClick={completion=v},label={Text("$v (${if(v=="All")d.total else d.counts[v]?:0})")})
                }
            }
            Row(horizontalArrangement=Arrangement.spacedBy(6.dp)){
                listOf("All","Verified","Unverified").forEach{v->
                    FilterChip(selected=verified==v,onClick={verified=v},label={Text("$v (${if(v=="All")d.total else d.counts[v]?:0})")})
                }
            }
        }
        val rows=d.rows.filter{r->(role!="EDITOR"||completion=="All"||r.completion==completion)&&
            (role!="EDITOR"||verified=="All"||r.verified==(verified=="Verified"))}
        MutedText("Showing ${rows.size} of ${d.rows.size} loaded results · maximum 200 per search")
        if(rows.isEmpty())MutedText("No users match.")
        rows.forEach{r->CardBox{
            Text(r.name.ifBlank{"User"},fontWeight=FontWeight.Bold)
            KeyValue("Role",r.role)
            if(r.role=="EDITOR"){KeyValue("Profile",r.completion);KeyValue("Verification",if(r.verified)"Verified" else "Unverified")}
            KeyValue("Account",if(r.suspended)"Suspended" else "Active")
            KeyValue("Strikes",r.strikes.toString());KeyValue("Projects",r.projects.toString())
        }}
    }
}

@Composable
private fun AdminProjects(owner:String){
    var filter by remember{mutableStateOf("all")}
    var input by remember{mutableStateOf("")}
    var query by remember{mutableStateOf("")}
    var offset by remember{mutableIntStateOf(0)}
    Dropdown("Project health",filter,listOf("all","normal","suspicious","dispute")){filter=it;offset=0}
    Field(input,{input=it.take(100)},"Search projects")
    PrimaryButton("Search"){query=input.trim();offset=0}
    val loaded=load(owner,filter,query,offset){NativeAdmin.projects(owner,filter,query,offset)}
    AdminLoaded(loaded){d->
        if(d.rows.isEmpty())MutedText("No projects on this page.")
        d.rows.forEach{r->CardBox{
            Text(r.str("title").ifBlank{"Project"},fontWeight=FontWeight.Bold)
            MutedText("SPH-"+r.str("id").replace("-","").take(6).uppercase())
            KeyValue("Health",r.str("health"));KeyValue("Status",r.str("status"))
            KeyValue("Client",r.str("client_name"));KeyValue("Editor",r.str("editor_name"))
            KeyValue("Amount",money(r.numOrNull("amount")));KeyValue("Payment",r.str("payment_status").ifBlank{"Unpaid"})
            if(NativeAdmin.arr(r,"reasons").isNotBlank())MutedText(NativeAdmin.arr(r,"reasons"))
            d.metrics[r.str("id")]?.let{m->
                KeyValue("Bids / editors chatted",m.str("bids")+" / "+m.str("chat_editors"))
                KeyValue("Messages / files",m.str("messages")+" / "+m.str("files"))
                KeyValue("Revisions / disputes",m.str("revisions")+" / "+m.str("disputes"))
                if(m.str("last_activity").isNotBlank())MutedText("Last activity: "+m.str("last_activity"))
            }
        }}
        Row(horizontalArrangement=Arrangement.spacedBy(8.dp)){
            TextButton(enabled=offset>0,onClick={offset=(offset-60).coerceAtLeast(0)}){Text("Previous")}
            TextButton(enabled=d.rows.size==60,onClick={offset+=60}){Text("Next")}
        }
        SectionTitle("Hidden projects (${d.hidden.size})")
        d.hidden.take(100).forEach{r->CardBox{Text(r.str("title").ifBlank{"Project"});MutedText("Hidden")}}
        if(d.hidden.size>100)MutedText("Showing first 100 hidden projects.")
    }
}

@Composable
private fun AdminDisputes(owner:String){
    val loaded=load(owner){NativeAdmin.disputes(owner)}
    AdminLoaded(loaded){d->
        SectionTitle("Open cases (${d.open.size} loaded)")
        if(d.open.isEmpty())MutedText("No open cases.")
        d.open.forEach{r->CardBox{
            Text(r.str("kind").ifBlank{"Case"},fontWeight=FontWeight.Bold)
            KeyValue("Project","SPH-"+r.str("job_id").replace("-","").take(6).uppercase())
            KeyValue("Category",r.str("category"));KeyValue("Status",r.str("status"));MutedText(r.str("created_at"))
        }}
        SectionTitle("Recent decisions")
        AuditRows(d.decisions)
    }
}
@Composable
private fun AdminPayments(owner:String){
    val loaded=load(owner){NativeAdmin.payments(owner)}
    AdminLoaded(loaded){d->
        MutedText("Read-only server status. No payment, refund or payout actions.")
        d.optJSONObject("by_status")?.let{r->CardBox{
            Text("Payment counts",fontWeight=FontWeight.Bold)
            listOf("paid","pending","failed","refunded").forEach{k->KeyValue(k,r.str(k).ifBlank{"0"})}
        }}
        d.optJSONObject("totals")?.let{r->CardBox{
            Text("Settlement totals",fontWeight=FontWeight.Bold)
            listOf("base","bonus","deductions","sphere").forEach{k->KeyValue(k,money(r.numOrNull(k)))}
        }}
        for((key,label) in listOf("payments" to "Latest client payments","manual_payouts" to "Manual payout status","payout_items" to "Payouts / deductions","refunds" to "Refunds","settlements" to "Settlements")){
            val rows=NativeAdmin.rows(d,key)
            SectionTitle("$label (${rows.size} loaded)")
            if(rows.isEmpty())MutedText("No records.")
            rows.take(100).forEach{r->CardBox{
                Text(r.str("title").ifBlank{r.str("kind").ifBlank{"Project"}},fontWeight=FontWeight.Bold)
                KeyValue("Status",r.str("status").ifBlank{r.str("payout_status").ifBlank{"—"}})
                if(r.str("editor").isNotBlank())KeyValue("Editor",r.str("editor"))
                if(r.has("amount"))KeyValue("Amount",money(r.numOrNull("amount")))
                if(key=="settlements"){KeyValue("Base",money(r.numOrNull("base")));KeyValue("Bonus",money(r.numOrNull("bonus")));KeyValue("Deduction",money(r.numOrNull("deduction")))}
            }}
            if(rows.size>100)MutedText("Showing first 100 records.")
        }
    }
}
@Composable
private fun AdminModeration(owner:String){
    val loaded=load(owner){NativeAdmin.moderation(owner)}
    AdminLoaded(loaded){d->
        CardBox{KeyValue("Recent hidden records",d.str("hidden_count"));KeyValue("Recent reviewed records",d.str("reviewed_count"))}
        SectionTitle("Flagged accounts")
        val rows=NativeAdmin.rows(d,"flagged_users")
        if(rows.isEmpty())MutedText("No flagged accounts.")
        rows.take(100).forEach{r->CardBox{
            Text(r.str("name").ifBlank{"User"},fontWeight=FontWeight.Bold);KeyValue("Role",r.str("role"));KeyValue("Strikes",r.str("strikes"))
            KeyValue("Account",if(r.optBoolean("suspended"))"Suspended" else "Active")
        }}
        MutedText("Original chat content and moderation overrides are not available in this preview.")
    }
}
@Composable
private fun AdminAudit(owner:String){
    val loaded=load(owner){NativeAdmin.audit(owner)}
    AdminLoaded(loaded){rows->AuditRows(rows)}
}
@Composable
private fun AuditRows(rows:List<JSONObject>){
    if(rows.isEmpty())MutedText("No matching audit records.")
    rows.forEach{r->CardBox{
        Text(r.str("action").ifBlank{"Action"},fontWeight=FontWeight.Bold)
        KeyValue("By",r.str("by"));KeyValue("At",r.str("at"))
        if(r.str("project").isNotBlank())KeyValue("Project",r.str("project"))
        if(r.str("old").isNotBlank()||r.str("new").isNotBlank())KeyValue("Change",r.str("old")+" → "+r.str("new"))
        if(r.str("reason").isNotBlank())MutedText(r.str("reason"))
    }}
}
