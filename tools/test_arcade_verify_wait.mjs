// Network-free deadline and UI regression for arcade settlement. No user tokens.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {parseHTML} from 'linkedom';
const src=fs.readFileSync('js/arcade-session.js','utf8').replace(/^import .*;$/m,'').replace(/\bexport /g,''),game=fs.readFileSync('js/game.js','utf8');
const tick=async()=>{for(let i=0;i<50;i++)await Promise.resolve();};
const good={result:'win',reason:'ko',damage:123,skills:2,turns:5,verified:true,session_id:'1'};
function harness(invoke,{loadRecord=async()=>{},daily=async()=>{}}={}){
 let now=0,id=0,uuid=0;const timers=new Map(),ls=new Map(),calls=[];
 const c=vm.createContext({version:'hash',Date:{now:()=>now},crypto:{randomUUID:()=>`uuid-${++uuid}`},setTimeout:(fn,ms)=>{timers.set(++id,{at:now+ms,fn});return id;},clearTimeout:id=>timers.delete(id),localStorage:{getItem:k=>ls.get(k)||null,setItem:(k,v)=>ls.set(k,v),removeItem:k=>ls.delete(k)},window:{VRAsk:async()=>true,VRDaily:{status:daily},VRCloud:{user:{id:'one'},loadRecord,sb:{functions:{invoke:(name,{body})=>{assert.equal(name,'arcade-verify-v5');calls.push(body);return invoke(body);}}}}}});
 vm.runInContext(src,c);
 return {c,ls,calls,advance:async ms=>{now+=ms;for(const [id,t]of timers)if(t.at<=now){timers.delete(id);t.fn();}await tick();},session:{id:'1',_owner:'one'},pending:()=>JSON.parse(ls.get('vrArcade.pendingV5:one')||'null')};
}
// A reply can be lost after commit. Timeout retains identical evidence; retry must not regrant.
{
 let hang=true,commits=0,stored;
 const h=harness(body=>{if(!stored){stored=good;commits++;}return hang?new Promise(()=>{}):Promise.resolve({data:{ok:true,status:'settled',result:stored}});});
 let failure;const p=h.c.finishArcadeVerified(h.session,[{k:'end'}]).catch(e=>failure=e);await tick();await h.advance(14999);assert.equal(failure,undefined);await h.advance(1);await p;assert.equal(failure.code,'ARCADE_TIMEOUT');assert.equal(h.calls.length,1);assert.equal(h.pending().phase,'finish');assert.equal(h.pending().body.id,'1');
 hang=false;assert.equal((await h.c.finishArcadeVerified(h.session,[{k:'end'}])).result,'win');assert.equal(commits,1);assert.equal(h.ls.size,0);assert.equal(JSON.stringify(h.calls[0]),JSON.stringify(h.calls[1]));
 console.log('PASS hung invoke exits at 15s, exact evidence retained, lost-commit retry does not duplicate');
}
// Error response .json() can hang just like invoke(). Same single deadline applies.
{
 const h=harness(()=>Promise.resolve({error:{message:'edge error',context:{json:()=>new Promise(()=>{})}}}));let error;
 const p=h.c.finishArcadeVerified(h.session,[]).catch(e=>error=e);await tick();await h.advance(15000);await p;assert.equal(error.code,'ARCADE_TIMEOUT');assert.equal(h.pending().phase,'finish');
 console.log('PASS stalled error-body parsing is bounded');
}
// Verified receipt must not wait for the optional stats/mission RPCs.
{
 let records=0,dailies=0;const h=harness(()=>Promise.resolve({data:{ok:true,result:good}}),{loadRecord:()=>{records++;return new Promise(()=>{});},daily:()=>{dailies++;throw Error('stats offline');}});let receipt;
 const p=h.c.finishArcadeVerified(h.session,[]).then(r=>receipt=r);await tick();assert.equal(receipt,good);await p;assert.equal(records,1);assert.equal(dailies,1);assert.equal(h.ls.size,0);
 // Recovery of a saved FINISH must also let the next START proceed despite hung stats.
 h.ls.set('vrArcade.pendingV5:one',JSON.stringify({phase:'finish',body:{op:'finish',id:'1',actions:[]}}));
 h.c.window.VRCloud.sb.functions.invoke=async(name,{body})=>({data:body.op==='start'?{ok:true,id:'2',seed:1,options:{}}:{ok:true,result:good}});
 const next=await h.c.startArcadeVerified({});assert.equal(next.id,'2');assert.equal(h.pending().phase,'active');
 console.log('PASS hung/rejected auxiliary refresh cannot block receipt or recovered next game');
}
{
 const h=harness(body=>body.op==='status'?Promise.resolve({data:{ok:true,status:'settled',result:good}}):Promise.reject(Error('lost reply')));
 assert.equal(await h.c.finishArcadeVerified(h.session,[]),good);assert.equal(h.calls.filter(x=>x.op==='finish').length,2);assert.equal(h.calls.at(-1).op,'status');
 const stalled=harness(body=>body.op==='status'?new Promise(()=>{}):Promise.reject(Error('network')));let error;const p=stalled.c.finishArcadeVerified(stalled.session,[]).catch(e=>error=e);await tick();await stalled.advance(15000);await p;assert.equal(error.code,'ARCADE_TIMEOUT');assert.equal(stalled.pending().phase,'finish');
 console.log('PASS status recovery shares deadline and preserves authoritative receipt');
}
{
 const h=harness(()=>Promise.resolve({data:{ok:true,result:{...good,damage:'invalid'}}}));await assert.rejects(h.c.finishArcadeVerified(h.session,[]),/서버 결과/);assert.equal(h.pending().phase,'finish');
 let resolve;const other=harness(()=>new Promise(r=>resolve=r));const p=other.c.finishArcadeVerified(other.session,[]);await tick();other.c.window.VRCloud.user.id='two';resolve({data:{ok:true,result:good}});await assert.rejects(p,/계정/);assert.equal(other.pending().phase,'finish');
 console.log('PASS malformed receipts/account changes cannot clear another pending result');
}
{
 let hang=true;const h=harness(body=>hang?new Promise(()=>{}):Promise.resolve({data:body.op==='start'?{ok:true,id:'2',seed:2,options:{}}:{ok:true,result:good}}));let error;
 const p=h.c.startArcadeVerified({}).catch(e=>error=e);await tick();await h.advance(15000);await p;assert.equal(error.code,'ARCADE_TIMEOUT');const request=h.pending().body.request;
 hang=false;await h.c.startArcadeVerified({});assert.equal(h.calls[1].request,request);assert(h.calls.some(x=>x.op==='forfeit'));assert.equal(h.pending().phase,'active');
 console.log('PASS START timeout releases mutex and reuses UUID before acknowledged forfeit/new session');
}
// Actual finish + showEnding, not a stubbed renderer: failure -> retry -> server verdict.
{
 const {document,CustomEvent}=parseHTML(fs.readFileSync('index.html','utf8'));const $=id=>document.getElementById(id);$('game').classList.remove('hidden');
 const gal=document.createElement('div');gal.id='gal-end';gal.textContent='도감·MVP 반영 보류';$('end-actions').before(gal);
 let fail=true,shown=0;const receipt={...good,result:'lose',mvp_id:'1',mvp_name:'인재'};
 const c=vm.createContext({document,$,CustomEvent,S:{arcadeSession:{id:'1'},arcade:{result:{result:'win'},actions:[]},log:{dmg:new Map(),total:999,skills:99},turnNo:1,myTurns:1,me:{hp:0,field:[],hand:[]},ai:{hp:100}},battleViewEpoch:0,window:{VRGem:{toast(){}},VRCloud:{user:{id:'one'}},dispatchEvent:e=>{if(e.type==='vr:match')shown++;}},finishArcadeVerified:()=>fail?Promise.reject(Error('서버 응답이 늦어요. 다시 시도해 주세요.')):Promise.resolve(receipt),hideModal(){},TUT(){},finishFx:()=>0,showEnding:null,pickMvp:()=>null,POOL:[{id:'1',name:'인재'}],IMG:'img/',fmt:String,endFx:()=>false,BFX:()=>false,voiceSet:null,queueEndingVoice(){},countUp(){},render(){},reportError:(w,e)=>{throw e;},setTimeout:fn=>fn(),console});
 const section=(a,b)=>game.slice(game.indexOf(a),game.indexOf(b,game.indexOf(a)));
 vm.runInContext(section('function showEnding(','async function shareResult(')+section('function finish(win, reason) {','// ===== 스토리 페이즈 규칙'),c);
 c.finish(true,'ko');assert.equal($('end-title').textContent,'검증 중');assert.equal(gal.textContent,'');assert.equal($('end-screen').getAttribute('aria-busy'),'true');await tick();
 assert.equal($('end-title').textContent,'검증을 완료하지 못했어요');assert($('end-text').textContent.includes('서버 응답이 늦어요'));assert.equal($('end-screen').getAttribute('aria-busy'),'false');assert.equal($('restart-btn').disabled,true);assert.equal($('share-btn').disabled,true);assert.equal(c.S.endShare,null);assert.equal(shown,0);
 const retry=$('end-text').querySelector('button');assert.equal(retry.textContent,'다시 시도');fail=false;retry.onclick();await tick();assert($('end-title').textContent.includes('DEFEAT'));assert(!$('end-screen').classList.contains('end-pending'));assert.equal($('restart-btn').disabled,false);assert.equal($('share-btn').disabled,false);assert.equal(c.S.arcadeReceipt,receipt);assert.equal(c.S.log.total,123);assert.equal(shown,1);
 c.reportError=()=>{};c.showEnding=()=>{throw Error('cosmetic rendering failed');};c.finish(false,'ko');assert.equal($('end-title').textContent,'결과 표시 오류');assert(!$('end-screen').classList.contains('end-pending'));assert.equal($('share-btn').disabled,true);assert.equal(c.S.endVoice,null);
 console.log('PASS real pending/error/retry UI: clear failure, no fake win/share, server DEFEAT and cosmetic-failure fallback rendered');
}
