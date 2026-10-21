// =====================================================================
// SPHERE — sphere-push (Web Push delivery). Deploy with "Verify JWT" OFF:
// the database calls it with a secret header; only {action:'init'} (returns the PUBLIC key) is open.
// Secrets used: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (provided by Supabase). No other secret is needed —
// the VAPID keys are created once by this function and stored privately in the database.
// =====================================================================
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { handle } from "./pushcore.js";
const CORS = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
Deno.serve(async (req) => {
  try {
    const r = await handle(req, db, fetch);
    return new Response(JSON.stringify(r.body), { status: r.status, headers: { ...CORS, "Content-Type": "application/json" } });
  } catch (e) {
    console.log("sphere-push error", String((e as Error)?.message ?? e).slice(0, 120));
    return new Response(JSON.stringify({ ok: false }), { status: 500, headers: { ...CORS, "Content-Type": "application/json" } });
  }
});
