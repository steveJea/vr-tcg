import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';
import {startArcadeVerified,finishArcadeVerified} from '../js/arcade-session.js';
import {createArcade} from '../js/arcade-core.js';
import {parseCSV,setCardPool,canSummon,RULES,allowedGrades} from '../js/rules.js';
import {setSkillData} from '../js/skills.js';
const rd=p=>readFile(new URL('../'+p,import.meta.url),'utf8'),ls=new Map(),calls=[];
globalThis.localStorage={getItem:k=>ls.get(k)||null,setItem:(k,v)=>ls.set(k,v),removeItem:k=>ls.delete(k)};
let fail=false,lost=false,issued=0,session,receipt,refresh=0;
globalThis.window={VRAsk:async()=>true,VRCloud:{user:{id:'one'},loadRecord:async()=>refresh++,sb:{functions:{invoke:async(name,{body})=>{
 assert.equal(name,'arcade-verify-v5');calls.push(body);if(fail)throw Error('network');
 if(body.op==='start'){if(session?.request!==body.request){issued++;session={ok:true,id:String(issued),seed:1,options:body.options,request:body.request};receipt=null;}return{data:session};}
 if(body.op==='status')return{data:{ok:true,status:receipt?'settled':'active',result:receipt}};
 receipt={result:body.op==='forfeit'?'lose':'win',verified:body.op!=='forfeit'};if(lost)throw Error('lost response');return{data:{ok:true,result:receipt}};
}}}}};
const options={grades:null,turns:10,clearFirst:false};
let s=await startArcadeVerified(options);assert.equal(issued,1);fail=true;
await assert.rejects(finishArcadeVerified(s,[{k:'end'}]),/network/);assert.equal(JSON.parse(ls.values().next().value).phase,'finish');
fail=false;s=await startArcadeVerified(options);assert.equal(issued,2);assert.equal(refresh,1);assert(calls.filter(b=>b.op==='finish').every(b=>!('result'in b)&&!('seed'in b)));
window.VRCloud.user.id='two';await assert.rejects(finishArcadeVerified(s,[]),/계정/);window.VRCloud.user.id='one';lost=true;
assert.equal((await finishArcadeVerified(s,[{k:'end'}])).result,'win','lost FINISH reply recovers original server status');assert.equal(ls.size,0);lost=false;
// Lost START request must retry the SAME UUID, not issue another random seed.
fail=true;await assert.rejects(startArcadeVerified(options),/network/);const request=calls.at(-1).request;fail=false;
s=await startArcadeVerified(options);assert.equal(calls.findLast(b=>b.request===request).request,request);assert(calls.some(b=>b.op==='forfeit'));
await finishArcadeVerified(s,null);
const game=await rd('js/game.js'),cloud=await rd('js/cloud.js');assert(!cloud.includes("sb.from('matches')"));assert(cloud.includes("sb.rpc('arcade_record_v5')"));assert(game.includes('if(!window.VRCloud?.user) Stats.record(win)'));
// Execute the ACTUAL UI start/action/turn adapter. Catches UI-only state divergence,
// first-player mixups, double mutation and lost AUTO scheduling that engine tests cannot.
const section=(a,b)=>{const i=game.indexOf(a),j=game.indexOf(b,i);assert(i>=0&&j>i,a);return game.slice(i,j);};
const pool=parseCSV(await rd('data/cards.csv'));setCardPool(pool);setSkillData(JSON.parse(await rd('data/skills.json')),JSON.parse(await rd('data/combos.json')));
const core=createArcade(1,options,pool),nodes=new Map();let aiCalls=0,autoCalls=0;
const ctx=vm.createContext({S:Object.assign(core.state,{arcade:core,busy:false}),selected:null,onEngine(){},flushHeldPassives(){ctx.S.holdPassive=null;},render(){},checkEnd:()=>false,onEnter(){},turnScroll(){},aiTurn:()=>aiCalls++,autoActive:()=>true,autoTurn:()=>autoCalls++,AI_DELAY:()=>0,setTimeout:f=>f()});
vm.runInContext(section('function startTurn(who) {','async function arcadeAiTurn()'),ctx);
vm.runInContext(`startTurn(S.arcade.nextWho)`,ctx);assert.equal(ctx.S.turn,ctx.S.first);assert.equal(core.state.totalTurns,1);
if(core.state.turn==='ai'){for(const a of core.plan())if(!core.result)core.act(a,'ai');vm.runInContext('startTurn(S.arcade.nextWho)',ctx);}
assert(autoCalls>0,'arcade AUTO must schedule after player turn start');
const card=core.state.me.hand.find(c=>canSummon(c,core.state.me,core.state.ai).ok);assert(card);const mana=core.state.me.mana;
ctx.intent={k:'summon',id:String(card.id)};vm.runInContext('arcadeSimple("me",intent)',ctx);assert.equal(core.state.me.mana,mana-card.cost);assert.equal(core.actions.length,1);assert.equal(core.state.me.field.length,1,'one summon, never UI+engine double mutation');
vm.runInContext(section('function endTurn() {','// ===== 엔딩'),ctx);vm.runInContext('endTurn()',ctx);assert.equal(aiCalls,ctx.S.first==='ai'?2:1);
// New session construction must use canonical first/decks/offers, not the discarded legacy coin.
assert(game.includes('first=S.first'));assert(game.includes('if(!S.arcade) initPlayers'));
console.log('phase5 UI: durable retries/lost responses, account isolation, no raw reports, actual arcade turn/AUTO/action adapters OK');

