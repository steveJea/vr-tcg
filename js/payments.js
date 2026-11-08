import {config} from './config.js';
import {enabled,api,paymentError,savePending,loadPending,pendingKey} from './payments-core.js';
const on=enabled(config),toast=t=>window.VRGem?.toast?.(t);let sdk,buying=false;
const deadline=async(p,ms=10000)=>{let t;try{return await Promise.race([p,new Promise((_,r)=>{t=setTimeout(()=>r(Error('payment confirmation pending')),ms);})]);}finally{clearTimeout(t);}};
async function loadSDK(){try{if(window.TossPayments)return Promise.resolve(window.TossPayments);if(!sdk)sdk=new Promise((resolve,reject)=>{const s=document.createElement('script');s.src='https://js.tosspayments.com/v2/standard';s.onload=()=>window.TossPayments?resolve(window.TossPayments):reject(Error('sdk'));s.onerror=()=>reject(Error('sdk'));document.head.appendChild(s);}).catch(e=>{sdk=null;throw e;});return await deadline(sdk);}catch{sdk=null;throw Error('payment sdk unavailable');}}
async function open(){
 if(!on)return;
 const c=window.VRCloud,uid=c?.user?.id;if(!c?.sb||!uid)return toast('로그인이 필요해요.');
 document.querySelector('[data-payment-modal]')?.remove();const modal=document.createElement('div');modal.className='gem-pop payment-pop';modal.dataset.paymentModal='1';
 const panel=document.createElement('div');panel.className='gem-panel';panel.setAttribute('role','dialog');panel.setAttribute('aria-label','테스트 충전 · 임시가');
 const close=document.createElement('button');close.className='gem-x';close.textContent='✕';close.setAttribute('aria-label','닫기');close.onclick=()=>modal.remove();
 const title=document.createElement('h2');title.textContent='테스트 충전 · 임시가';panel.append(close,title);modal.append(panel);document.body.append(modal);modal.onclick=e=>{if(e.target===modal)modal.remove();};
 const button=(text,fn)=>{const b=document.createElement('button');b.type='button';b.className='gem-charge payment-product';b.textContent=text;b.onclick=async()=>{if(buying)return;buying=true;panel.querySelectorAll('button.payment-product').forEach(x=>x.disabled=true);try{if(c.user?.id!==uid)throw Error('login required');await fn();}catch(e){toast(paymentError(e.code||e.message));}finally{buying=false;panel.querySelectorAll('button.payment-product').forEach(x=>x.disabled=false);}};panel.append(b);return b;};
 const prior=loadPending(localStorage,uid);
 if(prior?.paymentKey){button('충전 다시 확인',async()=>{const r=await api(c.sb,config,{op:'confirm',orderId:prior.orderId,paymentKey:prior.paymentKey,amount:prior.amount});if(c.user?.id!==uid)return;localStorage.removeItem(pendingKey(uid));void window.VRGem.status(true);toast('심연석 충전 완료');modal.remove();});return;}
 try{
  const {data,error}=await deadline(c.sb.from('payment_products').select('id,name,amount,paid_gems,bonus_gems').eq('active',true).order('sort'));if(error||!data?.length)throw Error('product unavailable');
  if(c.user?.id!==uid){modal.remove();return;}
  for(const p of data)button(`🔮 ${Number(p.paid_gems+p.bonus_gems).toLocaleString('ko-KR')} · ${Number(p.amount).toLocaleString('ko-KR')}원`,async()=>{
   let intent=loadPending(localStorage,uid);
   if(intent?.paymentKey)throw Error('payment confirmation pending');
   if(!intent||intent.product!==p.id){intent={product:p.id,request:crypto.randomUUID()};savePending(localStorage,uid,intent);}
   const result=await api(c.sb,config,{op:'create',product:p.id,request:intent.request}),o=result.order;
   if(c.user?.id!==uid)throw Error('login required');
   if(o.status==='paid'){localStorage.removeItem(pendingKey(uid));toast('이미 충전된 주문이에요.');return;}
   if(!result.clientKey?.startsWith('test_ck_')||o.userId!==uid)throw Error('payment mismatch');
   intent={...intent,orderId:o.orderId,amount:o.amount};savePending(localStorage,uid,intent);localStorage.setItem('vrTcg.toss.order.v1:'+o.orderId,JSON.stringify({uid,amount:o.amount}));
   const Toss=await loadSDK();if(c.user?.id!==uid)throw Error('login required');
   try{await Toss(result.clientKey).payment({customerKey:uid}).requestPayment({method:'CARD',amount:{currency:'KRW',value:o.amount},orderId:o.orderId,orderName:o.orderName,successUrl:location.origin+'/payment-return.html?vrpay=success',failUrl:location.origin+'/payment-return.html?vrpay=fail&vr_order='+o.orderId});}
   catch(e){if(['USER_CANCEL','PAY_PROCESS_CANCELED','PAYMENT_REQUEST_ABORTED'].includes(e.code)){localStorage.removeItem(pendingKey(uid));throw e;}if(['PAY_PROCESS_ABORTED','REJECT_CARD_COMPANY'].includes(e.code))throw e;console.warn(JSON.stringify({tag:'payments',stage:'checkout',code:/^[A-Z0-9_]{1,60}$/.test(e.code||'')?e.code:null}));throw Error('payment checkout failed');}
  });
 }catch(e){toast(paymentError(e.message));modal.remove();}
}
window.VRPayments={open,enabled:on};
