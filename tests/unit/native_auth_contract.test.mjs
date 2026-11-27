import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
const root="android-native/app/src/main/java/com/syahifilms/sphere/";
const read=p=>fs.readFileSync(root+p,"utf8");
test("Native phone OTP uses existing Supabase verify and preference contracts",()=>{
  const api=read("data/Api.kt");
  for (const text of ['"/auth/v1/otp"','"/auth/v1/verify"','"sp_otp_prefer"','.put("type", "sms")','.put("token", code)']) assert.ok(api.includes(text),text);
  assert.match(api,/verifyPhoneOtp[\s\S]*?finishLogin\(result,epoch\)/);
});
test("Native entry and protected screens check actual server account state",()=>{
  const auth=read("data/NativeAuth.kt"), nav=read("ui/Nav.kt"), common=read("ui/Common.kt"), guard=read("ui/NativeAuthScreens.kt");
  assert.match(auth,/sp_core_whoami/);
  assert.match(auth,/sp_phone_verify_status/);
  assert.match(common,/status\?\.optBoolean\("suspended"\) == true/);
  for(const route of ["home","jobs","profile","chats","payments","escrow","editorDetails"]) assert.ok(nav.includes('composable("'+route+'") { NativeAccountGate(nav)'));
  assert.match(guard,/if \(ready && readyOwner != null && readyOwner == Api.userId\) content\(\)/);
  assert.match(auth,/sp_phone_verify_start/);
  assert.doesNotMatch(read("data/Repo.kt"),/put\("role", meta\.str/);
});
test("OTP UI honors feature switches; phone verification trusts only server",()=>{
  const ui=read("ui/NativeAuthScreens.kt"),auth=read("data/NativeAuth.kt");
  assert.match(ui,/if \(!NativeAuth\.settings\(\)\.otpLogin\)/);
  assert.match(ui,/wait = 30/);
  assert.match(auth,/status\.getBoolean\("required"\) && !status\.getBoolean\("verified"\)/);
  assert.match(auth,/!settings\.waRequired/);
});
