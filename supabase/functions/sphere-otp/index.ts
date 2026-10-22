// =====================================================================
// SPHERE — sphere-otp: Supabase Auth "Send SMS" hook → OTP by WhatsApp, SMS fallback (MSG91).
// Deploy with "Verify JWT" OFF (Supabase Auth signs every call; the function checks that signature).
// Secrets (Supabase → Edge Functions → Secrets), set on launch day:
//   SEND_SMS_HOOK_SECRET   (from Auth → Hooks → Send SMS hook, "v1,whsec_…")
//   MSG91_AUTHKEY, MSG91_SMS_TEMPLATE_ID (DLT OTP template), MSG91_WA_NUMBER, MSG91_WA_TEMPLATE
//   optional: MSG91_WA_LANG (default "en"), MSG91_WA_NAMESPACE
// =====================================================================
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { handleHook } from "./otpcore.js";
const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
const env = Object.fromEntries(["SEND_SMS_HOOK_SECRET", "MSG91_AUTHKEY", "MSG91_SMS_TEMPLATE_ID", "MSG91_WA_NUMBER", "MSG91_WA_TEMPLATE", "MSG91_WA_LANG", "MSG91_WA_NAMESPACE"].map(k => [k, Deno.env.get(k) ?? ""]));
Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("{}", { status: 405 });
  try {
    const r = await handleHook(req, env, db, fetch);
    return new Response(JSON.stringify(r.body), { status: r.status, headers: { "Content-Type": "application/json" } });
  } catch (e) {
    console.log("sphere-otp error", String((e as Error)?.message ?? e).slice(0, 100));
    return new Response(JSON.stringify({ error: { http_code: 500, message: "Please try again." } }), { status: 500, headers: { "Content-Type": "application/json" } });
  }
});
