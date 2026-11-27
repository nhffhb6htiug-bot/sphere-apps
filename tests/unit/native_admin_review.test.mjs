import test from "node:test";import assert from "node:assert/strict";import fs from "node:fs";
const root="android-native/app/src/main/java/com/syahifilms/sphere/";
const read=p=>fs.readFileSync(root+p,"utf8");
test("Admin management simulation never calls a live API",()=>{
 const model=read("data/AdminDryRun.kt"),ui=read("ui/AdminReviewPanels.kt");
 assert.doesNotMatch(model,/Api\.|Repo\.|rpc\(/);
 assert.match(model,/No server change/);assert.match(ui,/AdminDryRun.simulate/);
 assert.doesNotMatch(ui,/Api.rpc|sp_ed_review|sp_verify_editor|sp_admin_user_action/);
});
test("Proof uses role authorization, bounded signed URLs and disabled image caches",()=>{
 const api=read("data/Api.kt"),ui=read("ui/AdminReviewPanels.kt"),admin=read("data/NativeAdmin.kt");
 assert.match(api,/adminProofUrl[\s\S]*?NativeAdmin.authorize\(owner\)/);
 assert.match(api,/object\/sign\/sphere-editor-proof/);
 assert.match(api,/put\("expiresIn",90\)/);
 assert.match(ui,/diskCachePolicy\(CachePolicy.DISABLED\)/);
 assert.match(ui,/memoryCachePolicy\(CachePolicy.DISABLED\)/);
 assert.match(ui,/https:\/\/wa.me\/\$phone\?text=/);
 assert.match(admin,/sp_admin_user_detail/);assert.match(admin,/sp_admin_project_detail/);
});
