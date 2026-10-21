// Runs the real notificationclick handler from sw.js in a fake service-worker environment.
import { readFileSync } from 'node:fs';
const src = readFileSync(new URL('../../sw.js', import.meta.url), 'utf8');
let pass = 0, fail = 0; const check = (n, ok, d = '') => { ok ? pass++ : fail++; console.log((ok ? 'PASS ' : 'FAIL ') + n + (d ? ' — ' + d : '')); };
async function run(data, windows){
  const handlers = {}; const log = { posted: [], focused: 0, opened: [] };
  const clients = { matchAll: async () => windows.map(() => ({ focus: async () => { log.focused++; }, postMessage: (m) => log.posted.push(m) })), openWindow: async (u) => { log.opened.push(u); }, claim: async () => {} };
  const self = { addEventListener: (t, f) => { handlers[t] = f; }, clients, skipWaiting: () => {}, registration: {}, location: { hostname: 'sphere-live.onrender.com', origin: 'https://sphere-live.onrender.com' } };
  const caches = { open: async () => ({ addAll: async () => {}, put: async () => {}, match: async () => null }), keys: async () => [], delete: async () => true, match: async () => null };
  log.fetched = log.fetched || [];
  new Function('self', 'caches', 'fetch', 'location', src)(self, caches, async (u, i) => { (log.fetched || []).push({ u, i }); return { ok: true, clone(){ return this; } }; }, { origin: 'https://sphere-live.onrender.com' });
  let done; const ev = { notification: { data, close(){} }, waitUntil: (p) => { done = p; } };
  handlers.notificationclick(ev); await done; return log;
}
const id = '22222222-2222-4222-8222-222222222222';
let l = await run({ chatWith: id }, [1]);
check('S1 app already open → tells it which chat to open and focuses it', l.posted.length === 1 && l.posted[0].type === 'sphere-open-chat' && l.posted[0].chatWith === id && l.focused === 1 && !l.opened.length, JSON.stringify(l));
l = await run({ chatWith: id }, []);
check('S2 app closed → opens Sphere at that chat (/?chat=…)', l.opened[0] === '/?chat=' + id, JSON.stringify(l.opened));
l = await run({ chatWith: 'javascript:alert(1)' }, []);
check('S3 a bad chat id is ignored → opens Sphere home only', l.opened[0] === '/', JSON.stringify(l.opened));
console.log(`TOTAL ${pass}/${pass + fail}`); process.exit(fail ? 1 : 0);
