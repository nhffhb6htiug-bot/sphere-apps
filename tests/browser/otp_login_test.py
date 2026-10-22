# v2.22.21: phone OTP login (switch off → old login; switch on → WhatsApp OTP, SMS on request, new user gives name)
import os, sys
from playwright.sync_api import sync_playwright
HERE=os.path.dirname(os.path.abspath(__file__)); ROOT=os.environ.get('SPHERE_ROOT', os.path.abspath(os.path.join(HERE, '..', '..')))
html=open(ROOT+'/index.html.html',encoding='utf-8').read(); js=open(ROOT+'/vendor/supabase-2.117.2.js',encoding='utf-8').read()
R=[]; ok=lambda n,c,d='': R.append(('PASS' if c else 'FAIL', n, d))
MOCK = """() => { window.__rpc = []; window.__otp = []; window.__verify = []; window.__saved = null; window.__alerts = []; window.alert = (m) => window.__alerts.push(String(m));
  sb.rpc = async (fn, a) => { window.__rpc.push([fn, a]); return { data: true, error: null }; };
  sb.auth.signInWithOtp = async (a) => { window.__otp.push(a); return { data: {}, error: null }; };
  sb.auth.verifyOtp = async (a) => { window.__verify.push(a); return a.token === '123456' ? { data: { session: {} }, error: null } : { data: null, error: { message: 'Token has expired or is invalid' } }; };
  sb.auth.getUser = async () => ({ data: { user: { id: 'new-1', phone: '919812345678', email: null, user_metadata: {} } } });
  fetchAndSetCurrentUser = async () => null;
  saveOwnProfile = async (row) => { window.__saved = row; return { error: null }; }; }"""
def page(p, flag):
    b=p.chromium.launch(); pg=b.new_page(viewport={'width':360,'height':760}); errs=[]
    pg.on('pageerror', lambda e: errs.append(str(e)[:200]))
    def rt(r):
        u=r.request.url
        if 'supabase-2.117.2' in u: return r.fulfill(body=js, content_type='application/javascript')
        if u.startswith('http://sphere.test/img/'): return r.fulfill(path=ROOT+u[len('http://sphere.test'):].split('?')[0], content_type='image/webp')
        if u.startswith('http://sphere.test'): return r.fulfill(body=html, content_type='text/html')
        return r.abort()
    pg.route('**/*', rt); pg.goto('http://sphere.test/'); pg.wait_for_timeout(2000); pg.add_style_tag(content='#netBanner{display:none !important}')
    pg.evaluate(MOCK); pg.evaluate(f"() => {{ SETTINGS.otp_login = {flag}; nav('authLanding'); }}"); pg.wait_for_timeout(600)
    return b, pg, errs
with sync_playwright() as p:
    b, pg, errs = page(p, 0); t = pg.inner_text('#app')
    ok('O1 switch OFF: today\u2019s login stays (Log In / Sign Up), no OTP screen', 'Log In' in t and 'Sign Up' in t and not pg.query_selector('#otpPhone'))
    ok('O2 the app starts without errors', not errs, str(errs[:2])); b.close()
    b, pg, errs = page(p, 1); t = pg.inner_text('#app')
    ok('N1 switch ON: only "mobile number → OTP" (no Google / email)', bool(pg.query_selector('#otpPhone')) and 'Log In' not in t and 'Continue with Google' not in t)
    pg.fill('#otpPhone', '12345'); pg.click('#otpSendBtn'); pg.wait_for_timeout(200)
    ok('N2 a wrong number is refused before anything is sent', any('10-digit' in a for a in pg.evaluate("() => window.__alerts")) and pg.evaluate("() => window.__otp.length") == 0)
    pg.fill('#otpPhone', '9812345678'); pg.click('#otpSendBtn'); pg.wait_for_timeout(400)
    rpc = pg.evaluate("() => window.__rpc"); otp = pg.evaluate("() => window.__otp")
    ok('N3 "Get OTP on WhatsApp" asks for WhatsApp and sends the OTP to +91…', rpc[-1] == ['sp_otp_prefer', {'p_phone': '9812345678', 'p_channel': 'whatsapp'}] and otp[-1] == {'phone': '+919812345678'} and bool(pg.query_selector('#otpCode')))
    ok('N4 "Send by SMS" appears only after 30 seconds', 'Send by SMS' not in pg.inner_text('#otpResend') and 'ask again in' in pg.inner_text('#otpResend'))
    pg.evaluate("() => { clearInterval(OTP.timer); OTP.wait = 0; document.getElementById('otpResend').innerHTML = otpResendHtml(); }")
    pg.click('#otpResend >> text=Send by SMS'); pg.wait_for_timeout(400)
    ok('N5 "Send by SMS" asks the server for SMS and sends a new OTP', pg.evaluate("() => window.__rpc").pop() == ['sp_otp_prefer', {'p_phone': '9812345678', 'p_channel': 'sms'}] and pg.evaluate("() => window.__otp.length") == 2)
    pg.fill('#otpCode', '111111'); pg.wait_for_timeout(400)
    ok('N6 a wrong code shows a clear message and stays on the code screen', any('Wrong or expired code' in a for a in pg.evaluate("() => window.__alerts")) and bool(pg.query_selector('#otpCode')))
    pg.fill('#otpCode', '123456'); pg.wait_for_timeout(900)
    ok('N7 the right code logs in; a new person goes to "How do you want to use Sphere?"', pg.evaluate("() => currentScreenName") == 'chooseRole' and pg.evaluate("() => window.__verify.pop()") == {'phone': '+919812345678', 'token': '123456', 'type': 'sms'})
    t2 = pg.inner_text('#app')
    ok('N8 the new person gives a name; the number is not asked again (already verified)', bool(pg.query_selector('#grName')) and not pg.query_selector('#grPhone') and '9812345678' in t2)
    pg.click('#grEditor'); pg.fill('#grName', 'Aman Kumar'); pg.click('text=Continue'); pg.wait_for_timeout(500)
    ok('N9 the profile is saved with the OTP-verified number, the name and the chosen role (no email)', pg.evaluate("() => window.__saved") == {'id': 'new-1', 'role': 'EDITOR', 'full_name': 'Aman Kumar', 'email': None, 'phone': '+919812345678'}, str(pg.evaluate("() => window.__saved")))
    ok('X1 no JavaScript errors', not errs, str(errs[:2])); b.close()
for r in R: print(f'{r[0]:5} {r[1]} {("— " + r[2]) if r[2] else ""}'[:230])
print('TOTAL', sum(1 for r in R if r[0]=='PASS'), '/', len(R))
sys.exit(0 if all(r[0]=='PASS' for r in R) else 1)
