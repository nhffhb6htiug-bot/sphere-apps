# v2.22.22: the Admin Panel keeps its place (after actions and when switching tabs) and centres the open tab
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
    pg.evaluate("""() => { currentUser.role = 'admin'; currentUser.baseRole = 'admin'; currentUser.phone = '+919812345678'; ADMIN_PIN = 'tok';
      window.__overlay = 0; const so = showLoadOverlay; showLoadOverlay = () => { window.__overlay++; so(); };
      sb.rpc = async (fn) => fn === 'sp_admin_pin_status' ? { data: true, error: null } : fn === 'sp_admin_overview' ? { data: { pending: { verifications: 1, disputes: 0 } }, error: null } : { data: null, error: null };
      const tall = (n) => async () => { await new Promise(r => setTimeout(r, 300)); return '<div class="card" style="height:3000px">' + n + ' tab</div>'; };
      adminOverviewTab = tall('Overview'); adminProjectsTab = tall('Projects'); adminDisputesTab = tall('Disputes'); adminVerificationTab = tall('Verification');
      adminModerationTab = tall('Moderation'); adminUsersTab = tall('Users'); adminPaymentsTab = tall('Payments'); adminMonetizationTab = tall('Money'); adminAuditTab = tall('Audit'); }""")
    centred = "() => { const s = document.querySelector('.ad-tabs'), o = s && s.querySelector('.on'); if(!o) return null; const a = s.getBoundingClientRect(), r = o.getBoundingClientRect(); return { off: Math.round((r.left + r.width / 2) - (a.left + a.width / 2)), inside: r.left >= a.left - 1 && r.right <= a.right + 1, tab: o.innerText.split('\\n')[0] }; }"
    pg.evaluate("() => nav('admin', { tab: 'overview' })"); pg.wait_for_timeout(900)
    pg.evaluate("() => nav('admin', { tab: 'verification' })"); pg.wait_for_timeout(900)
    c = pg.evaluate(centred)
    ok('T1 the chosen tab is fully visible and centred in the tab bar (no longer pushed to the side)', c and c['inside'] and abs(c['off']) <= 30 and 'Verification' in c['tab'], str(c))
    pg.evaluate("() => window.scrollTo(0, 1500)"); pg.wait_for_timeout(200); ov0 = pg.evaluate("() => window.__overlay")
    pg.evaluate("() => nav('admin')"); pg.wait_for_timeout(900)   # what every admin action does after saving (e.g. Verify)
    y = pg.evaluate("() => window.scrollY"); c2 = pg.evaluate(centred)
    ok('T2 after an action the panel stays on the same tab at the same place (no jump to the start)', abs(y - 1500) <= 5 and 'Verification' in c2['tab'], f'scrollY={y}')
    ok('T3 no loading flash while it refreshes', pg.evaluate("() => window.__overlay") == ov0)
    pg.evaluate("() => nav('admin', { tab: 'moderation' })"); pg.wait_for_timeout(900)
    strip_top = pg.evaluate("() => Math.round(document.querySelector('.ad-tabs').getBoundingClientRect().top)"); c3 = pg.evaluate(centred)
    ok('T4 switching tab from far down keeps the tab bar on screen, with the new tab centred', 0 <= strip_top <= 760 and c3['inside'] and abs(c3['off']) <= 30 and 'Moderati' in c3['tab'], f'strip top={strip_top} {c3}')
    pg.evaluate("() => nav('home')"); pg.wait_for_timeout(600); pg.evaluate("() => window.scrollTo(0, 400)"); pg.evaluate("() => nav('admin')"); pg.wait_for_timeout(900)
    ok('T5 opening the panel from elsewhere still starts at the top', pg.evaluate("() => window.scrollY") == 0)
    pg.evaluate("() => { SCREENS.adminUser = async (d) => { await new Promise(r => setTimeout(r, 200)); return '<div class=card style=height:3000px>User ' + d.userId + '</div>'; }; nav('adminUser', { userId: 'u-1' }); }"); pg.wait_for_timeout(700)
    pg.evaluate("() => window.scrollTo(0, 1200)"); pg.evaluate("() => nav('adminUser', { userId: 'u-1' })"); pg.wait_for_timeout(700)
    y1 = pg.evaluate("() => window.scrollY")
    pg.evaluate("() => nav('adminUser', { userId: 'u-2' })"); pg.wait_for_timeout(700)
    ok('T7 a user admin page stays in place after an action (Warn / Suspend); another user opens at the top', abs(y1 - 1200) <= 5 and pg.evaluate("() => window.scrollY") == 0, f'same user y={y1}')
    pg.evaluate("""() => { document.getElementById('app').innerHTML = '<div class="screen" style="width:330px"><div class="kv"><span>Categories</span><b>Vlog Editing, Reels &amp; Shorts, Motion Graphics, Ads &amp; Commercial</b></div></div>'; }""")
    lines = pg.evaluate("""() => { const b = document.querySelector('.kv b'); const r = document.createRange(); const t = b.firstChild; const out = []; let last = -1, cur = '';
      for(let i = 0; i < t.length; i++){ r.setStart(t, i); r.setEnd(t, i + 1); const top = Math.round(r.getBoundingClientRect().top); if(top !== last && cur){ out.push(cur); cur = ''; } last = top; cur += t.data[i]; } out.push(cur); return out; }""")
    broken = [l for l in lines[:-1] if l and l[-1].isalpha() and not l.endswith(' ')]
    ok('T6 long category lists wrap between words, not in the middle of a word', not broken, str(lines))
    ok('X1 no JavaScript errors', not errs, str(errs[:2]))
    b.close()
for r in R: print(f'{r[0]:5} {r[1]} {("— " + r[2]) if r[2] else ""}'[:240])
print('TOTAL', sum(1 for r in R if r[0]=='PASS'), '/', len(R))
sys.exit(0 if all(r[0]=='PASS' for r in R) else 1)
