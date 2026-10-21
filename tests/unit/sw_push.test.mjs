// Runs the real push + notificationclick handlers from sw.js in a fake service-worker environment.
import { readFileSync } from 'node:fs';
const src = readFileSync(new URL('../../sw.js', import.meta.url), 'utf8');
let pass = 0, fail = 0; const check = (n, ok, d = '') => { ok ? pass++ : fail++; console.log((ok ? 'PASS ' : 'FAIL ') + n + (d ? ' — ' + d : '')); };
function env(windows){
  const h = {}; const log = { shown: [], posted: [], opened: [], focused: 0, fetched: [] };
  const clients = { matchAll: async () => windows.map(v => ({ visibilityState: v, focus: async () => { log.focused++; }, postMessage: (m) => log.posted.push(m) })), openWindow: async (u) => log.opened.push(u), claim: async () => {} };
  const self = { addEventListener: (t, f) => { h[t] = f; }, clients, skipWaiting: () => {}, location: { hostname: 'sphere-live.onrender.com', origin: 'https://sphere-live.onrender.com' }, registration: { showNotification: async (t, o) => log.shown.push({ t, o }) } };
  const caches = { open: async () => ({ addAll: async () => {}, put: async () => {}, match: async () => null }), keys: async () => [], delete: async () => true, match: async () => null };
  log.fetched = log.fetched || [];
  new Function('self', 'caches', 'fetch', 'location', src)(self, caches, async (u, i) => { (log.fetched || []).push({ u, i }); return { ok: true, clone(){ return this; } }; }, { origin: 'https://sphere-live.onrender.com' });
  return { h, log };
}
async function push(windows, data, raw){
  const { h, log } = env(windows); let p;
  h.push({ data: raw !== undefined ? { json(){ throw new Error('bad'); } } : { json: () => data }, waitUntil: (x) => { p = x; } }); await p; return log;
}
async function click(windows, data){ const { h, log } = env(windows); let p; h.notificationclick({ notification: { data, close(){} }, waitUntil: (x) => { p = x; } }); await p; return log; }
const S = '22222222-2222-4222-8222-222222222222';
let l = await push(['visible'], { id: 'n1', title: 'Yhiyhi', body: 'hi', category: 'messages', sender_id: S, tag: 'chat-' + S });
check('P1 Sphere on screen → no phone notification (the app shows the message itself)', l.shown.length === 0 && l.posted[0].type === 'sphere-push');
l = await push(['hidden'], { id: 'n1', title: 'Yhiyhi 681', body: 'Final cut ready?', category: 'messages', sender_id: S, tag: 'chat-' + S });
check('P2 Sphere in the background → phone notification with name + message, opens that chat', l.shown.length === 1 && l.shown[0].t === 'Yhiyhi 681' && l.shown[0].o.body === 'Final cut ready?' && l.shown[0].o.tag === 'chat-' + S && l.shown[0].o.data.chatWith === S);
l = await push([], { id: 'n2', title: 'New bid on your job', body: '₹800 · Rahul', category: 'bids', tag: 'n-n2' });
check('P3 Sphere closed → bids / jobs / payments arrive too and open the Notifications screen', l.shown.length === 1 && l.shown[0].o.data.open === 'notifications' && !l.shown[0].o.data.chatWith);
l = await push(['visible'], { id: 'n3', title: '🔔 Sphere test', body: 'Phone notifications work', category: 'general' });
check('P4 the "Send test" notification is always shown, even with Sphere open', l.shown.length === 1);
l = await push([], null, 'broken');
check('P5 an unreadable push still shows a plain Sphere notification (never crashes)', l.shown.length === 1 && l.shown[0].t === 'Sphere');
l = await push([], { id: 'n4', title: 'x', category: 'messages', sender_id: 'javascript:alert(1)' });
check('P6 a bad sender id is never used as a chat link', l.shown[0].o.data.chatWith === '');
l = await click([], { open: 'notifications' });
check('C1 tapping a non-chat notification with Sphere closed opens the Notifications screen', l.opened[0] === '/?open=notifications');
l = await click(['hidden'], { open: 'notifications' });
check('C2 …with Sphere open in the background it switches to Notifications', l.posted[0] && l.posted[0].type === 'sphere-open-notifications' && l.focused === 1);
l = await click([], { chatWith: S });
check('C3 tapping a chat notification still opens that chat', l.opened[0] === '/?chat=' + S);
l = await push([], { id: 'n9', title: 'Yhiyhi', body: 'hi', category: 'messages', sender_id: S, tag: 'chat-' + S, ack: 'a'.repeat(64) });
const f = l.fetched[0]; const fb = f && JSON.parse(f.i.body);
check('R1 a chat push tells the server "delivered" (✓✓) with its receipt token', l.shown.length === 1 && f && f.u === 'https://sphere-live.onrender.com/sb/functions/v1/sphere-push' && fb.action === 'delivered' && fb.id === 'n9' && fb.token === 'a'.repeat(64));
l = await push(['visible'], { id: 'n10', title: 'x', category: 'messages', sender_id: S, ack: 'b'.repeat(64) });
check('R2 …also when Sphere is on screen', l.fetched.length === 1 && l.shown.length === 0);
l = await push([], { id: 'n11', title: 'New bid', category: 'bids' });
check('R3 other pushes send no receipt', l.fetched.length === 0);
console.log(`TOTAL ${pass}/${pass + fail}`); process.exit(fail ? 1 : 0);
