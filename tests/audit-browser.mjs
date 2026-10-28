// Browser-engine UI smoke tests with no real user logins or payments.
// Chromium: Android + desktop-like rendering; WebKit: Safari-like rendering.
// This is NOT a substitute for tests on physical iPhone/Android hardware.
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { chromium, webkit } from "playwright";

const root=path.resolve(".");
const baseDir=path.join(root,"tests","audit-screenshots");
fs.mkdirSync(baseDir,{recursive:true});
const mime={".html":"text/html; charset=utf-8",".js":"text/javascript",".webp":"image/webp",
 ".png":"image/png",".svg":"image/svg+xml",".css":"text/css",".json":"application/json",
 ".ico":"image/x-icon",".woff2":"font/woff2",".jpg":"image/jpeg"};
const server=http.createServer((req,res)=>{
 let p;
 try{p=decodeURIComponent(new URL(req.url,"http://localhost").pathname);}catch{res.writeHead(400).end();return;}
 const full=path.resolve(root,"."+p);
 if(!(full===root||full.startsWith(root+path.sep))){res.writeHead(403).end();return;}
 let target=full===root?path.join(root,"index.html.html"):full;
 try{
  const data=fs.readFileSync(target);
  res.writeHead(200,{"Content-Type":mime[path.extname(target)]||"application/octet-stream","Cache-Control":"no-store"});
  res.end(data);
 }catch{res.writeHead(404).end("Not found");}
});
await new Promise(resolve=>server.listen(0,"127.0.0.1",resolve));
const addr=server.address();
const origin="http://127.0.0.1:"+addr.port;
const cases=[
 {name:"android-360",engine:chromium,width:360,height:740,ua:"Mozilla/5.0 (Linux; Android 13; Pixel 6a) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Mobile Safari/537.36",touch:true},
 {name:"android-412",engine:chromium,width:412,height:915,ua:"Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Mobile Safari/537.36",touch:true},
 {name:"safari-375",engine:webkit,width:375,height:667,ua:"Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",touch:true},
 {name:"safari-390",engine:webkit,width:390,height:844,ua:"Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",touch:true},
 {name:"ipad-webkit",engine:webkit,width:820,height:1180,touch:true},
 {name:"desktop-small",engine:chromium,width:1024,height:768,touch:false},
 {name:"desktop-1366",engine:chromium,width:1366,height:768,touch:false},
 {name:"desktop-1920",engine:chromium,width:1920,height:1080,touch:false}
];
const report=[];
let failure=false;
try{
 for(const v of cases){
  const browser=await v.engine.launch({headless:true});
  try{
   const context=await browser.newContext({viewport:{width:v.width,height:v.height},userAgent:v.ua,isMobile:v.touch&&v.width<600,hasTouch:v.touch,serviceWorkers:"block"});
   const page=await context.newPage();
   const uncaught=[];
   page.on("pageerror",err=>uncaught.push(String(err)));
   // No real accounts, payment requests, messages, or admin operations.
   await page.route(/https?:\/\/(?!127\.0\.0\.1)/, route=>route.abort());
   await page.goto(origin+"/index.html.html",{waitUntil:"domcontentloaded",timeout:20000});
   await page.waitForTimeout(1000);
   await page.evaluate(()=>{if(typeof window.nav==="function") window.nav("authLanding")}).catch(()=>{});
   await page.waitForTimeout(900);
   const state=await page.evaluate(()=>({
     text:(document.body?.innerText||"").slice(0,400),
     bodyLength:document.body?.innerText?.trim()?.length||0,
     documentWidth:document.documentElement.scrollWidth,
     viewportWidth:document.documentElement.clientWidth,
     buttons:[...document.querySelectorAll("button")].filter(b=>b.getBoundingClientRect().width>0).length
   }));
   await page.screenshot({path:path.join(baseDir,v.name+".png"),fullPage:false,timeout:8000});
   const overflow=Math.max(0,state.documentWidth-state.viewportWidth);
   const passed=state.bodyLength>15 && overflow<=12 && uncaught.length===0;
   if(!passed)failure=true;
   report.push({name:v.name,engine:v.engine.name(),viewport:[v.width,v.height],...state,overflow,uncaught:uncaught.slice(0,6),passed});
   await context.close();
  }catch(e){failure=true;report.push({name:v.name,passed:false,error:String(e).slice(0,450)});}
  finally{await browser.close();}
 }
}finally{server.close();}
fs.writeFileSync(path.join(baseDir,"report.json"),JSON.stringify(report,null,2));
for(const x of report)console.log((x.passed?"PASS":"FAIL"),x.name,JSON.stringify({overflow:x.overflow,bodyLength:x.bodyLength,error:x.error||x.uncaught}));
if(failure) process.exitCode=1;
