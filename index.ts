// =====================================================================
// SPHERE — sphere-moderate (Part 9)
// AI check for a chat message that Sphere held for review.
//   • Called by the app right after a message is held ({ messageId }),
//     or by an admin from the Admin Panel ("Ask AI").
//   • Reads the held text + the last few messages for context.
//   • Asks Gemini: is this an attempt to move contact / payment outside Sphere?
//   • Saves the verdict with sp_chat_ai_verdict. "safe" (confidence ≥ 0.8)
//     releases the message automatically; everything else waits for an admin.
// Secrets used (Supabase → Edge Functions → Secrets):
//   GEMINI_API_KEY (or GOOGLE_API_KEY) — the same Google AI key Sphere AI uses
//   GEMINI_MODEL (optional, default gemini-2.5-flash-lite)
//   SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY are provided by Supabase.
// =====================================================================
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  try {
    const { messageId, holdId } = await req.json().catch(() => ({}));
    if (!messageId && !holdId) return json({ error: "messageId or holdId is required" }, 400);

    const url = Deno.env.get("SUPABASE_URL")!;
    const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
    const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    // Who is asking?
    const asUser = createClient(url, anon, { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } });
    const { data: who } = await asUser.auth.getUser();
    const user = who?.user;
    if (!user) return json({ error: "Please log in" }, 401);

    const db = createClient(url, service, { auth: { persistSession: false } });
    let q = db.from("sp_msg_holds").select("*");
    q = holdId ? q.eq("id", holdId) : q.eq("message_id", String(messageId));
    const { data: hold } = await q.maybeSingle();
    if (!hold) return json({ ok: true, status: "not_held" });
    if (hold.status !== "pending") return json({ ok: true, status: hold.status });

    // Only the two people in the chat, or an admin, may start the check.
    const { data: me } = await db.from("profiles").select("role").eq("id", user.id).maybeSingle();
    const isAdmin = String(me?.role ?? "").toUpperCase() === "ADMIN";
    if (!isAdmin && user.id !== hold.sender_id && user.id !== hold.receiver_id) return json({ error: "Not allowed" }, 403);
    if (hold.ai_checked_at && !isAdmin) return json({ ok: true, status: "pending", verdict: hold.ai_verdict });

    const key = Deno.env.get("GEMINI_API_KEY") ?? Deno.env.get("GOOGLE_API_KEY") ?? Deno.env.get("GOOGLE_AI_API_KEY");
    if (!key) return json({ ok: false, error: "AI key not set — the message waits for an admin" });
    const model = Deno.env.get("GEMINI_MODEL") ?? "gemini-2.5-flash-lite";

    // A little context: the last messages between the same two people.
    const { data: recent } = await db.from("sp_messages")
      .select("sender_id, text, created_at")
      .or(`and(sender_id.eq.${hold.sender_id},receiver_id.eq.${hold.receiver_id}),and(sender_id.eq.${hold.receiver_id},receiver_id.eq.${hold.sender_id})`)
      .order("created_at", { ascending: false }).limit(8);
    const context = (recent ?? []).reverse()
      .filter((m) => m.text && !String(m.text).startsWith("⏳"))
      .map((m) => (m.sender_id === hold.sender_id ? "SENDER: " : "OTHER: ") + String(m.text).slice(0, 200))
      .join("\n");

    const prompt =
      "You moderate chat on Sphere, an Indian marketplace where clients hire video editors. " +
      "All talk and ALL payments must stay inside Sphere. Decide if the NEW MESSAGE tries to move the conversation " +
      "or payment outside Sphere (WhatsApp, Telegram, Instagram DM, calls, email, UPI, bank transfer, cash, " +
      "Zoom/Meet, hints like 'number do', 'direct pay karo', 'bahar deal'). Normal video-editing talk that only " +
      "mentions an app name (e.g. 'export for WhatsApp status', 'Instagram reel', 'YouTube video') is SAFE. " +
      "Messages can be Hindi, English or Hinglish.\n" +
      'Reply ONLY with JSON: {"verdict":"safe"|"off_platform"|"unsure","confidence":0-1,"reason":"one short English sentence"}\n\n' +
      "RECENT CHAT:\n" + (context || "(none)") + "\n\nNEW MESSAGE:\n" + String(hold.original_text).slice(0, 1000);

    const ai = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${key}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{ role: "user", parts: [{ text: prompt }] }],
        generationConfig: { temperature: 0, responseMimeType: "application/json" },
      }),
    });
    if (!ai.ok) return json({ ok: false, error: "AI is busy (" + ai.status + ") — the message waits for an admin" });
    const out = await ai.json();
    const text: string = out?.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
    let verdict = "unsure", confidence = 0, reason = "";
    try {
      const a = text.indexOf("{"), b = text.lastIndexOf("}");
      const parsed = JSON.parse(text.slice(a, b + 1));
      verdict = ["safe", "off_platform", "unsure"].includes(parsed.verdict) ? parsed.verdict : "unsure";
      confidence = Math.max(0, Math.min(1, Number(parsed.confidence) || 0));
      reason = String(parsed.reason ?? "").slice(0, 300);
    } catch { reason = "AI answer could not be read"; }

    const { data: res, error } = await db.rpc("sp_chat_ai_verdict", {
      p_hold: hold.id, p_verdict: verdict, p_confidence: confidence, p_reason: reason,
    });
    if (error) return json({ ok: false, error: error.message }, 500);
    return json({ ok: true, verdict, confidence, reason, released: !!res?.released });
  } catch (e) {
    return json({ ok: false, error: String((e as Error)?.message ?? e) }, 500);
  }
});
