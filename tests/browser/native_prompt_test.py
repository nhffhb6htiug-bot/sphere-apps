# v2.22.18: the phone's own permission prompt on the first tap (once), iPhone tip, real Sphere notification icons
import os, sys
from PIL import Image
from playwright.sync_api import sync_playwright
HERE=os.path.dirname(os.path.abspath(__file__)); ROOT=os.environ.get('SPHERE_ROOT', os.path.abspath(os.path.join(HERE, '..', '..')))
html=open(ROOT+'/index.html.html',encoding='utf-8').read(); js=open(ROOT+'/vendor/supabase-2.117.2.js',encoding='utf-8').read(); mock=open(os.path.join(HERE,'fixtures','chat_mock.js')).read()
R=[]; ok=lambda n,c,d='': R.append(('PASS' if c else 'FAIL', n, d))
SETUP = """(perm) => { currentUser.phone = '+919812345678'; window.__reqs = 0; window.__ens = 0;
  class N { static requestPermission(){ window.__reqs++; N.permission = 'granted'; return Promise.resolve('granted'); } } N.permission = perm; window.Notification = N;
  ensurePush = async () => { window.__ens++; return true; }; }"""
def page(p, ua=None):
    b=p.chromium.launch(); ctx=b.new_context(viewport={'width':360,'height':720}, **({'user_agent': ua} if ua else {})); pg=ctx.new_page(); errs=[]
    pg.on('pageerror', lambda e: errs.append(str(e)[:200]))
    def rt(r):
        u=r.request.url
        if 'supabase-2.117.2' in u: return r.fulfill(body=js, content_type='application/javascript')
        if u.startswith('http://sphere.test/img/'): return r.fulfill(path=ROOT+u[len('http://sphere.test'):], content_type='image/webp')
        if u.startswith('http://sphere.test'): return r.fulfill(body=html, content_type='text/html')
        return r.abort()
    pg.route('**/*', rt); pg.goto('http://sphere.test/'); pg.wait_for_timeout(2500); pg.add_style_tag(content='#netBanner{display:none !important}')
    return b, pg, errs
with sync_playwright() as p:
    b, pg, errs = page(p); pg.evaluate(mock); pg.evaluate(SETUP, 'default')
    pg.evaluate("() => nav('home')"); pg.wait_for_timeout(1500)
    before = pg.evaluate("() => window.__reqs")
    pg.mouse.click(180, 300); pg.wait_for_timeout(400)
    ok('N1 nothing is asked before the first tap; the first tap opens the phone own prompt (once)', before == 0 and pg.evaluate("() => window.__reqs") == 1 and not pg.query_selector('#askNotif'))
    ok('N2 "Allow" registers this phone for notifications', pg.evaluate("() => window.__ens") >= 1)
    pg.evaluate("() => { Notification.permission = 'default'; NATIVE_ARMED = false; nav('chatList'); }"); pg.wait_for_timeout(900); pg.mouse.click(180, 300); pg.wait_for_timeout(300)
    ok('N3 it is not asked again later (once per person on this phone)', pg.evaluate("() => window.__reqs") == 1)
    ok('X1 no JavaScript errors', not errs, str(errs[:2])); b.close()
    for perm in ('granted', 'denied'):
        b, pg, errs = page(p); pg.evaluate(mock); pg.evaluate(SETUP, perm); pg.evaluate("() => nav('home')"); pg.wait_for_timeout(1200); pg.mouse.click(180, 300); pg.wait_for_timeout(300)
        ok(f'N4 already {perm} → never asked', pg.evaluate("() => window.__reqs") == 0); b.close()
    b, pg, errs = page(p, 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1')
    pg.evaluate(mock); pg.evaluate(SETUP, 'default'); pg.evaluate("() => nav('home')"); pg.wait_for_timeout(1200); pg.mouse.click(180, 300); pg.wait_for_timeout(300)
    tip = pg.evaluate("() => (document.getElementById('iosTip') || {}).innerText || ''")
    ok('N5 iPhone in Safari: no prompt (Apple allows it only for the Home Screen app) — a one-time "Add to Home Screen" tip instead', pg.evaluate("() => window.__reqs") == 0 and 'Add to Home Screen' in tip, tip[:80])
    b.close()
sw = open(ROOT + '/sw.js', encoding='utf-8').read()
ok('I1 notifications use the real Sphere icon and the white status-bar badge (app + service worker)', "icon: '/notif-icon.png', badge: '/notif-badge.png'" in sw and "icon: '/notif-icon.png', badge: '/notif-badge.png'" in html and "badge: '/favicon.png'" not in sw)
bd = Image.open(ROOT + '/notif-badge.png').convert('RGBA'); ic = Image.open(ROOT + '/notif-icon.png').convert('RGBA')
white_only = all(px[:3] == (255, 255, 255) for px in bd.getdata() if px[3] > 200)
ok('I2 the badge is a white Sphere mark on a transparent background (no box); the icon has no white box either', bd.size == (96, 96) and bd.getpixel((0, 0))[3] == 0 and white_only and 0.2 < sum(1 for px in bd.getdata() if px[3] > 128) / (96 * 96) < 0.7 and ic.getpixel((0, 0))[3] == 0)
for r in R: print(f'{r[0]:5} {r[1]} {("— " + r[2]) if r[2] else ""}'[:230])
print('TOTAL', sum(1 for r in R if r[0]=='PASS'), '/', len(R))
sys.exit(0 if all(r[0]=='PASS' for r in R) else 1)
