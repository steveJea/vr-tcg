// Client story/tower battle vs the direct replay. The client loop follows js/game.js
// (field start, seeded RNG, AUTO or manual clicks). The replay must finish the same way.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runDirect, verifyDirect, towerEnemies, rngOf as engineRngOf, storyIntrusionCard } from '../supabase/functions/story-direct-verify-v7/engine.mjs';
import { bossCard } from '../js/raid-core.js';
import { snapCard } from '../js/pvp-core.js';
import { ENEMY_MR_BASE } from '../js/enemy-mr.js';
import { rngOf } from '../js/direct-rng.js';
import { leaderSkill } from '../js/sweep-core.js';
import { autoNext, noteUsed } from '../js/auto-ai.js';
import {
  RULES, canSummon, makeUnit, resolveAttack, refillMana, endTurnXp, canTarget, doAction, levelUpOnce,
  aiSummonOrder, aiPickSacrifice, aiWantAccel, aiWantFieldHeal, aiWantBuff, aiWantHeal, aiWantShuffle,
  sacrifice, aiPickTarget, autoTarget, attackTargets, clearBuff, aiPickItem, equip, swapField, setCardPool, parseCSV,
  gainXp, xpToNext,
} from '../js/rules.js';
import {
  setSkillData, setRng, setEmitter, setSpare, initPlayers, placeUnit, turnStart, turnEnd,
  useSkill, skillState, aiPickSkill, refreshAll, spareBlocked, skillsOf,
} from '../js/skills.js';
import { skillCountMult } from '../js/rules.js';

const rd = p => readFileSync(new URL(p, import.meta.url), 'utf8');
const pool = parseCSV(rd('../data/cards.csv'));
setCardPool([...pool, ...parseCSV(rd('../data/npc_cards.csv'))]);
setSkillData(JSON.parse(rd('../data/skills.json')), JSON.parse(rd('../data/combos.json')));
globalThis.VRQuestSkillMult = c => skillCountMult(skillsOf(c?.id));
await import('../js/quest-gen.js');
const G = globalThis.VRQuestGen;

const clone = c => ({ ...c, gear: c.gear ? { ...c.gear } : undefined });
const LV_RATE = { NORMAL: 0.01, RARE: 0.02, 'HIGH RARE': 0.03, 'SUPER RARE': 0.04, 'ULTRA RARE': 0.05, 'MYTHIC RARE': 0.06, 'LEGENDARY RARE': 0.05 };
function lvScaled(c, lv) {
  if (!c || c.storyBoost || c.storyLv) return c;
  const n = Math.max(1, Number(lv) || 1);
  if (n <= 1) return { ...c };
  const m = 1 + (LV_RATE[c.grade] || 0.01) * (n - 1);
  return { ...c, HP: Math.round(c.HP * m), ATK: Math.round(c.ATK * m), DEF: Math.round(c.DEF * m), storyLv: n, storyBoost: true };
}
const cardOf = id => pool.find(x => String(x.id) === String(id));
function intrusionCard(spec, fallback) {
  const raw = spec?.card || (spec?.become != null && cardOf(spec.become)) || (spec?.id != null && cardOf(spec.id)) || fallback || null;
  return lvScaled(raw, spec?.storyLevel);
}

function deckAt(level, ids) {
  return ids.map(id => {
    const c = pool.find(x => String(x.id) === String(id));
    return { ...G.leveled(c, level), uid: 'u' + id };
  });
}

