// Sphere WhatsApp verification: signed-in user requests a code and checks status.
// Deploy after applying migration 090; requires WA_BUSINESS_NUMBER, WA_CODE_SECRET.
import { createClient } from "npm:@supabase/supabase-js@2";

const allowed = (Deno.env.get("SPHERE_ALLOWED_ORIGINS") ||
  "https://sphere.syahi.online,https://sphere-live.onrender.com").split(",").map(s=>s.trim());
function headers(req: Request) {
  const origin = req.headers.get("Origin") || "";
  return {
    "Access-Control-Allow-Origin": allowed.includes(origin) ? origin : allowed[0],
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
    "Access-Control-Allow-Methods": "POST,OPTIONS",
    "Vary": "Origin",
    "Content-Type": "application/json",
    "Cache-Control": "no-store",
  };
}
const reply=(req:Request,obj:unknown,status=200)=>new Response(JSON.stringify(obj),{status,headers:headers(req)});
const sha=async(text:string)=>Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256",new TextEncoder().encode(text)))).map(b=>b.toString(16).padStart(2,"0")).join("");
const clean=(p:unknown)=>{
  let digits=String(p??"").replace(/\D/g,"");
  if(digits.length===10)digits="91"+digits;
  return /^91[6-9][0-9]{9}$/.test(digits)?digits:null;
};
Deno.serve(async(req)=>{
  if(req.method==="OPTIONS")return new Response(null,{status:204,headers:headers(req)});
  if(req.method!=="POST")return reply(req,{error:"Method not allowed"},405);
  const url=Deno.env.get("SUPABASE_URL"),key=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if(!url||!key)return reply(req,{error:"Server configuration missing"},503);
  const admin=createClient(url,key,{auth:{persistSession:false}});
  const token=(req.headers.get("Authorization")||"").replace(/^Bearer\s+/i,"");
  const {data:{user},error:authErr}=await admin.auth.getUser(token);
  if(authErr||!user)return reply(req,{error:"Please sign in"},401);
  let action="";
  try{action=String((await req.json()).action||"status");}catch{return reply(req,{error:"Invalid request"},400);}
  const {data:claim,error:claimErr}=await admin.from("sp_wa_phone_claims").select("phone_e164").eq("user_id",user.id).maybeSingle();
  if(claimErr)return reply(req,{error:"Database migration 090 is required"},503);
  if(action==="status")return reply(req,{verified:!!claim,phone:claim?.phone_e164?"+91••••••"+claim.phone_e164.slice(-4):null});
  if(action!=="start")return reply(req,{error:"Unknown action"},400);
  if(claim)return reply(req,{verified:true});
  const phone=clean((await admin.from("profiles").select("phone").eq("id",user.id).maybeSingle()).data?.phone ||
     user.user_metadata?.phone || user.phone);
  if(!phone)return reply(req,{error:"Add a valid Indian mobile number to your profile first"},400);
  const {data:other,error:otherErr}=await admin.from("sp_wa_phone_claims").select("user_id").eq("phone_e164",phone).maybeSingle();
  if(otherErr)return reply(req,{error:"Could not check number status"},503);
  if(other)return reply(req,{error:"This number is already linked to a verified Sphere account"},409);
  const business=clean(Deno.env.get("WA_BUSINESS_NUMBER"));
  const secret=Deno.env.get("WA_CODE_SECRET");
  if(!business||!secret||secret.length<32)return reply(req,{error:"Sphere WhatsApp verification is not configured yet"},503);
  const now=new Date();
  const {count,error:countErr}=await admin.from("sp_wa_request_log").select("id",{count:"exact",head:true})
    .eq("user_id",user.id).gte("created_at",new Date(now.getTime()-3600000).toISOString());
  if(countErr)return reply(req,{error:"Rate limit service unavailable"},503);
  if((count??0)>=3)return reply(req,{error:"Too many requests. Try again later."},429);
  const {data:old}=await admin.from("sp_wa_challenges").select("created_at").eq("user_id",user.id).maybeSingle();
  if(old&&Date.now()-new Date(old.created_at).getTime()<60000)
    return reply(req,{error:"Please wait one minute before requesting another code"},429);
  const alphabet="ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  const bytes=crypto.getRandomValues(new Uint8Array(8));
  const code="SPH-"+Array.from(bytes,b=>alphabet[b%alphabet.length]).join("");
  const codeHash=await sha(code+":"+secret);
  const expires=new Date(now.getTime()+10*60000).toISOString();
  const {error:saveErr}=await admin.from("sp_wa_challenges").upsert({
    user_id:user.id,phone_e164:phone,code_hash:codeHash,
    created_at:now.toISOString(),expires_at:expires,attempts:0,confirmed_at:null,
  },{onConflict:"user_id"});
  if(saveErr)return reply(req,{error:"Could not create verification challenge"},503);
  await admin.from("sp_wa_request_log").insert({user_id:user.id});
  const message="Sphere verification: "+code;
  return reply(req,{verified:false,code,expires_at:expires,
    whatsapp_url:"https://wa.me/"+business+"?text="+encodeURIComponent(message)});
});
