// Visual UI unchanged. Pure synthetic browser tests without network or user data.
import assert from 'node:assert/strict';
import test from 'node:test';
import fs from 'node:fs';
import vm from 'node:vm';

const html = fs.readFileSync('index.html.html', 'utf8');
function between(a,b) {
  const start = html.indexOf(a); assert.ok(start>=0, 'missing '+a);
  const end=html.indexOf(b,start); assert.ok(end>start,'missing '+b);
  return html.slice(start,end);
}
const mediaSource=between('const SIGN_MAP = new Map();','/* ============ PART 20.1:');

function mediaTestHarness(opts={}) {
  let scheduled=[],observer=null,sequence=0, rpcCount=0, resolveRpc;
  let nodes=opts.nodes||[];
  const sb={storage:{from:()=>({
    createSignedUrls:async paths=>{
      rpcCount++;
      if(opts.delayed) return new Promise(resolve=>{resolveRpc=resolve});
      return {data:paths.map(p=>({path:p,signedUrl:'https://signed.example/'+p}))};
    }
  })}};
  const ctx={
    Map,Promise,Date,document:{body:{},querySelectorAll:()=>nodes},
    getCurrentUser:()=>({id:'user-one'}),sb,
    setTimeout:fn=>{const id=++sequence;scheduled.push({id,fn});return id;},
    clearTimeout:id=>{scheduled=scheduled.filter(x=>x.id!==id);},
    MutationObserver:class {constructor(fn){observer=fn}observe(){}}
  };
  vm.runInNewContext(mediaSource+`
    globalThis.__register=registerSigned;
    globalThis.__observe=signedMediaMutations;
    globalThis.__signed=SIGNED;
    globalThis.__map=SIGN_MAP;
    globalThis.__invalidate=()=>{ SIGN_SESSION_EPOCH++; SIGN_MAP.clear(); SIGNED.clear(); };
  `,ctx);
  return {ctx,registered:(bucket,path,url)=>ctx.__register(bucket,path,url),
    emit:nodes=>observer([{addedNodes:nodes}]), scheduled:()=>scheduled.length,
    flush:async()=>{const jobs=scheduled;scheduled=[];await Promise.all(jobs.map(j=>j.fn()));},
    count:()=>rpcCount, settle:result=>resolveRpc(result),
    setNodes:next=>nodes=next
  };
}

function fakeNode(type, selectorMatch=false) {
  return {nodeType:type,matches:()=>selectorMatch,querySelector:()=>null};
}

test('no media registered: unrelated DOM and new elements avoid all signing scans',()=>{
  const x=mediaTestHarness();
  x.emit([fakeNode(3),fakeNode(1,true)]);
  assert.equal(x.scheduled(),0);
  x.registered('private','image/path','original-url');
  assert.equal(x.scheduled(),1);
  x.emit([fakeNode(3),fakeNode(1,false)]);
  assert.equal(x.scheduled(),1,'unrelated elements do not add work');
});

test('new media and late media registration both update signed link without extra RPCs',async()=>{
  const img={
    nodeType:1,tagName:'IMG',src:'original-url',
    getAttribute(){return this.src},setAttribute(_,v){this.src=v},
    matches:()=>true,querySelector:()=>null
  };
  const x=mediaTestHarness({nodes:[img]});
  x.registered('private','image/path','original-url');
  await x.flush();
  assert.equal(img.src,'https://signed.example/image/path');
  assert.equal(x.count(),1);
  x.emit([fakeNode(1,false),fakeNode(3)]);
  assert.equal(x.scheduled(),0);
  x.emit([fakeNode(1,true)]);
  assert.equal(x.scheduled(),1);
  await x.flush();
  assert.equal(x.count(),1,'already signed media does not request a second URL');
});

test('private signing response arriving after logout is discarded',async()=>{
  const img={nodeType:1,tagName:'IMG',src:'old-url',
    getAttribute(){return this.src},setAttribute(_,value){this.src=value}};
  const x=mediaTestHarness({nodes:[img],delayed:true});
  x.registered('private','old/path','old-url');
  const pending=x.flush();
  await Promise.resolve();
  x.ctx.__invalidate();
  x.settle({data:[{path:'old/path',signedUrl:'https://signed.example/old/path'}]});
  await pending;
  assert.equal(x.ctx.__signed.size,0);
  assert.equal(img.src,'old-url');
});

function keyboardHarness(){
  let callback=null,navCalls=0,focuses=0,auth=true;
  const box={focus:()=>focuses++};
  const scope={
    document:{addEventListener:(type,fn)=>{if(type==='keydown')callback=fn},getElementById:()=>box},
    getCurrentUser:()=>auth?{id:'user-one'}:null,
    nav:async page=>{assert.equal(page,'searchAll');navCalls++},
    Promise
  };
  vm.runInNewContext(between('// Invisible keyboard add-on:', '// App-wide search:'),scope);
  const dispatch=async (key,target={closest:()=>null,isContentEditable:false},mods={})=>{
    const event={key,target,defaultPrevented:false,isComposing:false,altKey:false,ctrlKey:false,metaKey:false,shiftKey:false,preventDefault(){this.defaultPrevented=true},...mods};
    callback(event);
    await Promise.resolve();await Promise.resolve();
    return event;
  };
  return {dispatch,counts:()=>[navCalls,focuses],logout:()=>auth=false};
}
test('slash or Ctrl+K opens existing search, but slash cannot hijack typing',async()=>{
  const app=keyboardHarness();
  assert.equal((await app.dispatch('/')).defaultPrevented,true);
  assert.deepEqual(app.counts(),[1,1]);
  assert.equal((await app.dispatch('/',{closest:()=>({tagName:'INPUT'})})).defaultPrevented,false);
  assert.equal((await app.dispatch('/',{closest:()=>null,isContentEditable:true})).defaultPrevented,false);
  assert.deepEqual(app.counts(),[1,1]);
  assert.equal((await app.dispatch('k',undefined,{ctrlKey:true})).defaultPrevented,true);
  assert.deepEqual(app.counts(),[2,2]);
  app.logout();
  assert.equal((await app.dispatch('/')).defaultPrevented,false);
  assert.deepEqual(app.counts(),[2,2]);
});
