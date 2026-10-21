import os, sys, tempfile
from playwright.sync_api import sync_playwright
HERE=os.path.dirname(os.path.abspath(__file__)); ROOT=os.environ.get('SPHERE_ROOT', os.path.abspath(os.path.join(HERE, '..', '..'))); html=open(ROOT+'/index.html.html',encoding='utf-8').read(); js=open(ROOT+'/vendor/supabase-2.117.2.js',encoding='utf-8').read()
mock=open(os.path.join(HERE, 'fixtures', 'chat_mock.js')).read(); PHOTO=os.path.join(HERE, 'fixtures', 'photo.png'); DOC=os.path.join(HERE, 'fixtures', 'not_a_photo.txt')
R=[]; ok=lambda n,c,d='': R.append(('PASS' if c else 'FAIL', n, d))
SHOTS=tempfile.mkdtemp(prefix='chat_')
with sync_playwright() as p:
    b=p.chromium.launch(); ctx=b.new_context(viewport={'width':360,'height':720}, has_touch=True, is_mobile=True); pg=ctx.new_page(); errs=[]
    pg.on('pageerror', lambda e: errs.append(str(e)[:200]))
    def rt(r):
        u=r.request.url
        if 'supabase-2.117.2' in u: return r.fulfill(body=js, content_type='application/javascript')
        if u.startswith('http://sphere.test/img/'): return r.fulfill(path=ROOT+u[len('http://sphere.test'):], content_type='image/webp')
        if u.startswith('http://sphere.test'): return r.fulfill(body=html, content_type='text/html')
        return r.abort()
    pg.route('**/*', rt); pg.goto('http://sphere.test/'); pg.wait_for_timeout(2500); pg.add_style_tag(content='#netBanner{display:none !important}')
    pg.evaluate(mock)
    pg.evaluate("() => { window.__msgs.push({ id: 'm-a', sender_id: 'other-222', receiver_id: 'me-111', text: 'Hi, can you edit my vlog?', created_at: new Date(Date.now()-600000).toISOString(), mod_status: 'ok' }); nav('chatThread'); }")
    pg.wait_for_timeout(1500)
    vis = lambda sel: pg.evaluate("(s) => { const e = document.querySelector(s); if(!e) return false; const r = e.getBoundingClientRect(); return getComputedStyle(e).display !== 'none' && r.height > 0; }", sel)
    ok('P1 on opening the chat, the emoji panel, camera/gallery sheet and reply bar are really hidden', not vis('#emojiPanel') and not vis('#attachSheet') and not vis('#replyBar'),
       f"emoji={vis('#emojiPanel')} attach={vis('#attachSheet')} reply={vis('#replyBar')}")
    n = lambda: pg.evaluate("() => window.__inserts.length")
    # K1 keyboard stays: focus, type, tap Send → input keeps focus, cleared after success, one message
    pg.click('#chatInput'); pg.keyboard.type('Hello 👋 from the test'); pg.tap('#sendBtn'); pg.wait_for_timeout(600)
    ok('K1 tapping Send keeps the keyboard (focus stays in the box), clears only after sending, no screen reload',
       pg.evaluate("() => document.activeElement && document.activeElement.id") == 'chatInput' and pg.input_value('#chatInput') == '' and n() == 1
       and pg.evaluate("() => document.querySelectorAll('#chatBox .chat-bubble').length") == 2, f"focus={pg.evaluate('() => document.activeElement && document.activeElement.id')} inserts={n()}")
    # K2 failure keeps the text
    pg.evaluate("() => { window.__failInsert = 1; }"); pg.fill('#chatInput', 'will fail'); pg.tap('#sendBtn'); pg.wait_for_timeout(600)
    ok('K2 a failed send keeps the text in the box', pg.input_value('#chatInput') == 'will fail' and n() == 1, f"box='{pg.input_value('#chatInput')}'")
    pg.evaluate("() => { const d = document.getElementById('spDlg'); if(d) d.remove(); }")
    # K3 double tap → one message
    pg.fill('#chatInput', 'double tap'); pg.evaluate("() => { document.getElementById('sendBtn').click(); document.getElementById('sendBtn').click(); }"); pg.wait_for_timeout(600)
    ok('K3 two quick taps send only one message', n() == 2, f'inserts={n()}')
    # K4 Enter sends, Shift+Enter does not
    pg.fill('#chatInput', 'shift enter'); pg.press('#chatInput', 'Shift+Enter'); pg.wait_for_timeout(300); a = n()
    pg.press('#chatInput', 'Enter'); pg.wait_for_timeout(500)
    ok('K4 Enter sends, Shift+Enter does not', a == 2 and n() == 3, f'after shift={a} after enter={n()}')
    # E1 emoji panel inserts at the cursor and keeps focus
    pg.fill('#chatInput', 'ab'); pg.evaluate("() => { const i = document.getElementById('chatInput'); i.focus(); i.setSelectionRange(1,1); }")
    pg.tap('button[aria-label="Emoji"]'); pg.wait_for_timeout(200); pg.tap('#emojiPanel button[aria-label="🔥"]'); pg.wait_for_timeout(200)
    ok('E1 emoji picker inserts at the cursor', pg.input_value('#chatInput') == 'a🔥b' and pg.evaluate("() => document.activeElement.id") == 'chatInput', pg.input_value('#chatInput'))
    pg.fill('#chatInput', '')
    # R1 swipe right on a message → reply bar; send → reply saved and quoted; tap quote → jumps to original
    def swipe(sel, dx, dy):
        pg.evaluate("""([sel, dx, dy]) => { const el = document.querySelector(sel); const r = el.getBoundingClientRect(); const x = r.left + 20, y = r.top + r.height/2;
          const t = (cx, cy) => new Touch({ identifier: 1, target: el, clientX: cx, clientY: cy });
          el.dispatchEvent(new TouchEvent('touchstart', { bubbles: true, touches: [t(x, y)], changedTouches: [t(x, y)] }));
          for(let i = 1; i <= 8; i++) el.dispatchEvent(new TouchEvent('touchmove', { bubbles: true, touches: [t(x + dx*i/8, y + dy*i/8)], changedTouches: [t(x + dx*i/8, y + dy*i/8)] }));
          el.dispatchEvent(new TouchEvent('touchend', { bubbles: true, touches: [], changedTouches: [t(x + dx, y + dy)] })); }""", [sel, dx, dy])
    swipe('#chatBox .chat-bubble[data-id="m-a"]', 5, 90); pg.wait_for_timeout(250)
    vert = pg.evaluate("() => document.getElementById('replyBar').hidden")
    swipe('#chatBox .chat-bubble[data-id="m-a"]', 75, 4); pg.wait_for_timeout(300)
    bar = pg.evaluate("() => !document.getElementById('replyBar').hidden && document.getElementById('replyBar').innerText")
    ok('R1 vertical drag does not start a reply (scrolling is free)', vert is True)
    ok('R2 swipe right on a message opens the reply preview', bool(bar) and 'vlog' in bar, str(bar)[:60])
    pg.fill('#chatInput', 'Yes, I can'); pg.tap('#sendBtn'); pg.wait_for_timeout(600)
    last = pg.evaluate("() => window.__inserts[window.__inserts.length-1]")
    quote = pg.evaluate("() => { const b = [...document.querySelectorAll('#chatBox .chat-bubble')].pop(); const q = b.querySelector('.msg-quote'); return q ? q.innerText : null; }")
    ok('R3 the reply is saved with reply_to and shows a quote of the original', last.get('reply_to') == 'm-a' and quote and 'vlog' in quote and pg.evaluate("() => document.getElementById('replyBar').hidden"), f"reply_to={last.get('reply_to')} quote={str(quote)[:40]}")
    pg.evaluate("() => [...document.querySelectorAll('#chatBox .chat-bubble')].pop().querySelector('.msg-quote').click()"); pg.wait_for_timeout(200)
    ok('R4 tapping the quote jumps to and highlights the original', pg.evaluate("() => document.querySelector('#chatBox .chat-bubble[data-id=\"m-a\"]').classList.contains('flash')"))
    pg.tap('button[aria-label="Attach a photo or video"]'); pg.wait_for_timeout(150); o1 = vis('#attachSheet') and not vis('#emojiPanel')
    pg.evaluate("() => document.getElementById('chatBox').click()"); pg.wait_for_timeout(150); o2 = vis('#attachSheet')
    ok('P2 📎 shows Camera/Gallery (and hides emoji); tapping elsewhere closes it', o1 and not o2, f'open={o1} after outside tap={o2}')
    ok('P3 after sending, the reply bar is really hidden', not vis('#replyBar'))
    # I1 wrong file type refused
    pg.set_input_files('#chatFile', DOC); pg.wait_for_timeout(300)
    ok('I1 a non-photo file is refused', not pg.query_selector('#mediaPreview') and any('photos and videos' in t for t in [pg.evaluate("() => (document.getElementById('spDlg')||{}).innerText || ''")]))
    pg.evaluate("() => { const d = document.getElementById('spDlg'); if(d) d.remove(); }")
    # I2 photo → preview with caption → upload fails → retry → sent
    pg.evaluate("() => { window.__failUpload = 1; }"); pg.set_input_files('#chatCam', PHOTO); pg.wait_for_timeout(400)
    prev = pg.evaluate("() => !!document.querySelector('#mediaPreview img')"); pg.screenshot(path=os.path.join(SHOTS, 'preview.png'))
    pg.fill('#mpCaption', 'Reference photo'); pg.click('#mpSend'); pg.wait_for_timeout(700)
    err = pg.evaluate("() => (document.getElementById('mpErr')||{}).innerText || ''"); btn = pg.evaluate("() => document.getElementById('mpSend').textContent")
    pg.click('#mpSend'); pg.wait_for_timeout(800)
    last = pg.evaluate("() => window.__inserts[window.__inserts.length-1]")
    ok('I2 camera/gallery photo shows a preview before sending', prev)
    ok('I3 a failed upload shows the error and a retry button', 'Upload failed' in err and btn == '↻', err[:50])
    ok('I4 retry uploads and sends the photo with its caption', last.get('media_type') == 'image' and last.get('text') == 'Reference photo' and not pg.query_selector('#mediaPreview'), f"uploads={pg.evaluate('() => window.__uploads')}")
    # V1 full-screen viewer
    pg.evaluate("() => { const im = [...document.querySelectorAll('#chatBox .chat-img')].pop(); im.click(); }"); pg.wait_for_timeout(200)
    v = pg.evaluate("() => !!document.querySelector('#imgViewer img')"); pg.keyboard.press('Escape'); pg.wait_for_timeout(150)
    ok('V1 tapping a photo opens it full screen; Escape closes it', v and not pg.query_selector('#imgViewer'))
    # T1 typing + online + last seen in the header
    pg.evaluate("() => window.__ch.fire('typing', { payload: { from: 'other-222' } })"); pg.wait_for_timeout(150)
    typing = pg.evaluate("() => !document.getElementById('chTyping').hidden")
    pg.evaluate("() => { window.__pstate = {}; window.__ch.fire('sync'); }"); pg.wait_for_timeout(4000)
    seen = pg.evaluate("() => { const e = document.getElementById('chSeen'); return e && !e.hidden ? e.textContent : ''; }")
    pg.fill('#chatInput', 'x'); pg.evaluate("() => { lastTypingSent = 0; chatTyping(); }")
    sent = pg.evaluate("() => window.__bc.some(m => m.event === 'typing')")
    ok('T1 "typing…" shows when the other person types; my typing is sent', typing and sent)
    ok('T2 offline → "last seen today at …"', 'last seen today at' in seen, seen)
    # L1 layout: nothing wider than the screen, controls ≥ 36 px tall
    over = pg.evaluate("() => document.documentElement.scrollWidth > window.innerWidth + 1")
    sizes = pg.evaluate("() => ['#sendBtn', 'button[aria-label=\"Emoji\"]', 'button[aria-label=\"Attach a photo or video\"]'].map(s => Math.round(document.querySelector(s).getBoundingClientRect().height))")
    pg.screenshot(path=os.path.join(SHOTS, 'chat.png'))
    ok('L1 no sideways scrolling at 360 px; buttons easy to tap', not over and all(h >= 36 for h in sizes), str(sizes))
    ok('X1 no JavaScript errors', not errs, str(errs[:2]))
    b.close()
for r in R: print(f'{r[0]:5} {r[1]} {("— " + r[2]) if r[2] else ""}'[:230])
print('TOTAL', sum(1 for r in R if r[0]=='PASS'), '/', len(R))
sys.exit(0 if all(r[0]=='PASS' for r in R) else 1)