// Live fight (js/game.js startTurn / aiTurn / autoTurn) without the screen.
function playClient(spec, seed, policy) {
  const rng = rngOf(seed);
  const first = spec.first || (rng() < 0.5 ? 'me' : 'ai');
  setRng(rng);
  setEmitter(() => {});
  setSpare(spec.spare || null);
  const me = { name: '나', hp: RULES.HERO_HP, maxHp: RULES.HERO_HP, deck: spec.me.map(clone), hand: [], field: [], mana: 0, maxMana: 0, noBase: true, noActs: true, limitedAids: true };
  const aiHp = spec.win === 'ko' ? (spec.aiHp || 3000) : RULES.HERO_HP;
  const ai = { name: '적', hp: aiHp, maxHp: aiHp, deck: spec.ai.map(clone), hand: [], field: [], mana: 0, maxMana: 0, noBase: spec.win !== 'ko', noActs: true, limitedAids: true, heroGuard: spec.heroGuard || 0 };
  const state = { me, ai, turn: first, first, turnNo: 0, totalTurns: 0, myTurns: 0, over: false, win: null, reason: null, rules: spec.rules || {} };
  initPlayers(me, ai, first === 'ai' ? ai : me);
  const bossIds = [spec.bossId].filter(x => x != null).map(String);
  for (const who of ['me', 'ai']) {
    const p = state[who];
    const nb = p.deck.slice(0, RULES.FIELD_MAX + bossIds.length).filter(c => who === 'ai' && bossIds.includes(String(c.id))).length;
    const extra = (who === 'ai' && !bossIds.length) ? Math.max(0, p.deck.length - RULES.FIELD_MAX) : 0;
    for (const c of p.deck.splice(0, RULES.FIELD_MAX + (who === 'ai' ? nb : 0) + extra)) {
      const u = placeUnit(p, c, makeUnit);
      if (who === 'me' && spec.leaderUid && c.uid === spec.leaderUid) { u.isLeader = true; p.leaderSkill = { ...leaderSkill(c), uid: c.uid, deathPenalty: 0.3 }; }
      if (who === 'ai' && spec.bossId != null && String(c.id) === String(spec.bossId) && !p.field.some(x => x.undying)) { u.undying = true; u.boss = true; }
    }
    p.deck = [];
    p.fieldCap = Math.max(RULES.FIELD_MAX, p.field.length);
  }
  refreshAll(me); refreshAll(ai);
  const log = [];
  const gone = p => !p.field.length && !p.hand.length && !p.deck.length;
  const done = (win, reason) => { if (!state.over) { state.over = true; state.win = win; state.reason = reason; } return true; };
  function awaken() {
    const A = spec.awaken;
    if (!A || state.awakened || me.field.some(u => String(u.card.id) === String(A.on))) return;
    const card = intrusionCard(A);
    if (!card) return;
    state.awakened = true;
    const u = placeUnit(me, { ...card }, makeUnit, true);
    while (u.level < Math.min(A.battleLevel || 1, RULES.LEVEL_MAX)) levelUpOnce(u);
    u.hp = u.maxHp; u.mp = u.maxMp; u.canAttack = true;
  }
  function joinAlly() {
    const J = spec.joinAlly;
    if (!J || state.allyJoined || state.myTurns < (J.afterTurn || 1)) return;
    const card = intrusionCard(J);
    if (!card || me.field.filter(u => u.hp > 0).length >= RULES.FIELD_MAX) return;
    state.allyJoined = true;
    const u = placeUnit(me, { ...card }, makeUnit, true);
    while (u.level < Math.min(J.battleLevel || 1, RULES.LEVEL_MAX)) levelUpOnce(u);
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
  }
  function onDeath(u) {
    if (u.owner === me && (spec.rules?.mustLive || []).map(String).includes(String(u.card.id))) state.mustLiveDown = true;
    if (u.owner !== ai) return;
    const r = (spec.rules?.revive || []).find(x => String(x.id) === String(u.card.id));
    if (!r) return;
    const wait = (r.delay == null || r.delay === '') ? 1 : Math.max(0, r.delay | 0);
    const card0 = r.become ? intrusionCard(r, u.base) : (r.card || u.base);
    const level = r.become ? (r.battleLevel || 1) : (r.level === 'keep' ? u.level : 1);
    (ai.reviveQ ||= []).push({ card: card0, level, wait });
    if (wait === 0) revive('ai');
  }
  setEmitter(e => { if (e?.type === 'destroy' && e.unit) onDeath(e.unit); });
  function checkEnd() {
    if (state.over) return true;
    if (ai.hp <= 0 || me.hp <= 0) return done(ai.hp <= 0, 'ko');
    awaken();
    if (state.mustLiveDown) return done(false, 'mustlive');
    if (spec.win === 'wipe' && gone(ai)) return done(true, 'wipe');
    if (gone(me)) return done(false, 'wipe');
    return false;
  }
  function startTurn(who) {
    if (state.over) return;
    state.turn = who;
    if (who === state.first) state.turnNo++;
    state.totalTurns++;
    const p = state[who];
    p.ownTurns = (p.ownTurns || 0) + 1;
    if (who === 'me') { state.myTurns++; joinAlly(); }
    revive(who);
    clearBuff(who === 'me' ? ai : me);
    refillMana(p);
    p.field.forEach(u => { u.canAttack = true; });
    turnStart(p);
    checkEnd();
  }
  function aiAct() {
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
      if (state.over || !ai.field.includes(u) || !u.canAttack) continue;
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
  }
  function act(a) {
    if (a.k === 'end') { endTurnXp(me); turnEnd(me); checkEnd(); return; }
    if (a.k === 'buff') { doAction('buff', me); return; }
    if (a.k === 'skill') { const u = me.field[a.i]; const s = (u?.sk || []).find(x => x.name === a.s); if (u && s) useSkill(u, s); checkEnd(); return; }
    if (a.k === 'swap') { const x = me.field[a.i], y = me.field[a.g]; if (x && y) swapField(me, x, y); return; }
    if (a.k === 'atk') { const u = me.field[a.i]; const target = a.g === -1 ? null : ai.field[a.g]; resolveAttack(me, ai, u, target); checkEnd(); }
  }
  const max = spec.rules?.maxTurns || RULES.MAX_TURNS;
  while (!state.over && state.totalTurns < max) {
    startTurn(state.turn);
    if (state.over) break;
    if (state.turn === 'me') {
      const turn = { used: new Set(), scopes: new Set() };
      let guard = 0;
      while (!state.over && guard++ < 40) {
        let a = null;
        if (policy === 'swap-batch' && !state.swapped && me.field.length >= 2) {
          state.swapped = true;
          a = { t: state.myTurns, k: 'swap', i: 0, g: 1 };
        } else if (policy === 'auto') {
          const n = autoNext(me, ai, turn);
          if (!n) break;
          if (n.kind === 'skill') { noteUsed(turn, n.s); a = { t: state.myTurns, k: 'skill', i: me.field.indexOf(n.u), s: n.s.name }; }
          else a = { t: state.myTurns, k: 'atk', i: me.field.indexOf(n.u), g: n.t ? ai.field.indexOf(n.t) : -1 };
        } else if (policy === 'batch' || policy === 'swap-batch') {
          const u = me.field.find(x => x.hp > 0 && x.canAttack && !spareBlocked(x));
          if (!u) break;
          let t;
          if (policy === 'batch' && !state.manualDone) {
            const foes = ai.field.filter(x => x.hp > 0 && !x.undying);
            const named = foes.find(x => String(x.card.id) === '10022') || foes[Math.min(1, foes.length - 1)] || foes[0];
            const tg = attackTargets(me, ai, u);
            t = named && tg.units.includes(named) ? named : (tg.hero ? null : tg.units[0]);
            state.manualDone = true;
          } else t = autoTarget(u, me, ai);
          if (t === undefined) { u.canAttack = false; continue; }
          a = { t: state.myTurns, k: 'atk', i: me.field.indexOf(u), g: t ? ai.field.indexOf(t) : -1 };
        } else {
          const u = me.field.find(x => x.hp > 0 && x.canAttack && !spareBlocked(x));
          if (!u) break;
          const tg = attackTargets(me, ai, u);
          if (policy === 'manual' && tg.hero) a = { t: state.myTurns, k: 'atk', i: me.field.indexOf(u), g: -1 };
          else if (tg.units.length) {
            const t = tg.units.slice().sort((x, y) => x.hp - y.hp)[0];
            a = { t: state.myTurns, k: 'atk', i: me.field.indexOf(u), g: ai.field.indexOf(t) };
          } else if (tg.hero) a = { t: state.myTurns, k: 'atk', i: me.field.indexOf(u), g: -1 };
          else { u.canAttack = false; continue; }
          if (policy === 'skill') {
            const s = (u.sk || []).find(x => skillState(u, x).ok);
            if (s) a = { t: state.myTurns, k: 'skill', i: me.field.indexOf(u), s: s.name };
          }
        }
        if (!a || (a.k === 'atk' && !canTarget(me, ai, a.g === -1 ? null : ai.field[a.g], me.field[a.i]))) break;
        log.push(a);
        act(a);
      }
      if (!state.over) { log.push({ t: state.myTurns, k: 'end' }); act({ k: 'end' }); }
      if (!state.over) state.turn = 'ai';
    } else {
      aiAct();
      if (!state.over) state.turn = 'me';
    }
  }
  if (!state.over) done(false, 'timeout');
  setSpare(null);
  return { win: !!state.win, reason: state.reason, turns: state.totalTurns, my_turns: state.myTurns, log, aiHp: ai.hp };
}

