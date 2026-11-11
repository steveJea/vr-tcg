// Staging-only PAYMENT_STATUS_CHANGED receiver.
// Ordinary payment webhooks are authenticated by Payment.secret saved from the server-side
// approval response, then by a fresh GET. HMAC headers are not required: current docs limit
// signatures to webhooks that support them, and do not show that this event sends one.
// Retries without HTTP 200: 1, 4, 16, 64, 256, 1024, 4096 minutes, at most 7.
// This event has no eventId. transmission-id changes every send and is not an idempotency key.
export const STAGING='https://cuyqchmdcnsgzkwyclji.supabase.co';
const ORDER=/^vrs_[a-f0-9]{32}$/;
export const RETIRED_CLIENT_KEY='test_ck_D5GePWvyJnrK0W0k6q8gLzN97Eoq';
function envKey(env,plural,legacy){let keys;try{keys=JSON.parse(env[plural]||'{}');}catch{return null;}return keys.default||Object.values(keys)[0]||env[legacy];}
function same(a,b){const x=new TextEncoder().encode(String(a)),y=new TextEncoder().encode(String(b));if(x.length!==y.length)return false;let diff=0;for(let i=0;i<x.length;i++)diff|=x[i]^y[i];return diff===0;}
export function paymentSecret(value){return typeof value==='string'&&value.length>=1&&value.length<=50&&!/[\u0000-\u001f\u007f]/.test(value)?value:null;}
const minimalCancel=c=>c&&c.cancelStatus==='DONE'&&Number.isSafeInteger(c.cancelAmount)&&c.cancelAmount>0&&typeof c.transactionKey==='string'&&c.transactionKey.length>0&&c.transactionKey.length<=200&&typeof c.canceledAt==='string'&&Number.isFinite(Date.parse(c.canceledAt));
// Identity and current status come from the Toss GET. A present GET secret must match the stored approval secret.
export function providerSnapshot(p,order){
 if(!p||p.paymentKey!==order.payment_key||p.orderId!==order.order_id||p.currency!==order.currency||p.totalAmount!==order.amount||typeof p.mId!=='string'||!/^[A-Za-z0-9_-]{1,64}$/.test(p.mId)||!['카드','간편결제'].includes(p.method)||!Number.isSafeInteger(p.balanceAmount))return null;
 if(typeof p.secret==='string'&&p.secret.length&&!same(p.secret,order.secret))return null;
 const cancels=Array.isArray(p.cancels)?p.cancels:[];
 if(p.status==='DONE'&&p.balanceAmount===order.amount&&cancels.length===0)return {kind:'open',mid:p.mId,balance:p.balanceAmount,cancels:[]};
 if(cancels.length<1||cancels.length>20||!cancels.every(minimalCancel)||new Set(cancels.map(c=>c.transactionKey)).size!==cancels.length)return null;
 const sum=cancels.reduce((n,c)=>n+c.cancelAmount,0),slim=cancels.map(c=>({cancelAmount:c.cancelAmount,cancelStatus:c.cancelStatus,canceledAt:c.canceledAt,transactionKey:c.transactionKey}));
 if(p.status==='CANCELED'&&p.balanceAmount===0&&sum===order.amount)return {kind:'full',mid:p.mId,balance:0,cancels:slim};
 if(p.status==='PARTIAL_CANCELED'&&p.balanceAmount>0&&p.balanceAmount<order.amount&&sum===order.amount-p.balanceAmount)return {kind:'partial',mid:p.mId,balance:p.balanceAmount,cancels:slim};
 return null;
}
export function createHandler(env,fetcher=fetch,timeoutMs=8000){
 return async req=>{
  const reply=(status,body)=>new Response(JSON.stringify(body),{status,headers:{'content-type':'application/json','cache-control':'no-store'}});
  if(req.method!=='POST')return reply(405,{error:'POST required'});
  const controller=new AbortController();let timer,stage='request';
  const work=async()=>{
   if(env.SUPABASE_URL!==STAGING)return reply(503,{error:'staging only'});
   const secret=env.TOSS_SECRET_KEY;
   if(typeof secret!=='string'||!/^test_sk_[A-Za-z0-9_]+$/.test(secret)||secret===RETIRED_CLIENT_KEY)return reply(503,{error:'test payment configuration required'});
   const service=envKey(env,'SUPABASE_SECRET_KEYS','SUPABASE_SERVICE_ROLE_KEY');
   if(!service)return reply(503,{error:'backend configuration'});
   const reader=req.body?.getReader();if(!reader)return reply(400,{error:'invalid request'});let size=0,parts=[];
   for(;;){const {value,done}=await reader.read();if(done)break;size+=value.length;if(size>65536){await reader.cancel();return reply(413,{error:'invalid request'});}parts.push(value);}
   const bytes=new Uint8Array(size);let at=0;for(const part of parts){bytes.set(part,at);at+=part.length;}
   let raw;try{raw=new TextDecoder('utf-8',{fatal:true}).decode(bytes);}catch{return reply(200,{ok:true,state:'ignored'});}
   let body;try{body=JSON.parse(raw);}catch{return reply(200,{ok:true,state:'ignored'});}
   if(!body||typeof body!=='object'||Array.isArray(body)||body.eventType!=='PAYMENT_STATUS_CHANGED')return reply(200,{ok:true,state:'ignored'});
   const data=body.data&&typeof body.data==='object'&&!Array.isArray(body.data)?body.data:null;
   const hinted=data&&typeof data.orderId==='string'?data.orderId:null;
   if(!hinted||!ORDER.test(hinted))return reply(200,{ok:true,state:'ignored'});
   const presented=paymentSecret(data.secret);
   if(!presented)return reply(401,{error:'webhook secret'});
   const request=(url,opts={})=>fetcher(url,{...opts,signal:controller.signal});
   const rpc=async(name,args)=>{
    const headers={'content-type':'application/json',apikey:service};if(!service.startsWith('sb_secret_'))headers.authorization='Bearer '+service;
    const r=await request(STAGING+'/rest/v1/rpc/'+name,{method:'POST',headers,body:JSON.stringify(args)});
    if(!r.ok){const e=await r.json().catch(()=>({}));const code=String(e.message).includes('payments unavailable')?'payment database unavailable':String(e.message).includes('payment mismatch')?'payment mismatch':'refund pending';throw Error(code);}return r.json();
   };
   stage='order';const order=await rpc('_payment_provider_key_v1',{p_order:hinted});
   if(!order||typeof order.payment_key!=='string'||!paymentSecret(order.secret))return reply(200,{ok:true,state:'ignored'});
   if(!same(presented,order.secret))return reply(401,{error:'webhook secret'});
   if(typeof data.paymentKey==='string'&&data.paymentKey!==order.payment_key)return reply(401,{error:'webhook secret'});
   stage='toss';const headers={authorization:'Basic '+btoa(secret+':')};
   const got=await request('https://api.tosspayments.com/v1/payments/'+encodeURIComponent(order.payment_key),{headers});
   const payment=await got.json().catch(()=>null);
   if(got.status===401)return reply(503,{error:'test payment configuration required'});
   if(!got.ok||!payment)return reply(503,{error:'refund pending'});
   const snap=providerSnapshot(payment,order);
   if(!snap)return reply(503,{error:'refund pending'});
   stage='reconcile';const result=await rpc('_payment_external_reconcile_v1',{p_order:order.order_id,p_key:order.payment_key,p_amount:order.amount,p_currency:order.currency,p_status:snap.kind==='open'?'DONE':snap.kind==='full'?'CANCELED':'PARTIAL_CANCELED',p_balance:snap.balance,p_cancels:snap.cancels,p_mid:snap.mid});
   if(result?.retry===true)return reply(503,{error:'refund pending'});
   if(result?.ok===true&&['open','ignored','refunded','review','processing'].includes(result.state))return reply(200,{ok:true,state:result.state});
   return reply(503,{error:'refund pending'});
  };
  try{return await Promise.race([work(),new Promise(resolve=>{timer=setTimeout(()=>{controller.abort();resolve(reply(503,{error:'refund pending'}));},timeoutMs);})]);}
  catch(e){const error=e.message==='payment mismatch'||e.message==='payment database unavailable'||e.message==='refund pending'?e.message:'refund pending';console.warn(JSON.stringify({tag:'payments-webhook-v1',stage,code:error}));return reply(503,{error});}
  finally{clearTimeout(timer);}
 };
}
