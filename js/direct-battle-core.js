// Headless story/tower battle. Same rules.js and skills.js calls as js/game.js.
// Player actions are the only choices; every roll uses the session seed.
import cardsCsv from '../data/cards.csv';
import npcCsv from '../data/npc_cards.csv';
import skillsJson from '../data/skills.json';
import combosJson from '../data/combos.json';
import questJson from '../data/quest.json';
import { parseCSV, skillCountMult, RULES, canSummon, makeUnit, resolveAttack, refillMana, endTurnXp, aiPickTarget, canTarget, doAction, aiSummonOrder, aiPickSacrifice, aiWantAccel, aiWantFieldHeal, aiWantBuff, aiWantHeal, aiWantShuffle, aiPickItem, sacrifice, clearBuff, equip, setCardPool, levelUpOnce, xpToNext, gainXp, swapField } from './rules.js';
import { setSkillData, skillsOf, setRng, setEmitter, getEmitter, setSpare, initPlayers, placeUnit, turnStart, turnEnd, useSkill, skillState, aiPickSkill, refreshAll, checkDeath, spareBlocked } from './skills.js';
import { snapCard } from './pvp-core.js';
import { leaderSkill } from './sweep-core.js';
import './enemy-mr.js';
import './quest-gen.js';
import { rngOf, rollRank } from './direct-rng.js';
export { rngOf, rollRank };

const LV_RATE = { NORMAL: 0.01, RARE: 0.02, 'HIGH RARE': 0.03, 'SUPER RARE': 0.04, 'ULTRA RARE': 0.05, 'MYTHIC RARE': 0.06, 'LEGENDARY RARE': 0.05 };
const TOWER_BOSS = {
  normal: ['10439', '10331', '10324', '10358', '10062', '10060', '10311'],
  wind: ['10392', '10399', '10465', '10439', '10440', '10358', '10358'],
  ice: ['10024', '10317', '10255', '10341', '10045', '10322', '10359'],
  fire: ['10118', '10117', '10189', '10051', '10435', '10323', '10058'],
  light: ['10108', '10127', '10127', '10176', '10176', '10331', '10331'],
  dark: ['10415', '10054', '10325', '10304', '10324', '10291', '10326'],
};
const CLS = { wind: 'WIND', ice: 'ICE', fire: 'FIRE', light: 'LIGHT', dark: 'DARK' };
const cards = parseCSV(cardsCsv);
const npc = parseCSV(npcCsv);
const byId = new Map([...cards, ...npc].map(c => [String(c.id), c]));
setCardPool([...cards, ...npc]);
setSkillData(skillsJson, combosJson);
globalThis.VRQuestSkillMult = c => skillCountMult(skillsOf(c?.id));

const normals = () => cards.filter(c => c.grade === 'NORMAL').slice().sort((a, b) => a.power - b.power);
export function rollRankEnemies(stage, rng) { return rollRank(stage, rng, normals()); }
const BOSS_BASE = [500, 750, 1000, 1250, 1500];
const tierOf = n => Math.min(7, Math.max(1, Math.ceil(n / 50)));
function storyBossHp(chapter, stage) {
  if (stage?.baseHp != null) return Number(stage.baseHp);
  const i = Math.max(0, (chapter || 1) - 1);
  return i < BOSS_BASE.length ? BOSS_BASE[i] : BOSS_BASE[BOSS_BASE.length - 1] + 250 * (i - BOSS_BASE.length + 1);
}
const towerBossHp = n => 500 + 50 * (n / 10 - 1);

function scale(card, storyLv) {
  const lv = Math.max(1, Number(storyLv) || 1);
  const m = 1 + (LV_RATE[card.grade] || 0.01) * (lv - 1);
  return { ...card, HP: Math.round(card.HP * m), ATK: Math.round(card.ATK * m), DEF: Math.round(card.DEF * m), slv: lv };
}

/** Mid-battle insertion (awaken / joinAlly / revive.become). storyLevel scales HP·ATK·DEF like enemyFrom; do not treat it as a battle level. */
export function storyIntrusionCard(spec, fallback) {
  // become (target) before id (dying card). A 16-11 revive rule has both: id=10290, become=10291.
  const raw = spec?.card
    || (spec?.become != null && byId.get(String(spec.become)))
    || (spec?.id != null && byId.get(String(spec.id)))
    || fallback
    || null;
  if (!raw) return null;
  if (raw.storyBoost || raw.storyLv) return raw;
  return spec?.storyLevel ? scale(raw, spec.storyLevel) : { ...raw };
}

