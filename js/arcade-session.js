// Intent transcript only. Result/metrics/seed never come from a browser report.
import {ARCADE_ENGINE_VERSION as version} from './arcade-engine-version.js';
const cloud=owner=>{const c=window.VRCloud;if(!c?.sb||!c.user)throw Error('로그인이 필요해요');if(owner&&owner!==c.user.id)throw Object.assign(Error('로그인 계정이 바뀌었어요'),{code:'account-changed'});return c;};
const key=owner=>'vrArcade.pendingV5:'+owner;
const save=(owner,p)=>p===null?localStorage.removeItem(key(owner)):localStorage.setItem(key(owner),JSON.stringify(p));
const REQUEST_WINDOW_MS=15000;
const timeoutError=()=>Object.assign(Error('서버 응답이 늦어요. 다시 시도해 주세요.'),{code:'ARCADE_TIMEOUT'});
// One deadline covers retries, error-body parsing and lost-response status recovery.
// SDK versions that cannot abort invoke() may still settle remotely: retain the
// SAME durable submission so retry/status recovers its exact-once receipt.
function beforeDeadline(task,until){
 const left=until-Date.now();if(left<=0)return Promise.reject(timeoutError());
 let timer;return Promise.race([Promise.resolve().then(task),new Promise((_,reject)=>{timer=setTimeout(()=>reject(timeoutError()),left);})]).finally(()=>clearTimeout(timer));
}
async function rpc(body,owner,until=Date.now()+REQUEST_WINDOW_MS){
 let last;
 for(let n=0;n<2;n++){
  const c=cloud(owner);
  try{
   const {data,error}=await beforeDeadline(()=>c.sb.functions.invoke('arcade-verify-v5',{body}),until);cloud(owner);
   if(error){
    let d;try{d=await beforeDeadline(()=>error.context?.json(),until);}catch(e){if(e.code==='ARCADE_TIMEOUT')throw e;}
    const message=d?.error||error.message||'전투 검증에 실패했어요';
    throw Object.assign(Error(message),{trace:d?.trace});
   }
   if(!data?.ok)throw Error(data?.error||'전투 검증에 실패했어요');
   return data;
  }catch(e){cloud(owner);last=e;if(e.code==='ARCADE_TIMEOUT')throw e;}
 }
 throw last;
}
async function settle(body,owner){
 const until=Date.now()+REQUEST_WINDOW_MS;
 try{return await rpc(body,owner,until);}catch(e){
  if(e.code==='ARCADE_TIMEOUT'||Date.now()>=until)throw e;
  const r=await rpc({op:'status',id:body.id},owner,until).catch(statusError=>{if(statusError.code==='ARCADE_TIMEOUT')throw statusError;return null;});
  if(r?.status==='settled')return r;
  throw e;
 }
}
function receiptOf(r){
 const v=r?.result;
 if(!v||!['win','lose','draw'].includes(v.result)||typeof v.reason!=='string'||!['damage','skills','turns'].every(k=>Number.isSafeInteger(v[k])&&v[k]>=0))throw Error('서버 결과를 확인하지 못했어요. 다시 시도해 주세요.');
 return v;
}
// Record/mission refresh is auxiliary, NOT part of trusted result settlement.
// A stalled stats RPC must never keep an already-verified battle on 검증 중.
function refresh(owner){
 Promise.resolve().then(()=>cloud(owner).loadRecord?.()).catch(()=>{});
 Promise.resolve().then(()=>{cloud(owner);return window.VRDaily?.status?.();}).catch(()=>{});
}
let starting=false;
export async function startArcadeVerified(options){
 if(starting)throw Error('전투를 준비하고 있어요');starting=true;
 try{return await startSession(options);}finally{starting=false;}
}
async function startSession(options){
 const owner=cloud().user.id;let p=JSON.parse(localStorage.getItem(key(owner))||'null');
 if(p){if(p.phase==='start'){const s=await rpc(p.body,owner);p={phase:'active',session:s};save(owner,p);}
  if(p.phase==='active'){p={phase:'finish',body:{op:'forfeit',id:p.session.id}};save(owner,p);}
  receiptOf(await settle(p.body,owner));save(owner,null);refresh(owner);
 }
 const body={op:'start',request:crypto.randomUUID(),options,version};save(owner,{phase:'start',body});const s={...await rpc(body,owner),_owner:owner};save(owner,{phase:'active',session:s});return s;
}
export async function finishArcadeVerified(session,actions){
 const owner=session._owner;cloud(owner);const body=actions===null?{op:'forfeit',id:session.id}:{op:'finish',id:session.id,actions};save(owner,{phase:'finish',body});
 const result=receiptOf(await settle(body,owner));cloud(owner);save(owner,null);refresh(owner);return result;
}
