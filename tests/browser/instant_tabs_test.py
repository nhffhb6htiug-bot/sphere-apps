import time
from playwright.sync_api import sync_playwright
import os, sys
ROOT=os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..')); html=open(ROOT+'/index.html.html',encoding='utf-8').read(); js=open(ROOT+'/vendor/supabase-2.117.2.js',encoding='utf-8').read()
R=[]; ok=lambda n,c,d='': R.append(('PASS' if c else 'FAIL', n, d))
with sync_playwright() as p:
    b=p.chromium.launch(); pg=b.new_page(viewport={'width':360,'height':720}); errs=[]
    pg.on('pageerror', lambda e: errs.append(str(e)[:150]))
    def rt(r):
        u=r.request.url
        if 'supabase-2.117.2' in u: return r.fulfill(body=js, content_type='application/javascript')
        if u.startswith('http://sphere.test/img/'): return r.fulfill(path=ROOT+u[len('http://sphere.test'):], content_type='image/webp')
        if u.startswith('http://sphere.test'): return r.fulfill(body=html, content_type='text/html')
        return r.abort()
    pg.route('**/*', rt); pg.goto('http://sphere.test/'); pg.wait_for_timeout(2500)
    pg.add_style_tag(content='#netBanner{display:none !important}')
    pg.evaluate("""() => { currentUser = { id: 'u-1', name: 'Hh', role: 'CLIENT', baseRole: 'CLIENT' }; window.__n = 0;
      const slow = (name) => async () => { await new Promise(r => setTimeout(r, 800)); window.__n++; return `<div class="screen"><h2 id="t">${name} #${window.__n}</h2>` + '<p>'.repeat(1) + 'Lorem ipsum dolor sit amet, video editing projects list. '.repeat(40) + '</p></div>'; };
      SCREENS.jobs = slow('jobs'); SCREENS.premiumScreen = slow('premium'); SCREENS.testSlow = slow('other'); SCREENS.home = () => '<div class="screen"><h2 id="t">home</h2></div>'; }""")
    def visit(screen):
        pg.evaluate(f"() => {{ window.__ov = false; const o = setInterval(() => {{ const el = document.getElementById('spLoadOv'); if(el && el.classList.contains('on')) window.__ov = true; }}, 20); window.__stop = () => clearInterval(o); nav('{screen}'); }}")
        t0=time.time(); pg.wait_for_timeout(60); early=pg.evaluate("() => (document.getElementById('t') || {}).textContent || ''")
        pg.wait_for_timeout(1100); late=pg.evaluate("() => (document.getElementById('t') || {}).textContent || ''"); ov=pg.evaluate("() => { window.__stop(); return window.__ov; }")
        return early, late, ov
    e1,l1,o1=visit('jobs'); ok('N1 first visit: loader shown, then content', o1 and l1.startswith('jobs'), f'early="{e1}" late="{l1}" loader={o1}')
    visit('home')
    e2,l2,o2=visit('jobs'); ok('N2 second visit: last copy shown at once (60 ms), no loader, fresh copy replaces it', e2.startswith('jobs #1') and not o2 and l2.startswith('jobs #2'), f'at 60 ms "{e2}" → later "{l2}" · loader={o2}')
    visit('home'); e3,l3,o3=visit('testSlow'); visit('home'); e4,l4,o4=visit('testSlow')
    ok('N3 screens outside the list (payments, chat threads, forms) are never served from the copy (loader each time)', o3 and o4 and not e4.startswith('other') and l4.startswith('other'), f'1st {l3} · 2nd visit at 60 ms "{e4}" loader={o4}')
    pg.evaluate("() => { currentUser = { id: 'u-2', name: 'Other', role: 'CLIENT', baseRole: 'CLIENT' }; }"); visit('home')
    e5,l5,o5=visit('jobs'); ok("N4 another user never sees the previous user's copy", not e5.startswith('jobs') and o5, f'at 60 ms "{e5}" loader={o5}')
    pg.evaluate("async () => { try { await logout(); } catch(e) {} }"); pg.wait_for_timeout(600)
    ok('N5 logout clears all copies', pg.evaluate("() => SCREEN_CACHE.size") == 0)
    # Liquid Glass look over colourful content
    pg.evaluate("""() => { currentUser = { id: 'u-1', name: 'Hh', role: 'CLIENT', baseRole: 'CLIENT' };
      SCREENS.home = () => '<div class="screen" style="padding:14px">' + ['#ff7a59','#2563eb','#10b981','#f59e0b','#8b5cf6','#ec4899'].map(c => `<div style="height:70px;margin:8px 0;border-radius:16px;background:linear-gradient(90deg,${c},#fff)"></div>`).join('') + '</div>'; nav('home'); }""")
    pg.wait_for_timeout(800); pg.evaluate("() => window.scrollTo(0, 120)"); pg.wait_for_timeout(300)
    import tempfile; pg.screenshot(path=os.path.join(tempfile.mkdtemp(), 'liquid_nav.png'), clip={'x':0,'y':560,'width':360,'height':160})
    st=pg.evaluate("() => { const c = getComputedStyle(document.getElementById('bottomNav')); return c.backdropFilter || c.webkitBackdropFilter; }")
    ok('N6 Liquid Glass style applied to the navigation bar', 'saturate' in st and 'blur' in st, st)
    ok('N99 no JavaScript errors', not errs, str(errs[:2]))
    b.close()
for r in R: print(f'{r[0]:5} {r[1]} {("— " + r[2]) if r[2] else ""}'[:220])
print('TOTAL', sum(1 for r in R if r[0]=='PASS'), '/', len(R))
sys.exit(0 if all(r[0]=='PASS' for r in R) else 1)
