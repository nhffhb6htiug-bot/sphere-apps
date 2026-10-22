// sphere-otp core — Supabase "Send SMS" auth hook: delivers the login OTP by WhatsApp, or SMS (MSG91).
// The OTP is never logged. Phone numbers reach the database only as hashes (sp_otp_hook_log).
const te = new TextEncoder();
function b64(bytes){ let s = ''; bytes.forEach(b => { s += String.fromCharCode(b); }); return btoa(s); }
function unb64(s){ const bin = atob(s); return Uint8Array.from(bin, c => c.charCodeAt(0)); }
function sameText(a, b){ a = String(a || ''); b = String(b || ''); if (!a || a.length !== b.length) return false; let r = 0; for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i); return r === 0; }
// Standard Webhooks signature used by Supabase hooks: base64(HMAC-SHA256(secret, `${id}.${timestamp}.${body}`))
export async function verifyHook(secret, headers, body, nowSec){
  const raw = String(secret || '').replace(/^v1,/, '').replace(/^whsec_/, '');
  const id = headers.get('webhook-id'), ts = headers.get('webhook-timestamp'), sigs = headers.get('webhook-signature');
  if (!raw || !id || !ts || !sigs) return false;
  if (Math.abs((nowSec ?? Date.now() / 1000) - Number(ts)) > 300) return false;          // older than 5 minutes → refuse (replay)
  const key = await crypto.subtle.importKey('raw', unb64(raw), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const sig = b64(new Uint8Array(await crypto.subtle.sign('HMAC', key, te.encode(`${id}.${ts}.${body}`))));
  return sigs.split(' ').some(part => { const [v, s] = part.split(','); return v === 'v1' && sameText(s, sig); });
}
export function digits(p){ return String(p || '').replace(/\D/g, ''); }
// MSG91 SMS (DLT-registered OTP template): our OTP is passed in "otp"
export async function sendSms(env, phone, otp, doFetch){
  const url = 'https://control.msg91.com/api/v5/otp?template_id=' + encodeURIComponent(env.MSG91_SMS_TEMPLATE_ID) + '&mobile=' + phone + '&otp=' + otp;
  const r = await doFetch(url, { method: 'POST', headers: { authkey: env.MSG91_AUTHKEY, 'Content-Type': 'application/json' }, body: '{}' });
  const j = await r.json().catch(() => ({}));
  return r.ok && j.type !== 'error';
}
// MSG91 WhatsApp (approved "authentication" template with the code in the body and the copy-code button)
export function whatsappBody(env, phone, otp){
  return { integrated_number: env.MSG91_WA_NUMBER, content_type: 'template', payload: { messaging_product: 'whatsapp', type: 'template', template: {
    name: env.MSG91_WA_TEMPLATE, language: { code: env.MSG91_WA_LANG || 'en', policy: 'deterministic' },
    ...(env.MSG91_WA_NAMESPACE ? { namespace: env.MSG91_WA_NAMESPACE } : {}),
    to_and_components: [{ to: [phone], components: { body_1: { type: 'text', value: otp }, button_1: { subtype: 'url', type: 'text', value: otp } } }] } } };
}
export async function sendWhatsApp(env, phone, otp, doFetch){
  const r = await doFetch('https://api.msg91.com/api/v5/whatsapp/whatsapp-outbound-message/bulk/', { method: 'POST',
    headers: { authkey: env.MSG91_AUTHKEY, 'Content-Type': 'application/json' }, body: JSON.stringify(whatsappBody(env, phone, otp)) });
  const j = await r.json().catch(() => ({}));
  return r.ok && j.hasError !== true && j.type !== 'error' && j.status !== 'fail';
}
const err = (code, message) => ({ status: code, body: { error: { http_code: code, message } } });
export async function handleHook(req, env, db, doFetch, nowSec){
  const body = await req.text();
  if (!(await verifyHook(env.SEND_SMS_HOOK_SECRET, req.headers, body, nowSec))) return err(401, 'Invalid hook signature');
  let p; try { p = JSON.parse(body); } catch (_e) { return err(400, 'Bad request'); }
  const phone = digits(p && p.user && p.user.phone), otp = String((p && p.sms && p.sms.otp) || '');
  if (!/^91[6-9]\d{9}$/.test(phone)) return err(400, 'Only Indian mobile numbers (+91) are supported.');
  if (!/^\d{4,10}$/.test(otp)) return err(400, 'Bad request');
  const { data: chk, error } = await db.rpc('sp_otp_hook_check', { p_phone: phone });
  if (error || !chk) return err(500, 'Please try again.');
  if (!chk.allowed) return err(429, chk.reason || 'Too many OTP requests. Please try again later.');
  const waReady = !!(env.MSG91_AUTHKEY && env.MSG91_WA_NUMBER && env.MSG91_WA_TEMPLATE);
  const smsReady = !!(env.MSG91_AUTHKEY && env.MSG91_SMS_TEMPLATE_ID);
  if (!waReady && !smsReady) return err(500, 'OTP sending is not set up yet.');
  let channel = (chk.channel === 'sms' && smsReady) || !waReady ? 'sms' : 'whatsapp', ok = false;
  if (channel === 'whatsapp'){
    ok = await sendWhatsApp(env, phone, otp, doFetch).catch(() => false);
    if (!ok && smsReady) channel = 'sms';                     // WhatsApp failed → SMS
  }
  if (!ok && channel === 'sms') ok = await sendSms(env, phone, otp, doFetch).catch(() => false);
  await db.rpc('sp_otp_hook_log', { p_phone: phone, p_channel: channel, p_ok: ok });
  if (!ok) return err(500, 'Could not send the OTP right now. Please try again.');
  return { status: 200, body: {} };
}
