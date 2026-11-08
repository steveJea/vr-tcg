// No secret/API key here. Test-only hostname + project gates must BOTH match.
export const STAGE_HOST='vr-tcg-staging.notcold.workers.dev', STAGE_DB='https://cuyqchmdcnsgzkwyclji.supabase.co';
export const enabled=(c,l=location)=>c.enabled&&c.isStaging&&c.supabaseUrl===STAGE_DB&&l.hostname===STAGE_HOST;
export const ORDER=/^vrs_[a-f0-9]{32}$/;
export function paymentError(code){return ({'login required':'로그인이 필요해요.','order not found':'이 주문을 만든 계정으로 로그인해 주세요.','order expired':'주문이 만료됐어요. 다시 충전해 주세요.','payment mismatch':'결제 정보가 맞지 않아요.','payment conflict':'이 주문의 결제 정보가 달라요.','product unavailable':'지금은 구매할 수 없는 상품이에요.','rate limited':'잠시 후 다시 시도해 주세요.','payment not completed':'결제가 완료되지 않았어요. 다시 확인해 주세요.','test payment configuration required':'테스트 결제 설정이 아직 준비되지 않았어요.','USER_CANCEL':'결제를 취소했어요.','PAY_PROCESS_CANCELED':'결제를 취소했어요.','PAY_PROCESS_ABORTED':'결제를 완료하지 못했어요.','REJECT_CARD_COMPANY':'결제수단을 확인하고 다시 시도해 주세요.','PAYMENT_REQUEST_ABORTED':'결제를 취소했어요.'})[code]||'결제 확인이 지연되고 있어요. 다시 확인해 주세요.';}
export function readReturn(href){const u=new URL(href),p=u.searchParams,amount=Number(p.get('amount'));if(p.get('vrpay')==='fail')return {failed:true,code:p.get('code')||'failed',orderId:p.get('orderId')||p.get('vr_order')};if(p.get('vrpay')==='success'&&ORDER.test(p.get('orderId')||'')&&p.get('paymentKey')&&p.get('paymentKey').length<=200&&/^\d+$/.test(p.get('amount')||'')&&Number.isSafeInteger(amount)&&amount>=100&&amount<=1000000)return {op:'confirm',orderId:p.get('orderId'),paymentKey:p.get('paymentKey'),amount};return null;}
export const pendingKey=uid=>'vrTcg.toss.pending.v1:'+uid;
export function savePending(store,uid,value){store.setItem(pendingKey(uid),JSON.stringify({...value,uid}));}
export function loadPending(store,uid){try{const p=JSON.parse(store.getItem(pendingKey(uid)));return p?.uid===uid?p:null;}catch{return null;}}
export async function api(sb,c,body,fetcher=fetch,timeout=14000){
 if(c.supabaseUrl!==STAGE_DB||!c.isStaging)throw Error('staging only');
 let timer;const ctrl=new AbortController();
 const work=async()=>{const {data}=await sb.auth.getSession();if(!data?.session?.access_token)throw Error('login required');const r=await fetcher(STAGE_DB+'/functions/v1/payments-confirm-v1',{method:'POST',headers:{'content-type':'application/json',apikey:c.anonKey,authorization:'Bearer '+data.session.access_token},body:JSON.stringify(body),signal:ctrl.signal});const d=await r.json();if(!r.ok||!d?.ok)throw Error(d?.error||'payment confirmation pending');return d;};
 try{return await Promise.race([work(),new Promise((_,reject)=>{timer=setTimeout(()=>{ctrl.abort();reject(Error('payment confirmation pending'));},timeout);})]);}finally{clearTimeout(timer);}
}
