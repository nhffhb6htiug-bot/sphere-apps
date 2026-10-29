// No-UI-change performance regressions using only synthetic users and mocked RPCs.
// Neither Supabase production nor real customer data is contacted.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const html = fs.readFileSync('index.html.html', 'utf8');
function section(start, end){
  const a = html.indexOf(start);
  assert.ok(a !== -1, 'missing start: ' + start);
  const b = html.indexOf(end, a);
  assert.ok(b > a, 'missing end: ' + end);
  return html.slice(a, b);
}
const badgeCode = section('const PREMIUM_CACHE = new Map();', '// Chat "online" status');
function badgeHarness(){
  let account = { id: 'client-one' }, rpcCount = 0, settle = null;
  let observers = [], scheduled = [], next = 1;
  const els = [];
  const sand = {
    Map, Set, Promise, Date,
    getCurrentUser: () => account,
    document: { documentElement: {}, querySelectorAll: () => els.filter(e => !e.dataset.done) },
    MutationObserver: class { constructor(fn){ observers.push(fn); } observe(){} },
    setTimeout: fn => {const id=next++;scheduled.push({id,fn});return id;},
    clearTimeout: id => {scheduled=scheduled.filter(t=>t.id!==id);},
    sb: {rpc: async () => {rpcCount++;return await new Promise(resolve => {settle=resolve;});}},
  };
  vm.runInNewContext(badgeCode + `
    globalThis.premiumCheck = isPremiumClient;
    globalThis.badgeChanges = premiumBadgeMutations;
    globalThis.badgeCache = PREMIUM_CACHE;
    globalThis.pendingBadges = PREMIUM_INFLIGHT;
    globalThis.fillBadges = fillPremiumBadges;
  `, sand);
  return {sand, els, observers, setUser: v => account=v, calls:()=>rpcCount,
    resolve: value => settle({ data:value, error:null }),
    scheduled: () => scheduled.length,
    flush: () => {const a=scheduled; scheduled=[];a.forEach(x=>x.fn());}
  };
}

test('concurrent Premium badges for one client use one RPC and cache a successful result', async()=>{
  const h=badgeHarness();
  const first=h.sand.premiumCheck('client-2');
  const second=h.sand.premiumCheck('client-2');
  assert.equal(h.calls(), 1);
  h.resolve(true);
  assert.equal(await first, true);
  assert.equal(await second, true);
  assert.equal(h.sand.pendingBadges.size,0);
  assert.equal(await h.sand.premiumCheck('client-2'),true);
  assert.equal(h.calls(),1);
});

test('Premium RPC response from a signed-out account is not cached for the next login', async()=>{
  const h=badgeHarness();
  const pending=h.sand.premiumCheck('client-3');
  h.setUser({ id: 'client-other' });
  h.resolve(true); await pending;
  assert.equal(h.sand.badgeCache.has('client-3'),false);
});

test('unrelated DOM changes do not trigger Premium lookups; new slots do',()=>{
  const h=badgeHarness();
  const normal = {nodeType:1, matches:()=>false, querySelector:()=>null};
  h.sand.badgeChanges([{addedNodes:[normal]}]);
  assert.equal(h.scheduled(),0);
  const badge={nodeType:1,matches:selector=>selector.includes('prem-badge-slot'),querySelector:()=>null};
  h.sand.badgeChanges([{addedNodes:[badge]}]);
  h.sand.badgeChanges([{addedNodes:[badge]}]);
  assert.equal(h.scheduled(),1,'batch several slot additions into one refresh');
});

test('account-status checks coalesce and never navigate after user switches account', async()=>{
  const src = section('let STATUS_TIMER = null, STATUS_IN_FLIGHT = null;', '// ---- v2.22.24:');
  let user={id:'account-one',suspended:false}, calls=0, resolveStatus;
  let navigations=[];
  const sand={
    getCurrentUser:()=>user,
    document:{hidden:false,addEventListener(){}},
    setInterval(){return 1;},
    loadAccountStatus: async u=>{calls++;await new Promise(resolve=>{resolveStatus=resolve;});u.suspended=true;},
    PREMIUM_CACHE:{clear(){}},SCREEN_CACHE:{clear(){}},nav:x=>navigations.push(x),
    Promise
  };
  vm.runInNewContext(src+'\nglobalThis.checkStatus = refreshAccountStatus;', sand);
  const a=sand.checkStatus(),b=sand.checkStatus();
  assert.equal(calls,1);
  user={id:'account-two',suspended:false};
  resolveStatus();
  await Promise.all([a,b]);
  assert.deepEqual(navigations,[],'stale old-account response must not route the new user');
});

test('logout clears signed media, premium results and private screen caches',()=>{
  const src=section('function clearSessionState(){','// Session ended somewhere else');
  const cleared=[];
  let channels=0, clearedTimer=0;
  const cache=name=>({ clear:()=>cleared.push(name) });
  const sand={
    msgChannel:null, RT_OK:{msg:true,notif:true}, rtPollTimer:2, clearInterval(){channels++;},
    currentUser:{id:'test'},pendingAuthUser:{},ADMIN_PIN:'fake',
    currentChatWith:'other',currentJobId:'job',aiHistory:['secret'],
    PREMIUM_CACHE:cache('premium'),PREMIUM_INFLIGHT:cache('pending'),
    SCREEN_CACHE:cache('screens'),SIGN_MAP:cache('sign-map'),SIGNED:cache('signed'),
    MSG_INDEX:cache('messages'),SIGN_SESSION_EPOCH:0,signTimer:3,clearTimeout(){clearedTimer++;},
    chatPresence:null,PV_POLL:null
  };
  vm.runInNewContext(src+'\nglobalThis.logoutLocal = clearSessionState;',sand);
  sand.logoutLocal();
  assert.deepEqual(cleared.sort(),['messages','pending','premium','screens','sign-map','signed'].sort());
  assert.equal(sand.currentUser,null);assert.equal(clearedTimer,1);assert.equal(channels,1);
  assert.equal(sand.SIGN_SESSION_EPOCH,1);
});

test('new user can check suspension while old user status request is still running', async()=>{
  const src = section('let STATUS_TIMER = null, STATUS_IN_FLIGHT = null;', '// ---- v2.22.24:');
  let user={id:'account-one',suspended:false}, checks=[];
  const sand={
    getCurrentUser:()=>user,document:{hidden:false,addEventListener(){}},setInterval(){return 1;},
    loadAccountStatus: u=>new Promise(resolve=>checks.push({u,resolve})),
    PREMIUM_CACHE:{clear(){}},SCREEN_CACHE:{clear(){}},nav(){},Promise
  };
  vm.runInNewContext(src+'\\nglobalThis.checkStatus = refreshAccountStatus;',sand);
  const before=sand.checkStatus();
  user={id:'account-two',suspended:false};
  const after=sand.checkStatus();
  assert.equal(checks.length,2,'new account should not wait for old session check');
  checks.forEach(x=>x.resolve());
  await Promise.all([before,after]);
});

test('verification polling is foreground-only and never overlaps in-flight requests',()=>{
  assert.match(html, /if\(document\.hidden \|\| PV_POLL_BUSY\) return;/);
  assert.match(html, /PV_POLL_BUSY = true;/);
  assert.match(html, /finally \{ PV_POLL_BUSY = false; \}/);
  assert.match(html, /if\(!document\.hidden && PV_POLL_CHECK && currentScreenName === 'verifyPhone'\)/);
});
