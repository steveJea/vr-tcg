// 자동 전투(auto-ai.js) vs 기존 적 AI 승률 비교: node tools/sim_auto.mjs [games=200] [floors=...]
// 같은 덱·같은 적·같은 시드로 내 쪽 정책만 바꿔 비교 (적 쪽은 항상 기존 AI). 시련의 탑 실제 층 구성(quest-gen) 사용.
import './seed_rng.mjs';
import { readFileSync } from 'fs';
import { setSkillData, initPlayers, placeUnit, turnStart, turnEnd, useSkill, aiPickSkill, refreshAll, setRng } from '../js/skills.js';
import { parseCSV, aiPickTarget, makeUnit, resolveAttack, refillMana, clearBuff, endTurnXp, setCardPool } from '../js/rules.js';
import { autoNext, noteUsed } from '../js/auto-ai.js';
await import('../js/quest-gen.js');
const G = globalThis.VRQuestGen;
const rd = p => readFileSync(new URL(p, import.meta.url), 'utf8');
const pool = parseCSV(rd('../data/cards.csv')), combos = JSON.parse(rd('../data/combos.json')), cfg = JSON.parse(rd('../data/quest.json'));
setCardPool(pool); setSkillData(JSON.parse(rd('../data/skills.json')), combos);
const games = +(process.argv[2] || 200);
const RATIO = +(process.env.RATIO || 1.0);
const FLOORS = (process.argv[3] || '1,10,30,60,100,146,210,250,300,350').split(',').map(Number);
const ORDER = ['NORMAL', 'RARE', 'HIGH RARE', 'SUPER RARE', 'ULTRA RARE', 'MYTHIC RARE'];
let seed = 1; const rnd = () => { seed = (seed * 16807) % 2147483647; return seed / 2147483647; };
function myDeck(f, ratio) {
  const T = f.power * ratio, gi = ORDER.indexOf(f.grade), out = [];
  for (const g of [ORDER[gi], ORDER[gi - 1], ORDER[gi + 1]].filter(Boolean)) {
    const cands = pool.filter(c => c.grade === g && !out.some(o => o.id === c.id)).map(c => {
      let L = 1, d = Infinity; for (let l = 1; l <= G.capOf(g); l++) { const x = Math.abs(G.powerAt(c, l) - T); if (x < d) { d = x; L = l; } }
      return { c, L, d: d / T };
    }).filter(x => x.d <= 0.12);
    while (out.length < 5 && cands.length) { const x = cands.splice(Math.floor(rnd() * cands.length), 1)[0]; out.push(G.leveled(x.c, x.L)); }
    if (out.length >= 5) break;
  }
  return out;
}
// 게임 난수도 판마다 같은 시드로 (정책만 다르게)
let gs = 1; const grng = () => { gs = (gs * 48271) % 2147483647; return gs / 2147483647; };
function battle(me, ai, auto, gameSeed) {
  gs = gameSeed; setRng(grng); Math.random = grng;
  const mk = name => ({ name, hp: 1, maxHp: 1, deck: [], hand: [], field: [], mana: 0, maxMana: 0, noBase: true });
  const P = [mk('me'), mk('ai')];
  const firstMe = grng() < 0.5;
  initPlayers(P[0], P[1], firstMe ? P[0] : P[1]);
  me.forEach(c => placeUnit(P[0], { ...c }, makeUnit)); ai.forEach(c => placeUnit(P[1], { ...c }, makeUnit));
  refreshAll(P[0]); refreshAll(P[1]);
  const gone = p => !p.field.some(u => u.hp > 0);
  const end = () => gone(P[1]) ? 1 : gone(P[0]) ? 0 : -1;
  for (let t = 0; t < (cfg.maxTurns || 40); t++) {
    const cur = P[(t + (firstMe ? 0 : 1)) % 2], op = cur.foe;
    clearBuff(op); refillMana(cur); cur.field.forEach(u => u.canAttack = true); turnStart(cur);
    let e = end(); if (e >= 0) return { win: e, turns: t + 1 };
    if (auto && cur === P[0]) {
      const turn = { used: new Set(), scopes: new Set() };
      for (let k = 0; k < 40; k++) {
        const a = autoNext(cur, op, turn); if (!a) break;
        if (a.kind === 'skill') { noteUsed(turn, a.s); useSkill(a.u, a.s); a.u.canAttack = false; }
        else { if (a.t) resolveAttack(cur, op, a.u, a.t); a.u.canAttack = false; }
        e = end(); if (e >= 0) return { win: e, turns: t + 1 };
      }
    } else for (const u of [...cur.field]) {
      if (!cur.field.includes(u) || !u.canAttack) continue;
      const sk = aiPickSkill(u);
      if (sk) useSkill(u, sk); else { const tg = aiPickTarget(u, cur, op); if (tg === undefined || tg === null) continue; resolveAttack(cur, op, u, tg); }
      e = end(); if (e >= 0) return { win: e, turns: t + 1 };
    }
    endTurnXp(cur); turnEnd(cur);
    e = end(); if (e >= 0) return { win: e, turns: t + 1 };
  }
  return { win: 0, turns: cfg.maxTurns || 40 };
}
const tot = { base: 0, auto: 0, n: 0 };
for (const n of FLOORS) {
  const f = cfg.floors[n - 1], g = G.generate(cfg, f, pool, combos);
  let wb = 0, wa = 0, tb = 0, ta = 0, k = 0;
  for (let i = 0; i < games; i++) {
    const d = myDeck(f, RATIO); if (d.length < 5) continue; k++;
    const sd = 1000 + n * 7919 + i;
    const b = battle(d, g.enemies, false, sd), a = battle(d, g.enemies, true, sd);
    wb += b.win; wa += a.win; tb += b.turns; ta += a.turns;
  }
  if (!k) continue;
  tot.base += wb; tot.auto += wa; tot.n += k;
  console.log(`층 ${String(n).padStart(3)} ${f.grade.padEnd(11)} 기존AI ${(wb / k * 100).toFixed(1).padStart(5)}%  자동 ${(wa / k * 100).toFixed(1).padStart(5)}%  (평균 턴 ${(tb / k).toFixed(1)} → ${(ta / k).toFixed(1)}, n=${k})`);
}
console.log(`합계 기존AI ${(tot.base / tot.n * 100).toFixed(1)}%  자동 ${(tot.auto / tot.n * 100).toFixed(1)}%  (n=${tot.n})`);
