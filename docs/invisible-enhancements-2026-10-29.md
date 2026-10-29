# Sphere invisible enhancements — October 29, 2026

## Contract

The exact same rendered mobile, iOS PWA, and desktop user interfaces remain in place.
No styles, icons, screen order, copy, navigation choices, prices, escrow logic, authentication rules,
financial state transitions, Supabase migrations, or customer rows are changed.

## Performance + add-on improvements

1. **Duplicate Premium badge requests are shared.** When the same user ID is rendered by
   concurrent components, they await one `sp_is_premium_client` request and reuse the existing
   five-minute cache. In-flight answers cannot populate a different user's cache after logout.
2. **DOM observer wakes only for newly inserted badge slots.** Previously every unrelated
   DOM change started an 80-ms timer and could rerun badge detection. Badge batches explicitly
   continue when more than 30 unique client IDs are present; unrelated chat DOM changes are ignored.
3. **Foreground-only WhatsApp verification polling.** The verification page now pauses 3-second
   status checks while the app is hidden, avoids overlapping requests, and checks immediately on
   return. It still uses the same verification database RPC and expiry behavior.
4. **Account-status checks coalesce per signed-in account.** Repeated focus/timer checks share
   the same request; a stale response from a previous account cannot navigate the current account.
5. **Logout privacy and memory cleanup.** A signed-out session clears Premium, screen and signed
   media caches, old message index and presence, stops its verification timer, and invalidates
   outstanding signed-media responses. Different users sharing a browser must not reuse private
   signed URLs.
6. **PWA cache v5.** Installing the new worker refreshes the public static offline shell so the
   updated app can be used after the next successful online visit. Authenticated API responses
   remain excluded from the offline Cache Storage.

## Regression tests and limits

- `node tests/audit-static.mjs` validates script syntax, assets, responsive metadata and Android RPC safeguards.
- `node --test tests/unit/*.test.mjs` covers all existing cryptographic/payment/OTP/push/cache
  tests plus `quiet_performance.test.mjs` for deduplication, observer noise, account switching,
  logout cache clearing, and foreground-only verification.
- `node tests/audit-browser.mjs` and `node tests/audit-authenticated.mjs` cover Chromium and
  Safari-like WebKit viewports with synthetic accounts in GitHub Actions.
- These tests do not prove a numerical latency gain, physical-device compatibility, app-store
  approval, payment settlement/refunds, or 100-200-user load capacity.
- No server-side database indexes or RLS changes are made without a measured query plan.

## Rollback

Revert the merge commit in GitHub and redeploy the previous known-good web version through Render.
Because service-worker cache versions change, also **increase** the cache version on a rollback
release so installed PWAs refresh their offline shell; do not restore a stale `v4` cache name.
