// Sphere PWA service worker v4 — no visual changes.
// Only static public assets may enter Cache Storage. In particular, Supabase
// responses and account data are never cached, even if proxied by this origin.
const CACHE = 'sphere-static-v4';
const PRECACHE = ['/', '/manifest.json', '/icon-192.png', '/icon-512.png', '/favicon.png'];
const STATIC_ASSETS = /^\/(?:img\/[^?#]+|(?:icon|apple-touch-icon|notif-icon|notif-badge|favicon)[^/]*\.(?:png|webp|svg|ico)|sphere-(?:dark-theme|desktop)\.css|manifest\.json)$/i;
const CACHE_FIRST = /^\/img\/[^?#]+\.(?:webp|png|jpe?g|svg)$/i;
const PRIVATE_PREFIX = /^\/(?:sb(?:\/|$)|api(?:\/|$)|rest\/v1(?:\/|$)|auth\/v1(?:\/|$)|functions\/v1(?:\/|$)|storage\/v1(?:\/|$))/i;

self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(CACHE).then((c) => c.addAll(PRECACHE)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin || PRIVATE_PREFIX.test(url.pathname)) return;

  // Navigations: fresh-first, cached offline shell fallback.
  // Only "/" is cached: never cache account-specific or OTP query parameters.
  if (req.mode === 'navigate') {
    event.respondWith(
      fetch(req).then((res) => {
        if (res && res.ok && (url.pathname === '/' || url.pathname === '/index.html')) {
          event.waitUntil(caches.open(CACHE).then((c) => c.put('/', res.clone())).catch(() => {}));
        }
        return res;
      }).catch(() => caches.match('/').then((r) => r || Response.error()))
    );
    return;
  }

  // Skip ALL dynamic responses: user/financial data, admin endpoints, etc.
  // Unknown paths go directly to the network, without any Cache Storage write.
  if (!STATIC_ASSETS.test(url.pathname)) return;

  if (CACHE_FIRST.test(url.pathname)) {
    // Original image assets are versioned with the service worker on deploy.
    // Avoid the old unnecessary network request for every cached image.
    event.respondWith(caches.match(req).then((cached) => cached || fetch(req).then((res) => {
      if (res && res.ok) {
        event.waitUntil(caches.open(CACHE).then((c) => c.put(req, res.clone())).catch(() => {}));
      }
      return res;
    })));
    return;
  }

  // Unversioned CSS/manifest/icons: network first; cached fallback offline.
  event.respondWith(fetch(req).then((res) => {
    if (res && res.ok) {
      event.waitUntil(caches.open(CACHE).then((c) => c.put(req, res.clone())).catch(() => {}));
    }
    return res;
  }).catch(() => caches.match(req).then((r) => r || Response.error())));
});

// Tapping a message notification opens (or focuses) Sphere
// Phone push (sent by the sphere-push function). If Sphere is on screen it shows the message itself.
const SPHERE_API = self.location.hostname === 'sphere-live.onrender.com' ? self.location.origin + '/sb' : 'https://sphere-api.niteshkumarmatho37.workers.dev';
function sphereAck(d) {          // tells the sender's chat "delivered" (✓✓) — only with the receipt token from the server
  if (!d || !d.ack || !d.id) return Promise.resolve();
  return fetch(SPHERE_API + '/functions/v1/sphere-push', { method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ action: 'delivered', id: d.id, token: d.ack }) }).catch(() => {});
}
self.addEventListener('push', (event) => {
  let d = {};
  try { d = event.data ? event.data.json() : {}; } catch (e) { d = {}; }
  event.waitUntil((async () => {
    const ack = sphereAck(d);
    const wins = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    const isTest = d.title === '🔔 Sphere test';
    if (!isTest && wins.some((c) => c.visibilityState === 'visible')) {
      wins.forEach((c) => c.postMessage({ type: 'sphere-push', data: { id: d.id, category: d.category } }));
      await ack; return;
    }
    const chatWith = d.category === 'messages' && /^[0-9a-f-]{36}$/i.test(String(d.sender_id || '')) ? String(d.sender_id) : '';
    await self.registration.showNotification(String(d.title || 'Sphere').slice(0, 80), {
      body: String(d.body || '').slice(0, 300), icon: '/notif-icon.png', badge: '/notif-badge.png',
      tag: String(d.tag || ('n-' + (d.id || Date.now()))), renotify: true, vibrate: [120, 60, 120],
      data: { chatWith, open: chatWith ? '' : 'notifications', id: d.id || null }
    });
    await ack;
  })());
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const d = event.notification.data || {};
  const chatWith = /^[0-9a-f-]{36}$/i.test(String(d.chatWith || '')) ? String(d.chatWith) : '';
  const openList = !chatWith && d.open === 'notifications';
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
      for (const c of list) {
        if ('focus' in c) {
          if (chatWith) c.postMessage({ type: 'sphere-open-chat', chatWith });   // the open app jumps to that chat
          else if (openList) c.postMessage({ type: 'sphere-open-notifications' });
          return c.focus();
        }
      }
      return self.clients.openWindow(chatWith ? '/?chat=' + chatWith : openList ? '/?open=notifications' : '/');    // a new window opens it after login
    })
  );
});