// Full startGame wrapper: a discarded local coin/options must never replace server context.
{
 let loads=0,called;const nodes=new Map(),node=id=>{if(!nodes.has(id))nodes.set(id,{classList:{add(){},remove(){},toggle(){}},style:{},parentElement:{classList:{toggle(){}}},textContent:'',innerHTML:''});return nodes.get(id);};
 const expected=createArcade(123,options,pool).state.first;
 const randomMath=Object.create(Math);randomMath.random=()=>expected==='me'?.99:.01;
 const c=vm.createContext({Math:randomMath,Event:class{},window:{VRCloud:{user:{id:'one'}}},startArcadeVerified:async()=>({seed:123,options,_owner:'one',id:'42'}),createArcade,POOL:pool,RULES,allowedGrades,
 ArcadeOpts:{DEF:options,load:()=>{loads++;return loads===1?options:{grades:['NORMAL'],turns:40,clearFirst:true};},isDefault:o=>o.grades===null&&o.turns===40&&!o.clearFirst,summary:()=>''},
 rngOn(){},AUTO_KEY:()=>'',localStorage:{getItem:()=>null},setSpare(){},newPlayer:()=>({}),Merc:{roll:()=>assert.fail('canonical merc offers must not reroll')},$:node,
 dockStoryBuff(){},setBattleBg(){},preloadHit(){},preloadFx(){},fxQueue:[],mrCancel:null,fitBoardSoon(){},initPlayers:()=>assert.fail('canonical skill/foe/first context must not initialize twice'),log(){},vsIntro:()=>null,startTurn:who=>{called=who;},GRADE_SHORT:{},render(){},crypto,setTimeout(){}});
 await vm.runInContext(section('async function startGame(', '/** 3-2 VS 인트로')+';startGame()',c);
 assert.equal(c.S.first,expected);assert.equal(called,expected);assert.equal(loads,1);assert.deepEqual(c.S.opts,options);assert.equal(c.S.me.clearFirst,false);
}
// Old VICTORY/share state must disappear while waiting; only the server verdict reaches showEnding.
{
 let resolve,shown;const nodes=new Map(),node=id=>{if(!nodes.has(id))nodes.set(id,{classList:{add(){},remove(){}},textContent:'old victory',innerHTML:'old victory',disabled:false});return nodes.get(id);};
 const c=vm.createContext({S:{arcadeSession:{},arcade:{result:{result:'win'},actions:[]},log:{total:999,skills:99},turnNo:99},$:node,finishArcadeVerified:()=>new Promise(r=>resolve=r),hideModal(){},TUT(){},finishFx:()=>0,window:{VRCloud:{user:{id:'one'}},dispatchEvent(){}},CustomEvent:class{},Stats:{record:()=>assert.fail('account must not increment local stats')},showEnding:(win)=>{shown=win;},pickMvp:()=>null,render(){},countUp(){},reportError(){},console,setTimeout:f=>f()});
 vm.runInContext(section('function finish(win, reason) {','// ===== 스토리 페이즈 규칙'),c);vm.runInContext("finish(true,'ko')",c);
 assert.equal(node('end-title').textContent,'검증 중');assert.equal(node('share-btn').disabled,true);assert.equal(c.S.endShare,null);assert.equal(shown,undefined);
 resolve({result:'lose',reason:'hp',damage:42,skills:2,turns:5});await Promise.resolve();await Promise.resolve();assert.equal(shown,false);assert.equal(c.S.log.total,42);assert.equal(c.S.turnNo,5);assert.equal(node('share-btn').disabled,false);
}
console.log('phase5 full UI: server-issued first/options preserved, no double init, pending victory/share cleared, authoritative receipt overrides local display OK');
