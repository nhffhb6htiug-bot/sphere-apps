import test from "node:test";import assert from "node:assert/strict";import fs from "node:fs";
const root="android-native/app/src/main/java/com/syahifilms/sphere/";
const read=p=>fs.readFileSync(root+p,"utf8");
test("Preview upload uses encoded output and existing private upload contracts",()=>{
 const enc=read("data/PreviewEncoder.kt"),api=read("data/Api.kt"),data=read("data/NativeDelivery.kt"),ui=read("ui/NativeDeliveryPanel.kt");
 assert.match(enc,/getOverlaySettings\(presentationTimeUs:Long\)/);assert.match(enc,/OverlayEffect/);assert.match(enc,/out.length\(\) in 1L..limit/);
 assert.match(ui,/val encoded=PreviewEncoder.encode/);assert.match(ui,/NativeDelivery.uploadEncodedPreview\(job,encoded/);assert.doesNotMatch(ui,/uploadEncodedPreview\(job,original/);
 assert.match(data,/sp_files_begin/);assert.match(data,/sp_files_finish/);assert.match(data,/encoded.media/);assert.match(api,/uploadDeliveryFile[\s\S]*?file.asRequestBody/);
});
test("Change attachments pass server-confirmed ids and private signed links",()=>{
 const ui=read("ui/NativeDeliveryPanel.kt"),data=read("data/NativeDelivery.kt");
 assert.match(ui,/OpenMultipleDocuments/);assert.match(ui,/attachmentIds=attachmentIds\+id/);assert.match(data,/put\("p_file_ids",JSONArray\(fileIds\)\)/);assert.match(ui,/Api.deliveryFileUrl/);
});
