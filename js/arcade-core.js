// Canonical arcade reducer. UI never owns randomness, legal actions or the verdict.
import {RULES,GRADES,allowedGrades,buildDeck,makeUnit,fieldCount,GUARD_GRADES,GUARD_SWAP_TURNS,guardOf,canSummon,canRecall,canSacrifice,sacrifice,canAction,doAction,canEquip,equip,canTarget,resolveAttack,refillMana,clearBuff,endTurnXp,judgeTimeout,aiShouldRecall,aiWantShuffle,aiWantAccel,aiPickSacrifice,aiSummonOrder,aiPickItem,aiWantFieldHeal,aiWantBuff,aiWantHeal,aiPickTarget,swapField} from './rules.js';
import {initPlayers,placeUnit,turnStart,turnEnd,useSkill,skillState,aiPickSkill,refreshAll,TURN,setSpare,setEmitter,getEmitter,setRng} from './skills.js';
import {rngOf} from './pvp-core.js';
const exact=(o,ks)=>o&&typeof o==='object'&&!Array.isArray(o)&&Object.keys(o).sort().join(',')===ks.sort().join(',');
export function arcadeOptions(o) {
 if(!exact(o,['grades','turns','clearFirst'])||![0,10,40].includes(o.turns)||typeof o.clearFirst!=='boolean'||o.grades!==null&&(!Array.isArray(o.grades)||!o.grades.length||o.grades.length>GRADES.length||new Set(o.grades).size!==o.grades.length||o.grades.some(g=>!GRADES.includes(g))))throw Error('invalid arcade options');
 return {grades:o.grades===null?null:GRADES.filter(g=>o.grades.includes(g)),turns:o.turns,clearFirst:o.clearFirst};
}
export function checkArcadeAction(a){
 const keys={summon:['k','id'],guard:['k','id'],merc:['k','id'],swap:['k','g','f'],move:['k','i','t'],atk:['k','i','t'],skill:['k','i','s'],action:['k','name'],equip:['k','i','item'],recall:['k','i'],sacrifice:['k','i'],undo:['k','i'],end:['k']};
 if(!exact(a,keys[a?.k]||[]))throw Error('invalid arcade action');
 for(const k of ['i','g','f','t'])if(k in a&&(!Number.isInteger(a[k])||a[k]<(k==='t'?-1:0)||a[k]>20))throw Error('invalid arcade index');
 for(const k of ['id','s','name','item'])if(k in a&&(typeof a[k]!=='string'||!a[k].length||a[k].length>100))throw Error('invalid arcade action');
 return a;
}
const PRICE={'HIGH RARE':1.2,'SUPER RARE':1.5,'ULTRA RARE':1.8};
export const mercPrice=c=>Math.ceil(c.cost*PRICE[c.grade]);
export const arcadePool = pool => pool.filter(c=>!/^(1|true|npc|y)$/i.test(String(c.npc||'').trim()));
export function createArcade(seed,opts,pool) {
 pool=arcadePool(pool);
 if(!Number.isInteger(seed)||seed<0||seed>4294967295)throw Error('invalid arcade seed');
 opts=arcadeOptions(opts);const r=rngOf(seed),choiceR=rngOf(seed^0xa5a5a5a5),actions=[],events=[];let s,result=null,nextWho;
 function scoped(fn){const rand=Math.random,em=getEmitter(),oldTurn=TURN.p;if(s)TURN.p=s[s.turn]||s[s.first];setSpare(null);Math.random=r;setRng(r);setEmitter(e=>{events.push(e);if(e.type==='dealt'&&e.src?.owner===s?.me){const k=String(e.src.card.id),v=s.log.dmg.get(k)||{card:e.src.card,dmg:0};v.dmg+=e.dmg;s.log.dmg.set(k,v);s.log.total+=e.dmg;}});try{return fn();}finally{Math.random=rand;setRng(rand);setEmitter(em);TURN.p=oldTurn;}}
 scoped(()=>{
  setSpare(null);const first=r()<.5?'me':'ai',grades=allowedGrades(opts),gp=grades?pool.filter(c=>grades.has(c.grade)):pool;
  const player=(name,second)=>{const deck=buildDeck(pool,r,grades),n=RULES.OPENING_HAND+(second?RULES.SECOND_PLAYER_BONUS_CARDS:0);return{name,hp:RULES.HERO_HP,maxHp:RULES.HERO_HP,deck,hand:deck.splice(0,n),field:[],mana:0,maxMana:0,second,pool:gp,clearFirst:opts.clearFirst,limitedAids:!!opts.grades||opts.turns!==40||opts.clearFirst};};
  s={me:player('나',first!=='me'),ai:player('적군',first!=='ai'),opts,first,turn:'wait',turnNo:0,totalTurns:0,myTurns:0,over:false,maxTurns:opts.turns||Infinity,guardMode:true,limitedAids:!!opts.grades||opts.turns!==40||opts.clearFirst,mercBought:0,mercHired:null,mercOffer:[],undo:null,log:{dmg:new Map(),total:0,skills:0,merc:null,played:new Set(),kills:{},blocks:{}}};
  if(!s.limitedAids){const owned=new Set([...s.me.deck,...s.me.hand].map(c=>String(c.id))),eligible=gp.filter(c=>!owned.has(String(c.id)));for(const g of Object.keys(PRICE)){const a=eligible.filter(c=>c.grade===g&&!s.mercOffer.includes(c));if(a.length)s.mercOffer.push(a[Math.floor(r()*a.length)]);}const rest=eligible.filter(c=>c.grade in PRICE&&!s.mercOffer.includes(c));while(s.mercOffer.length<3&&rest.length)s.mercOffer.push(rest.splice(Math.floor(r()*rest.length),1)[0]);}
  initPlayers(s.me,s.ai,s[first]);nextWho=first;
 });
 const other=who=>who==='me'?'ai':'me';
 function finish(win,reason){if(result)return;const rank=Object.fromEntries(GRADES.map((g,i)=>[g,i]));const best=[...s.log.dmg.values()].sort((a,b)=>b.dmg-a.dmg)[0]?.card||[...s.me.field.map(u=>u.card),...s.me.hand].sort((a,b)=>(rank[b.grade]||0)-(rank[a.grade]||0)||b.cost-a.cost)[0];result={result:win===null?'draw':win?'win':'lose',reason,turns:s.turnNo,totalTurns:s.totalTurns,damage:Math.floor(s.log.total),skills:s.log.skills,mvp_id:best?String(best.id):null,mvp_name:best?.name||null,merc_id:s.log.merc?String(s.log.merc.id):null};s.over=true;}
 function check(timeout=false){if(s.ai.hp<=0||s.me.hp<=0)finish(s.ai.hp<=0,'ko');else if(timeout&&s.totalTurns>=Math.min(s.maxTurns,400)){const j=judgeTimeout(s.me,s.ai);finish(j.winner===null?null:j.winner===s.me,j.reason);}}
 function begin(who){if(result||who!==nextWho)throw Error('illegal arcade turn');return scoped(()=>{nextWho=null;s.turn=who;if(who===s.first)s.turnNo++;s.totalTurns++;if(who==='me')s.myTurns++;const p=s[who];p.ownTurns=(p.ownTurns||0)+1;clearBuff(s[other(who)]);refillMana(p);if(p.deck.length)p.hand.push(p.deck.shift());p.field.forEach(u=>u.canAttack=true);turnStart(p);check();return drain();});}
 function guardCheck(c,p){return c&&GUARD_GRADES.has(c.grade)&&!guardOf(p)&&p.mana>=c.cost;}
 function swapCheck(p,g,f){return g?.guard&&f&&f!==g&&!f.guard&&p.field.includes(f)&&f.hp>0&&GUARD_GRADES.has(f.base.grade)&&!f.st.para&&(p.ownTurns||0)-(g.guardAt||0)>=GUARD_SWAP_TURNS;}
 function setGuard(u,p){u.guard=u.boss=u.undying=true;u.guardAt=p.ownTurns||0;u.hp=Math.max(1,u.hp);}
 function signature(){const f=p=>p.field.map(x=>`${x.uid}:${x.hp}:${x.maxHp}:${JSON.stringify(x.st,(k,v)=>k&&v&&typeof v==='object'&&v.uid!=null?'u'+v.uid:v)}`).join('|');return[s.me.mana,s.me.hp,s.ai.hp,s.me.hand.length,f(s.me),f(s.ai),s.turnNo].join('#');}
 function canUndo(u){return !!s.undo&&s.undo.u===u&&!u.boss&&s.turn==='me'&&!result&&s.me.field.includes(u)&&s.undo.sig===signature();}
 function act(a,who='me'){
  checkArcadeAction(a);if(result||s.turn!==who)throw Error('illegal arcade turn');
  return scoped(()=>{const p=s[who],f=s[other(who)],u=p.field[a.i],c=p.hand.find(c=>String(c.id)===a.id);let out={ok:true},undo=s.undo;
   const need=b=>{if(!b)throw Error('illegal arcade action');};
   switch(a.k){
    case 'summon':case 'guard':{need(c&&p.hand.includes(c)&&(a.k==='guard'?guardCheck(c,p):canSummon(c,p,f).ok));p.mana-=c.cost;p.hand.splice(p.hand.indexOf(c),1);const v=placeUnit(p,c,makeUnit,a.k==='summon');if(a.k==='guard'){setGuard(v,p);refreshAll(p);s.undo=null;}else if(who==='me')s.undo={u:v,card:c,cost:c.cost,sig:signature()};out.u=v;break;}
    case 'swap':{const g=p.field[a.g],v=p.field[a.f];need(swapCheck(p,g,v));[p.field[a.g],p.field[a.f]]=[v,g];g.guard=g.boss=g.undying=false;delete g.guardAt;setGuard(v,p);refreshAll(p);s.undo=null;out.end=true;break;}
    case 'move':need(u&&p.field[a.t]&&swapField(p,u,p.field[a.t]));break;
    case 'atk':{const t=a.t===-1?null:f.field[a.t];need(u&&u.canAttack&&(a.t===-1||t)&&canTarget(p,f,t,u));s.undo=null;out.hits=resolveAttack(p,f,u,t);u.canAttack=false;break;}
    case 'skill':{const sk=u?.sk.find(sk=>sk.name===a.s);need(u&&sk&&skillState(u,sk).ok);s.undo=null;need(useSkill(u,sk).ok);if(who==='me')s.log.skills++;break;}
    case 'action':{need(canAction(a.name,p).ok);s.undo=null;out=doAction(a.name,p);break;}
    case 'equip':{need(u&&canEquip(a.item,u,p).ok);s.undo=null;out=equip(a.item,u,p);break;}
    case 'recall':{const v=u&&canRecall(u,p);need(v?.ok);p.mana-=v.cost;p.field.splice(a.i,1);p.hand.push(u.base);s.undo=null;refreshAll(p);break;}
    case 'sacrifice':need(u&&canSacrifice(u,p).ok);s.undo=null;out=sacrifice(u,p);break;
    case 'undo':need(who==='me'&&canUndo(u));p.field.splice(a.i,1);p.hand.push(undo.card);p.mana+=undo.cost;s.undo=null;refreshAll(p);break;
    case 'merc':{const v=s.mercOffer.find(c=>String(c.id)===a.id);need(who==='me'&&!s.limitedAids&&v&&s.mercBought<1&&![...p.deck,...p.hand,...p.field.map(u=>u.base),...p.grave].some(c=>String(c.id)===a.id)&&p.mana>=mercPrice(v));p.mana-=mercPrice(v);p.hand.push(v);s.mercBought++;s.mercHired=a.id;s.log.merc=v;s.undo=null;break;}
    case 'end':out.end=true;break;
   }
   check();if(out.end&&!result){s.undo=null;endTurnXp(p);turnEnd(p);check(true);if(!result){s.turn='wait';nextWho=other(who);}}
   if(who==='me')actions.push(structuredClone(a));return {...out,events:drain(),result};
  });
 }
 function* plan(who='ai'){
  const p=s[who],f=s[other(who)],idx=u=>p.field.indexOf(u),decide=fn=>{if(who==='ai')return scoped(fn);const old=Math.random;Math.random=choiceR;setRng(choiceR);try{return fn();}finally{Math.random=old;setRng(old);}};
  for(const u of [...p.field])if(aiShouldRecall(u,p,f))yield{k:'recall',i:idx(u)};
  if(aiWantShuffle(p,f))yield{k:'action',name:'shuffle'};
  if(aiWantAccel(p,true))yield{k:'action',name:'accel'};
  {const u=aiPickSacrifice(p,f);if(u)yield{k:'sacrifice',i:idx(u)};}
  for(const c of aiSummonOrder(p.hand))if(canSummon(c,p,f).ok)yield{k:'summon',id:String(c.id)};
  {const c=p.hand.filter(c=>guardCheck(c,p)).sort((a,b)=>b.power-a.power)[0];if(c)yield{k:'guard',id:String(c.id)};}
  {const g=guardOf(p),u=g&&g.hp<g.maxHp*.3&&p.field.filter(u=>swapCheck(p,g,u)&&u.hp>g.hp*2).sort((a,b)=>b.hp-a.hp)[0];if(u){yield{k:'swap',g:idx(g),f:idx(u)};return;}}
  for(let n=0;n<12;n++){const it=decide(()=>aiPickItem(p,f));if(!it)break;yield{k:'equip',i:idx(it[1]),item:it[0]};}
  for(const [name,want] of [['accel',()=>aiWantAccel(p)],['fieldheal',()=>aiWantFieldHeal(p)],['buff',()=>aiWantBuff(p)]])if(want())yield{k:'action',name};
  for(const u of [...p.field]){if(result)return;if(!p.field.includes(u)||!u.canAttack)continue;const sk=decide(()=>aiPickSkill(u));if(sk){yield{k:'skill',i:idx(u),s:sk.name};continue;}const t=decide(()=>aiPickTarget(u,p,f));if(t!==undefined)yield{k:'atk',i:idx(u),t:t?f.field.indexOf(t):-1};}
  if(!result&&aiWantHeal(p))yield{k:'action',name:'heal'};
  if(!result)yield{k:'end'};
 }
 function drain(){return events.splice(0);}
 return{state:s,actions,begin,act,plan,canUndo,get result(){return result;},get nextWho(){return nextWho;},drain};
}
export function replayArcade(seed,options,actions,pool){
 if(!Array.isArray(actions)||actions.length>20000)throw Error('invalid arcade transcript');
 const c=createArcade(seed,options,pool);let i=0,n=0;
 while(!c.result){if(++n>100000)throw Error('arcade replay limit');if(c.nextWho)c.begin(c.nextWho);if(c.result)break;
  if(c.state.turn==='ai'){for(const a of c.plan()){if(c.result)break;c.act(a,'ai');}}
  else{if(i>=actions.length)throw Error('incomplete arcade transcript');c.act(actions[i++]);}
 }
 if(i!==actions.length)throw Error('extra arcade actions');return c.result;
}
