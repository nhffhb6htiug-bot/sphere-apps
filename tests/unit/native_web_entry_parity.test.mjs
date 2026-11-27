import test from "node:test";import assert from "node:assert/strict";import fs from "node:fs";
const root="android-native/app/src/main/";
const read=p=>fs.readFileSync(root+"java/com/syahifilms/sphere/ui/"+p,"utf8");
test("Native onboarding uses original web art and ordered copy",()=>{
const d=read("NativeAuthDesign.kt"),nav=read("Nav.kt"),auth=read("AuthScreens.kt");
for(const [asset,web,title] of [["onboard_hire","082a0646075c735b","Hire Top Editors"],["onboard_chat","9823ae8fa53bb565","Direct Editor Chat"],["onboard_vault","c055b24fc823715f","Secure Project Vault"],["auth_landing","15ff7b3e628d1cb7","Sphere"]]){
 assert.ok(d.includes(title));assert.ok(fs.readFileSync(root+"res/drawable-nodpi/"+asset+".webp").equals(fs.readFileSync("img/"+web+".webp")));
}
assert.match(nav,/onboard\/\{page\}/);assert.match(auth,/Config.previewConfigured\) "onboard\/0"/);
assert.match(d,/enabled=googleReady&&!busy/);
for(const x of ["Get Started","Skip ›","Log In","Sign Up","Contact"])assert.ok(d.includes(x));
assert.match(auth,/AuthFormLayout\("Welcome Back", "Login to continue"/);
});
test("Default visual palette follows the web October glass theme",()=>{
const d=read("WebsiteDesign.kt"),c=read("Common.kt");
for(const x of ["0xFFF9D3EA","0xFFFFEADB","0xFFE8DEFE","0xFFF6D8F3","0xFF7735ED","0xFFA64CDE","0xFFDF6FAE"])assert.ok(d.includes(x));
assert.ok(c.includes("0xFF7139E4"));assert.ok(c.includes("0xFF100C16"));
});
