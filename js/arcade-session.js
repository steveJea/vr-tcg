// Intent transcript only. Result/metrics/seed never come from a browser report.
import {ARCADE_ENGINE_VERSION as version} from './arcade-engine-version.js';
const cloud=owner=>{const c=window.VRCloud;if(!c?.sb||!c.user)throw Error('로그인이 필요해요');if(owner&&owner!==c.user.id)throw Error('로그인 계정이 바뀌었어요');return c;};
const key=owner=>'vrArcade.pendingV5:'+owner;
const save=(owner,p)=>p===null?localStorage.removeItem(key(owner)):localStorage.setItem(key(owner),JSON.stringify(p));
async function rpc(body,owner){let last;for(let n=0;n<2;n++){const c=cloud(owner);try{const {data,error}=await c.sb.functions.invoke('arcade-verify-v5',{body});cloud(owner);if(error){let d;try{d=await error.context?.json();}catch{}throw Error(d?.error||error.message);}if(!data?.ok)throw Error(data?.error||'전투 검증에 실패했어요');return data;}catch(e){cloud(owner);last=e;}}throw last;}
async function settle(body,owner){try{return await rpc(body,owner);}catch(e){const r=await rpc({op:'status',id:body.id},owner).catch(()=>null);if(r?.status==='settled')return r;throw e;}}
let starting=false;
export async function startArcadeVerified(options){
 if(starting)throw Error('전투를 준비하고 있어요');starting=true;
 try{return await startSession(options);}finally{starting=false;}
}
async function startSession(options){
 const owner=cloud().user.id;let p=JSON.parse(localStorage.getItem(key(owner))||'null');
 if(p){if(p.phase==='start'){const s=await rpc(p.body,owner);p={phase:'active',session:s};save(owner,p);}
  if(p.phase==='active'){if(!await window.VRAsk?.('이전 아케이드 전투를 포기하고 새로 시작할까요?'))throw Error('이전 전투 확인 필요');p={phase:'finish',body:{op:'forfeit',id:p.session.id}};save(owner,p);}
  await settle(p.body,owner);save(owner,null);await cloud(owner).loadRecord?.();
 }
 const body={op:'start',request:crypto.randomUUID(),options,version};save(owner,{phase:'start',body});const s={...await rpc(body,owner),_owner:owner};save(owner,{phase:'active',session:s});return s;
}
export async function finishArcadeVerified(session,actions){const owner=session._owner;cloud(owner);const body=actions===null?{op:'forfeit',id:session.id}:{op:'finish',id:session.id,actions};save(owner,{phase:'finish',body});const r=await settle(body,owner);save(owner,null);await cloud(owner).loadRecord?.();window.VRDaily?.status?.();return r.result;}
