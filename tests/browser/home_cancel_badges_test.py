# v2.22.17: Help & Support moved, cancel before paying (asked twice), minimise, Premium Client / Verified Editor pills
import os, sys, tempfile
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
    pg.evaluate("""() => { currentUser.phone = '+919812345678'; currentUser.role = 'client'; currentUser.baseRole = 'client';
      window.__calls = []; window.__answers = []; window.confirm = (q) => { window.__asked = (window.__asked || 0) + 1; return window.__answers.length ? window.__answers.shift() : false; }; window.alert = () => {};
      const mk = (id, title, status, extra) => Object.assign({ id, title, category: 'Vlog', status, deadline: '2099-01-01', budget: 600, created_at: '2026-10-20T10:00:00Z', client_id: 'me-111' }, extra || {});
      window.__jobs = [mk('j-neg', 'Knnx', 'negotiating', { assigned_editor: 'ed-1', locked_amount: 900 }), mk('j-pay', 'G fxyd', 'payment-pending', { assigned_editor: 'ed-2', locked_amount: 666 }), mk('j-work', 'Working one', 'in-progress', { assigned_editor: 'ed-3', locked_amount: 500 })];
      const f0 = sb.from; sb.from = (t) => t === 'sp_jobs' ? { select(){ return this; }, eq(){ return this; }, order(){ return Promise.resolve({ data: window.__jobs, error: null }); } } : f0(t);
      const r0 = sb.rpc; sb.rpc = async (fn, a) => { if(fn === 'sp_client_cancel_job'){ window.__calls.push(a); return { data: { ok: true }, error: null }; } return r0(fn, a); };
      localStorage.removeItem('sp_needs_min'); }""")
    # S1/S2 support
    pg.evaluate("() => nav('chatList')"); pg.wait_for_timeout(1200)
    ok('S1 the Sphere Support card is no longer in the chat list', not pg.query_selector('#app .support-card'))
    sc = pg.evaluate("() => { const d = document.createElement('div'); d.innerHTML = supportCard(); return [d.innerText, d.querySelectorAll('a[href^=\"tel:\"]').length]; }")
    ok('S2 the support card shows no direct phone numbers and no call links (WhatsApp + Report stay)', sc[1] == 0 and not any(ch.isdigit() and sc[0].count(ch) > 5 for ch in '0123456789') and '7739363798' not in sc[0] and 'WhatsApp' in sc[0] and 'Report problem' in sc[0], sc[0][:120].replace('\n', ' | '))
    # H1 home: Help & Support after the search bar
    pg.evaluate("() => { SCREEN_CACHE.clear(); nav('home'); }"); pg.wait_for_timeout(1800)
    order = pg.evaluate("() => { const s = document.querySelector('.home-search-bottom'), h = document.querySelector('.help-mini'); return !!(s && h && (s.compareDocumentPosition(h) & Node.DOCUMENT_POSITION_FOLLOWING)); }")
    ok('H1 Home has a small "Help & Support" right after the search bar', order and 'Help & Support' in pg.inner_text('.help-mini'))
    # C1 cancel only on pre-payment projects
    pg.evaluate("async () => { CLIENT_DASH_CACHE = { uid: null, html: '' }; await renderClientDashboard(); }"); pg.wait_for_timeout(600)
    btns = pg.evaluate("() => [...document.querySelectorAll('#clientDash .cl-action .cl-cancel')].length")
    needs_n = pg.evaluate("() => [...document.querySelectorAll('#clientDash .cl-action')].length")
    work_has = pg.evaluate("() => [...document.querySelectorAll('#clientDash .cl-proj')].some(c => c.innerText.includes('Working one') && c.querySelector('.cl-cancel'))")
    ok('C1 every not-yet-paid project under "Needs your action" has Cancel; work in progress never does', needs_n >= 1 and btns == needs_n and not work_has, f'needs={needs_n} buttons={btns}')
    # C2 one "No" → nothing; C3 two "Yes" → cancelled once
    pg.evaluate("() => { window.__answers = [true, false]; window.__asked = 0; }"); pg.click('#clientDash .cl-cancel >> nth=0'); pg.wait_for_timeout(300)
    ok('C2 it asks twice; answering "No" to either question cancels nothing', pg.evaluate("() => window.__asked") == 2 and pg.evaluate("() => window.__calls.length") == 0)
    pg.evaluate("() => { window.__answers = [true, true]; }"); pg.click('#clientDash .cl-cancel >> nth=0'); pg.wait_for_timeout(500)
    ok('C3 "Yes" twice → the project is cancelled on the server (once)', pg.evaluate("() => window.__calls.length") == 1 and pg.evaluate("() => window.__calls[0].p_job") in ('j-neg', 'j-pay'))
    ok('C4 opening the card is not triggered by the Cancel button', pg.evaluate("() => currentScreenName") != 'jobDetail')
    # M1 minimise
    pg.click('#clientDash .sec-min'); pg.wait_for_timeout(500)
    hidden = pg.evaluate("() => document.querySelectorAll('#clientDash .cl-action').length") == 0 and '➕' in pg.inner_text('#clientDash .sec-min')
    pg.evaluate("async () => { CLIENT_DASH_CACHE = { uid: null, html: '' }; await renderClientDashboard(); }"); pg.wait_for_timeout(500)
    ok('M1 ➖ hides "Needs your action" (➕ shows it again) and it stays hidden after reopening', hidden and pg.evaluate("() => document.querySelectorAll('#clientDash .cl-action').length") == 0)
    pg.click('#clientDash .sec-min'); pg.wait_for_timeout(500)
    ok('M2 ➕ shows the cards again', pg.evaluate("() => document.querySelectorAll('#clientDash .cl-action').length") > 0)
    # B1/B2 badges with shine
    pg.evaluate("""() => { sb.rpc = async (fn, a) => fn === 'sp_is_premium_client' ? { data: true, error: null } : { data: null, error: null }; PREMIUM_CACHE.clear();
      document.getElementById('app').innerHTML = '<div class="screen" style="padding:16px"><b id="pn">Yhiyhi' + premiumBadgeSlot('me-111') + '</b></div>' + bidCard({ a: { id: 'a1', message: 'hi' }, ed: { id: 'ed-1', name: 'Ravi', verified: true }, status: 'pending', price: 800, days: 2, rating: 0, reviews: 0, done: 0 }, { price: 800, days: 2, rating: 0 }, true, 1); }""")
    pg.wait_for_timeout(700)
    prem = pg.evaluate("() => { const e = document.querySelector('#pn .sp-pill.prem'); return e ? [e.innerText, getComputedStyle(e, '::after').animationName] : null; }")
    ver = pg.evaluate("() => { const e = document.querySelector('.sp-pill.ver'); return e ? [e.innerText, getComputedStyle(e, '::after').animationName] : null; }")
    pg.screenshot(path=os.path.join(tempfile.mkdtemp(prefix='sphere_2217_'), 'badges.png'), clip={'x':0,'y':0,'width':360,'height':200})
    ok('B1 a Premium client shows a blue "💎 Premium Client" pill with a moving shine', prem and 'Premium Client' in prem[0] and prem[1] == 'spShine', str(prem))
    ok('B2 a verified editor shows a "✔ Verified Editor" pill with the same shine', ver and 'Verified Editor' in ver[0] and ver[1] == 'spShine', str(ver))
    ok('X1 no JavaScript errors', not errs, str(errs[:2]))
    b.close()
for r in R: print(f'{r[0]:5} {r[1]} {("— " + r[2]) if r[2] else ""}'[:230])
print('TOTAL', sum(1 for r in R if r[0]=='PASS'), '/', len(R))
sys.exit(0 if all(r[0]=='PASS' for r in R) else 1)
