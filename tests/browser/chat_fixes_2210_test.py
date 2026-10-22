# v2.22.10: Send button always visible, delete for me, bell without chat, auto-read, permission prompt, last seen on open
import os, sys, tempfile
from playwright.sync_api import sync_playwright
HERE=os.path.dirname(os.path.abspath(__file__)); ROOT=os.environ.get('SPHERE_ROOT', os.path.abspath(os.path.join(HERE, '..', '..')))
html=open(ROOT+'/index.html.html',encoding='utf-8').read(); js=open(ROOT+'/vendor/supabase-2.117.2.js',encoding='utf-8').read(); mock=open(os.path.join(HERE,'fixtures','chat_mock.js')).read()
R=[]; ok=lambda n,c,d='': R.append(('PASS' if c else 'FAIL', n, d))
FAKE_N = """(perm) => { window.__reqs = 0; class N { constructor(){} static requestPermission(){ window.__reqs++; N.permission = 'granted'; return Promise.resolve('granted'); } } N.permission = perm; window.Notification = N; }"""
def page(p, w=360):
    b=p.chromium.launch(); ctx=b.new_context(viewport={'width':w,'height':720}, has_touch=True); pg=ctx.new_page(); errs=[]
    pg.on('pageerror', lambda e: errs.append(str(e)[:200]))
    def rt(r):
        u=r.request.url
        if 'supabase-2.117.2' in u: return r.fulfill(body=js, content_type='application/javascript')
        if u.startswith('http://sphere.test/img/'): return r.fulfill(path=ROOT+u[len('http://sphere.test'):], content_type='image/webp')
        if u.startswith('http://sphere.test'): return r.fulfill(body=html, content_type='text/html')
        return r.abort()
    pg.route('**/*', rt); pg.goto('http://sphere.test/'); pg.wait_for_timeout(2500); pg.add_style_tag(content='#netBanner{display:none !important}')
    pg.evaluate(mock); pg.evaluate(FAKE_N, 'granted'); pg.evaluate("() => { currentUser.phone = '+919812345678'; }")
    pg.evaluate("() => { window.__msgs.push({ id: 'm-a', sender_id: 'other-222', receiver_id: 'me-111', text: 'Hi, can you edit my vlog?', created_at: new Date(Date.now()-600000).toISOString(), mod_status: 'ok' }, { id: 'm-b', sender_id: 'me-111', receiver_id: 'other-222', text: 'Sure', created_at: new Date(Date.now()-500000).toISOString(), mod_status: 'ok' }); }")
    return b, pg, errs
