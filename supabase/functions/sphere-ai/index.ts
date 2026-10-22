// Supabase Edge Function: sphere-ai
// Sphere AI assistant powered by Google Gemini (free tier from Google AI Studio).
// The Gemini API key stays here on the server (secret GEMINI_API_KEY), never in the app.
import { createClient } from "npm:@supabase/supabase-js@2";

// Google renames/retires models over time, so we ASK Google which Flash models exist right now
// and use the newest one. The model that worked last is remembered while the function stays warm.
const FALLBACK_MODELS = ["gemini-flash-latest", "gemini-flash-lite-latest", "gemini-3-flash", "gemini-2.5-flash"];
let lastGoodModel: string | null = null;
let discovered: string[] | null = null;
async function discoverModels(key: string): Promise<string[]> {
  if (discovered) return discovered;
  try {
    const r = await fetch("https://generativelanguage.googleapis.com/v1beta/models?pageSize=200", { headers: { "x-goog-api-key": key } });
    const d = await r.json();
    const names: string[] = (d.models ?? [])
      .filter((m: any) => (m.supportedGenerationMethods ?? []).includes("generateContent"))
      .map((m: any) => String(m.name).replace(/^models\//, ""))
      .filter((n: string) => /flash/i.test(n) && !/(image|tts|audio|live|embed|vision|thinking|computer|robotics)/i.test(n));
    const score = (n: string) => {
      const v = parseFloat((n.match(/gemini-(\d+(?:\.\d+)?)/) ?? [])[1] ?? "0");
      return v * 10 + (/latest/.test(n) ? 3 : 0) - (/lite/.test(n) ? 1 : 0) - (/(preview|exp)/.test(n) ? 4 : 0);
    };
    discovered = names.sort((a, b) => score(b) - score(a)).slice(0, 5);
  } catch (e) {
    console.error("model discovery failed", e);
    discovered = [];
  }
  return discovered;
}
const DAILY_LIMIT = Number(Deno.env.get("AI_DAILY_LIMIT") ?? "30"); // messages per user per day
const CATEGORIES = ["Vlog Editing", "Cinematic", "Gaming Edits", "Reels & Shorts", "Podcast Editing",
  "Color Grading & VFX", "Motion Graphics", "Ads & Commercial"];

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

type Msg = { role: "user" | "model"; text: string };

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const key = Deno.env.get("GEMINI_API_KEY");
    if (!key) return json({ error: "Sphere AI is not set up yet. Please try again later." }, 503);

    const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const token = (req.headers.get("Authorization") ?? "").replace("Bearer ", "");
    const { data: { user } } = await admin.auth.getUser(token);
    if (!user) return json({ error: "Please log in first" }, 401);

    const body = await req.json();
    const action: "chat" | "draft_job" = body.action === "draft_job" ? "draft_job" : "chat";
    const history: Msg[] = (Array.isArray(body.messages) ? body.messages : [])
      .filter((m: Msg) => m && (m.role === "user" || m.role === "model") && typeof m.text === "string")
      .slice(-12)
      .map((m: Msg) => ({ role: m.role, text: m.text.slice(0, 2000) }));
    if (!history.length || history[history.length - 1].role !== "user") {
      return json({ error: "Please type a message" }, 400);
    }

    // ---- daily limit per user (protects the free Gemini quota)
    const day = new Date(Date.now() + 330 * 60000).toISOString().slice(0, 10); // India date
    const { data: usage } = await admin.from("sp_ai_usage").select("count").eq("user_id", user.id).eq("day", day).maybeSingle();
    const used = usage?.count ?? 0;
    if (used >= DAILY_LIMIT) {
      return json({ error: `You have used all ${DAILY_LIMIT} Sphere AI messages for today. Please come back tomorrow.` }, 429);
    }
    await admin.from("sp_ai_usage").upsert({ user_id: user.id, day, count: used + 1 }, { onConflict: "user_id,day" });

    // ---- context: who is asking + the real verified editors (so AI never invents editors)
    const { data: me } = await admin.from("profiles").select("full_name, role").eq("id", user.id).maybeSingle();
    const { data: eds } = await admin.from("profiles")
      .select("id, full_name, verification_code, categories, languages, price_range, experience_years, skills")
      .eq("role", "EDITOR").eq("is_verified", true).limit(40);
    const ids = (eds ?? []).map((e) => e.id);
    const { data: rts } = ids.length ? await admin.from("sp_ratings").select("editor_id, stars").in("editor_id", ids) : { data: [] };
    const agg: Record<string, { s: number; n: number }> = {};
    (rts ?? []).forEach((r) => { agg[r.editor_id] = agg[r.editor_id] ?? { s: 0, n: 0 }; agg[r.editor_id].s += r.stars; agg[r.editor_id].n++; });
    const editorLines = (eds ?? []).map((e) => {
      const a = agg[e.id];
      return `- ${e.full_name} | code ${e.verification_code} | ${(e.categories ?? []).join(", ") || "-"} | languages: ${(e.languages ?? []).join(", ") || "-"} | ₹${e.price_range ?? "?"} per video | ${e.experience_years ?? "?"} yrs | ` +
        `${a ? (a.s / a.n).toFixed(1) + "★ (" + a.n + " reviews)" : "new, no reviews yet"} | skills: ${(e.skills ?? []).join(", ") || "-"}`;
    }).join("\n") || "(no verified editors yet)";

    const { data: feeRow } = await admin.from("sp_settings").select("value").eq("key", "platform_fee_percent").maybeSingle();
    const feePct = Number.isFinite(Number(feeRow?.value)) ? Number(feeRow?.value) : 5;
    const system = `You are "Sphere AI", the friendly assistant inside Sphere by Syahi Films — an Indian app where clients hire verified video editors.
The user is ${me?.full_name ?? "a user"} (${String(me?.role ?? "client").toLowerCase()}).

HOW SPHERE WORKS (only state these facts, never invent others):
- Categories: ${CATEGORIES.join(", ")}.
- Clients post a job (category, details, budget, deadline, raw files or a Drive link). Editors bid; clients see on every bid whether the editor is ✔ Verified by Sphere or "Not verified". The client picks one, both agree a final price, it gets locked.
- The client pays inside the app (Razorpay). Money is held in escrow. The editor delivers a link; when the client approves, payment is released. Sphere keeps a ${feePct}% fee from the editor's payout.
- No automatic refund after delivery. Full refund if the editor does not deliver within 3 days after the deadline, or if the client cancels within 24 hours of paying before any delivery. Disputes: use "Report problem" — the Sphere team reviews and decides.
- Editors become verified after a call with the Sphere team; they get a code like SF-EDT-1234 and a ✔ badge.
- Support: open Help & Support at the bottom of the Home screen — WhatsApp the Sphere team or use "Report problem" (10 AM–7 PM Mon–Sat). Never share phone numbers.

VERIFIED EDITORS (the ONLY editors you may recommend; always mention their code exactly):
${editorLines}

RULES:
- Reply in the user's language (English, Hindi or Hinglish), short and practical. Use simple bullet points when helpful.
- Help clients write clear job posts (what to include: video type, length, style, references, deadline, budget) and choose editors from the list by category, budget, rating and experience.
- Help editors write bids, improve their profile and portfolio, and give editing advice.
- Never invent editors, prices or policies. If unsure, suggest contacting Support.
- Never ask for passwords, OTPs, card or bank details. Do not discuss anything unrelated to video, editing, creative work or Sphere — politely steer back.`;

    const contents = history.map((m) => ({ role: m.role, parts: [{ text: m.text }] }));
    const generationConfig: Record<string, unknown> = { temperature: action === "draft_job" ? 0.3 : 0.6, maxOutputTokens: 2048 };
    let systemText = system;
    if (action === "draft_job") {
      systemText += `\n\nTASK NOW: Based on the conversation, write a ready-to-post job for Sphere. ` +
        `Pick the best category from the list, write clear project details (3-6 short lines), a sensible budget in rupees, and days until deadline.`;
      generationConfig.responseMimeType = "application/json";
      generationConfig.responseSchema = {
        type: "OBJECT",
        properties: {
          category: { type: "STRING", enum: CATEGORIES },
          description: { type: "STRING" },
          budget: { type: "INTEGER" },
          deadline_days: { type: "INTEGER" },
        },
        required: ["category", "description", "budget", "deadline_days"],
      };
    }

    const payload = JSON.stringify({ systemInstruction: { parts: [{ text: systemText }] }, contents, generationConfig });
    let res: Response | null = null;
    let data: any = null;
    // Busy (503/500/429) or retired (404) model -> try the next one. Bad key/request -> stop.
    const retryable = (st: number) => st === 404 || st === 429 || st === 500 || st === 503;
    const queue: string[] = [];
    const add = (m?: string | null) => { if (m && !queue.includes(m)) queue.push(m); };
    add(Deno.env.get("GEMINI_MODEL")); add(lastGoodModel);
    (await discoverModels(key)).forEach(add);
    FALLBACK_MODELS.forEach(add);
    let calls = 0;
    outer: for (let qi = 0; qi < queue.length && calls < 8; qi++) {
      const model = queue[qi];
      for (let attempt = 0; attempt < 2 && calls < 8; attempt++) {
        calls++;
        res = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`, {
          method: "POST",
          headers: { "Content-Type": "application/json", "x-goog-api-key": key },
          body: payload,
        });
        data = await res.json().catch(() => ({}));
        if (res.ok) { lastGoodModel = model; break outer; }
        console.error("Gemini error", model, res.status, JSON.stringify(data).slice(0, 300));
        // Google often names the replacement model in the error: "...use models/gemini-X-flash..."
        const hint = String(data?.error?.message ?? "").match(/models\/(gemini-[\w.\-]+)/g) ?? [];
        hint.map((h) => h.replace("models/", "").replace(/\.+$/, ""))
          .filter((h) => h !== model && !queue.slice(0, qi + 1).includes(h))
          .forEach((h) => { const at = queue.indexOf(h); if (at > -1) queue.splice(at, 1); queue.splice(qi + 1, 0, h); });
        if (model === lastGoodModel) lastGoodModel = null;
        if (!retryable(res.status)) break outer;
        if (res.status !== 503 || attempt === 1) break;       // 503: one quick retry on the same model
        await new Promise((r) => setTimeout(r, 700));
      }
    }
    // a failed answer does not use up the user's daily messages
    const refund = () => admin.from("sp_ai_usage").upsert({ user_id: user.id, day, count: used }, { onConflict: "user_id,day" });
    if (!res || !res.ok) {
      await refund();
      const status = res?.status ?? 0;
      const g = String(data?.error?.status ?? "");
      const gmsg = String(data?.error?.message ?? "").slice(0, 160);
      if (status === 429 || status === 503 || status === 500) {
        return json({ error: "Sphere AI is busy right now. Please try again in a minute." }, 429);
      }
      if (status === 400 && /API key|API_KEY/i.test(gmsg + g)) {
        return json({ error: "Setup problem: the Gemini API key is not valid. Check GEMINI_API_KEY in Supabase secrets." }, 502);
      }
      if (status === 403 || g === "PERMISSION_DENIED") {
        return json({ error: "Setup problem: Google blocked this key (" + gmsg + ")" }, 502);
      }
      return json({ error: "Sphere AI could not answer (" + status + (gmsg ? ": " + gmsg : "") + ")" }, 502);
    }
    const text = (data?.candidates?.[0]?.content?.parts ?? []).map((p: { text?: string }) => p.text ?? "").join("").trim();
    if (!text) {
      await refund();
      const why = data?.candidates?.[0]?.finishReason ?? data?.promptFeedback?.blockReason ?? "empty";
      return json({ error: "Sphere AI could not answer that (" + why + "). Try asking differently." }, 502);
    }

    if (action === "draft_job") {
      try {
        const d = JSON.parse(text);
        return json({ draft: {
          category: CATEGORIES.includes(d.category) ? d.category : CATEGORIES[0],
          description: String(d.description ?? "").slice(0, 1500),
          budget: Math.max(0, Math.round(Number(d.budget) || 0)),
          deadline_days: Math.min(60, Math.max(1, Math.round(Number(d.deadline_days) || 7))),
        }, left: DAILY_LIMIT - used - 1 });
      } catch {
        return json({ error: "Could not create the job draft. Please try again." }, 502);
      }
    }
    return json({ reply: text.slice(0, 4000), left: DAILY_LIMIT - used - 1 });
  } catch (e) {
    return json({ error: String((e as Error)?.message ?? e) }, 500);
  }
});
