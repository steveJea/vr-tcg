// New Sheet 18–21 feedback: execute actual UI code with DOM/Audio/timer mocks.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { parseHTML } from 'linkedom';
import { parseCSV, setCardPool } from '../js/rules.js';
import { setSkillData } from '../js/skills.js';
import { createArcade } from '../js/arcade-core.js';
import { verifyBattle } from '../supabase/functions/_shared/arcade-engine-v5.mjs';
const source = fs.readFileSync('js/game.js', 'utf8');
const section = (from, to) => { const a=source.indexOf(from), b=source.indexOf(to,a); assert(a>=0&&b>a,from); return source.slice(a,b); };
const dom = () => parseHTML('<html><body><div id="arcade-verifying" class="hidden"></div><button id="home-btn"></button><div id="game"></div><div id="end-screen"></div><div id="me-dock"></div><div id="me-boss"></div><div id="ai-boss"></div><div id="me-hand"></div><div id="start-screen" class="hidden"></div></body></html>');
// 18: enemy attack focuses our field ABOVE the sticky hand/HUD, before effects.
{
 const {document}=dom();Object.defineProperty(document.documentElement,'scrollHeight',{value:2200});
 const dock=document.getElementById('me-dock');dock.getBoundingClientRect=()=>({top:540});
 const mine=document.getElementById('me-boss'),enemy=document.getElementById('ai-boss');
 for(const n of [mine,enemy])n.getBoundingClientRect=()=>({top:700,bottom:860,height:160});
 let scrolls=[];const c=vm.createContext({document,S:{turn:'ai',over:false},$:id=>document.getElementById(id),REDUCED:()=>false,window:{innerHeight:900,scrollY:0,scrollTo:o=>scrolls.push(o)},clearTimeout(){},setTimeout:f=>{if(!f.name)queueMicrotask(f);return 1;}});
 vm.runInContext(section('let peekOn =','function hitFx('),c);
 await c.peekBefore(mine);assert.equal(scrolls.length,1);assert.equal(scrolls[0].top,510);assert.equal(scrolls[0].behavior,'smooth');
 c.S.turn='me';await c.peekBefore(enemy);assert.equal(scrolls.length,2);
 c.window.TCG_FAST=true;await c.peekBefore(mine);assert.equal(scrolls.length,2);
 assert(!source.includes("if (who === 'me') await peekBefore(tEl)"));
 console.log('PASS 18 enemy/player target focus excludes sticky dock and precedes lunge');
}
// 19: battle prefetch = entry _0 only (skill voices via preloadSkillVoice for hand/field, 2026-11-12), including requests made before voice index resolves.
{
 const {document}=dom();let resolveIndex;const audios=[];
 class Audio {constructor(){audios.push(this);}addEventListener(){}pause(){} }
 const c=vm.createContext({document,S:null,performance:{now:()=>0},window:{VRVoice:{track(){}}},localStorage:{getItem:()=>null},Audio,fetch:()=>new Promise(r=>resolveIndex=r),skillsOf:()=>[{name:'skill'}],SWEEPING:()=>false,setTimeout(){},ic:()=>''});
 vm.runInContext(section('const VOICE_ON_KEY =','// ===== 효과음'),c);
 c.preloadVoice([{id:11}]);assert.equal(audios.length,0);
 resolveIndex({ok:true,json:async()=>['11_0','11_1','12_0']});for(let i=0;i<5;i++)await Promise.resolve();
 assert.deepEqual(audios.map(a=>a.src).sort(),['data/voice/11_0.mp3']);
 c.preloadVoice([{id:11},{id:12},{id:13}]);assert.equal(audios.length,2);
 c.preloadSkillVoice([{id:11},{id:13}]);assert.equal(audios.length,3);assert.equal(audios[2].src,'data/voice/11_1.mp3');assert(audios.every(a=>a.preload==='auto'));
 console.log('PASS 19 entry voices prefetch and late index catch-up without missing-file requests');
}
// 20: real keyed reconciliation keeps images across mana/class/sort/partial shuffle.
{
 const {document}=dom();let picked;const cards=[{id:1},{id:2},{id:3}];
 const c=vm.createContext({document,$:id=>document.getElementById(id),S:{me:{hand:cards},ai:{}},closeStaleHandDetail(){},renderSortBar(){},sortedHand:h=>h,canSummon:()=>({ok:c.ready}),cardHTML:x=>`<div><img class="card-img" src="img/thumb/${x.id}.webp" data-id="${x.id}"><b>${x.id}</b></div>`,showDetail:x=>picked=x,IMG:'full/'});c.ready=true;
 vm.runInContext(section('function sameCheck(','/** 진영 HP 글자:')+`function renderHand(){const myTurn=true;${section('  closeStaleHandDetail();','// ===== 손패 정렬')}`,c);
 c.renderHand();const hand=document.getElementById('me-hand'), old=hand.children[1],image=old.querySelector('img');
 c.ready=false;c.renderHand();assert.equal(hand.children[1],old);assert.equal(old.querySelector('img'),image);assert(old.className.includes('opacity-60'));
 c.S.me.hand=[cards[2],cards[1],{id:4}];c.renderHand();assert.equal(hand.children[1],old);assert.equal(old.querySelector('img'),image);assert.deepEqual([...hand.children].map(x=>x.dataset.id),['3','2','4']);
 const latest={id:2,changed:true};c.S.me.hand=[latest,{id:2}];c.renderHand();assert.equal(hand.childElementCount,2);assert.notEqual(hand.children[0].dataset.uid,hand.children[1].dataset.uid);hand.children[0].onclick();assert.equal(picked,latest);
 // Bounded thumbnail warming, visible + two upcoming draws, never full-deck art flood.
 const seen=[],fx=[];class Image {constructor(){seen.push(this);}}
 const media=vm.createContext({Image,cardThumb:id=>`img/thumb/${id}.webp`,preloadFx:cs=>fx.push(cs.map(x=>x.id)),S:{me:{hand:[{id:1}],field:[],deck:[{id:2},{id:3},{id:4}]},ai:{hand:[],field:[{card:{id:5}}],deck:[]}}});
 vm.runInContext(section('const thumbWarmed =','// 상세 창 초상화:'),media);media.primeBattleMedia();media.primeBattleMedia();assert.equal(seen.length,4);assert(!fx[0].includes(4));assert(seen.every(x=>x.fetchPriority==='high'));
 media.warmThumbs(Array.from({length:120},(_,id)=>({id})));assert.equal(vm.runInContext('thumbWarmed.size',media),96);
 console.log('PASS 20 hand image-node reuse, latest click bindings, duplicate IDs, bounded visible/next thumbnail warmup');
}
function lifecycleContext(){
 const {document}=dom(),timers=new Map();let timer=0,stops=0,plays=0;
 const c=vm.createContext({document,$:id=>document.getElementById(id),S:{over:true},window:{VRVoice:{stopAll:()=>stops++}},voiceCur:{pause:()=>stops++,currentTime:7},setTimeout:f=>{timers.set(++timer,f);return timer;},clearTimeout:id=>timers.delete(id),FX_OFF:()=>false,play:()=>plays++});
 vm.runInContext(section('function setArcadeWait(','// ===== 스토리 페이즈 규칙')+section('let battleViewEpoch =','// ===== 스킬 ====='),c);
 return {c,document,timers,flush:()=>{const fs=[...timers.values()];timers.clear();fs.forEach(f=>f());},get plays(){return plays;},get stops(){return stops;}};
}
// 21: navigation stops playing voices AND cancels pending callbacks (not a 150ms grace).
{
 const h=lifecycleContext(),{c,document}=h;c.queueEndingVoice(c.play);c.leaveBattleVoices();assert.equal(h.timers.size,0);assert.equal(h.stops,2);assert.equal(c.voiceCur.currentTime,0);h.flush();assert.equal(h.plays,0);
 c.queueEndingVoice(c.play);document.getElementById('end-screen').classList.add('hidden');h.flush();assert.equal(h.plays,0);
 document.getElementById('end-screen').classList.remove('hidden');c.queueEndingVoice(c.play);c.S={over:true};h.flush();assert.equal(h.plays,0);
 c.queueEndingVoice(c.play);h.flush();assert.equal(h.plays,1);
 Object.assign(c,{Event:class{},ArcadeOpts:{load:()=>({})},startArcadeVerified:()=>new Promise(()=>{})});c.window.VRCloud={user:{id:'one'}};
 c.queueEndingVoice(c.play);vm.runInContext(section('async function startGame(','/** 3-2 VS 인트로')+';startGame()',c);assert.equal(h.timers.size,0,'stop before server start resolves');
 c.renderStats=()=>{};vm.runInContext(section("$('home-btn').onclick",'renderStats();\n// ===== 아케이드 설정'),c);c.queueEndingVoice(c.play);document.getElementById('home-btn').onclick();assert.equal(h.timers.size,0);assert(document.getElementById('game').classList.contains('hidden'));
 assert(source.includes("$('home-btn').onclick = () => { leaveBattleVoices();"));
 console.log('PASS 21 immediate restart/home stop, delayed-voice invalidation, hidden/new battle guard');
}
// Copy of 21: opaque verification state, still server authoritative; late results cannot reopen UI.
{
 assert.match(fs.readFileSync('index.html','utf8'),/#end-screen\.end-pending\s*\{\s*background:\s*#09090b/);
 for(const fail of [false,true]){
  const h=lifecycleContext(),{c,document}=h;for(const id of ['end-title','end-text','end-mvp-wrap','end-stats','end-share-msg','share-btn','restart-btn']){const n=document.createElement('div');n.id=id;document.body.appendChild(n);}
  let resolve,reject;Object.assign(c,{S:{arcadeSession:{},arcade:{result:{},actions:[]},log:{}},finishArcadeVerified:()=>new Promise((r,j)=>{resolve=r;reject=j;}),console});
  vm.runInContext(section('function finish(win, reason) {','// ===== 스토리 페이즈 규칙'),c);c.finish(true,'ko');
  assert(document.getElementById('end-screen').classList.contains('end-pending'));assert.equal(document.getElementById('end-title').textContent,'');assert(document.getElementById('end-screen').classList.contains('hidden'));
  c.leaveBattleVoices();document.getElementById('game').classList.add('hidden');document.getElementById('end-screen').classList.add('hidden');
  if(fail)reject(Error('offline'));else resolve({result:'lose',reason:'hp',damage:42,skills:2,turns:5});for(let i=0;i<4;i++)await Promise.resolve();
  assert(document.getElementById('end-screen').classList.contains('hidden'));assert.equal(document.getElementById('end-title').textContent,'');assert(document.getElementById('end-screen').classList.contains('hidden'));if(!fail)assert.equal(c.S.arcadeSettled,true);
 }
 console.log('PASS 21 copy hidden pending result, spinner cleanup, authoritative receipt retained after home without reopening result');
}
// Related phase5 integration defect: dragging must log canonical move intents, not mutate silently.
{
 const pool=parseCSV(fs.readFileSync('data/cards.csv','utf8'));setCardPool(pool);setSkillData(JSON.parse(fs.readFileSync('data/skills.json')),JSON.parse(fs.readFileSync('data/combos.json')));
 let moved=0;
 for(let seed=1;seed<=8;seed++){
  const options={grades:null,turns:40,clearFirst:false},core=createArcade(seed,options,pool),c=vm.createContext({S:Object.assign(core.state,{arcade:core,busy:false}),arcadeSimple:(who,a)=>core.act(a,who)});
  vm.runInContext(section('function moveFieldCard(','function enableDrag('),c);let dragged=false;
  while(!core.result){if(core.nextWho)core.begin(core.nextWho);if(core.result)break;const who=core.state.turn;
   if(who==='me'&&!dragged){const units=core.state.me.field.filter(u=>!u.undying);if(units.length>=3){const guard=core.state.me.field.find(u=>u.undying),pos=core.state.me.field.indexOf(guard),u=units[0];c.moveFieldCard(u,2);assert.equal(core.state.me.field.filter(u=>!u.undying)[2],u);if(guard)assert.equal(core.state.me.field.indexOf(guard),pos);assert(core.actions.slice(-2).every(a=>a.k==='move'));dragged=true;moved++;}}
   for(const a of core.plan(who))if(!core.result)core.act(a,who);
  }
  assert.deepEqual(verifyBattle({seed,options},core.actions),core.result);
 }
 assert(moved>0);console.log(`PASS extra arcade drag recorded through legal moves; ${moved} dragged games replay identically on unchanged Edge`);
}
