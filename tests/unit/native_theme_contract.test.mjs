import test from "node:test";import assert from "node:assert/strict";import fs from "node:fs";
const root="android-native/app/src/main/java/com/syahifilms/sphere/";
const read=p=>fs.readFileSync(root+p,"utf8");
test("Native theme is opt-in, persistent and matches web dark palette",()=>{
 const common=read("ui/Common.kt"),design=read("ui/WebsiteDesign.kt"),settings=read("ui/WebsiteFeatureScreens.kt");
 assert.match(common,/Api.setPref\("appearance",value\)/);assert.match(common,/darkColorScheme\(/);
 for(const color of ["0xFF100C16","0xFF241A2B","0xFFC69AFF"])assert.ok(common.includes(color));
 assert.match(design,/0xFFAA4FBB/);assert.match(settings,/SphereAppearance.setAppearance\("dark"\)/);
 assert.match(common,/widthIn\(max = 640.dp\)/);
});
test("Splash launch count is bounded and legacy UPI checkout is disabled",()=>{
 const common=read("ui/Common.kt"),main=read("MainActivity.kt"),auth=read("ui/AuthScreens.kt");
 assert.match(main,/SphereAppearance.initialize\(savedInstanceState == null\)/);
 assert.match(common,/initialSplashMotion = count < 4/);
 assert.match(auth,/if \(animate && error == null\) CircularProgressIndicator/);
 assert.doesNotMatch(common,/upi:\/\/pay|fee_qr/);
 assert.match(read("data/PreviewEncoder.kt"),/listOf<androidx.media3.effect.TextureOverlay>\(mark\)/);
});
