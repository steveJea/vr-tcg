import csv from '../data/cards.csv';
import npcCsv from '../data/npc_cards.csv';
import skills from '../data/skills.json';
import combos from '../data/combos.json';
import { parseCSV, setCardPool } from '../js/rules.js';
import { setSkillData } from '../js/skills.js';
import { snapCard, rngOf, stepper, matchGen } from '../js/pvp-core.js';
import { raidGen } from '../js/raid-core.js';
import { warDeck, warOpt } from '../js/war-core.js';
const pool = parseCSV(csv), by = new Map([...pool,...parseCSV(npcCsv)].map(c=>[String(c.id),c]));
setCardPool(pool); setSkillData(skills,combos);
export function checkActions(actions) {
 if (!Array.isArray(actions)||actions.length>1600) throw Error('invalid actions');
 for(const a of actions) {
  if(!a||typeof a!=='object'||Array.isArray(a)) throw Error('invalid action');
  const k=Object.keys(a).sort().join(','), ix=n=>Number.isInteger(n)&&n>=0&&n<5;
  if(a.k==='end'&&k==='k') continue;
  if(a.k==='atk'&&k==='i,k,t'&&ix(a.i)&&(ix(a.t)||a.t===-1)) continue;
  if(a.k==='skill'&&k==='i,k,s'&&ix(a.i)&&typeof a.s==='string'&&a.s.length>0&&a.s.length<=160) continue;
  throw Error('invalid action');
 }
}
export function verifyBattle(s,actions) {
 if(s.control==='actions') checkActions(actions);
 else if(s.control!=='auto'||actions!==null) throw Error('invalid control');
 const manual=s.control==='actions', log=[], r=rngOf(s.seed), card=id=>by.get(String(id));
 const valid=d=>{if(!Array.isArray(d)||d.length<1||d.length>5||d.some(o=>!card(o.id)))throw Error('invalid deck');return d;};
 let gen;
 if(s.kind==='raid') {
  if(!Number.isInteger(s.stage)||s.stage<1||!['normal','hard','abyss'].includes(s.difficulty))throw Error('invalid raid');
  gen=raidGen(valid(s.deck).map(o=>snapCard(o,card,'raid')),s.stage,s.difficulty,r,card,log,manual,null,{strict:true});
 } else if(s.kind==='war') gen=matchGen(warDeck(valid(s.atk),card,s.atk_buff),warDeck(valid(s.def),card,s.def_buff),r,log,manual,null,warOpt({strict:true}));
 else throw Error('invalid kind');
 const st=stepper(gen,r); let x=st.next(),at=0,steps=0;
 while(!x.done){if(++steps>20000||!x.value?.ask||!manual||at>=actions.length)throw Error('missing action');x=st.next(actions[at++]);}
 if(manual&&at!==actions.length)throw Error('extra actions');
 if(!x.value||!Number.isInteger(x.value.turns))throw Error('incomplete engine');
 return x.value;
}
