package com.syahifilms.sphere.data
import org.junit.Assert.*
import org.junit.Test

class PaymentLabTest {
    private fun captured(p:LabProduct)=LabOrder(p).apply(LabAction.START).apply(LabAction.CONFIRM_FIXTURE)
    @Test fun projectReleaseOnlyAfterDelivery(){
        val paid=captured(LabProduct.PROJECT)
        assertFalse(paid.finalUnlocked)
        assertThrows(IllegalArgumentException::class.java){paid.apply(LabAction.RELEASE)}
        val released=paid.apply(LabAction.DELIVER).apply(LabAction.RELEASE)
        assertTrue(released.finalUnlocked)
        assertTrue(released.actions().isEmpty())
    }
    @Test fun disputeBlocksReleaseAndRefundIsTerminal(){
        val disputed=captured(LabProduct.PROJECT).apply(LabAction.DELIVER).apply(LabAction.DISPUTE)
        assertThrows(IllegalArgumentException::class.java){disputed.apply(LabAction.RELEASE)}
        val refunded=disputed.apply(LabAction.APPROVE_REFUND_FIXTURE).apply(LabAction.CONFIRM_REFUND_FIXTURE)
        assertFalse(refunded.finalUnlocked)
        assertTrue(refunded.actions().isEmpty())
    }
    @Test fun digitalBenefitsOnlyForCapturedFixture(){
        for(p in LabProduct.entries.filterNot{it.project}){
            val pending=LabOrder(p).apply(LabAction.START)
            assertFalse(pending.simulatedBenefit)
            assertFalse(pending.apply(LabAction.CANCEL).simulatedBenefit)
            val captured=pending.apply(LabAction.CONFIRM_FIXTURE)
            assertTrue(captured.simulatedBenefit)
            assertThrows(IllegalArgumentException::class.java){captured.apply(LabAction.CONFIRM_FIXTURE)}
            assertFalse(captured.apply(LabAction.APPROVE_REFUND_FIXTURE).apply(LabAction.CONFIRM_REFUND_FIXTURE).simulatedBenefit)
        }
    }
}
