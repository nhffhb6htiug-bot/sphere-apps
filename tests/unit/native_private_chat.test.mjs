import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
const root="android-native/app/src/main/java/com/syahifilms/sphere/";
const read=p=>fs.readFileSync(root+p,"utf8");
test("Private typing has no public fallback and is conversation scoped",()=>{
  const src=read("data/PrivateChatPresence.kt"),ui=read("ui/NativeChatScreen.kt"),sql=fs.readFileSync("docs/staged-private-chat-rls.sql","utf8");
  assert.match(src,/put\("private",true\)/);
  assert.match(src,/listOf\(owner,peer\).sorted\(\)/);
  assert.match(src,/data.str\("from"\) != peer/);
  assert.match(sql,/me not in \(a,b\)/);
  assert.match(sql,/public.sp_last_seen\(peer\)/);
  assert.match(ui,/!foreground \|\| blocked \|\| !blockKnown \|\| ownSeen != true/);
  assert.match(ui,/withTimeout\(45000\)/);
});
test("Push receiver rejects wrong accounts and never displays message text",()=>{
  const src=read("data/SpherePush.kt"),manifest=fs.readFileSync("android-native/app/src/main/AndroidManifest.xml","utf8");
  assert.match(src,/Api.userId != owner/);
  assert.match(src,/!enabled\(context,owner\)/);
  assert.match(src,/POST_NOTIFICATIONS/);
  assert.match(src,/VISIBILITY_PRIVATE/);
  assert.doesNotMatch(src,/message.notification|message.data\["text"\]/);
  assert.match(manifest,/firebase_messaging_auto_init_enabled" android:value="false"/);
});
