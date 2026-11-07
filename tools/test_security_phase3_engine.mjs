import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { parseCSV, setCardPool } from '../js/rules.js';
import { setSkillData } from '../js/skills.js';
import { snapCard, runSeries, manualMatch, MODES, roundSeed } from '../js/pvp-core.js';
import { ENGINE_VERSION, verifyBattle, checkActions } from '../supabase/functions/_shared/pvp-engine-v3.mjs';
const rd = p => readFile(new URL('../'+p,import.meta.url),'utf8');
const pool = parseCSV(await rd('data/cards.csv')); setCardPool(pool);
setSkillData(JSON.parse(await rd('data/skills.json')),JSON.parse(await rd('data/combos.json')));
const byId = id => pool.find(c=>String(c.id)===String(id));
const hr = pool.filter(c=>['NORMAL','RARE','HIGH RARE'].includes(c.grade));
const one = (c,i) => ({ id:String(c.id),level:1+(i*17)%70,ex:i%3,exb:i%3*10,boost:{ ATK:i%7,HP:i%9,DEF:i%4 } });
const decks = (mode,offset) => Array.from({length:MODES[mode].decks},(_,i)=>Array.from({length:mode==='boss'?6:5},(_,j)=>one(j===0&&mode==='boss'?hr[(offset+i)%hr.length]:pool[(offset+i*11+j)%pool.length],offset+i+j)));
const toCards = d=>d.map(o=>snapCard(o,byId));
export function recordActions(session) {
 const M=MODES[session.mode], acts=[]; let w=0,l=0;
 for(let i=0;i<M.decks && w<M.need && l<M.need;i++) {
  const st=manualMatch(session.me[i].map(o=>snapCard(o,byId)),session.opp[i].map(o=>snapCard(o,byId)),roundSeed(session.seed,i),null,{view:true,manual:true,boss:!!M.boss});
  let x=st.next(), guard=0;
  while(!x.done) { assert(++guard<20000); x=st.next(x.value?.ask?{k:'auto'}:undefined); }
  acts.push(st.acts); x.value.win?w++:l++;
 }
 return acts;
}
let cases=0, sample;
for(const mode of Object.keys(MODES)) for(let seed=1;seed<=40;seed++) {
 const s={mode,seed,me:decks(mode,seed*3),opp:decks(mode,seed*5+33),control:'auto'};
 const oldRandom=Math.random;
 const client=runSeries(mode,s.me.map(toCards),s.opp.map(toCards),seed);
 const server=verifyBattle(s,null);
 assert.deepEqual({win:server.win,wins:server.wins,losses:server.losses,rounds:server.rounds},client);
 const acts=recordActions(s), manual=verifyBattle({...s,control:'actions'},acts);
 assert.deepEqual(manual,server,'AUTO→canonical manual replay must consume exactly the same RNG/results');
 assert.equal(Math.random,oldRandom,'scoped RNG restored');
 assert.deepEqual(verifyBattle(s,null),server,'repeat requests cannot carry skill/RNG state');
 if(mode==='3v3' && acts.some(a=>a.length)) sample={s:{...s,control:'actions'},acts};
 cases++;
}
assert(sample); const {s,acts}=sample;
assert.throws(()=>verifyBattle(s,acts.slice(0,-1)),/missing|round/);
const extra=structuredClone(acts); extra.at(-1).push({k:'end'}); assert.throws(()=>verifyBattle(s,extra),/extra/);
const missing=structuredClone(acts); missing.find(a=>a.length).pop(); assert.throws(()=>verifyBattle(s,missing),/missing|illegal/);
const bad=structuredClone(acts); bad.find(a=>a.length)[0]={k:'skill',i:0,s:'forged skill'}; assert.throws(()=>verifyBattle(s,bad),/illegal/);
for(const action of [{k:'auto'},{k:'atk',i:'0',t:0},{k:'atk',i:0,t:99},{k:'end',win:true},{k:'swap',g:-1,f:2},null]) assert.throws(()=>checkActions([[action]]));
assert.throws(()=>verifyBattle({...s,control:'auto'},acts),/control/);
assert.throws(()=>verifyBattle({...s,me:[[{id:'forged'}]]},acts),/snapshot|card/);
console.log(`Phase3 engine: ${cases} canonical browser/server AUTO + live manual/SKIP fixtures; strict missing/extra/illegal inputs and RNG isolation OK (${ENGINE_VERSION.slice(0,12)})`);
