# v2.22.40: WhatsApp phone verification gate + "Verify on WhatsApp" screen (user sends the code; free)
import os, sys
from playwright.sync_api import sync_playwright
HERE=os.path.dirname(os.path.abspath(__file__)); ROOT=os.environ.get('SPHERE_ROOT', os.path.abspath(os.path.join(HERE, '..', '..')))
html=open(ROOT+'/index.html.html',encoding='utf-8').read(); js=open(ROOT+'/vendor/supabase-2.117.2.js',encoding='utf-8').read(); mock=open(os.path.join(HERE,'fixtures','chat_mock.js')).read()
R=[]; ok=lambda n,c,d='': R.append(('PASS' if c else 'FAIL', n, d))
SETUP = """(cfg) => { currentUser.role = cfg.role; currentUser.baseRole = cfg.role; currentUser.phone = '+919812345678'; window.__rpc = []; window.__opened = []; window.__upd = [];
  window.__st = { verified: false, phone: '9812345678', required: !!cfg.required }; window.__startErr = null;
  SETTINGS.wa_verify_required = cfg.required ? '1' : '0'; SETTINGS.wa_verify_number = cfg.number || '';
  window.open = (u) => { window.__opened.push(u); return null; };
  const real = sb.rpc.bind(sb);
  sb.rpc = async (fn, a) => { window.__rpc.push([fn, a]);
    if(fn === 'sp_phone_verify_status') return { data: Object.assign({}, window.__st), error: null };
    if(fn === 'sp_phone_verify_start') return window.__startErr ? { data: null, error: { message: window.__startErr } } : { data: { code: 'SPH-123456', phone: a.p_phone }, error: null };
    if(fn === 'sp_core_whoami') return { data: { role: cfg.role.toUpperCase(), suspended: false }, error: null };
    return { data: [], error: null }; };
  const realFrom = sb.from.bind(sb);
  sb.from = (t) => t === 'profiles' ? { update: (v) => ({ eq: async () => { window.__upd.push(v); return { error: null }; } }) } : realFrom(t);
  loadClientProjects = async () => ({ ok: true, stats: { total: 0, active: 0, needYou: 0, done: 0, spent: 0 }, items: [] }); isPremiumClient = async () => false; fillSponsored = () => {}; installBanner = () => ''; accountStatusBanner = () => ''; }"""
