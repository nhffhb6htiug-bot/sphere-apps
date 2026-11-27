package com.syahifilms.sphere.data

import org.json.JSONArray
import org.json.JSONObject

/** No client-side role promotion or service key. All reads use the caller's session and existing RLS/RPCs. */
object NativeAdmin {
    enum class Tab(val label:String) {
        OVERVIEW("Overview"), VERIFICATION("Verification"), USERS("Users"), PROJECTS("Projects"),
        DISPUTES("Disputes"), PAYMENTS("Payments"), MODERATION("Moderation"), AUDIT("Audit")
    }
    data class UserRow(val id:String,val name:String,val role:String,val verified:Boolean,val completion:String,
        val suspended:Boolean,val strikes:Int,val projects:Int)
    data class VerificationRow(val id:String,val name:String,val status:String,val number:Int?,val contacted:Boolean,
        val fee:String,val proofVideo:Boolean,val proofPhoto:Boolean,val freeRank:Int,val categories:String,val note:String)
    data class VerificationData(val rows:List<VerificationRow>,val verified:List<JSONObject>,val requests:List<JSONObject>)
    data class ProjectData(val rows:List<JSONObject>,val hidden:List<JSONObject>,val metrics:Map<String,JSONObject>)
    data class UsersData(val rows:List<UserRow>,val counts:Map<String,Int>,val total:Int)
    data class CasesData(val open:List<JSONObject>,val decisions:List<JSONObject>)
    data class Overview(val values:JSONObject,val pinConfigured:Boolean)
    fun rows(o:JSONObject,key:String):List<JSONObject> = o.optJSONArray(key)?.mapObjects{it}.orEmpty()
    fun arr(o:JSONObject,key:String):String = o.optJSONArray(key)?.let{a->(0 until a.length()).map{a.optString(it)}.joinToString(", ")} ?: o.str(key)
    private fun requireOwner(owner:String){require(Api.userId==owner){"Account changed"}}
    suspend fun authorize(owner:String){
        requireOwner(owner)
        val status=NativeAuth.accountStatus() ?: throw ApiException(403,"Admin access unavailable")
        requireOwner(owner)
        if(status.str("id")!=owner || status.str("role").trim().uppercase()!="ADMIN" ||
            !status.has("suspended") || status.optBoolean("suspended",true))throw ApiException(403,"Admin access denied")
    }
    private suspend fun obj(owner:String,fn:String,args:JSONObject=JSONObject()):JSONObject {
        authorize(owner)
        val result=JSONObject(Api.rpc(fn,args))
        requireOwner(owner)
        return result
    }
    private suspend fun list(owner:String,fn:String,args:JSONObject=JSONObject()):List<JSONObject>{
        authorize(owner)
        val result=JSONArray(Api.rpc(fn,args)).mapObjects{it}
        requireOwner(owner)
        return result
    }
    private suspend fun profiles(owner:String)=list(owner,"sp_admin_profiles",JSONObject().put("p_role","EDITOR").put("p_verified",JSONObject.NULL))
    private fun filled(o:JSONObject,key:String)=o.str(key).isNotBlank() && o.str(key)!="null"
    fun completion(p:JSONObject,video:Boolean):String {
        val bio=filled(p,"bio")
        val skills=p.optJSONArray("skills")?.let{a->(0 until a.length()).any{!a.isNull(it)&&a.optString(it).isNotBlank()}} ?: filled(p,"skills")
        val portfolio=filled(p,"portfolio_url")||filled(p,"sample_video_url")||video
        return if(bio&&skills&&portfolio)"Complete" else if(bio||skills||portfolio)"Partial" else "Incomplete"
    }
    private fun applicant(p:JSONObject):Boolean =
        p.optBoolean("is_verified") || p.optBoolean("verified") ||
        (p.str("role").trim().uppercase()=="EDITOR" && p.has("verification_status") && p.isNull("verification_status")) ||
        p.str("verification_status").lowercase() in setOf("pending","rejected","approved") ||
        p.str("verification_fee_status").lowercase() in setOf("submitted","confirmed") || filled(p,"proof_video_url")
    private fun joined(p:JSONObject):Long = runCatching{java.time.OffsetDateTime.parse(p.str("created_at")).toInstant().toEpochMilli()}.getOrDefault(Long.MAX_VALUE)
    suspend fun overview(owner:String):Overview {
        val values=obj(owner,"sp_admin_overview")
        val pin=Api.rpc("sp_admin_pin_status",JSONObject()).trim()
        requireOwner(owner)
        return Overview(values,pin=="true")
    }
    suspend fun users(owner:String,role:String,search:String):UsersData {
        require(role in setOf("all","CLIENT","EDITOR","ADMIN"))
        val users=list(owner,"sp_admin_users",JSONObject().put("p_search",search.take(100).ifBlank{null}?:JSONObject.NULL)
            .put("p_role",role).put("p_limit",200))
        val profiles=if(role=="EDITOR")profiles(owner) else emptyList()
        // Fetch only video presence metadata, not any private media contents. If it fails, do not classify.
        val videos=if(role=="EDITOR") {
            authorize(owner)
            val ids=mutableSetOf<String>()
            var offset=0
            while(true){
                val page=Api.select("sp_portfolio?select=editor_id,video_url&video_url=not.is.null&order=id.asc&limit=500&offset=$offset")
                requireOwner(owner)
                page.mapObjects{it}.filter{filled(it,"video_url")}.forEach{ids.add(it.str("editor_id"))}
                if(page.length()<500)break
                offset+=500
                if(offset>=20000)throw ApiException(503,"Portfolio classification limit reached; narrow the data server-side.")
            }
            ids
        }else emptySet<String>()
        val profileMap=profiles.associateBy{it.str("id")}
        val tagged=users.map{u->
            val profile=profileMap[u.str("id")]
            UserRow(u.str("id"),u.str("name"),u.str("role"),profile?.optBoolean("is_verified")?:u.optBoolean("verified"),
                profile?.let{completion(it,it.str("id") in videos)}?:"Unknown",u.optBoolean("suspended"),u.optInt("strikes"),u.optInt("projects"))
        }
        val counts=profiles.groupingBy{completion(it,it.str("id") in videos)}.eachCount()+
            mapOf("Verified" to profiles.count{it.optBoolean("is_verified")},"Unverified" to profiles.count{!it.optBoolean("is_verified")})
        return UsersData(tagged,counts,profiles.size)
    }
    suspend fun verification(owner:String):VerificationData {
        val pending=list(owner,"sp_admin_verifications")
        val contacted=list(owner,"sp_admin_editor_outreach_list").map{it.str("id")}.toSet()
        val serial=profiles(owner).filter(::applicant).distinctBy{it.str("id")}.sortedWith(compareBy<JSONObject>{joined(it)}.thenBy{it.str("id")})
            .mapIndexed{i,p->p.str("id") to i+1}.toMap()
        val verified=list(owner,"sp_admin_editor_review",JSONObject().put("p_ids",JSONObject.NULL))
        val requests=list(owner,"sp_admin_detail_requests")
        return VerificationData(pending.map{p->
            VerificationRow(p.str("id"),p.str("name"),p.str("status"),serial[p.str("id")],p.str("id") in contacted,p.str("fee_status"),
                filled(p,"proof_video"),filled(p,"proof_screenshot"),p.optInt("free_offer_rank"),arr(p,"categories"),p.str("note"))
        }.sortedByDescending{it.number?:0},verified.map{JSONObject().put("name",it.str("name")).put("verified_at",it.str("verified_at")).put("status",it.str("status"))},
          requests.map{JSONObject().put("name",it.str("name")).put("at",it.str("at"))})
    }
    suspend fun projects(owner:String,filter:String,search:String,offset:Int):ProjectData{
        require(filter in setOf("all","normal","suspicious","dispute") && offset>=0)
        val rows=list(owner,"sp_admin_projects",JSONObject().put("p_filter",filter).put("p_search",search.take(100).ifBlank{null}?:JSONObject.NULL)
            .put("p_limit",60).put("p_offset",offset))
        val ids=rows.map{it.str("id")}.filter(::validId)
        val metrics=if(ids.isEmpty())emptyMap() else list(owner,"sp_admin_project_metrics",JSONObject().put("p_jobs",JSONArray(ids))).associateBy{it.str("job_id")}
        return ProjectData(rows,list(owner,"sp_admin_hidden_projects"),metrics)
    }
    private fun validId(id:String)=NativeChat.validId(id)
    suspend fun disputes(owner:String):CasesData{
        authorize(owner)
        val cases=Api.select("sp_disputes?status=eq.open&select=id,job_id,kind,category,status,created_at&order=created_at.asc&limit=50").mapObjects{it}
        requireOwner(owner)
        return CasesData(cases,audit(owner,"case_decision",30))
    }
    suspend fun payments(owner:String)=obj(owner,"sp_admin_payments")
    suspend fun moderation(owner:String):JSONObject{
        val d=obj(owner,"sp_admin_moderation")
        // No unmasked message text or raw chat history retained.
        return JSONObject().put("hidden_count",rows(d,"hidden").size).put("reviewed_count",rows(d,"reviewed").size)
            .put("flagged_users",JSONArray(rows(d,"flagged_users").map{r->JSONObject().put("name",r.str("name")).put("role",r.str("role")).put("strikes",r.optInt("strikes")).put("suspended",r.optBoolean("suspended"))}))
    }
    suspend fun audit(owner:String,action:String="",limit:Int=150)=list(owner,"sp_admin_audit_list",JSONObject().put("p_limit",limit.coerceIn(1,150)).put("p_action",action.ifBlank{null}?:JSONObject.NULL))
    /** One explicitly confirmed outreach operation. No token or PIN persisted or logged. */
    suspend fun outreach(owner:String,editor:String,mark:Boolean,pin:String){
        require(validId(editor) && editor!=owner && pin.length in 1..128)
        authorize(owner)
        val unlock=JSONObject(Api.rpc("sp_admin_unlock",JSONObject().put("p_pin",pin)))
        requireOwner(owner)
        if(!unlock.optBoolean("ok"))throw ApiException(403,if(unlock.optBoolean("locked"))"PIN temporarily locked. Try again later." else "PIN not accepted.")
        val token=unlock.str("token")
        require(token.isNotBlank()){"Admin unlock not confirmed"}
        authorize(owner)
        Api.rpc("sp_admin_editor_outreach_set",JSONObject().put("p_editor",editor).put("p_mark",mark).put("p_pin",token))
        requireOwner(owner)
    }
}
