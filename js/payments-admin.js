// Staging-only admin UI; authorization enforced again in Edge AND every admin RPC.
import {config} from './config.js';
import {enabled,api,paymentError} from './payments-core.js';
const message=document.getElementById('pay-message'),rows=document.getElementById('pay-orders'),reload=document.getElementById('pay-load');
const states={paid:'결제 완료',pending:'결제 대기',open:'결제 대기',canceled:'결제 취소',failed:'결제 실패',expired:'만료',none:'',processing:'환불 확인 중',refunded:'환불 완료',review:'고객지원 확인 필요'};
let sb,busy=false;
const cell=(row,text)=>{const td=document.createElement('td');td.textContent=String(text);row.append(td);return td;};
const seoul=value=>{
 const d=new Date(value);if(Number.isNaN(d.getTime()))return '';
 const parts=new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Seoul',year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',second:'2-digit',hourCycle:'h23'}).formatToParts(d);
 const get=type=>parts.find(part=>part.type===type)?.value||'';
 return get('year')+'-'+get('month')+'-'+get('day')+' '+get('hour')+':'+get('minute')+':'+get('second');
};
const buyer=o=>{const name=typeof o.buyer==='string'?o.buyer.trim():'';return name||(typeof o.user_id==='string'?o.user_id:'');};
const paidWhen=o=>{if(o.paid_at)return seoul(o.paid_at);if(o.status==='paid')return '';return o.created_at?'미결제 · 생성 '+seoul(o.created_at):'미결제';};
async function load(){
 const result=await api(sb,config,{op:'orders'});rows.replaceChildren();
 for(const o of result.orders){
  const row=document.createElement('tr');cell(row,o.order_name+' / '+o.order_id);cell(row,buyer(o));cell(row,Number(o.amount).toLocaleString('ko-KR')+'원');cell(row,Number(o.paid_gems+o.bonus_gems).toLocaleString('ko-KR'));
  cell(row,states[o.cancel_status!=='none'?o.cancel_status:o.status==='paid'?'paid':o.checkout_status]||'확인 필요');cell(row,paidWhen(o));cell(row,Number(o.cancel_amount).toLocaleString('ko-KR')+'원');
  const actions=cell(row,'');
  if(o.status==='paid'&&o.cancel_status!=='refunded'){
   const button=document.createElement('button');button.className='ad-btn';button.textContent=o.cancel_status==='none'?'전액 환불':'환불 다시 확인';actions.append(button);
   button.onclick=async()=>{
    if(busy||!window.confirm('이 테스트 주문을 전액 환불하고 지급 심연석을 회수할까요?'))return;
    busy=true;button.disabled=true;reload.disabled=true;message.textContent='환불 처리 중';
    try{const r=await api(sb,config,{op:'refund',orderId:o.order_id});message.textContent=r.state==='refunded'?'환불 완료':'환불 상태 확인 필요';}
    catch(e){message.textContent=paymentError(e.message);}
    finally{try{await load();}catch{}busy=false;reload.disabled=false;button.disabled=false;}
   };
  }
  rows.append(row);
 }
}
async function refresh(){if(busy)return;busy=true;reload.disabled=true;try{await load();message.textContent='';}catch(e){message.textContent=paymentError(e.message);}finally{busy=false;reload.disabled=false;}}
reload.onclick=refresh;
async function init(){
 if(!enabled(config)){message.textContent='테스트 서버에서만 이용할 수 있어요.';reload.disabled=true;return;}
 try{
  const {createClient}=await import('https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.45.4/+esm');
  sb=createClient(config.supabaseUrl,config.anonKey,{auth:{persistSession:true,detectSessionInUrl:false,flowType:'pkce'}});
  await sb.auth.initialize();await refresh();
 }catch{message.textContent='로그인 서버에 연결할 수 없어요.';}
}
init();
