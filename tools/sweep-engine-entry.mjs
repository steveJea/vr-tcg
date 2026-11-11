// Tower sweep authority. Enemies, stats, gear and the seed come from server data.
// The browser's win/turn report is not an input.
import cardsCsv from '../data/cards.csv';
import npcCsv from '../data/npc_cards.csv';
import skillsJson from '../data/skills.json';
import combosJson from '../data/combos.json';
import questJson from '../data/quest.json';
import { parseCSV, setCardPool, skillCountMult } from '../js/rules.js';
import { setSkillData, skillsOf, initPlayers, placeUnit, turnStart, turnEnd, useSkill, aiPickSkill, refreshAll, setRng, setEmitter, getEmitter } from '../js/skills.js';
import { clearBuff, refillMana, endTurnXp, makeUnit, resolveAttack, aiPickTarget } from '../js/rules.js';
import { snapCard } from '../js/pvp-core.js';
import { runSweep, leaderSkill } from '../js/sweep-core.js';
import '../js/enemy-mr.js';
import '../js/quest-gen.js';

const cards = parseCSV(cardsCsv);
const npc = parseCSV(npcCsv);
const byId = new Map(cards.map(c => [String(c.id), c]));
const SK = { initPlayers, placeUnit, turnStart, turnEnd, useSkill, aiPickSkill, refreshAll, setRng, setEmitter, getEmitter };
const R = { clearBuff, refillMana, endTurnXp, makeUnit, resolveAttack, aiPickTarget };
const CLS = { wind: 'WIND', ice: 'ICE', fire: 'FIRE', light: 'LIGHT', dark: 'DARK' };
setCardPool([...cards, ...npc]);
setSkillData(skillsJson, combosJson);
globalThis.VRQuestSkillMult = c => skillCountMult(skillsOf(c?.id));

function combatCard(raw) {
  const src = raw?.loan && typeof raw.loan === 'object'
    ? { ...raw.loan, id: raw.id, uid: raw.uid, gear: raw.gear || raw.loan.gear || [], sigil: raw.sigil ?? raw.loan.sigil ?? null }
    : raw;
  const card = snapCard(src, id => byId.get(String(id)), 'tower');
  if (!card) return null;
  card.uid = raw.uid;
  return card;
}

export function verifySweep(session) {
  if (!session || session.mode !== 'tower_sweep') throw new Error('not a sweep');
  const target = String(session.target || '');
  const parts = target.split(':');
  if (parts.length !== 2) throw new Error('invalid tower target');
  const [tower, floorText] = parts;
  if (!/^(normal|wind|ice|fire|light|dark)$/.test(tower) || !/^[1-9][0-9]{0,2}$/.test(floorText)) throw new Error('invalid tower target');
  const floor = Number(floorText);
  const spec = questJson.floors?.[floor - 1];
  if (!spec || spec.floor !== floor || floor % 10 === 0) throw new Error('boss floor or invalid floor');
  const seed = Number(session.seed);
  const G = globalThis.VRQuestGen;
  const enemies = CLS[tower]
    ? G.generateAttr(questJson, spec, cards, { tower, cls: CLS[tower], npc, levelOffset: 10 }).enemies
    : G.generate(questJson, spec, cards, combosJson).enemies;
  if (!enemies?.length) throw new Error('no enemies');
  const me = (session.snapshot?.cards || []).map(combatCard).filter(Boolean);
  if (!me.length || me.length > 5) throw new Error('invalid sweep party');
  const leaderCard = me.find(c => c.uid && c.uid === session.snapshot?.leader);
  const leader = leaderCard ? { ...leaderSkill(leaderCard), uid: leaderCard.uid } : null;
  const fought = runSweep(SK, R, { me, ai: enemies.map(c => ({ ...c })), seed, maxTurns: questJson.maxTurns || 40, leader });
  return {
    win: fought.win,
    reason: fought.timeout ? 'timeout' : 'wipe',
    turns: fought.turns,
    my_turns: Math.ceil(fought.turns / 2),
  };
}