function replay(spec, seed, log) {
  const rng = engineRngOf(seed);
  const first = spec.first || (rng() < 0.5 ? 'me' : 'ai');
  return runDirect({ ...spec, first }, log, rng);
}

const cases = [];
function add(label, spec, seed, policy) {
  const client = playClient(spec, seed, policy);
  let server, error = null;
  try { server = replay(spec, seed, client.log); }
  catch (e) { error = e.message; }
  cases.push({ label, policy, seed, spec, client, server, error });
}

const strong = ['10051', '10323', '10058', '10311', '10118'];
const mid = ['10118', '10067', '10333', '10045', '10109'];
for (const tower of ['normal', 'wind', 'ice', 'fire', 'light', 'dark']) {
  for (const floor of [10, 20, 50, 100]) {
    const built = towerEnemies(tower, floor);
    const spec = { me: deckAt(floor < 50 ? 50 : 60, strong), ai: built.enemies, win: built.win, aiHp: built.aiHp, bossId: built.bossId, heroGuard: built.heroGuard || 0, leaderUid: 'u10051' };
    for (const policy of ['auto', 'manual']) for (const seed of [3, 8, 21, 1000 + floor]) add(`${tower} ${floor} boss`, spec, seed, policy);
  }
  const normal = towerEnemies(tower, 7);
  const spec = { me: deckAt(20, mid), ai: normal.enemies, win: normal.win, aiHp: normal.aiHp, bossId: null, heroGuard: 0 };
  for (const seed of [7, 11, 19]) {
    add(`${tower} 7 normal`, spec, seed, 'auto');
    add(`${tower} 7 normal`, spec, seed, 'manual');
  }
}
const storyBoss = {
  me: deckAt(30, strong), ai: deckAt(12, ['10074', '10080', '10445', '10375', '10051']),
  win: 'ko', aiHp: 750, bossId: '10051', heroGuard: 0,
};
storyBoss.ai = storyBoss.ai.map(c => ({ ...c, uid: undefined }));
add('story boss', storyBoss, 21, 'auto');
add('story boss', storyBoss, 21, 'manual');
add('story boss', storyBoss, 8, 'skill');
const awaken = {
  me: deckAt(8, ['10074', '10080', '10445', '10375', '10404']),
  ai: deckAt(20, ['10051']).map(c => ({ ...c, HP: 400, ATK: 80, DEF: 40 })),
  win: 'wipe', aiHp: null, bossId: null, heroGuard: 0,
  awaken: { on: '10074', id: '10311', battleLevel: 30 },
};
for (const seed of [4, 12]) for (const policy of ['auto', 'manual']) add('story awaken', awaken, seed, policy);
// 17-14 style: no pre-scaled card, storyLevel on the intrusion (이지영).
const awakenLv = {
  me: deckAt(8, ['10074', '10080', '10445', '10375', '10404']),
  ai: deckAt(20, ['10051']).map(c => ({ ...c, HP: 400, ATK: 80, DEF: 40 })),
  win: 'wipe', aiHp: null, bossId: null, heroGuard: 0,
  awaken: { on: '10074', id: '10311', storyLevel: 50, battleLevel: 1 },
};
for (const seed of [4, 12]) for (const policy of ['auto', 'manual']) add('story awaken storyLevel', awakenLv, seed, policy);
// 16-11 style: 윤진아 dies and becomes [각성] 윤진아 at storyLevel 100, battleLevel 10. No pre-scaled card.
const becomeLv = {
  me: deckAt(30, strong),
  ai: [clone(cardOf('10290'))],
  win: 'wipe', aiHp: null, bossId: null, heroGuard: 0, first: 'me',
  rules: { maxTurns: 20, revive: [{ id: '10290', become: '10291', delay: 0, storyLevel: 100, battleLevel: 10 }] },
};
for (const seed of [4, 12]) for (const policy of ['auto', 'manual']) add('story become storyLevel', becomeLv, seed, policy);
// Real 16-11 stage (6 enemies, mustLive 소민섭, 윤진아 → [각성] 윤진아). Server path has id+become and no pre-scaled card.
const ch1611Boost = {
  '10406': { HP: 580, ATK: 81, DEF: 81, storyLv: 45, power: 38309 },
  '10290': { HP: 179, ATK: 19, DEF: 21, storyLv: 45, power: 7682 },
  '10383': { HP: 966, ATK: 124, DEF: 138, storyLv: 45, power: 116253 },
  '10097': { HP: 235, ATK: 30, DEF: 56, storyLv: 45, power: 10455 },
  '10393': { HP: 499, ATK: 70, DEF: 81, storyLv: 45, power: 38466 },
  '10306': { HP: 179, ATK: 30, DEF: 34, storyLv: 45, power: 7943 },
};
const ch1611 = {
  me: deckAt(1, ['10200']),
  ai: ['10406', '10290', '10383', '10097', '10393', '10306'].map(id => ({ ...clone(cardOf(id)), ...ch1611Boost[id] })),
  win: 'wipe', aiHp: null, bossId: null, heroGuard: 0, first: 'me',
  rules: {
    maxTurns: 20, mustLive: ['10200'],
    revive: [{ id: '10290', become: '10291', delay: 0, storyLevel: 100, battleLevel: 10 }],
  },
};
for (const seed of [4, 7, 8, 12, 21, 100]) for (const policy of ['auto', 'manual']) add('story 16-11', ch1611, seed, policy);
const joinLv = {
  me: deckAt(8, ['10074', '10080', '10445']),
  ai: deckAt(20, ['10051']).map(c => ({ ...c, HP: 800, ATK: 80, DEF: 40 })),
  win: 'wipe', aiHp: null, bossId: null, heroGuard: 0, first: 'me',
  joinAlly: { id: '10311', afterTurn: 1, storyLevel: 100, battleLevel: 10 },
};
for (const seed of [4, 12]) for (const policy of ['auto', 'manual']) add('story joinAlly storyLevel', joinLv, seed, policy);
const floor1 = towerEnemies('normal', 1);
const oyuna = { me: deckAt(50, ['10256', '10118', '10067', '10333', '10045']), ai: floor1.enemies, win: floor1.win, aiHp: floor1.aiHp, bossId: null, heroGuard: 0 };
for (const seed of [3, 8, 21, 50]) add('normal 1 batch', oyuna, seed, 'batch');
add('normal 1 swap then batch', oyuna, 8, 'swap-batch');
assert.throws(() => verifyDirect({ mode: 'tower', target: 'normal:1', seed: 3, snapshot: { cards: [] } }, [{ t: 1, k: 'end' }]), /unsupported battle/);
const handler = rd('../supabase/functions/story-direct-verify-v7/handler.mjs');
assert.match(handler, /verifyDirect\(s, body\.actions\)/);
assert.doesNotMatch(handler, /verifyDirect\([^)]*body\.cards/);

