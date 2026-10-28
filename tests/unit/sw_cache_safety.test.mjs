// Deterministic service-worker safety/performance tests. No network or real users.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';

function createWorker() {
  const script = fs.readFileSync('sw.js', 'utf8');
  const handlers = new Map();
  const stored = new Map();
  let calls = [];
  let networkDown = false;
  const origin = 'https://sphere.syahi.online';
  const key = (request) => typeof request === 'string' ? new URL(request, origin).href : request.url;
  const cache = {
    match: async (request, opts = {}) => {
      const exact = stored.get(key(request));
      if (exact || !opts.ignoreSearch) return exact;
      const target = new URL(key(request)).pathname;
      for (const [k, value] of stored) {
        if (new URL(k).pathname === target) return value;
      }
    },
    put: async (request, response) => { stored.set(key(request), response); },
    addAll: async paths => { paths.forEach(p => stored.set(key(p), response(p))); }
  };
  const response = url => ({ ok: true, url, clone() { return response(url); } });
  const fetch = async request => {
    calls.push(key(request));
    if (networkDown) throw new Error('offline');
    return response(key(request));
  };
  const context = {
    self: {
      location: { origin, hostname: 'sphere.syahi.online' },
      addEventListener: (name, fn) => handlers.set(name, fn),
      clients: { claim: async () => {}, matchAll: async () => [] },
      skipWaiting: () => {},
    },
    fetch,
    caches: {
      open: async () => cache,
      keys: async () => ['sphere-static-v4'],
      delete: async () => true,
      match: async (request, options) => cache.match(request, options),
    },
    Response: { error: () => ({ ok: false, offline: true }) },
    URL, Promise, Date, JSON, RegExp, String, Object, Array
  };
  vm.runInNewContext(script, context, { filename: 'sw.js' });
  let lastResponse = null;
  async function dispatch(path, mode = 'cors', method = 'GET') {
    const waiting = [];
    let result;
    const request = { url: path.startsWith('http') ? path : origin + path, method, mode };
    handlers.get('fetch')({
      request,
      respondWith(p) { result = Promise.resolve(p); },
      waitUntil(p) { waiting.push(Promise.resolve(p)); }
    });
    const handled = !!result;
    if (result) lastResponse = await result;
    await Promise.all(waiting);
    return { handled };
  }
  return {
    dispatch,
    calls: () => calls.slice(),
    cacheKeys: () => [...stored.keys()],
    offline: v => { networkDown = v; },
    handlers,
    lastResponse: () => lastResponse
  };
}

test('private proxied API, auth, payments, and unknown data are never intercepted or cached', async () => {
  const sw = createWorker();
  const paths = [
    '/sb/rest/v1/profiles?select=*',
    '/sb/auth/v1/user',
    '/api/private-me',
    '/rest/v1/sp_jobs',
    '/functions/v1/release-payout',
    '/storage/v1/object/authenticated/private-file',
    '/sensitive-account.json'
  ];
  for (const path of paths) {
    assert.deepEqual(await sw.dispatch(path), { handled: false }, path);
  }
  assert.deepEqual(await sw.dispatch('/img/abc.webp', 'cors', 'POST'), { handled: false });
  assert.equal(sw.cacheKeys().length, 0);
  assert.equal(sw.calls().length, 0);
});

test('hashed Sphere image is fetched only once after warm cache, without changing UI artwork', async () => {
  const sw = createWorker();
  const url = '/img/0cbdc280b5c44e61.webp';
  assert.equal((await sw.dispatch(url)).handled, true);
  assert.equal((await sw.dispatch(url)).handled, true);
  assert.equal(sw.calls().length, 1);
  assert.ok(sw.cacheKeys().some(k => k.endsWith(url)));
});

test('offline navigation uses cached HTML shell; no private query is stored as cache key', async () => {
  const sw = createWorker();
  assert.equal((await sw.dispatch('/?source=app', 'navigate')).handled, true);
  sw.offline(true);
  assert.equal((await sw.dispatch('/?chat=00000000-0000-4000-8000-000000000000', 'navigate')).handled, true);
  const keys = sw.cacheKeys();
  assert.ok(keys.includes('https://sphere.syahi.online/'));
  assert.ok(!keys.some(k => k.includes('chat=')));
});

test('offline versioned CSS falls back to its precached unversioned resource', async () => {
  const sw = createWorker();
  await sw.dispatch('/sphere-dark-theme.css');
  sw.offline(true);
  assert.equal((await sw.dispatch('/sphere-dark-theme.css?v=2')).handled, true);
  assert.equal(sw.lastResponse()?.ok, true);
});
