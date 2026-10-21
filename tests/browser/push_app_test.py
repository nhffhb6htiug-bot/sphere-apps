# v2.22.12: the app registers the phone for push, avoids double notifications, unregisters on logout, settings test button
import os, sys
from playwright.sync_api import sync_playwright
HERE=os.path.dirname(os.path.abspath(__file__)); ROOT=os.environ.get('SPHERE_ROOT', os.path.abspath(os.path.join(HERE, '..', '..')))
html=open(ROOT+'/index.html.html',encoding='utf-8').read(); js=open(ROOT+'/vendor/supabase-2.117.2.js',encoding='utf-8').read(); mock=open(os.path.join(HERE,'fixtures','chat_mock.js')).read()
R=[]; ok=lambda n,c,d='': R.append(('PASS' if c else 'FAIL', n, d))
KEY='BCVxsr7N_eNgVRqvHtD0zTZsEc6-VV-JvLexhqUzORcxaOzi6-AYWXvTBHm4bjyPjs7Vd8pZGH6SRpkNtoIAiw4'
SETUP = """([key, perm]) => {
  currentUser.phone = '+919812345678';
  window.__subs = 0; window.__unsubs = 0; window.__sub = null; window.__notes = 0;
  class N { constructor(){ window.__notes++; } close(){} static requestPermission(){ N.permission = 'granted'; return Promise.resolve('granted'); } } N.permission = perm; window.Notification = N;
  const fakeSub = (opts) => ({ endpoint: 'https://fcm.googleapis.com/fcm/send/test-phone-1', options: opts, toJSON(){ return { endpoint: this.endpoint, keys: { p256dh: 'BPfake', auth: 'authfake' } }; }, unsubscribe: async () => { window.__unsubs++; window.__sub = null; return true; } });
  const pm = { getSubscription: async () => window.__sub, subscribe: async (opts) => { window.__subs++; window.__sub = fakeSub(opts); window.__subKey = Array.from(new Uint8Array(opts.applicationServerKey)); return window.__sub; } };
  const reg = { pushManager: pm, showNotification: async () => { window.__notes++; } };
  Object.defineProperty(navigator, 'serviceWorker', { configurable: true, value: { ready: Promise.resolve(reg), getRegistration: async () => reg, addEventListener: () => {} } });
  window.PushManager = function(){};
  const rpc0 = sb.rpc; sb.rpc = async (fn, args) => { if(fn === 'sp_push_public_key') { window.__rpcs.push(fn); return { data: key, error: null }; } if(fn === 'sp_push_subscribe' || fn === 'sp_push_unsubscribe' || fn === 'sp_push_test'){ window.__rpcs.push(fn); window['__' + fn] = args; return { data: true, error: null }; } return rpc0(fn, args); };
  window.alert = (m) => { window.__alert = String(m); };
}"""
with sync_playwright() as p:
    b=p.chromium.launch(); pg=b.new_page(viewport={'width':360,'height':720}); errs=[]
    pg.on('pageerror', lambda e: errs.append(str(e)[:200]))
    def rt(r):
        u=r.request.url
        if 'supabase-2.117.2' in u: return r.fulfill(body=js, content_type='application/javascript')
        if u.startswith('http://sphere.test/img/'): return r.fulfill(path=ROOT+u[len('http://sphere.test'):], content_type='image/webp')
        if u.startswith('http://sphere.test'): return r.fulfill(body=html, content_type='text/html')
        return r.abort()
    pg.route('**/*', rt); pg.goto('http://sphere.test/'); pg.wait_for_timeout(2500); pg.add_style_tag(content='#netBanner{display:none !important}')
    pg.evaluate(mock); pg.evaluate(SETUP, [KEY, 'granted'])
    # A1 logged in + permission already granted → this phone is registered once
    pg.evaluate("() => nav('home')"); pg.wait_for_timeout(1500); pg.evaluate("() => nav('chatList')"); pg.wait_for_timeout(1200)
    sub_args = pg.evaluate("() => window.__sp_push_subscribe")
    key_ok = pg.evaluate("([k]) => { const t = k.replace(/-/g,'+').replace(/_/g,'/'); const b = atob(t + '='.repeat((4 - t.length % 4) % 4)); return JSON.stringify(Array.from(b, c => c.charCodeAt(0))) === JSON.stringify(window.__subKey); }", [KEY])
    ok('A1 with notifications allowed, the phone registers for push once (server key, endpoint + keys saved)', pg.evaluate("() => window.__subs") == 1 and key_ok and sub_args and sub_args['p_endpoint'].startswith('https://fcm.googleapis.com/') and pg.evaluate("() => PUSH_ON"), str(sub_args)[:120])
    # A2 app in the background with push on → no second notification from the tab
    pg.evaluate("() => { Object.defineProperty(document, 'hidden', { configurable: true, get: () => true }); window.__notes = 0; alertIncoming({ id: 'x1', sender_id: '22222222-2222-4222-8222-222222222222', text: 'hi' }, false); }"); pg.wait_for_timeout(500)
    ok('A2 Sphere in the background → only the phone push shows it (no double notification)', pg.evaluate("() => window.__notes") == 0)
    pg.evaluate("() => { Object.defineProperty(document, 'hidden', { configurable: true, get: () => false }); }")
    # A3 settings: status + test button
    pg.evaluate("() => nav('msgAlerts')"); pg.wait_for_timeout(800)
    card = pg.inner_text('#app'); pg.click('text=Send a test notification'); pg.wait_for_timeout(500)
    ok('A3 Settings shows "On for this phone" and "Send a test notification" works', 'On for this phone' in card and 'sp_push_test' in pg.evaluate("() => window.__rpcs") and 'Test sent' in (pg.evaluate("() => window.__alert") or ''))
    # A6 "Turn off for this phone" → removed, and it does not switch itself back on
    pg.evaluate("() => nav('msgAlerts')"); pg.wait_for_timeout(700); u0 = pg.evaluate("() => window.__unsubs")
    pg.click('text=Turn off for this phone'); pg.wait_for_timeout(800)
    again = pg.evaluate("async () => await ensurePush()")
    ok('A6 "Turn off for this phone" removes it and it stays off (no silent re-register)', pg.evaluate("() => window.__unsubs") == u0 + 1 and not pg.evaluate("() => PUSH_ON") and again is False and 'Turn on for this phone' in pg.inner_text('#app'))
    pg.click('text=Turn on for this phone'); pg.wait_for_timeout(800)
    ok('A7 "Turn on for this phone" registers it again', pg.evaluate("() => PUSH_ON"))
    # A4 logout → this phone stops getting the account's notifications
    u_before = pg.evaluate("() => window.__unsubs"); r_before = pg.evaluate("() => window.__rpcs.filter(x => x === 'sp_push_unsubscribe').length")
    pg.evaluate("async () => { try { await logout(); } catch(e) {} }"); pg.wait_for_timeout(800)
    ok('A4 logging out removes this phone from push (server + browser)', pg.evaluate("() => window.__rpcs.filter(x => x === 'sp_push_unsubscribe').length") == r_before + 1 and pg.evaluate("() => window.__unsubs") == u_before + 1 and not pg.evaluate("() => PUSH_ON"))
    ok('X1 no JavaScript errors', not errs, str(errs[:2]))
    b.close()
    # A5 permission not given → nothing registered; Allow in the prompt registers
    b=p.chromium.launch(); pg=b.new_page(viewport={'width':360,'height':720}); errs=[]
    pg.on('pageerror', lambda e: errs.append(str(e)[:200])); pg.route('**/*', rt); pg.goto('http://sphere.test/'); pg.wait_for_timeout(2500); pg.add_style_tag(content='#netBanner{display:none !important}')
    pg.evaluate(mock); pg.evaluate(SETUP, [KEY, 'default']); pg.evaluate("() => nav('home')"); pg.wait_for_timeout(2400)
    before = pg.evaluate("() => window.__subs"); pg.click('#askNotif .btn-primary'); pg.wait_for_timeout(1200)
    ok('A5 nothing is registered until the person taps Allow; then the phone registers', before == 0 and pg.evaluate("() => window.__subs") == 1 and pg.evaluate("() => PUSH_ON"))
    ok('X2 no JavaScript errors', not errs, str(errs[:2]))
    # A8 if the server key cannot be fetched, the reason is reported (so it can be fixed without screenshots)
    pg.evaluate("() => { window.__sub = null; PUSH_ON = false; const r = sb.rpc; sb.rpc = async (fn, a) => fn === 'sp_push_public_key' ? { data: null, error: null } : r(fn, a); sb.functions.invoke = async () => ({ data: null, error: { message: 'down' } }); window.__q.length = 0; }")
    res = pg.evaluate("async () => await ensurePush()"); pg.wait_for_timeout(300)
    rep = pg.evaluate("() => window.__q.filter(q => q.table === 'sp_client_errors' && q.op === 'insert').map(q => q.payload.message)")
    ok('A8 a failed registration is reported with the reason (no endpoint / keys / tokens in it)', res is False and rep == ['Push: no server key'], str(rep))
    b.close()
for r in R: print(f'{r[0]:5} {r[1]} {("— " + r[2]) if r[2] else ""}'[:230])
print('TOTAL', sum(1 for r in R if r[0]=='PASS'), '/', len(R))
sys.exit(0 if all(r[0]=='PASS' for r in R) else 1)
