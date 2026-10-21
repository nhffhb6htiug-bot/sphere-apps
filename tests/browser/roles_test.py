# v2.22.16: one role per account — no self switching; admin keeps their editor view and can change a user's role
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
    # an editor who had picked "client mode" before is now always an editor
    r = pg.evaluate("() => { setMode('ed-1', 'client'); return toAppUser({ id: 'ed-1', role: 'EDITOR', full_name: 'Ed' }).role; }")
    ok('M1 an editor is always an editor (an old "client mode" is ignored)', r == 'editor', r)
    r2 = pg.evaluate("() => { setMode('ad-1', 'editor'); return toAppUser({ id: 'ad-1', role: 'ADMIN', full_name: 'Ad' }).role; }")
    ok('M2 the admin can still look at Sphere as an editor', r2 == 'editor', r2)
    ed = pg.evaluate("() => modeSwitchCard({ baseRole: 'editor', role: 'editor' }) + '|' + modeSwitchCard({ baseRole: 'client', role: 'client' }) + '|' + modeChip({ baseRole: 'editor', role: 'editor' })")
    ok('M3 editors and clients see no Switch / Become an Editor in Settings', ed == '||', ed[:80])
    ad = pg.evaluate("() => modeSwitchCard({ baseRole: 'admin', role: 'client' })")
    ok('M4 the admin still has the switch', 'Switch to Editor' in ad)
    # admin panel: Make Client / Make Editor with PIN
    pg.evaluate("""() => { window.__calls = []; window.__alerts = []; window.confirm = () => true; window.alert = (m) => window.__alerts.push(String(m));
      const navs = []; window.__navs = navs; nav = (s, d) => { navs.push([s, d]); return Promise.resolve(); };
      sb.rpc = async (fn, a) => { window.__calls.push([fn, a]); return { data: { role: a && a.p_role, changed: true }, error: null }; }; }""")
    pg.evaluate("() => { ADMIN_PIN = ''; adminChangeRole('u-5', 'CLIENT'); }"); pg.wait_for_timeout(200)
    no_pin = len(pg.evaluate("() => window.__calls.filter(c => c[0] === 'sp_admin_set_role')"))
    pg.evaluate("async () => { ADMIN_PIN = 'tok'; await adminChangeRole('u-5', 'CLIENT'); }"); pg.wait_for_timeout(200)
    calls = pg.evaluate("() => window.__calls.filter(c => c[0] === 'sp_admin_set_role').map(c => c[1])")
    ok('A1 "Make Client" needs the Admin PIN, then calls the server switch and reopens the user', no_pin == 0 and calls == [{'p_user': 'u-5', 'p_role': 'CLIENT', 'p_pin': 'tok'}] and pg.evaluate("() => window.__navs.slice(-1)[0][0]") == 'adminUser', str(calls))
    ok('X1 no JavaScript errors', not errs, str(errs[:2]))
    b.close()
for r in R: print(f'{r[0]:5} {r[1]} {("— " + r[2]) if r[2] else ""}'[:230])
print('TOTAL', sum(1 for r in R if r[0]=='PASS'), '/', len(R))
sys.exit(0 if all(r[0]=='PASS' for r in R) else 1)
