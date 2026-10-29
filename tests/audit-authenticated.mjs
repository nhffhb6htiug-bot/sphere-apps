// Logged-in route smoke tests: entirely synthetic Supabase data, no real credentials,
// payments, messages, or production writes. Chromium Android/PC + WebKit iPhone.
import { chromium, webkit } from 'playwright';
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';

const root = path.resolve('.');
const fixture = fs.readFileSync('tests/browser/fixtures/chat_mock.js','utf8');
const folder = path.join(root,'tests','audit-screenshots');
fs.mkdirSync(folder,{recursive:true});
const mime={'.html':'text/html','.js':'text/javascript','.json':'application/json',
 '.webp':'image/webp','.svg':'image/svg+xml','.png':'image/png','.css':'text/css'};
const server=http.createServer((req,res)=>{
  let u;try{u=new URL(req.url,'http://localhost');}catch{return res.writeHead(400).end();}
  let name;try{name=decodeURIComponent(u.pathname)}catch{return res.writeHead(400).end();}
  const target=path.resolve(root,'.'+name);
  if(!target.startsWith(root+path.sep)&&target!==root)return res.writeHead(403).end();
  const file=target===root?path.join(root,'index.html.html'):target;
  try{res.writeHead(200,{'Content-Type':mime[path.extname(file)]||'application/octet-stream',
     'Cache-Control':'no-store'});res.end(fs.readFileSync(file));}
  catch{res.writeHead(404).end('Not found')}
});
await new Promise(ok=>server.listen(0,'127.0.0.1',ok));
const origin='http://127.0.0.1:'+server.address().port;
const profiles={
 client:{id:'me-111',name:'Client QA',role:'client',baseRole:'client',phone:'+919812345678',email:'test-client@example.invalid'},
 editor:{id:'ed-777',name:'Editor QA',role:'editor',baseRole:'editor',phone:'+919812345678',email:'test-editor@example.invalid',verified:true,categories:['Vlog Editing'],languages:['English']},
 admin:{id:'ad-999',name:'Admin QA',role:'admin',baseRole:'admin',phone:'+919812345678',email:'test-admin@example.invalid'}
};
const matrix=[
 {name:'android-client',browser:chromium,w:360,h:780,role:'client'},
 {name:'android-editor',browser:chromium,w:412,h:860,role:'editor'},
 {name:'safari-client',browser:webkit,w:390,h:844,role:'client'},
 {name:'safari-editor',browser:webkit,w:375,h:812,role:'editor'},
 {name:'desktop-client',browser:chromium,w:1366,h:768,role:'client'},
 {name:'desktop-admin',browser:chromium,w:1440,h:900,role:'admin'}
];
const routes=['home','jobs','chatList','profile','notifications','support','settingsScreen','searchAll'];
const results=[];let hasFailures=false;
try{
 for(const entry of matrix){
  const browser=await entry.browser.launch({headless:true});
  try{
   const context=await browser.newContext({viewport:{width:entry.w,height:entry.h},
     hasTouch:entry.w<600,isMobile:entry.w<600,serviceWorkers:'block'});
   const page=await context.newPage();
   let errors=[];
   page.on('pageerror',e=>errors.push(String(e).slice(0,300)));
   page.on('dialog',d=>d.dismiss().catch(()=>{}));
   // All external calls blocked. The fixture handles Supabase queries in memory.
   await page.route(/https?:\/\/(?!127\.0\.0\.1)/,r=>r.abort());
   await page.goto(origin+'/',{waitUntil:'domcontentloaded'});
   await page.waitForTimeout(1550); // allow splash transition before mock is installed
   await page.evaluate(fixture);
   await page.evaluate((profile)=>{
     currentUser=profile; pendingAuthUser=null; ADMIN_PIN='test-only';
     window.alert=()=>{};window.confirm=()=>false;
     // No phone verification bypass is changed in production. Mock gates only.
     phoneVerifyStatus=async()=>({required:false,verified:true});
     SCREEN_CACHE.clear();
   },profiles[entry.role]);
   for(const route of routes){
     const before=errors.length;
     let thrown=null;try{await page.evaluate(async r=>await nav(r),route)}
       catch(e){thrown=String(e).slice(0,300)}
     await page.waitForTimeout(100);
     const state=await page.evaluate(()=>({
       route:currentScreenName,
       text:(document.querySelector('#app')?.innerText||'').trim().slice(0,220),
       width:document.documentElement.scrollWidth,
       viewport:document.documentElement.clientWidth
     }));
     const ok=!thrown&&errors.length===before&&state.text.length>=10
       &&state.width<=state.viewport+16
       &&!['authLanding','login','verifyPhone'].includes(state.route);
     if(!ok)hasFailures=true;
     results.push({device:entry.name,role:entry.role,requested:route,actual:state.route,
       ok,thrown,errors:errors.slice(before, before+2),textLength:state.text.length,
       overflow:state.width-state.viewport});
     if(route==='home'){
       await page.screenshot({path:path.join(folder,entry.name+'-logged-in.png'),
         timeout:8000}).catch(()=>{});
     }
   }
   await context.close();
  }catch(e){hasFailures=true;results.push({device:entry.name,ok:false,error:String(e).slice(0,450)});}
  finally{await browser.close()}
 }
}finally{server.close()}
fs.writeFileSync(path.join(folder,'logged-in-report.json'),JSON.stringify(results,null,2));
for(const row of results)console.log((row.ok?'PASS':'FAIL'),row.device,row.requested||'startup',
  '→',row.actual||'?',row.thrown||row.errors?.[0]||row.error||'');
console.log('Logged-in routes:',results.filter(x=>x.ok).length,'/',results.length);
if(hasFailures)process.exitCode=1;
