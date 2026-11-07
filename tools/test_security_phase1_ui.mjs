// Minimal browser-contract smoke: client events must not assert reward eligibility.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';
const calls=[],listeners=new Map(),box={textContent:''};
const document={readyState:'loading',body:{},
  querySelectorAll:()=>[],querySelector:()=>null,
  getElementById:id=>id==='gal-end'?box:null,addEventListener:()=>{}};
const window={VRCloud:{user:{id:'fixture'},sb:{rpc:async name=>{calls.push(name);return {data:null,error:null};}}},
  addEventListener:(name,fn)=>listeners.set(name,fn)};
const context=vm.createContext({window,document,console,Map,Set,Date,
  setTimeout:()=>0,setInterval:()=>0,MutationObserver:class{observe(){}},
  localStorage:{getItem:()=>{throw new Error('legacy pending queue must not be replayed');}}});
await vm.runInContext(await readFile(new URL('../js/daily.js',import.meta.url),'utf8'),context);
await vm.runInContext(await readFile(new URL('../js/gallery.js',import.meta.url),'utf8'),context);
assert(window.VRDaily && window.VRGallery,'scripts initialize with exports intact');
for(let i=0;i<40;i++) listeners.get('vr:daily')({detail:{k:'skill',n:999}});
listeners.get('vr:daily')({detail:{k:'battle',mode:'arcade',win:true,n:2147483647}});
listeners.get('vr:match')({detail:{result:'win',fieldIds:['fake'],mvpId:'fake'}});
await new Promise(resolve=>setImmediate(resolve));
assert.deepEqual(calls,['daily_status','weekly_status'],'only authoritative status reads, never kind/n or gallery writes');
assert.equal(box.textContent,'도감·MVP 반영 보류');
console.log('Browser event smoke: no counter/register RPC, no pending replay, exports intact: OK');
