import { readFileSync, writeFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os'; import { join } from 'node:path';
const FN = new URL('../../supabase/functions/sphere-push/', import.meta.url);
const TMP = mkdtempSync(join(tmpdir(), 'sphere-push-'));
writeFileSync(join(TMP, 'webpush.mjs'), readFileSync(new URL('webpush.js', FN), 'utf8'));
writeFileSync(join(TMP, 'pushcore.mjs'), readFileSync(new URL('pushcore.js', FN), 'utf8').replace("from './webpush.js'", "from './webpush.mjs'"));
const { handle } = await import(join(TMP, 'pushcore.mjs'));
const { b64u, ub64u } = await import(join(TMP, 'webpush.mjs'));
import { createECDH, hkdfSync, createDecipheriv } from 'node:crypto';
let pass = 0, fail = 0; const check = (n, ok, d = '') => { ok ? pass++ : fail++; console.log((ok ? 'PASS ' : 'FAIL ') + n + (d ? ' — ' + d : '')); };
// ---- tiny in-memory database with the query shapes the function uses ----
function makeDb(){
  const T = { sp_notifications: [], sp_push_subs: [] }; const cfg = { vapid_public: null, vapid_private: null, trigger_secret: 'a'.repeat(64), subject: 'https://sphere-live.onrender.com' };
  let keyCalls = 0;
  const db = {
    T, cfg, get keyCalls(){ return keyCalls; },
    async rpc(fn, a){
      if (fn === 'sp_push_internal_config') return { data: { ...cfg }, error: null };
      if (fn === 'sp_push_internal_set_keys'){ keyCalls++; if (!cfg.vapid_public){ cfg.vapid_public = a.p_public; cfg.vapid_private = a.p_private; } return { data: { ...cfg }, error: null }; }
      return { data: null, error: { message: 'unknown' } };
    },
    from(t){
      const q = { t, op: 'select', patch: null, f: [] };
      const rows = () => T[t].filter(r => q.f.every(([k, op, v]) => op === 'eq' ? r[k] === v : op === 'lt' ? r[k] < v : r[k] > v));
      const run = () => {
        if (q.op === 'update'){ const rs = rows(); rs.forEach(r => Object.assign(r, q.patch)); return { data: rs, error: null }; }
        if (q.op === 'delete'){ const rs = rows(); T[t] = T[t].filter(r => !rs.includes(r)); return { data: rs, error: null }; }
        return { data: rows(), error: null };
      };
      const p = {
        update(x){ q.op = 'update'; q.patch = x; return p; }, delete(){ q.op = 'delete'; return p; }, select(){ return p; },
        eq(k, v){ q.f.push([k, 'eq', v]); return p; }, lt(k, v){ q.f.push([k, 'lt', v]); return p; }, gt(k, v){ q.f.push([k, 'gt', v]); return p; }, limit(){ return p; },
        async maybeSingle(){ const r = run(); return { data: r.data[0] || null, error: null }; },
        then(res, rej){ return Promise.resolve(run()).then(res, rej); },
      };
      return p;
    },
  };
  return db;
}
// ---- fake phones + push service ----
function phone(){ const e = createECDH('prime256v1'); e.generateKeys(); const auth = crypto.getRandomValues(new Uint8Array(16)); return { e, auth, p256dh: b64u(e.getPublicKey()), authB: b64u(auth) }; }
function decrypt(ph, body){
  const salt = body.slice(0, 16), idlen = body[20], asP = body.slice(21, 21 + idlen), ct = body.slice(21 + idlen);
  const ikm = Buffer.from(hkdfSync('sha256', ph.e.computeSecret(Buffer.from(asP)), Buffer.from(ph.auth), Buffer.concat([Buffer.from('WebPush: info\0'), ph.e.getPublicKey(), Buffer.from(asP)]), 32));
  const cek = Buffer.from(hkdfSync('sha256', ikm, Buffer.from(salt), Buffer.from('Content-Encoding: aes128gcm\0'), 16));
  const nonce = Buffer.from(hkdfSync('sha256', ikm, Buffer.from(salt), Buffer.from('Content-Encoding: nonce\0'), 12));
  const d = createDecipheriv('aes-128-gcm', cek, nonce); d.setAuthTag(Buffer.from(ct.slice(-16)));
  const pl = Buffer.concat([d.update(Buffer.from(ct.slice(0, -16))), d.final()]); return JSON.parse(pl.slice(0, -1).toString());
}
const sent = []; let statusFor = {}; let throwFor = {};
const fakeFetch = async (url, init) => { sent.push({ url, init }); if (throwFor[url]) throw new Error('network'); return { status: statusFor[url] ?? 201, body: null }; };
const req = (body, secret) => ({ method: 'POST', headers: { get: (h) => h === 'x-sphere-push' ? secret : null }, json: async () => body });
const db = makeDb(); const SECRET = db.cfg.trigger_secret;
const U = '11111111-1111-4111-8111-111111111111', S = '22222222-2222-4222-8222-222222222222';
const p1 = phone(), p2 = phone();
db.T.sp_push_subs.push({ id: 's1', user_id: U, endpoint: 'https://fcm.googleapis.com/fcm/send/phone1', p256dh: p1.p256dh, auth: p1.authB },
                      { id: 's2', user_id: U, endpoint: 'https://fcm.googleapis.com/fcm/send/phone2', p256dh: p2.p256dh, auth: p2.authB });
db.T.sp_notifications.push({ id: 'n1', user_id: U, title: 'Yhiyhi 681', body: 'Final cut ready? 🎬', category: 'messages', sender_id: S, push_status: 'pending', created_at: new Date().toISOString() });
// F1 no / wrong secret
let r = await handle(req({ id: 'n1' }, 'wrong'), db, fakeFetch);
check('F1 without the database secret nothing is sent (401)', r.status === 401 && sent.length === 0 && db.T.sp_notifications[0].push_status === 'pending');
// F2 init makes the server keys once, returns only the public key
r = await handle(req({ action: 'init' }), db, fakeFetch); const k1 = r.body.publicKey;
r = await handle(req({ action: 'init' }), db, fakeFetch);
check('F2 init creates the server keys once and returns only the public key', k1 && r.body.publicKey === k1 && db.keyCalls === 1 && !JSON.stringify(r.body).includes('"d"'), `keyCalls=${db.keyCalls}`);
// F3 delivery to both phones, readable, right headers
r = await handle(req({ id: 'n1' }, SECRET), db, fakeFetch);
const m1 = decrypt(p1, sent[0].init.body), m2 = decrypt(p2, sent[1].init.body), h = sent[0].init.headers;
check('F3 the message reaches both phones and only they can read it (title, preview, chat tag)', sent.length === 2 && m1.title === 'Yhiyhi 681' && m1.body === 'Final cut ready? 🎬' && m1.tag === 'chat-' + S && m1.sender_id === S && m2.id === 'n1', JSON.stringify(m1));
const jwt = h.Authorization.match(/^vapid t=([^,]+), k=(.+)$/); const [hh, cc, ss] = jwt[1].split('.');
const vk = await crypto.subtle.importKey('raw', ub64u(jwt[2]), { name: 'ECDSA', namedCurve: 'P-256' }, false, ['verify']);
const sigOk = await crypto.subtle.verify({ name: 'ECDSA', hash: 'SHA-256' }, vk, ub64u(ss), new TextEncoder().encode(hh + '.' + cc));
check('F4 push headers: valid VAPID signature with the stored key, kept 24 h if the phone is off, high urgency, per-chat topic', sigOk && jwt[2] === k1 && h.TTL === '86400' && h.Urgency === 'high' && h.Topic.length <= 32 && /^[A-Za-z0-9_-]+$/.test(h.Topic) && h['Content-Encoding'] === 'aes128gcm');
check('F5 the notification is marked sent', db.T.sp_notifications[0].push_status === 'sent');
// F6 duplicate call → nothing sent again
const before = sent.length; r = await handle(req({ id: 'n1' }, SECRET), db, fakeFetch);
check('F6 the same notification called twice → delivered only once', sent.length === before && r.body.results[0].status === 'skipped');
// F7 a phone that uninstalled (410) is removed; the other still gets it
db.T.sp_notifications.push({ id: 'n2', user_id: U, title: 'Payment received', body: '₹500 for Vlog edit', category: 'payment', push_status: 'pending', created_at: new Date().toISOString() });
statusFor['https://fcm.googleapis.com/fcm/send/phone1'] = 410;
r = await handle(req({ id: 'n2' }, SECRET), db, fakeFetch);
const n2 = db.T.sp_notifications.find(x => x.id === 'n2');
check('F7 a phone that no longer exists is removed; the others still get it', n2.push_status === 'sent' && db.T.sp_push_subs.length === 1 && db.T.sp_push_subs[0].id === 's2');
check('F8 non-chat notifications are not tied to a chat (tag per notification, normal grouping)', decrypt(p2, sent[sent.length - 1].init.body).tag === 'n-n2' && !sent[sent.length - 1].init.headers.Topic);
// F9 network error → failed, no crash; F10 nobody's phones → no_device
db.T.sp_notifications.push({ id: 'n3', user_id: U, title: 'x', body: '', category: 'general', push_status: 'pending', created_at: new Date().toISOString() });
throwFor['https://fcm.googleapis.com/fcm/send/phone2'] = true;
r = await handle(req({ id: 'n3' }, SECRET), db, fakeFetch);
check('F9 a network error marks it failed without crashing', db.T.sp_notifications.find(x => x.id === 'n3').push_status === 'failed');
db.T.sp_notifications.push({ id: 'n4', user_id: S, title: 'New bid', body: '', category: 'bids', push_status: 'pending', created_at: new Date().toISOString() });
r = await handle(req({ id: 'n4' }, SECRET), db, fakeFetch);
check('F10 a person with no phones registered → no_device (nothing sent)', db.T.sp_notifications.find(x => x.id === 'n4').push_status === 'no_device');
// F11 sweep: only pending older than a minute
throwFor = {}; db.T.sp_notifications.push({ id: 'n5', user_id: U, title: 'Old', body: '', category: 'general', push_status: 'pending', created_at: new Date(Date.now() - 120000).toISOString() },
                                          { id: 'n6', user_id: U, title: 'Fresh', body: '', category: 'general', push_status: 'pending', created_at: new Date().toISOString() });
r = await handle(req({ sweep: true }, SECRET), db, fakeFetch);
check('F11 the sweep resends only notifications stuck for over a minute', db.T.sp_notifications.find(x => x.id === 'n5').push_status === 'sent' && db.T.sp_notifications.find(x => x.id === 'n6').push_status === 'pending');
console.log(`TOTAL ${pass}/${pass + fail}`); process.exit(fail ? 1 : 0);
