# Native parity work — 2026-11-24
Baseline: web commit b41b8ec03ec36dacf565f9ef7a44cc2a00815c78. Android implementation only; not an assertion of full parity.
## Implemented in this branch, awaiting build and device validation
- Restore Jetpack Compose entry point; current native home, auth, navigation retained.
- Project title, length, format, style notes, reference links, 0–4 languages stored with web database columns.
- No expected-revision selection at posting; null stored as web does.
- Show project metadata on detail screen; reference links limited to project parties in UI (backend policies still required).
- Version 2.2.9/code 13; CI checks Compose entry point; debug-only branch builds.
## Remaining release gates
- Private raw/reference upload, camera and media picker, thumbnails/video playback, signed URLs and attachment access tests.
- Smart brief builder, AI autofill, drafts, review step, premium post purchase and audience; matching recommendations.
- Payment checkout, approval, escrow/release, disputes, revisions/change requests; verify against web server RPCs and sandbox.
- Chat presence, offline queue, retry, search, moderated media; test account switching and signed media access.
- Editor verification flow including first-50 offer, paid confirmation, admin user counts and filters, and profile status.
- Latest dark/light UI, home layout, startup/back-navigation, category/icon fidelity, notification parity.
- Native Google sign-in with correct signing fingerprint; secure token storage and account deletion; permissions and privacy review.
- Build/device tests on two roles, test-only accounts, feature-by-feature comparison; no live payments or production mutations as tests.
- Signed AAB only once parity/security review passes and authorized owner configures signing.

## Phase 2 — v2.2.10 (source; compile/device validation pending)
- Private raw/reference upload with combined 5 files, 50 MiB limit, bounded temporary files, owner path, existing RLS, signed file opening; signed URLs for private project/chat media.
- Browse document picker, external camera photo and video capture, local photo/video thumbnails, project photo previews and video playback via signed link.
- Review step, stable project request ID during form session, notification failure isolation; do not remove uploads on uncertain insert.
- Chat list search; job titles on home cards.
- Remaining: remote video thumbnails/in-app playback, full chat presence/retry/offline queue, drafts/AI brief, payments, full admin, notification parity, dark theme and integration/device tests. No production DB writes during development.

## Phase 3 — v2.2.11 (source changes; build and device tests required)
- Server-synced text drafts, edit/delete, draft-based stable post ID. Attachments deliberately not persisted in drafts, matching web behavior.
- Notification sections, mark read, clear, load more and project links; chat notices omitted.
- Read-only native admin Overview, Users, independent completeness/verification filters, and verification queues including confirmed paid editors (not excluded if messaged). Admin-only RPCs enforce access; no PIN/write operations added.
- Back behavior for home and review; update obsolete WebView startup regression to assert Compose startup instead.
- Payment checkout, admin write actions, dark mode, full AI/drafts parity, full chat/notification/device security tests, and signed AAB remain release gates.

## Phase 4 — v2.2.12 (source implementation, not release-certified)
- Native settings dark-mode toggle, web-derived black/pink/purple palette in common surfaces, navigation, cards, home and chat; original light-mode art retained.
- Smart brief builder and existing authenticated Sphere AI draft_job API wired into editable project form (AI suggestions require review; backend's draft action returns a limited schema).
- Android Keystore AES-GCM encrypted session storage and plaintext migration; failed migration requires re-login. Disable implicit network retries for writes. Existing manual GET retry preserved.
- Compile and test on actual Android devices, especially dark-mode contrast, camera, signed links, draft posting, login/refresh, admin permissions and payment workflow. Full payments, revisions/disputes, chat presence/offline queue, all admin PIN actions, premium checkout, push notifications and release signing remain pending.
