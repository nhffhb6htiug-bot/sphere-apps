// Meta WhatsApp Cloud API webhook. Verification via challenge text sent FROM user's WhatsApp.
// Configure Meta GET callback with WA_VERIFY_TOKEN; POST requires WA_APP_SECRET HMAC.
import { createClient } from "npm:@supabase/supabase-js@2";

const utf8=new TextEncoder();
const hex=(v:Uint8Array)=>Array.from(v,b=>b.toString(16).padStart(2,"0")).join("");
async function hmacHex(secret:string,body:string){
 const key=await crypto.subtle.importKey("raw",utf8.encode(secret),{name:"HMAC",hash:"SHA-256"},false,["sign"]);
 return hex(new Uint8Array(await crypto.subtle.sign("HMAC",key,utf8.encode(body))));
}
async function sha(s:string){return hex(new Uint8Array(await crypto.subtle.digest("SHA-256",utf8.encode(s))));}
function same(a:string,b:string){
 if(a.length!==b.length)return false;
 let mismatch=0;for(let i=0;i<a.length;i++)mismatch|=a.charCodeAt(i)^b.charCodeAt(i);
 return mismatch===0;
}
Deno.serve(async req=>{
 const verifyToken=Deno.env.get("WA_VERIFY_TOKEN");
 const u=new URL(req.url);
 if(req.method==="GET"){
  const mode=u.searchParams.get("hub.mode");
  const token=u.searchParams.get("hub.verify_token");
  const challenge=u.searchParams.get("hub.challenge");
  if(mode==="subscribe"&&verifyToken&&token&&same(token,verifyToken)&&challenge)
    return new Response(challenge,{status:200,headers:{"Content-Type":"text/plain"}});
  return new Response("Forbidden",{status:403});
 }
 if(req.method!=="POST")return new Response("Method not allowed",{status:405});
 const appSecret=Deno.env.get("WA_APP_SECRET");
 const codeSecret=Deno.env.get("WA_CODE_SECRET");
 if(!appSecret||!codeSecret)return new Response("Unconfigured",{status:503});
 const signature=req.headers.get("x-hub-signature-256")||"";
 const raw=await req.text();
 const expected="sha256="+await hmacHex(appSecret,raw);
 if(!same(signature.toLowerCase(),expected))return new Response("Bad signature",{status:401});
 let data:any;
 try{data=JSON.parse(raw);}catch{return new Response("Invalid JSON",{status:400});}
 const supabaseUrl=Deno.env.get("SUPABASE_URL"),serviceKey=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
 if(!supabaseUrl||!serviceKey)return new Response("Unconfigured",{status:503});
 const admin=createClient(supabaseUrl,serviceKey,{auth:{persistSession:false}});
 const requiredPhoneId=Deno.env.get("WA_PHONE_NUMBER_ID");
 for(const entry of data.entry||[]){
  for(const change of entry.changes||[]){
   if(change.field!=="messages")continue;
   const value=change.value||{};
   if(requiredPhoneId&&String(value.metadata?.phone_number_id||"")!==requiredPhoneId)continue;
   for(const msg of value.messages||[]){
    if(msg.type!=="text")continue;
    const sender=String(msg.from||"").replace(/\D/g,"");
    if(!/^91[6-9][0-9]{9}$/.test(sender))continue;
    const body=String(msg.text?.body||"");
    const found=body.match(/\bSPH-[A-HJ-NP-Z2-9]{8}\b/i);
    if(!found)continue;
    const code=found[0].toUpperCase();
    const hashed=await sha(code+":"+codeSecret);
    const {error}=await admin.rpc("sp_wa_complete",{p_phone:sender,p_code_hash:hashed});
    if(error)console.error("WhatsApp verification database action failed",error.code);
   }
  }
 }
 return new Response("ok",{status:200,headers:{"Content-Type":"text/plain"}});
});