function firstIllegal(spec, seed, log) {
  for (let n = 1; n <= log.length; n++) {
    try { replay(spec, seed, log.slice(0, n)); }
    catch (e) { return { n, action: log[n - 1], message: e.message }; }
  }
  return null;
}
let bad = 0;
for (const row of cases) {
  const same = row.server && row.client.win === row.server.win && row.client.reason === row.server.reason && row.client.turns === row.server.turns;
  if (!same) {
    bad++;
    const badAt = row.error ? firstIllegal(row.spec, row.seed, row.client.log) : null;
    console.log('DIFF', row.label, row.policy, 'seed', row.seed,
      'client', row.client.win, row.client.reason, 't' + row.client.turns, 'base', row.client.aiHp,
      'server', row.server ? [row.server.win, row.server.reason, 't' + row.server.turns] : row.error,
      badAt ? JSON.stringify(badAt) : '');
  }
}
console.log(`parity ${cases.length - bad}/${cases.length}`);
if (bad) process.exit(1);
const floor10 = cases.filter(c => c.label === 'normal 10 boss' && c.policy === 'manual');
assert.ok(floor10.some(c => c.client.win && c.server?.win && c.client.reason === 'ko' && c.server.reason === 'ko'));
assert.ok(cases.some(c => c.label === 'story awaken' && c.client.win && c.server?.win));
assert.ok(cases.filter(c => c.label === 'story awaken storyLevel').every(c => c.client.win === c.server?.win && c.client.reason === c.server?.reason && !c.error));
assert.ok(cases.filter(c => c.label === 'story become storyLevel').every(c => c.client.win === c.server?.win && c.client.reason === c.server?.reason && !c.error));
assert.ok(cases.filter(c => c.label === 'story joinAlly storyLevel').every(c => c.client.win === c.server?.win && c.client.reason === c.server?.reason && !c.error));
assert.ok(cases.filter(c => c.label === 'story 16-11').every(c => c.client.win === c.server?.win && c.client.reason === c.server?.reason && c.client.turns === c.server?.turns && !c.error));
const yj = cardOf('10291');
const expectJina = lvScaled(yj, 100);
assert.equal(storyIntrusionCard({ become: '10291', storyLevel: 100 }).HP, expectJina.HP);
assert.equal(storyIntrusionCard({ become: '10291', storyLevel: 100 }).ATK, expectJina.ATK);
assert.equal(storyIntrusionCard({ id: '10311', storyLevel: 50 }).HP, lvScaled(cardOf('10311'), 50).HP);
assert.notEqual(storyIntrusionCard({ become: '10291', storyLevel: 100 }).HP, yj.HP);
// Real path: the revive rule carries both the dying id and become. Must resolve 10291, not 10290.
const becomeRule = { id: '10290', become: '10291', storyLevel: 100, battleLevel: 10 };
const became = storyIntrusionCard(becomeRule);
assert.equal(String(became.id), '10291');
assert.equal(became.HP, expectJina.HP);
assert.equal(became.ATK, expectJina.ATK);
assert.notEqual(String(became.id), '10290');
assert.notEqual(became.HP, lvScaled(cardOf('10290'), 100).HP);

