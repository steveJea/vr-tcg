// Client story/tower battle vs the direct replay. The client loop follows js/game.js
// (field start, seeded RNG, AUTO or manual clicks). The replay must finish the same way.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runDirect, verifyDirect, towerEnemies, rngOf as engineRngOf } from '../supabase/functions/story-direct-verify-v7/engine.mjs';
import { rngOf } from '../js/direct-rng.js';
import { leaderSkill } from '../js/sweep-core.js';
import { autoNext, noteUsed } from '../js/auto-ai.js';
import {
  RULES, canSummon, makeUnit, resolveAttack, refillMana, endTurnXp, canTarget, doAction, levelUpOnce,
  aiSummonOrder, aiPickSacrifice, aiWantAccel, aiWantFieldHeal, aiWantBuff, aiWantHeal, aiWantShuffle,
  sacrifice, aiPickTarget, autoTarget, attackTargets, clearBuff, aiPickItem, equip, swapField, setCardPool, parseCSV,
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
  const state = { me, ai, turn: first, first, turnNo: 0, totalTurns: 0, myTurns: 0, over: false, win: null, reason: null };
  initPlayers(me, ai, first === 'ai' ? ai : me);
  const bossIds = [spec.bossId].filter(x => x != null).map(String);
  for (const who of ['me', 'ai']) {
    const p = state[who];
    const nb = p.deck.slice(0, RULES.FIELD_MAX + bossIds.length).filter(c => who === 'ai' && bossIds.includes(String(c.id))).length;
    for (const c of p.deck.splice(0, RULES.FIELD_MAX + (who === 'ai' ? nb : 0))) {
      const u = placeUnit(p, c, makeUnit);
      if (who === 'me' && spec.leaderUid && c.uid === spec.leaderUid) { u.isLeader = true; p.leaderSkill = { ...leaderSkill(c), uid: c.uid, deathPenalty: 0.3 }; }
      if (who === 'ai' && spec.bossId != null && String(c.id) === String(spec.bossId) && !p.field.some(x => x.undying)) { u.undying = true; u.boss = true; }
    }
    p.deck = [];
  }
  refreshAll(me); refreshAll(ai);
  const log = [];
  const gone = p => !p.field.length && !p.hand.length && !p.deck.length;
  const done = (win, reason) => { if (!state.over) { state.over = true; state.win = win; state.reason = reason; } return true; };
  function awaken() {
    const A = spec.awaken;
    if (!A || state.awakened || me.field.some(u => String(u.card.id) === String(A.on))) return;
    const card = A.card || pool.find(c => String(c.id) === String(A.id));
    if (!card) return;
    state.awakened = true;
    const u = placeUnit(me, { ...card }, makeUnit, true);
    while (u.level < Math.min(A.battleLevel || 1, RULES.LEVEL_MAX)) levelUpOnce(u);
    u.hp = u.maxHp; u.mp = u.maxMp; u.canAttack = true;
  }
  function checkEnd() {
    if (state.over) return true;
    if (ai.hp <= 0 || me.hp <= 0) return done(ai.hp <= 0, 'ko');
    awaken();
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
    if (who === 'me') state.myTurns++;
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
const batch1 = cases.filter(c => c.label === 'normal 1 batch');
assert.ok(batch1.length === 4 && batch1.every(c => c.client.win === c.server?.win && c.client.reason === c.server?.reason));
assert.ok(batch1.some(c => c.client.log.filter(a => a.k === 'atk').length >= 2));
assert.ok(cases.some(c => c.label === 'normal 1 swap then batch' && c.client.log.some(a => a.k === 'swap') && c.client.win === c.server?.win));
console.log('direct parity ok');
