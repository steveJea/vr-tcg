import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {startVerified,finishVerified,recoverVerified,sweepVerified} from '../js/guildbattle-session.js';
const ls=new Map(),calls=[];globalThis.localStorage={getItem:k=>ls.get(k)||null,setItem:(k,v)=>ls.set(k,v),removeItem:k=>ls.delete(k)};
let fail=false,issued=0,active,receipt;
globalThis.window={VRAsk:async()=>true,VRCloud:{user:{id:'one'},sb:{rpc:async(n,a)=>{calls.push([n,a]);if(n==='guildbattle_lookup_v4')return {data:active};if(fail)throw Error('network');return {data:{result:{damage:42}}};},functions:{invoke:async(n,{body})=>{
 calls.push([n,body]);if(fail)throw Error('network');if(body.op==='start'){issued++;active={ok:true,id:String(issued),kind:body.kind};return {data:active};}if(body.op==='status')return {data:{ok:true,status:receipt?'settled':'issued',result:receipt}};receipt={damage:42};return {data:{ok:true,status:'settled',result:receipt}};
}}}}};
const s=await startVerified('raid',{uids:['owned']},'actions');fail=true;await assert.rejects(finishVerified('raid',s,[{k:'end'}]),/network/);assert(ls.size>0);await assert.rejects(startVerified('raid',{uids:['owned']},'actions'),/이전/);
fail=false;assert.deepEqual(await recoverVerified('raid'),{damage:42});assert.equal(ls.size,0);assert.equal(issued,1);
receipt=null;await startVerified('war',{slot:1,deck:1},'auto');window.VRCloud.user.id='two';await assert.rejects(finishVerified('war',{id:'2',_owner:'one'},null),/계정/);assert.equal(await recoverVerified('war'),null);window.VRCloud.user.id='one';assert.deepEqual(await recoverVerified('war'),{damage:42});assert.equal(ls.size,0);
fail=true;await assert.rejects(sweepVerified(window.VRCloud.sb.rpc),/network/);const first=calls.at(-1)[1].p_request;fail=false;await sweepVerified(window.VRCloud.sb.rpc);assert.equal(calls.at(-1)[1].p_request,first);
// A lost START response is resolved by authenticated UUID lookup, not a new attempt.
fail=true;await assert.rejects(startVerified('raid',{uids:['owned']},'auto'),/network/);active={ok:true,id:'99'};receipt=null;fail=false;const previous=issued;await recoverVerified('raid');assert.equal(issued,previous);assert.equal(ls.size,0);
for(const file of ['raid','war']){const ui=await readFile(new URL('../js/'+file+'.js',import.meta.url),'utf8');assert(!/rpc\('(raid|war)_(start|finish|log)'/.test(ui));assert(!/p_damage:|p_win:|p_atk_hp:|p_def_hp:/.test(ui));assert(ui.includes('finishVerified'));assert(ui.includes('recoverVerified'));}
const engine=await readFile(new URL('../tools/guildbattle-engine-entry.mjs',import.meta.url),'utf8');assert(!/\breplay\(/.test(engine));assert(engine.includes('strict:true'));
console.log('Phase4 UI PASS: no reported outcomes/raw legacy writes, durable finish/start/sweep retry, per-account pending state and authoritative receipts');
