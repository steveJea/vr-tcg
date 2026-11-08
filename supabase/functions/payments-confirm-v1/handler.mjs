// Staging-only test checkout. All privileged values come from env, never source.
export const STAGING='https://cuyqchmdcnsgzkwyclji.supabase.co';
const HOST='https://vr-tcg-staging.notcold.workers.dev';
export const TEST_CLIENT_KEY='test_ck_D5GePWvyJnrK0W0k6q8gLzN97Eoq'; // Official Toss sample; public identifier, NOT a secret.
const UUID=/^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i, ORDER=/^vrs_[a-f0-9]{32}$/;
const RPC_ERRORS=['order not found','order expired','payment mismatch','payment conflict','product unavailable','request conflict','rate limited','login required'];
const exact=(x,keys)=>x&&typeof x==='object'&&!Array.isArray(x)&&Object.keys(x).sort().join(',')===[...keys].sort().join(',');
export const validPayment=(p,o,key)=>p&&p.paymentKey===key&&p.orderId===o.order_id&&p.currency==='KRW'&&p.totalAmount===o.amount&&p.balanceAmount===o.amount&&p.status==='DONE'&&typeof p.approvedAt==='string'&&Number.isFinite(Date.parse(p.approvedAt))&&(!p.cancels||p.cancels.length===0)&&['카드','간편결제'].includes(p.method);
function envKey(env,plural,legacy){let keys;try{keys=JSON.parse(env[plural]||'{}');}catch{return null;}return keys.default||Object.values(keys)[0]||env[legacy];}
export function createHandler(env,fetcher=fetch,timeoutMs=9000) {
 return async req=>{
  const origin=req.headers.get('origin');
  const cors={'access-control-allow-origin':HOST,'access-control-allow-headers':'authorization, apikey, content-type, x-client-info','access-control-allow-methods':'POST, OPTIONS','vary':'Origin'};
  const reply=(status,body)=>new Response(JSON.stringify(body),{status,headers:{...cors,'content-type':'application/json','cache-control':'no-store'}});
  if(origin&&origin!==HOST)return reply(403,{error:'origin not allowed'});
  if(req.method==='OPTIONS')return new Response(null,{status:204,headers:cors});
  if(req.method!=='POST')return reply(405,{error:'POST required'});
  const controller=new AbortController();let timer,stage='request';
  // One bounded deadline includes body reads/Auth/REST/Toss/response JSON. Lost responses preserve the bound key and can retry.
  const work=async()=>{
   if(env.SUPABASE_URL!==STAGING)return reply(503,{error:'staging only'});
   const secret=env.TOSS_SECRET_KEY,clientKey=env.TOSS_CLIENT_KEY||TEST_CLIENT_KEY;
   if(typeof secret!=='string'||!/^test_sk_[A-Za-z0-9_]+$/.test(secret)||typeof clientKey!=='string'||!/^test_ck_[A-Za-z0-9_]+$/.test(clientKey))return reply(503,{error:'test payment configuration required'});
   const pub=envKey(env,'SUPABASE_PUBLISHABLE_KEYS','SUPABASE_ANON_KEY'),service=envKey(env,'SUPABASE_SECRET_KEYS','SUPABASE_SERVICE_ROLE_KEY');
   if(!pub||!service)return reply(503,{error:'backend configuration'});
   if(!/^application\/json(?:;|$)/i.test(req.headers.get('content-type')||''))return reply(400,{error:'invalid request'});
   const reader=req.body?.getReader();if(!reader)return reply(400,{error:'invalid request'});let size=0,parts=[];
   for(;;){const {value,done}=await reader.read();if(done)break;size+=value.length;if(size>4096){await reader.cancel();return reply(413,{error:'invalid request'});}parts.push(value);}
   const bytes=new Uint8Array(size);let at=0;for(const p of parts){bytes.set(p,at);at+=p.length;}let b;try{b=JSON.parse(new TextDecoder().decode(bytes));}catch{return reply(400,{error:'invalid request'});}
   if(b.op==='create') {if(!exact(b,['op','product','request'])||typeof b.product!=='string'||!/^gem_[0-9]+$/.test(b.product)||typeof b.request!=='string'||!UUID.test(b.request))return reply(400,{error:'invalid request'});}
   else if(b.op==='confirm') {if(!exact(b,['op','orderId','paymentKey','amount'])||typeof b.orderId!=='string'||!ORDER.test(b.orderId)||typeof b.paymentKey!=='string'||b.paymentKey.length<1||b.paymentKey.length>200||/[\x00-\x1f\x7f]/.test(b.paymentKey)||!Number.isSafeInteger(b.amount)||b.amount<100||b.amount>1000000)return reply(400,{error:'invalid request'});}
   else return reply(400,{error:'invalid request'});
   const token=req.headers.get('authorization');if(!/^Bearer \S+$/i.test(token||''))return reply(401,{error:'login required'});
   const request=(url,opts={})=>fetcher(url,{...opts,signal:controller.signal});
   stage='auth';const auth=await request(STAGING+'/auth/v1/user',{headers:{authorization:token,apikey:pub}});if(!auth.ok)return reply(401,{error:'login required'});
   const user=await auth.json();if(typeof user.id!=='string'||!UUID.test(user.id))return reply(401,{error:'login required'});
   const rpc=async(name,args,trusted=true)=>{
    const headers={'content-type':'application/json',apikey:trusted?service:pub};if(!trusted)headers.authorization=token;else if(!service.startsWith('sb_secret_'))headers.authorization='Bearer '+service;
    const r=await request(STAGING+'/rest/v1/rpc/'+name,{method:'POST',headers,body:JSON.stringify(args)});
    if(!r.ok){
     const e=await r.json().catch(()=>({}));
     const known=RPC_ERRORS.find(s=>String(e.message).includes(s));
     const code=known||(['PGRST202','42P01','42883','42703'].includes(e.code)?'payment sql required':e.code==='42501'?'payment database permissions':String(e.message).includes('payments unavailable')?'payment database unavailable':stage==='order'?'order creation failed':'payment confirmation pending');
     // Safe diagnostic: no token, keys, SQL text, account/order IDs, or provider payload.
     console.warn(JSON.stringify({tag:'payments-confirm-v1',stage,status:r.status,dbCode:/^[A-Z0-9_]{3,24}$/.test(e.code||'')?e.code:null,code}));
     throw Error(code);
    }return r.json();
   };
   if(b.op==='create') {
    stage='order';const o=await rpc('payment_create_v1',{p_product:b.product,p_request:b.request},false);
    return reply(200,{ok:true,order:{orderId:o.order_id,orderName:o.order_name,amount:o.amount,currency:o.currency,userId:user.id,paidGems:o.paid_gems,bonusGems:o.bonus_gems,status:o.status},clientKey});
   }
   stage='bind';const o=await rpc('_payment_bind_v1',{p_uid:user.id,p_order:b.orderId,p_key:b.paymentKey,p_amount:b.amount});
   if(o.status==='paid')return reply(200,o.receipt);
   stage='toss';const tossHeaders={authorization:'Basic '+btoa(secret+':'),'content-type':'application/json'};
   // Retrieval first also recovers a successful Toss approval followed by a lost HTTP/DB response.
   const get=()=>request('https://api.tosspayments.com/v1/payments/'+encodeURIComponent(b.paymentKey),{headers:tossHeaders});
   let r=await get(),p=await r.json().catch(()=>null);
   if(!(r.ok&&validPayment(p,o,b.paymentKey))) {
    if(r.ok&&p&&p.status!=='IN_PROGRESS'&&p.status!=='READY')return reply(409,{error:'payment not completed'});
    if(!r.ok&&r.status!==404)return reply(503,{error:'payment processing unavailable'});
    r=await request('https://api.tosspayments.com/v1/payments/confirm',{method:'POST',headers:{...tossHeaders,'Idempotency-Key':'vr-toss-'+o.order_id},body:JSON.stringify({paymentKey:b.paymentKey,orderId:o.order_id,amount:o.amount})});
    p=await r.json().catch(()=>null);
    if(!r.ok){r=await get();p=await r.json().catch(()=>null);}
   }
   if(!r.ok||!validPayment(p,o,b.paymentKey))return reply(409,{error:'payment not completed'});
   stage='settle';return reply(200,await rpc('_payment_settle_v1',{p_uid:user.id,p_order:o.order_id,p_key:p.paymentKey,p_amount:p.totalAmount,p_currency:p.currency,p_status:p.status,p_balance:p.balanceAmount,p_approved:p.approvedAt}));
  };
  try {return await Promise.race([work(),new Promise(resolve=>{timer=setTimeout(()=>{controller.abort();resolve(reply(504,{error:stage==='order'?'order creation delayed':'payment confirmation pending',stage}));},timeoutMs);})]);}
  catch(e){const allowed=[...RPC_ERRORS,'payment sql required','payment database permissions','payment database unavailable','order creation failed'];const error=allowed.includes(e.message)?e.message:stage==='order'?'order creation failed':'payment confirmation pending';return reply(error==='login required'?401:error.startsWith('payment sql')||error.startsWith('payment database')||error==='order creation failed'?503:409,{error,stage});}
  finally{clearTimeout(timer);}
 };
}
