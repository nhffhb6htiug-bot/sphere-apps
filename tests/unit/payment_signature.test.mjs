// Unit tests for the payment signature checks in the deployed Edge Functions (copied in supabase/functions).
// Runs the real sameText / hmacHex code from each file with Node's WebCrypto. No network, no secrets.
import { readFileSync } from 'node:fs';
import { webcrypto, createHmac } from 'node:crypto';
const root = new URL('../../', import.meta.url).pathname;
const files = ['sphere-extra-payment', 'verify-razorpay-payment', 'razorpay-webhook'].map(f => [f, readFileSync(root + 'supabase/functions/' + f + '/index.ts', 'utf8')]);
let pass = 0, fail = 0;
const check = (name, ok, extra = '') => { ok ? pass++ : fail++; console.log((ok ? 'PASS ' : 'FAIL ') + name + (extra ? ' — ' + extra : '')); };
const strip = s => s.replace(/: string/g, '').replace(/: boolean/g, '').replace(/: Promise<string>/g, '');
for (const [name, src] of files) {
  const st = src.match(/function sameText[\s\S]*?\n}\n/); const hm = src.match(/async function hmacHex[\s\S]*?\n}\n/);
  check(`${name}: has a constant-time compare`, !!st);
  check(`${name}: never compares the signature with !== / ===`, !/expected\s*(!==|===)\s*signature|signature\s*(!==|===)\s*expected/.test(src));
  if (!st || !hm) continue;
  const fns = new Function('crypto', strip(st[0]) + strip(hm[0]) + '; return { sameText, hmacHex };')(webcrypto);
  const secret = 'test_secret_only', msg = 'order_ABC|pay_XYZ';
  const good = createHmac('sha256', secret).update(msg).digest('hex');
  check(`${name}: HMAC matches Node's HMAC-SHA256`, (await fns.hmacHex(secret, msg)) === good);
  check(`${name}: correct signature accepted`, fns.sameText(await fns.hmacHex(secret, msg), good));
  const bad = good.slice(0, -1) + (good.endsWith('0') ? '1' : '0');
  check(`${name}: changed signature refused`, !fns.sameText(await fns.hmacHex(secret, msg), bad));
  check(`${name}: shorter signature refused`, !fns.sameText(await fns.hmacHex(secret, msg), good.slice(1)));
}
const wh = files.find(f => f[0] === 'razorpay-webhook')[1];
check('webhook: refuses everything when its secret is missing', /if \(!secret\) return json\(\{ ok: false, error: "not configured" \}, 500\)/.test(wh));
check('webhook: records each event id once (duplicate → no second processing)', /sp_webhook_events"\)\.insert/.test(wh) && /23505[\s\S]{0,80}duplicate: true/.test(wh));
check('webhook: checks the paid amount against the database', /amount mismatch/.test(wh));
const ex = files.find(f => f[0] === 'sphere-extra-payment')[1];
check('extra-payment: amount comes from the database, never the app', /amount: Math\.round\(Number\(x\.amount\) \* 100\)/.test(ex));
check('extra-payment: only the owner can pay / verify', /x\[ownerField\] !== who\.user\.id/.test(ex));
check('extra-payment: reuses the open order (no double charge)', /if \(x\.order_id && x\.status === "pending"\)/.test(ex));
console.log(`TOTAL ${pass}/${pass + fail}`); process.exit(fail ? 1 : 0);
