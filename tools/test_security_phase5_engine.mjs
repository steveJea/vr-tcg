import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {parseCSV,setCardPool,GRADES} from '../js/rules.js';
import {setSkillData,TURN} from '../js/skills.js';
import {createArcade,replayArcade,arcadeOptions,checkArcadeAction} from '../js/arcade-core.js';
import {verifyBattle} from '../supabase/functions/_shared/arcade-engine-v5.mjs';
const rd=p=>readFile(new URL('../'+p,import.meta.url),'utf8'),pool=parseCSV(await rd('data/cards.csv'));
setCardPool(pool);setSkillData(JSON.parse(await rd('data/skills.json')),JSON.parse(await rd('data/combos.json')));
import {fixture} from './phase5_fixture.mjs';
const kinds=new Set();let n=0;
for(const grades of [null,...GRADES.map(g=>[g]),GRADES.slice(0,3),GRADES.slice(3),GRADES.filter(g=>g!=='MYTHIC RARE')])for(const turns of [10,40,0])for(const clearFirst of [false,true]){
 const f=fixture(++n,{grades,turns,clearFirst});for(const k of f.kinds)kinds.add(k);
 assert.deepEqual(replayArcade(f.seed,f.options,f.actions,pool),f.result);
 assert.deepEqual(verifyBattle(f,f.actions),f.result,'browser/server replay parity');
 assert.deepEqual(fixture(f.seed,f.options,true).result,f.result,'UI random effects must not change combat');
 assert.throws(()=>replayArcade(f.seed,f.options,f.actions.slice(0,-1),pool));
 assert.throws(()=>replayArcade(f.seed,f.options,[...f.actions,{k:'end'}],pool));
}
for(const a of [{k:'heal'},{k:'atk',i:-1,t:0},{k:'skill',i:0,s:'x',damage:1},{k:'end',result:'win'},null])assert.throws(()=>checkArcadeAction(a));
for(const o of [{grades:[],turns:10,clearFirst:false},{grades:null,turns:100,clearFirst:false},{grades:['RARE','RARE'],turns:10,clearFirst:false},{grades:null,turns:10,clearFirst:false,seed:1}])assert.throws(()=>arcadeOptions(o));
console.log('phase5 engine: '+n+' mode combinations x browser/server/FX parity, strict transcript; covered '+[...kinds].join(','));
for(let seed=1;seed<=40;seed++){
 const options={grades:null,turns:40,clearFirst:false},c=createArcade(seed,options,pool);
 while(c.nextWho&&c.nextWho!=='me'){c.begin(c.nextWho);for(const a of c.plan())if(!c.result)c.act(a,'ai');}
 if(c.result)continue;c.begin('me');
 const card=c.state.me.hand.find(x=>x.cost<=c.state.me.mana);if(!card)continue;
 assert.throws(()=>c.act({k:'summon',id:'not-in-hand'}));
 const before=c.state.me.mana,r=c.act({k:'summon',id:String(card.id)}),u=r.u;
 assert(c.canUndo(u));c.act({k:'undo',i:c.state.me.field.indexOf(u)});assert.equal(c.state.me.mana,before);assert(c.state.me.hand.includes(card));
 assert.throws(()=>c.act({k:'undo',i:0}));
 c.act({k:'summon',id:String(card.id)});
 for(let j=0;j<20&&!c.result;j++){
  if(c.state.turn==='me'){
   const offer=c.state.mercOffer.find(x=>Math.ceil(x.cost*({'HIGH RARE':1.2,'SUPER RARE':1.5,'ULTRA RARE':1.8}[x.grade]))<=c.state.me.mana);
   if(offer&&!c.state.mercBought){c.act({k:'merc',id:String(offer.id)});assert.throws(()=>c.act({k:'merc',id:String(offer.id)}));}
   if(c.state.me.field.filter(u=>!u.undying).length>1){const ix=c.state.me.field.map((u,i)=>u.undying?-1:i).filter(i=>i>=0);c.act({k:'move',i:ix[0],t:ix[1]});}
  }
  for(const a of c.plan(c.state.turn))if(!c.result)c.act(a,c.state.turn);
  if(c.nextWho)c.begin(c.nextWho);
 }
 while(!c.result){if(c.nextWho)c.begin(c.nextWho);if(c.result)break;const who=c.state.turn;for(const a of c.plan(who))if(!c.result)c.act(a,who);}
 assert.deepEqual(verifyBattle({seed,options},c.actions),c.result,'undo/merc/reorder actions replay identically');
}
console.log('phase5 extended manual: 40 seeded undo/refund, mercenary purchase limits, field reorder, illegal membership and complete Edge replay OK');
