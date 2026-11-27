package com.syahifilms.sphere.data

import org.json.JSONObject
import org.json.JSONArray

object NativeDelivery {
    data class Snapshot(val work:JSONObject?,val files:List<JSONObject>,val extensions:List<JSONObject>,
        val revisions:List<JSONObject>,val changes:List<JSONObject>,val disputes:List<JSONObject>,val refunds:List<JSONObject>,
        val events:List<JSONObject>,val settings:Map<String,Int>,val settlement:JSONObject?) {
        val previews get()=files.filter{it.str("kind")=="preview" && it.str("status")=="ready"}
        val freeUsed get()=revisions.count{it.str("status")!="cancelled"}
        val openRevision get()=revisions.any{it.str("status") in setOf("open","awaiting_payment")}
        val openChange get()=changes.any{it.str("status") in setOf("pending","accepted_awaiting_payment")}
        val openDispute get()=disputes.any{it.str("status")=="open" && it.str("kind")=="dispute"}
        fun setting(k:String)=settings[k]
    }
    private fun party(job:Job):String {
        val uid=Api.userId ?: error("Please log in")
        require(NativeChat.validId(job.id) && uid in setOf(job.clientId,job.assignedEditor))
        return uid
    }
    suspend fun load(job:Job):Snapshot {
        val owner=party(job)
        suspend fun rows(table:String,fields:String,order:String)=Api.select("$table?job_id=eq.${job.id}&select=$fields&order=$order").mapObjects{it}
        val work=Api.selectOne("sp_project_work?job_id=eq.${job.id}&select=*")
        val files=rows("sp_project_files","id,kind,source,storage_path,external_url,version,status,note,created_at,file_name,mime,size_bytes","version.desc")
        val ext=rows("sp_project_extensions","id,hours,reason,status","created_at.desc")
        val rev=rows("sp_revisions","id,number,notes,status,fee,new_due_at","number.asc")
        val changes=rows("sp_change_requests","id,details,extra_price,extra_hours,status,editor_note,link,file_ids","created_at.asc")
        val disputes=rows("sp_disputes","id,kind,category,details,status,decision_note","created_at.desc")
        val refunds=rows("sp_refunds","id,amount,status","created_at.desc")
        val events=rows("sp_project_events","kind,title,details,at","at.desc&limit=60")
        val settings=Api.select("sp_settings?key=in.(free_revisions,revision_fee,revision_hours,late_fee_per_hour,final_review_hours,bonus_early_hours,preview_max_minutes,file_max_mb)&select=key,value")
            .mapObjects{it.str("key") to it.str("value").toIntOrNull()}.mapNotNull{(k,v)->v?.let{k to it}}.toMap()
        val settlement=if(owner==job.assignedEditor && job.status in setOf("approved","closed")){
            val raw=Api.rpc("sp_settlement_mine",JSONObject().put("p_job",job.id))
            if(raw.trim()=="null" || raw.isBlank())null else JSONObject(raw)
        }else null
        require(Api.userId==owner)
        return Snapshot(work,files,ext,rev,changes,disputes,refunds,events,settings,settlement)
    }
    private suspend fun call(job:Job,client:Boolean,fn:String,args:JSONObject) {
        val uid=party(job)
        require(uid==if(client)job.clientId else job.assignedEditor)
        Api.rpc(fn,args)
    }
    private fun jobArgs(j:Job)=JSONObject().put("p_job",j.id)
    suspend fun requestTime(j:Job,h:Int,reason:String)=call(j,false,"sp_work_request_extension",jobArgs(j).put("p_hours",h).put("p_reason",reason))
    suspend fun answerTime(j:Job,approve:Boolean)=call(j,true,"sp_work_answer_extension",jobArgs(j).put("p_approve",approve))
    suspend fun giveTime(j:Job,h:Int,note:String)=call(j,true,"sp_work_give_time",jobArgs(j).put("p_hours",h).put("p_note",note.ifBlank{null}?:JSONObject.NULL))
    suspend fun revision(j:Job,notes:String)=call(j,true,"sp_rev_request",jobArgs(j).put("p_notes",notes))
    suspend fun cancelRevision(j:Job,id:String)=call(j,true,"sp_rev_cancel",JSONObject().put("p_rev",id))
    suspend fun change(j:Job,details:String,price:Long,h:Int,link:String,fileIds:List<String> = emptyList()) {
        require(fileIds.size <= ProjectMedia.MAX_FILES && fileIds.all { NativeChat.validId(it) })
        call(j,true,"sp_cr_create",jobArgs(j).put("p_details",details).put("p_extra_price",price).put("p_extra_hours",h).put("p_link",link.ifBlank{null}?:JSONObject.NULL).put("p_file_ids",JSONArray(fileIds)))
    }

