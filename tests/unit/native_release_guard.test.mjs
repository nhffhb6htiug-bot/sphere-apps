import test from "node:test";import assert from "node:assert/strict";import fs from "node:fs";
const root="android-native/app/src/main/java/com/syahifilms/sphere/";
const read=p=>fs.readFileSync(root+p,"utf8");
test("Preview has independent package and fails closed without staging",()=>{
 const g=fs.readFileSync("android-native/app/build.gradle.kts","utf8"),c=read("data/Config.kt"),api=read("data/Api.kt"),auth=read("ui/AuthScreens.kt");
 assert.match(g,/applicationIdSuffix = "\.preview"/);assert.match(g,/SPHERE_PREVIEW_SUPABASE_URL/);
 assert.match(c,/claims.optString\("role"\) == "anon"/);
 assert.match(c,/claims.optString\("ref"\) == ref/);
 assert.doesNotMatch(c,/workers\.dev/);
 assert.match(api,/Config.requirePreviewBackend\(\)/);
 assert.match(auth,/if \(!Config.previewConfigured\)/);
 assert.match(g,/preReleaseBuild/);
});
test("Transport and external intents fail closed",()=>{
 const a=read("data/Api.kt"),ui=read("ui/Common.kt");
 assert.match(a,/retryOnConnectionFailure\(false\)/);
 assert.match(a,/followRedirects\(false\)/);
 assert.match(a,/expectedOwner != userId/);
 assert.match(a,/finally \{ synchronized\(sessionWriteLock\) \{ if \(userId == owner\) clearSession\(\)/);
 assert.match(ui,/else -> false/);assert.match(ui,/if\(!permitted\)/);
 assert.match(fs.readFileSync("android-native/app/src/main/AndroidManifest.xml","utf8"),/usesCleartextTraffic="false"/);
});
