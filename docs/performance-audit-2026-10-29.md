# Sphere performance and reliability audit — 2026-10-29

## Scope
- Existing Sphere website UI and native Android Compose UI must remain visually unchanged.
- Improve performance for desktop, mobile browsers, iOS PWA and native Android APK without changing financial business logic, payments or user records.
- Evidence is from repository source, Supabase index metadata and automated tests. Hardware/device performance measurements are not available.

## Applied improvements
1. **Static image caching:** Service worker now serves cached `/img/` images from Cache Storage with no redundant network fetch for subsequent requests. Only a public static allowlist is cacheable.
2. **Sensitive data cache exclusion:** Same-origin proxies such as `/sb/rest/v1` and all `/auth/v1`, `/functions/v1`, `/storage/v1` paths bypass the service-worker cache. No authenticated API responses should be stored in browser Cache Storage.
3. **Offline PWA startup:** HTML shell, manifest, icons, pinned Supabase JS bundle, and Sphere theme/desktop CSS are precached. Version-query CSS has an offline fallback.
4. **Data-saver:** At page load, 19 eager image warmups are replaced by three priority images scheduled when the browser is idle; no preload on Save-Data/2G connections. UI's own lazy image elements remain unchanged.
5. **Dashboard speed:** Independent client project work + editor profile data and public ratings + Pro lookups are fetched in parallel.
6. **Request coalescing:** Multiple callers requesting the verified-editor directory for the same signed-in account now share one in-flight result, with the existing 60-second cache.
7. **Desktop resize performance:** Multiple resize event passes are grouped into one animation-frame layout pass.
8. **Recover from offline:** When network returns, only Home dashboard data is refreshed, not forms, chats or payment steps.
9. **Keyboard feature:** Ctrl/Cmd+K opens the pre-existing search page; no new visual control.
10. **Native auth reliability:** Android uses a coroutine Mutex to serialize single-use Supabase refresh-token rotations. Recoverable HTTP 429 does not wipe the session. Version bumped to 2.2.2.

## Backend review
The production Supabase tables `sp_jobs`, `sp_messages`, `sp_applications`, `sp_notifications`, and `profiles` already have useful composite indexes on their common filters. The sampled table sizes are small (under 130 kB per table at the time of review); additional indexes would increase write overhead without a demonstrated benefit. No new SQL indexes, RLS policies, payment functions or user records were changed in this release.

## Tests
- `node tests/audit-static.mjs`: inline JS parsing, responsive meta, asset existence, Android package identity and payment-security assertions.
- `node --test tests/unit/sw_cache_safety.test.mjs`: API data never cached, repeated public image only fetched once, offline shell, versioned CSS offline fallback.
- `node tests/audit-browser.mjs` via GitHub Actions: Chromium Android-like 360 and 412px, WebKit Safari-like 375 and 390px, WebKit iPad-like 820px, desktop 1024, 1366, 1920px; **simulated unauthenticated smoke tests only**.
- Android: Gradle `assembleDebug` via GitHub Actions, no real-device UI/latency guarantee.

## Still requires separate testing
- Physical iOS Safari/PWA, physical Android devices and native APK, Google login redirect, chat/media transfer, real user roles, network throttling and accessibility with VoiceOver/TalkBack.
- Real-money payment, escrow, refunds and payouts need test-mode fixtures and independent approval before executing.
- Quantitative latency/CPU/CDN savings have **not** been measured; do not advertise speed-up percentages until measured with consistent before/after instrumentation.

## Rollback
Revert the performance PR in GitHub, verify the Render static site redeploy; restoring the old service worker cache version may require a follow-up cache-version bump. Native APK changes do not update installed apps automatically; distribute a rebuilt signed update separately.
