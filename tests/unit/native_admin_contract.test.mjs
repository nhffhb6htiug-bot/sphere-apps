import test from "node:test";import assert from "node:assert/strict";import fs from "node:fs";
const root="android-native/app/src/main/java/com/syahifilms/sphere/";
const read=p=>fs.readFileSync(root+p,"utf8");
test("Admin route checks server identity, role and suspension, protects screen and clears on background",()=>{
 const data=read("data/NativeAdmin.kt"),ui=read("ui/NativeAdminScreen.kt"),nav=read("ui/Nav.kt");
 assert.match(nav,/composable\("admin"\) \{ NativeAccountGate/);
 assert.match(data,/NativeAuth.accountStatus\(\)/);
 assert.match(data,/status.str\("id"\)!=owner/);
 assert.match(data,/uppercase\(\)!="ADMIN"/);
 assert.match(data,/optBoolean\("suspended",true\)/);
 assert.match(ui,/FLAG_SECURE/);
 assert.match(ui,/if\(!foreground\)allowed=false/);
 assert.match(data,/authorize\(owner\)[\s\S]*?Api.rpc/);
});
test("Completion filters are independent of verification, and queues use existing serial and outreach rules",()=>{
 const data=read("data/NativeAdmin.kt"),ui=read("ui/NativeAdminScreen.kt");
 assert.match(data,/bio&&skills&&portfolio/);
 assert.match(data,/sp_admin_editor_outreach_list/);
 assert.match(data,/filter\(::applicant\)/);
 assert.match(ui,/r.verified==\(verified=="Verified"\)/);
 for(const v of ["New","Messaged","Rejected","Verified","Complete","Partial","Incomplete"])assert.ok(ui.includes('"'+v+'"'));
});
test("Only explicitly confirmed PIN-gated outreach writes are enabled",()=>{
 const data=read("data/NativeAdmin.kt"),ui=read("ui/NativeAdminScreen.kt");
 assert.match(data,/sp_admin_unlock/);
 assert.match(data,/put\("p_pin",token\)/);
 assert.match(ui,/PasswordVisualTransformation\(\)/);
 assert.match(ui,/NativeAdmin.outreach\(owner,r.id,!r.contacted,entered\)/);
 assert.doesNotMatch(data,/Api\.(update|delete|insert|function)|release-payout|refund-payment|sp_admin_force_verify_editor|sp_admin_set_role|sp_admin_user_action/);
});
