// AI vs AI 시뮬레이션: node tools/sim.mjs [games] [heroHP] [damageMult]
import { readFileSync } from 'fs';
import { RULES, calcDamage, canSummon, buildDeck, parseCSV, aiSummonOrder, aiPickTarget } from '../js/rules.js';

const pool = parseCSV(readFileSync(new URL('../data/cards.csv', import.meta.url), 'utf8'));
const [games = 500, hp, mult] = process.argv.slice(2).map(Number);
if (hp) RULES.HERO_HP = hp;
if (mult) RULES.DAMAGE_MULT = mult;

function player() { const deck = buildDeck(pool); return { hp: RULES.HERO_HP, deck, hand: deck.splice(0, RULES.OPENING_HAND), field: [], mana: 0, maxMana: 0 }; }

function play() {
  const P = [player(), player()];
  for (let turn = 0; turn < 400; turn++) {
    const me = P[turn % 2], op = P[(turn + 1) % 2];
    me.maxMana = Math.min(RULES.MANA_MAX, me.maxMana + RULES.MANA_PER_TURN); me.mana = me.maxMana;
    if (me.deck.length) me.hand.push(me.deck.shift());
    me.field.forEach(u => u.canAttack = true);
    for (const c of aiSummonOrder(me.hand)) if (canSummon(c, me, op).ok) {
      me.mana -= c.cost; me.hand.splice(me.hand.indexOf(c), 1); me.field.push({ card: c, hp: c.HP, canAttack: false });
    }
    for (const u of [...me.field]) {
      if (!me.field.includes(u) || !u.canAttack) continue;
      u.canAttack = false;
      const t = aiPickTarget(u, op.field);
      if (!t) { op.hp -= calcDamage(u.card, null); if (op.hp <= 0) return { winner: turn % 2, rounds: Math.floor(turn / 2) + 1 }; }
      else {
        t.hp -= calcDamage(u.card, t.card); u.hp -= calcDamage(t.card, u.card);
        if (t.hp <= 0) op.field.splice(op.field.indexOf(t), 1);
        if (u.hp <= 0) me.field.splice(me.field.indexOf(u), 1);
      }
    }
  }
  return { winner: -1, rounds: 200 };
}

const res = Array.from({ length: games }, play);
const r = res.map(x => x.rounds).sort((a, b) => a - b);
const q = p => r[Math.min(r.length - 1, Math.floor(p * r.length))];
const first = res.filter(x => x.winner === 0).length / games;
console.log(JSON.stringify({ heroHP: RULES.HERO_HP, mult: RULES.DAMAGE_MULT, games, median: q(0.5), p10: q(0.1), p90: q(0.9), firstWin: +first.toFixed(3), unfinished: res.filter(x => x.winner < 0).length }));
