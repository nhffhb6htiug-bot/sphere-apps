// Regression checks for Sphere's startup screen across web/PWA and Android.
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

const html = fs.readFileSync("index.html.html","utf8");
const manifest = JSON.parse(fs.readFileSync("manifest.json","utf8"));
const sw = fs.readFileSync("sw.js","utf8");
const android = fs.readFileSync("android-native/app/src/main/java/com/syahifilms/sphere/MainActivity.kt","utf8");
const native = fs.readFileSync("android-native/app/src/main/java/com/syahifilms/sphere/ui/AuthScreens.kt","utf8");

test("Initial HTML paints Sphere splash and loader before the external scripts",()=>{
  const initial = html.indexOf('<div id="app">');
  const vendors = html.indexOf('src="vendor/');
  assert.ok(initial > 0);
  assert.ok(html.slice(initial, initial+600).includes('splash-wrap sphere-launch-screen'));
  assert.ok(html.slice(initial, initial+700).includes('sp-loader sp-loader-big'));
  assert.ok(html.slice(initial, initial+700).includes('Connecting Editors &amp; Clients'));
  assert.ok(html.includes("Sphere is taking longer than expected"));
});

test("Every dynamic splash includes a spinner and a user-controlled retry",()=>{
  const renderer = html.slice(html.indexOf("SCREENS.splash = () => {"),html.indexOf("const onboardData = ["));
  assert.ok(renderer.includes('sp-loader sp-loader-big'));
  assert.ok(renderer.includes("nav('splash')"));
  assert.ok(renderer.includes("catch(e)"));
});

test("PWA starts pastel instead of black on iPhone and PC",()=>{
  assert.equal(manifest.background_color,"#fde9e1");
  assert.equal(manifest.theme_color,"#fde9e1");
  assert.match(html, /apple-mobile-web-app-status-bar-style" content="default"/);
  assert.match(sw,/sphere-pastel-startup-v20/);
});

test("APK has a native loading view while the WebView renders",()=>{
  assert.ok(android.includes("createSplashOverlay()"));
  assert.ok(android.includes("onPageCommitVisible"));
  assert.ok(android.includes("showSplashNetworkError()"));
  assert.ok(android.includes("browser.reload()"));
  assert.ok(native.includes('Text("Connecting Editors & Clients"'));
  assert.ok(native.includes("CircularProgressIndicator("));
});
