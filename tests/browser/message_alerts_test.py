import os, sys, json, tempfile
from playwright.sync_api import sync_playwright
HERE=os.path.dirname(os.path.abspath(__file__)) if '__file__' in dir() else '/tmp'
HERE=os.path.dirname(os.path.abspath(__file__)); ROOT=os.environ.get('SPHERE_ROOT', os.path.abspath(os.path.join(HERE, '..', '..'))); html=open(ROOT+'/index.html.html',encoding='utf-8').read(); js=open(ROOT+'/vendor/supabase-2.117.2.js',encoding='utf-8').read()
mock=open(os.path.join(HERE, 'fixtures', 'chat_mock.js')).read()
SENDER='22222222-2222-4222-8222-222222222222'
R=[]; ok=lambda n,c,d='': R.append(('PASS' if c else 'FAIL', n, d))
SETUP = """(perm) => {
  window.__notes = []; window.__reqs = 0; window.__osc = 0;
  class FakeN { constructor(t, o){ this.title = t; this.opts = o; window.__notes.push(this); } close(){} static requestPermission(){ window.__reqs++; FakeN.permission = 'granted'; return Promise.resolve('granted'); } }
  FakeN.permission = perm; window.Notification = FakeN;
  if(navigator.serviceWorker) navigator.serviceWorker.getRegistration = async () => undefined;
  getProfilesByIds = async (ids) => Object.fromEntries(ids.map(i => [i, { id: i, name: 'Yhiyhi 681' }]));
  window.__hidden = false; Object.defineProperty(document, 'hidden', { configurable: true, get: () => window.__hidden });
}"""
def new_page(p, url='http://sphere.test/'):
    b=p.chromium.launch(); ctx=b.new_context(viewport={'width':360,'height':720}, has_touch=True); pg=ctx.new_page(); errs=[]
    pg.on('pageerror', lambda e: errs.append(str(e)[:200]))
    def rt(r):
        u=r.request.url
        if 'supabase-2.117.2' in u: return r.fulfill(body=js, content_type='application/javascript')
        if u.startswith('http://sphere.test/img/'): return r.fulfill(path=ROOT+u[len('http://sphere.test'):].split('?')[0], content_type='image/webp')
        if u.startswith('http://sphere.test'): return r.fulfill(body=html, content_type='text/html')
        return r.abort()
    pg.route('**/*', rt); pg.goto(url); pg.wait_for_timeout(2500); pg.add_style_tag(content='#netBanner{display:none !important}')
    return b, ctx, pg, errs
