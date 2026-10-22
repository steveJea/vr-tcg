// 속성 1:1 밸런스 시뮬: node tools/sim_elements.mjs [games=1000] [grade=SUPER RARE]
// quest_sim 과 같은 전투 루프(양측 AI, 5장 필드 시작, 진영 없음, 전멸 = 승리, 40턴 초과 = 무승부 0.5).
// 양측 카드 능력치·등급·성별 동일, 스킬 없음 → 차이는 속성(상성·회피·패시브)뿐.
// A: 실제 규칙(상성 포함) 라운드로빈  B: 상성 끄고 패시브만, 기준(패시브 없음·회피 4%) 상대
import { readFileSync } from 'fs';
import { setSkillData, initPlayers, placeUnit, turnStart, turnEnd, useSkill, aiPickSkill, refreshAll } from '../js/skills.js';
import { RULES, aiPickTarget, makeUnit, resolveAttack, refillMana, clearBuff, endTurnXp } from '../js/rules.js';
const rd = p => readFileSync(new URL(p, import.meta.url), 'utf8');
setSkillData(JSON.parse(rd('../data/skills.json')), JSON.parse(rd('../data/combos.json')));
const games = +(process.argv[2] || 1000), grade = process.argv[3] || 'SUPER RARE';
const EL = ['FIRE', 'WIND', 'ICE', 'DARK', 'LIGHT', 'ABYSS'];
const card = (cls, i) => ({ id: `sim${cls}${i}`, name: `${cls}${i}`, gender: 'MALE', grade, class: cls, attribute: 'CHARGE', HP: 420, ATK: 72, DEF: 56, cost: 30, PHY: 60, MEN: 60, MOR: 60 });
function battle(a, b, firstA) {
  const mk = name => ({ name, hp: 1, maxHp: 1, deck: [], hand: [], field: [], mana: 0, maxMana: 0, noBase: true });
  const P = [mk('A'), mk('B')]; initPlayers(P[0], P[1]);
  a.forEach(c => placeUnit(P[0], { ...c }, makeUnit)); b.forEach(c => placeUnit(P[1], { ...c }, makeUnit));
  refreshAll(P[0]); refreshAll(P[1]);
  const gone = p => !p.field.some(u => u.hp > 0);
  for (let t = 0; t < 40; t++) {
    const cur = P[(t + (firstA ? 0 : 1)) % 2], op = cur.foe;
    clearBuff(op); refillMana(cur); cur.field.forEach(u => u.canAttack = true); turnStart(cur);
    if (gone(P[1])) return 1; if (gone(P[0])) return 0;
    for (const u of [...cur.field]) {
      if (!cur.field.includes(u) || !u.canAttack) continue;
      const sk = aiPickSkill(u); if (sk) useSkill(u, sk); else { const tg = aiPickTarget(u, cur, op); if (tg == null) continue; resolveAttack(cur, op, u, tg); }
      if (gone(P[1])) return 1; if (gone(P[0])) return 0;
    }
    endTurnXp(cur); turnEnd(cur);
    if (gone(P[1])) return 1; if (gone(P[0])) return 0;
  }
  return 0.5;
}
const rate = (x, y) => { let w = 0; for (let i = 0; i < games; i++) w += battle([0,1,2,3,4].map(k => card(x, k)), [0,1,2,3,4].map(k => card(y, k)), i % 2 === 0); return w / games; };
const pct = v => (v * 100).toFixed(1).padStart(5);
console.log(`games=${games} grade=${grade}`);
console.log('A) 실제 규칙 (행 = 공격측 속성 승률)\n       ' + EL.map(e => e.padStart(6)).join(' ') + '   평균(자기 제외)');
for (const x of EL) { const r = EL.map(y => rate(x, y)); const o = r.filter((_, i) => EL[i] !== x); console.log(x.padEnd(6), r.map(v => ' ' + pct(v)).join(' '), '  ', pct(o.reduce((s, v) => s + v, 0) / o.length)); }
RULES.ELEM_MULT_ON = false;
console.log('B) 상성 끔 · 패시브만 vs 기준(ABYSS = 패시브 없음, 회피 4%)');
for (const x of EL.slice(0, 5)) { const v = rate(x, 'ABYSS'); console.log(x.padEnd(6), pct(v), Math.abs(v - 0.5) > 0.03 ? '⚠ 50±3% 밖' : 'OK'); }
RULES.EL_PASSIVE_ON = false; RULES.EVADE_BASE = {};
console.log('C) 대조군: 패시브·상성·속성 회피 모두 끔 (치명타만)');
for (const x of ['FIRE']) console.log(x.padEnd(6), pct(rate(x, 'ABYSS')));
