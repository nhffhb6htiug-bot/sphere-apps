from playwright.sync_api import sync_playwright
import tempfile as _tf, os as _os
SHOTS=_tf.mkdtemp(prefix='sphere_shots_')
import os
ROOT=os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
html=open(os.path.join(ROOT, 'index.html.html'), encoding='utf-8').read()
js=open(os.path.join(ROOT, 'vendor', 'supabase-2.117.2.js'), encoding='utf-8').read()
R=[]
def check(name, ok, detail): R.append(('PASS' if ok else 'FAIL', name, detail))
with sync_playwright() as p:
    b=p.chromium.launch(); pg=b.new_page(viewport={'width':360,'height':720}); errs=[]
    pg.on('pageerror', lambda e: errs.append(str(e)[:150]))
    def rt(r):
        u=r.request.url
        if 'supabase-2.117.2' in u: return r.fulfill(body=js, content_type='application/javascript')
        if u.startswith('http://sphere.test/img/'): return r.fulfill(path=os.path.join(ROOT, u[len('http://sphere.test/'):]), content_type='image/webp')
        if u.startswith('http://sphere.test'): return r.fulfill(body=html, content_type='text/html')
        return r.abort()
    pg.route('**/*', rt); pg.goto('http://sphere.test/'); pg.wait_for_timeout(2500)
    pg.evaluate("""() => { window.__premium = { 'aaaa': true, 'bbbb': false }; window.__calls = 0;
        sb.rpc = async (fn, args) => { if(fn === 'sp_is_premium_client'){ window.__calls++; return { data: !!window.__premium[args.p_user], error: null }; } return { data: null, error: { message: 'mock' } }; };
        currentUser = { id: 'aaaa', name: 'Hh Client', role: 'CLIENT', baseRole: 'CLIENT' }; }""")
    pg.evaluate("() => { document.getElementById('app').innerHTML = '<div class=\"screen\" style=\"padding:16px\">' + clientDashSkeleton({ id: 'aaaa', name: 'Hh Client', role: 'CLIENT' }) + '<p id=\"free\">Free: <b>Ravi</b>' + premiumBadgeSlot('bbbb') + '</p></div>'; }")
    pg.wait_for_timeout(600)
    a=pg.evaluate("() => !!document.querySelector('.cl-hello .sp-pill.prem')"); f=pg.evaluate("() => !!document.querySelector('#free .sp-pill.prem')")
    pg.add_style_tag(content='#netBanner{display:none !important}'); pg.wait_for_timeout(200)
    pg.screenshot(path=_os.path.join(SHOTS, 'premium_badge_home.png'), clip={'x':0,'y':0,'width':360,'height':140})
    check('P01 active Premium client shows 💎 (server said yes)', a, f'greeting badge={a}')
    check('P02 free client shows no badge (server said no)', not f, f'free badge={f}')
    calls1=pg.evaluate("() => window.__calls")
    pg.evaluate("() => { document.getElementById('app').innerHTML += '<p id=\"again\">' + premiumBadgeSlot('aaaa') + '</p>'; }"); pg.wait_for_timeout(500)
    calls2=pg.evaluate("() => window.__calls")
    check('P03 answer is cached (no repeated server calls within 5 min)', calls2==calls1, f'server calls {calls1} → {calls2}')
    pg.evaluate("() => { window.__premium.aaaa = false; PREMIUM_CACHE.set('aaaa', { v: true, at: Date.now() - 301000 }); document.getElementById('app').innerHTML = '<div class=\"screen\">' + clientDashSkeleton({ id: 'aaaa', name: 'Hh Client', role: 'CLIENT' }) + '</div>'; }")
    pg.wait_for_timeout(600); gone=not pg.evaluate("() => !!document.querySelector('.sp-pill.prem')")
    check('P04 expired plan: badge gone on the next check', gone, f'badge shown={not gone}')
    pg.evaluate("() => { window.__premium.bbbb = true; PREMIUM_CACHE.set('bbbb', { v: false, at: Date.now() }); document.getElementById('app').innerHTML = '<p id=\"x\">' + premiumBadgeSlot('bbbb') + '</p>'; }")
    pg.wait_for_timeout(500); cached=not pg.evaluate("() => !!document.querySelector('#x .sp-pill.prem')")
    check('P05 a value set on the page is replaced by the server answer after 5 min (cache cannot be trusted forever)', cached, 'within 5 min the cached answer is used; it is refreshed from the server after that')
    pg.evaluate("() => { PREMIUM_CACHE.set('zzzz', { v: true, at: Date.now() }); }")
    pg.evaluate("async () => { try { await logout(); } catch(e) {} }"); pg.wait_for_timeout(800)
    cleared=pg.evaluate("() => PREMIUM_CACHE.size")
    check('P06 logout clears remembered badges', cleared==0, f'cache size after logout={cleared}')
    check('P99 no JavaScript errors', not errs, str(errs[:2]))
    b.close()
for r in R: print(f'{r[0]:5} {r[1]} — {r[2]}')
print('TOTAL', sum(1 for r in R if r[0]=='PASS'), '/', len(R))
import sys; sys.exit(0 if all(r[0]=='PASS' for r in R) else 1)
