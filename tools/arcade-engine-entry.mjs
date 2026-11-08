import csv from '../data/cards.csv';
import skills from '../data/skills.json';
import combos from '../data/combos.json';
import {parseCSV,setCardPool} from '../js/rules.js';
import {setSkillData} from '../js/skills.js';
import {replayArcade,arcadeOptions,checkArcadeAction,arcadePool} from '../js/arcade-core.js';
const pool=arcadePool(parseCSV(csv));setCardPool(pool);setSkillData(skills,combos);
export {arcadeOptions};
export function checkActions(actions){if(!Array.isArray(actions)||actions.length>20000)throw Error('invalid actions');for(const a of actions)checkArcadeAction(a);}
export function verifyBattle(s,actions){checkActions(actions);return replayArcade(s.seed,s.options,actions,pool);}
