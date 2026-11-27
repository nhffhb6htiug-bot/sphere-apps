import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
const root="android-native/app/src/main/java/com/syahifilms/sphere/";
const read=p=>fs.readFileSync(root+p,"utf8");
test("Session storage is encrypted and stale login responses are rejected",()=>{
 const a=read("data/Api.kt"),v=read("data/SessionVault.kt");
 assert.match(v,/AndroidKeyStore/);assert.match(v,/AES\/GCM\/NoPadding/);assert.match(v,/updateAAD\(aad\)/);
 assert.match(a,/vault.write\(encoded\)/);assert.doesNotMatch(a,/putString\("session",/);
 assert.match(a,/expectedEpoch != sessionEpoch/);assert.match(a,/sessionEpoch != epoch/);
 assert.match(v,/deleteEntry\(alias\)/);
});
test("Only backend-marked isolated QA fixtures skip real phone onboarding",()=>{
 const a=read("data/NativeAuth.kt"),r=read("data/Repo.kt"),c=read("ui/Common.kt");
 assert.match(a,/BuildConfig.DEBUG/);assert.match(a,/abxrlvigoouwbunnurkc.supabase.co/);
 assert.match(a,/matchesAccount\(profile,status\)/);assert.match(a,/optBoolean\("qa_fixture",false\)/);
 assert.match(r,/!NativeAuth.isQaFixture\(p,status\)/);assert.match(c,/Repo.needsOnboarding\(me,status\)/);
});
