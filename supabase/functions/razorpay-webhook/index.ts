// =====================================================================
// SPHERE — razorpay-webhook (Part 17)
// Razorpay calls this URL after a payment. It:
//   1) checks the X-Razorpay-Signature (HMAC-SHA256 of the raw body with the
//      webhook secret) — anything unsigned or changed is refused;
//   2) records the event id once (sp_webhook_events) — repeats do nothing;
//   3) checks the amount against the database, then marks the payment paid
//      through the same server-only functions the app flow uses:
//        notes.fee_id   → sp_fee_mark_paid   (₹29 verification / ₹199 Pro)
//        notes.extra_id → sp_extra_mark_paid (₹50 revision / change price)
//        otherwise      → sp_webhook_project_paid (project payment, by order id)
// Secrets: RAZORPAY_WEBHOOK_SECRET (set the same text in Razorpay → Webhooks).
// Never logs card / bank / personal details.
// =====================================================================
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { "Content-Type": "application/json" } });

async function hmacHex(secret: string, message: string): Promise<string> {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message));
  return Array.from(new Uint8Array(sig)).map((b) => b.toString(16).padStart(2, "0")).join("");
}
function sameText(a: string, b: string): boolean {          // constant-time compare
  if (a.length !== b.length) return false;
  let r = 0;
  for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return r === 0;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ ok: false }, 405);
  const secret = Deno.env.get("RAZORPAY_WEBHOOK_SECRET");
  if (!secret) return json({ ok: false, error: "not configured" }, 500);

  const raw = await req.text();
  if (raw.length > 200000) return json({ ok: false }, 413);
  const signature = req.headers.get("x-razorpay-signature") ?? "";
  if (!sameText(await hmacHex(secret, raw), signature)) return json({ ok: false, error: "bad signature" }, 401);

  let ev: any;
  try { ev = JSON.parse(raw); } catch { return json({ ok: false }, 400); }
  const pay = ev?.payload?.payment?.entity ?? {};
  const order = ev?.payload?.order?.entity ?? {};
  const eventId = req.headers.get("x-razorpay-event-id") ?? `${ev?.event}:${pay.id ?? order.id ?? ev?.created_at}`;

  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
  const { error: seenErr } = await db.from("sp_webhook_events").insert({ event_id: String(eventId).slice(0, 200), event_type: String(ev?.event ?? "").slice(0, 60) });
  if (seenErr) {
    if (seenErr.code === "23505") return json({ ok: true, duplicate: true });   // already handled
    return json({ ok: false }, 500);                                           // Razorpay will retry
  }

  let status = "ignored", note = "";
  try {
    if (ev?.event === "payment.captured" || ev?.event === "order.paid") {
      const orderId: string = pay.order_id ?? order.id ?? "";
      const paymentId: string = pay.id ?? "";
      const paise = Number(pay.amount ?? order.amount_paid ?? 0);
      const notes = { ...(order.notes ?? {}), ...(pay.notes ?? {}) };
      if (notes.fee_id || notes.extra_id) {
        const table = notes.fee_id ? "sp_fee_payments" : "sp_extra_payments";
        const id = notes.fee_id ?? notes.extra_id;
        const { data: row } = await db.from(table).select("id, amount, status").eq("id", id).maybeSingle();
        if (!row) { status = "failed"; note = "unknown payment"; }
        else if (Math.round(Number(row.amount) * 100) !== paise) { status = "failed"; note = "amount mismatch"; }
        else {
          const fn = notes.fee_id ? "sp_fee_mark_paid" : "sp_extra_mark_paid";
          const args = notes.fee_id ? { p_fee: id, p_method: "razorpay", p_payment: paymentId, p_order: orderId }
                                    : { p_extra: id, p_method: "razorpay", p_payment: paymentId, p_order: orderId };
          const { error } = await db.rpc(fn, args);
          status = error ? "failed" : "processed"; note = error ? "could not mark paid" : "";
        }
      } else if (orderId) {
        const { data, error } = await db.rpc("sp_webhook_project_paid", { p_order: orderId, p_payment: paymentId, p_amount_paise: paise });
        const r = String(data?.status ?? "");
        status = !error && (r === "paid" || r === "already") ? "processed" : "failed";   // Part 19.4: unknown order / amount mismatch must be visible
        note = error ? "could not mark paid" : r;
      }
    } else if (ev?.event === "payment.failed") {
      status = "ignored"; note = "failure is shown to the payer in the app";
    }
  } catch (_e) {
    status = "failed"; note = "error while processing";
  }
  await db.from("sp_webhook_events").update({ status, note, processed_at: new Date().toISOString() }).eq("event_id", String(eventId).slice(0, 200));
  return json({ ok: true, status });
});