function mustSummonOf(stage) {
  if (stage?.mustSummon) return stage.mustSummon;
  if (stage?.tutorial || stage?.single !== true) return null;
  return stage.party?.forced || stage.party?.mustLive || null;
}

function enemyFrom(id, stage) {
  const base = byId.get(String(id));
  if (!base) return null;
  let c = { ...base };
  const storyLv = stage?.enemies?.storyLevels?.[String(base.id)];
  if (storyLv) c = scale(c, storyLv);
  const lv = stage?.enemies?.levels?.[String(base.id)];
  if (lv) c = { ...c, slv: lv };
  const boost = stage?.enemies?.boost?.[String(base.id)];
  if (boost && typeof boost === 'object') c = { ...c, ...boost };
  return c;
}

export function storyEnemies(stage, rng) {
  if (Array.isArray(stage?.enemies?.ids) && stage.enemies.ids.length) return stage.enemies.ids.map(id => enemyFrom(id, stage)).filter(Boolean);
  return rollRankEnemies(stage, rng);
}

function towerBossCard(tower, floor, level) {
  const id = (TOWER_BOSS[tower] || TOWER_BOSS.normal)[tierOf(floor) - 1];
  const c = byId.get(String(id));
  return c ? globalThis.VRQuestGen.leveled(c, level + 5) : null;
}

function bossMinions(tower, floor, boss, generated) {
  const G = globalThis.VRQuestGen;
  const spec = questJson.floors[floor - 1];
  const r = G.rngOf((floor * 7919 + 13) >>> 0);
  const L = generated.level || generated.leader?.qLevel || 1;
  const gi = Math.max(0, G.ORDER.indexOf(generated.grade || spec?.grade));
  const used = new Set([String(boss.id)]);
  const out = [];
  const take = c => { if (!c || used.has(String(c.id))) return false; used.add(String(c.id)); out.push(G.leveled(c, L)); return true; };
  const from = (gr, same) => cards.filter(c => !used.has(String(c.id)) && G.ORDER.indexOf(c.grade) === gr && (!same || c.class === boss.class));
  const elemental = !!CLS[tower];
  const pickOne = gr => { for (const same of elemental ? [true] : [true, false]) { const list = from(gr, same); if (list.length) return list[Math.floor(r() * list.length)]; } return null; };
  for (let i = 0; i < Math.min(5, Math.floor(floor / 50)); i++) take(pickOne(Math.min(G.ORDER.length - 2, gi + 1)) || pickOne(gi));
  const combo = (combosJson || []).find(cb => (cb.cards || []).map(String).includes(String(boss.id)));
  for (const id of combo?.cards || []) { if (out.length >= 5) break; const c = byId.get(String(id)); if (c && G.ORDER.indexOf(c.grade) <= gi + 1) take(c); }
  const keep = (generated.enemies || []).filter(c => !used.has(String(c.id)));
  while (out.length < 5) { const c = pickOne(gi) || keep.shift(); if (!c) break; if (!take(c)) continue; }
  return out.slice(0, 5);
}

export function towerEnemies(tower, floor) {
  const spec = questJson.floors?.[floor - 1];
  if (!spec) return { enemies: [], bossId: null, aiHp: null, win: 'wipe' };
  const G = globalThis.VRQuestGen;
  const generated = CLS[tower]
    ? G.generateAttr(questJson, spec, cards, { tower, cls: CLS[tower], npc, levelOffset: 10 })
    : G.generate(questJson, spec, cards, combosJson);
  if (floor % 10 !== 0) return { enemies: generated.enemies || [], bossId: null, aiHp: null, win: 'wipe', heroGuard: 0 };
  const level = generated.level || generated.leader?.qLevel || 1;
  const boss = towerBossCard(tower, floor, level);
  if (!boss) return { enemies: generated.enemies || [], bossId: null, aiHp: towerBossHp(floor), win: 'ko', heroGuard: 5 };
  const mins = bossMinions(tower, floor, boss, generated);
  return { enemies: [boss, ...(mins.length === 5 ? mins : (generated.enemies || []))], bossId: String(boss.id), aiHp: towerBossHp(floor), win: 'ko', heroGuard: 5 };
}

