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
