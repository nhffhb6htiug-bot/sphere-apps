# Deployed Edge Functions (copied from production, read-only)

Source of each `index.ts` was copied from the deployed function (Supabase → get_edge_function) on 19 Oct 2026.
No secrets are stored here — every key is read at runtime with `Deno.env.get(...)` from Supabase → Edge Functions → Secrets.

| Function | Deployed version | Verify JWT | Notes |
|---|---|---|---|
| create-razorpay-order | 12 | ON | Project payment order; reuses an open order |
| verify-razorpay-payment | 10 | ON | Checks the payment signature (constant-time) |
| release-payout | 5 | ON | Approve → release (Route) or manual payout |
| refund-payment | 5 | ON | Admin + recorded refund decision; one claim per refund |
| razorpay-webhook | 5 | **OFF** | Signed by Razorpay (`RAZORPAY_WEBHOOK_SECRET`), duplicate-safe |
| sphere-health | 5 | **OFF** | Uptime check, no personal data |
| sphere-moderate | 4 | ON | AI check of held chat messages |
| sphere-otp | 1 | **OFF** | Supabase Auth "Send SMS" hook: login OTP by WhatsApp, SMS fallback (MSG91); checks the hook signature |
| sphere-push | 2 | **OFF** | Web Push delivery; called only by the database with a secret header (VAPID keys stored privately in the database) |
| sphere-extra-payment | 7 | ON | ₹29 / ₹199 / ₹5 / ₹50 payments; constant-time signature check (Part 24.5) |

Secrets used: `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET`, `RAZORPAY_WEBHOOK_SECRET`, `GEMINI_API_KEY`
(plus `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` provided by Supabase).
Deploy with the same Verify-JWT setting shown above.
