import assert from 'node:assert/strict';
import fs from 'node:fs';
import {parseCSV,setCardPool} from '../js/rules.js';
import {setSkillData} from '../js/skills.js';
import {snapCard} from '../js/pvp-core.js';
import {manualRaid,runRaid} from '../js/raid-core.js';
import {warDeck,warSession,runWar} from '../js/war-core.js';
import {verifyBattle,checkActions} from '../supabase/functions/_shared/guildbattle-engine-v4.mjs';
const pool=parseCSV(fs.readFileSync('data/cards.csv','utf8')),npc=parseCSV(fs.readFileSync('data/npc_cards.csv','utf8')),by=new Map([...pool,...npc].map(c=>[String(c.id),c]));
setCardPool(pool);setSkillData(JSON.parse(fs.readFileSync('data/skills.json')),JSON.parse(fs.readFileSync('data/combos.json')));
const card=id=>by.get(String(id));
const ids=['10060','10062','10311','10326','10118'];
const deck=(level=40)=>ids.map((id,i)=>({uid:'u'+i,id,level,ex:2,exb:15,boost:{ATK:9,HP:8,DEF:7},skillLv:{1:4,2:3},gear:[{stat:'atk',pct:10,plus:2,opts:[]}],sigil:5}));
function play(s){let x=s.next(),n=0;while(!x.done){assert(++n<20000);x=s.next(x.value?.ask?{k:'auto'}:undefined);}return x.value;}
let n=0;
for(const seed of [1,13,252,91082])for(const stage of [1,2,5,9])for(const difficulty of ['normal','hard','abyss']){
 const s={kind:'raid',control:'auto',seed,stage,difficulty,deck:deck(stage%2?1:40)},log=[],browser=runRaid(s.deck.map(o=>snapCard(o,card,'raid')),stage,difficulty,seed,card,log);
 assert.deepEqual(verifyBattle(s,null),browser);
 const ses=manualRaid(s.deck.map(o=>snapCard(o,card,'raid')),stage,difficulty,seed,card,[],{view:true}),manual=play(ses);
 assert.deepEqual(verifyBattle({...s,control:'actions'},ses.acts),manual);assert.deepEqual(manual,browser);
 assert.throws(()=>verifyBattle({...s,control:'actions'},[...ses.acts,{k:'end'}]),/extra/);
 assert.throws(()=>verifyBattle({...s,control:'actions'},[{k:'atk',i:99,t:0}]),/invalid/);
 if(ses.acts.length)assert.throws(()=>verifyBattle({...s,control:'actions'},ses.acts.slice(0,-1)),/missing/);
 n++;
}
for(const seed of [1,2,8192,9001])for(const npcDef of [false,true])for(const low of [false,true]){
 const atk=deck(low?1:80),def=npcDef?npc.slice(0,5).map((c,i)=>({id:String(c.id),uid:'n'+i,level:10,scale:1})):deck(low?80:1).map(o=>({...o,uid:'b'+o.uid}));
 const s={kind:'war',control:'auto',seed,atk,def,atk_buff:{atk:1.25,def:1.25},def_buff:{atk:1.15,def:1.15}};
 const A=()=>warDeck(atk,card,s.atk_buff),B=()=>warDeck(def,card,s.def_buff),r=runWar(A(),B(),seed);
 assert.deepEqual(verifyBattle(s,null),r);
 const ses=warSession(A(),B(),seed,[],{view:true}),manual=play(ses);assert.deepEqual(manual,r);assert.deepEqual(verifyBattle({...s,control:'actions'},ses.acts),manual);
 assert.throws(()=>verifyBattle({...s,control:'actions'},[{k:'atk',i:0,t:4},...ses.acts]),/illegal|missing|extra/);
 // Carry HP can never be healed above its start; replay the injured snapshots too.
 const injured={...s,atk:atk.map(o=>({...o,hp:100})),def:def.map(o=>({...o,hp:200}))};const ri=verifyBattle(injured,null);assert(Object.values(ri.aHp).every(h=>h<=100));assert(Object.values(ri.bHp).every(h=>h<=200));
 n++;
}
for(const a of [[{k:'auto'}],[{k:'end',win:true}],[{k:'skill',i:0,s:'fake',damage:99999}],null,{}])assert.throws(()=>checkActions(a));
assert.throws(()=>verifyBattle({kind:'raid',control:'auto'},[]));
console.log(`Phase4 engine PASS: ${n} raid/war fixtures × AUTO/actions/view/browser/server; NPC, MR, levels/EX/boost/gear/skills, injured HP, strict missing/extra/illegal intentions`);
