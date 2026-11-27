import test from "node:test";import assert from "node:assert/strict";import fs from "node:fs";
const root="android-native/app/src/main/java/com/syahifilms/sphere/";
const read=p=>fs.readFileSync(root+p,"utf8");
test("Payment simulation is debug only, isolated from live account operations",()=>{
 const ui=read("ui/NativePaymentLab.kt"),data=read("data/PaymentLab.kt"),nav=read("ui/Nav.kt");
 assert.match(nav,/BuildConfig.DEBUG\) composable\("paymentLab"\)/);
 assert.match(ui,/if\(!BuildConfig.DEBUG\)return/);
 for(const src of [ui,data])assert.doesNotMatch(src,/Api\.|Repo\.|https:\/\/|razorpay|BillingClient/);
 assert.match(data,/require\(action in actions\(\)\)/);
 assert.match(data,/LabState.CANCELLED,LabState.RELEASED,LabState.REFUNDED -> emptyList\(\)/);
 assert.match(data,/product.project && state==LabState.RELEASED/);
});
test("Production payment functions disabled in preview, final link gated in both screens",()=>{
 const api=read("data/Api.kt"),repo=read("data/Repo.kt"),vault=read("ui/WebsiteFeatureScreens.kt"),job=read("ui/JobScreens.kt");
 for(const name of ["create-razorpay-order","verify-razorpay-payment","release-payout","refund-payment","sphere-extra-payment"])assert.ok(api.includes('"'+name+'"'));
 assert.doesNotMatch(repo,/Api.function\("release-payout"/);
 assert.match(vault,/j.clientId == me.id && j.status in setOf\("approved","closed"\) && j.payment == "released"/);
 assert.match(job,/job.payment == "released"/);
});
