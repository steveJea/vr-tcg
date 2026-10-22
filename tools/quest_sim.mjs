// 퀘스트(시련의 탑) 승률 곡선 시뮬: node tools/quest_sim.mjs [games=200] [floors=1,10,...]
// 양측 AI. 실제 퀘스트 규칙: 양측 5장 전부 필드 시작, 손패·드로우 없음, 진영 없음(양측 noBase), 적 전멸 = 승리, 40턴 초과 = 패배
// 내 덱 모델: 층 리더 등급 카드 5장(같은 등급 우선, 모자라면 한 단계 아래), 각 카드 전투력 ≈ 목표 × ratio (레벨로 맞춤). ratio 0.8 / 1.0 / 1.2
import { readFileSync } from 'fs';
import { setSkillData, initPlayers, placeUnit, turnStart, turnEnd, useSkill, aiPickSkill, refreshAll } from '../js/skills.js';
import { RULES, parseCSV, aiPickTarget, makeUnit, resolveAttack, refillMana, clearBuff, endTurnXp, setCardPool } from '../js/rules.js';
await import('../js/quest-gen.js');
const G = globalThis.VRQuestGen;
const rd = p => readFileSync(new URL(p, import.meta.url), 'utf8');
const pool = parseCSV(rd('../data/cards.csv')), combos = JSON.parse(rd('../data/combos.json')), cfg = JSON.parse(rd('../data/quest.json'));
setCardPool(pool); setSkillData(JSON.parse(rd('../data/skills.json')), combos);
const games = +(process.argv[2] || 200);
const FLOORS = (process.argv[3] || '1,10,30,59,60,79,80,100,130,145,146,180,209,210,221,222,250,289,299,300,320,330,349,350').split(',').map(Number);
const RATIOS = (process.env.Q_RATIOS || '0.8,1.0,1.2').split(',').map(Number);
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
function battle(me, ai) {
  const mk = (name, cards) => ({ name, hp: 1, maxHp: 1, deck: [], hand: [], field: [], mana: 0, maxMana: 0, noBase: true });
  const P = [mk('me'), mk('ai')];
  initPlayers(P[0], P[1]);
  me.forEach(c => placeUnit(P[0], { ...c }, makeUnit)); ai.forEach(c => placeUnit(P[1], { ...c }, makeUnit));
  refreshAll(P[0]); refreshAll(P[1]);
  const gone = p => !p.field.some(u => u.hp > 0);
  const firstMe = rnd() < 0.5;
  for (let t = 0; t < (cfg.maxTurns || 40); t++) {
    const cur = P[(t + (firstMe ? 0 : 1)) % 2], op = cur.foe;
    clearBuff(op); refillMana(cur);
    cur.field.forEach(u => u.canAttack = true);
    turnStart(cur);
    if (gone(P[1])) return 1; if (gone(P[0])) return 0;
    for (const u of [...cur.field]) {
      if (!cur.field.includes(u) || !u.canAttack) continue;
      const sk = aiPickSkill(u);
      if (sk) useSkill(u, sk); else { const tg = aiPickTarget(u, cur, op); if (tg === undefined || tg === null) continue; resolveAttack(cur, op, u, tg); }
      if (gone(P[1])) return 1; if (gone(P[0])) return 0;
    }
    endTurnXp(cur); turnEnd(cur);
    if (gone(P[1])) return 1; if (gone(P[0])) return 0;
  }
  return 0;   // 40턴 초과 = 패배
}
const rows = [];
for (const n of FLOORS) {
  const f = cfg.floors[n - 1], g = G.generate(cfg, f, pool, combos);
  const row = { floor: n, grade: f.grade, target: f.power, leader: g.leader.power, combo: g.combo || '' };
  for (const r of RATIOS) { let w = 0, k = 0; for (let i = 0; i < games; i++) { const d = myDeck(f, r); if (d.length < 5) continue; k++; w += battle(d, g.enemies); } row['x' + r] = k ? +(w / k).toFixed(2) : null; }
  rows.push(row); console.log(JSON.stringify(row));
}
