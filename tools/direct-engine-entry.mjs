// Direct story / tower authority. Tower non-boss calls the bundled verifySweep.
// Story fixed-enemy fights use the same runSweep the sweep bundle was built from.
// This file does not modify js/rules.js or the hash-pinned engine bundles.
import { ENGINE_VERSION, verifySweep } from '../supabase/functions/_shared/sweep-engine-v6.mjs';
import cardsCsv from '../data/cards.csv';
import npcCsv from '../data/npc_cards.csv';
import skillsJson from '../data/skills.json';
import combosJson from '../data/combos.json';
import { parseCSV, calcPower, setCardPool, skillCountMult } from '../js/rules.js';
import { setSkillData, skillsOf, initPlayers, placeUnit, turnStart, turnEnd, useSkill, aiPickSkill, refreshAll, setRng, setEmitter, getEmitter } from '../js/skills.js';
import { clearBuff, refillMana, endTurnXp, makeUnit, resolveAttack, aiPickTarget } from '../js/rules.js';
import { snapCard } from '../js/pvp-core.js';
import { runSweep, leaderSkill } from '../js/sweep-core.js';

const LV_RATE = { NORMAL: 0.01, RARE: 0.02, 'HIGH RARE': 0.03, 'SUPER RARE': 0.04, 'ULTRA RARE': 0.05, 'MYTHIC RARE': 0.06, 'LEGENDARY RARE': 0.05 };
const cards = parseCSV(cardsCsv);
const npc = parseCSV(npcCsv);
const byId = new Map([...cards, ...npc].map(c => [String(c.id), c]));
const SK = { initPlayers, placeUnit, turnStart, turnEnd, useSkill, aiPickSkill, refreshAll, setRng, setEmitter, getEmitter };
const R = { clearBuff, refillMana, endTurnXp, makeUnit, resolveAttack, aiPickTarget };
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

function list(value) {
  return Array.isArray(value) ? value : [];
}

export function storyUnsupported(stage) {
  if (!stage || typeof stage !== 'object') return 'unsupported battle';
  if (stage.tutorial) return 'unsupported battle';
  if (stage.type === 'boss' || stage.baseHp != null) return 'unsupported battle';
  if (stage.mustSummon || stage.awaken || stage.joinAlly || list(stage.reserve).length) return 'unsupported battle';
  const rules = stage.rules || {};
  if (rules.mustSummon || rules.revive || rules.undying || rules.invuln != null || rules.expire != null) return 'unsupported battle';
  if (!list(stage.enemies?.ids).length) return 'unsupported battle';
  return '';
}

function enemyFrom(id, stage) {
  const base = byId.get(String(id));
  if (!base) return null;
  let c = { ...base };
  const storyLv = stage.enemies?.storyLevels?.[String(base.id)];
  if (storyLv) {
    const m = 1 + (LV_RATE[c.grade] || 0.01) * (Math.max(1, Number(storyLv) || 1) - 1);
    c = { ...c, HP: Math.round(base.HP * m), ATK: Math.round(base.ATK * m), DEF: Math.round(base.DEF * m), slv: storyLv };
  }
  const lv = stage.enemies?.levels?.[String(base.id)];
  if (lv) c = { ...c, slv: lv };
  const boost = stage.enemies?.boost?.[String(base.id)];
  if (boost && typeof boost === 'object') {
    c = { ...c, ...boost, storyBoost: true };
    if (boost.power == null) c.power = calcPower(c, skillsOf(c.id));
  }
  return c;
}

function replayStory(session, stage) {
  const me = (session.snapshot?.cards || []).map(combatCard).filter(Boolean);
  if (!me.length || me.length > 5) throw new Error('unsupported battle');
  const ai = list(stage.enemies.ids).map(id => enemyFrom(id, stage));
  if (ai.some(c => !c)) throw new Error('unsupported battle');
  const leaderCard = me.find(c => c.uid && c.uid === session.snapshot?.leader);
  const leader = leaderCard ? { ...leaderSkill(leaderCard), uid: leaderCard.uid } : null;
  const survive = Number(stage.rules?.survive);
  const maxTurns = Number.isFinite(survive) && survive > 0
    ? Math.min(40, Math.max(2, survive * 2))
    : Math.min(40, Math.max(1, Number(stage.rules?.maxTurns) || 40));
  return runSweep(SK, R, { me, ai: ai.map(c => ({ ...c })), seed: Number(session.seed), maxTurns, leader });
}

function packed(fought, reason) {
  const turns = Math.max(1, Math.min(40, fought.turns | 0 || 1));
  return { win: !!fought.win, reason, turns, my_turns: Math.ceil(turns / 2) };
}

export function verifyDirect(session, outcome) {
  if (!session || (session.mode !== 'story' && session.mode !== 'tower')) throw new Error('not a direct battle');
  if (outcome !== 'claim' && outcome !== 'loss' && outcome !== 'giveup') throw new Error('invalid outcome');
  if (outcome === 'giveup') return { win: false, reason: 'giveup', turns: 2, my_turns: 1 };
  if (session.mode === 'tower') {
    const floor = Number(String(session.target || '').split(':')[1]);
    if (!Number.isInteger(floor) || floor < 1 || floor % 10 === 0) throw new Error('boss floor');
    if (outcome === 'loss') return { win: false, reason: 'wipe', turns: 2, my_turns: 1 };
    return verifySweep({ ...session, mode: 'tower_sweep' });
  }
  const stage = session.snapshot?.stage || {};
  if (stage.loseClears) return { win: false, reason: 'wipe', turns: 2, my_turns: 1, scripted: 'loseClears' };
  const why = storyUnsupported(stage);
  if (why) throw new Error(why);
  if (outcome === 'loss' && !(Number(stage.rules?.survive) > 0)) return { win: false, reason: 'wipe', turns: 2, my_turns: 1 };
  const fought = replayStory(session, stage);
  if (Number(stage.rules?.survive) > 0) {
    if (fought.win || fought.timeout) return packed({ ...fought, win: true }, fought.timeout ? 'survive' : 'wipe');
    return packed(fought, 'wipe');
  }
  return packed(fought, fought.timeout ? 'timeout' : 'wipe');
}

export { ENGINE_VERSION };
