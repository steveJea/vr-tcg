// Execute the actual war module in a real DOM implementation; no network/account data.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {parseHTML} from 'linkedom';
import * as controls from '../js/war-deck-controls.js';
import {warCard,warDeck,WAR_ROLES} from '../js/war-core.js';
import {hitCap,runRaid} from '../js/raid-core.js';
import {parseCSV,setCardPool} from '../js/rules.js';
import {setSkillData} from '../js/skills.js';
import {verifyBattle} from '../supabase/functions/_shared/guildbattle-engine-v4.mjs';
const src=fs.readFileSync('js/war.js','utf8'),game=fs.readFileSync('js/game.js','utf8');
const pool=parseCSV(fs.readFileSync('data/cards.csv','utf8')),npc=parseCSV(fs.readFileSync('data/npc_cards.csv','utf8'));
setCardPool(pool);setSkillData(JSON.parse(fs.readFileSync('data/skills.json')),JSON.parse(fs.readFileSync('data/combos.json')));
const byReal=id=>[...pool,...npc].find(c=>String(c.id)===String(id));
const cards=pool.slice(0,8).map((c,i)=>({...c,name:['가람','나리','다솜','라온','마루','바다','사랑','아라'][i],cost:i*5}));
const by=id=>cards.find(c=>String(c.id)===String(id))||byReal(id);
const own=cards.map((c,i)=>({uid:'u'+i,id:String(c.id),name:c.name,level:30,ex:0,boost:{},skillLv:{'1':3},power:100+i}));
own.push({...own[0],uid:'duplicate',level:40,power:9999});
const snap=o=>{const {name,power,...s}=o;return s;};
const enemy={slot:1,role:'def',name:'테스트 방어조',npc:true,cards:[{id:own[2].id,level:30,hp:50,snapshot:snap(own[2])}],deck:1,decks:2};
const fixture=()=>({ok:true,phase:'signup',season:'2026-11-03',season_end:'2026-11-07',day:5,guild:{role:'boss',members:14},entry:{locked:false},roster:[{user_id:'owner',slot:14,role:'boss'}],decks:{def1:[snap(own[0])],def2:[snap(own[1])],atk1:[snap(own[0])],atk2:null},numbers:{roles:WAR_ROLES,points:{def:10,atk:10,mid:10,boss:10,etc:10}},match:{id:42,ended:false,score_me:0,score_opp:0,opponent:{name:'상대'},gate_open:false,me:{slot:14,alive:true,attacks_left:5,atk:{}},enemy:[structuredClone(enemy)],mine:[]}});
const tick=async()=>{for(let i=0;i<40;i++)await Promise.resolve();};
const deferred=()=>{let resolve;const promise=new Promise(r=>resolve=r);return {promise,resolve};};
function harness() {
 const {window,document}=parseHTML('<html><body><div id="page"></div><div id="detail" class="hidden"></div></body></html>');
 // linkedom exposes a getter only; browsers support assigning select.value.
 Object.defineProperty(window.HTMLSelectElement.prototype,'value',{configurable:true,get(){return [...this.options].find(o=>o.selected)?.value||this.options[0]?.value||'';},set(v){for(const o of this.options)o.selected=o.value===String(v);}});
 let state=fixture(),summary=async()=>({ok:true,owned:structuredClone(own),decks:[{name:'보관 덱',uids:['u2','u3']}]});
 const calls=[],infos=[],timers=[],details={closed:0},hooks={};let setDeferred=null,statusDeferred=null,starts=0,current=null;
 window.VRCloud={user:{id:'owner'}};window.VRAsk=async()=>true;
 window.VRStory={summary:()=>summary(),save:{owned:own},api:{statsOf:o=>warCard(snap(o),by)}};
 window.TCG={cardById:by,showCardInfo:(c,opt)=>{infos.push({c,opt});document.getElementById('detail').classList.remove('hidden');},closeDetail:()=>{details.closed++;document.getElementById('detail').classList.add('hidden');}};
 window.__WAR_MOCK=async(name,args)=>{calls.push([name,args]);if(name==='war_status'){if(statusDeferred){const d=statusDeferred;statusDeferred=null;return d.promise;}return structuredClone(state);}if(name==='war_ui')return {ok:true};if(name==='war_meta')return {ok:true,need_deck:false};if(name==='war_set_deck'){if(setDeferred){const d=setDeferred;setDeferred=null;return d.promise;}state.decks[args.p_kind]=args.p_uids.map(u=>snap(own.find(o=>o.uid===u)));return {ok:true,decks:structuredClone(state.decks)};}throw Error('Unexpected RPC '+name);};
 window.VRPages={get current(){return current;},host(name,title,root,leave,show){if(hooks.leave)hooks.leave();current=name;Object.assign(hooks,{root,leave,show});root.classList.add('vr-in-page');document.getElementById('page').replaceChildren(root);show();}};
 const ctx=vm.createContext({window,document,console,Object,Map,Set,Date,Promise,cardThumb:id=>`img/${id}.webp`,...controls,warCard,warDeck,WAR_ROLES,modeToggle:()=>'',bindMode:()=>{},battleMode:()=> 'auto',startVerified:async()=>{starts++;throw Error('Setup must not start a battle');},finishVerified:async()=>null,recoverVerified:async()=>null,setTimeout:(fn,ms)=>{timers.push({fn,ms});return timers.length;},clearTimeout:()=>{},setInterval:()=>{throw Error('No cross-page editor polling allowed');}});
 vm.runInContext(src.replace(/^import .*;\n/gm,'').replaceAll('export ',''),ctx);
 const el=sel=>document.querySelector(sel),click=async sel=>{const e=el(sel);assert(e,'missing '+sel+' '+document.body.innerHTML);assert(!e.disabled,'disabled '+sel);e.click();await tick();return e;};
 return {window,document,calls,infos,details,el,click,tick,open:()=>window.VRWar.open(),get state(){return state;},set state(s){state=s;},get starts(){return starts;},setSummary:f=>{summary=f;},delaySave:d=>setDeferred=d,delayStatus:d=>statusDeferred=d,
 nav(name='tower'){hooks.leave?.();current=name;document.getElementById('page').replaceChildren();},showWar(){current='war';document.getElementById('page').appendChild(hooks.root);hooks.show();}};
}
// Pure candidate validation never mutates inventory, loses selected duplicate copies or accepts paired IDs.
{
 const before=structuredClone(own),r=controls.pickPool(own,['u0'],by);assert(r.some(o=>o.uid==='u0'));assert(!r.some(o=>o.uid==='duplicate'));
 assert.equal(controls.pickPool(own,[],by)[0].uid,'duplicate');
 assert.deepEqual(controls.pickPool(own,[],by,' 가 ',0,'cost').map(o=>o.id),[own[0].id]);
 assert(controls.draftProblem(['u0','duplicate'],own));assert(controls.draftProblem(['u0'],own,[own[0]]));assert(controls.draftProblem(['not-owned'],own));assert(controls.draftProblem([],own));assert.equal(controls.draftProblem(['u2','u3'],own,[own[0]]),'');assert.deepEqual(own,before);
}
{
 const h=harness();await h.open();await h.click('[data-decks]');assert(h.el('[data-war-deck]'));
 await h.click('[data-edit-kind="def1"]');assert(h.el('.wr-owned'));assert(h.el('[data-pick="u0"]').getAttribute('aria-pressed')==='true');assert(h.el('[data-pick="u1"]').disabled);
 await h.click('[data-pick="u2"]');await h.click('[data-cancel]');assert.equal(h.calls.filter(([n])=>n==='war_set_deck').length,0);
 await h.click('[data-edit-kind="def1"]');assert.equal(h.el('[data-count]').textContent,'1/5');
 await h.click('[data-reset]');assert.equal(h.el('[data-count]').textContent,'0/5');assert(h.el('[data-save]').disabled);assert.equal(h.state.decks.def1.length,1);
 await h.click('[data-pick="u2"]');await h.click('[data-pick="u3"]');await h.click('[data-save]');
 assert.deepEqual(Array.from(h.calls.find(([n])=>n==='war_set_deck')[1].p_uids),['u2','u3']);assert(h.el('[data-edit-kind="def1"]'));
 h.window.VRAsk=async()=>false;await h.click('[data-release="def2"]');assert.equal(h.state.decks.def2.length,1);
 h.window.VRAsk=async()=>true;await h.click('[data-release="def2"]');assert.equal(h.state.decks.def2.length,0);assert.equal(h.state.decks.def1.length,2);
 h.state.phase='live';h.state.entry.locked=true;h.state.match.me.atk={'1':{alive:0}};await h.open();await h.click('[data-decks]');assert(h.el('[data-edit-kind="def1"]').disabled);assert(h.el('[data-edit-kind="atk1"]').disabled);assert(!h.el('[data-edit-kind="atk2"]').disabled);
}
console.log('PASS #8/#13/#15 direct editor, selected-copy preservation, paired-ID ownership checks, draft cancel/clear, explicit save, confirmed optional release, server season/used-deck locks');
{
 const h=harness();h.state.phase='live';await h.open();await h.click('[data-aj="1"]');assert(h.el('[data-compose="atk2"]'));
 await h.click('[data-card="0"]');const shown=h.infos.at(-1),expected=warCard(enemy.cards[0].snapshot,by,{atk:1,def:1.2});assert.equal(shown.c.DEF,expected.DEF);assert.equal(shown.opt.hp,50);assert.equal(shown.opt.level,30);assert.deepEqual(shown.c.skillLv,own[2].skillLv);
 h.window.TCG.closeDetail();await h.click('[data-compose="atk2"]');assert(h.el('.wr-owned'));assert(h.el('[data-pick="duplicate"]').disabled);await h.click('[data-pick="u1"]');await h.click('[data-save]');assert(h.el('[data-go="2"]'));assert(!h.el('[data-go="2"]').disabled);assert.equal(h.starts,0,'setup never reserves an attempt');
 h.nav();assert.equal(h.document.querySelectorAll('[data-war-overlay]').length,0);assert(h.details.closed>0);h.showWar();await tick();assert.equal(h.document.querySelectorAll('[data-war-overlay]').length,0,'return does not resurrect deck windows');
}
console.log('PASS #11/#12 empty attack2 direct setup and same-target return without battle/entry; frozen level/skill/role/HP details; page-owned detail cleanup');
{
 const h=harness();await h.open();const d=deferred();h.setSummary(()=>d.promise);const pending=h.click('[data-decks]');await tick();h.nav();d.resolve({ok:true,owned:own,decks:[]});await pending;await tick();assert.equal(h.document.querySelectorAll('.wr-pop').length,0);
 h.showWar();assert.equal(h.document.querySelectorAll('[data-war-overlay]').length,0);
 h.setSummary(async()=>({ok:true,owned:own,decks:[]}));await h.click('[data-decks]');await h.click('[data-edit-kind="atk2"]');await h.click('[data-pick="u1"]');const save=deferred();h.delaySave(save);const saving=h.click('[data-save]');await tick();h.nav();save.resolve({ok:true,decks:{...h.state.decks,atk2:[snap(own[1])]}});await saving;await tick();assert.equal(h.document.querySelectorAll('.wr-pop').length,0);
 const h2=harness(),status=deferred();h2.delayStatus(status);const opening=h2.open();h2.nav();status.resolve(fixture());await opening;assert.equal(h2.document.querySelectorAll('.wr-pop').length,0);
 const h4=harness();await h4.open();await h4.click('[data-decks]');await h4.click('[data-edit-kind="atk2"]');await h4.click('[data-pick="u1"]');h4.window.VRCloud.user.id='other';await h4.click('[data-save]');await h4.click('[data-own-info="u1"]');assert.equal(h4.calls.filter(([n])=>n==='war_set_deck').length,0);assert.equal(h4.infos.length,0);
 const h3=harness();await h3.open();const account=deferred();h3.setSummary(()=>account.promise);await h3.click('[data-decks]');h3.window.VRCloud.user.id='other';account.resolve({ok:true,owned:own,decks:[]});await tick();assert.equal(h3.document.querySelectorAll('[data-war-overlay]').length,0);
}
assert(!src.includes('goEdit(')&&!src.includes('setInterval('));
console.log('PASS #14 pending summary/save/status, navigation/back and account switch cannot reopen or leak an old war editor into tower; polling removed');
// Real damage aggregation: 6000 twice is TWO hits, not an extra multiplier. Other modes retain ×n.
{
 let now=0;const {document}=parseHTML('<html><body></body></html>');const ctx=vm.createContext({Map,performance:{now:()=>now}});
 vm.runInContext(game.slice(game.indexOf('const fxStacks ='),game.indexOf('function dmgNumber(')),ctx);
 const d=document.createElement('div');document.body.appendChild(d);let r=ctx.fxStackSlot('boss','-6,000','hits');r.push(d);assert(ctx.fxStackSlot('boss','-6,000','hits').merged);assert.equal(d.dataset.n,'2타');assert(ctx.fxStackSlot('boss','-6,000','hits').merged);assert.equal(d.dataset.n,'3타');now=1000;assert(!ctx.fxStackSlot('boss','-6,000','hits').merged);
 r=ctx.fxStackSlot('normal','-10');const n=document.createElement('div');document.body.appendChild(n);r.push(n);ctx.fxStackSlot('normal','-10');assert.equal(n.dataset.n,'×2');
 assert(game.includes("extra.split(/\\s+/).includes('fx-dmg-raid') ? 'hits' : 'times'"));assert(game.includes('행동당 상한 ${fmt(raid.cap)}'));
 assert.equal(hitCap(1),6000);assert.equal(hitCap(2),6600);assert.equal(hitCap(3),7260);
 const strong=pool.filter(c=>c.grade==='MYTHIC RARE').slice(0,5).map((c,i)=>({uid:'raid'+i,id:String(c.id),level:70,ex:2}));assert(strong.length);
 const deck=strong.map(o=>warCard(o,byReal));const local=runRaid(deck,1,'normal',37,byReal);assert(local.damage>6000);assert.deepEqual(verifyBattle({kind:'raid',control:'auto',seed:37,stage:1,difficulty:'normal',deck:strong},null),local);
}
const css=fs.readFileSync('css/pages.css','utf8');assert(/#detail:not\(\.hidden\)\s*\{\s*z-index: 9660 !important/.test(css));assert(/#zoom-view.open\s*\{\s*z-index: 9680 !important/.test(css));
assert(game.includes('hp: opt.hp, level: opt.level ?? c.slv ?? c.level ?? 1'));assert(game.includes('skillListHTML(c, unit || view, myTurn, level, { skillLv: c.skillLv })'));
console.log('PASS #9/#10 stage action caps 6000/6600/7260, total >6000 and identical Edge replay, repeat-hit badge 2타/3타 with no arithmetic changes; detail/zoom layering and read-only skill levels');
