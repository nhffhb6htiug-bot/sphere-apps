# v2.22.39: PC admin panel — full-width sidebar layout and two-pane Verification desk on a computer
import os, sys
from playwright.sync_api import sync_playwright
HERE=os.path.dirname(os.path.abspath(__file__)); ROOT=os.environ.get('SPHERE_ROOT', os.path.abspath(os.path.join(HERE, '..', '..')))
html=open(ROOT+'/index.html.html',encoding='utf-8').read(); js=open(ROOT+'/vendor/supabase-2.117.2.js',encoding='utf-8').read(); mock=open(os.path.join(HERE,'fixtures','chat_mock.js')).read()
R=[]; ok=lambda n,c,d='': R.append(('PASS' if c else 'FAIL', n, d))
SETUP = """() => { currentUser.role = 'admin'; currentUser.baseRole = 'admin'; ADMIN_PIN = 'tok'; window.__rpc = [];
  const eds = [
    { id: 'e1', name: 'Rahul Verma', phone: '+919812345678', email: 'rahul@x.in', categories: ['Wedding', 'Reels & Shorts'], languages: ['Hindi'], skills: ['Premiere Pro'], experience: 3, price: '1500-3000',
      sample: 'https://youtu.be/dQw4w9WgXcQ', portfolio: 'https://instagram.com/rahul', bio: 'Wedding films', status: 'pending', fee_status: 'submitted', fee_ref: 'UTR123', fee_at: new Date().toISOString(),
      avatar: null, proof_video: 'https://www.youtube.com/watch?v=abcdefghijk', proof_at: new Date().toISOString(), joined: new Date().toISOString(), works: 0 },
    { id: 'e2', name: 'Priya Singh', phone: '+919900011122', email: 'priya@x.in', categories: ['Vlog'], status: 'pending', fee_status: 'unpaid', works: 2, proof_video: null },
    { id: 'e3', name: 'Aman Gupta', phone: '', email: 'aman@x.in', categories: ['Gaming'], status: 'rejected', note: 'Video not his', fee_status: 'confirmed', works: 0, proof_video: 'https://drive.google.com/file/d/ABCDEF123/view' }];
  sb.rpc = async (fn, a) => { window.__rpc.push(fn);
    if(fn === 'sp_admin_pin_status') return { data: true, error: null };
    if(fn === 'sp_admin_overview') return { data: { users: 12, clients: 7, editors: 5, verified_editors: 1, active_projects: 2, completed: 4, pending_payments: 0, pending_refunds: 0, paid_volume: 0, refunded_projects: 0, suspended: 0,
      pending: { verifications: 3, disputes: 1 }, revenue: { projects: 0, extras: 0, verification: 29, total: 29 } }, error: null };
    if(fn === 'sp_admin_verifications') return { data: eds, error: null };
    if(fn === 'sp_admin_editor_review') return { data: a && a.p_ids ? [] : [{ id: 'v1', name: 'Verified Vicky', history: [] }], error: null };
    if(fn === 'sp_admin_detail_requests') return { data: [], error: null };
    if(fn === 'sp_verify_editor') return { data: 'SPH-E-0001', error: null };
    return { data: [], error: null }; };
  appErrorsCard = async () => ''; loadSystemStatus = async () => ({}); systemStatusCard = () => '';
  window.alert = (m) => { window.__alert = m; }; window.confirm = () => true; }"""
