import test from "node:test";import assert from "node:assert/strict";import fs from "node:fs";
const root="android-native/app/src/main/java/com/syahifilms/sphere/";
const read=p=>fs.readFileSync(root+p,"utf8");
test("Delivery uses server workflow RPCs and never directly changes money or delivery status",()=>{
 const data=read("data/NativeDelivery.kt");
 for(const name of ["sp_work_request_extension","sp_work_answer_extension","sp_work_give_time","sp_rev_request","sp_rev_cancel","sp_cr_create","sp_cr_answer","sp_cr_cancel","sp_files_add_link","sp_final_submit","sp_dispute_open","sp_settlement_mine"])assert.ok(data.includes(name),name);
 assert.match(data,/uid in setOf\(job.clientId,job.assignedEditor\)/);assert.doesNotMatch(data,/Api.update|release-payout|refund-payment/);
});
test("Final link is hidden before release; uploaded previews are private",()=>{
 const ui=read("ui/JobScreens.kt"),delivery=read("ui/NativeDeliveryPanel.kt"),api=read("data/Api.kt");
 assert.match(ui,/isClient && job.status in setOf\("approved","closed"\) && NativePortfolio.validLink\(job.deliveryLink\)/);
 assert.match(api,/object\/sign\/sphere-project/);
 assert.match(delivery,/rememberInfiniteTransition/);assert.match(delivery,/Payment release is disabled/);
});
