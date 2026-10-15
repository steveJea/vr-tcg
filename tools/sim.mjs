// AI vs AI 시뮬레이션: node tools/sim.mjs [games] [heroHP] [damageMult]
import { readFileSync } from 'fs';
import { setSkillData, initPlayers, placeUnit, turnStart, turnEnd, useSkill, aiPickSkill, refreshAll, stats as skillStats } from '../js/skills.js';
import { RULES, calcDamage, canSummon, buildDeck, parseCSV, aiSummonOrder, aiPickTarget, canRecall, aiShouldRecall, makeUnit, resolveAttack, refillMana, doAction, clearBuff, aiWantShuffle, aiWantBuff, aiWantHeal, aiWantFieldHeal, aiPickItem, equip, endTurnXp, setCardPool, sacrifice, aiPickSacrifice, aiWantAccel, judgeTimeout } from '../js/rules.js';

const pool = parseCSV(readFileSync(new URL('../data/cards.csv', import.meta.url), 'utf8'));
const SKILLS = JSON.parse(readFileSync(new URL('../data/skills.json', import.meta.url), 'utf8'));
setCardPool(pool);
setSkillData(SKILLS, JSON.parse(readFileSync(new URL('../data/combos.json', import.meta.url), 'utf8')));
// SIM_FORCE=카드id → 0번 플레이어(선후공 무작위) 덱에 그 카드를 강제로 넣음 (카드별 승률 측정)
const FORCE = process.env.SIM_FORCE ? pool.find(c => String(c.id) === process.env.SIM_FORCE) : null;
const cardStat = {}; // id → { games, wins }
const [games = 500, hp, mult, bonusMana = 0, noRecall = 0, noRewards = 0, noActions = 0] = process.argv.slice(2).map(Number);
if (process.env.SIM_RULES) Object.assign(RULES, JSON.parse(process.env.SIM_RULES)); // 예: SIM_RULES='{"HEAL_AMOUNT":200}'
if (noRewards) { RULES.KILL_MANA_REFUND_RATIO = 0; RULES.LEVEL_MAX = 1; RULES.OVERFLOW_TO_HERO = false; }
let recalls = 0, forcedWins = 0; const acts = { shuffle: 0, heal: 0, buff: 0, fieldheal: 0, item: 0, sacrifice: 0, accel: 0 }; let gamesWith = { shuffle: 0, heal: 0, buff: 0, fieldheal: 0, item: 0, sacrifice: 0, accel: 0 }; const reasons = { ko: 0, hp: 0, cards: 0, draw: 0 }; let manaSum = 0, manaN = 0; const maxLv = []; let lvl10 = 0, gamesLv10 = 0; // bonusMana: 후공 첫 턴 추가 마나(실험용)
if (hp) RULES.HERO_HP = hp;
if (mult) RULES.DAMAGE_MULT = mult;

function player(second, force) { const deck = buildDeck(pool); if (force) { deck.splice(deck.findIndex(c => c.grade === 'NORMAL'), 1); deck.splice(Math.floor(Math.random() * deck.length), 0, force); } const d0 = [...deck]; return { d0, hp: RULES.HERO_HP, deck, hand: deck.splice(0, RULES.OPENING_HAND + (second ? RULES.SECOND_PLAYER_BONUS_CARDS : 0)), field: [], mana: 0, maxMana: 0 }; }

