# Android FCM release gates
The receiver is compiled with Firebase Messaging 24.1.2, auto-init off, data-only event filtering, Android 13+ permission and a generic private notification. No real Firebase project, token registration or dispatcher is configured by this patch. The preview intentionally does not obtain/send registration tokens.
 
Before enabling:
1. Owner creates or confirms a Firebase Android app for com.syahifilms.sphere, configures the appropriate Firebase client resources/google-services plugin and verifies the signing fingerprints where needed. Never commit a service account private key.
2. Implement authenticated device registration with ownership derived from JWT, opt-out, token rotation, logout/revocation and account deletion. Avoid readable cross-user token tables. Use a device identifier and revoke previous user mapping at account switch.
3. Trusted server only sends FCM HTTP v1 data-only messages for authorized notification records; never accept client-chosen recipient/token or raw chat text. Store service credentials exclusively in server secret storage. Payload fields: kind=sphere_notice, owner, notice_id. Do not use FCM notification payload because Android may display it automatically without receiver account validation.
4. Test real devices: permission denied, background, process death, token rotation, logout/account switch, block/report, revoked session, offline reconnection and generic lock screen. A force-stopped app is not guaranteed delivery.
5. Update privacy policy/Data Safety and opt-in. No claim of end-to-end encryption or guaranteed delivery.
