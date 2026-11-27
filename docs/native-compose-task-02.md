# Task 02 — Native Compose parity (development preview)
Baseline: ba3950b494aec4126f04d99257a52c87ca95231a. Production main and Supabase remain unchanged. The launcher now uses SphereTheme and SphereNav directly instead of the Render site in WebView. Do not install the debug preview over production or use real accounts/payments. Auth and role gates require review.
 
## Implemented (source, CI pending)
- Native launcher and API initialization.
- Project form: up to four languages (comma-separated), title, length, format, style notes, HTTPS reference links in existing job fields.
- Chat reports include the reported user's ID (sp_reports.chat_user_id).
- Project checkout website redirect removed; checkout unavailable in preview.
- Release builds blocked. Debug CI compiles and lints.
 
## Remaining gates
- Email OTP, password/reset links, WhatsApp verification, suspended-account and role routing, signup terms and certificate testing.
- Raw/reference media uploads, camera/video thumbnails, private storage, drafts, premium audience, AI form, suggested editors, cancellation, revisions, changes, disputes, preview and delivery end-to-end.
- Chat presence, typing, replies, deletion, viewer, voice, retries, realtime/push and privacy settings.
- Profile/portfolio uploads, device fields, verification workflow, dark mode, settings, reports history and account deletion.
- Compliant billing, verification/contact unlock, escrow and withdrawal; do not test real payments. Existing native fee and release actions require review.
- Admin remains web-only; review whether to include in consumer app.
- RLS, auth/phone guards, 16 KB binary checks, physical-device tests and client/editor flows.
 
No release until applicable gates pass. No live backend changes or tests were performed.

## Task 02.2 — native authentication (source changes, verification pending)
- Replace obsolete WebView-specific splash assertion with Compose launcher, loading, error, retry and navigation assertions; retain web/PWA tests.
- Honor OTP and WhatsApp verification switches; add native phone OTP, resend countdown, provider preference, phone verification status/start using existing backend APIs, suspended screen and route-entry/periodic server checks. No live settings changed. Server-side RLS remains authoritative.
- Remove native profile fallback that derived roles from editable user metadata; preserve existing database role on onboarding. Add signup password rules and Terms/Privacy acknowledgement.
- Password recovery still uses the existing HTTPS website recovery link. Verified Android App Links/PKCE recovery, Google signing certificate, real OTP delivery, editor-specific verification/payment flows and physical-device runtime tests remain release gates. Do not use real accounts in this preview.

## Task 02.3 — native project composer (development preview)
- Three-step Compose form (details, attachments, review); photos/videos, reference-only video selection, full-size delegated camera/camcorder capture, private temporary staging, thumbnails and in-app playback.
- Use existing private sphere-raw bucket, 5 files combined, 50 MiB each, existing raw_files JSON and kind=reference. Stream local files rather than reading full videos into heap. Private signed links are issued only for authorized project parties.
- Account-scoped sp_job_drafts list/save/resume/delete with same web JSON. Draft media is not persisted; direct-hire drafts are intentionally unavailable because web does not preserve editor target. Premium posting and AI-generated form remain out of scope of this preview and are not silently converted to normal posting.
- Stable in-form UUID for retries; never delete attachments after ambiguous project creation. Orphan cleanup/reconciliation after interrupted uploads remains a release gate. No live database writes or real accounts/media used in this task.
- Compile/lint, RLS integration, camera provider and codec coverage, rotation/process death, upload failures, draft roundtrip and physical device testing still required. Release remains blocked.
