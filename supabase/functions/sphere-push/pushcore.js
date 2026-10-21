// sphere-push core: delivers one notification (or a sweep of pending ones) to the person's phones.
// Called only by the database (secret header). No message text is ever logged.
import { encryptPayload, generateVapidKeys, vapidHeader } from './webpush.js';
const te = new TextEncoder();
function sameText(a, b){ a = String(a || ''); b = String(b || ''); if (!a || a.length !== b.length) return false; let r = 0; for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i); return r === 0; }
const URGENT = new Set(['messages', 'payment', 'refund', 'dispute', 'security']);
export async function ensureKeys(db, cfg){
  if (cfg && cfg.vapid_public && cfg.vapid_private) return cfg;
  const k = await generateVapidKeys();
  const { data, error } = await db.rpc('sp_push_internal_set_keys', { p_public: k.publicKey, p_private: k.privateJwk });
  if (error) throw new Error('keys: ' + error.message);
  return data;                                            // the keys that won (another call may have made them first)
}
export async function deliver(db, cfg, id, doFetch){
  const { data: n } = await db.from('sp_notifications').update({ push_status: 'sending' }).eq('id', id).eq('push_status', 'pending')
    .select('id,user_id,title,body,category,sender_id').maybeSingle();
  if (!n) return { id, status: 'skipped' };               // already handled (duplicate call) or push not wanted
  const { data: subs } = await db.from('sp_push_subs').select('id,endpoint,p256dh,auth').eq('user_id', n.user_id);
  if (!subs || !subs.length){ await db.from('sp_notifications').update({ push_status: 'no_device' }).eq('id', n.id); return { id, status: 'no_device' }; }
  const isChat = n.category === 'messages' && !!n.sender_id;
  const payload = te.encode(JSON.stringify({ id: n.id, title: (n.title || 'Sphere').slice(0, 80), body: (n.body || '').slice(0, 300),
    category: n.category || 'general', sender_id: isChat ? n.sender_id : null, tag: isChat ? 'chat-' + n.sender_id : 'n-' + n.id }));
  let sent = 0, gone = 0, failed = 0;
  for (const s of subs){
    try {
      const body = await encryptPayload(payload, s.p256dh, s.auth);
      const headers = { Authorization: await vapidHeader(s.endpoint, cfg.vapid_public, cfg.vapid_private, cfg.subject),
        'Content-Encoding': 'aes128gcm', 'Content-Type': 'application/octet-stream', TTL: '86400',
        Urgency: URGENT.has(n.category) ? 'high' : 'normal' };
      if (isChat) headers.Topic = ('c' + n.sender_id.replace(/-/g, '')).slice(0, 32);   // newer message from the same person replaces an undelivered older one
      const r = await doFetch(s.endpoint, { method: 'POST', headers, body });
      try { await r.body?.cancel?.(); } catch (_e) {}
      if (r.status >= 200 && r.status < 300){ sent++; await db.from('sp_push_subs').update({ last_ok_at: new Date().toISOString() }).eq('id', s.id); }
      else if (r.status === 404 || r.status === 410){ gone++; await db.from('sp_push_subs').delete().eq('id', s.id); }   // phone uninstalled / permission removed
      else { failed++; console.log('push not accepted', r.status); }
    } catch (e){ failed++; console.log('push error', String(e && e.message || e).slice(0, 100)); }
  }
  const status = sent ? 'sent' : (gone && !failed ? 'no_device' : 'failed');
  await db.from('sp_notifications').update({ push_status: status }).eq('id', n.id);
  return { id, status, sent, gone, failed };
}
export async function handle(req, db, doFetch){
  if (req.method === 'OPTIONS') return { status: 200, body: { ok: true } };
  if (req.method !== 'POST') return { status: 405, body: { ok: false } };
  let input = {}; try { input = await req.json(); } catch (_e) {}
  const { data: cfg0, error } = await db.rpc('sp_push_internal_config');
  if (error || !cfg0) return { status: 500, body: { ok: false, error: 'not configured' } };
  if (input.action === 'init'){ const cfg = await ensureKeys(db, cfg0); return { status: 200, body: { ok: true, publicKey: cfg.vapid_public } }; }   // public key only
  if (!sameText(req.headers.get('x-sphere-push'), cfg0.trigger_secret)) return { status: 401, body: { ok: false } };
  const cfg = await ensureKeys(db, cfg0);
  let ids = [];
  if (input.id) ids = [String(input.id)];
  else if (input.sweep){
    const { data } = await db.from('sp_notifications').select('id').eq('push_status', 'pending')
      .lt('created_at', new Date(Date.now() - 60000).toISOString()).gt('created_at', new Date(Date.now() - 86400000).toISOString()).limit(50);
    ids = (data || []).map(r => r.id);
  }
  const results = [];
  for (const id of ids) results.push(await deliver(db, cfg, id, doFetch));
  return { status: 200, body: { ok: true, results: results.map(r => ({ status: r.status, sent: r.sent || 0 })) } };
}
