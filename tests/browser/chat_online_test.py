from playwright.sync_api import sync_playwright
import tempfile as _tf, os as _os
SHOTS=_tf.mkdtemp(prefix='sphere_shots_')
import os, sys
ROOT=os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..')); html=open(ROOT+'/index.html.html',encoding='utf-8').read(); js=open(ROOT+'/vendor/supabase-2.117.2.js',encoding='utf-8').read()
R=[]; ok=lambda n,c,d='': R.append(('PASS' if c else 'FAIL', n, d))
with sync_playwright() as p:
    b=p.chromium.launch(); pg=b.new_page(viewport={'width':360,'height':720}); errs=[]
    pg.on('pageerror', lambda e: errs.append(str(e)[:150]))
    def rt(r):
        u=r.request.url
        if 'supabase-2.117.2' in u: return r.fulfill(body=js, content_type='application/javascript')
        if u.startswith('http://sphere.test/img/'): return r.fulfill(path=os.path.join(ROOT, u[len('http://sphere.test/'):]), content_type='image/webp')
        if u.startswith('http://sphere.test'): return r.fulfill(body=html, content_type='text/html')
        return r.abort()
    pg.route('**/*', rt); pg.goto('http://sphere.test/'); pg.wait_for_timeout(2500)
    pg.add_style_tag(content='#netBanner{display:none !important}')
    pg.evaluate("""() => {
      currentUser = { id: 'me-111', name: 'Hh', role: 'CLIENT', baseRole: 'CLIENT' };
      window.__log = []; window.__state = {};
      sb.channel = (name, opts) => { const h = {}; const ch = {
          name, on(t, f, cb){ (h[f.event] = h[f.event] || []).push(cb); return ch; },
          subscribe(cb){ window.__log.push('subscribe:' + name + ':key=' + opts.config.presence.key); setTimeout(() => cb('SUBSCRIBED'), 10); return ch; },
          presenceState(){ return window.__state; }, track(){ window.__log.push('track'); return Promise.resolve(); }, untrack(){ window.__log.push('untrack'); return Promise.resolve(); },
          fire(ev){ (h[ev] || []).forEach(f => f()); } }; window.__ch = ch; return ch; };
      sb.removeChannel = (c) => { window.__log.push('remove:' + c.name); };
      document.getElementById('app').innerHTML = `<div class="screen"><div class="chat-head" style="flex-wrap:wrap;"><button class="ch-back">‹</button><div class="avatar" style="width:44px;height:44px;border-radius:50%;background:#ddd"></div><div class="ch-name"><b>Yhiyhi 681 💎</b><small>Client<span id="chOnline" class="ch-online" hidden> · <i></i>online</span></small></div><button class="ch-more">⋮</button></div></div>`;
      startChatPresence('other-222'); }""")
    pg.wait_for_timeout(200)
    log=pg.evaluate("() => window.__log")
    ok('O1 joins a private channel named after the two people and shares own status', any(x.startswith('subscribe:presence-me-111-other-222') for x in log) and 'track' in log, str(log))
    pg.evaluate("() => { window.__state = { 'other-222': [{ at: 1 }] }; window.__ch.fire('join'); }"); pg.wait_for_timeout(100)
    on=pg.evaluate("() => !document.getElementById('chOnline').hidden")
    pg.screenshot(path=_os.path.join(SHOTS, 'chat_online.png'), clip={'x':0,'y':0,'width':360,'height':110})
    ok('O2 other person in the chat → "online" shown', on)
    pg.evaluate("() => { window.__state = {}; window.__ch.fire('leave'); }"); pg.wait_for_timeout(100)
    ok('O3 other person leaves → "online" hidden', pg.evaluate("() => document.getElementById('chOnline').hidden"))
    pg.evaluate("() => { Object.defineProperty(document, 'hidden', { configurable: true, get: () => true }); document.dispatchEvent(new Event('visibilitychange')); }"); pg.wait_for_timeout(100)
    ok('O4 app goes to background → own status removed (untrack)', 'untrack' in pg.evaluate("() => window.__log"))
    pg.evaluate("() => { Object.defineProperty(document, 'hidden', { configurable: true, get: () => false }); }")
    pg.evaluate("() => nav('home')"); pg.wait_for_timeout(500)
    ok('O5 leaving the chat closes the channel', any(x.startswith('remove:presence-me-111-other-222') for x in pg.evaluate("() => window.__log")) and pg.evaluate("() => chatPresence === null"))
    pg.evaluate("() => { document.getElementById('app').innerHTML = `<div class=\"chat-head\"><button class=\"ch-back\">‹</button><div class=\"ch-name\"><b>x</b></div><button class=\"ch-more\">⋮</button></div>`; }")
    sz=pg.evaluate("() => ['.ch-back','.ch-more'].map(s => { const r = document.querySelector('.chat-head ' + s).getBoundingClientRect(); return [Math.round(r.width), Math.round(r.height)]; })")
    ok('O6 back and ⋮ buttons are at least 44×44 px (easy to tap)', all(w >= 44 and h >= 44 for w,h in sz), str(sz))
    ok('O99 no JavaScript errors', not errs, str(errs[:2]))
    b.close()
for r in R: print(f'{r[0]:5} {r[1]} {("— " + r[2]) if r[2] else ""}'[:200])
print('TOTAL', sum(1 for r in R if r[0]=='PASS'), '/', len(R))
sys.exit(0 if all(r[0]=='PASS' for r in R) else 1)
