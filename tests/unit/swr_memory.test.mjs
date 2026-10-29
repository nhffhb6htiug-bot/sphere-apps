// Pure regression tests for navigation cache and safe public profile fallback.
// No real auth, private user data, network or payment calls.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const html = fs.readFileSync('index.html.html', 'utf8');
function extract(start, end) {
  const a = html.indexOf(start);
  assert.ok(a >= 0, 'start anchor: ' + start);
  const b = html.indexOf(end, a);
  assert.ok(b > a, 'end anchor: ' + end);
  return html.slice(a, b);
}

function screenCacheHarness() {
  const source = extract('const SWR_SCREENS = new Set(', '\nlet IS_RECOVERY');
  let now = 1000000;
  const NativeDate = Date;
  class FakeDate extends NativeDate { static now() { return now; } }
  const sandbox = { Date: FakeDate, Map, Set, JSON, getCurrentUser: () => ({
    id: 'user-one', role: 'client'
  }) };
  vm.runInNewContext(source + `
    globalThis.__cache = SCREEN_CACHE;
    globalThis.__cacheGet = screenCacheGet;
    globalThis.__cachePut = screenCachePut;
    globalThis.__cacheHas = screenCacheHas;
    globalThis.__key = swrKey;
    globalThis.__max = SCREEN_CACHE_MAX;
  `, sandbox);
  return { ...sandbox, advance: ms => { now += ms; } };
}

test('SWR cache preserves existing routes and stores only a bounded set of screens', () => {
  const cache = screenCacheHarness();
  assert.equal(cache.__key('home',{}), 'user-one|client|home|{}');
  assert.equal(cache.__key('login',{}), null);
  for (let i=0; i<45; i++) cache.__cachePut('p'+i, 'screen-'+i);
  assert.equal(cache.__cache.size, cache.__max);
  assert.equal(cache.__cacheGet('p0'), null, 'oldest entry evicted');
  assert.equal(cache.__cacheGet('p44'), 'screen-44');
  assert.equal(cache.__cacheGet('p33'), 'screen-33');
  cache.__cachePut('new', 'latest');
  assert.equal(cache.__cacheGet('p34'), null, 'least-recently-used entry evicted');
});

test('SWR cache expires stale screens, ignores large HTML, and still supports logout clearing', () => {
  const cache = screenCacheHarness();
  cache.__cachePut('home', 'cached-home');
  assert.equal(cache.__cacheGet('home'), 'cached-home');
  cache.advance(120001);
  assert.equal(cache.__cacheHas('home'), false, 'old screen expires');
  assert.equal(cache.__cache.size, 0);
  cache.__cachePut('too-big', 'x'.repeat(190000));
  assert.equal(cache.__cache.size, 0);
  cache.__cachePut('private', 'user content');
  cache.__cache.clear();
  assert.equal(cache.__cacheGet('private'), null, 'logout clears data');
});

test('public editor profile lookup never tries a private profiles table fallback', async () => {
  const source = extract('async function getProfilesByIds(ids){', '\nlet VERIFIED_CACHE');
  let rpcCalls = 0, privateQueries = 0, publicQueries = 0;
  const sandbox = {
    Set, Map, Promise,
    sb: {
      rpc: async () => { rpcCalls++; return { data: null, error: { message: 'RPC unavailable' } }; },
      from: () => { privateQueries++; throw new Error('private fallback is forbidden'); }
    },
    publicEditors: async () => { publicQueries++; return {data: [{id:'a', full_name:'Public Editor'}]}; },
    toAppUser: x => x,
    attachRatings: async arr => arr
  };
  vm.runInNewContext(source + '\nglobalThis.__lookup = getProfilesByIds;', sandbox);
  const profiles = await sandbox.__lookup(['a']);
  assert.equal(profiles.a.full_name, 'Public Editor');
  assert.equal(rpcCalls, 1);
  assert.equal(publicQueries, 1);
  assert.equal(privateQueries, 0);
});