with sync_playwright() as p:
    b=p.chromium.launch(); errs=[]
    def page(cfg):
        pg=b.new_page(viewport={'width':390,'height':844})
        pg.on('pageerror', lambda e: errs.append(str(e)[:200])); pg.on('dialog', lambda d: d.accept())
        def rt(r):
            u=r.request.url
            if 'supabase-2.117.2' in u: return r.fulfill(body=js, content_type='application/javascript')
            if u.startswith('http://sphere.test/img/') or u.startswith('http://sphere.test/icon'): return r.fulfill(path=ROOT+u[len('http://sphere.test'):].split('?')[0])
            if u.startswith('http://sphere.test'): return r.fulfill(body=html, content_type='text/html')
            return r.abort()
        pg.route('**/*', rt); pg.goto('http://sphere.test/'); pg.wait_for_timeout(1800); pg.add_style_tag(content='#netBanner{display:none !important}')
        pg.evaluate(mock); pg.evaluate(SETUP, cfg); return pg
    # 1 switched OFF → nothing changes
    pg=page({'role':'client','required':False,'number':''})
    pg.evaluate("() => nav('home')"); pg.wait_for_timeout(900)
    ok('V1 switch OFF: client opens Home normally', pg.evaluate("() => currentScreenName") == 'home')
    ok('V2 switch OFF: Google button still on the first screen', (pg.evaluate("() => { SCREENS.authLanding(); return SCREENS.authLanding().includes('googleFallbackBtn'); }")))
    # 2 switched ON, unverified client
    pg=page({'role':'client','required':True,'number':'9000011111'})
    pg.evaluate("() => nav('home')"); pg.wait_for_timeout(1200)
    ok('V3 switch ON: unverified client is sent to the verify screen', pg.evaluate("() => currentScreenName") == 'verifyPhone', pg.evaluate("() => currentScreenName"))
    t=pg.evaluate("() => document.body.innerText")
    ok('V4 screen shows the text + number box with the saved number', 'Verify your mobile number' in t and pg.input_value('#vpPhone') == '9812345678')
    pg.evaluate("() => nav('jobs')"); pg.wait_for_timeout(700)
    ok('V5 other screens (Jobs) are blocked too', pg.evaluate("() => currentScreenName") == 'verifyPhone')
    pg.click('#vpBtn'); pg.wait_for_timeout(900)
    r=pg.evaluate("() => ({ rpc: window.__rpc.filter(x => x[0] === 'sp_phone_verify_start').map(x => x[1]), opened: window.__opened, upd: window.__upd, msg: document.getElementById('vpMsg').innerText, code: document.getElementById('vpCode').innerText })")
    ok('V6 button asks the server for a code for that number', r['rpc'] == [{'p_phone': '9812345678'}], str(r['rpc']))
    ok('V7 WhatsApp opens on Sphere\'s number with the code typed in', r['opened'] == ['https://wa.me/919000011111?text=SPH-123456'], str(r['opened']))
    ok('V8 same number → profile not rewritten; code also shown on screen', r['upd'] == [] and 'SPH-123456' in r['code'] and 'Waiting' in r['msg'], str(r))
    pg.evaluate("() => { window.__st.verified = true; }"); pg.wait_for_timeout(4200)
    ok('V9 after the WhatsApp message arrives the app moves on to Home by itself', pg.evaluate("() => currentScreenName") == 'home', pg.evaluate("() => currentScreenName"))
    # 3 changed number is saved first
    pg=page({'role':'client','required':True,'number':'9000011111'})
    pg.evaluate("() => nav('home')"); pg.wait_for_timeout(1100)
    pg.fill('#vpPhone','9817263540'); pg.click('#vpBtn'); pg.wait_for_timeout(900)
    r=pg.evaluate("() => ({ upd: window.__upd, rpc: window.__rpc.filter(x => x[0] === 'sp_phone_verify_start').map(x => x[1]) })")
    ok('V10 changed number is saved to the profile, then verified', r['upd'] == [{'phone': '+919817263540'}] and r['rpc'] == [{'p_phone': '9817263540'}], str(r))
    # 4 duplicate number message
    pg.evaluate("() => { window.__startErr = 'This mobile number is already registered with another Sphere account. Please log in with that account.'; }")
    pg.click('#vpBtn'); pg.wait_for_timeout(700)
    ok('V11 number used by another account → clear message', 'already registered' in pg.inner_text('#vpMsg'), pg.inner_text('#vpMsg'))
    # 5 number not set up yet
    pg=page({'role':'client','required':True,'number':''})
    pg.evaluate("() => nav('home')"); pg.wait_for_timeout(1100)
    ok('V12 Sphere number not set yet → button disabled + "being set up" text', pg.is_disabled('#vpBtn') and 'being set up' in pg.evaluate("() => document.body.innerText"))
    ok('V13 Google button is hidden on the first screen when verification is required', 'googleFallbackBtn' not in pg.evaluate("() => SCREENS.authLanding()"))
    # 6 admin + verified + editor
    pg=page({'role':'admin','required':True,'number':'9000011111'})
    pg.evaluate("() => nav('home')"); pg.wait_for_timeout(900)
    ok('V14 admin never has to verify', pg.evaluate("() => currentScreenName") != 'verifyPhone')
    pg=page({'role':'editor','required':True,'number':'9000011111'})
    pg.evaluate("() => { window.__st.verified = true; nav('home'); }"); pg.wait_for_timeout(900)
    ok('V15 an already-verified editor goes straight to Home', pg.evaluate("() => currentScreenName") == 'home')
    pg=page({'role':'editor','required':True,'number':'9000011111'})
    pg.evaluate("() => nav('home')"); pg.wait_for_timeout(1100); pg.evaluate("() => nav('support')"); pg.wait_for_timeout(600)
    ok('V16 Support stays reachable while unverified', pg.evaluate("() => currentScreenName") == 'support')
    # 7 status RPC failure never locks people out
    pg=page({'role':'client','required':True,'number':'9000011111'})
    pg.evaluate("() => { const o = sb.rpc; sb.rpc = async (fn, a) => fn === 'sp_phone_verify_status' ? { data: null, error: { message: 'down' } } : o(fn, a); nav('home'); }"); pg.wait_for_timeout(1000)
    ok('V17 if the check itself fails the user is NOT locked out', pg.evaluate("() => currentScreenName") == 'home')
    ok('X1 no JavaScript errors', not errs, str(errs[:3]))
    b.close()
for r in R: print(f'{r[0]:5} {r[1]} {("— " + r[2]) if r[2] else ""}'[:240])
print('TOTAL', sum(1 for r in R if r[0]=='PASS'), '/', len(R))
sys.exit(0 if all(r[0]=='PASS' for r in R) else 1)
