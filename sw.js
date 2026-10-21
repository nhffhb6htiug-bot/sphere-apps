// Sphere service worker — makes the app installable and opens fast.
// Pages: network first (always newest version), falls back to the saved copy when offline.
// Supabase / Razorpay / other sites are never cached.
const CACHE = 'sphere-v2';
const PRECACHE = ['/', '/manifest.json', '/icon-192.png', '/icon-512.png', '/favicon.png'];

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
  if (url.origin !== self.location.origin) return;

  if (req.mode === 'navigate') {
    event.respondWith(
      fetch(req)
        .then((res) => {
          if (url.pathname === '/' || url.pathname === '/index.html') {
            const copy = res.clone();
            caches.open(CACHE).then((c) => c.put('/', copy));
          }
          return res;
        })
        .catch(() => caches.match(req).then((r) => r || caches.match('/')))
    );
    return;
  }

  event.respondWith(
    caches.match(req).then((cached) => {
      const fresh = fetch(req).then((res) => {
        if (res && res.ok) caches.open(CACHE).then((c) => c.put(req, res.clone()));
        return res;
      }).catch(() => cached);
      return cached || fresh;
    })
  );
});

// Tapping a message notification opens (or focuses) Sphere
// Phone push (sent by the sphere-push function). If Sphere is on screen it shows the message itself.
self.addEventListener('push', (event) => {
  let d = {};
  try { d = event.data ? event.data.json() : {}; } catch (e) { d = {}; }
  event.waitUntil((async () => {
    const wins = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    const isTest = d.title === '🔔 Sphere test';
    if (!isTest && wins.some((c) => c.visibilityState === 'visible')) {
      wins.forEach((c) => c.postMessage({ type: 'sphere-push', data: { id: d.id, category: d.category } }));
      return;
    }
    const chatWith = d.category === 'messages' && /^[0-9a-f-]{36}$/i.test(String(d.sender_id || '')) ? String(d.sender_id) : '';
    await self.registration.showNotification(String(d.title || 'Sphere').slice(0, 80), {
      body: String(d.body || '').slice(0, 300), icon: '/icon-192.png', badge: '/favicon.png',
      tag: String(d.tag || ('n-' + (d.id || Date.now()))), renotify: true, vibrate: [120, 60, 120],
      data: { chatWith, open: chatWith ? '' : 'notifications', id: d.id || null }
    });
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
