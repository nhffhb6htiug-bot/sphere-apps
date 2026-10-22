# Sphere — Phone OTP launch day (checklist)

Today the OTP login is built and tested but **OFF** (`sp_settings.otp_login = 0`). Nothing changes for users until launch day.

## Before launch day (owner / guardian)
1. MSG91 account (msg91.com), balance added.
2. SMS: DLT registration done, sender ID approved, OTP template approved — note its **template ID**.
3. WhatsApp: WhatsApp Business number connected in MSG91, Meta business verification done, an **authentication** template approved (code in the body + copy-code button) — note the **template name** and the **WhatsApp number**.

## Launch day (in this order — Claude does steps 2–9 with you)
1. Supabase → Authentication → **Providers → Phone → Enable**.
2. Supabase → Authentication → **Hooks → Send SMS hook → HTTPS** → URL `https://pwcchgjsgkwrsvbzqspp.supabase.co/functions/v1/sphere-otp` → **Generate secret** → copy it.
3. Supabase → Edge Functions → Secrets: `SEND_SMS_HOOK_SECRET` (step 2), `MSG91_AUTHKEY`, `MSG91_SMS_TEMPLATE_ID`, `MSG91_WA_NUMBER`, `MSG91_WA_TEMPLATE` (optional `MSG91_WA_LANG`, `MSG91_WA_NAMESPACE`).
4. Test with your own number while the switch is still OFF (Claude can call the login screen directly).
5. **Delete all old accounts** (owner decision, 22 Oct: all accounts incl. admins, no backup). Claude runs it carefully (storage files, data, auth users).
6. Add the database rule **one mobile number = one account** (unique number).
7. Switch ON: `otp_login = 1`.
8. Supabase → Authentication → Providers: **turn off Email and Google**.
9. Nitesh / Harshit / Reena sign up again with OTP → Claude makes them admin again.

If anything goes wrong: set `otp_login = 0` (old login screen comes back) and keep Email on until it is fixed.
