package com.syahifilms.sphere.ui

import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.text.font.FontWeight
import androidx.navigation.NavHostController
import com.syahifilms.sphere.BuildConfig
import com.syahifilms.sphere.data.*

@Composable
fun NativePaymentLab(nav:NavHostController) {
    if(!BuildConfig.DEBUG)return
    var product by remember {mutableStateOf(LabProduct.PROJECT)}
    var order by remember {mutableStateOf(LabOrder(product))}
    val labels=mapOf(
        LabAction.START to "Simulate checkout",
        LabAction.CANCEL to "Simulate cancellation",
        LabAction.CONFIRM_FIXTURE to "Simulate verified capture",
        LabAction.DELIVER to "Simulate delivery",
        LabAction.DISPUTE to "Simulate dispute",
        LabAction.RELEASE to "Simulate release",
        LabAction.APPROVE_REFUND_FIXTURE to "Simulate approved refund",
        LabAction.CONFIRM_REFUND_FIXTURE to "Simulate refund confirmation"
    )
    Page("Payment simulation",onBack={nav.popBackStack()}) {
        CardBox {
            Text("DEMO ONLY · NO REAL MONEY",fontWeight=FontWeight.Bold)
            MutedText("Fictional orders. Nothing is charged, released, refunded or granted to your Sphere account. All changes reset when this screen is closed.")
        }
        Dropdown("Test product",product.label,LabProduct.entries.map{it.label}){label->
            product=LabProduct.entries.first{it.label==label};order=LabOrder(product)
        }
        CardBox{
            KeyValue("Example amount","₹"+order.product.paise/100)
            KeyValue("Simulated status",order.state.name.replace('_',' '))
            if(order.product.project)KeyValue("Simulated final link",if(order.finalUnlocked)"Unlocked" else "Locked")
            else KeyValue("Simulated benefit",if(order.simulatedBenefit)"Available in fixture only" else "Not granted")
        }
        order.actions().forEach{action->
            PrimaryButton(labels.getValue(action)){order=order.apply(action)}
        }
        SecondaryButton("Reset fictional order"){order=LabOrder(product)}
        MutedText("This is a state-machine demonstration, not a payment gateway sandbox or proof of backend settlement.")
    }
}
