import assert from 'node:assert/strict';
import vm from 'node:vm';
import { readFile } from 'node:fs/promises';
import { createHandler } from '../supabase/functions/pvp-verify-v3/handler.mjs';
const src=await readFile(new URL('../js/pvp.js',import.meta.url),'utf8');
for(const old of ['pvp_start','pvp_log','pvp_report']) assert(!new RegExp(`rpc\\('`+old+`'`).test(src),'ranked legacy RPC must not be called');
const ranked=src.slice(src.indexOf('async function fight()'),src.indexOf('// ---- 수동:'));
assert(!ranked.includes('p_wins:')&&!ranked.includes('p_losses:'));
assert(src.includes("sb.functions.invoke('pvp-verify-v3'"));
assert(src.includes('rep.rounds.map') && !src.includes('rep ? rep.delta : -s.dl'));
const block=(start,end)=>src.slice(src.indexOf(start),src.indexOf(end,src.indexOf(start)));
let starting=null,stored=null,calls=[],shown=[],localRuns=0,fail=false,live=false,buttons={};
const session={id:'42',mode:'1v1',me:[[]],opp:[[]],seed:123};
const official={ok:true,verified:true,win:false,wins:0,losses:1,rounds:[{win:false}],rating:984,delta:-16};
const ctx=vm.createContext({
 console,crypto:{randomUUID:()=> 'aaaaaaaa-aaaa-4aaa-8aaa-000000000001'},PVP_ENGINE_VERSION:'version',view:{league:'open',mode:'1v1'},
 document:{querySelector:()=>null},battleMode:()=> 'auto',VIEW:()=>live?{}:null,
 verifyRpc:async body=>{calls.push(body);if(body.op==='start')return {...session,control:body.control};if(fail)throw new Error('network');return official;},
 pendingStart:value=>value===undefined?starting:(starting=value),pendingResult:value=>value===undefined?stored:(stored=value),showResult:(s,r)=>shown.push(r),vsScreen:async()=>{},card:()=>{},snapCard:()=>{},
 runSeries:()=>{localRuns++;return {win:true,wins:1,losses:0,rounds:[{win:true}]};},viewSeries:async()=>({acts:[[{k:'end'}]],win:true}),
 playback:async()=>{},toast:()=>{},errText:e=>e.message,esc:String,open:async()=>{},
 modal:()=>({querySelector:s=>(buttons[s] ||= {})})
});
vm.runInContext(block('async function finishVerified(body) {','const pendingKey'),ctx);
vm.runInContext(block('async function fight() {','function showResult'),ctx);
vm.runInContext(block('async function retryResult() {','const ERR ='),ctx);
await vm.runInContext('fight()',ctx);
assert.equal(calls[0].op,'start');assert.equal(calls[0].control,'auto');assert.equal(calls[1].op,'finish');assert.equal(calls[1].actions,null);
assert.deepEqual(Object.keys(calls[1]).sort(),['actions','id','op']);
assert.equal(shown[0],official,'official server loss overrides local win');assert.equal(stored,null);
shown=[];calls=[];fail=true;await vm.runInContext('fight()',ctx);
assert.equal(shown.length,0,'network errors must not display a fabricated local official win/rating');
assert.equal(stored.body.id,'42');const saved=JSON.stringify(stored.body);assert(buttons['[data-retry]'].onclick);
fail=false;calls=[];await vm.runInContext('retryResult()',ctx);
assert.equal(calls.length,1);assert.equal(JSON.stringify(calls[0]),saved,'retry exact transcript, never create another attempt');assert.equal(stored,null);
shown=[];calls=[];live=true;await vm.runInContext('fight()',ctx);assert.equal(calls[0].control,'actions');assert.equal(calls[1].actions[0][0].k,'end');
assert.equal(localRuns,2);
// Reload after an engine upgrade must not repeatedly submit a saved old version.
starting={op:'start',league:'open',mode:'1v1',request:'bbbbbbbb-bbbb-4bbb-8bbb-000000000002',control:'actions',version:'old-version'};
calls=[]; await vm.runInContext('fight()',ctx);
assert.equal(calls[0].version,'version'); assert.notEqual(calls[0].request,'bbbbbbbb-bbbb-4bbb-8bbb-000000000002'); assert.equal(starting,null);
// Same-version network retries retain the original request identity.
const retryStart={op:'start',league:'open',mode:'1v1',request:'bbbbbbbb-bbbb-4bbb-8bbb-000000000003',control:'actions',version:'version'};
starting=retryStart; calls=[]; await vm.runInContext('fight()',ctx); assert.equal(calls[0],retryStart);

// The invocation helper itself retries the identical body and extracts safe Edge error bodies.
let invokes=0; const body={op:'finish',id:'1',actions:null};
const transport=vm.createContext({window:{VRCloud:{sb:{functions:{invoke:async(name,args)=>{
 assert.equal(name,'pvp-verify-v3');assert.equal(args.body,body);invokes++;
 return invokes===1?{error:{message:'network'}}:{data:official};
}}}}},Error});
vm.runInContext(block('async function verifyRpc(body) {','const pendingKey'),transport);
transport.body=body; assert.equal(await vm.runInContext('verifyRpc(body)',transport),official);assert.equal(invokes,2);
let networkCalls=0;
const handler=createHandler({SUPABASE_URL:'https://cuyqchmdcnsgzkwyclji.supabase.co'},()=>{networkCalls++;throw Error('must not call');});
const huge=await handler(new Request('https://example.invalid',{method:'POST',headers:{'content-type':'application/json'},body:'x'.repeat(524289)}));assert.equal(huge.status,413);
assert.equal((await handler(new Request('https://example.invalid',{method:'GET'}))).status,405);
assert.equal((await handler(new Request('https://example.invalid',{method:'OPTIONS'}))).status,204);
assert.equal(networkCalls,0);
// A conflicting tab/expired first response resolves only to the saved official receipt.
transport.window.VRCloud.sb.functions.invoke=async(name,{body})=>body.op==='status'?{data:{ok:true,status:'settled',result:official}}:{error:{message:'submission conflict'}};
assert.equal(await vm.runInContext('finishVerified(body)',transport),official);
console.log('Phase3 UI: verified start/finish wiring, server result overrides, failed-settlement hold/retry, live action transcript, same-request/stale-version retries and bounded backend payload OK');
