# Sphere no-UI-change reliability add-on — 29 October 2026

## Scope and guarantees
The existing Sphere mobile, iOS PWA, desktop and native Android screens remain visually unchanged. No icons, CSS, prices, navigation, project data, Razorpay logic, database migrations, RLS policies or secrets have been changed.

## Changes
1. **PWA image loading:** simultaneous requests for the same public hashed /img asset or pinned vendor bundle share one in-flight network fetch and store the result in the public-only offline cache. Responses are cloned for each caller. Errors clear the in-flight entry to permit a later retry. Private /sb, /api, /auth/v1, /rest/v1, /functions/v1 and /storage/v1 paths remain excluded. Offline shell cache version is v6.
2. **Native Android account safety:** session writes and token-refresh completion are synchronized, so an old refresh response cannot overwrite another user's signed-in session after a logout or account switch; an old refresh error likewise cannot clear the replacement session.
3. **Sphere AI server reads:** the logged-in profile, verified editor list, and fee configuration are independent read-only database requests and now run concurrently instead of in series. Ratings continue after editor IDs are loaded. Existing quotas, provider fallback, price calculations and responses are unchanged.

## Tests
- `tests/unit/sw_cache_safety.test.mjs`: concurrent asset requests, cache reuse, offline failure/recovery, private routes, offline shell.
- `tests/unit/ai_parallel_reads.test.mjs`: verifies all three independent database requests start together using synthetic results.
- `tests/audit-static.mjs`: checks the native stale-refresh guard and lock remain in place.
- GitHub Actions cross-platform Chromium/WebKit smoke tests and Android build should pass before merge.

## Limitations / rollout
- These changes are designed to reduce redundant work but are **not measured speed-up claims**. Run a before/after waterfall and metrics study before publishing percentages.
- No production payment transactions or customer database modifications are required for this change.
- The Sphere AI Edge Function was deployed separately to Supabase project `sphere` as active version **24** on October 29, 2026, and its source was read back to confirm an exact match. GitHub merging alone does not deploy future Edge Function changes.
- The native Android code change reaches devices only with a newly built and installed APK.
- For a rollback, revert the release and increment the service-worker cache name again rather than reusing an older cache version.

## Verified CI
- GitHub Actions cross-platform smoke test for commit `b322c8672` passed (synthetic browser flows, not real devices).
- GitHub Actions Android debug APK build for commit `4446b32e3` passed. This does not install an APK onto users' devices.
