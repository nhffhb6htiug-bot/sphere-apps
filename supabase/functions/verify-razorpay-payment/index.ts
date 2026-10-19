// Supabase Edge Function: verify-razorpay-payment
// Razorpay ka signature check karta hai. Sahi ho tabhi job "in-progress + escrow-held" hoti hai.
import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

async function hmacHex(secret: string, message: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message));
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function sameText(a: string, b: string): boolean {   // constant-time compare (Part 19.4)
  if (a.length !== b.length) return false;
  let r = 0;
  for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return r === 0;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const keySecret = Deno.env.get("RAZORPAY_KEY_SECRET");
    if (!keySecret) return json({ valid: false, error: "Razorpay secret is not set" }, 500);

    const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const token = (req.headers.get("Authorization") ?? "").replace("Bearer ", "");
    const { data: { user } } = await admin.auth.getUser(token);
    if (!user) return json({ valid: false, error: "Please log in first" }, 401);

    const { order_id, payment_id, signature } = await req.json();
    if (!order_id || !payment_id || !signature) return json({ valid: false, error: "Payment details are incomplete" }, 400);

    const expected = await hmacHex(keySecret, `${order_id}|${payment_id}`);
    if (!sameText(expected, String(signature))) return json({ valid: false, error: "Payment signature is invalid" }, 400);

    const { data: job } = await admin.from("sp_jobs").select("*").eq("razorpay_order_id", order_id).maybeSingle();
    if (!job || job.client_id !== user.id) return json({ valid: false, error: "Job not found" }, 404);

    if (job.status === "payment-pending") {
      const { data: upd, error: upErr } = await admin.from("sp_jobs").update({
        status: "in-progress", payment_status: "escrow-held", razorpay_payment_id: payment_id,
        payout_status: job.payout_status === "awaiting" ? "held" : (job.payout_status ?? "manual"),
      }).eq("id", job.id).eq("status", "payment-pending").select("id");
      if (upErr) {
        return json({ valid: false, error: "Your payment was received, but the project could not be started yet. Please contact Support with payment ID " + payment_id }, 500);
      }
      if (upd?.length && job.assigned_editor) {
        await admin.from("sp_notifications").insert({
          user_id: job.assigned_editor,
          title: "Payment Received 💰",
          body: "The client has paid. You can start editing now!",
        });
      }
    }
    return json({ valid: true });
  } catch (e) {
    return json({ valid: false, error: String((e as Error)?.message ?? e) }, 500);
  }
});
