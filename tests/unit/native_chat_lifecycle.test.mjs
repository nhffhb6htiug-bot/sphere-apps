import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
const root="android-native/app/src/main/java/com/syahifilms/sphere/";
const read=p=>fs.readFileSync(root+p,"utf8");
test("Typing expires and chat sends are independent of refresh",()=>{
 const ui=read("ui/NativeChatScreen.kt");
 assert.match(ui,/elapsedRealtime\(\) - latestEdit.value < 4000/);
 assert.match(ui,/lastEditAt = android.os.SystemClock.elapsedRealtime\(\)/);
 assert.doesNotMatch(ui,/LaunchedEffect\(refresh,queueReady/);
 assert.match(ui,/retryDelay \* 2\).coerceIn\(5000L,60000L\)/);
 assert.match(ui,/!latestForeground.value \|\| !canDrain.value/);
 assert.match(ui,/LaunchedEffect\(otherId,refresh,foreground\)/);
});
test("Push alerts reset on logout and account switch; configuration remains optional",()=>{
 const api=read("data/Api.kt");
 assert.match(api,/session\(\)\?\.optString\("user_id"\) != s.optString\("user_id"\)/);
 assert.match(api,/fun clearSession\(\)[\s\S]*?SpherePush.clearLocalAlerts/);
 const build=fs.readFileSync("android-native/app/build.gradle.kts","utf8");
 assert.match(build,/if \(file\("google-services.json"\).isFile\)/);
 assert.match(read("data/PrivateChatPresence.kt"),/tick >= 10 && !joined.get\(\)/);
});