const batch1 = cases.filter(c => c.label === 'normal 1 batch');
assert.ok(batch1.length === 4 && batch1.every(c => c.client.win === c.server?.win && c.client.reason === c.server?.reason));
assert.ok(batch1.some(c => c.client.log.filter(a => a.k === 'atk').length >= 2));
assert.ok(cases.some(c => c.label === 'normal 1 swap then batch' && c.client.log.some(a => a.k === 'swap') && c.client.win === c.server?.win));

function searchWin(session, summonIds = []) {
  const log = [];
  for (let n = 0; n < 80; n++) {
    let res;
    try { res = verifyDirect(session, log); } catch (e) { return { err: e.message, log }; }
    if (res.win || res.reason !== 'incomplete') return { res, log };
    const t = res.my_turns;
    const opts = [];
    for (const id of summonIds) opts.push({ t, k: 'summon', id });
    for (let i = 0; i < 6; i++) for (let g = 0; g < 6; g++) opts.push({ t, k: 'atk', i, g });
    opts.push({ t, k: 'end' });
    let picked = null;
    for (const opt of opts) { try { verifyDirect(session, log.concat(opt)); picked = opt; break; } catch { /* not legal yet */ } }
    if (!picked) return { res, log, stuck: true };
    log.push(picked);
  }
  return { err: 'search', log };
}
const normalBoss = (target, stage, cards, summonIds = []) => searchWin({
  mode: 'story', target, seed: 4,
  snapshot: { mana: stage.mana ?? null, leader: null, cards, stage },
}, summonIds);
const ch158 = normalBoss('15:8', {
  no: 8, type: 'normal', bossId: '10143', mana: 80,
  enemies: { ids: ['10143', '10144', '10145', '10157', '10158'], boost: {
    '10143': { HP: 90, ATK: 20, DEF: 14 }, '10144': { HP: 90, ATK: 22, DEF: 16 }, '10145': { HP: 108, ATK: 23, DEF: 18 },
    '10157': { HP: 180, ATK: 25, DEF: 20 }, '10158': { HP: 180, ATK: 27, DEF: 27 },
  } },
}, [{ id: '10290', uid: 'a', level: 81 }, { id: '10200', uid: 'b', level: 81 }], ['10290', '10200']);
assert.equal(ch158.res?.win, true, JSON.stringify(ch158.res || ch158.err));
assert.equal(ch158.res.reason, 'wipe');
const bossStage = { no: 8, type: 'boss', bossId: '10143', baseHp: 999999, mana: 80, enemies: { ids: ['10143', '10144', '10145', '10157', '10158'], boost: { '10143': { HP: 90, ATK: 20, DEF: 14 }, '10144': { HP: 90, ATK: 22, DEF: 16 }, '10145': { HP: 108, ATK: 23, DEF: 18 }, '10157': { HP: 180, ATK: 25, DEF: 20 }, '10158': { HP: 180, ATK: 27, DEF: 27 } } } };
let bossReplay;
try {
  bossReplay = verifyDirect({ mode: 'story', target: '15:8', seed: 4, snapshot: { mana: 80, cards: [{ id: '10290', uid: 'a', level: 81 }, { id: '10200', uid: 'b', level: 81 }], stage: bossStage } }, ch158.log);
} catch (e) { bossReplay = { win: false, reason: e.message }; }
assert.notEqual(bossReplay.reason, 'wipe');
for (const [target, bossId, ids, card] of [
  ['3:1', '10157', ['10157', '10156', '10155', '10154', '10153'], '10384'],
  ['4:1', '10157', ['10153', '10154', '10155', '10156', '10157'], '10300'],
  ['6:2', '10146', ['10146', '10153', '10143', '10144', '10145'], '10111'],
]) {
  const fought = normalBoss(target, { type: 'normal', bossId, enemies: { ids } }, [{ id: card, uid: 'p', level: 60 }]);
  assert.equal(fought.res?.reason, 'wipe', `${target} ${JSON.stringify(fought.res || fought.err)}`);
  assert.equal(fought.res.win, true);
}
const missSummon = verifyDirect({
  mode: 'story', target: '16:1', seed: 4,
  snapshot: {
    mana: 200, leader: null,
    cards: [{ id: '10406', uid: 'h', level: 1 }, { id: '10118', uid: 'a', level: 30 }],
    stage: {
      no: 1, type: 'normal', single: true, tutorial: false, mana: 200,
      enemies: { ids: ['10143'], boost: { '10143': { HP: 1, ATK: 1, DEF: 1 } } },
      party: { forced: ['10406'] },
    },
  },
}, [{ t: 1, k: 'end' }, { t: 2, k: 'end' }]);
assert.equal(missSummon.reason, 'mustsummon', JSON.stringify(missSummon));
assert.equal(missSummon.win, false);
const summonedOk = verifyDirect({
  mode: 'story', target: '16:1', seed: 4,
  snapshot: {
    mana: 200, leader: null,
    cards: [{ id: '10406', uid: 'h', level: 1 }, { id: '10118', uid: 'a', level: 30 }],
    stage: {
      no: 1, type: 'normal', single: true, tutorial: false, mana: 200,
      enemies: { ids: ['10143'], boost: { '10143': { HP: 1, ATK: 1, DEF: 1 } } },
      party: { forced: ['10406'] },
    },
  },
}, [{ t: 1, k: 'end' }]);
assert.notEqual(summonedOk.reason, 'mustsummon', 'one end-turn must not fail the 2-turn rule');
console.log('direct parity ok');

