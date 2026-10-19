// =====================================================================
// SPHERE — sphere-health (Part 18)
// GET https://<project>.supabase.co/functions/v1/sphere-health
// → 200 {"status":"ok","db":"ok","schema":"018",...} when the database answers,
//   503 when it does not. For an uptime monitor (e.g. UptimeRobot, free).
// No personal data, no secrets. Deploy with "Verify JWT" OFF.
// =====================================================================
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const headers = { "Content-Type": "application/json", "Cache-Control": "no-store", "Access-Control-Allow-Origin": "*" };

Deno.serve(async (req) => {
  if (req.method !== "GET" && req.method !== "HEAD") return new Response(null, { status: 405, headers });
  const started = Date.now();
  try {
    const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
    const { data, error } = await db.rpc("sp_health");
    if (error || !data) throw new Error("db");
    return new Response(JSON.stringify({ status: "ok", db: "ok", schema: data.schema ?? null, ms: Date.now() - started, time: new Date().toISOString() }), { status: 200, headers });
  } catch {
    return new Response(JSON.stringify({ status: "down", db: "unreachable", ms: Date.now() - started, time: new Date().toISOString() }), { status: 503, headers });
  }
});