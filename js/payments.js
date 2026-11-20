import {config} from './config.js';
import {enabled,api,paymentError,savePending,loadPending,pendingKey,checkoutParams,sdkErrorCode,sdkFailure,RETIRED_TOSS_CLIENT_KEY} from './payments-core.js';
const on=enabled(config),toast=t=>window.VRGem?.toast?.(t);let sdk,buying=false;
async function startCheckout(p,c,uid){
 let intent=loadPending(localStorage,uid);
 if(intent?.paymentKey)throw Error('payment confirmation pending');
 if(!intent||intent.product!==p.id){intent={product:p.id,request:crypto.randomUUID()};savePending(localStorage,uid,intent);}
 const result=await api(c.sb,config,{op:'create',product:p.id,request:intent.request}),o=result.order;
 if(c.user?.id!==uid)throw Error('login required');
 if(['canceled','failed','expired','refunded'].includes(o.status)){localStorage.removeItem(pendingKey(uid));throw Error(o.status==='refunded'?'payment refunded':'payment closed');}
 if(o.status==='paid'){localStorage.removeItem(pendingKey(uid));toast('이미 충전된 주문이에요.');return;}
 if(o.userId!==uid)throw Error('payment mismatch');
 if(typeof result.clientKey!=='string'||!/^test_ck_[A-Za-z0-9_]+$/.test(result.clientKey)||result.clientKey===RETIRED_TOSS_CLIENT_KEY)throw Error('test payment configuration required');
 intent={...intent,orderId:o.orderId,amount:o.amount};savePending(localStorage,uid,intent);localStorage.setItem('vrTcg.toss.order.v1:'+o.orderId,JSON.stringify({uid,amount:o.amount}));
 const Toss=await loadSDK(result.clientKey);if(c.user?.id!==uid)throw Error('login required');
 let phase='sdk-init';
 try{
  const params=checkoutParams(o,uid,location.origin);
  if(typeof Toss!=='function')throw Error('sdk:SDK_VERSION_MISMATCH');
  const payment=Toss(result.clientKey);if(typeof payment?.payment!=='function')throw Error('sdk:SDK_VERSION_MISMATCH');
  const session=payment.payment({customerKey:uid});if(typeof session?.requestPayment!=='function')throw Error('sdk:SDK_VERSION_MISMATCH');
  phase='checkout';await session.requestPayment(params);
 }catch(e){
  if(c.user?.id===uid)try{
   const reason=['USER_CANCEL','PAY_PROCESS_CANCELED','PAYMENT_REQUEST_ABORTED'].includes(sdkErrorCode(e))?'canceled':'failed';
   const ended=await api(c.sb,config,{op:'abandon',orderId:o.orderId,reason});
   if(['canceled','failed','expired'].includes(ended.state)){
    const current=loadPending(localStorage,uid);if(current?.orderId===o.orderId&&!current.paymentKey)localStorage.removeItem(pendingKey(uid));
    localStorage.removeItem('vrTcg.toss.order.v1:'+o.orderId);
   }
  }catch{}
  throw sdkFailure(e,phase,result.clientKey);
 }
}
function failCheckout(e,uid){if(['payment refunded','payment closed','order expired'].includes(e?.message)&&window.VRCloud?.user?.id===uid)localStorage.removeItem(pendingKey(uid));toast(paymentError(e?.code||e?.message,e?.sdkMessage));}
const deadline=async(p,ms=10000)=>{let t;try{return await Promise.race([p,new Promise((_,r)=>{t=setTimeout(()=>r(Error('payment confirmation pending')),ms);})]);}finally{clearTimeout(t);}};
async function loadSDK(clientKey){try{if(window.TossPayments)return Promise.resolve(window.TossPayments);if(!sdk)sdk=new Promise((resolve,reject)=>{const s=document.createElement('script');s.src='https://js.tosspayments.com/v2/standard';s.onload=()=>window.TossPayments?resolve(window.TossPayments):reject(Error('sdk'));s.onerror=()=>reject(Error('sdk'));document.head.appendChild(s);}).catch(e=>{sdk=null;throw e;});return await deadline(sdk);}catch(e){sdk=null;throw sdkFailure({code:'SDK_LOAD_FAILED',message:e?.message,stack:e?.stack},'sdk-load',clientKey);}}
async function open(){
 if(!on)return;
 const c=window.VRCloud,uid=c?.user?.id;if(!c?.sb||!uid)return toast('로그인이 필요해요.');
 document.querySelector('[data-payment-modal]')?.remove();const modal=document.createElement('div');modal.className='gem-pop payment-pop';modal.dataset.paymentModal='1';modal.setAttribute('data-clarity-mask','true');
 const panel=document.createElement('div');panel.className='gem-panel';panel.setAttribute('data-clarity-mask','true');panel.setAttribute('role','dialog');panel.setAttribute('aria-label','테스트 충전 · 임시가');
 const close=document.createElement('button');close.className='gem-x';close.textContent='✕';close.setAttribute('aria-label','닫기');close.onclick=()=>modal.remove();
 const title=document.createElement('h2');title.textContent='테스트 충전 · 임시가';panel.append(close,title);modal.append(panel);document.body.append(modal);modal.onclick=e=>{if(e.target===modal)modal.remove();};
 const button=(text,fn)=>{const b=document.createElement('button');b.type='button';b.className='gem-charge payment-product';b.textContent=text;b.onclick=async()=>{if(buying)return;buying=true;panel.querySelectorAll('button.payment-product').forEach(x=>x.disabled=true);try{if(c.user?.id!==uid)throw Error('login required');await fn();}catch(e){if(['payment refunded','payment closed','order expired'].includes(e?.message)&&c.user?.id===uid){localStorage.removeItem(pendingKey(uid));modal.remove();}toast(paymentError(e?.code||e?.message,e?.sdkMessage));}finally{buying=false;panel.querySelectorAll('button.payment-product').forEach(x=>x.disabled=false);}};panel.append(b);return b;};
 const prior=loadPending(localStorage,uid);
 if(prior?.paymentKey){button('충전 다시 확인',async()=>{const r=await api(c.sb,config,{op:'confirm',orderId:prior.orderId,paymentKey:prior.paymentKey,amount:prior.amount});if(c.user?.id!==uid)return;localStorage.removeItem(pendingKey(uid));void window.VRGem.status(true);toast(r?.kind==='pass'?'시즌패스 구매 완료':'심연석 충전 완료');modal.remove();});return;}
 try{
  const {data,error}=await deadline(c.sb.from('payment_products').select('id,name,amount,paid_gems,bonus_gems').eq('active',true).like('id','gem_%').order('sort'));if(error||!data?.length)throw Error('product unavailable');
  if(c.user?.id!==uid){modal.remove();return;}
  for(const p of data)button(`🔮 ${Number(p.paid_gems+p.bonus_gems).toLocaleString('ko-KR')} · ${Number(p.amount).toLocaleString('ko-KR')}원`,()=>startCheckout(p,c,uid));
 }catch(e){toast(paymentError(e.message));modal.remove();}
}
async function checkout(p){
 if(!on||!p?.id)return;
 const c=window.VRCloud,uid=c?.user?.id;if(!c?.sb||!uid)return toast('로그인이 필요해요.');
 if(loadPending(localStorage,uid)?.paymentKey)return open();
 if(buying)return;buying=true;
 try{await startCheckout(p,c,uid);}catch(e){failCheckout(e,uid);}finally{buying=false;}
}
window.VRPayments={open,checkout,enabled:on};