// Same card the live story battle picks, then the same gear.cd add (js/story.js bossOf + bossCdMinus).
function applyBossCd(stage, enemies) {
  if (stage?.type !== 'boss' || !stage.bossCdMinus || !enemies?.length) return enemies;
  const bc = (stage.bossId != null && enemies.find(c => String(c.id) === String(stage.bossId)))
    || (stage.enemyName && enemies.find(c => c.name === stage.enemyName))
    || (stage.enemies?.ids ? enemies[0] : [...enemies].sort((a, b) => (b.power || 0) - (a.power || 0))[0]);
  if (!bc) return enemies;
  bc.gear = { ...(bc.gear || {}), cd: (bc.gear?.cd || 0) + (stage.bossCdMinus | 0) };
  return enemies;
}

function combatCard(raw) {
  const src = raw?.loan && typeof raw.loan === 'object'
    ? { ...raw.loan, id: raw.id, uid: raw.uid, gear: raw.gear || raw.loan.gear || [], sigil: raw.sigil ?? raw.loan.sigil ?? null }
    : raw;
  const card = snapCard(src, id => byId.get(String(id)), 'tower');
  if (!card) return null;
  card.uid = raw.uid;
  return card;
}

function raiseLevels(u, lv) {
  while (u.level < Math.min(lv | 0, RULES.LEVEL_MAX)) levelUpOnce(u);
}

function sideSnap(p) {
  return { hp: p.hp | 0, max: p.maxHp | 0, units: p.field.map(u => ({ id: String(u.card.id), hp: u.hp | 0, max: u.maxHp | 0 })) };
}
function pack(state, win, reason) {
  const turns = Math.max(1, Math.min(40, state.totalTurns | 0 || 1));
  return {
    win: !!win, reason, turns, my_turns: Math.max(1, state.myTurns | 0 || 1),
    mana: state.me.manaPool ? Math.max(0, state.me.mana | 0) : null,
    max_mana: state.me.manaPool ? Math.max(0, state.me.maxMana | 0) : null,
  };
}

function specFrom(session, rng) {
  const snap = session.snapshot || {};
  const stage = snap.stage || {};
  if (session.mode === 'tower') {
    const [tower, floorText] = String(session.target || '').split(':');
    const floor = Number(floorText);
    if (!/^(normal|wind|ice|fire|light|dark)$/.test(tower) || !Number.isInteger(floor) || floor < 1) throw new Error('unsupported battle');
    const built = towerEnemies(tower, floor);
    return {
      me: (snap.cards || []).map(combatCard).filter(Boolean),
      ai: built.enemies, win: built.win, aiHp: built.aiHp, bossId: built.bossId, heroGuard: built.heroGuard || 0,
      first: rng() < 0.5 ? 'me' : 'ai', mana: null, rules: {}, leaderUid: snap.leader || null,
    };
  }
  const enemies = applyBossCd(stage, storyEnemies(stage, rng));
  if (!enemies.length) throw new Error('unsupported battle');
  const mana = snap.mana == null ? null : Number(snap.mana);
  const boss = stage.type === 'boss' || stage.baseHp != null;
  const chapter = Number(String(session.target || '').split(':')[0]);
  return {
    me: (snap.cards || []).map(combatCard).filter(Boolean).map(card => {
      const mul = stage.party?.statMul?.[String(card.id)];
      if (!mul) return card;
      const o = { ...card };
      for (const k of ['HP', 'ATK', 'DEF']) if (mul[k] != null) o[k] = Math.round(o[k] * mul[k]);
      return o;
    }),
    ai: enemies,
    win: boss ? 'ko' : 'wipe',
    aiHp: boss ? storyBossHp(chapter, stage) : null,
    // The live fight only puts a card in the boss slot when the phase type is boss.
    // Normal phases still carry bossId in the chapter data; treating that as undying
    // leaves the card at 1 HP and the wipe never finishes.
    bossId: stage.type === 'boss' && stage.bossId != null ? String(stage.bossId) : (stage.rules?.invuln != null ? String(stage.rules.invuln) : null),
    heroGuard: 0,
    first: stage.enemyFirst ? 'ai' : 'me',
    mana: Number.isFinite(mana) ? mana : null,
    rules: stage.rules || {},
    mustSummon: mustSummonOf(stage),
    reserve: stage.reserve || [],
    awaken: stage.awaken || null,
    joinAlly: stage.joinAlly || null,
    spare: stage.spare || null,
    leaderUid: snap.leader || null,
    fullMp: !!stage.fullMp,
    meLevels: stage.party?.battleLevels || null,
    enemyLevels: stage.enemies?.levels || null,
    stage,
  };
}

