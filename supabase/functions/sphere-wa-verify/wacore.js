// sphere-wa-verify core — Meta WhatsApp Cloud API webhook: the USER sends "SPH-123456" to Sphere's number;
// we check the code + the sender's real number in the database and reply "verified". Nothing here sends OTPs,
// so there is no per-message cost (user-started chats + replies inside the 24 h window are free).
// Phone numbers and codes are never logged.
const te = new TextEncoder();
function hex(buf){ return [...new Uint8Array(buf)].map(b => b.toString(16).padStart(2, '0')).join(''); }
function sameText(a, b){ a = String(a || ''); b = String(b || ''); if (!a || a.length !== b.length) return false; let r = 0; for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i); return r === 0; }
// Meta signs the raw body with the App Secret: header  x-hub-signature-256: sha256=<hex hmac>
export async function verifySignature(appSecret, header, body){
  if (!appSecret || !header || !String(header).startsWith('sha256=')) return false;
  const key = await crypto.subtle.importKey('raw', te.encode(appSecret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const sig = hex(await crypto.subtle.sign('HMAC', key, te.encode(body)));
  return sameText(String(header).slice(7), sig);
}
export function phone10(p){ return String(p || '').replace(/\D/g, '').slice(-10); }
export function extractCode(text){ const m = String(text || '').match(/SPH[\s\-_:]*([0-9]{6})(?![0-9])/i); return m ? m[1] : ''; }
export function extractMessages(payload){
  const out = [];
  for (const e of (payload && payload.entry) || []) for (const c of (e && e.changes) || []) {
    const v = c && c.value; if (!v || !Array.isArray(v.messages)) continue;
    for (const m of v.messages) out.push({ from: String(m.from || ''), type: m.type, text: (m.text && m.text.body) || '', id: m.id || '', phoneId: (v.metadata && v.metadata.phone_number_id) || '' });
  }
  return out;
}
export const REPLY = {
  ok: '✅ Your mobile number is verified. Go back to the Sphere app — it will open by itself.',
  no_match: '❌ This code is wrong or has expired. Open Sphere and tap “Verify on WhatsApp” again to get a new code.',
  taken: 'This mobile number is already registered with another Sphere account. Please log in with that account.',
  help: 'Hi! To verify your number, open the Sphere app and tap “Verify on WhatsApp”. Then send the code message from here.',
  fail: 'Sorry, we could not check this right now. Please try again in a minute.'
};
export async function sendReply(env, phoneId, to, body, doFetch){
  const id = env.WA_PHONE_NUMBER_ID || phoneId;
  if (!env.WA_ACCESS_TOKEN || !id || !to) return false;
  const r = await doFetch('https://graph.facebook.com/v21.0/' + id + '/messages', { method: 'POST',
    headers: { Authorization: 'Bearer ' + env.WA_ACCESS_TOKEN, 'Content-Type': 'application/json' },
    body: JSON.stringify({ messaging_product: 'whatsapp', to, type: 'text', text: { body } }) });
  return r.ok;
}
export async function handle(req, env, db, doFetch){
  const url = new URL(req.url);
  if (req.method === 'GET') {            // Meta's one-time "verify this webhook" call
    const ok = url.searchParams.get('hub.mode') === 'subscribe' && sameText(url.searchParams.get('hub.verify_token'), env.WA_VERIFY_TOKEN);
    return ok ? { status: 200, text: url.searchParams.get('hub.challenge') || '' } : { status: 403, text: 'Forbidden' };
  }
  if (req.method !== 'POST') return { status: 405, text: '' };
  const body = await req.text();
  if (!(await verifySignature(env.WA_APP_SECRET, req.headers.get('x-hub-signature-256'), body))) return { status: 401, text: 'Bad signature' };
  let payload; try { payload = JSON.parse(body); } catch (_e) { return { status: 200, text: 'ok' }; }
  for (const m of extractMessages(payload)) {
    if (m.type !== 'text') continue;
    const code = extractCode(m.text);
    let reply = REPLY.help;
    if (code) {
      const { data, error } = await db.rpc('sp_phone_verify_complete', { p_phone10: phone10(m.from), p_code: code });
      reply = error ? REPLY.fail : (REPLY[data] || REPLY.no_match);
    }
    await sendReply(env, m.phoneId, m.from, reply, doFetch).catch(() => false);
  }
  return { status: 200, text: 'ok' };   // always 200 so Meta does not keep retrying
}
