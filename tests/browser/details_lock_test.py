# v2.22.24: checked details are locked for the editor; ₹29 update request; admin edits details from the call
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
    pg.evaluate("""() => { window.__rpc = []; window.__pay = []; window.__upd = []; window.__open = []; window.alert = () => {};
      sb.rpc = async (fn, a) => { window.__rpc.push([fn, a]); if(fn === 'sp_admin_detail_requests') return { data: [{ id: 'rq-1', editor_id: 'ed-7', name: 'Yhiyhi', note: 'Experience is now 3 years', at: '2026-10-22T10:00:00Z' }], error: null };
        if(fn === 'sp_admin_verifications') return { data: [{ id: 'ed-9', full_name: 'New Editor', categories: [], languages: [] }], error: null }; return { data: [], error: null }; };
      payFee = async (k, a) => { window.__pay.push([k, a]); }; profileUpdate = async (v) => { window.__upd.push(v); return { error: null }; }; fetchAndSetCurrentUser = async () => currentUser;
      const f0 = sb.from; sb.from = (t) => {
        if(t === 'sp_detail_requests') return { select(){ return this; }, eq(){ return this; }, limit(){ return Promise.resolve({ data: window.__open, error: null }); } };
        if(t === 'profiles') return { select(){ return this; }, eq(){ return this; }, maybeSingle(){ return Promise.resolve({ data: { id: 'ed-7', full_name: 'Yhiyhi', experience_years: 4, price_range: '500-900', categories: ['Vlog Editing'], languages: ['Hindi'], skills: ['CapCut'], edit_device: 'mobile' }, error: null }); } };
        return f0(t); }; }""")
    # editor side
    pg.evaluate("() => { currentUser = { id: 'ed-7', name: 'Yhiyhi', role: 'editor', baseRole: 'editor', phone: '+919812345678', verified: true, detailsLocked: true, verificationStatus: 'approved', experience: 4, price: '500-900', categories: ['Vlog Editing'], languages: ['Hindi'], skills: 'CapCut', editDevice: '' }; nav('editorDetails'); }")
    pg.wait_for_timeout(700); t = pg.inner_text('#app')
    ok('L1 a verified editor sees "Checked by Sphere" and the values — no fields to change them', 'Checked by Sphere' in t and '4 yrs' in t and '500-900' in t and not pg.query_selector('#edCats') and not pg.query_selector('#edSkills'))
    pg.select_option('#lkDevice', 'pc'); pg.click('text=Save'); pg.wait_for_timeout(400)
    ok('L2 if Mobile/PC was never chosen, they can choose it once', pg.evaluate("() => window.__upd") == [{'edit_device': 'pc'}])
    pg.evaluate("() => { currentUser.editDevice = 'pc'; nav('editorDetails'); }"); pg.wait_for_timeout(500)
    pg.evaluate("() => { window.prompt = () => 'Experience is now 3 years'; }"); pg.click('#feePayBtn'); pg.wait_for_timeout(400)
    ok('L3 "Request an update (₹29)" saves what to change, then opens the ₹29 payment', ['sp_detail_request_draft', {'p_note': 'Experience is now 3 years'}] in pg.evaluate("() => window.__rpc") and pg.evaluate("() => window.__pay") == [['details_update', 'editorDetails']] and not pg.query_selector('#lkDevice'))
    pg.evaluate("() => { window.__open = [{ id: 'rq-1', status: 'open', note: 'Experience is now 3 years' }]; nav('editorDetails'); }"); pg.wait_for_timeout(700)
    ok('L4 after paying, the page shows "Update request sent" instead of the button', 'Update request sent' in pg.inner_text('#detReqBox'))
    pg.evaluate("() => { currentUser = Object.assign({}, currentUser, { verified: false, detailsLocked: false, verificationStatus: 'pending' }); nav('editorDetails'); }"); pg.wait_for_timeout(500)
    ok('L5 an editor who is not verified yet still fills the normal application', bool(pg.query_selector('#edCats')) and 'Checked by Sphere' not in pg.inner_text('#app'))
    # admin side
    pg.evaluate("() => { currentUser = { id: 'ad-1', name: 'Nitesh', role: 'admin', baseRole: 'admin', phone: '+919812345678' }; }")
    vt = pg.evaluate("async () => await adminVerificationTab()")
    ok('A1 the Verification tab lists Update requests (name, what to change, Edit details)', 'Update requests (1)' in vt and 'Experience is now 3 years' in vt and "requestId: 'rq-1'" in vt)
    ok('A2 a pending editor\u2019s card has "Edit details (from the call)" before "Verify after call"', 'Edit details (from the call)' in vt and vt.find('Edit details (from the call)') < vt.find('Verify after call'))
    pg.evaluate("() => nav('adminEditDetails', { userId: 'ed-7', requestId: 'rq-1' })"); pg.wait_for_timeout(800)
    ok('A3 the edit screen opens with the editor\u2019s current details filled in', pg.input_value('#aeExp') == '4' and pg.input_value('#aePrice') == '500-900' and pg.input_value('#aeDevice') == 'mobile')
    pg.fill('#aeExp', '2'); pg.fill('#aePrice', '300-600')
    pg.evaluate("() => { ADMIN_PIN = ''; window.__rpc = []; }"); pg.click('text=Save checked details'); pg.wait_for_timeout(300)
    no_pin = not any(c[0] == 'sp_admin_set_editor_details' for c in pg.evaluate("() => window.__rpc"))
    pg.evaluate("() => { ADMIN_PIN = 'tok'; }"); pg.click('text=Save checked details'); pg.wait_for_timeout(500)
    call = [c[1] for c in pg.evaluate("() => window.__rpc") if c[0] == 'sp_admin_set_editor_details']
    ok('A4 saving needs the Admin PIN, then sends the checked details and closes the request', no_pin and call and call[0]['p_user'] == 'ed-7' and call[0]['p_request'] == 'rq-1' and call[0]['p_details']['experience_years'] == '2' and call[0]['p_details']['price_range'] == '300-600' and call[0]['p_details']['categories'] == ['Vlog Editing'] and call[0]['p_pin'] == 'tok', str(call)[:200])
    ok('X1 no JavaScript errors', not errs, str(errs[:2]))
    b.close()
for r in R: print(f'{r[0]:5} {r[1]} {("— " + r[2]) if r[2] else ""}'[:230])
print('TOTAL', sum(1 for r in R if r[0]=='PASS'), '/', len(R))
sys.exit(0 if all(r[0]=='PASS' for r in R) else 1)
