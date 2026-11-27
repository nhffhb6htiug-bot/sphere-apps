import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
const root="android-native/app/src/main/java/com/syahifilms/sphere/";
const read=p=>fs.readFileSync(root+p,"utf8");
test("Project attachments match private storage contract and streaming limits",()=>{
  const data=read("data/ProjectMedia.kt"), api=read("data/Api.kt"), projects=read("data/NativeProjects.kt");
  assert.match(data,/MAX_FILES = 5/);
  assert.match(data,/MAX_BYTES = 50L \* 1024 \* 1024/);
  assert.match(data,/total <= MAX_BYTES/);
  assert.match(data,/!reference \|\| mime\.startsWith\("video\/"\)/);
  assert.match(api,/file\.asRequestBody/);
  assert.match(api,/object\/sign\/sphere-raw/);
  assert.match(projects,/\.put\("raw_files", rawFiles\)/);
  assert.match(projects,/item\.put\("kind", "reference"\)/);
});
test("Native form uses system selection/capture, actual video frames, review and private drafts",()=>{
  const ui=read("ui/ProjectComposer.kt"), projects=read("data/NativeProjects.kt");
  for (const s of ["OpenMultipleDocuments","PickMultipleVisualMedia","TakePicture","CaptureVideo","getScaledFrameAtTime","VideoView","Done · Review","Save as draft","ProjectDraftsScreen"]) assert.ok(ui.includes(s),s);
  assert.match(projects,/sp_job_drafts\?client_id=eq\./);
  assert.match(projects,/val existing = Repo\.job\(requestId\)/);
  assert.match(projects,/require\(fields\.str\("audience"\) != "premium"\)/);
});
