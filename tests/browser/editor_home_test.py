# v2.22.19: editor Home has no "Your status for clients" card or status chip
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
    pg.evaluate("() => { currentUser = { id: 'ed-1', name: 'Yhiyhi', role: 'editor', baseRole: 'editor', phone: '+919812345678', verified: false, availability: 'busy' }; SCREEN_CACHE.clear(); nav('home'); }")
    pg.wait_for_timeout(2500)
    t = pg.inner_text('#app')
    ok('E1 editor Home shows the greeting and stats', 'Hi, Yhiyhi' in t and 'Completed' in t, t[:120].replace('\n', ' | '))
    ok('E2 no "Your status for clients" card and no Available / Busy / Away buttons', 'Your status for clients' not in t and not pg.query_selector('.av-pick'))
    ok('E3 no status chip next to the greeting', 'Busy' not in t.split('Completed')[0])
    ok('X1 no JavaScript errors', not errs, str(errs[:2]))
    b.close()
for r in R: print(f'{r[0]:5} {r[1]} {("— " + r[2]) if r[2] else ""}'[:230])
print('TOTAL', sum(1 for r in R if r[0]=='PASS'), '/', len(R))
sys.exit(0 if all(r[0]=='PASS' for r in R) else 1)
