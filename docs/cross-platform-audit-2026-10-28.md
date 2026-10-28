# Sphere cross-platform audit — 2026-10-28

Scope: Render static PWA on Android Chrome, iPhone Safari/WebKit and Windows desktop; Kotlin/Jetpack Compose native Android APK; Supabase Auth, Postgres/RLS, Edge Functions and project-payment workflow.

**Important distinction:** Source inspection, automated browser smoke tests, database policy tests and successful APK compilation do **not** certify every logged-in screen, native device, bank transfer, refund or notification. No real payment/refund was executed, and no customer data was intentionally modified.

## Verified fixes

1. **Database excessive privileges (critical)**: Migration `048_security_permission_hardening.sql` applied to live project. Revoked `TRUNCATE`, `TRIGGER`, `REFERENCES` and `MAINTAIN` from `anon` and `authenticated` for all public base tables. Confirmed 0 exposed tables retain the tested TRUNCATE/TRIGGER privileges. Also removed `sp17_prof_read` (`USING(true)`) to stop broad access to profiles including phone/email; kept owner/admin/connected-party read policy. Test-transaction simulation: authenticated owner sees own profile, nonmember dummy ID sees none. Anonymous has no private table SELECT grant.
2. **Premium jobs / bids policy conflict (critical)**: Migration `049_premium_jobs_bid_rls_cleanup.sql` applied. Removed old `sp_jobs_select` policy (allowed all open jobs independent of premium audience), and redundant `sp17_apps_write` / old bid DELETE policies that could weaken selected-bid deletion protection. Validated 2 job SELECT and 1 bid DELETE policies remain; own job visibility unaffected in rollback simulation.
3. **Native Android project flow (high)**: Direct `sp_jobs.status='delivered'` patch replaced with `sp_files_add_link`, client `sp_approve_preview`, editor `sp_final_submit`, and server-only release with explicit user confirmation. Rating now uses `sp_rating_submit` from −3 to +3 instead of incompatible old 1–5 direct table write. Server denies unauthorized transitions.
4. **Native payout confirmation (high)**: UI now requires server JSON `ok=true`, rather than treating an unsuccessful JSON response as a success.
5. **Native credential backup**: `allowBackup=false` prevents automatic Android backup of login-session preferences.
6. **Google sign-in display**: A visible Google "G" icon with safe busy reset in login button; actual OAuth eligibility still needs signing configuration.
7. **APK distribution stability**: Android workflow supports private GitHub secret `SPHERE_DEBUG_KEYSTORE_B64` for stable debug signing and writes SHA1/SHA256 signing certificate fingerprints. This secret is **not** created by the audit.
8. **Static website tests**: Source HTML/JS syntax checks all pass (5 inline scripts), all 36 referenced icons exist, and Android native secure RPC checks pass.
9. **Cross-browser smoke tests**: GitHub Actions Chromium/WebKit run 40747314342 passed all 8 viewport cases (Android 360/412, iPhone Safari-like 375/390, iPad 820, desktop 1024/1366/1920). No initial auth screen JS uncaught errors or horizontal overflow; these tests deliberately block external APIs and do not sign into real user accounts.

## Not certified / release blockers

- **Real-world end to end**: Need consented nonfinancial test accounts, physical iOS/Android handsets, network offline/reconnect, deep links, image picker, attachments, background notifications and accessibility checks.
- **Native Google OAuth**: Register SHA1 signing certificate fingerprint and package `com.syahifilms.sphere` in Google Cloud Android OAuth. Configure correct web client ID and origins. Temporary GitHub runner debug keystore will rotate unless private signing secret is configured; do not publish any private signing material.
- **Stable Play Store release**: Current build is a debug APK, not a production signed AAB. Play Store compliance and organization/guardian account setup are separate.
- **Payment flow**: Real Razorpay settlement/refund/failed transfer, webhook retries, double submit, stale auth and 3DS are **not exercised**. `release-payout` Edge Function has remote transfer API interactions before updating the DB; idempotency/reconciliation requires targeted finance audit before major changes. Do not run live-money tests casually.
- **Native feature parity**: The Kotlin app does not yet contain all website features (e.g. some checkout flows redirect to website), so Render downtime may still affect those functions.
- **Supabase advisors**: 4 SECURITY DEFINER views and many definer RPCs were flagged. The public profiles view intentionally exposes sanitized editor fields with public visibility; changing it to invoker without redesigned access model would break editor directory. Audit function-by-function, not broad revoke. Review `sp_otp_prefer` (publicly executable for pre-login flow), and enable leaked-password protection in Supabase Auth settings if available.
- **Scale/traffic**: No load test for 100–200 simultaneous users was run against production; avoid availability/financial impact.

## Test and implementation references

- Browser CI: https://github.com/nhffhb6htiug-bot/sphere-apps/actions/runs/40747314342
- Android audit CI: https://github.com/nhffhb6htiug-bot/sphere-apps/actions/runs/40747314304
- Migration 048 and 049 in this branch.
- `tests/audit-static.mjs`, `tests/audit-browser.mjs`, `.github/workflows/audit-cross-platform.yml`

Future regression gates: signed-in client/editor/admin test data with role-based visibility assertions, physical device screenshot snapshots, server idempotency unit tests, accessibility focus/contrast, network throttling, browser console and mobile crash reports.
