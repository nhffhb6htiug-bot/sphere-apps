// Supabase Edge Function: sphere-ai
// Sphere AI assistant powered by Google Gemini (free tier from Google AI Studio).
// The Gemini API key stays here on the server (secret GEMINI_API_KEY), never in the app.
// v22: use Groq supported GPT-OSS models and its authenticated model catalog;
// Gemini remains primary but quickly falls back to Groq if unavailable.
import { createClient } from "npm:@supabase/supabase-js@2";

const FALLBACK_MODELS = ["gemini-3.5-flash-lite", "gemini-flash-lite-latest", "gemini-3.8-flash", "gemini-flash-latest"];
let lastGoodModel: string | null = null;
let discovered: string[] | null = null;
// In-memory per warm instance: avoid hammering a retired or overloaded provider model.
const unavailableUntil = new Map<string, number>();
// These model IDs replace the retired free-tier Llama models (Groq deprecations 2026).
const GROQ_PREFERRED_MODELS = ["openai/gpt-oss-20b", "openai/gpt-oss-120b", "qwen/qwen3.8-27b"];
let groqCatalog: { models: string[]; until: number } | null = null;
async function discoverGroqModels(key: string): Promise<string[]> {
  if (groqCatalog && groqCatalog.until > Date.now()) return groqCatalog.models;
  try {
    const response = await fetch("https://api.groq.com/openai/v1/models", {
      headers: { Authorization: "Bearer " + key },
      signal: AbortSignal.timeout(3500),
    });
    if (!response.ok) {
      console.error("Groq model catalog request", response.status);
      return GROQ_PREFERRED_MODELS;
    }
    const catalog = await response.json();
    const ids = new Set<string>((Array.isArray(catalog?.data) ? catalog.data : [])
      .filter((item: any) => item?.active !== false && typeof item?.id === "string")
      .map((item: any) => item.id));
    const available = GROQ_PREFERRED_MODELS.filter((id) => ids.has(id));
    groqCatalog = { models: available, until: Date.now() + 15 * 60000 };
    if (!available.length) console.error("Groq account has no supported text models in its catalog");
    return available;
  } catch (e) {
    console.error("Groq model catalog unavailable", (e as Error)?.name ?? "Error");
    return GROQ_PREFERRED_MODELS;
  }
}
async function discoverModels(key: string): Promise<string[]> {
  if (discovered) return discovered;
  try {
    const r = await fetch("https://generativelanguage.googleapis.com/v1beta/models?pageSize=200", { headers: { "x-goog-api-key": key }, signal: AbortSignal.timeout(5000) });
    const d = await r.json();
    const names: string[] = (d.models ?? [])
      .filter((m: any) => (m.supportedGenerationMethods ?? []).includes("generateContent"))
      .map((m: any) => String(m.name).replace(/^models\//, ""))
      .filter((n: string) => /flash/i.test(n) && !/gemini-2\.5(?:-|$)/.test(n) && !/(image|tts|audio|live|embed|vision|thinking|computer|robotics)/i.test(n));
    const score = (n: string) => {
      const v = parseFloat((n.match(/gemini-(\d+(?:\.\d+)?)/) ?? [])[1] ?? "0");
      return (/lite/.test(n) ? 100 : 0) + v * 10 + (/latest/.test(n) ? 3 : 0) - (/(preview|exp)/.test(n) ? 30 : 0);
    };
    discovered = names.sort((a, b) => score(b) - score(a)).slice(0, 5);
  } catch (e) {
    console.error("model discovery failed", e);
    discovered = [];
  }
  return discovered;
}
const DAILY_LIMIT = Number(Deno.env.get("AI_DAILY_LIMIT") ?? "30");
const CATEGORIES = ["Vlog Editing", "Cinematic", "Gaming Edits", "Reels & Shorts", "Podcast Editing",
  "Color Grading & VFX", "Motion Graphics", "Ads & Commercial", "AI Video Editor"];

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
  const started = Date.now();
  try {
    const key = Deno.env.get("GEMINI_API_KEY");
    const groqKey = Deno.env.get("GROQ_API_KEY");
    if (!key && !groqKey) return json({ error: "Sphere AI providers are not configured yet." }, 503);

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

    const day = new Date(Date.now() + 330 * 60000).toISOString().slice(0, 10);
    const { data: usage } = await admin.from("sp_ai_usage").select("count").eq("user_id", user.id).eq("day", day).maybeSingle();
    const used = usage?.count ?? 0;
    if (used >= DAILY_LIMIT) {
      return json({ error: `You have used all ${DAILY_LIMIT} Sphere AI messages for today. Please come back tomorrow.` }, 429);
    }
    await admin.from("sp_ai_usage").upsert({ user_id: user.id, day, count: used + 1 }, { onConflict: "user_id,day" });

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
- The client pays inside the app (Razorpay). Money is held in escrow. The editor sends a watermarked preview; the client approves the preview or asks for a revision; then the editor delivers the final video and the client releases the payment. Sphere keeps a ${feePct}% fee from the editor's payout.
- Refunds are never automatic: the client asks with "Report problem" on the project (or Help & Support), and the Sphere team checks the case and sends approved refunds back through Razorpay. Per the Refund Policy a full refund is given if the editor does not deliver within 3 days after the deadline, or if the client asks to cancel within 24 hours of paying and nothing was delivered yet. After a delivery the Sphere team decides (re-edit, partial or full refund, or release to the editor). After the client approves, there is no refund.
- Editors become verified after making a short Sphere promo video and a call with the Sphere team; they get a code like SF-EDT-1234 and a ✔ badge.
- Support: open Help & Support — WhatsApp the Sphere team or use "Report problem" (10 AM–7 PM Mon–Sat). Never share phone numbers.

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
    let status = 0;
    // busy (503/500/429), timed out (504) or retired (404) model -> try the next one. Bad key/request -> stop.
    const retryable = (st: number) => st === 404 || st === 429 || st === 500 || st === 503 || st === 504;
    const queue: string[] = [];
    const add = (m?: string | null) => { if (m && !/gemini-2\.5(?:-|$)/.test(m) && !queue.includes(m)) queue.push(m); };
    if (key) {
      add(lastGoodModel);
      FALLBACK_MODELS.forEach(add);
      add(Deno.env.get("GEMINI_MODEL"));
      // Save the model-discovery call for when Groq backup is not configured.
      if (!groqKey) (await discoverModels(key)).forEach(add);
    }
    let calls = 0;
    for (let qi = 0; qi < queue.length && calls < (groqKey ? 1 : 4); qi++) {
      const left = (groqKey ? 17000 : 30000) - (Date.now() - started);
      if (left < 4000) break;                                  // give up in time; never hang
      const model = queue[qi];
      if ((unavailableUntil.get(model) ?? 0) > Date.now()) continue;
      calls++;
      try {
        res = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`, {
          method: "POST",
          headers: { "Content-Type": "application/json", "x-goog-api-key": key },
          body: payload,
          signal: AbortSignal.timeout(Math.min(groqKey ? 5000 : 8000, left - 1000)),
        });
        status = res.status;
        data = await res.json().catch(() => ({}));
      } catch (e) {
        res = null; status = 504; data = { error: { message: "timed out" } };
        console.error("Gemini timeout", model, String((e as Error)?.message ?? e));
      }
      if (res && res.ok) { lastGoodModel = model; unavailableUntil.delete(model); break; }
      if (res) console.error("Gemini error", model, status, JSON.stringify(data).slice(0, 300));
      if (status === 404) unavailableUntil.set(model, Date.now() + 24 * 60 * 60 * 1000);
      else if (status === 429 || status === 500 || status === 503 || status === 504)
        unavailableUntil.set(model, Date.now() + (status === 429 ? 120000 : 60000));
      const hint = String(data?.error?.message ?? "").match(/models\/(gemini-[\w.\-]+)/g) ?? [];
      hint.map((h) => h.replace("models/", "").replace(/\.+$/, ""))
        .filter((h) => h !== model && !queue.slice(0, qi + 1).includes(h))
        .forEach((h) => { const at = queue.indexOf(h); if (at > -1) queue.splice(at, 1); queue.splice(qi + 1, 0, h); });
      if (model === lastGoodModel) lastGoodModel = null;
      if (!retryable(status)) break;
    }

    // Groq fallback uses the same authenticated user, verified editors and usage limit.
    // The API key never leaves Supabase; nothing about it is returned to the browser.
    if ((!res || !res.ok) && groqKey && (status === 0 || retryable(status))) {
      const groqModels = await discoverGroqModels(groqKey);
      const groqInstructions = action === "draft_job"
        ? systemText + "\nRespond with ONLY a valid JSON object with category, description, budget and deadline_days. category must be one of: " + CATEGORIES.join(", ") + ". budget and deadline_days must be numbers. No markdown."
        : systemText;
      for (const model of groqModels) {
        const left = 39000 - (Date.now() - started);
        if (left < 4000) break;
        try {
          const groqRequest = {
            model,
            messages: [
              { role: "system", content: groqInstructions },
              ...history.map((m) => ({ role: m.role === "model" ? "assistant" : "user", content: m.text })),
            ],
            temperature: action === "draft_job" ? 0.3 : 0.6,
            max_completion_tokens: action === "draft_job" ? 1600 : 1600,
            ...(model.startsWith("openai/gpt-oss-") ? { reasoning_effort: "low", include_reasoning: false } : {}),
            ...(action === "draft_job" ? { response_format: { type: "json_object" } } : {}),
          };
          const gr = await fetch("https://api.groq.com/openai/v1/chat/completions", {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              Authorization: "Bearer " + groqKey,
            },
            body: JSON.stringify(groqRequest),
            signal: AbortSignal.timeout(Math.min(11000, left - 1000)),
          });
          const gd = await gr.json().catch(() => ({}));
          const groqText = String(gd?.choices?.[0]?.message?.content ?? "").trim();
          if (gr.ok && groqText) {
            // Reuse the existing response parsing, draft schema validation, quota logic
            // and error-handling code; do not alter client response contracts.
            res = new Response(null, { status: 200 });
            status = 200;
            data = { candidates: [{ content: { parts: [{ text: groqText }] } }] };
            console.log("Sphere AI fallback provider succeeded", model);
            break;
          }
          console.error("Groq backup response", model, gr.status, String(gd?.error?.code ?? gd?.error?.type ?? "").slice(0, 60));
          if (![404, 408, 429, 500, 502, 503, 504].includes(gr.status)) break;
        } catch (e) {
          console.error("Groq backup connection/timeout", model, (e as Error)?.name ?? "Error");
        }
      }
    }

    const refund = () => admin.from("sp_ai_usage").upsert({ user_id: user.id, day, count: used }, { onConflict: "user_id,day" });
    if (!res || !res.ok) {
      await refund();
      const g = String(data?.error?.status ?? "");
      const gmsg = String(data?.error?.message ?? "").slice(0, 160);
      if (retryable(status) || status === 0) {
        return json({ error: "AI provider is temporarily busy. Please try again shortly." }, 503);
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
