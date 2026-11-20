// Generated from handler.mjs; staging only; JWT verification ON.
// Staging-only test checkout. All privileged values come from env, never source.
export const STAGING='https://cuyqchmdcnsgzkwyclji.supabase.co';
const HOST='https://vr-tcg-staging.notcold.workers.dev';
// This formerly public example now returns UNAUTHORIZED_KEY. Never silently fall back to it.
export const RETIRED_CLIENT_KEY='test_ck_D5GePWvyJnrK0W0k6q8gLzN97Eoq';
const UUID=/^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i, ORDER=/^vrs_[a-f0-9]{32}$/;
const RPC_ERRORS=['order not found','order expired','payment mismatch','payment conflict','product unavailable','request conflict','rate limited','login required','forbidden','refund cs review','refund not eligible','refund pending','payment refunded','payment closed'];
const exact=(x,keys)=>x&&typeof x==='object'&&!Array.isArray(x)&&Object.keys(x).sort().join(',')===[...keys].sort().join(',');
export const validPayment=(p,o,key)=>p&&p.paymentKey===key&&p.orderId===o.order_id&&p.currency==='KRW'&&p.totalAmount===o.amount&&p.balanceAmount===o.amount&&p.status==='DONE'&&typeof p.approvedAt==='string'&&Number.isFinite(Date.parse(p.approvedAt))&&(!p.cancels||p.cancels.length===0)&&['카드','간편결제'].includes(p.method);
// Never accept a browser-supplied amount/key or a webhook assertion as cancellation proof.
export const validCancellation=(p,o)=>p&&p.paymentKey===o.payment_key&&p.orderId===o.order_id&&p.currency===o.currency&&p.totalAmount===o.amount&&p.balanceAmount===0&&p.status==='CANCELED'&&['카드','간편결제'].includes(p.method)&&Array.isArray(p.cancels)&&p.cancels.length>0&&p.cancels.length<=20&&p.cancels.every(c=>c.cancelStatus==='DONE'&&Number.isSafeInteger(c.cancelAmount)&&c.cancelAmount>0&&typeof c.transactionKey==='string'&&c.transactionKey.length>0&&c.transactionKey.length<=200&&typeof c.canceledAt==='string'&&Number.isFinite(Date.parse(c.canceledAt)))&&new Set(p.cancels.map(c=>c.transactionKey)).size===p.cancels.length&&p.cancels.reduce((n,c)=>n+c.cancelAmount,0)===o.amount;
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
   const secret=env.TOSS_SECRET_KEY,clientKey=env.TOSS_CLIENT_KEY;
   if(typeof secret!=='string'||!/^test_sk_[A-Za-z0-9_]+$/.test(secret)||typeof clientKey!=='string'||!/^test_ck_[A-Za-z0-9_]+$/.test(clientKey)||clientKey===RETIRED_CLIENT_KEY)return reply(503,{error:'test payment configuration required'});
   const pub=envKey(env,'SUPABASE_PUBLISHABLE_KEYS','SUPABASE_ANON_KEY'),service=envKey(env,'SUPABASE_SECRET_KEYS','SUPABASE_SERVICE_ROLE_KEY');
   if(!pub||!service)return reply(503,{error:'backend configuration'});
   if(!/^application\/json(?:;|$)/i.test(req.headers.get('content-type')||''))return reply(400,{error:'invalid request'});
   const reader=req.body?.getReader();if(!reader)return reply(400,{error:'invalid request'});let size=0,parts=[];
   for(;;){const {value,done}=await reader.read();if(done)break;size+=value.length;if(size>4096){await reader.cancel();return reply(413,{error:'invalid request'});}parts.push(value);}
   const bytes=new Uint8Array(size);let at=0;for(const p of parts){bytes.set(p,at);at+=p.length;}let b;try{b=JSON.parse(new TextDecoder().decode(bytes));}catch{return reply(400,{error:'invalid request'});}
   if(!b||typeof b!=='object'||Array.isArray(b))return reply(400,{error:'invalid request'});
   if(b.op==='create') {if(!exact(b,['op','product','request'])||typeof b.product!=='string'||!/^(gem_[0-9]+|pass_[123])$/.test(b.product)||typeof b.request!=='string'||!UUID.test(b.request))return reply(400,{error:'invalid request'});}
   else if(b.op==='confirm') {if(!exact(b,['op','orderId','paymentKey','amount'])||typeof b.orderId!=='string'||!ORDER.test(b.orderId)||typeof b.paymentKey!=='string'||b.paymentKey.length<1||b.paymentKey.length>200||/[\x00-\x1f\x7f]/.test(b.paymentKey)||!Number.isSafeInteger(b.amount)||b.amount<100||b.amount>1000000)return reply(400,{error:'invalid request'});}
   else if(b.op==='abandon') {if(!exact(b,['op','orderId','reason'])||!ORDER.test(b.orderId||'')||!['canceled','failed'].includes(b.reason))return reply(400,{error:'invalid request'});}
   else if(['refund','refund-status'].includes(b.op)) {if(!exact(b,['op','orderId'])||typeof b.orderId!=='string'||!ORDER.test(b.orderId))return reply(400,{error:'invalid request'});}
   else if(b.op==='orders') {if(!exact(b,['op']))return reply(400,{error:'invalid request'});}
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
   if(b.op==='abandon') {stage='abandon';return reply(200,await rpc('payment_abandon_v1',{p_order:b.orderId,p_reason:b.reason},false));}
   if(['orders','refund','refund-status'].includes(b.op)) {
    stage='admin';const admin=await rpc('admin_check',{},false);if(admin?.admin!==true)return reply(403,{error:'forbidden'});
    if(b.op==='orders')return reply(200,await rpc('admin_payment_orders_v1',{},false));
    stage='refund-prepare';const ticket=await rpc(b.op==='refund'?'admin_payment_refund_prepare_v1':'admin_payment_refund_lookup_v1',{p_order:b.orderId},false);
    const o=ticket.order,hold=ticket.refund;
    if(!hold)return reply(409,{error:'refund not eligible'});
    if(hold.state==='refunded')return reply(200,hold.receipt);
    const note=async(error)=>{try{await rpc('_payment_refund_note_v1',{p_order:o.order_id,p_error:error});}catch{}};
    const headers={authorization:'Basic '+btoa(secret+':'),'content-type':'application/json'},url='https://api.tosspayments.com/v1/payments/'+encodeURIComponent(o.payment_key);
    const get=async()=>{const r=await request(url,{headers});return {r,p:await r.json().catch(()=>null)};};
    const finish=async(p)=>rpc('_payment_refund_finish_v1',{p_order:o.order_id,p_key:p.paymentKey,p_amount:p.totalAmount,p_currency:p.currency,p_status:p.status,p_balance:p.balanceAmount,p_cancels:p.cancels.map(c=>({cancelAmount:c.cancelAmount,cancelStatus:c.cancelStatus,canceledAt:c.canceledAt,transactionKey:c.transactionKey}))});
    stage='refund-read';let {r,p}=await get();
    if(r.ok&&validCancellation(p,o))return reply(200,await finish(p));
    const unchanged=()=>r.ok&&p&&p.paymentKey===o.payment_key&&p.orderId===o.order_id&&p.currency===o.currency&&p.totalAmount===o.amount&&p.balanceAmount===o.amount&&p.status==='DONE'&&['카드','간편결제'].includes(p.method)&&(!p.cancels||p.cancels.length===0);
    if(!unchanged()){await note(r.ok?'provider mismatch':'provider unavailable');return reply(409,{error:'refund pending'});}
    if(b.op==='refund-status')return reply(200,{ok:true,state:'processing',orderId:o.order_id});
    // No automatic POST after review or after the provider's idempotency retention window.
    if(hold.state==='review'||!Number.isFinite(Date.parse(hold.created_at))||Date.now()-Date.parse(hold.created_at)>14*86400000){await note('provider mismatch');return reply(409,{error:'refund cs review'});}
    stage='refund-cancel';
    // Reserve a separate short POST deadline so a lost/late response can be re-fetched
    // in this invocation, without aborting the outer Auth/DB/reconciliation deadline.
    const cancelController=new AbortController(),abort=()=>cancelController.abort();controller.signal.addEventListener('abort',abort,{once:true});let cancelTimer;
    try{await Promise.race([(async()=>{const result=await fetcher(url+'/cancel',{method:'POST',headers:{...headers,'Idempotency-Key':hold.idempotency_key},body:JSON.stringify({cancelReason:'미사용 상품 청약철회',cancelAmount:o.amount,refundableAmount:o.amount,currency:o.currency}),signal:cancelController.signal});await result.text();})(),new Promise((_,reject)=>{cancelTimer=setTimeout(()=>{cancelController.abort();reject(Error('refund pending'));},Math.min(2500,timeoutMs/3));})]);}catch{}finally{clearTimeout(cancelTimer);controller.signal.removeEventListener('abort',abort);}
    stage='refund-reconcile';({r,p}=await get());
    if(r.ok&&validCancellation(p,o))return reply(200,await finish(p));
    await note(r.ok&&!unchanged()?'provider mismatch':'refund pending');
    return reply(409,{error:'refund pending'}); // Never release held gems on an ambiguous PG result.
   }
   if(b.op==='create') {
    stage='order';const o=await rpc('payment_create_v1',{p_product:b.product,p_request:b.request},false);
    return reply(200,{ok:true,order:{orderId:o.order_id,orderName:o.order_name,amount:o.amount,currency:o.currency,userId:user.id,paidGems:o.paid_gems,bonusGems:o.bonus_gems,status:o.checkout_status&&o.checkout_status!=='open'?o.checkout_status:o.cancel_status&&o.cancel_status!=='none'?'refunded':o.status},clientKey});
   }
   stage='bind';const o=await rpc('_payment_bind_v1',{p_uid:user.id,p_order:b.orderId,p_key:b.paymentKey,p_amount:b.amount});
   if(o.cancel_status&&o.cancel_status!=='none')return reply(409,{error:'payment refunded'});
   if(o.checkout_status&&o.checkout_status!=='open')return reply(409,{error:'payment closed'});
   if(o.status==='paid')return reply(200,o.receipt);
   stage='toss';const tossHeaders={authorization:'Basic '+btoa(secret+':'),'content-type':'application/json'};
   // Retrieval first also recovers a successful Toss approval followed by a lost HTTP/DB response.
   const get=()=>request('https://api.tosspayments.com/v1/payments/'+encodeURIComponent(b.paymentKey),{headers:tossHeaders});
   let r=await get(),p=await r.json().catch(()=>null);
   if(!(r.ok&&validPayment(p,o,b.paymentKey))) {
    if(r.ok&&p&&p.status!=='IN_PROGRESS'&&p.status!=='READY')return reply(409,{error:'payment not completed'});
    if(r.status===401)return reply(503,{error:'test payment configuration required'});
    if(!r.ok&&r.status!==404)return reply(503,{error:'payment processing unavailable'});
    r=await request('https://api.tosspayments.com/v1/payments/confirm',{method:'POST',headers:{...tossHeaders,'Idempotency-Key':'vr-toss-'+o.order_id},body:JSON.stringify({paymentKey:b.paymentKey,orderId:o.order_id,amount:o.amount})});
    p=await r.json().catch(()=>null);
    if(!r.ok){r=await get();p=await r.json().catch(()=>null);}
   }
   if(r.status===401)return reply(503,{error:'test payment configuration required'});
   if(!r.ok||!validPayment(p,o,b.paymentKey))return reply(409,{error:'payment not completed'});
   stage='settle';const receipt=await rpc('_payment_settle_v1',{p_uid:user.id,p_order:o.order_id,p_key:p.paymentKey,p_amount:p.totalAmount,p_currency:p.currency,p_status:p.status,p_balance:p.balanceAmount,p_approved:p.approvedAt});
   // Payment.secret is the documented payment-status webhook check. It is not returned to the browser.
   const webhookSecret=typeof p.secret==='string'&&p.secret.length>=1&&p.secret.length<=50&&!/[\u0000-\u001f\u007f]/.test(p.secret)?p.secret:null;
   if(webhookSecret){try{await rpc('_payment_remember_secret_v1',{p_order:o.order_id,p_key:p.paymentKey,p_secret:webhookSecret});}catch{console.warn(JSON.stringify({tag:'payments-confirm-v1',stage:'webhook-secret',code:'not stored'}));}}
   return reply(200,receipt);
  };
  try {return await Promise.race([work(),new Promise(resolve=>{timer=setTimeout(()=>{controller.abort();resolve(reply(504,{error:stage.startsWith('refund')?'refund pending':stage==='order'?'order creation delayed':'payment confirmation pending',stage}));},timeoutMs);})]);}
  catch(e){const allowed=[...RPC_ERRORS,'payment sql required','payment database permissions','payment database unavailable','order creation failed'];const error=allowed.includes(e.message)?e.message:stage.startsWith('refund')?'refund pending':stage==='order'?'order creation failed':'payment confirmation pending';return reply(error==='forbidden'?403:error==='login required'?401:error.startsWith('payment sql')||error.startsWith('payment database')||error==='order creation failed'?503:409,{error,stage});}
  finally{clearTimeout(timer);}
 };
}

Deno.serve(createHandler(Deno.env.toObject()));
