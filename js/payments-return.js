import {config} from './config.js';
import {enabled,api,readReturn,paymentError,savePending,loadPending,pendingKey} from './payments-core.js';
const raw=window.__VR_PAYMENT_RETURN;delete window.__VR_PAYMENT_RETURN;
let evidence=readReturn(raw||location.href);
try{if(evidence?.op==='confirm')sessionStorage.setItem('vrTcg.toss.callback.url.v1',raw);else if(!evidence)evidence=readReturn(sessionStorage.getItem('vrTcg.toss.callback.url.v1')||location.href);}catch{}
const title=document.getElementById('pay-title'),retry=document.getElementById('pay-retry'),home=document.getElementById('pay-home'),toast=document.getElementById('pay-toast'),spinner=document.querySelector('.payment-spinner');
let sb,uid,busy=false,context;
try{context=JSON.parse(localStorage.getItem('vrTcg.toss.order.v1:'+evidence?.orderId));if(evidence?.paymentKey&&context?.uid)savePending(localStorage,context.uid,evidence);}catch{}
async function bounded(fn){let t;try{return await Promise.race([fn(),new Promise((_,r)=>{t=setTimeout(()=>r(Error('payment confirmation pending')),8000);})]);}finally{clearTimeout(t);}}
function show(t,message,again=false){spinner.hidden=true;title.hidden=false;title.textContent=t;home.hidden=false;retry.hidden=!again;toast.hidden=!message;toast.textContent=message||'';}
async function confirm(){if(busy)return;busy=true;retry.disabled=true;spinner.hidden=false;try{const p=evidence?.op==='confirm'?evidence:loadPending(localStorage,uid);if(!p?.paymentKey)throw Error('payment mismatch');const {data,error}=await bounded(()=>sb.auth.getUser());if(error||data.user?.id!==uid)throw Error('login required');if(context?.uid&&context.uid!==uid)throw Error('order not found');savePending(localStorage,uid,p);await api(sb,config,{op:'confirm',orderId:p.orderId,paymentKey:p.paymentKey,amount:p.amount});localStorage.removeItem(pendingKey(uid));localStorage.removeItem('vrTcg.toss.order.v1:'+p.orderId);sessionStorage.removeItem('vrTcg.toss.callback.url.v1');show('충전 완료','심연석이 지급됐어요.');}catch(e){show('충전 확인 필요',paymentError(e.message),true);}finally{busy=false;retry.disabled=false;}}
retry.onclick=confirm;
async function init(){
 if(!enabled(config))return show('이용할 수 없어요.','테스트 서버에서만 이용할 수 있어요.');
 if(evidence?.failed){try{const p=context?.uid&&loadPending(localStorage,context.uid);if(p?.orderId===evidence.orderId&&!p.paymentKey)localStorage.removeItem(pendingKey(context.uid));}catch{}return show('결제 종료',paymentError(evidence.code));}
 if(!evidence)return show('결제 정보 없음','충전 화면에서 다시 시작해 주세요.');
 let timer;
 try{
  sb=await Promise.race([(async()=>{const {createClient}=await import('https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.45.4/+esm');return createClient(config.supabaseUrl,config.anonKey,{auth:{persistSession:true,detectSessionInUrl:false,flowType:'pkce'}});})(),new Promise((_,r)=>{timer=setTimeout(()=>r(Error('login required')),8000);})]);
  await bounded(()=>sb.auth.initialize());const {data,error}=await bounded(()=>sb.auth.getUser());if(error||!data.user)throw Error('login required');uid=data.user.id;
  await confirm();
 }catch(e){show('로그인 확인 필요',paymentError(e.message));}finally{clearTimeout(timer);}
}
init();
