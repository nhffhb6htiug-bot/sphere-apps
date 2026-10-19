// Supabase Edge Function: release-payout
// Client video approve karta hai (ya Admin release karta hai) -> job "approved" hoti hai
// aur editor ka held paisa Razorpay Route se release ho jata hai.
import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const keyId = Deno.env.get("RAZORPAY_KEY_ID");
    const keySecret = Deno.env.get("RAZORPAY_KEY_SECRET");
    if (!keyId || !keySecret) return json({ error: "Razorpay keys are not set (check Edge Function secrets)" }, 500);
    const rz = async (path: string, method = "GET", body?: unknown) => {
      const res = await fetch("https://api.razorpay.com" + path, {
        method,
        headers: { "Content-Type": "application/json", Authorization: "Basic " + btoa(`${keyId}:${keySecret}`) },
        body: body ? JSON.stringify(body) : undefined,
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data?.error?.description ?? "Razorpay error");
      return data;
    };

    const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const token = (req.headers.get("Authorization") ?? "").replace("Bearer ", "");
    const { data: { user } } = await admin.auth.getUser(token);
    if (!user) return json({ error: "Please log in first" }, 401);

    const { jobId } = await req.json();
    const { data: job } = await admin.from("sp_jobs").select("*").eq("id", jobId).maybeSingle();
    if (!job) return json({ error: "Job not found" }, 404);

    const { data: me } = await admin.from("profiles").select("role").eq("id", user.id).maybeSingle();
    const isAdmin = String(me?.role ?? "").toUpperCase() === "ADMIN";
    if (job.client_id !== user.id && !isAdmin) return json({ error: "This job is not yours" }, 403);
    if (job.status !== "delivered") return json({ error: "The video can be approved only after delivery" }, 400);

    let payout = job.payout_status === "held" ? "failed" : "manual";
    let transferId: string | null = null;
    let note = "";
    if (job.payout_status === "held" && job.razorpay_payment_id) {
      try {
        const list = await rz(`/v1/payments/${job.razorpay_payment_id}/transfers`);
        const items = (list?.items ?? []) as Array<{ id: string; on_hold: boolean }>;
        for (const t of items) {
          if (t.on_hold) await rz(`/v1/transfers/${t.id}`, "PATCH", { on_hold: false });
        }
        if (items.length) { payout = "released"; transferId = items[0].id; }
        else note = "Transfer not found";
      } catch (e) {
        note = String((e as Error)?.message ?? e);
        console.error("Release failed:", note);
      }
    }

    const { data: upd, error: upErr } = await admin.from("sp_jobs").update({
      status: "approved", payment_status: "released", payout_status: payout, razorpay_transfer_id: transferId,
    }).eq("id", job.id).eq("status", "delivered").select("id");
    if (upErr) return json({ error: "The payout step ran, but the project could not be marked approved. Contact Support. " + upErr.message }, 500);
    if (!upd?.length) return json({ ok: false, error: "This payment was just released" }, 409);   // Part 19.4: second simultaneous tap

    const amt = job.editor_amount ?? job.locked_amount;
    await admin.from("sp_notifications").insert({
      user_id: job.assigned_editor,
      title: payout === "released" ? "Payment Released 🎉" : "Video Approved ✅",
      body: payout === "released"
        ? `₹${amt} has been released to your bank account (Razorpay settlement can take 2–3 days).`
        : `The client approved your video. Syahi Films will send you ₹${amt} soon.`,
    });
    return json({ ok: true, payout, note });
  } catch (e) {
    return json({ error: String((e as Error)?.message ?? e) }, 500);
  }
});
