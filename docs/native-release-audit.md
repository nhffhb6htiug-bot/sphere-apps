# Sphere native A–Z release audit — 2026-11-27
Source baseline dffb78c; branch native-compose-task-02. No live accounts, media, messages, payments, or admin actions used; no production changes. Current assessment is source/CI only, not an end-to-end certification.

## CI history
13d690f obsolete WebView splash assertion failed; 87e95d9 both workflows passed. c9bcfd7/82260b4 chat static regression failed; cf04694/e6a5bfa both passed. 26bcf03 and d429866 native compile failed on Media3 TextureOverlay type; 31849ea compile and smoke passed. de66fd4 initial admin native build and cross-platform passed. dffb78c follow-up queued/running at audit start. Prior success is not proof of current build.

## Prioritized remaining gates
P0 means no production release. P1 means required before declaring feature parity.

| ID | Priority | Area | Status / required acceptance |
|---|---|---|---|
| 01 | P0 | Preview isolation | Separate package and explicit staging-only config added. Provision isolated Supabase with sanitized fixtures, no production secrets or provider webhooks; default preview offline. |
| 02 | P0 | Current CI | Compile, lint, JVM unit, cross-platform and security source tests must pass on exact final SHA. |
| 03 | P0 | Auth | Register preview OAuth package/SHA and verify Google account picker, email, OTP, logout/revocation and blocked accounts; stage verified recovery callback; email OTP parity pending. |
| 04 | P0 | Session / RLS | Encrypt session at rest; test anon/client/editor/admin access to phone/code/attachments, direct final-file reads before release, revoked sessions and cross-account races. Source guards not server authorization. |
| 05 | P1 | Composer | Draft media persistence, direct-hire draft target, premium and AI composer, three suggested editors, media/process-death and orphan cleanup. |
| 06 | P1 | Chat | Private channel RLS migration and web parity, online status, typing, full history pagination/search, offline media and voice; test moderation/block/retry. |
| 07 | P1 | Push | Firebase preview registration, authenticated token lifecycle and trusted data-only sender; background device tests. |
| 08 | P1 | Portfolio | Server-side 12-item cap/concurrency, image orphan cleanup, proof/reapply and profile completion; verify photo/video rendering. |
| 09 | P0 | Delivery | Actual encoder audio/rotation/duration/size/cancellation tests, signed URLs, server final-file authorization, upload recovery; PDF/audio/ZIP native attachments pending. |
| 10 | P0 | Payment security | Captured amount/currency/order/owner verification, unique receipt, durable order claims, shared release/refund lock, reconciliation and webhook recovery. No real payment. See native-payment-audit.md. |
| 11 | P0 | Billing | Play policy classification, appropriate billing/provider test integration, receipt validation, premium/contact/verification, paid revision, refund and payout tests with authorized adult merchant. |
| 12 | P1 | UI | Theme consistency and all screens, back stack, scroll, keyboard, small/large displays, accessibility, splash and orientation tests. |
| 13 | P0 | Admin | New mutation controls only simulated. Existing outreach gated by PIN; staging tests, server MFA/session/suspension and target/state checks, atomic reopen, projections, dispute/settings/moderation/financial parity. See native-admin-release-gates.md. |
| 14 | P0 | Account/privacy | In-app and external account deletion flow, retention/disclosure/consent, reporting and blocking across flows; verify actual published links and Play Data Safety. |
| 15 | P0 | Packaging | Confirm release signing by authorized owner, versionCode > published artifact if needed, target SDK policy, 64-bit and 16 KB alignment, Play testing requirements, signed AAB after release gates pass. |
| 16 | P0 | Physical QA | Test separate preview on two Android devices with synthetic client/editor/admin accounts; camera, media, offline, permissions, cold start and process death; no real transactions. |

## Fixes started
Preview applicationIdSuffix .preview, distinct launcher label, explicit staging URL and matching anon-only legacy JWT claims, no prod fallback; optional staging OAuth ID. Raw transport disallows redirects and automatic retry; explicitly retries GET only. Session/account checks, logout race handling, external link allowlist, no cleartext, failed loads clear stale data. Password recovery blocked until staging redirect. These are defense-in-depth; real RLS and payment/admin authorization are still mandatory.

## Build and test instructions
Default CI intentionally supplies no staging URL/key: install preview alongside original; access local payment simulator/theme, no login. For connected QA, authorized project owner provisions a separate Supabase instance with synthetic data and copies required reviewed schema/config only. Set SPHERE_PREVIEW_SUPABASE_URL and SPHERE_PREVIEW_SUPABASE_ANON_KEY in local build environment (direct project URL and legacy anon JWT for that staging ref, never service_role). Optional SPHERE_PREVIEW_GOOGLE_CLIENT_ID is staging OAuth web ID; register com.syahifilms.sphere.preview and installed signing SHA separately. Preview Firebase client resources must match preview package if configured. Do not copy production keys, accounts, contact details, transaction references, or provider service credentials. No real recovery, OTP delivery, provider charges or payout until configured isolated test paths. Release preReleaseBuild remains blocked.

## Go/no-go
NO-GO for public Play release. Source parity is partial; no physical device or authenticated RLS tests completed by this audit. CI only checks code/build, not provider or device behavior. Fix P0 gates first, then P1 parity; update exact evidence and obtain explicit approval for production deployment.