const scale = (base, level) => {
  const m = 1 + 0.06 * (level - 1);
  return { HP: Math.round(base.HP * m), ATK: Math.round(base.ATK * m), DEF: Math.round(base.DEF * m) };
};
const byCsv = new Map(parseCSV(rd('../data/cards.csv')).map(c => [String(c.id), c]));
const tower210 = towerEnemies('normal', 210);
const shin = tower210.enemies.find(c => String(c.id) === '10062');
assert.ok(shin, 'tower 210 boss is 김신현');
assert.equal(String(tower210.bossId), '10062');
const expectShin = scale(ENEMY_MR_BASE['10062'], shin.qLevel);
assert.deepEqual({ HP: shin.HP, ATK: shin.ATK, DEF: shin.DEF }, expectShin);
assert.notEqual(shin.ATK, scale(byCsv.get('10062'), shin.qLevel).ATK);
const dark350 = towerEnemies('dark', 350);
const yuri = dark350.enemies.find(c => String(c.id) === '10326');
assert.ok(yuri, 'dark tower 350 boss is awakened 임유리');
assert.deepEqual({ HP: yuri.HP, ATK: yuri.ATK, DEF: yuri.DEF }, scale(ENEMY_MR_BASE['10326'], yuri.qLevel));
let normalMr = null;
for (let floor = 1; floor <= 350 && !normalMr; floor++) {
  if (floor % 10 === 0) continue;
  for (const c of towerEnemies('normal', floor).enemies) if (ENEMY_MR_BASE[String(c.id)]) { normalMr = c; break; }
}
if (normalMr) assert.deepEqual({ HP: normalMr.HP, ATK: normalMr.ATK, DEF: normalMr.DEF }, scale(ENEMY_MR_BASE[String(normalMr.id)], normalMr.qLevel));
const raidBoss = bossCard(3, 'normal', id => byCsv.get(String(id)));
const raidUp = 1 + 0.12 * 2;
assert.equal(raidBoss.ATK, Math.round(ENEMY_MR_BASE['10062'].ATK * 0.8 * raidUp));
assert.equal(raidBoss.DEF, Math.round(ENEMY_MR_BASE['10062'].DEF * 0.2 * raidUp));
assert.notEqual(raidBoss.ATK, Math.round(byCsv.get('10062').ATK * 0.8 * raidUp));
const playerRaid = snapCard({ id: '10062', uid: 'mine', level: 1 }, id => byCsv.get(String(id)), 'raid');
assert.equal(playerRaid.ATK, byCsv.get('10062').ATK);
assert.equal(playerRaid.HP, byCsv.get('10062').HP);
assert.equal(playerRaid.DEF, byCsv.get('10062').DEF);
console.log('enemy MR pre-nerf stats ok');
