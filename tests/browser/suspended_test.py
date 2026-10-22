# v2.22.23: a suspended account sees only the suspended page; the status is rechecked while the app is open
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
        if u.startswith('http://sphere.test/img/'): return r.fulfill(path=ROOT+u[len('http://sphere.test'):].split('?')[0], content_type='image/webp')
        if u.startswith('http://sphere.test'): return r.fulfill(body=html, content_type='text/html')
        return r.abort()
    pg.route('**/*', rt); pg.goto('http://sphere.test/'); pg.wait_for_timeout(2000); pg.add_style_tag(content='#netBanner{display:none !important}')
    pg.evaluate(mock)
    pg.evaluate("""() => { currentUser.phone = '+919812345678'; currentUser.role = 'client'; currentUser.baseRole = 'client'; currentUser.suspended = false; window.__susp = false;
      const r0 = sb.rpc; sb.rpc = async (fn, a) => fn === 'sp_core_whoami' ? { data: { suspended: window.__susp, role: 'CLIENT' }, error: null } : r0(fn, a); }""")
    pg.evaluate("() => nav('chatList')"); pg.wait_for_timeout(1000)
    ok('A1 a normal account uses Sphere as usual', pg.evaluate("() => currentScreenName") == 'chatList' and 'suspended' not in pg.inner_text('#app').lower())
    pg.evaluate("async () => { window.__susp = true; await refreshAccountStatus(); }"); pg.wait_for_timeout(800)
    t = pg.inner_text('#app')
    ok('S1 while the app is open, a suspension shows at once: full "Your account is suspended" page with support and Log out', pg.evaluate("() => currentScreenName") == 'suspended' and 'Your account is suspended' in t and 'WhatsApp' in t and 'Log out' in t)
    for scr in ('home', 'chatList', 'jobs', 'profile', 'premiumScreen', 'postJob'):
        pg.evaluate(f"() => nav('{scr}')"); pg.wait_for_timeout(300)
    ok('S2 every other screen leads back to the suspended page (home, chats, projects, profile, Premium, post a job)', pg.evaluate("() => currentScreenName") == 'suspended')
    pg.evaluate("() => nav('support')"); pg.wait_for_timeout(600)
    ok('S3 Help & Support can still be opened', pg.evaluate("() => currentScreenName") == 'support')
    pg.evaluate("async () => { window.__susp = false; await refreshAccountStatus(); }"); pg.wait_for_timeout(1000)
    ok('S4 after Reactivate the app goes back to Home by itself', pg.evaluate("() => currentScreenName") == 'home' and not pg.evaluate("() => currentUser.suspended"))
    ok('X1 no JavaScript errors', not errs, str(errs[:2]))
    b.close()
for r in R: print(f'{r[0]:5} {r[1]} {("— " + r[2]) if r[2] else ""}'[:230])
print('TOTAL', sum(1 for r in R if r[0]=='PASS'), '/', len(R))
sys.exit(0 if all(r[0]=='PASS' for r in R) else 1)