function play() {
  const forcedFirst = Math.random() < 0.5;
  const P = [player(false, FORCE && forcedFirst ? FORCE : null), player(true, FORCE && !forcedFirst ? FORCE : null)];
  P[0].name = 'A'; P[1].name = 'B';
  initPlayers(P[0], P[1]);
  const over = () => P[0].hp <= 0 || P[1].hp <= 0;
  const result = (turn, w = P[1].hp <= 0 ? 0 : 1, reason = 'ko') => { reasons[reason]++; if (w >= 0) for (let i = 0; i < 2; i++) for (const id of new Set(P[i].d0.map(c => c.id))) { const st = cardStat[id] ||= { games: 0, wins: 0 }; st.games++; if (w === i) st.wins++; } if (FORCE) forcedWins += (forcedFirst ? 0 : 1) === w ? 1 : 0; return done({ winner: w, rounds: Math.floor(turn / 2) + 1, turns: turn + 1 }); };
  const used = { shuffle: 0, heal: 0, buff: 0, fieldheal: 0, item: 0, sacrifice: 0, accel: 0 };
  let gotLv10 = 0;
  const done = r => { if (gotLv10) gamesLv10++; for (const k in used) { acts[k] += used[k]; if (used[k]) gamesWith[k]++; } return r; };
  for (let turn = 0; turn < RULES.MAX_TURNS; turn++) {
    const me = P[turn % 2], op = P[(turn + 1) % 2];
    clearBuff(op); refillMana(me); if (turn === 1) me.mana += bonusMana;
    if (me.deck.length) me.hand.push(me.deck.shift());
    me.field.forEach(u => u.canAttack = true);
    turnStart(me);
    if (over()) return result(turn);
    if (!noRecall) for (const u of [...me.field]) if (aiShouldRecall(u, me, op)) {
      me.mana -= canRecall(u, me).cost; me.field.splice(me.field.indexOf(u), 1); me.hand.push(u.base); recalls++; refreshAll(me);
    }
    manaSum += me.mana; manaN++;
    if (!noActions && aiWantShuffle(me, op)) { doAction('shuffle', me); used.shuffle++; }
    if (!noActions && aiWantAccel(me, true)) { doAction('accel', me); used.accel++; }
    if (!noActions) { const v = aiPickSacrifice(me, op); if (v) { sacrifice(v, me); used.sacrifice++; } }
    for (const c of aiSummonOrder(me.hand)) if (canSummon(c, me, op).ok) {
      me.mana -= c.cost; me.hand.splice(me.hand.indexOf(c), 1); placeUnit(me, c, makeUnit); if (over()) return result(turn);
    }
    if (!noActions) { let it; while ((it = aiPickItem(me, op))) { equip(it[0], it[1], me); used.item++; } }
    if (!noActions && aiWantAccel(me)) { doAction('accel', me); used.accel++; }
    if (!noActions && aiWantFieldHeal(me)) { doAction('fieldheal', me); used.fieldheal++; }
    if (!noActions && aiWantBuff(me)) { doAction('buff', me); used.buff++; }
    for (const u of [...me.field]) {
      if (!me.field.includes(u) || !u.canAttack) continue;
      const sk = aiPickSkill(u);
      if (sk) useSkill(u, sk);
      else {
        const t = aiPickTarget(u, me, op);
        if (t === undefined) continue;
        resolveAttack(me, op, u, t);
      }
      for (const x of [...me.field, ...op.field]) { if (x.level >= RULES.LEVEL_MAX && !x.hero10) { x.hero10 = 1; lvl10++; gotLv10 = 1; } }
      if (over()) return result(turn);
    }
    if (!noActions && aiWantHeal(me)) { doAction('heal', me); used.heal++; }
    endTurnXp(me); turnEnd(me);
    if (over()) return result(turn);
    for (const x of me.field) if (x.level >= RULES.LEVEL_MAX && !x.hero10) { x.hero10 = 1; lvl10++; gotLv10 = 1; }
  }
  const j = judgeTimeout(P[0], P[1]);
  return result(RULES.MAX_TURNS - 1, j.winner ? P.indexOf(j.winner) : -1, j.reason);
}

const res = Array.from({ length: games }, play);
const r = res.map(x => x.rounds).sort((a, b) => a - b);
const q = p => r[Math.min(r.length - 1, Math.floor(p * r.length))];
const first = res.filter(x => x.winner === 0).length / games;
console.log(JSON.stringify({ heroHP: RULES.HERO_HP, mult: RULES.DAMAGE_MULT, games, median: q(0.5), p10: q(0.1), p90: q(0.9), bonusCards: RULES.SECOND_PLAYER_BONUS_CARDS, bonusMana, firstWin: +first.toFixed(3), recallsPerGame: +(recalls / games).toFixed(2), actionsPerGame: Object.fromEntries(Object.entries(acts).map(([k, v]) => [k, +(v / games).toFixed(2)])), gamesUsing: Object.fromEntries(Object.entries(gamesWith).map(([k, v]) => [k, +(v / games).toFixed(2)])), gamesWithLv10: +(gamesLv10 / games).toFixed(3), lv10PerGame: +(lvl10 / games).toFixed(3), draws: +(res.filter(x => x.winner < 0).length / games).toFixed(3), avgTurns: +(res.reduce((a, x) => a + x.turns, 0) / games).toFixed(1), reasons: Object.fromEntries(Object.entries(reasons).map(([k, v]) => [k, +(v / games).toFixed(3)])), avgManaAtTurnStart: +(manaSum / manaN).toFixed(1) }));

// ---- 스킬 / 카드 통계 ----
if (process.env.SIM_FORCE) console.log(JSON.stringify({ force: FORCE?.name, forcedWinRate: +(forcedWins / games).toFixed(3) }));
if (process.env.SIM_DETAIL) {
  const names = Object.fromEntries(pool.map(c => [c.id, c.name]));
  const allSkills = Object.values(SKILLS).flat().map(s => s.name);
  console.log('skillUsage', JSON.stringify(skillStats.counts));
  console.log('neverTriggered', JSON.stringify(allSkills.filter(n => !skillStats.counts[n])));
  const rows = Object.entries(cardStat).filter(([, v]) => v.games >= 20).map(([id, v]) => [names[id], v.games, +(v.wins / v.games).toFixed(3), !!SKILLS[id]]);
  rows.sort((a, b) => b[2] - a[2]);
  console.log('topCards', JSON.stringify(rows.slice(0, 12)));
  console.log('skillCards', JSON.stringify(rows.filter(r => r[3])));
}
