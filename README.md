# sphere-moderate (Part 9) — optional AI check for held chat messages

Without this function everything still works: held messages simply wait for an admin
(Admin Panel → 🛡️ Messages to review). With it, AI checks each held message within seconds
and delivers the innocent ones automatically.

## Deploy from the Supabase dashboard (no coding tools needed)
1. Supabase → **Edge Functions** → **Deploy a new function** → **Via Editor**.
2. Function name: `sphere-moderate` (exactly).
3. Delete the sample code, paste the whole `index.ts` from this folder → **Deploy**.
4. Supabase → **Edge Functions** → **Secrets**: make sure the Google AI key is there as
   `GEMINI_API_KEY` (if Sphere AI uses a different name, add the same key again under `GEMINI_API_KEY`).

## Test
Send a chat message like "WhatsApp pe aa jao" → it shows "being checked" → in Admin Panel the
message gets an "🤖 AI: …" chip. A message like "export it for WhatsApp status also" should be
delivered automatically.
