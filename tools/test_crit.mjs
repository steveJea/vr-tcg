// 치명타·속성 패시브 단위 테스트: node tools/test_crit.mjs
import { readFileSync } from 'fs';
import { setSkillData, initPlayers, placeUnit, refreshAll, setEmitter } from '../js/skills.js';
import { RULES, makeUnit, resolveAttack, calcDamage } from '../js/rules.js';
const rd = p => readFileSync(new URL(p, import.meta.url), 'utf8');
setSkillData(JSON.parse(rd('../data/skills.json')), JSON.parse(rd('../data/combos.json')));
const evs = []; setEmitter(e => evs.push(e));
let fail = 0; const ok = (c, m) => { console.log((c ? 'PASS ' : 'FAIL ') + m); if (!c) fail++; };
const card = (cls, grade = 'SUPER RARE', id = 'x') => ({ id: 't' + cls + id, name: cls + id, gender: 'MALE', grade, class: cls, attribute: 'CHARGE', HP: 5000, ATK: 100, DEF: 40, cost: 30 });
const base = { ...RULES, CRIT_RATE: { ...RULES.CRIT_RATE }, EVADE_BASE: { ...RULES.EVADE_BASE } };
function setup(a, b, over = {}) {
  Object.assign(RULES, base, { CRIT_RATE: Object.fromEntries(Object.keys(base.CRIT_RATE).map(k => [k, 0])), EVADE_ON: false, FIRE_BURN_P: 0, ICE_GUARD_P: 0, DARK_DRAIN_P: 0, DARK_COUNTER_P: 0, LIGHT_CLEANSE_P: 0, LIGHT_NULL_P: 0 }, over);
  const mk = n => ({ name: n, hp: 1, maxHp: 1, deck: [], hand: [], field: [], mana: 0, maxMana: 0, noBase: true });
  const P = [mk('A'), mk('B')]; initPlayers(P[0], P[1]);
  const u = placeUnit(P[0], a, makeUnit), t = placeUnit(P[1], b, makeUnit); refreshAll(P[0]); refreshAll(P[1]); evs.length = 0;
  u.canAttack = true; return { P, u, t, hit: () => resolveAttack(P[0], P[1], u, t).find(e => e.type === 'hit') };
}
ok(JSON.stringify(base.CRIT_RATE) === JSON.stringify({ 'NORMAL': 0.03, 'RARE': 0.04, 'HIGH RARE': 0.05, 'SUPER RARE': 0.06, 'ULTRA RARE': 0.08, 'MYTHIC RARE': 0.10 }) && base.CRIT_MULT === 1.5, '등급별 치명 확률·150%');
{ const s = setup(card('WIND'), card('WIND', 'SUPER RARE', 'b')); const n = s.hit(); const s2 = setup(card('WIND'), card('WIND', 'SUPER RARE', 'b'), { CRIT_RATE: { 'SUPER RARE': 1 } }); const c = s2.hit();
  ok(c.d1 === Math.round(n.d1 * 1.5) && evs.some(e => e.type === 'crit'), `기본 공격 치명 ×1.5 (${n.d1} → ${c.d1})`); ok(c.d2 === Math.round(n.d2 * 1.5), `반격 치명 ×1.5 (${n.d2} → ${c.d2})`); }
{ const s = setup(card('FIRE'), card('ICE', 'SUPER RARE', 'b'), { FIRE_BURN_P: 1 }); s.hit(); ok(s.t.st.burn?.t >= 2, '불: 적중 시 화상 2턴');
  const base2 = setup(card('ICE', 'SUPER RARE', 'c'), card('WIND', 'SUPER RARE', 'd')); const d = base2.hit().d1; const b = setup(card('ICE', 'SUPER RARE', 'c'), card('WIND', 'SUPER RARE', 'd')); b.u.st.burn = { kind: 'burn', t: 2 }; ok(b.hit().d1 === Math.round(d * 0.95), '화상: 주는 피해 -5%');
  b.u.st.bleed = { kind: 'bleed', t: 2 }; ok(b.u.st.burn && b.u.st.bleed, '화상·출혈 공존'); }
{ const n = setup(card('WIND'), card('ICE', 'SUPER RARE', 'b')).hit(); const s = setup(card('WIND'), card('ICE', 'SUPER RARE', 'b'), { ICE_GUARD_P: 1 }); const h = s.hit();
  ok(h.d1 === Math.round(n.d1 * 0.5) && h.d2 > 0, `얼음: 피격 절반 (${n.d1} → ${h.d1}), 반격 유지`); }
{ const s = setup(card('DARK'), card('DARK', 'SUPER RARE', 'b'), { DARK_DRAIN_P: 1 }); s.u.hp = 1000; const h = s.hit(); ok(evs.some(e => e.type === 'heal' && e.unit === s.u && e.amt === Math.round(h.d1 * 0.2)), '어둠: 흡혈 20%'); }
{ const n = setup(card('WIND'), card('DARK', 'SUPER RARE', 'b')).hit(); const h = setup(card('WIND'), card('DARK', 'SUPER RARE', 'b'), { DARK_COUNTER_P: 1 }).hit(); ok(h.d2 === Math.round(n.d2 * 2), `어둠: 반격 2배 (${n.d2} → ${h.d2})`); }
{ const s = setup(card('LIGHT'), card('WIND', 'SUPER RARE', 'b'), { LIGHT_NULL_P: 1 }); ok(s.hit().d2 === 0, '빛: 받는 반격 무효');
  const c = setup(card('LIGHT'), card('WIND', 'SUPER RARE', 'b'), { LIGHT_CLEANSE_P: 1 }); c.u.st.burn = { kind: 'burn', t: 2 }; c.hit(); ok(!c.u.st.burn, '빛: 디버프 1개 해제'); }
{ const s = setup(card('WIND'), card('WIND', 'SUPER RARE', 'b'), { EVADE_ON: true }); ok(RULES.EVADE_BASE.WIND === 0.07, '바람 회피 7%'); }
Object.assign(RULES, base);
console.log(fail ? `${fail} FAIL` : 'ALL PASS'); process.exit(fail ? 1 : 0);