with sync_playwright() as p:
    b=p.chromium.launch(); errs=[]
    def page(w, h):
        pg=b.new_page(viewport={'width':w,'height':h})
        pg.on('pageerror', lambda e: errs.append(str(e)[:200]))
        def rt(r):
            u=r.request.url
            if 'supabase-2.117.2' in u: return r.fulfill(body=js, content_type='application/javascript')
            if u.startswith('http://sphere.test/img/') or u.startswith('http://sphere.test/icon'): return r.fulfill(path=ROOT+u[len('http://sphere.test'):].split('?')[0])
            if u.startswith('http://sphere.test'): return r.fulfill(body=html, content_type='text/html')
            return r.abort()
        pg.route('**/*', rt); pg.goto('http://sphere.test/'); pg.wait_for_timeout(2000); pg.add_style_tag(content='#netBanner{display:none !important}')
        pg.evaluate(mock); pg.evaluate(SETUP); return pg
    pg = page(1440, 900)
    pg.evaluate("() => nav('admin', { tab: 'overview' })"); pg.wait_for_timeout(900)
    st = pg.evaluate("""() => ({ pc: document.body.classList.contains('pc-admin'), side: !!document.querySelector('.pca-side'), w: Math.round(document.querySelector('.pca-main').getBoundingClientRect().width),
      tabs: document.querySelectorAll('.pca-side > button').length, badge: (document.querySelector('.pca-side button .n') || {}).innerText, mobileStrip: !!document.querySelector('.screen > .ad-tabs') })""")
    ok('P1 on a 1440px screen the Admin Panel opens full width with a sidebar', st['pc'] and st['side'] and st['w'] > 1000 and st['tabs'] >= 10 and not st['mobileStrip'], str(st))
    pg.screenshot(path='/tmp/pc_overview.png')
    pg.click("text=✔ Verification"); pg.wait_for_timeout(900)
    v = pg.evaluate("""() => ({ items: document.querySelectorAll('.pcv-item').length, on: (document.querySelector('.pcv-item.on b') || {}).innerText, head: (document.querySelector('.pcv-head h2') || {}).innerText,
       frames: [...document.querySelectorAll('#pcvDetail iframe')].map(f => f.src), num: (document.querySelector('.pcv-call .num') || {}).innerText })""")
    ok('P2 Verification desk: list on the left, first editor open on the right', v['items'] == 2 and 'Rahul' in (v['on'] or '') and 'Rahul' in (v['head'] or ''), str(v))
    ok('P3 promo video and sample play inline (YouTube embeds)', len(v['frames']) == 2 and all('youtube-nocookie.com/embed/' in f for f in v['frames']), str(v['frames']))
    ok('P4 phone number shown big for the call', v['num'] == '+91 98123 45678', str(v['num']))
    pg.screenshot(path='/tmp/pc_verify.png')
    pg.keyboard.press('j'); pg.wait_for_timeout(200)
    ok('P5 J key moves to the next editor without reloading', 'Priya' in pg.evaluate("() => document.querySelector('.pcv-head h2').innerText") and 'not sent yet' in pg.evaluate("() => document.getElementById('pcvDetail').innerText").lower())
    pg.keyboard.press('k'); pg.wait_for_timeout(200)
    ok('P6 K goes back', 'Rahul' in pg.evaluate("() => document.querySelector('.pcv-head h2').innerText"))
    pg.fill('#pcvSearch', 'priya'); pg.wait_for_timeout(200)
    ok('P7 search filters the list as you type', pg.evaluate("() => document.querySelectorAll('.pcv-item').length") == 1)
    pg.fill('#pcvSearch', ''); pg.click("text=Rejected"); pg.wait_for_timeout(800)
    r = pg.evaluate("() => ({ n: document.querySelectorAll('.pcv-item').length, h: document.querySelector('.pcv-head h2').innerText, f: [...document.querySelectorAll('#pcvDetail iframe')].map(f => f.src) })")
    ok('P8 Rejected filter + Drive promo video embeds as a preview', r['n'] == 1 and 'Aman' in r['h'] and r['f'] and 'drive.google.com/file/d/ABCDEF123/preview' in r['f'][0], str(r))
    pg.click("text=✔ Verified"); pg.wait_for_timeout(800)
    ok('P9 Verified filter lists verified editors', 'Verified Vicky' in pg.evaluate("() => document.querySelector('.pca-body').innerText"))
    pg.click("text=Waiting"); pg.wait_for_timeout(800)
    pg.click(".pcv-item:nth-child(2)"); pg.wait_for_timeout(200)
    pg.evaluate("() => { window.__confirms = 0; window.confirm = () => { window.__confirms++; return true; }; }")
    pg.click("text=✔ Verify editor"); pg.wait_for_timeout(900)
    a = pg.evaluate("() => ({ c: window.__confirms, alert: window.__alert, rpc: window.__rpc.includes('sp_verify_editor'), stillPc: !!document.querySelector('.pcv') })")
    ok('P10 Verify asks first when checklist is not ticked, then verifies and stays on the desk', a['c'] == 1 and a['rpc'] and 'verified' in (a['alert'] or '').lower() and a['stillPc'], str(a))
    pg.evaluate("() => { SCREENS.adminUser = async (d) => '<div class=\"header\"><h1>User page</h1></div><div class=\"screen\">x</div>'; nav('adminUser', { userId: 'e1' }); }"); pg.wait_for_timeout(700)
    s2 = pg.evaluate("() => ({ side: !!document.querySelector('.pca-side'), on: (document.querySelector('.pca-side button.on') || {}).innerText, t: document.querySelector('.pca-body').innerText })")
    ok('P11 sub-pages (user profile) open inside the PC layout with the right section highlighted', s2['side'] and 'Users' in (s2['on'] or '') and 'User page' in s2['t'], str(s2))
    pg.evaluate("() => nav('admin', { tab: 'overview' })"); pg.wait_for_timeout(700)
    pg.click("text=📱 Phone view"); pg.wait_for_timeout(900)
    ok('P12 "Phone view" switches back to the normal layout (with a PC view button)', not pg.evaluate("() => document.body.classList.contains('pc-admin')") and pg.evaluate("() => !!document.querySelector('.ad-tabs')") and pg.is_visible("text=🖥 PC view"))
    pg.click("text=🖥 PC view"); pg.wait_for_timeout(900)
    ok('P13 "PC view" brings the PC layout back', pg.evaluate("() => !!document.querySelector('.pca-side')"))
    pg.evaluate("() => nav('profile')"); pg.wait_for_timeout(700)
    ok('P14 leaving the Admin Panel returns to the normal phone-width app', not pg.evaluate("() => document.body.classList.contains('pc-admin')") and pg.evaluate("() => Math.round(document.body.getBoundingClientRect().width)") <= 480)
    m = page(390, 844)
    m.evaluate("() => nav('admin', { tab: 'verification' })"); m.wait_for_timeout(900)
    mm = m.evaluate("() => ({ pc: document.body.classList.contains('pc-admin'), strip: !!document.querySelector('.ad-tabs'), desk: !!document.querySelector('.pcv'), cards: document.body.innerText.includes('Verify after call') })")
    ok('P15 on a phone nothing changes (old tabs + cards)', not mm['pc'] and mm['strip'] and not mm['desk'] and mm['cards'], str(mm))
    ok('X1 no JavaScript errors', not errs, str(errs[:3]))
    b.close()
for r in R: print(f'{r[0]:5} {r[1]} {("— " + r[2]) if r[2] else ""}'[:260])
print('TOTAL', sum(1 for r in R if r[0]=='PASS'), '/', len(R))
sys.exit(0 if all(r[0]=='PASS' for r in R) else 1)
