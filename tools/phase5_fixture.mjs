import {readFile} from 'node:fs/promises';
import {parseCSV,setCardPool,GRADES} from '../js/rules.js';
import {setSkillData,TURN} from '../js/skills.js';
import {createArcade,replayArcade,arcadeOptions,checkArcadeAction} from '../js/arcade-core.js';
const rd=p=>readFile(new URL('../'+p,import.meta.url),'utf8'),pool=parseCSV(await rd('data/cards.csv'));
setCardPool(pool);setSkillData(JSON.parse(await rd('data/skills.json')),JSON.parse(await rd('data/combos.json')));
export function fixture(seed,options={grades:null,turns:10,clearFirst:false},fx=false){const c=createArcade(seed,options,pool);let n=0;const kinds=new Set();while(!c.result){if(++n>5000)throw Error('loop');if(c.nextWho)c.begin(c.nextWho);if(c.result)break;const who=c.state.turn;for(const a of c.plan(who)){if(c.result)break;c.act(a,who);kinds.add(a.k);if(fx){TURN.p={name:'unrelated battle'};for(let i=0;i<37;i++)Math.random();}}}return{seed,options,actions:c.actions,result:c.result,kinds};}
