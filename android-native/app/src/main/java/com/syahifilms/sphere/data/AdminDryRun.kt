package com.syahifilms.sphere.data

/** Dry-run only: no API, identity, entitlement or server mutation in this model. */
enum class AdminReviewAction(val label:String,val result:String,val reasonRequired:Boolean=true,val hoursRequired:Boolean=false){
    APPROVE("Approve verification","Verified",false),
    REJECT("Reject verification","Rejected"),
    REOPEN("Reopen application","Pending / New",false),
    SUSPEND("Suspend account","Suspended"),
    REACTIVATE("Reactivate account","Active"),
    WARN("Warn user","Warning queued"),
    CLEAR_STRIKES("Clear strikes","0 strikes"),
    FLAG("Flag project","Suspicious"),
    CLEAR_FLAG("Clear flag","Normal"),
    HIDE("Hide project","Hidden"),
    RESTORE("Restore project","Visible"),
    OPEN_REVIEW("Open team review","Review pending"),
    ADD_TIME("Add deadline time","Deadline extended",true,true),
    CLOSE_UNPAID("Close unpaid project","Closed")
}
object AdminDryRun {
    fun simulate(action:AdminReviewAction,reason:String,hours:Int?):String {
        require(!action.reasonRequired || reason.trim().length in 5..500)
        require(!action.hoursRequired || hours?.let{it in 1..168}==true)
        return "Simulated: "+action.result+(if(action.hoursRequired)" (+$hours hours)" else "")+". No server change."
    }
}
