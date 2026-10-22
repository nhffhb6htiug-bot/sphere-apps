# v2.22.25: unread notification cards are readable (the green chat badge style no longer leaks into them)
import os, sys
from playwright.sync_api import sync_playwright
HERE=os.path.dirname(os.path.abspath(__file__)); ROOT=os.environ.get('SPHERE_ROOT', os.path.abspath(os.path.join(HERE, '..', '..')))
html=open(ROOT+'/index.html.html',encoding='utf-8').read(); js=open(ROOT+'/vendor/supabase-2.117.2.js',encoding='utf-8').read(); mock=open(os.path.join(HERE,'fixtures','chat_mock.js')).read()
R=[]; ok=lambda n,c,d='': R.append(('PASS' if c else 'FAIL', n, d))
def run(p, engine):
    try: b = getattr(p, engine).launch()
    except Exception as e: return f'{engine} not available'
    pg=b.new_page(viewport={'width':375,'height':800}); errs=[]
    pg.on('pageerror', lambda e: errs.append(str(e)[:200]))
    def rt(r):
        u=r.request.url
        if 'supabase-2.117.2' in u: return r.fulfill(body=js, content_type='application/javascript')
        if u.startswith('http://sphere.test/img/'): return r.fulfill(path=ROOT+u[len('http://sphere.test'):].split('?')[0], content_type='image/webp')
        if u.startswith('http://sphere.test'): return r.fulfill(body=html, content_type='text/html')
        return r.abort()
    pg.route('**/*', rt); pg.goto('http://sphere.test/'); pg.wait_for_timeout(2000); pg.add_style_tag(content='#netBanner{display:none !important}')
    pg.evaluate(mock)
    pg.evaluate("""() => { currentUser.phone = '+919812345678';
      const rows = [{ id: 1, title: 'Video Approved ✅', body: 'The client approved your video.', is_read: false, category: 'payment', created_at: '2026-10-22T16:07:00Z', job_id: 'a26ece00-0000-0000-0000-000000000000', important: true },
                    { id: 2, title: 'Payment Received 💰', body: 'The client has paid.', is_read: true, category: 'payment', created_at: '2026-10-22T09:10:00Z' }];
      const f0 = sb.from; sb.from = (t) => t === 'sp_notifications' ? { select(){ return this; }, eq(){ return this; }, or(){ return this; }, neq(){ return this; }, not(){ return this; }, in(){ return this; }, order(){ return this; }, range(){ return this; }, limit(){ return Promise.resolve({ data: rows, error: null }); }, then(r){ return Promise.resolve({ data: rows, error: null }).then(r); }, update(){ return this; } } : f0(t);
      nav('notifications'); }""")
    pg.wait_for_timeout(1500)
    st = pg.evaluate("""() => { const u = document.querySelector('.nt-item.nt-new'), r = document.querySelector('.nt-item:not(.nt-new)'); if(!u || !r) return null;
      const t = u.querySelector('.nt-main b'), cs = getComputedStyle(t), cu = getComputedStyle(u);
      return { color: cs.color, align: getComputedStyle(u.querySelector('.nt-main')).textAlign, pad: cu.paddingTop, readColor: getComputedStyle(r.querySelector('.nt-main b')).color }; }""")
    if not st: b.close(); return f'{engine}: cards not rendered'
    dark = lambda c: sum(int(x) for x in c[c.find('(')+1:c.find(')')].split(',')[:3]) < 300
    ok(f'{engine}: N1 the title of an unread notification is dark and readable (not white)', dark(st['color']), str(st))
    ok(f'{engine}: N2 its text starts on the left like the others (not centred) and keeps its normal padding', st['align'] in ('start', 'left') and st['pad'] == '12px')
    pg.evaluate("() => { document.getElementById('app').insertAdjacentHTML('beforeend', '<span class=\"unread\" id=\"badge\">3</span>'); }")
    bg = pg.evaluate("() => getComputedStyle(document.getElementById('badge')).backgroundColor")
    ok(f'{engine}: N3 the green unread badge in the chat list still looks the same', bg == 'rgb(37, 211, 102)', bg)
    ok(f'{engine}: X1 no JavaScript errors', not errs, str(errs[:2]))
    b.close(); return None
with sync_playwright() as p:
    for eng in ('chromium', 'webkit'):
        msg = run(p, eng)
        if msg: print('NOTE', msg)
for r in R: print(f'{r[0]:5} {r[1]} {("— " + r[2]) if r[2] else ""}'[:230])
print('TOTAL', sum(1 for r in R if r[0]=='PASS'), '/', len(R))
sys.exit(0 if R and all(r[0]=='PASS' for r in R) else 1)
