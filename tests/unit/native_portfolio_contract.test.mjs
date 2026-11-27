import test from "node:test";import assert from "node:assert/strict";import fs from "node:fs";
const root="android-native/app/src/main/java/com/syahifilms/sphere/";
const read=p=>fs.readFileSync(root+p,"utf8");
test("Portfolio uses web-compatible fields and owner-scoped writes",()=>{
 const p=read("data/NativePortfolio.kt");assert.match(p,/MAX_ITEMS = 12/);assert.match(p,/put\("editor_id",owner\)/);assert.match(p,/editor_id=eq\.\$owner/);assert.match(p,/25L\*1024\*1024/);assert.match(p,/inJustDecodeBounds=true/);
 assert.match(p,/bio && skills && portfolio/);assert.match(p,/items.any \{ it.video.isNotBlank\(\) \}/);
});
test("Profile updates never grant verification; rejected application returns to pending",()=>{
 const repo=read("data/Repo.kt"),p=read("data/NativePortfolio.kt");
 assert.match(repo,/put\("edit_device", device\)/);assert.match(repo,/put\("bio", bio/);assert.match(repo,/put\("availability", availability\)/);
 assert.match(p,/verification_status=eq.rejected/);assert.match(p,/put\("verification_status","pending"\)/);
 assert.doesNotMatch(p,/put\("is_verified"/);
});
