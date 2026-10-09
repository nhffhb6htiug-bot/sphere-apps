// =====================================================================
// SPHERE — sphere-extra-payment (Part 11 + Part 15)
// Razorpay checkout for:
//   • the ₹50 fee for a 4th+ revision (100 % recorded for the editor)      { extraId }
//   • the extra price of an accepted change request                        { extraId }
//   • the ₹29 editor verification fee and ₹199 Editor Pro (Part 15)        { feeId }
// The amount ALWAYS comes from the database; the app never decides it.
// action "create": makes a Razorpay order for an sp_extra_payments row
//                  (the amount always comes from the database, never from the app)
// action "verify": checks Razorpay's signature, then marks it paid with
//                  sp_extra_mark_paid → the revision opens / the change is applied.
// Secrets (Supabase → Edge Functions → Secrets) — the same ones the other
// Razorpay functions use: RAZORPAY_KEY_ID and RAZORPAY_KEY_SECRET.
// SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY come from Supabase.
// =====================================================================
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });

async function hmacHex(secret: string, message: string): Promise<string> {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message));
  return Array.from(new Uint8Array(sig)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  try {
    const body = await req.json().catch(() => ({}));
    const { action, extraId, feeId } = body;
    if ((!extraId && !feeId) || !["create", "verify"].includes(action)) return json({ ok: false, error: "Bad request" }, 400);
    const isFee = !!feeId;
    const table = isFee ? "sp_fee_payments" : "sp_extra_payments";
    const ownerField = isFee ? "user_id" : "client_id";
    const markPaid = isFee ? "sp_fee_mark_paid" : "sp_extra_mark_paid";
    const rowId = isFee ? feeId : extraId;

    const url = Deno.env.get("SUPABASE_URL")!;
    const asUser = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } });
    const { data: who } = await asUser.auth.getUser();
    if (!who?.user) return json({ ok: false, error: "Please log in" }, 401);

    const db = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
    const { data: x } = await db.from(table).select("*").eq("id", rowId).maybeSingle();
    if (!x || x[ownerField] !== who.user.id) return json({ ok: false, error: "Not your payment" }, 403);
    if (x.status === "paid") return json({ ok: false, error: "Already paid ✅", paid: true });
    if (x.status === "cancelled") return json({ ok: false, error: "This payment was cancelled" });
    if (isFee && x.status !== "pending") return json({ ok: false, error: "Start the payment again from the app" });

    const keyId = Deno.env.get("RAZORPAY_KEY_ID");
    const secret = Deno.env.get("RAZORPAY_KEY_SECRET") ?? Deno.env.get("RAZORPAY_SECRET");
    if (!keyId || !secret) return json({ ok: false, error: "Online payment is not set up — use UPI" });

    if (action === "create") {
      const r = await fetch("https://api.razorpay.com/v1/orders", {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: "Basic " + btoa(keyId + ":" + secret) },
        body: JSON.stringify({
          amount: Math.round(Number(x.amount) * 100),
          currency: "INR",
          receipt: ((isFee ? "sf_" : "sx_") + x.id).slice(0, 40),
          notes: isFee ? { fee_id: x.id, kind: x.kind, user_id: x.user_id } : { extra_id: x.id, job_id: x.job_id, kind: x.kind },
        }),
      });
      const order = await r.json();
      if (!r.ok || !order?.id) return json({ ok: false, error: order?.error?.description ?? "Could not start the payment" }, 502);
      await db.from(table).update({ order_id: order.id, method: "razorpay" }).eq("id", x.id).eq("status", "pending");
      return json({ ok: true, order_id: order.id, amount: order.amount, currency: order.currency, key_id: keyId });
    }

    // verify
    const { order_id, payment_id, signature } = body;
    if (!order_id || !payment_id || !signature || order_id !== x.order_id) return json({ ok: false, valid: false, error: "Order does not match" });
    const expected = await hmacHex(secret, order_id + "|" + payment_id);
    if (expected !== signature) return json({ ok: false, valid: false, error: "Payment could not be verified" });
    const args = isFee ? { p_fee: x.id, p_method: "razorpay", p_payment: payment_id, p_order: order_id }
                       : { p_extra: x.id, p_method: "razorpay", p_payment: payment_id, p_order: order_id };
    const { error } = await db.rpc(markPaid, args);
    if (error) return json({ ok: false, valid: true, error: error.message }, 500);
    return json({ ok: true, valid: true });
  } catch (e) {
    return json({ ok: false, error: String((e as Error)?.message ?? e) }, 500);
  }
});
