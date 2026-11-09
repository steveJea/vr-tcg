// Staging-only Toss PAYMENT_STATUS_CHANGED receiver.
// Signature proves the sender. Payment status, amount, and player come only from a server GET.
// Official retry: no 200 within 10s retries after 1, 4, 16, 64, 256, 1024, 4096 minutes, at most 7 times.
// PAYMENT_STATUS_CHANGED has no eventId. transmission-id changes every send, so it is not an idempotency key.
export const STAGING='https://cuyqchmdcnsgzkwyclji.supabase.co';
const ORDER=/^vrs_[a-f0-9]{32}$/;
const SKEW_MS=10*60*1000;
const API_KEY=/^(?:test|live)_(?:sk|ck|gsk|gck)_/;
export const RETIRED_CLIENT_KEY='test_ck_D5GePWvyJnrK0W0k6q8gLzN97Eoq';
function envKey(env,plural,legacy){let keys;try{keys=JSON.parse(env[plural]||'{}');}catch{return null;}return keys.default||Object.values(keys)[0]||env[legacy];}
function b64(value){if(typeof value!=='string'||!/^[A-Za-z0-9+/]+={0,2}$/.test(value)||value.length%4===1)return null;let bin;try{bin=atob(value);}catch{return null;}const out=new Uint8Array(bin.length);for(let i=0;i<bin.length;i++)out[i]=bin.charCodeAt(i);return out;}
function same(a,b){if(!(a instanceof Uint8Array)||!(b instanceof Uint8Array)||a.length!==b.length)return false;let diff=0;for(let i=0;i<a.length;i++)diff|=a[i]^b[i];return diff===0;}
function sentAt(value){if(typeof value!=='string'||value.length<10||value.length>40)return NaN;if(/^\d{13}$/.test(value))return Number(value);if(/^\d{10}$/.test(value))return Number(value)*1000;if(!/(?:Z|[+-]\d{2}:\d{2})$/.test(value))return NaN;return Date.parse(value);}
export async function verifyTossWebhook(raw,time,signature,secret,now=Date.now()){
 if(typeof raw!=='string'||typeof secret!=='string'||secret.length<16||secret.length>200||/\s/.test(secret)||API_KEY.test(secret))return false;
 const sent=sentAt(time);if(!Number.isFinite(sent)||Math.abs(now-sent)>SKEW_MS)return false;
 if(typeof signature!=='string'||signature.length<8||signature.length>2048)return false;
 const key=await crypto.subtle.importKey('raw',new TextEncoder().encode(secret),{name:'HMAC',hash:'SHA-256'},false,['sign']);
 const mac=new Uint8Array(await crypto.subtle.sign('HMAC',key,new TextEncoder().encode(raw+':'+time)));
 for(const part of signature.split(',')){const token=part.trim();if(!token.startsWith('v1:'))continue;const decoded=b64(token.slice(3));if(same(mac,decoded))return true;}
 return false;
}
const minimalCancel=c=>c&&c.cancelStatus==='DONE'&&Number.isSafeInteger(c.cancelAmount)&&c.cancelAmount>0&&typeof c.transactionKey==='string'&&c.transactionKey.length>0&&c.transactionKey.length<=200&&typeof c.canceledAt==='string'&&Number.isFinite(Date.parse(c.canceledAt));
// Identity is checked against the stored order. The webhook JSON is not an input here.
export function providerSnapshot(p,order){
 if(!p||p.paymentKey!==order.payment_key||p.orderId!==order.order_id||p.currency!==order.currency||p.totalAmount!==order.amount||typeof p.mId!=='string'||!/^[A-Za-z0-9_-]{1,64}$/.test(p.mId)||!['카드','간편결제'].includes(p.method)||!Number.isSafeInteger(p.balanceAmount))return null;
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
   const secret=env.TOSS_SECRET_KEY,hook=env.TOSS_WEBHOOK_SECRET;
   if(typeof secret!=='string'||!/^test_sk_[A-Za-z0-9_]+$/.test(secret)||secret===RETIRED_CLIENT_KEY)return reply(503,{error:'test payment configuration required'});
   if(typeof hook!=='string'||hook.length<16||hook.length>200||/\s/.test(hook)||API_KEY.test(hook))return reply(503,{error:'test payment configuration required'});
   const service=envKey(env,'SUPABASE_SECRET_KEYS','SUPABASE_SERVICE_ROLE_KEY');
   if(!service)return reply(503,{error:'backend configuration'});
   const reader=req.body?.getReader();if(!reader)return reply(400,{error:'invalid request'});let size=0,parts=[];
   for(;;){const {value,done}=await reader.read();if(done)break;size+=value.length;if(size>65536){await reader.cancel();return reply(413,{error:'invalid request'});}parts.push(value);}
   const bytes=new Uint8Array(size);let at=0;for(const p of parts){bytes.set(p,at);at+=p.length;}
   const raw=new TextDecoder('utf-8',{fatal:true}).decode(bytes);
   const time=req.headers.get('tosspayments-webhook-transmission-time'),signature=req.headers.get('tosspayments-webhook-signature');
   if(!await verifyTossWebhook(raw,time,signature,hook))return reply(401,{error:'webhook signature'});
   let body;try{body=JSON.parse(raw);}catch{return reply(200,{ok:true,state:'ignored'});}
   if(!body||typeof body!=='object'||Array.isArray(body))return reply(200,{ok:true,state:'ignored'});
   if(body.eventType!=='PAYMENT_STATUS_CHANGED')return reply(200,{ok:true,state:'ignored'});
   const hinted=body.data&&typeof body.data==='object'&&!Array.isArray(body.data)?body.data.orderId:null;
   if(typeof hinted!=='string'||!ORDER.test(hinted))return reply(200,{ok:true,state:'ignored'});
   const request=(url,opts={})=>fetcher(url,{...opts,signal:controller.signal});
   const rpc=async(name,args)=>{
    const headers={'content-type':'application/json',apikey:service};if(!service.startsWith('sb_secret_'))headers.authorization='Bearer '+service;
    const r=await request(STAGING+'/rest/v1/rpc/'+name,{method:'POST',headers,body:JSON.stringify(args)});
    if(!r.ok){const e=await r.json().catch(()=>({}));const code=String(e.message).includes('payments unavailable')?'payment database unavailable':String(e.message).includes('payment mismatch')?'payment mismatch':'refund pending';throw Error(code);}return r.json();
   };
   stage='order';const order=await rpc('_payment_provider_key_v1',{p_order:hinted});
   if(!order||typeof order.payment_key!=='string')return reply(200,{ok:true,state:'ignored'});
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
  catch(e){const error=e.message==='payment mismatch'||e.message==='payment database unavailable'||e.message==='refund pending'?e.message:'refund pending';if(stage)console.warn(JSON.stringify({tag:'payments-webhook-v1',stage,code:error}));return reply(error==='payment database unavailable'?503:503,{error});}
  finally{clearTimeout(timer);}
 };
}