export function verifyDirect(session, actions) {
  if (!session || (session.mode !== 'story' && session.mode !== 'tower')) throw new Error('not a direct battle');
  if (!Array.isArray(actions) || actions.length > 200) throw new Error('tampered');
  const seed = Number(session.seed);
  if (!Number.isSafeInteger(seed) || seed < 1) throw new Error('tampered');
  const rng = rngOf(seed);
  const spec = specFrom(session, rng);
  if (session.mode === 'story' && spec.stage?.loseClears && actions.some(a => a && a.k === 'giveup')) {
    return { win: false, reason: 'giveup', turns: 2, my_turns: 1, mana: null, max_mana: null };
  }
  const result = runDirect(spec, actions, rng);
  if (session.mode === 'story' && spec.stage?.loseClears && result.reason !== 'giveup') return { ...result, win: false, scripted: 'loseClears' };
  return result;
}

export function runDirect(spec, actions, rng = null) {
  if (!rng) rng = rngOf(1);
  setRng(rng);
  setEmitter(() => {});
  setSpare(spec.spare || null);
  const meCards = (spec.me || []).filter(Boolean).slice(0, 10);
  const aiCards = (spec.ai || []).filter(Boolean).slice(0, 12);
  if (!meCards.length || !aiCards.length) throw new Error('unsupported battle');
  const mana = spec.mana == null ? null : Math.max(0, Math.round(spec.mana));
  const me = { name: '나', hp: RULES.HERO_HP, maxHp: RULES.HERO_HP, deck: meCards.map(c => ({ ...c })), hand: [], field: [], mana: 0, maxMana: 0, noBase: true, noActs: true, limitedAids: true };
  const ai = { name: '적', hp: spec.win === 'ko' ? (spec.aiHp || 3000) : RULES.HERO_HP, maxHp: spec.win === 'ko' ? (spec.aiHp || 3000) : RULES.HERO_HP, deck: aiCards.map(c => ({ ...c })), hand: [], field: [], mana: 0, maxMana: 0, noBase: spec.win !== 'ko', noActs: true, limitedAids: true, heroGuard: spec.heroGuard || 0 };
  const state = { me, ai, turn: spec.first === 'ai' ? 'ai' : 'me', first: spec.first === 'ai' ? 'ai' : 'me', turnNo: 0, totalTurns: 0, myTurns: 0, over: false, win: null, reason: null, rules: spec.rules || {}, awaken: spec.awaken, awakened: false, joinAlly: spec.joinAlly, allyJoined: false, mustSummon: null, reserve: [], reviveUsed: {}, pairShield: null };
  initPlayers(me, ai, state.first === 'ai' ? ai : me);
  const bossIds = [spec.bossId, spec.rules?.invuln].filter(x => x != null).map(String);
  for (const who of ['me', 'ai']) {
    const p = state[who];
    if (who === 'me' && mana != null) { p.hand = p.deck.splice(0); p.manaPool = true; p.mana = p.maxMana = mana; continue; }
    const nb = p.deck.slice(0, RULES.FIELD_MAX + bossIds.length).filter(c => bossIds.includes(String(c.id))).length;
    const extra = (who === 'ai' && !bossIds.length) ? Math.max(0, p.deck.length - RULES.FIELD_MAX) : 0;
    for (const c of p.deck.splice(0, RULES.FIELD_MAX + nb + extra)) {
      const u = placeUnit(p, c, makeUnit);
      if (who === 'me' && spec.leaderUid && c.uid === spec.leaderUid) { u.isLeader = true; p.leaderSkill = { ...leaderSkill(c), uid: c.uid, deathPenalty: 0.3 }; }
      if (who === 'me' && spec.meLevels) raiseLevels(u, spec.meLevels[String(c.id)] || 0);
      if (who === 'me' && spec.fullMp) u.mp = u.maxMp;
      if (who === 'ai' && spec.bossId != null && String(c.id) === String(spec.bossId) && !p.field.some(x => x.undying)) { u.undying = true; u.boss = true; }
      if (who === 'ai' && spec.enemyLevels) raiseLevels(u, spec.enemyLevels[String(c.id)] || 0);
      if (who === 'ai' && (spec.rules?.undying || []).map(String).includes(String(c.id))) u.undying = true;
      if (who === 'ai' && spec.rules?.invuln != null && String(c.id) === String(spec.rules.invuln)) { u.undying = true; u.noDamage = true; u.boss = true; }
      const blind = spec.rules?.blind?.[String(c.id)];
      if (who === 'me' && blind) u.card.blindP = +blind;
    }
    p.deck = [];
    p.fieldCap = Math.max(RULES.FIELD_MAX, p.field.length);
  }
  const reserveIds = Array.isArray(spec.reserve) ? spec.reserve : [];
  state.reserve = reserveIds.map(id => byId.get(String(id))).filter(Boolean).map(c => ({ card: c }));
  if (mana != null) {
    const need = (spec.mustSummon || []).map(String).filter(id => me.hand.some(c => String(c.id) === id));
    state.mustSummon = need.length ? { ids: need, by: need.length >= 2 ? 3 : 2 } : null;
  }
  const ps = spec.rules?.pairShield;
  if (ps) {
    const tgt = me.field.find(u => String(u.card.id) === String(ps.id));
    if (tgt && me.field.some(u => String(u.card.id) === String(ps.with))) { tgt.noDamage = true; state.pairShield = { u: tgt, turns: ps.turns | 0 }; }
  }
  refreshAll(me); refreshAll(ai);
  let cursor = 0;
  const done = (win, reason) => { if (!state.over) { state.over = true; state.win = win; state.reason = reason; } return true; };
  const gone = p => !p.field.length && !p.hand.length && !p.deck.length;
  const mustLeft = () => state.mustSummon ? state.mustSummon.ids.filter(id => !me.field.some(u => String(u.card.id) === id) && me.hand.some(c => String(c.id) === id)) : [];
  const affordable = () => me.hand.filter(c => { try { return canSummon(c, me, ai).ok; } catch { return false; } });
  function checkEnd() {
    if (state.over) return true;
    if (ai.hp <= 0 || me.hp <= 0) return done(ai.hp <= 0, 'ko');
    awaken();
    if (state.mustLiveDown) return done(false, 'mustlive');
    if (spec.win === 'wipe' && gone(ai)) return done(true, 'wipe');
    if (me.manaPool ? !me.field.length && !affordable().length : gone(me)) return done(false, 'wipe');
    return false;
  }
  function awaken() {
    const A = state.awaken;
    if (!A || state.awakened) return;
    const on = String(A.on || '');
    if (me.field.some(u => u.hp > 0 && String(u.card.id) === on)) { state.seenAwaken = true; return; }
    if (!state.seenAwaken) return;
    const card = storyIntrusionCard(A);
    if (!card) return;
    state.awakened = true;
    const u = placeUnit(me, { ...card }, makeUnit, true);
    raiseLevels(u, A.battleLevel || 1);
    u.hp = u.maxHp; u.mp = u.maxMp; u.canAttack = true;
  }
  function joinAlly() {
    const J = state.joinAlly;
    if (!J || state.allyJoined || state.myTurns < (J.afterTurn || 1)) return;
    const card = storyIntrusionCard(J);
    if (!card || me.field.filter(u => u.hp > 0).length >= RULES.FIELD_MAX) return;
    state.allyJoined = true;
    const u = placeUnit(me, { ...card }, makeUnit, true);
    raiseLevels(u, J.battleLevel || 1);
    u.hp = u.maxHp; u.canAttack = true;
  }
  function revive(who) {
    const p = state[who];
    if (!p.reviveQ?.length) return;
    const q = p.reviveQ.splice(0);
    for (const r of q) {
      if (--r.wait > 0 || p.field.filter(u => u.hp > 0).length >= (p.fieldCap || RULES.FIELD_MAX)) { p.reviveQ.push(r); continue; }
      const u = placeUnit(p, { ...r.card }, makeUnit);
      while (u.level < r.level) { const need = xpToNext(u.level) - (u.xp | 0); if (!isFinite(need) || !gainXp(u, Math.max(1, need))) break; }
    }
    refreshAll(p);
  }
  function onDeath(u) {
    const id = String(u.card.id);
    if (u.owner === me && (state.rules.mustLive || []).map(String).includes(id)) state.mustLiveDown = true;
    if (u.owner === ai) {
      const r = (state.rules.revive || []).find(x => String(x.id) === id);
      if (!r) return;
      const k = id + ':' + (u.uid || 0);
      if (r.times && (state.reviveUsed[k] | 0) >= r.times) return;
      state.reviveUsed[k] = (state.reviveUsed[k] | 0) + 1;
      const wait = (r.delay == null || r.delay === '') ? 1 : Math.max(0, r.delay | 0);
      const card0 = r.become ? (storyIntrusionCard(r, u.base)) : (r.card || u.base);
      const level = r.become ? (r.battleLevel || 1) : (r.level === 'keep' ? u.level : 1);
      (ai.reviveQ ||= []).push({ card: card0, level, wait });
      if (wait === 0) revive('ai');
    }
  }
  const oldEmit = getEmitter();
  setEmitter(e => { if (e?.type === 'destroy' && e.unit) onDeath(e.unit); oldEmit(e); });
  function startTurn(who) {
    if (state.over) return;
    state.turn = who;
    if (who === state.first) state.turnNo++;
    state.totalTurns++;
    if (state.pairShield && state.turnNo > state.pairShield.turns) { state.pairShield.u.noDamage = false; state.pairShield = null; }
    const p = state[who];
    p.ownTurns = (p.ownTurns || 0) + 1;
    if (who === 'me') { state.myTurns++; joinAlly(); }
    revive(who);
    if (state.rules.expire && state.rules.invuln != null && state.turnNo > state.rules.expire) {
      for (const u of [...ai.field]) { u.undying = false; u.noDamage = false; u.hp = 0; checkDeath(u); }
    }
    clearBuff(who === 'me' ? ai : me);
    refillMana(p);
    p.field.forEach(u => { u.canAttack = true; });
    turnStart(p);
    checkEnd();
  }
  function aiAct() {
    const script = (state.rules.aiScript || []).find(x => x.turn === (ai.ownTurns | 0));
    if (script) {
      const u = (script.unit && ai.field.find(x => String(x.card.id) === String(script.unit) && x.hp > 0)) || ai.field.find(x => x.hp > 0);
      if (script.skill && u) { const s = (u.sk || []).find(x => x.name === script.skill); if (s) useSkill(u, s); }
      if (script.end !== false) { if (!state.over) { endTurnXp(ai); turnEnd(ai); checkEnd(); } return; }
    }
    if (aiWantShuffle(ai, me)) doAction('shuffle', ai);
    if (aiWantAccel(ai, true)) doAction('accel', ai);
    const sac = aiPickSacrifice(ai, me);
    if (sac) sacrifice(sac, ai);
    for (const c of aiSummonOrder(ai.hand)) if (canSummon(c, ai, me).ok) { ai.mana -= c.cost; ai.hand.splice(ai.hand.indexOf(c), 1); placeUnit(ai, c, makeUnit, true); }
    for (let it; (it = aiPickItem(ai, me));) equip(it[0], it[1], ai);
    if (aiWantAccel(ai)) doAction('accel', ai);
    if (aiWantFieldHeal(ai)) doAction('fieldheal', ai);
    if (aiWantBuff(ai)) doAction('buff', ai);
    for (const u of [...ai.field]) {
      if (state.over || !u.canAttack || !ai.field.includes(u)) continue;
      if (spareBlocked(u)) { u.canAttack = false; continue; }
      const sk = aiPickSkill(u);
      if (sk) { useSkill(u, sk); checkEnd(); continue; }
      const target = aiPickTarget(u, ai, me);
      if (target === undefined) continue;
      resolveAttack(ai, me, u, target);
      checkEnd();
    }
    if (!state.over && aiWantHeal(ai)) doAction('heal', ai);
    if (!state.over) { endTurnXp(ai); turnEnd(ai); checkEnd(); }
    const survive = state.rules.survive;
    if (!state.over && survive && state.totalTurns >= survive * 2) done(true, 'survive');
  }
  function apply(a) {
    if (!a || a.t !== state.myTurns || state.turn !== 'me' || state.over) throw new Error('tampered');
    if (a.k === 'giveup') return done(false, 'giveup');
    if (a.k === 'end') {
      endTurnXp(me); turnEnd(me);
      if (state.mustSummon && state.myTurns >= state.mustSummon.by && mustLeft().length) return done(false, 'mustsummon');
      checkEnd();
      const survive = state.rules.survive;
      if (!state.over && survive && state.totalTurns >= survive * 2) done(true, 'survive');
      return 'end';
    }
    if (a.k === 'summon') {
      const card = me.hand.find(c => String(c.id) === String(a.id));
      if (!card || !canSummon(card, me, ai).ok) throw new Error('tampered');
      me.mana -= card.cost; me.hand.splice(me.hand.indexOf(card), 1);
      const u = placeUnit(me, card, makeUnit, true);
      if (me.manaPool && spec.leaderUid && card.uid === spec.leaderUid) { u.isLeader = true; me.leaderSkill = { ...leaderSkill(card), uid: card.uid, deathPenalty: 0.3 }; }
      if (spec.meLevels) raiseLevels(u, spec.meLevels[String(card.id)] || 0);
      refreshAll(me);
      checkEnd();
      return 'ok';
    }
    if (a.k === 'reserve') {
      const r = state.reserve.shift();
      if (!r || me.field.filter(u => u.hp > 0).length >= RULES.FIELD_MAX) throw new Error('tampered');
      const u = placeUnit(me, { ...r.card }, makeUnit);
      u.canAttack = true; checkEnd(); return 'ok';
    }
    if (a.k === 'buff') { if (!doAction('buff', me).ok) throw new Error('tampered'); return 'ok'; }
    if (a.k === 'atk') {
      const u = me.field[a.i];
      const target = a.g === -1 ? null : ai.field[a.g];
      if (!u || u.hp <= 0 || !u.canAttack || !canTarget(me, ai, target, u)) throw new Error('tampered');
      resolveAttack(me, ai, u, target); checkEnd(); return 'ok';
    }
    if (a.k === 'skill') {
      const u = me.field[a.i];
      const s = (u?.sk || []).find(x => x.name === a.s);
      if (!u || u.hp <= 0 || !s || !skillState(u, s).ok) throw new Error('tampered');
      useSkill(u, s); checkEnd(); return 'ok';
    }
    if (a.k === 'undo') {
      const u = [...me.field].reverse().find(x => String(x.card.id) === String(a.id) && x.hp > 0);
      if (!u) throw new Error('tampered');
      me.field = me.field.filter(x => x !== u);
      me.hand.push(u.base);
      me.mana += u.base.cost || 0;
      refreshAll(me);
      return 'ok';
    }
    if (a.k === 'swap') {
      const x = me.field[a.i], y = me.field[a.g];
      if (!x || !y || !swapField(me, x, y)) throw new Error('tampered');
      return 'ok';
    }
    throw new Error('tampered');
  }
  const max = Math.min(40, spec.rules?.maxTurns || RULES.MAX_TURNS);
  try {
    while (!state.over && state.totalTurns < max) {
      startTurn(state.turn);
      if (state.over) break;
      if (state.turn === 'me') {
        let ended = false;
        while (!state.over && !ended) {
          const a = actions[cursor];
          if (!a) { done(false, 'incomplete'); break; }
          cursor++;
          const step = apply(a);
          if (step === 'end') ended = true;
        }
        if (!state.over) state.turn = 'ai';
      } else {
        aiAct();
        if (!state.over) state.turn = 'me';
      }
    }
    if (!state.over) done(false, 'timeout');
  } finally { setSpare(null); setEmitter(oldEmit); }
  if (cursor < actions.length && state.reason !== 'giveup') throw new Error('tampered');
  const out = pack(state, state.win, state.reason);
  if (!out.win) out.debug = { turn: state.turnNo | 0, my_turns: state.myTurns | 0, action: cursor, reason: state.reason, me: sideSnap(state.me), ai: sideSnap(state.ai) };
  return out;
}

if (typeof window !== 'undefined' && !window.VRDirect) window.VRDirect = { rngOf, rollRank };
