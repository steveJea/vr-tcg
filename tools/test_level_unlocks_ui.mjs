import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {parseHTML} from 'linkedom';
import vm from 'node:vm';
const rd=p=>readFile(new URL('../'+p,import.meta.url),'utf8');
const policy=JSON.parse(await rd('tools/unlocks/policy.json'));
const dom=parseHTML(`<html><head></head><body><div id="start-screen"><button id="main-pvp">PvP</button><button id="main-guild">조직</button><button id="main-trade">거래소</button><button id="arcade">아케이드</button><button id="shop">상점</button></div><div id="story-screen" class="hidden"></div><div id="game" class="hidden"></div></body></html>`);
const w=dom.window,d=w.document;
const listeners=[];const add=d.addEventListener.bind(d);d.addEventListener=(type,fn,capture)=>{listeners.push({type,fn,capture});return add(type,fn,capture);};
const ctx=vm.createContext({window:w,document:d,console,Map,Set,Array,Object,Date,Promise,Event:w.Event,MutationObserver:w.MutationObserver,setInterval:()=>0,setTimeout:()=>0,clearInterval:()=>{},getComputedStyle:()=>({display:'block'})});
const evaluate=src=>vm.runInContext(src,ctx);
let level=1, requests=[], opens=0;
const entries=structuredClone(policy.entries).map(e=>({...e,eligible:false,claimed:false,action_done:true}));
w.VRPlayer={now:()=>({level}),setWallet:()=>{}};
w.VRCloud={user:{id:'fixture'},sb:{rpc:async(name,args)=>{
 requests.push({name,args});
 if(name==='unlock_status')return {data:{level,entries:structuredClone(entries)}};
 if(name==='unlock_intro_claim'){entries.find(e=>e.key===args.p_event).claimed=true;return {data:{ok:true}};}
 throw Error('unexpected RPC '+name);
}}};
w.VRQuest={open:()=>{opens++;}};
evaluate(await rd('js/unlock-policy.js'));evaluate(await rd('js/unlocks.js'));
const U=w.VRUnlocks;
for(const[key,n]of Object.entries(policy.features)){level=n-1;assert.equal(U.allowed(key),false,key);level=n;assert.equal(U.allowed(key),true,key);}
level=1;U.paint();
const gnb=d.createElement('button');gnb.className='gnb-t';gnb.dataset.gnb='tower';gnb.textContent='탑';d.body.append(gnb);
U.paint();
assert.equal(gnb.querySelector('.ul-lock'),null,'bottom tabs have no Lv badge');
assert.equal(gnb.classList.contains('ul-locked'),true);
assert.equal(d.querySelector('#main-pvp .ul-lock').textContent,'🔒 Lv3');
assert.equal(d.querySelector('#main-guild .ul-lock').textContent,'🔒 Lv6');
assert.equal(d.querySelector('#main-trade .ul-lock').textContent,'🔒 Lv15');
assert.equal(d.querySelector('#arcade .ul-lock'),null);assert.equal(d.querySelector('#shop .ul-lock'),null);
let clicks=0;const capture=listeners.find(x=>x.type==='click'&&x.capture===true).fn;
function clickPvp(){let stopped=false;capture({target:d.querySelector('#main-pvp'),preventDefault(){},stopImmediatePropagation(){stopped=true;}});if(!stopped)clicks++;}
clickPvp();assert.equal(clicks,0);assert.equal(d.querySelector('#ul-lockpop'),null,'lobby tiles keep the toast, not the tab popup');
let gnbStopped=false;capture({target:gnb,preventDefault(){},stopImmediatePropagation(){gnbStopped=true;}});
assert.equal(gnbStopped,true);assert.match(d.querySelector('#ul-lockpop p').textContent,/계정레벨 10 이후 이용할 수 있어요/);
d.querySelector('#ul-lockpop button').click();assert.equal(d.querySelector('#ul-lockpop'),null);
level=3;U.paint();assert.equal(d.querySelector('#main-pvp .ul-lock'),null);clickPvp();assert.equal(clicks,1);
assert.equal(gnb.classList.contains('ul-locked'),true,'tower tab stays locked at the pvp level');
entries.find(e=>e.key==='pvp_hr').eligible=true;
d.querySelector('#game').classList.remove('hidden');await U.tick();assert.equal(d.querySelector('#unlock-intro'),null);assert.equal(requests.length,0);
d.querySelector('#game').classList.add('hidden');
const video=d.createElement('div');video.id='story-video';d.body.append(video);await U.tick();assert.equal(d.querySelector('#unlock-intro'),null);video.remove();
const dialogue=d.createElement('div');dialogue.className='story-ovp';d.body.append(dialogue);await U.tick();assert.equal(d.querySelector('#unlock-intro'),null);dialogue.remove();
await U.tick();assert.equal(d.querySelectorAll('#unlock-intro').length,1);assert.match(d.querySelector('#unlock-title').textContent,/PvP/);
// A new battle/video immediately defers a displayed intro, without granting anything.
d.querySelector('#game').classList.remove('hidden');await U.tick();assert.equal(d.querySelector('#unlock-intro'),null);assert.equal(requests.filter(x=>x.name==='unlock_intro_claim').length,0);
d.querySelector('#game').classList.add('hidden');await U.tick();assert(d.querySelector('#unlock-intro'));
d.querySelector('#unlock-intro button').click();await new Promise(r=>setImmediate(r));assert.equal(d.querySelector('#unlock-intro'),null);
await U.tick();assert.equal(d.querySelector('#unlock-intro'),null);assert.equal(requests.filter(x=>x.name==='unlock_intro_claim').length,1);
// Tower: only a normal battle, never a mandatory sweep. No premature reward request.
level=10;const tower=entries.find(e=>e.key==='tower');tower.eligible=true;tower.action_done=false;
await U.refresh(true);await U.tick();assert.equal(d.querySelector('#unlock-intro button').textContent,'한 판 도전');
d.querySelector('#unlock-intro button').click();assert.equal(opens,1);assert.equal(requests.filter(x=>x.name==='unlock_intro_claim').length,1);
await U.tick();assert.equal(d.querySelector('#unlock-intro'),null);
tower.action_done=true;await U.refresh(true);await U.tick();assert.equal(d.querySelector('#unlock-intro button').textContent,'확인');
d.querySelector('#unlock-intro button').click();await new Promise(r=>setImmediate(r));assert.equal(requests.filter(x=>x.name==='unlock_intro_claim').length,2);
// The real camp picker recommends the lowest level but sends the player's selection.
level=12;w.TCG={cardById:()=>({grade:'NORMAL',name:'인재'}),skillsOf:()=>[]};
evaluate(await rd('js/camp.js'));
const st={level:12,slots:[{slot:1,open:true,uid:null}],cap_minus:5,camp_lv:1};
w.VRCamp._set(st,[{uid:'high',id:'2',level:5},{uid:'low',id:'1',level:1}]);
w.VRCamp._mock=async(name,args)=>{requests.push({name,args});throw Error('fixture stop after selected RPC');};
w.VRCamp._pick(1);
assert.equal(d.querySelector('.camp-grid [data-recommended]').dataset.u,'low');
assert.equal(requests.some(x=>x.name==='camp_put'),false,'no forced auto assignment');
d.querySelector('.camp-grid [data-u="high"]').click();await new Promise(r=>setImmediate(r));
assert.equal(requests.find(x=>x.name==='camp_put').args.p_uid,'high');
for(const[file,key]of [['js/quest.js','tower'],['js/pvp.js','pvp_hr'],['js/guild.js','guild'],['js/raid.js','raid'],['js/war.js','war'],['js/dispatch.js','dispatch'],['js/camp.js','camp'],['js/friends.js','friends'],['js/trade.js','trade'],['js/gear.js','gear'],['js/story.js','merge']])assert((await rd(file)).includes(`VRUnlocks.guard('${key}')`),file+' direct guard');
// Facility UI is account-level based even when training-building level differs.
const facilityState={level:19,camp_lv:10,forge_lv:5,dojo_lv:8,forge_account_level:20,dojo_account_level:20,dojo_slots:0,dojo_max:7,dojo_next_cost:1500,jobs:[],slots:[{slot:1,open:true,need_level:12,uid:null}],next:{lv:3,need_level:25,cost:{gold:20000}}};
w.VRCamp._set(facilityState,[]);w.VRCamp._draw();
assert.equal(d.querySelector('[data-forge]'),null);assert.equal(d.querySelector('[data-dojounlock]'),null);
assert.equal(Array.from(d.querySelectorAll('#camp-box .camp-slot.locked button')).filter(b=>b.textContent==='Lv20').length,2);
level=20;await U.refresh(true);facilityState.level=20;facilityState.camp_lv=1;w.VRCamp._set(facilityState,[]);w.VRCamp._draw();
assert(d.querySelector('[data-forge]'),'forge opens at account20/camp1');assert(d.querySelector('[data-dojounlock]'),'dojo purchase is available at account20/camp1');
assert.equal(d.querySelector('[data-lvup]').textContent,'Lv25','training building account lock is unchanged');
assert.match(d.querySelector('[data-dojounlock]').textContent,/1,500/);
facilityState.dojo_slots=2;w.VRCamp._set(facilityState,[]);w.VRCamp._draw();assert.equal(d.querySelectorAll('[data-dojo]').length,2);
// Execute the actual chapter policy at account Lv1, including legacy grandfathering.
const story=await rd('js/story.js'), from=story.indexOf('  const chapterDone ='), to=story.indexOf('  async function checkChapters()',from);
const save={cleared:{0:[],1:[],2:[]},starter:'10111'};
const D={chapters:[{id:0,phases:[{no:1}]},{id:1,phases:[{no:1}]},{id:2,phases:[{no:1}]}]};
const storyCtx=vm.createContext({window:{VRPlayer:{now:()=>({level:1})}},D,save,chReady:{0:true,1:true,2:true},serverMode:true});
vm.runInContext(story.slice(from,to)+';globalThis.access={chapterOpen,ch0Pending};',storyCtx);
assert.equal(storyCtx.access.chapterOpen(1),false);assert.equal(storyCtx.access.ch0Pending(),true);
save.cleared[0]=[1];assert.equal(storyCtx.access.chapterOpen(1),true);assert.equal(storyCtx.access.chapterOpen(2),false);
save.cleared[1]=[1];assert.equal(storyCtx.access.chapterOpen(2),true,'CH2 opens at Lv1 on previous clear');
save.cleared[0]=[];assert.equal(storyCtx.access.ch0Pending(),false,'existing CH1 progress not sent back to CH0');
console.log('Level unlock UI: compact locks, exact boundaries, click guards, lobby-only single queue, no mid-video rewards, one normal battle, freely selected camp recommendation: OK');