    /** Upload only a staged file; server allocates the object path and validates party/phase. */
    private suspend fun upload(j:Job,kind:String,item:LocalProjectMedia,duration:Double?,note:String):String {
        val owner=party(j)
        require(j.status=="in-progress" && owner==if(kind=="preview")j.assignedEditor else j.clientId)
        require(kind in setOf("preview","client_file"))
        ProjectMedia.validate(listOf(item))
        val b=JSONObject(Api.rpc("sp_files_begin",jobArgs(j).put("p_kind",kind).put("p_name",item.name)
            .put("p_mime",item.mime).put("p_size",item.size)))
        val id=b.str("id");val path=b.str("path")
        val folder=if(kind=="preview")"preview" else "client"
        require(NativeChat.validId(id) && b.str("bucket")=="sphere-project" && path.startsWith("${j.id}/$folder/$id."))
        // A timeout may have committed an upload. Do not mark it failed or retry blindly.
        try { Api.uploadDeliveryFile(owner,j.id,path,item.file,item.mime) }
        catch(e:kotlinx.coroutines.CancellationException){throw e}
        catch(e:Exception){
            throw ApiException(503,"Upload not confirmed. Refresh project files before retrying.")
        }
        require(Api.userId==owner)
        val f=JSONObject(Api.rpc("sp_files_finish",JSONObject().put("p_id",id).put("p_ok",true)
            .put("p_duration",duration?:JSONObject.NULL).put("p_note",note.ifBlank{null}?:JSONObject.NULL)))
        require(f.str("status")=="ready"){"File not confirmed. Refresh project files."}
        return id
    }
    suspend fun uploadEncodedPreview(j:Job,encoded:EncodedPreview,note:String):String =
        upload(j,"preview",encoded.media,encoded.durationSeconds,note)
    suspend fun uploadChangeAttachment(j:Job,item:LocalProjectMedia):String =
        upload(j,"client_file",item,null,"For a change request")
    suspend fun answerChange(j:Job,id:String,yes:Boolean,note:String)=call(j,false,"sp_cr_answer",JSONObject().put("p_cr",id).put("p_accept",yes).put("p_note",note.ifBlank{null}?:JSONObject.NULL))
    suspend fun cancelChange(j:Job,id:String)=call(j,true,"sp_cr_cancel",JSONObject().put("p_cr",id))
    suspend fun dispute(j:Job,category:String,details:String)=call(j,true,"sp_dispute_open",jobArgs(j).put("p_category",category).put("p_details",details))
    suspend fun preview(j:Job,url:String,note:String)=call(j,false,"sp_files_add_link",jobArgs(j).put("p_kind","preview").put("p_url",url).put("p_name","Watermarked preview").put("p_note",note.ifBlank{null}?:JSONObject.NULL))
    suspend fun final(j:Job,preview:String,url:String,note:String)=call(j,false,"sp_final_submit",jobArgs(j).put("p_preview",preview).put("p_final_link",url).put("p_note",note.ifBlank{null}?:JSONObject.NULL))
}
