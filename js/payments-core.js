// No secret/API key here. Test-only hostname + project gates must BOTH match.
export const STAGE_HOST='vr-tcg-staging.notcold.workers.dev', STAGE_DB='https://cuyqchmdcnsgzkwyclji.supabase.co';
export const enabled=(c,l=location)=>c.enabled&&c.isStaging&&c.supabaseUrl===STAGE_DB&&l.hostname===STAGE_HOST;
export const ORDER=/^vrs_[a-f0-9]{32}$/;
export function paymentError(code){if(typeof code==='string'&&/^sdk:[A-Za-z][A-Za-z0-9_]{1,60}$/.test(code)){const c=code.slice(4);const text=({'SDK_LOAD_FAILED':'결제창을 불러오지 못했어요.','INVALID_CLIENT_KEY':'테스트 결제 키를 확인해 주세요.','INVALID_CUSTOMER_KEY':'결제 고객 정보를 확인해 주세요.','INVALID_ORDER_ID':'결제 주문 정보를 확인해 주세요.','INVALID_AMOUNT_VALUE':'결제 금액을 확인해 주세요.','INVALID_ORDER_NAME':'결제 상품명을 확인해 주세요.','SDK_VERSION_MISMATCH':'결제창을 새로 불러와 주세요.','USER_CANCEL':'결제를 취소했어요.','PAY_PROCESS_CANCELED':'결제를 취소했어요.','PAYMENT_REQUEST_ABORTED':'결제를 취소했어요.'})[c]||'결제창을 열지 못했어요.';return text+' ('+c+')';}return ({'order creation delayed':'주문 생성이 지연됐어요. 다시 눌러 주세요.','order creation failed':'주문을 만들지 못했어요. 다시 시도해 주세요.','payment gateway authentication':'결제 서버의 로그인 설정을 확인해 주세요.','payment function missing':'결제 서버가 아직 배포되지 않았어요.','payment sql required':'결제 DB 설정을 확인해 주세요.','payment database permissions':'결제 DB 권한을 확인해 주세요.','payment database unavailable':'결제 DB 연결을 확인해 주세요.','backend configuration':'결제 서버 설정을 확인해 주세요.','payment sdk unavailable':'결제창을 불러오지 못했어요. 다시 시도해 주세요.','payment checkout failed':'결제창을 열지 못했어요. 다시 시도해 주세요.','login required':'로그인이 필요해요.','order not found':'이 주문을 만든 계정으로 로그인해 주세요.','order expired':'주문이 만료됐어요. 다시 충전해 주세요.','payment mismatch':'결제 정보가 맞지 않아요.','payment conflict':'이 주문의 결제 정보가 달라요.','product unavailable':'지금은 구매할 수 없는 상품이에요.','rate limited':'잠시 후 다시 시도해 주세요.','payment not completed':'결제가 완료되지 않았어요. 다시 확인해 주세요.','test payment configuration required':'테스트 결제 설정이 아직 준비되지 않았어요.','USER_CANCEL':'결제를 취소했어요.','PAY_PROCESS_CANCELED':'결제를 취소했어요.','PAY_PROCESS_ABORTED':'결제를 완료하지 못했어요.','REJECT_CARD_COMPANY':'결제수단을 확인하고 다시 시도해 주세요.','PAYMENT_REQUEST_ABORTED':'결제를 취소했어요.'})[code]||'결제 확인이 지연되고 있어요. 다시 확인해 주세요.';}
export function readReturn(href){const u=new URL(href),p=u.searchParams,amount=Number(p.get('amount'));if(p.get('vrpay')==='fail')return {failed:true,code:p.get('code')||'failed',orderId:p.get('orderId')||p.get('vr_order')};if(p.get('vrpay')==='success'&&ORDER.test(p.get('orderId')||'')&&p.get('paymentKey')&&p.get('paymentKey').length<=200&&/^\d+$/.test(p.get('amount')||'')&&Number.isSafeInteger(amount)&&amount>=100&&amount<=1000000)return {op:'confirm',orderId:p.get('orderId'),paymentKey:p.get('paymentKey'),amount};return null;}
export const pendingKey=uid=>'vrTcg.toss.pending.v1:'+uid;
export function savePending(store,uid,value){store.setItem(pendingKey(uid),JSON.stringify({...value,uid}));}
export function loadPending(store,uid){try{const p=JSON.parse(store.getItem(pendingKey(uid)));return p?.uid===uid?p:null;}catch{return null;}}
// Only safe, known categories cross to UI; never display backend SQL/SDK raw messages.
const KNOWN_ERRORS=new Set(['login required','order not found','order expired','payment mismatch','payment conflict','product unavailable','request conflict','rate limited','payment not completed','test payment configuration required','backend configuration','payment sql required','payment database permissions','payment database unavailable','order creation failed','payment confirmation pending']);
export async function api(sb,c,body,fetcher=fetch,timeout=14000){
 if(c.supabaseUrl!==STAGE_DB||!c.isStaging)throw Error('staging only');
 const creating=body.op==='create',pending=creating?'order creation delayed':'payment confirmation pending';
 let timer;const ctrl=new AbortController();
 const work=async()=>{
  const {data}=await sb.auth.getSession();if(!data?.session?.access_token)throw Error('login required');
  const r=await fetcher(STAGE_DB+'/functions/v1/payments-confirm-v1',{method:'POST',headers:{'content-type':'application/json',apikey:c.anonKey,authorization:'Bearer '+data.session.access_token},body:JSON.stringify(body),signal:ctrl.signal});
  let d;try{d=await r.json();}catch{throw Error(r.status===504?pending:creating?'order creation failed':'payment confirmation pending');}
  if(!r.ok||!d?.ok){
   if(r.status===401)throw Error(d?.error==='login required'?'login required':'payment gateway authentication');
   if(r.status===404)throw Error('payment function missing');
   if(r.status===504)throw Error(pending);
   if(d?.error==='payment confirmation pending')throw Error(creating?'order creation failed':pending);
   throw Error(KNOWN_ERRORS.has(d?.error)?d.error:creating?'order creation failed':'payment confirmation pending');
  }
  return d;
 };
 try{return await Promise.race([work(),new Promise((_,reject)=>{timer=setTimeout(()=>{ctrl.abort();reject(Error(pending));},timeout);})]);}
 catch(e){if(KNOWN_ERRORS.has(e.message)||['payment gateway authentication','payment function missing',pending].includes(e.message))throw e;throw Error(creating?'order creation failed':'payment confirmation pending');}
 finally{clearTimeout(timer);}
}

