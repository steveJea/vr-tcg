// AI vs AI 시뮬레이션: node tools/sim.mjs [games] [heroHP] [damageMult]
import { readFileSync } from 'fs';
import { RULES, calcDamage, canSummon, buildDeck, parseCSV, aiSummonOrder, aiPickTarget, canRecall, aiShouldRecall, makeUnit, resolveAttack, refillMana } from '../js/rules.js';

const pool = parseCSV(readFileSync(new URL('../data/cards.csv', import.meta.url), 'utf8'));
const [games = 500, hp, mult, bonusMana = 0, noRecall = 0, noRewards = 0] = process.argv.slice(2).map(Number);
if (noRewards) { RULES.KILL_MANA_REFUND_RATIO = 0; RULES.LEVEL_MAX = 1; RULES.OVERFLOW_TO_HERO = false; }
let recalls = 0; // bonusMana: 후공 첫 턴 추가 마나(실험용)
if (hp) RULES.HERO_HP = hp;
if (mult) RULES.DAMAGE_MULT = mult;

function player(second) { const deck = buildDeck(pool); return { hp: RULES.HERO_HP, deck, hand: deck.splice(0, RULES.OPENING_HAND + (second ? RULES.SECOND_PLAYER_BONUS_CARDS : 0)), field: [], mana: 0, maxMana: 0 }; }

function play() {
  const P = [player(false), player(true)];
  for (let turn = 0; turn < 400; turn++) {
    const me = P[turn % 2], op = P[(turn + 1) % 2];
    refillMana(me); if (turn === 1) me.mana += bonusMana;
    if (me.deck.length) me.hand.push(me.deck.shift());
    me.field.forEach(u => u.canAttack = true);
    if (!noRecall) for (const u of [...me.field]) if (aiShouldRecall(u, me, op)) {
      me.mana -= canRecall(u, me).cost; me.field.splice(me.field.indexOf(u), 1); me.hand.push(u.base); recalls++;
    }
    for (const c of aiSummonOrder(me.hand)) if (canSummon(c, me, op).ok) {
      me.mana -= c.cost; me.hand.splice(me.hand.indexOf(c), 1); me.field.push(makeUnit(c, 0));
    }
    for (const u of [...me.field]) {
      if (!me.field.includes(u) || !u.canAttack) continue;
      resolveAttack(me, op, u, aiPickTarget(u, op.field));
      if (op.hp <= 0) return { winner: turn % 2, rounds: Math.floor(turn / 2) + 1 };
    }
  }
  return { winner: -1, rounds: 200 };
}

const res = Array.from({ length: games }, play);
const r = res.map(x => x.rounds).sort((a, b) => a - b);
const q = p => r[Math.min(r.length - 1, Math.floor(p * r.length))];
const first = res.filter(x => x.winner === 0).length / games;
console.log(JSON.stringify({ heroHP: RULES.HERO_HP, mult: RULES.DAMAGE_MULT, games, median: q(0.5), p10: q(0.1), p90: q(0.9), bonusCards: RULES.SECOND_PLAYER_BONUS_CARDS, bonusMana, firstWin: +first.toFixed(3), recallsPerGame: +(recalls / games).toFixed(2), unfinished: res.filter(x => x.winner < 0).length }));
