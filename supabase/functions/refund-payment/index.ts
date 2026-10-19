// Supabase Edge Function: refund-payment  (sirf ADMIN)
// Jhagde me Syahi Films refund ka faisla kare tab: editor ka held hissa wapas (reversal) + client ko refund.
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
    const { data: me } = await admin.from("profiles").select("role").eq("id", user.id).maybeSingle();
    if (String(me?.role ?? "").toUpperCase() !== "ADMIN") return json({ error: "Only the admin can issue refunds" }, 403);

    const { jobId } = await req.json();
    const { data: job } = await admin.from("sp_jobs").select("*").eq("id", jobId).maybeSingle();
    if (!job) return json({ error: "Job not found" }, 404);
    if (!job.razorpay_payment_id) return json({ error: "This job was not paid online" }, 400);
    if (job.status === "refunded") return json({ error: "This job is already refunded" }, 400);
    // Part 19.4: only an unreleased project can be refunded — the database refuses the rest, so never move money first
    if (!["payment-pending", "in-progress", "delivered"].includes(job.status)) {
      return json({ error: "This project cannot be refunded now (status: " + job.status + ")" }, 400);
    }
    // Part 19.4: a recorded Sphere-team decision (PIN + reason) is required — an admin login alone is not enough
    const { data: rf } = await admin.from("sp_refunds").select("id, status").eq("job_id", job.id)
      .in("status", ["approved", "processing", "failed"]).order("created_at", { ascending: false }).limit(1).maybeSingle();
    if (!rf) return json({ error: "A Sphere-team refund decision (with PIN and reason) is needed first. Open the case in Admin → Disputes." }, 409);
    // claim it, so two taps can never refund twice. The app may already have set "processing" (with no
    // error) just before calling this function — that is still claimable; a running call leaves its marker.
    const MARK = "refund call in progress";
    const claim = { status: "processing", error: MARK, updated_at: new Date().toISOString() };
    let { data: claimed } = await admin.from("sp_refunds").update(claim)
      .eq("id", rf.id).in("status", ["approved", "failed"]).select("id");
    if (!claimed?.length) {
      ({ data: claimed } = await admin.from("sp_refunds").update(claim)
        .eq("id", rf.id).eq("status", "processing").is("error", null).select("id"));
    }
    if (!claimed?.length) return json({ error: "This refund is already being processed" }, 409);

    // One Razorpay call: refund the client AND take back the editor's Route share together (all or nothing)
    const hasTransfers = ["held", "awaiting"].includes(String(job.payout_status));
    let refund: { id: string };
    try {
      refund = await rz(`/v1/payments/${job.razorpay_payment_id}/refund`, "POST", {
        speed: "normal", notes: { jobId: String(jobId) }, ...(hasTransfers ? { reverse_all: 1 } : {}),
      });
    } catch (e) {
      await admin.from("sp_refunds").update({ status: "failed", error: String((e as Error).message).slice(0, 300), updated_at: new Date().toISOString() }).eq("id", rf.id);
      return json({ error: "Refund failed — nothing was changed: " + String((e as Error).message) }, 502);
    }

    const { error: upErr } = await admin.from("sp_jobs").update({
      status: "refunded", payment_status: "refunded", payout_status: "reversed",
    }).eq("id", job.id);
    if (upErr) {
      await admin.from("sp_refunds").update({ status: "refunded", error: ("refund " + refund.id + " sent; project status update failed: " + upErr.message).slice(0, 300), updated_at: new Date().toISOString() }).eq("id", rf.id);
      return json({ error: "The refund was sent to the client (" + refund.id + ") but the project status could not be updated. Contact the developer." }, 500);
    }

    await admin.from("sp_refunds").update({ status: "refunded", error: null, updated_at: new Date().toISOString() }).eq("id", rf.id);
    const amt = job.locked_amount ?? job.budget;
    await admin.from("sp_notifications").insert([
      { user_id: job.client_id, title: "Refund processed 💸",
        body: `Your refund of ₹${amt} has started. It will reach your account in 5–7 working days.` },
      ...(job.assigned_editor ? [{ user_id: job.assigned_editor, title: "Project refunded",
        body: "After review, Syahi Films refunded this project. Questions? Contact Support." }] : []),
    ]);
    return json({ ok: true, refund_id: refund.id });
  } catch (e) {
    return json({ error: String((e as Error)?.message ?? e) }, 500);
  }
});
