# v2.22.14: expired jobs are not shown in "Recent projects" on the client Home
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
    pg.evaluate("""() => {
      currentUser.phone = '+919812345678'; currentUser.role = 'client'; currentUser.baseRole = 'client';   // app uses lower-case roles
      const mk = (id, title, status, deadline, extra) => Object.assign({ id, title, category: 'Reels', status, deadline, budget: 500, created_at: '2026-10-01T10:00:00Z', client_id: 'me-111' }, extra || {});
      window.__jobs = [mk('j1', 'Gaming Edits', 'open', '2026-10-07'), mk('j2', 'Old Cinematic', 'open', '2026-09-30'),
                       mk('j3', 'Wedding Teaser', 'open', '2099-01-01'), mk('j4', 'Done Vlog', 'approved', '2026-09-01', { assigned_editor: 'ed-9', locked_amount: 800 })];
      const f0 = sb.from; sb.from = (t) => t === 'sp_jobs' ? { select(){ return this; }, eq(){ return this; }, order(){ return Promise.resolve({ data: window.__jobs, error: null }); } } : f0(t);
      document.getElementById('app').innerHTML = '<div class="screen" id="clientDash"></div>';
    }""")
    pg.evaluate("async () => { CLIENT_DASH_CACHE = { uid: null, html: '' }; const el = document.getElementById('clientDash'); await renderClientDashboard(); }"); pg.wait_for_timeout(800)
    txt = pg.inner_text('#app'); rec = txt.split('Recent projects')[1] if 'Recent projects' in txt else ''
    ok('H0 the Home dashboard really rendered (guards against an empty screen passing H1)', 'Recent projects' in txt and len(rec) > 20)
    ok('H1 expired jobs are not in Recent projects on Home', 'Gaming Edits' not in rec and 'Old Cinematic' not in rec and 'Expired' not in rec, rec[:160].replace('\n', ' | '))
    ok('H2 other projects still show (open and completed)', 'Wedding Teaser' in rec and 'Done Vlog' in rec)
    ok('X1 no JavaScript errors', not errs, str(errs[:2]))
    b.close()
for r in R: print(f'{r[0]:5} {r[1]} {("— " + r[2]) if r[2] else ""}'[:230])
print('TOTAL', sum(1 for r in R if r[0]=='PASS'), '/', len(R))
sys.exit(0 if all(r[0]=='PASS' for r in R) else 1)
