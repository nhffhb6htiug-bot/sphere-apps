# Sphere native Android APK + Play Store AAB automation

The real **Kotlin/Jetpack Compose** Android app lives on the branch
`release/native-compose-no-webview-20261110`, under `android-native/`.
The branch's GitHub Actions workflow builds when files under `android-native/**`
or the workflow itself change, and can also be started manually under **Actions**.

## Output files

- **Sphere-Native-Debug-APK** — test-only debug APK, generated on every successful compile.
- **Sphere-Native-Release-APK** — release-signed APK, only when all signing secrets exist.
- **Sphere-Native-PlayStore-AAB** — release-signed, signature-verified AAB, only when all signing secrets exist.
- **Sphere-Native-UNSIGNED-AAB-NOT-FOR-PLAY** — when signing is not set up, for diagnosis/offline signing only. Do **not** upload this to Play Console.

Download files from **Actions → Build Sphere Android app → latest successful run → Artifacts**.
GitHub artifact retention is limited to 30 days for the signed outputs.

## One-time signing setup (must be done by the account owner)

Go to **Repository → Settings → Secrets and variables → Actions → New repository secret**.
Set all four repository secrets using your existing secure Sphere upload keystore:

1. `SPHERE_RELEASE_KEYSTORE_B64`: base64 encoding of the **binary** existing upload-keystore `.jks` (no whitespace).
2. `SPHERE_RELEASE_STORE_PASSWORD`: existing keystore password.
3. `SPHERE_RELEASE_KEY_ALIAS`: existing key alias.
4. `SPHERE_RELEASE_KEY_PASSWORD`: existing key password.

Generate the base64 **locally**, not on a public website. On Windows PowerShell:
```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\\path\\to\\Sphere-Android-Upload-Key.jks"))
```
Use the correct file path. **Never** put the keystore, passwords, or base64 string into a commit, issue, chat screenshot, or public file. Keep a secure backup of the key and credentials.

Play Console may already have an upload certificate associated with this package name. If so, use the matching existing upload key, or request an upload-key reset through the account owner. Do **not** silently switch upload keys between releases.

## Version numbers

Actions sets `SPHERE_CI_VERSION_CODE=100000 + GITHUB_RUN_NUMBER`. This means each CI build gets a new, increasing Android versionCode; the app's native Kotlin source does **not** change merely because the build ran. Manually change the base versionName in `app/build.gradle.kts` for a major public release.

## Limits

- A GitHub build does **not** publish the app to the Play Store automatically.
- Google Play review, testing, app content declarations, and account checks remain separate steps.
- Website updates on `main` are not automatically included in this native Compose branch.
- Run a real Android-device smoke test on authentication, chat, payments, and navigation before uploading a new release.
