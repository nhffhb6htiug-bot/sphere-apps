import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
const root="android-native/app/src/main/java/com/syahifilms/sphere/";
const read=p=>fs.readFileSync(root+p,"utf8");
test("Native chat uses scoped realtime invalidation and private media",()=>{
  const socket=read("data/ChatRealtime.kt"),api=read("data/Api.kt"),ui=read("ui/NativeChatScreen.kt");
  assert.match(socket,/postgres_changes/);
  assert.match(socket,/access_token/);
  assert.match(socket,/awaitClose/);
  assert.match(api,/object\/sign\/sphere-chat/);
  assert.match(api,/uploadChatFile[\s\S]*?file\.asRequestBody/);
  assert.match(ui,/Api\.chatMediaUrl/);
  assert.doesNotMatch(ui,/publicUrl/);
});
test("Offline queue encrypts account-scoped text and reconciles stable ids",()=>{
  const data=read("data/NativeChat.kt"),ui=read("ui/NativeChatScreen.kt");
  assert.match(data,/AndroidKeyStore/);
  assert.match(data,/AES\/GCM\/NoPadding/);
  assert.match(data,/Api\.userId == owner/);
  assert.match(data,/existing\(owner,pending\.peer,pending\.id\)/);
  assert.match(data,/put\("reply_to",pending\.reply\)/);
  assert.match(ui,/Search loaded messages/);
  assert.match(data,/sp_last_seen/);
});
