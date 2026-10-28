// SPHERE — sphere-wa-verify: Meta WhatsApp Cloud API webhook for "send the code to us" phone verification.
// Deploy with "Verify JWT" OFF (Meta cannot send a Supabase JWT; every POST is checked with the App Secret signature).
// Secrets (Supabase → Edge Functions → Secrets):
//   WA_VERIFY_TOKEN     any long random text; paste the same text in Meta → WhatsApp → Configuration → "Verify token"
//   WA_APP_SECRET       Meta app → Settings → Basic → App secret
//   WA_ACCESS_TOKEN     permanent System User token with whatsapp_business_messaging
//   WA_PHONE_NUMBER_ID  (optional) the Phone number ID of Sphere's WhatsApp number
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { handle } from "./wacore.js";
const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
const env = Object.fromEntries(["WA_VERIFY_TOKEN", "WA_APP_SECRET", "WA_ACCESS_TOKEN", "WA_PHONE_NUMBER_ID"].map(k => [k, Deno.env.get(k) ?? ""]));
Deno.serve(async (req) => {
  try {
    const r = await handle(req, env, db, fetch);
    return new Response(r.text, { status: r.status, headers: { "Content-Type": "text/plain" } });
  } catch (e) {
    console.log("sphere-wa-verify error", String((e as Error)?.message ?? e).slice(0, 100));
    return new Response("ok", { status: 200 });
  }
});
