# v2.22.15: every editor can bid; the client sees Verified / Not verified on each bid
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
    cards = pg.evaluate("""() => {
      const mk = (id, name, verified) => ({ a: { id: 'a-' + id, message: 'I can do it' }, ed: { id, name, verified }, status: 'pending', price: 800, days: 2, rating: 0, reviews: 0, done: 0 });
      const best = { price: 800, days: 2, rating: 0 };
      return [bidCard(mk('e1', 'Verified Ravi', true), best, true, 2), bidCard(mk('e2', 'New Aman', false), best, true, 2)];
    }""")
    pg.evaluate("(h) => { document.getElementById('app').innerHTML = '<div class=\"screen\">' + h.join('') + '</div>'; }", cards); pg.wait_for_timeout(200)
    t = pg.inner_text('#app').replace('\n', ' | ')
    ok('V1 the client sees "✔ Verified" on a verified editor\'s bid', 'Verified Ravi' in t and '✔ Verified' in t.split('New Aman')[0])
    ok('V2 the client sees "⚠️ Not verified" on an unverified editor\'s bid', '⚠️ Not verified' in t.split('New Aman')[1] and 'Not verified' not in t.split('New Aman')[0], t[:200])
    # app fallback (if the database rule cannot be read) never blocks an editor any more
    res = pg.evaluate("""async () => { sb.rpc = async () => ({ data: null, error: { message: 'offline' } });
      return await bidEligibility({ id: 'e9', verified: false, baseRole: 'editor', role: 'editor' }, 'job-1'); }""")
    ok('V3 even without the server answer the app lets every editor bid (marked unverified)', res.get('ok') is True and res.get('code') == 'unverified', str(res))
    ok('X1 no JavaScript errors', not errs, str(errs[:2]))
    b.close()
for r in R: print(f'{r[0]:5} {r[1]} {("— " + r[2]) if r[2] else ""}'[:230])
print('TOTAL', sum(1 for r in R if r[0]=='PASS'), '/', len(R))
sys.exit(0 if all(r[0]=='PASS' for r in R) else 1)
