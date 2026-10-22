# v2.22.20: Get Premium under the logo, minimise "No projects yet", Verified PC = PC editors, Mobile/PC in the form, ₹29 first with skip
import os, sys
from playwright.sync_api import sync_playwright
HERE=os.path.dirname(os.path.abspath(__file__)); ROOT=os.environ.get('SPHERE_ROOT', os.path.abspath(os.path.join(HERE, '..', '..')))
html=open(ROOT+'/index.html.html',encoding='utf-8').read(); js=open(ROOT+'/vendor/supabase-2.117.2.js',encoding='utf-8').read(); mock=open(os.path.join(HERE,'fixtures','chat_mock.js')).read()
R=[]; ok=lambda n,c,d='': R.append(('PASS' if c else 'FAIL', n, d))
with sync_playwright() as p:
    b=p.chromium.launch(); pg=b.new_page(viewport={'width':360,'height':760}); errs=[]
    pg.on('pageerror', lambda e: errs.append(str(e)[:200]))
    def rt(r):
        u=r.request.url
        if 'supabase-2.117.2' in u: return r.fulfill(body=js, content_type='application/javascript')
        if u.startswith('http://sphere.test/img/'): return r.fulfill(path=ROOT+u[len('http://sphere.test'):], content_type='image/webp')
        if u.startswith('http://sphere.test'): return r.fulfill(body=html, content_type='text/html')
        return r.abort()
    pg.route('**/*', rt); pg.goto('http://sphere.test/'); pg.wait_for_timeout(2500); pg.add_style_tag(content='#netBanner{display:none !important}')
    pg.evaluate(mock)
    pg.evaluate("""() => { currentUser.phone = '+919812345678'; currentUser.role = 'client'; currentUser.baseRole = 'client'; window.__prem = false; window.__jobs = [];
      const f0 = sb.from; sb.from = (t) => t === 'sp_jobs' ? { select(){ return this; }, eq(){ return this; }, order(){ return Promise.resolve({ data: window.__jobs, error: null }); } } : f0(t);
      const r0 = sb.rpc; sb.rpc = async (fn, a) => fn === 'sp_is_premium_client' ? { data: window.__prem, error: null } : r0(fn, a);
      localStorage.removeItem('sp_empty_min'); document.getElementById('app').innerHTML = '<div class="screen" id="clientDash"></div>'; }""")
    pg.evaluate("async () => { CLIENT_DASH_CACHE = { uid: null, html: '' }; PREMIUM_CACHE.clear(); await renderClientDashboard(); }"); pg.wait_for_timeout(600)
    r = pg.evaluate("() => { const b = document.getElementById('premRowBtn'), h = document.querySelector('#clientDash .cl-hello'); const br = b.getBoundingClientRect(); return { text: b.innerText, right: Math.round(br.right), above: !!(b.compareDocumentPosition(h) & Node.DOCUMENT_POSITION_FOLLOWING), inGreeting: !!h.querySelector('.prem-pill') }; }")
    ok('P1 the Premium button sits above the greeting (under the logo), fully on screen, says "Get Premium"', r['text'] == '💎 Get Premium' and r['right'] <= 360 and r['above'] and not r['inGreeting'], str(r))
    pg.evaluate("async () => { window.__prem = true; CLIENT_DASH_CACHE = { uid: null, html: '' }; PREMIUM_CACHE.clear(); await renderClientDashboard(); }"); pg.wait_for_timeout(700)
    ok('P2 a Premium client sees "💎 Premium"', pg.inner_text('#premRowBtn') == '💎 Premium')
    # E1 minimise "No projects yet"
    has_card = pg.evaluate("() => !!document.querySelector('#clientDash .cl-empty')")
    pg.click('#clientDash .sec-min'); pg.wait_for_timeout(500)
    hidden = not pg.evaluate("() => !!document.querySelector('#clientDash .cl-empty')") and '➕' in pg.inner_text('#clientDash .sec-min')
    pg.evaluate("async () => { CLIENT_DASH_CACHE = { uid: null, html: '' }; await renderClientDashboard(); }"); pg.wait_for_timeout(400)
    stays = not pg.evaluate("() => !!document.querySelector('#clientDash .cl-empty')")
    pg.click('#clientDash .sec-min'); pg.wait_for_timeout(500)
    ok('E1 "No projects yet" can be minimised with ➖ (stays hidden) and shown again with ➕', has_card and hidden and stays and pg.evaluate("() => !!document.querySelector('#clientDash .cl-empty')"))
    # V1 Verified PC = PC / Both editors only
    pg.evaluate("""() => { VERIFIED_CACHE = null; getVerifiedEditors = async () => [{ id: 'a', name: 'PC Pro', verified: true, editDevice: 'pc', categories: [] }, { id: 'b', name: 'Phone Guy', verified: true, editDevice: 'mobile', categories: [] }, { id: 'c', name: 'Both Ways', verified: true, editDevice: 'both', categories: [] }, { id: 'd', name: 'Unknown', verified: true, editDevice: '', categories: [] }]; SCREEN_CACHE.clear(); nav('verifiedEditorsScreen'); }""")
    pg.wait_for_timeout(1200); t = pg.inner_text('#app')
    ok('V1 Verified PC shows only editors who edit on a PC (PC or Both)', 'PC Pro' in t and 'Both Ways' in t and 'Phone Guy' not in t and 'Unknown' not in t, t[:160].replace('\n', ' | '))
    # F1/F2 editor form: Mobile / PC required and saved
    pg.evaluate("""() => { currentUser = { id: 'ed-1', name: 'Ed', role: 'editor', baseRole: 'editor', phone: '+919812345678', categories: [], languages: [], editDevice: '' };
      window.__upd = null; window.__alerts = []; window.alert = (m) => window.__alerts.push(String(m));
      const f1 = sb.from; sb.from = (t) => t === 'profiles' ? { update(v){ window.__upd = v; return { eq(){ return Promise.resolve({ error: null }); } }; }, select(){ return this; }, eq(){ return this; }, maybeSingle(){ return Promise.resolve({ data: null, error: null }); } } : f1(t);
      document.getElementById('app').innerHTML = SCREENS.editorDetails(); }""")
    pg.wait_for_timeout(300)
    opts = pg.evaluate("() => [...document.querySelectorAll('#edDevice option')].map(o => o.value)")
    pg.evaluate("() => { document.querySelector('.chip, [data-cat], input[type=checkbox]') ; }")
    pg.evaluate("""() => { document.querySelectorAll('#app input[type=checkbox], #app .chip').forEach((el, i) => { if(i < 2){ if(el.type === 'checkbox') el.checked = true; else el.click(); } }); }""")
    ok('F1 the application asks "Where do you edit?" — Mobile / PC / Both', opts == ['', 'mobile', 'pc', 'both'], str(opts))
    # V2 verification screen: pay ₹29 first, or skip
    pg.evaluate("() => { document.getElementById('app').innerHTML = verificationNotAppliedScreen(currentUser); }")
    t2 = pg.inner_text('#app'); btns = pg.evaluate("() => [...document.querySelectorAll('#app button')].map(b => [b.innerText, b.getAttribute('onclick')])")
    pay = [x for x in btns if 'Pay ₹29 first' in x[0]]; skip = [x for x in btns if 'Skip' in x[0]]
    ok('V2 verification starts with "Pay ₹29 first" (then the form) and a "Skip — pay later" option', pay and "payFee('verification', 'editorDetails')" in pay[0][1] and skip and "editorDetails" in skip[0][1] and t2.find('Pay the ₹29') < t2.find('Fill your editor application'), str(btns)[:200])
    ok('X1 no JavaScript errors', not errs, str(errs[:2]))
    b.close()
for r in R: print(f'{r[0]:5} {r[1]} {("— " + r[2]) if r[2] else ""}'[:230])
print('TOTAL', sum(1 for r in R if r[0]=='PASS'), '/', len(R))
sys.exit(0 if all(r[0]=='PASS' for r in R) else 1)
