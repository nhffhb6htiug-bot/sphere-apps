# Sphere: WhatsApp phone verification — staging integration

**Status: code prepared, NOT activated in production.** Existing signup remains unchanged.
The profile screen provides an optional "Verify phone via WhatsApp" flow. A complete
production rollout requires Meta Cloud API onboarding, consent from the phone-number
owner, Supabase migration/deploy, and end-to-end testing.

## How it works
1. Signed-in Sphere user opens Profile → Verify phone via WhatsApp.
2. `sphere-wa-start` reads the user's existing profile number and generates a
   random one-time code. Only a SHA-256 hash of that code + server-only secret
   is stored (expires after 10 minutes; three requests/hour; eight wrong attempts).
3. User sends the prepared message to the configured business WhatsApp number.
4. `sphere-wa-webhook` accepts only a valid Meta-signed webhook message,
   checks sender number equals the pending Sphere user's number, and calls
   `sp_wa_complete` to atomically claim that number.
5. Only one Sphere user can claim a given verified phone number. The existing
   profiles are **not** automatically converted or blocked.

## Setup (a parent/guardian should own and manage the official business account)
- Obtain explicit permission from the business-number owner; do not use a
  friend's number long-term without ownership and ongoing access.
- Onboard a phone number to **Meta WhatsApp Cloud API**. WhatsApp Business
  mobile app alone does not supply Cloud API webhooks; coexistence is subject
  to Meta eligibility.
- Create and save your Meta app secret and verification token securely.
- In Supabase, apply migration `090_whatsapp_verification.sql` after backup.
- Deploy `sphere-wa-start` with JWT verification enabled.
- Deploy `sphere-wa-webhook` with JWT verification **disabled** so that Meta
  can call it. It enforces Meta's HMAC SHA-256 signature itself.
- Point Meta Webhooks callback URL to:
  `https://<supabase-project-ref>.supabase.co/functions/v1/sphere-wa-webhook`
  and subscribe to the WhatsApp `messages` webhook field.
- Set these **Supabase Edge Function secrets** (NEVER commit them):
  - `WA_BUSINESS_NUMBER`: Business WhatsApp number, Indian 10 digits or +91 format.
  - `WA_PHONE_NUMBER_ID`: Meta Cloud API Phone Number ID (not telephone number).
  - `WA_APP_SECRET`: Meta app secret for validating `x-hub-signature-256`.
  - `WA_VERIFY_TOKEN`: long randomly-generated secret matching Meta webhook config.
  - `WA_CODE_SECRET`: separate random secret of at least 32 characters; do not rotate
    while any verification codes are pending.
  - `SPHERE_ALLOWED_ORIGINS`: comma-separated live origins; include both
    `https://sphere.syahi.online` and `https://sphere-live.onrender.com` where needed.
- Supabase default environment values for SUPABASE_URL and service_role must
  be available to both Edge Functions; never expose service_role to frontend.

## Release gates before merging PR
- SQL migration applied successfully to staging and verified RLS.
- Meta GET callback challenge succeeds, wrong token returns 403.
- Meta POST rejects invalid signature (401), accepts valid signature (200).
- User A sends exact code from own WhatsApp phone; A is verified.
- User B cannot claim A's number; code sent from any other phone cannot verify A.
- Expired/replayed/wrong codes rejected, rate limits active.
- App login, client/editor workflows, payments and existing users regression-tested.
- Record legitimate consent; verify guardian-controlled business setup.
- Only after tests: consider mandatory signup verification AND server-side
  enforcement on privileged RPC/Edge Functions. UI-only gating is insufficient.

## Important limits
- The new verification claim table enforces uniqueness among **verified claims**;
  it does not repair pre-existing profiles with repeated/unchecked numbers.
- The code is not an SMS OTP and users send the message themselves.
- Meta/WhatsApp messaging charges and eligibility depend on current account terms.
- This branch intentionally does not hardcode or publish any personal number.
