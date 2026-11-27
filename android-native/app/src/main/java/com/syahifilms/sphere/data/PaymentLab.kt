package com.syahifilms.sphere.data

/** Fictional, in-memory test fixture. Never connected to a real account, purchase, API or entitlement. */
enum class LabProduct(val label:String,val paise:Long,val project:Boolean=false) {
    PROJECT("Editing project",50000,true),
    REVISION("Paid revision",5000),
    CHANGE("Additional editing work",10000),
    PREMIUM("Premium project posting",19900),
    VERIFICATION("Editor verification",2900),
    CONTACT("Contact unlock",500)
}
enum class LabState { CREATED,PENDING,CANCELLED,CAPTURED,DELIVERED,DISPUTED,RELEASED,REFUND_PENDING,REFUNDED }
enum class LabAction { START,CANCEL,CONFIRM_FIXTURE,DELIVER,DISPUTE,RELEASE,APPROVE_REFUND_FIXTURE,CONFIRM_REFUND_FIXTURE }
data class LabOrder(val product:LabProduct,val state:LabState=LabState.CREATED) {
    val finalUnlocked get()=product.project && state==LabState.RELEASED
    val simulatedBenefit get()=!product.project && state==LabState.CAPTURED
    fun actions():List<LabAction> = when(state) {
        LabState.CREATED -> listOf(LabAction.START,LabAction.CANCEL)
        LabState.PENDING -> listOf(LabAction.CONFIRM_FIXTURE,LabAction.CANCEL)
        LabState.CAPTURED -> if(product.project) listOf(LabAction.DELIVER,LabAction.APPROVE_REFUND_FIXTURE) else listOf(LabAction.APPROVE_REFUND_FIXTURE)
        LabState.DELIVERED -> listOf(LabAction.DISPUTE,LabAction.RELEASE)
        LabState.DISPUTED -> listOf(LabAction.APPROVE_REFUND_FIXTURE)
        LabState.REFUND_PENDING -> listOf(LabAction.CONFIRM_REFUND_FIXTURE)
        LabState.CANCELLED,LabState.RELEASED,LabState.REFUNDED -> emptyList()
    }
    fun apply(action:LabAction):LabOrder {
        require(action in actions()) { "Invalid or repeated test transition" }
        return copy(state=when(action) {
            LabAction.START->LabState.PENDING
            LabAction.CANCEL->LabState.CANCELLED
            LabAction.CONFIRM_FIXTURE->LabState.CAPTURED
            LabAction.DELIVER->LabState.DELIVERED
            LabAction.DISPUTE->LabState.DISPUTED
            LabAction.RELEASE->LabState.RELEASED
            LabAction.APPROVE_REFUND_FIXTURE->LabState.REFUND_PENDING
            LabAction.CONFIRM_REFUND_FIXTURE->LabState.REFUNDED
        })
    }
}