with sync_playwright() as p:
    b, ctx, pg, errs = new_page(p)
    pg.evaluate(mock); pg.evaluate(SETUP, 'granted')
    pg.evaluate("""() => { const orig = sb.channel; window.__chans = {}; sb.channel = (n, o) => { const c = orig(n, o); window.__chans[n] = c; return c; }; msgChannel = null; listenForMessages(); }""")
    pg.mouse.click(180, 400); pg.wait_for_timeout(200)                     # a real touch unlocks sound
    pg.evaluate("() => { if(AUDIO_CTX){ const f = AUDIO_CTX.createOscillator.bind(AUDIO_CTX); AUDIO_CTX.createOscillator = () => { window.__osc++; return f(); }; } }")
    audio_ok = pg.evaluate("() => audioReady()")
    fire = lambda mid, sender=SENDER: pg.evaluate("([id, s]) => window.__chans['sphere-messages-me-111'].fire('INSERT', { new: { id, sender_id: s, receiver_id: 'me-111', text: 'Final cut ready?', created_at: new Date().toISOString(), mod_status: 'ok' } })", [mid, sender])
    state = lambda: pg.evaluate("() => ({ osc: window.__osc, notes: window.__notes.length, banner: !!document.getElementById('msgBanner'), reqs: window.__reqs })")
    # A1 reading that chat → nothing
    pg.evaluate("([s]) => { currentChatWith = s; currentChatJob = null; nav('chatThread'); }", [SENDER]); pg.wait_for_timeout(1200)
    s0 = state(); fire('a1'); pg.wait_for_timeout(500); s1 = state()
    ok('A1 message from the chat you are reading → no sound, no banner, no notification', s1['osc'] == s0['osc'] and s1['notes'] == 0 and not s1['banner'], str(s1))
    # A2 another screen, app visible → Sphere tone + banner (no system notification)
    pg.evaluate("() => nav('home')"); pg.wait_for_timeout(1500); s0 = state(); fire('a2'); pg.wait_for_timeout(700); s2 = state()
    btxt = pg.evaluate("() => (document.getElementById('msgBanner') || {}).innerText || ''")
    ok('A2 on another screen → Sphere tone plays and a banner shows name + preview', audio_ok and s2['osc'] > s0['osc'] and s2['banner'] and 'Yhiyhi' in btxt and 'Final cut' in btxt and s2['notes'] == 0, f"{s2} banner='{btxt[:40]}'")
    # A3 the same message again (after the 1.2 s sound gap) → nothing new
    pg.wait_for_timeout(1500); pg.evaluate("() => { const b = document.getElementById('msgBanner'); if(b) b.remove(); }"); s0 = state(); fire('a2'); pg.wait_for_timeout(600); s3 = state()
    ok('A3 the same message delivered twice → alerts only once', s3['osc'] == s0['osc'] and not s3['banner'], str(s3))
    # A4 app in background + allowed → system notification with name + preview, tagged per sender
    pg.evaluate("() => { window.__hidden = true; }"); fire('a4'); pg.wait_for_timeout(500)
    n4 = pg.evaluate("() => { const n = window.__notes[window.__notes.length-1]; return n ? { t: n.title, b: n.opts.body, tag: n.opts.tag, chat: n.opts.data.chatWith } : null; }")
    ok('A4 app in background → system notification (name, preview, one per chat)', n4 and n4['t'] == 'Yhiyhi 681' and 'Final cut' in n4['b'] and n4['tag'] == 'chat-' + SENDER, str(n4))
    # A5 preview off → "New message"
    pg.evaluate("() => setMsgPrefs({ preview: false })"); fire('a5'); pg.wait_for_timeout(500)
    b5 = pg.evaluate("() => window.__notes[window.__notes.length-1].opts.body")
    ok('A5 "Show message preview" off → notification says only "New message"', b5 == 'New message', b5)
    pg.evaluate("() => setMsgPrefs({ preview: true })")
    # A6 tapping the notification opens that exact chat
    pg.evaluate("() => { window.__hidden = false; window.__notes[window.__notes.length-1].onclick(); }"); pg.wait_for_timeout(1200)
    ok('A6 tapping the notification opens the right conversation', pg.evaluate("() => currentScreenName") == 'chatThread' and pg.evaluate("() => currentChatWith") == SENDER)
    # A7 permission denied → nothing shown, never asked again
    pg.evaluate("() => { nav('home'); Notification.permission = 'denied'; window.__hidden = true; }"); pg.wait_for_timeout(800)
    c0 = pg.evaluate("() => window.__notes.length"); fire('a7'); pg.wait_for_timeout(500)
    ok('A7 permission denied → no notification and no new permission request', pg.evaluate("() => window.__notes.length") == c0 and pg.evaluate("() => window.__reqs") == 0)
    # A8 alerts switched off → nothing at all; silent tone → banner but no sound
    pg.evaluate("() => { Notification.permission = 'granted'; window.__hidden = false; setMsgPrefs({ enabled: false }); }"); s0 = state(); fire('a8'); pg.wait_for_timeout(500); s8 = state()
    ok('A8 message alerts off → no sound, no banner, no notification', s8['osc'] == s0['osc'] and not s8['banner'] and s8['notes'] == s0['notes'], str(s8))
    pg.wait_for_timeout(1300); pg.evaluate("() => setMsgPrefs({ enabled: true, tone: 'silent' })"); s0 = state(); fire('a9'); pg.wait_for_timeout(600); s9 = state()
    ok('A9 Silent tone → banner only, no sound', s9['osc'] == s0['osc'] and s9['banner'], str(s9))
    ok('A10 Sphere never asked for notification permission by itself', pg.evaluate("() => window.__reqs") == 0)
    # B1 settings: tones, preview, choose, permission button
    pg.evaluate("() => { const b = document.getElementById('msgBanner'); if(b) b.remove(); Notification.permission = 'default'; nav('msgAlerts'); }"); pg.wait_for_timeout(800)
    names = pg.evaluate("() => [...document.querySelectorAll('.tone-row input')].map(i => i.value)")
    o0 = pg.evaluate("() => window.__osc"); pg.click('button[aria-label="Play Laser"]'); pg.wait_for_timeout(200); o1 = pg.evaluate("() => window.__osc")
    pg.click('.tone-row input[value="wobble"]'); pg.wait_for_timeout(200)
    ok('B1 tone list has Silent + 12 Sphere tones; ▶ plays a preview', len(names) == 13 and names[0] == 'silent' and 'telepathy' in names and o1 > o0, f'{len(names)} tones, preview oscillators {o1 - o0}')
    pg.screenshot(path=os.path.join(tempfile.mkdtemp(prefix='sphere_alerts_'), 'msg_alerts.png'))
    pg.click('text=Allow notifications'); pg.wait_for_timeout(600)
    ok('B2 "Allow notifications" asks once, only when tapped', pg.evaluate("() => window.__reqs") == 1)
    ok('X1 no JavaScript errors (first session)', not errs, str(errs[:2]))
    saved = pg.evaluate("() => localStorage.getItem('sp_msg_prefs:me-111')")
    pg.reload(); pg.wait_for_timeout(2500); pg.evaluate(mock); pg.evaluate("() => nav('msgAlerts')"); pg.wait_for_timeout(800)
    ok('B3 chosen tone is remembered after reloading the app', pg.evaluate("() => (document.querySelector('.tone-row input:checked') || {}).value") == 'wobble' and '"wobble"' in (saved or ''), saved)
    b.close()
    # B4 a notification link opens that chat after login (and the link is cleaned from the address bar)
    b, ctx, pg, errs = new_page(p, 'http://sphere.test/?chat=' + SENDER)
    pend = pg.evaluate("() => PENDING_CHAT"); clean = pg.evaluate("() => location.search")
    pg.evaluate(mock); pg.evaluate("() => { getProfilesByIds = async (ids) => Object.fromEntries(ids.map(i => [i, { id: i, name: 'Yhiyhi 681' }])); nav('home'); }"); pg.wait_for_timeout(1500)
    first = pg.evaluate("() => currentScreenName")                                   # no phone yet → app asks for it first
    pg.evaluate("() => { currentUser.phone = '+919812345678'; currentUser.phone_verified = true; nav('home'); }"); pg.wait_for_timeout(2600)
    ok('B4 notification link → after login (and after adding a phone) opens that chat; address bar cleaned',
       pend == SENDER and clean == '' and first == 'addPhone' and pg.evaluate("() => currentScreenName") == 'chatThread' and pg.evaluate("() => currentChatWith") == SENDER and pg.evaluate("() => PENDING_CHAT") is None,
       f'pending={pend} first={first} then={pg.evaluate("() => currentScreenName")}')
    bad = new_page(p, 'http://sphere.test/?chat=../../admin'); okbad = bad[2].evaluate("() => PENDING_CHAT") is None; bad[0].close()
    ok('B5 a malformed chat link is ignored', okbad)
    b.close()
for r in R: print(f'{r[0]:5} {r[1]} {("— " + r[2]) if r[2] else ""}'[:230])
print('TOTAL', sum(1 for r in R if r[0]=='PASS'), '/', len(R))
sys.exit(0 if all(r[0]=='PASS' for r in R) else 1)