export const SAMPLE_TOSS_CLIENT_KEY='test_ck_D5GePWvyJnrK0W0k6q8gLzN97Eoq'; // Public official sample identifier.
export function sdkErrorCode(error){
 const fromMessage=typeof error?.message==='string'&&error.message.startsWith('sdk:')?error.message.slice(4):null;
 const code=error?.code||fromMessage;
 if(typeof code==='string'&&/^[A-Z][A-Z0-9_]{1,60}$/.test(code))return code;
 const name=error?.name;
 return typeof name==='string'&&/^(?:[A-Z][A-Za-z]{1,50}Error|Error|NotSupportedEnvironment)$/.test(name)?name:'SDK_UNKNOWN';
}
export function sdkFailure(error,stage,clientKey){
 const code=sdkErrorCode(error);
 // Never log error objects/messages, customer/order IDs, keys, or callback URLs.
 console.warn(JSON.stringify({tag:'payments',stage,code,sdk:2,windowTarget:'self',keyMode:clientKey===SAMPLE_TOSS_CLIENT_KEY?'official-sample':'custom-test'}));
 return Error('sdk:'+code);
}
export function checkoutParams(order,uid,origin){
 const bad=code=>{throw Error('sdk:'+code);};
 if(typeof uid!=='string'||!/^[A-Za-z0-9_=.@-]{22,50}$/.test(uid)||!/[_.=@-]/.test(uid))bad('INVALID_CUSTOMER_KEY');
 if(!ORDER.test(order?.orderId||''))bad('INVALID_ORDER_ID');
 if(!Number.isSafeInteger(order?.amount)||order.amount<100||order.amount>1000000)bad('INVALID_AMOUNT_VALUE');
 if(typeof order?.orderName!=='string'||!order.orderName.trim()||order.orderName.length>100)bad('INVALID_ORDER_NAME');
 if(origin!=='https://'+STAGE_HOST)bad('INVALID_URL');
 // Full-page redirect on PC and mobile: no popup or iframe/user-activation dependency.
 return {method:'CARD',windowTarget:'self',amount:{currency:'KRW',value:order.amount},orderId:order.orderId,orderName:order.orderName,successUrl:origin+'/payment-return.html?vrpay=success',failUrl:origin+'/payment-return.html?vrpay=fail&vr_order='+order.orderId};
}
