#!/usr/bin/env python3
"""Create the packaged Android-only HTML, using the exact latest Sphere website source.
No iframe to Render, no iOS/desktop stylesheet, no changes to production HTML.
"""
from pathlib import Path
import re
import shutil

root = Path(__file__).resolve().parents[1]
dest = root / "webview-android-out/app/src/main/assets"
dest.mkdir(parents=True, exist_ok=True)

for folder in ("img", "vendor"):
    src = root / folder
    if not src.is_dir():
        raise SystemExit(f"Required website asset folder missing: {src}")
    shutil.copytree(src, dest / folder, dirs_exist_ok=True)

# Only files the Android app actually loads. No PC/iOS-specific styles or touch icons.
for name in ("sphere-dark-theme.css", "favicon.png", "contact.html", "terms.html",
             "privacy.html", "refund.html", "delete-account.html", "icon-192.png"):
    src = root / name
    if src.is_file():
        shutil.copy2(src, dest / name)

html = (root / "index.html.html").read_text(encoding="utf-8")
html = re.sub(r'<link[^>]+href=["\'](?:/)?sphere-desktop\.css[^"\']*["\'][^>]*>', "", html, flags=re.I)
html = re.sub(r'<link[^>]+(?:rel=["\']apple-touch-icon["\']|href=["\']/apple-touch-icon)[^>]*>', "", html, flags=re.I)
html = re.sub(r'<meta[^>]+(?:apple-mobile-web-app)[^>]*>', "", html, flags=re.I)
html = re.sub(r'<link[^>]+rel=["\']manifest["\'][^>]*>', "", html, flags=re.I)

# No PWA worker in packaged WebView. Static resources already exist inside the APK.
html = html.replace("if('serviceWorker' in navigator){", "if(false && 'serviceWorker' in navigator){")

before = """<script>
// Sphere APK: trusted origin-only native message interface.
window.SphereAndroid = Object.freeze({
  openExternal: function(url) {
    if(window.SphereNative) window.SphereNative.postMessage(JSON.stringify({action:'external',url:String(url)}));
  },
  requestGoogleSignIn: function() {
    if(window.SphereNative) window.SphereNative.postMessage(JSON.stringify({action:'google'}));
    else alert('Android sign-in is unavailable on this device.');
  }
});
document.documentElement.classList.remove('os-other','os-ios','sphere-desktop');
document.documentElement.classList.add('os-android');
</script>
<style>
/* Android only — never show PC/iOS chrome inside the APK. */
html.sphere-desktop,html.os-other{max-width:none}
#sphereDesktopNav,#sphereDesktopTop,.sphere-ios-back-cue{display:none!important}
html,body{max-width:480px!important;margin-left:auto!important;margin-right:auto!important}
</style>
"""
if "<head>" not in html:
    raise SystemExit("Website HTML missing <head>")
html = html.replace("<head>", "<head>\n" + before, 1)

google = """<script>
// Native Credential Manager sign-in: no embedded Google OAuth WebView.
window.signInWithGoogle = function() {
  if(window.SphereAndroid) window.SphereAndroid.requestGoogleSignIn();
};
window.sphereNativeGoogleResult = async function(payload) {
  if(!payload) return;
  if(payload.error){ alert(payload.error); return; }
  if(!payload.token || !payload.nonce){ alert('Google did not return a login token.'); return; }
  try {
    const { error } = await sb.auth.signInWithIdToken({
      provider: 'google', token: payload.token, nonce: payload.nonce
    });
    if(error) { alert('Google login failed: ' + error.message); return; }
    const profile = await fetchAndSetCurrentUser();
    if(profile) { nav(typeof sphereEntryScreen === 'function' ? sphereEntryScreen(profile) : 'home'); return; }
    const { data: { user: au } } = await sb.auth.getUser();
    if(au) { pendingAuthUser = au; nav('chooseRole'); }
    else alert('Could not load the account after Google sign-in.');
  } catch(e) { alert('Could not complete Google sign-in. Check internet and try again.'); }
};
</script>
"""
if "</body>" not in html:
    raise SystemExit("Website HTML missing </body>")
html = html.replace("</body>", google + "</body>", 1)
(dest / "index.html").write_text(html, encoding="utf-8")

# Fail the release if the included Android app bridge or runtime dependencies are missing.
assert "const IN_ANDROID_APP" in html and "SphereApp/" in html
assert "window.sphereNativeGoogleResult" in html
assert (dest / "vendor/supabase-2.117.2.js").is_file()
assert len(list((dest / "img").rglob("*"))) > 20
print("Android-only packaged Sphere site:", len(html), "HTML chars;",
      len(list(dest.rglob("*"))), "packaged asset entries")
