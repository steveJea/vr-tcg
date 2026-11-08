// Feedback 16-1: actor, lifetime, non-shortening, and canonical replay. Offline only.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {parseCSV,makeUnit,setCardPool,canAction} from '../js/rules.js';
import {setSkillData,initPlayers,placeUnit,useSkill,skillState,turnStart,turnEnd} from '../js/skills.js';
import {snapCard,manualMatch,runSeries,MODES,roundSeed} from '../js/pvp-core.js';
import {manualRaid,runRaid} from '../js/raid-core.js';
import {warDeck,warSession,runWar} from '../js/war-core.js';
import {verifyBattle as verifyPvp} from '../supabase/functions/_shared/pvp-engine-v3.mjs';
import {verifyBattle as verifyGuild} from '../supabase/functions/_shared/guildbattle-engine-v4.mjs';
const rd=p=>fs.readFileSync(new URL('../data/'+p,import.meta.url),'utf8');
const pool=parseCSV(rd('cards.csv')),npc=parseCSV(rd('npc_cards.csv')),by=new Map([...pool,...npc].map(c=>[String(c.id),c]));
setCardPool(pool);setSkillData(JSON.parse(rd('skills.json')),JSON.parse(rd('combos.json')));
const NAME='Tempus est discerpi',card=id=>by.get(String(id));
const side=name=>({name,hp:999999,maxHp:999999,mana:100,field:[],hand:[],deck:[],used:{},turnsTaken:1});
for(const role of ['A','B']) {
 const A=side('A'),B=side('B'),p=role==='A'?A:B,f=role==='A'?B:A;initPlayers(A,B,p);
 const u=placeUnit(p,card('10060'),makeUnit);u.level=8;u.mp=u.maxMp;u.canAttack=true;
 const foes=['10051','10053','10054'].map(id=>placeUnit(f,card(id),makeUnit));
 const skill=u.sk.find(s=>s.name===NAME);assert(useSkill(u,skill).ok);
 assert.equal(p.actionLock,0,'caster must not gain a self-lock');assert.equal(f.actionLock,1);
 assert(foes.every(t=>t.st.disrupt && !t.st.confuse),'original self-base disruption stays');
 assert(canAction('buff',p).ok,'caster can still use unique actions immediately');
 for(const action of ['shuffle','heal','buff','fieldheal','accel'])assert.equal(canAction(action,f).reason,'고유기술 봉인');
 turnEnd(p);assert.equal(f.actionLock,1,'caster turn end cannot consume opponent lock');
 const hp=f.hp;turnStart(f);assert(f.hp<hp,'opponent still attacks its own base');
 assert.equal(canAction('buff',f).reason,'고유기술 봉인','sealed throughout next opponent turn');
 turnEnd(f);assert.equal(f.actionLock,0);assert(foes.every(t=>!t.st.disrupt));assert(canAction('buff',f).ok);
}
// Do not erase another effect on the caster, or shorten a longer existing opponent seal.
{
 const p=side('P'),f=side('F');initPlayers(p,f,p);const u=placeUnit(p,card('10060'),makeUnit);placeUnit(f,card('10051'),makeUnit);
 u.level=8;u.mp=u.maxMp;u.canAttack=true;p.actionLock=1;f.actionLock=3;
 assert(useSkill(u,u.sk.find(s=>s.name===NAME)).ok);assert.equal(p.actionLock,1);assert.equal(f.actionLock,3);
}
let casts=0;
function play(st,holdForSkill=false) {
 let x=st.next(),n=0;
 while(!x.done) {
  assert(++n<20000);const v=x.value;
  if(v.anim?.k==='skill' && v.anim.s?.name===NAME){const actor=v.anim.side==='A'?v.A:v.B;assert(actor.foe.actionLock>=1);casts++;}
  let input;
  if(v.ask){const u=v.A.field.find(u=>String(u.base.id)==='10060' && u.sk.some(s=>s.name===NAME && skillState(u,s).ok));input=u?{k:'skill',i:v.A0.indexOf(u),s:NAME}:{k:holdForSkill?'end':'auto'};}
  x=st.next(input);
 }
 return x.value;
}
const deck=(offset=0)=>['10051','10060','10053','10054','10056'].map((id,i)=>({id,uid:'u'+(i+offset),level:5,skillLv:{2:1}}));
const cards=(d,mode)=>d.map(o=>snapCard(o,card,mode));let fixtures=0;
for(const mode of Object.keys(MODES))for(const seed of [1,13]) {
 const M=MODES[mode],s={mode,seed,control:'auto',me:Array.from({length:M.decks},(_,i)=>deck(i*5)),opp:Array.from({length:M.decks},(_,i)=>deck(100+i*5))};
 const auto=runSeries(mode,s.me.map(d=>cards(d)),s.opp.map(d=>cards(d)),seed),server=verifyPvp(s,null);
 assert.deepEqual({win:server.win,wins:server.wins,losses:server.losses,rounds:server.rounds},auto);
 const acts=[],rounds=[];let w=0,l=0;
 for(let i=0;i<M.decks && w<M.need && l<M.need;i++){const st=manualMatch(cards(s.me[i]),cards(s.opp[i]),roundSeed(seed,i),null,{manual:true,view:true,boss:!!M.boss});const r=play(st);acts.push(st.acts);rounds.push(r);r.win?w++:l++;}
 const replay=verifyPvp({...s,control:'actions'},acts);assert.deepEqual({win:replay.win,wins:replay.wins,losses:replay.losses,rounds:replay.rounds},{win:w>=M.need,wins:w,losses:l,rounds});
 assert(acts.some(a=>a.some(a=>a.k==='skill' && a.s===NAME)));fixtures++;
}
for(const seed of [1,13]) {
 const d=deck().map(o=>({...o,level:80})),r={kind:'raid',control:'auto',seed,stage:1,difficulty:'normal',deck:d};
 assert.deepEqual(verifyGuild(r,null),runRaid(cards(d,'raid'),1,'normal',seed,card));
 const raid=manualRaid(cards(d,'raid'),1,'normal',seed,card,null,{view:true}),rr=play(raid,true);
 assert(raid.acts.some(a=>a.k==='skill'&&a.s===NAME));assert.deepEqual(verifyGuild({...r,control:'actions'},raid.acts),rr);
 const w={kind:'war',control:'auto',seed,atk:d,def:deck(100),atk_buff:{},def_buff:{}};
 assert.deepEqual(verifyGuild(w,null),runWar(warDeck(w.atk,card,{}),warDeck(w.def,card,{}),seed));
 const war=warSession(warDeck(w.atk,card,{}),warDeck(w.def,card,{}),seed,null,{view:true}),wr=play(war);
 assert(war.acts.some(a=>a.k==='skill'&&a.s===NAME));assert.deepEqual(verifyGuild({...w,control:'actions'},war.acts),wr);fixtures+=2;
}
assert(casts>0);console.log(`Feedback16 PASS: both caster roles, opponent-next-turn lifetime, disruption preserved, existing seals intact; ${fixtures} explicit Sungjin PvP/raid/war AUTO + forced-skill manual browser/server replays (${casts} casts)`);
