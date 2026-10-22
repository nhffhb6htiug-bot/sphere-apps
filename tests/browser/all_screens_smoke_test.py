# Smoke test: open every screen as client, editor and admin (offline mocks) and report JavaScript errors / empty screens
import os, sys
from playwright.sync_api import sync_playwright
HERE=os.path.dirname(os.path.abspath(__file__)); ROOT=os.environ.get('SPHERE_ROOT', os.path.abspath(os.path.join(HERE, '..', '..')))
html=open(ROOT+'/index.html.html',encoding='utf-8').read(); js=open(ROOT+'/vendor/supabase-2.117.2.js',encoding='utf-8').read(); mock=open(os.path.join(HERE,'fixtures','chat_mock.js')).read()
SKIP = {'splash'}   # timers that navigate away by design
R=[]; ok=lambda n,c,d='': R.append(('PASS' if c else 'FAIL', n, d))
ROLES = {
  'client': "{ id: 'me-111', name: 'Test Client', role: 'client', baseRole: 'client', phone: '+919812345678', email: 'c@x.in' }",
  'editor': "{ id: 'ed-7', name: 'Test Editor', role: 'editor', baseRole: 'editor', phone: '+919812345678', email: 'e@x.in', verified: true, categories: ['Vlog Editing'], languages: ['Hindi'], skills: 'CapCut', editDevice: 'pc', verificationStatus: 'approved' }",
  'admin':  "{ id: 'ad-1', name: 'Test Admin', role: 'admin', baseRole: 'admin', phone: '+919812345678', email: 'a@x.in' }",
}
with sync_playwright() as p:
    for role, user in ROLES.items():
        b=p.chromium.launch(); pg=b.new_page(viewport={'width':360,'height':760}); errs=[]
        pg.on('pageerror', lambda e: errs.append(str(e)[:160]))
        def rt(r):
            u=r.request.url
            if 'supabase-2.117.2' in u: return r.fulfill(body=js, content_type='application/javascript')
            if u.startswith('http://sphere.test/img/'): return r.fulfill(path=ROOT+u[len('http://sphere.test'):].split('?')[0], content_type='image/webp')
            if u.startswith('http://sphere.test'): return r.fulfill(body=html, content_type='text/html')
            return r.abort()
        pg.route('**/*', rt); pg.goto('http://sphere.test/'); pg.wait_for_timeout(2000); pg.add_style_tag(content='#netBanner{display:none !important}')
        pg.evaluate(mock)
        names = pg.evaluate(f"() => {{ currentUser = {user}; ADMIN_PIN = 'tok'; window.alert = () => {{}}; window.confirm = () => false; window.prompt = () => null; return Object.keys(SCREENS); }}")
        bad = []; blank = []
        for n in names:
            if n in SKIP: continue
            before = len(errs)
            try:
                pg.evaluate(f"() => {{ try {{ nav('{n}', {{}}); }} catch(e) {{ window.__navErr = String(e); }} }}")
                pg.wait_for_timeout(450)
            except Exception as e:
                errs.append(f'{n}: {str(e)[:120]}')
            if len(errs) > before: bad.append(f"{n}: {errs[-1][:110]}")
            txt = pg.evaluate("() => (document.getElementById('app') || {}).innerText || ''")
            if len(txt.strip()) < 2: blank.append(n)
        ok(f'{role}: all {len(names) - len(SKIP)} screens open without JavaScript errors', not bad, ' ; '.join(bad[:6]))
        ok(f'{role}: no screen is left completely empty', not blank, ', '.join(blank[:12]))
        b.close()
for r in R: print(f'{r[0]:5} {r[1]} {("— " + r[2]) if r[2] else ""}'[:900])
print('TOTAL', sum(1 for r in R if r[0]=='PASS'), '/', len(R))
sys.exit(0 if all(r[0]=='PASS' for r in R) else 1)
