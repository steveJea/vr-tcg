// 스킬 레벨 (E-6) 엔진 테스트: node tools/test_skill_level.mjs
import './seed_rng.mjs';   // 고정 시드 난수 (치명타·회피·속성 패시브 등 확률 결과 고정)
import { readFileSync } from 'fs';
import { setSkillData, initPlayers, placeUnit, refreshAll, setEmitter, useSkill, skillsOf, skillLvOf, skillCd, skillCdAt, skillLvMult, SKILL_LV_MAX } from '../js/skills.js';
import { RULES, makeUnit } from '../js/rules.js';
const rd = p => readFileSync(new URL(p, import.meta.url), 'utf8');
const DB = JSON.parse(rd('../data/skills.json'));
setSkillData(DB, JSON.parse(rd('../data/combos.json')));
const evs = []; setEmitter(e => evs.push(e));
let fail = 0; const ok = (c, m) => { console.log((c ? 'PASS ' : 'FAIL ') + m); if (!c) fail++; };
Object.assign(RULES, { CRIT_RATE: Object.fromEntries(Object.keys(RULES.CRIT_RATE).map(k => [k, 0])), EVADE_ON: false, EL_PASSIVE_ON: false });
const find = name => { for (const [id, l] of Object.entries(DB)) { const i = l.findIndex(s => s.name === name); if (i >= 0) return { id, i, s: l[i] }; } };
const card = (id, extra = {}) => ({ id, name: 'c' + id, gender: 'FEMALE', grade: 'SUPER RARE', class: 'WIND', attribute: 'CHARGE', HP: 5000, ATK: 300, DEF: 40, cost: 30, ...extra });
const foe = n => card('foe' + n, { gender: 'FEMALE', HP: 99999, DEF: 0 });
function run(name, lv, prep) {
  const f = find(name), mk = n => ({ name: n, hp: 1, maxHp: 1, deck: [], hand: [], field: [], mana: 0, maxMana: 0, noBase: true });
  const P = [mk('A'), mk('B')]; initPlayers(P[0], P[1]);
  const u = placeUnit(P[0], card(f.id, lv ? { skillLv: { [f.i + 1]: lv } } : {}), makeUnit);
  const ally = placeUnit(P[0], card('ally'), makeUnit), t = placeUnit(P[1], foe(1), makeUnit);
  refreshAll(P[0]); refreshAll(P[1]); u.level = 99; u.mp = 9999; u.canAttack = true; prep?.({ u, ally, t });
  evs.length = 0; const s = skillsOf(f.id)[f.i]; useSkill(u, s); return { u, ally, t, s, f };
}
// 공식
ok(SKILL_LV_MAX === 10 && Math.abs(skillLvMult(10) - 1.27) < 1e-9 && skillLvMult(1) === 1 && Math.abs(skillLvMult(5) - 1.12) < 1e-9, '배율: Lv1 ×1, Lv5 ×1.12, Lv10 ×1.27');
ok(skillCdAt(4, 4) === 4 && skillCdAt(4, 5) === 3 && skillCdAt(4, 10) === 2 && skillCdAt(2, 10) === 1 && skillCdAt(2, 5) === 1 && skillCdAt(3, 10) === 1 && skillCdAt(0, 10) === 0, '쿨타임: Lv5 −1, Lv10 −2, 최소 1');
// 피해
{ const a = run('절망하라', 0, ({ t }) => { t.hp = t.maxHp; }), b = run('절망하라', 10);
  const da = a.t.maxHp - a.t.hp, db = b.t.maxHp - b.t.hp;
  ok(db > da && Math.abs(db - da * 1.27) <= 6, `스킬 피해 Lv10 ×1.27 (${da} → ${db})`);
  ok(a.u.cd['절망하라'] === a.s.cooldown && b.u.cd['절망하라'] === Math.max(1, a.s.cooldown - 2), `쿨타임 ${a.s.cooldown} → ${b.u.cd['절망하라']}`);
  ok(skillLvOf(b.u, b.s) === 10 && skillLvOf(a.u, a.s) === 1 && skillLvOf(b.t, b.s) === 1, '스킬 레벨 읽기 (skillLv 없는 카드 = Lv1)'); }
// 회복
{ const pre = ({ ally }) => { ally.hp = 100; }, a = run('주님 저희를 구하소서', 0, pre), b = run('주님 저희를 구하소서', 10, pre);
  ok(b.ally.hp - 100 === Math.round((a.ally.hp - 100) * 1.27), `회복 ×1.27 (${a.ally.hp - 100} → ${b.ally.hp - 100})`); }
// 버프 ATK
{ const a = run('Divina tibi poena adveniat', 0), b = run('Divina tibi poena adveniat', 10);
  ok(Math.abs(b.u.st.Divina.atk - a.u.st.Divina.atk * 1.27) < 1e-9 && Math.abs(b.ally.st.Divina.atk - 0.3 * 1.27) < 1e-9 && b.u.st.Divina.t === a.u.st.Divina.t, `버프 ATK ×1.27, 지속 그대로 (${a.u.st.Divina.atk} → ${b.u.st.Divina.atk})`);
  ok(b.u.mp === a.u.mp, 'MP 비용 그대로'); }
// 패시브는 레벨 무시
{ const [id, l] = Object.entries(DB).find(([, l]) => l.some(s => s.mode === 'passive')); const i = l.findIndex(s => s.mode === 'passive');
  const u = makeUnit(card(id, { skillLv: { [i + 1]: 10 } }), 'x'); ok(skillLvOf(u, u.sk[i]) === 1 && skillCd(u, u.sk[i]) === u.sk[i].cooldown, '패시브: 레벨 적용 안 함'); }
// 스킬 밖에서는 배율 없음 (전역 상태 정리)
{ const b = run('절망하라', 10); const h0 = b.ally.hp; b.ally.hp = 100; const m = await import('../js/skills.js'); m.heal(b.ally, 50); ok(b.ally.hp === 150, '스킬 끝난 뒤 회복 배율 원복'); }
console.log(fail ? `${fail} FAIL` : 'ALL PASS'); process.exit(fail ? 1 : 0);