with sync_playwright() as p:
    # C1 Send button fully visible on 360 px and the smallest 320 px phones
    for w in (360, 320):
        b, pg, errs = page(p, w); pg.evaluate("() => nav('chatThread')"); pg.wait_for_timeout(1500)
        pg.fill('#chatInput', 'A long message to make sure the box never pushes the send button off the screen'); pg.wait_for_timeout(100)
        r = pg.evaluate("() => { const s = document.getElementById('sendBtn').getBoundingClientRect(); const i = document.getElementById('chatInput').getBoundingClientRect(); return { right: Math.round(s.right), w: Math.round(s.width), vw: innerWidth, inputRight: Math.round(i.right), sendLeft: Math.round(s.left), over: document.documentElement.scrollWidth > innerWidth + 1 }; }")
        ok(f'C1 Send button fully visible at {w} px (not pushed off screen)', r['right'] <= r['vw'] and r['w'] >= 44 and r['inputRight'] <= r['sendLeft'] and not r['over'], str(r))
        if w == 320: pg.screenshot(path=os.path.join(tempfile.mkdtemp(prefix='sphere_2210_'), 'composer_320.png'))
        b.close()
    b, pg, errs = page(p); pg.evaluate("() => nav('chatThread')"); pg.wait_for_timeout(1500)
    # L1 last seen appears on opening the chat, without waiting for the live channel
    pg.wait_for_timeout(800)
    ok('L1 last seen shows soon after opening the chat', 'last seen' in pg.evaluate("() => (document.getElementById('chSeen') || {}).textContent || ''"), pg.evaluate("() => (document.getElementById('chSeen') || {}).textContent || ''"))
    # D1 long-press → menu → Delete for me → bubble gone, stays gone after reopening
    pg.evaluate("""() => { const el = document.querySelector('#chatBox .chat-bubble[data-id="m-a"]'); const r = el.getBoundingClientRect(); const t = new Touch({ identifier: 9, target: el, clientX: r.left + 30, clientY: r.top + 10 });
        el.dispatchEvent(new TouchEvent('touchstart', { bubbles: true, touches: [t], changedTouches: [t] })); }""")
    pg.wait_for_timeout(750)
    menu = pg.evaluate("() => (document.getElementById('msgMenu') || {}).innerText || ''")
    pg.evaluate("() => document.dispatchEvent(new TouchEvent('touchend', { bubbles: true, touches: [], changedTouches: [] }))")
    ok('D1 long-press on a message opens Reply / Copy / Delete for me', all(k in menu for k in ('Reply', 'Copy', 'Delete for me')), menu.replace('\n', ' | '))
    pg.click('#msgMenu .danger'); pg.wait_for_timeout(150); confirm = pg.evaluate("() => (document.getElementById('msgMenu') || {}).innerText || ''")
    pg.click('#msgMenu .danger'); pg.wait_for_timeout(500)
    gone = not pg.query_selector('#chatBox .chat-bubble[data-id="m-a"]'); saved = pg.evaluate("() => window.__hidden")
    ok('D2 asks once more, then deletes only for me (saved, bubble removed, message itself kept)', 'still see it' in confirm and gone and saved == ['m-a'] and pg.evaluate("() => window.__msgs.some(m => m.id === 'm-a')"), f'saved={saved}')
    pg.evaluate("() => { HIDDEN_FOR = null; HIDDEN_MSGS = new Set(); nav('home'); }"); pg.wait_for_timeout(800); pg.evaluate("() => nav('chatThread')"); pg.wait_for_timeout(1500)
    ok('D3 after reopening the chat the deleted message stays hidden', not pg.query_selector('#chatBox .chat-bubble[data-id="m-a"]') and bool(pg.query_selector('#chatBox .chat-bubble[data-id="m-b"]')))
    pg.evaluate("""() => { const el = document.querySelector('#chatBox .chat-bubble[data-id="m-b"]'); el.dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, cancelable: true })); }"""); pg.wait_for_timeout(200)
    ok('D4 on a computer, right-click opens the same menu', bool(pg.query_selector('#msgMenu'))); pg.evaluate("() => closeMsgMenu()")
    # B1 bell counts only Sphere notifications; B2 opening the list marks them read
    pg.evaluate("() => { window.__q.length = 0; refreshBell(); }"); pg.wait_for_timeout(400)
    bellq = pg.evaluate("() => window.__q.filter(q => q.table === 'sp_notifications').map(q => q.calls.map(c => c.join(':')).join(' '))")
    ok('B1 the bell does not count chat-message notifications', any('category.neq.messages' in x for x in bellq), str(bellq)[:160])
    pg.evaluate("() => { window.__notifs = [{ id: 'n1', title: 'Verification approved', body: 'You are verified', is_read: false, category: 'verification', created_at: new Date().toISOString() }]; window.__rpcs.length = 0; window.__q.length = 0; nav('notifications'); }"); pg.wait_for_timeout(1500)
    listq = pg.evaluate("() => window.__q.filter(q => q.table === 'sp_notifications' && q.op === 'select').map(q => q.calls.map(c => c.join(':')).join(' '))")
    ok('B2 the notifications list leaves out chat messages', any('category.neq.messages' in x for x in listq), str(listq)[:160])
    ok('B3 opening the bell marks everything as read (no button needed)', 'sp_notif_mark_read' in pg.evaluate("() => window.__rpcs"), str(pg.evaluate("() => window.__rpcs")))
    # P1 the phone's own permission prompt opens on the first tap after login — exactly once
    pg.evaluate(FAKE_N, 'default'); pg.evaluate("() => { NOTIF_ARMED = false; nav('home'); }"); pg.wait_for_timeout(1500)
    before_tap = pg.evaluate("() => window.__reqs")
    pg.mouse.click(180, 300); pg.wait_for_timeout(400); pg.mouse.click(180, 300); pg.wait_for_timeout(300)
    pg.evaluate("() => nav('chatList')"); pg.wait_for_timeout(800); pg.mouse.click(180, 300); pg.wait_for_timeout(300)
    ok('P1 no prompt before a tap; the first tap opens the phone\'s real "Allow notifications?" prompt — only once', before_tap == 0 and pg.evaluate("() => window.__reqs") == 1 and not pg.query_selector('#askNotif'), f"before={before_tap} asks={pg.evaluate('() => window.__reqs')}")
    ok('X1 no JavaScript errors', not errs, str(errs[:2]))
    b.close()
    # P2 permission already decided (allowed or blocked) → the phone is never asked again
    b, pg, errs = page(p)
    for perm in ('granted', 'denied'):
        pg.evaluate(FAKE_N, perm); pg.evaluate("() => { NOTIF_ARMED = false; nav('home'); }"); pg.wait_for_timeout(900); pg.mouse.click(180, 300); pg.wait_for_timeout(300)
    ok('P2 if notifications are already allowed or blocked, Sphere never asks again', pg.evaluate("() => window.__reqs") == 0)
    # P3 iPhone in Safari (not added to the Home Screen) → one-time tip, closable, not shown again
    pg.evaluate("""() => { Object.defineProperty(navigator, 'userAgent', { configurable: true, get: () => 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 Version/17.5 Mobile/15E148 Safari/604.1' }); localStorage.removeItem('sp_ios_tip_done'); nav('home'); }"""); pg.wait_for_timeout(1800)
    tip = pg.evaluate("() => (document.getElementById('iosTip') || {}).innerText || ''")
    pg.click('#iosTip button'); pg.evaluate("() => nav('home')"); pg.wait_for_timeout(1800)
    ok('P3 iPhone (Safari) gets a one-time "Add to Home Screen" tip; closing it keeps it away', 'Add to Home Screen' in tip and not pg.query_selector('#iosTip'), tip[:80])
    b.close()
for r in R: print(f'{r[0]:5} {r[1]} {("— " + r[2]) if r[2] else ""}'[:230])
print('TOTAL', sum(1 for r in R if r[0]=='PASS'), '/', len(R))
sys.exit(0 if all(r[0]=='PASS' for r in R) else 1)
