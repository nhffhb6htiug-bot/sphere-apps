// Supabase Edge Function: create-razorpay-order
// Amount app se nahi, database me locked job amount se liya jata hai.
// Editor ka hissa (95%) Razorpay Route se editor ke linked account me HOLD pe jata hai.
// Client approve karega tab release hoga (release-payout function).
// Part 19.4: tapping Pay twice reuses the open order (no second order that a customer could also pay).
import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const DEFAULT_FEE_PERCENT = 5; // used only if the admin setting is missing

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const keyId = Deno.env.get("RAZORPAY_KEY_ID");
    const keySecret = Deno.env.get("RAZORPAY_KEY_SECRET");
    if (!keyId || !keySecret) return json({ error: "Razorpay keys are not set (check Edge Function secrets)" }, 500);

    const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const token = (req.headers.get("Authorization") ?? "").replace("Bearer ", "");
    const { data: { user } } = await admin.auth.getUser(token);
    if (!user) return json({ error: "Please log in first" }, 401);

    const { jobId, expectedKeyId } = await req.json();
    // Do not create an order with a different merchant account than the app's configured test key.
    if (expectedKeyId !== keyId) return json({ error: "Razorpay account mismatch. Configure this account's test Key ID and Key Secret in Supabase Edge Function Secrets before testing payments." }, 409);
    const { data: job } = await admin.from("sp_jobs").select("*").eq("id", jobId).maybeSingle();
    if (!job || job.client_id !== user.id) return json({ error: "Job not found" }, 404);
    if (job.status !== "payment-pending" || !job.locked_amount) {
      return json({ error: "This job cannot be paid right now" }, 400);
    }

    const amount = Math.round(Number(job.locked_amount) * 100); // rupees -> paise

    // Never reuse a project order from the previous Razorpay merchant account.
    if (job.razorpay_order_id) {
      let previous: Response;
      try {
        previous = await fetch("https://api.razorpay.com/v1/orders/" + encodeURIComponent(job.razorpay_order_id), {
          headers: { Authorization: "Basic " + btoa(`${keyId}:${keySecret}`) },
        });
      } catch (_e) {
        return json({ error: "Existing Razorpay order cannot be checked. Retry later; no new order created." }, 503);
      }
      if (previous.ok) {
        const o = await previous.json();
        if (o?.id !== job.razorpay_order_id || Number(o.amount) !== amount || (o.currency ?? "INR") !== "INR")
          return json({ error: "Existing payment order does not match. Contact support." }, 409);
        if (o.status === "paid")
          return json({ error: "This order may already have been paid. Refresh the project before trying again." }, 409);
        return json({ id: o.id, amount: o.amount, currency: o.currency ?? "INR" });
      }
      // Only an explicit 404 lets an old merchant's unpaid order be replaced.
      if (previous.status !== 404)
        return json({ error: "Could not validate the existing order; please try again later." }, 503);
    }
    // commission % comes from Admin Panel → Settings (sp_settings)
    const { data: feeRow } = await admin.from("sp_settings").select("value").eq("key", "platform_fee_percent").maybeSingle();
    const feeParsed = Number(feeRow?.value);
    const feePercent = Number.isFinite(feeParsed) && feeParsed >= 0 && feeParsed <= 30 ? feeParsed : DEFAULT_FEE_PERCENT;
    const editorPaise = Math.round(amount * (100 - feePercent) / 100);

    // (who can be hired is checked by the database: unverified editors only for their first 3 paid works)
    const { data: editor } = await admin.from("profiles")
      .select("razorpay_account_id").eq("id", job.assigned_editor).maybeSingle();

    const createOrder = async (withTransfer: boolean) => {
      const body: Record<string, unknown> = {
        amount, currency: "INR", receipt: String(jobId).slice(0, 40), notes: { jobId },
      };
      if (withTransfer) {
        body.transfers = [{
          account: editor!.razorpay_account_id, amount: editorPaise, currency: "INR",
          on_hold: true, notes: { jobId },
        }];
      }
      const res = await fetch("https://api.razorpay.com/v1/orders", {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: "Basic " + btoa(`${keyId}:${keySecret}`) },
        body: JSON.stringify(body),
      });
      return { ok: res.ok, data: await res.json() };
    };

    let withTransfer = !!editor?.razorpay_account_id;
    let result = await createOrder(withTransfer);
    if (!result.ok && withTransfer) {
      // If Route fails, do not block the payment — admin pays the editor manually
      console.error("Route transfer order failed:", result.data?.error?.description);
      withTransfer = false;
      result = await createOrder(false);
    }
    const order = result.data;
    if (!result.ok) return json({ error: order?.error?.description ?? "Razorpay order fail" }, 502);

    await admin.from("sp_jobs").update({
      razorpay_order_id: order.id,
      editor_amount: editorPaise / 100,
      platform_fee: (amount - editorPaise) / 100,
      payout_status: withTransfer ? "awaiting" : "manual",
    }).eq("id", jobId);
    return json({ id: order.id, amount: order.amount, currency: order.currency });
  } catch (e) {
    return json({ error: String((e as Error)?.message ?? e) }, 500);
  }
});
