// Static, read-only checks for the actual production HTML entrypoint.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";

const htmlPath = "index.html.html";
const html = fs.readFileSync(htmlPath, "utf8");
let errors = [];
let checks = [];
const assert = (ok, label) => { checks.push({label, passed:ok}); if(!ok)errors.push(label); };
assert(html.startsWith("<!DOCTYPE html>"), "HTML doctype");
assert(/<meta[^>]+name=["']viewport["']/i.test(html), "Responsive viewport");
assert(/Content-Security-Policy/i.test(html), "Content Security Policy");
assert(/\bSCREENS\.home\s*=/.test(html), "Home route exists");
assert(/\bSCREENS\.(authLanding|login)\s*=/.test(html), "Login route exists");
assert(/\bSCREENS\.profile\s*=/.test(html), "Profile route exists");
assert(/\bSCREENS\.chatList\s*=/.test(html), "Chat list route exists");
assert(/if\s*\(t\s*&&\s*t\.isConnected\s*&&\s*t\.parentElement\)\s*t\.outerHTML\s*=\s*tickHtml\(m\)/.test(html),
  "Chat receipt DOM update checks for detached elements before mutation");

const matches = [...html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/gi)];
let inlineCount=0;
for (let i=0;i<matches.length;i++) {
  const [,attrs,source] = matches[i];
  if (/\bsrc\s*=/.test(attrs) || /^\s*$/.test(source) || /type\s*=\s*["']application\/(?:json|ld\+json)/i.test(attrs)) continue;
  inlineCount++;
  const tmp = path.join(os.tmpdir(),"sphere-audit-script-"+process.pid+"-"+i+".js");
  fs.writeFileSync(tmp, source);
  const p = spawnSync(process.execPath,["--check",tmp],{encoding:"utf8"});
  try { fs.unlinkSync(tmp); } catch {}
  assert(p.status===0, "Inline JS "+i+" syntax"+(p.status===0?"":": "+(p.stderr||"").slice(-250)));
}
assert(inlineCount>0,"Inline JS found");

const imagePaths=[...html.matchAll(/['"`](\/img\/[^'"`\s?]+\.(?:webp|png|svg|jpg|jpeg))(?:\?[^'"`]*)?['"`]/gi)]
  .map(x=>x[1]).filter((v,i,a)=>a.indexOf(v)===i);
const missing=imagePaths.filter(x=>!fs.existsSync(x.slice(1)));
assert(missing.length===0,"Local icon assets present (missing: "+missing.slice(0,10).join(", ")+")");

const apkBuild=fs.readFileSync("android-native/app/build.gradle.kts","utf8");
assert(/versionCode\s*=\s*\d+/.test(apkBuild),"Android versionCode present");
assert(/applicationId\s*=\s*"com\.syahifilms\.sphere"/.test(apkBuild),"Android package stable");
const manifest=fs.readFileSync("android-native/app/src/main/AndroidManifest.xml","utf8");
assert(/allowBackup="false"/.test(manifest),"Android session backup disabled");
const repo=fs.readFileSync("android-native/app/src/main/java/com/syahifilms/sphere/data/Repo.kt","utf8");
assert(repo.includes('sp_files_add_link'),"Native preview uses secure RPC");
assert(repo.includes('sp_final_submit'),"Native final uses secure RPC");
assert(repo.includes('sp_rating_submit'),"Native rating uses secure RPC");
const nativeApi = fs.readFileSync("android-native/app/src/main/java/com/syahifilms/sphere/data/Api.kt","utf8");
assert(nativeApi.includes("private val sessionWriteLock = Any()"),"Native session writes serialized");
assert(nativeApi.includes('if (session()?.optString("refresh_token") != refreshToken)'),
  "Native stale refresh cannot overwrite a new login");
assert(nativeApi.includes('if (session()?.optString("refresh_token") == refreshToken) clearSession()'),
  "Native old refresh errors cannot clear the new session");
assert(!repo.includes('put("status", "delivered")'),"Native cannot directly set delivered status");

// A selected video may be hundreds of MB. Never read it without a byte cap,
// and do not erase a typed caption if the upload fails.
const nativeChat = fs.readFileSync("android-native/app/src/main/java/com/syahifilms/sphere/ui/ChatProfileScreens.kt","utf8");
assert(!nativeChat.includes("it.readBytes()"),"Native chat picker does not read unbounded media");
assert(/bytesRead\s*>\s*maxMediaBytes/.test(nativeChat) && /50L\s*\*\s*1024\s*\*\s*1024/.test(nativeChat),
  "Native chat rejects media above 50MB while reading");
assert(/Repo\.sendMedia\(me, otherId, bytes, mime, caption\)[\s\S]*?if \(text\.trim\(\) == caption\) text = ""/.test(nativeChat),
  "Native chat preserves message caption until media upload succeeds");
assert((nativeChat.match(/try \{ messages = Repo\.thread\(otherId\) \} catch \(_: Exception\) \{ \}/g) || []).length >= 2,
  "Native chat distinguishes successful sends from subsequent refresh failures");

console.log(JSON.stringify({checks,scriptCount:inlineCount,imagesChecked:imagePaths.length},null,2));
if(errors.length) process.exitCode=1;
