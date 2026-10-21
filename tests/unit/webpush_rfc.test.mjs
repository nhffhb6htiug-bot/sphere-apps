import { readFileSync, writeFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os'; import { join } from 'node:path';
const FN = new URL('../../supabase/functions/sphere-push/', import.meta.url);
const TMP = mkdtempSync(join(tmpdir(), 'sphere-push-'));
writeFileSync(join(TMP, 'webpush.mjs'), readFileSync(new URL('webpush.js', FN), 'utf8'));
writeFileSync(join(TMP, 'pushcore.mjs'), readFileSync(new URL('pushcore.js', FN), 'utf8').replace("from './webpush.js'", "from './webpush.mjs'"));
const { encryptPayload, b64u, ub64u, vapidHeader, generateVapidKeys } = await import(join(TMP, 'webpush.mjs'));
let pass = 0, fail = 0; const check = (n, ok, d = '') => { ok ? pass++ : fail++; console.log((ok ? 'PASS ' : 'FAIL ') + n + (d ? ' — ' + d : '')); };
// RFC 8291 Appendix A test vector
const asPublic = 'BP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27mlmlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A8';
const asPrivate = 'yfWPiYE-n46HLnH0KqZOF1fJJU3MYrct3AELtAQ-oRw';
const pub = ub64u(asPublic);
const asJwk = { kty: 'EC', crv: 'P-256', d: asPrivate, x: b64u(pub.slice(1, 33)), y: b64u(pub.slice(33, 65)) };
const body = await encryptPayload(new TextEncoder().encode('When I grow up, I want to be a watermelon'),
  'BCVxsr7N_eNgVRqvHtD0zTZsEc6-VV-JvLexhqUzORcxaOzi6-AYWXvTBHm4bjyPjs7Vd8pZGH6SRpkNtoIAiw4', 'BTBZMqHH6r4Tts7J_aSIgg',
  { asJwk, asPublic, salt: 'DGv6ra1nlYgDCS1FRnbzlw' });
const expected = 'DGv6ra1nlYgDCS1FRnbzlwAAEABBBP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27mlmlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A_yl95bQpu6cVPTpK4Mqgkf1CXztLVBSt2Ks3oZwbuwXPXLWyouBWLVWGNWQexSgSxsj_Qulcy4a-fN';
check('W1 encryption matches the RFC 8291 test vector byte for byte', b64u(body) === expected, b64u(body) === expected ? '' : b64u(body).slice(0, 60) + '…');
// VAPID: header shape + signature verifies with the public key
const k = await generateVapidKeys();
const h = await vapidHeader('https://fcm.googleapis.com/fcm/send/abc', k.publicKey, k.privateJwk, 'https://sphere-live.onrender.com');
const m = h.match(/^vapid t=([^.]+)\.([^.]+)\.([^,]+), k=(.+)$/);
const claims = m && JSON.parse(new TextDecoder().decode(ub64u(m[2])));
const vkey = await crypto.subtle.importKey('raw', ub64u(k.publicKey), { name: 'ECDSA', namedCurve: 'P-256' }, false, ['verify']);
const okSig = m && await crypto.subtle.verify({ name: 'ECDSA', hash: 'SHA-256' }, vkey, ub64u(m[3]), new TextEncoder().encode(m[1] + '.' + m[2]));
check('W2 VAPID token: ES256 signature verifies, audience = push service, expires within 24 h', !!okSig && claims.aud === 'https://fcm.googleapis.com' && claims.exp - Date.now() / 1000 <= 86400 && claims.sub.startsWith('https://'), JSON.stringify(claims));
check('W3 VAPID public key is a 65-byte uncompressed P-256 point', ub64u(k.publicKey).length === 65 && ub64u(k.publicKey)[0] === 4);
// random encryption (normal use) round-trips with an independent Node decryptor
import { createECDH, hkdfSync, createDecipheriv } from 'node:crypto';
const ua = createECDH('prime256v1'); ua.generateKeys(); const auth = crypto.getRandomValues(new Uint8Array(16));
const msg = JSON.stringify({ title: 'Yhiyhi 681', body: 'Final cut ready? 🎬', category: 'messages' });
const b2 = await encryptPayload(new TextEncoder().encode(msg), b64u(ua.getPublicKey()), b64u(auth));
const salt = b2.slice(0, 16), idlen = b2[20], asP = b2.slice(21, 21 + idlen), ct = b2.slice(21 + idlen);
const shared = ua.computeSecret(Buffer.from(asP));
const ikm = Buffer.from(hkdfSync('sha256', shared, Buffer.from(auth), Buffer.concat([Buffer.from('WebPush: info\0'), ua.getPublicKey(), Buffer.from(asP)]), 32));
const cek = Buffer.from(hkdfSync('sha256', ikm, Buffer.from(salt), Buffer.from('Content-Encoding: aes128gcm\0'), 16));
const nonce = Buffer.from(hkdfSync('sha256', ikm, Buffer.from(salt), Buffer.from('Content-Encoding: nonce\0'), 12));
const d = createDecipheriv('aes-128-gcm', cek, nonce); d.setAuthTag(Buffer.from(ct.slice(-16)));
const plain = Buffer.concat([d.update(Buffer.from(ct.slice(0, -16))), d.final()]);
check('W4 a normal (random-key) push decrypts correctly with Node’s own crypto (Hindi/emoji text too)', plain.slice(0, -1).toString() === msg && plain[plain.length - 1] === 2);
let bad = false; try { await encryptPayload(new Uint8Array([1]), 'AAAA', b64u(auth)); } catch(e) { bad = true; }
check('W5 a broken subscription key is refused (no crash, no send)', bad);
console.log(`TOTAL ${pass}/${pass + fail}`); process.exit(fail ? 1 : 0);
