# v2.22.11: admin verification tab — who verified / rejected, private note, unverify
import os, sys, tempfile
from playwright.sync_api import sync_playwright
HERE=os.path.dirname(os.path.abspath(__file__)); ROOT=os.environ.get('SPHERE_ROOT', os.path.abspath(os.path.join(HERE, '..', '..')))
html=open(ROOT+'/index.html.html',encoding='utf-8').read(); js=open(ROOT+'/vendor/supabase-2.117.2.js',encoding='utf-8').read(); mock=open(os.path.join(HERE,'fixtures','chat_mock.js')).read()
R=[]; ok=lambda n,c,d='': R.append(('PASS' if c else 'FAIL', n, d))
SETUP = """(broken) => {
  currentUser = { id: 'admin-1', name: 'Nitesh', role: 'ADMIN', baseRole: 'ADMIN', phone: '+919812345678' };
  window.__calls = []; window.__alerts = []; window.__navs = [];
  window.alert = (m) => window.__alerts.push(String(m)); window.confirm = () => true;
  const realNav = nav; nav = (s, d) => { window.__navs.push([s, d]); return Promise.resolve(); };
  const verified = [{ id: 'ed-1', name: 'Editor <img src=x onerror="window.__xss=1">One', is_verified: true, verified_at: '2026-10-12T11:40:00Z', verified_by_name: 'Nitesh',
    note: 'Good <b>colour</b> work', note_by: 'Harshit', note_at: '2026-10-15T09:00:00Z',
    history: [{ at: '2026-10-12T11:40:00Z', by: 'Nitesh', decision: 'approved', reason: null }, { at: '2026-10-08T10:00:00Z', by: 'Harshit', decision: 'rejected', reason: 'Low quality sample' }] }];
  const pendingRev = [{ id: 'ed-2', name: 'Editor Two', history: [{ at: '2026-10-18T08:00:00Z', by: 'Harshit', decision: 'rejected', reason: 'Sample video missing' }] }];
  sb.rpc = async (fn, args) => {
    window.__calls.push([fn, JSON.stringify(args || {})]);
    if(fn === 'sp_admin_verifications') return { data: [{ id: 'ed-2', name: 'Editor Two', status: 'pending', fee_status: 'paid', works: 0, categories: ['Reels'] }], error: null };
    if(fn === 'sp_admin_editor_review'){ if(broken) return { data: null, error: { message: 'Could not find the function public.sp_admin_editor_review' } }; return { data: args && args.p_ids ? pendingRev : verified, error: null }; }
    return { data: null, error: null };
  };
}"""
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
    pg.evaluate(mock); pg.evaluate(SETUP, False)
    pg.evaluate("async () => { document.getElementById('app').innerHTML = '<div class=\"screen\">' + await adminVerificationTab() + '</div>'; }"); pg.wait_for_timeout(300)
    txt = pg.inner_text('#app')
    ok('V1 "Verified editors" lists each verified editor with who verified and when', 'Verified editors (1)' in txt and 'Verified by Nitesh' in txt, txt[txt.find('Verified editors'):][:120].replace('\n', ' | '))
    vc = pg.inner_text('#vcard_ed-1')
    ok('V2 every decision is shown: admin name, time, reason (newest first)', vc.find('Approved by Nitesh') != -1 and vc.find('Rejected by Harshit') > vc.find('Approved by Nitesh') and 'Low quality sample' in vc, vc[:160].replace('\n', ' | '))
    ok('V3 pending requests also show the last decision', 'Rejected by Harshit' in txt.split('Verified editors')[0] and 'Sample video missing' in txt.split('Verified editors')[0])
    ok('V4 note shows who wrote it last; names and notes are shown as text (no HTML runs)', 'Last edited by Harshit' in vc and pg.evaluate("() => !window.__xss && !document.querySelector('#vcard_ed-1 img, #vcard_ed-1 textarea b')") and pg.input_value('#enote_ed-1') == 'Good <b>colour</b> work')
    pg.screenshot(path=os.path.join(tempfile.mkdtemp(prefix='sphere_2211_'), 'admin_verified.png'), full_page=True)
    # note: needs the Admin PIN; then saves the trimmed text
    pg.evaluate("() => { ADMIN_PIN = ''; }"); pg.fill('#enote_ed-1', '  Fast delivery, clean cuts  '); pg.click('#vcard_ed-1 >> text=Save note'); pg.wait_for_timeout(200)
    no_pin = pg.evaluate("() => window.__calls.filter(c => c[0] === 'sp_admin_set_editor_note').length")
    pg.evaluate("() => { ADMIN_PIN = 'pin-token'; }"); pg.click('#vcard_ed-1 >> text=Save note'); pg.wait_for_timeout(300)
    saved = pg.evaluate("() => window.__calls.filter(c => c[0] === 'sp_admin_set_editor_note').map(c => JSON.parse(c[1]))")
    ok('N1 saving a note without the Admin PIN is stopped', no_pin == 0 and any('Admin PIN' in a for a in pg.evaluate("() => window.__alerts")))
    ok('N2 with the PIN the note is saved (trimmed) for that editor', len(saved) == 1 and saved[0] == {'p_editor': 'ed-1', 'p_note': 'Fast delivery, clean cuts', 'p_pin': 'pin-token'} and 'Saved' in pg.inner_text('#enoteInfo_ed-1'), str(saved))
    # unverify: needs a real reason, then calls the existing server function and returns to the Verification tab
    pg.click('#vcard_ed-1 >> text=Unverify'); vis = pg.evaluate("() => !document.getElementById('unvBox_ed-1').hidden")
    pg.fill('#unvR_ed-1', 'bad'); pg.click('#unvBox_ed-1 >> text=Remove verified badge'); pg.wait_for_timeout(200)
    short = pg.evaluate("() => window.__calls.filter(c => c[0] === 'sp_unverify_editor').length")
    pg.fill('#unvR_ed-1', 'Missed 3 deadlines in a row'); pg.click('#unvBox_ed-1 >> text=Remove verified badge'); pg.wait_for_timeout(300)
    un = pg.evaluate("() => window.__calls.filter(c => c[0] === 'sp_unverify_editor').map(c => JSON.parse(c[1]))")
    back = pg.evaluate("() => window.__navs.slice(-1)[0]")
    ok('U1 Unverify opens a reason box; a too-short reason is refused', vis and short == 0)
    ok('U2 with a reason + PIN it removes the badge and returns to the Verification tab', un == [{'p_editor': 'ed-1', 'p_reason': 'Missed 3 deadlines in a row', 'p_pin': 'pin-token'}] and back == ['admin', {'tab': 'verification'}], f'{un} back={back}')
    # database not updated yet → clear message, pending list still works
    pg.evaluate(SETUP, True); pg.evaluate("async () => { document.getElementById('app').innerHTML = '<div class=\"screen\">' + await adminVerificationTab() + '</div>'; }"); pg.wait_for_timeout(300)
    t2 = pg.inner_text('#app')
    ok('D1 if the database update is missing, the tab still works and says so', 'Editor Two' in t2 and 'latest database update (036)' in t2)
    ok('X1 no JavaScript errors', not errs, str(errs[:2]))
    b.close()
for r in R: print(f'{r[0]:5} {r[1]} {("— " + r[2]) if r[2] else ""}'[:230])
print('TOTAL', sum(1 for r in R if r[0]=='PASS'), '/', len(R))
sys.exit(0 if all(r[0]=='PASS' for r in R) else 1)
