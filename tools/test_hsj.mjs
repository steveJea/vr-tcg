import './seed_rng.mjs';   // 고정 시드 난수 (치명타·회피·속성 패시브 등 확률 결과 고정)
import fs from 'fs';
import { setCardPool, parseCSV, makeUnit, resolveAttack, calcDamage, RULES } from '../js/rules.js';
// 스킬 수치 검증용: 성별 피해(7-1)·속성 회피(7-2)는 끄고 확인 (해당 규칙은 test_batchB.mjs에서 검증)
RULES.GENDER_ON = false; RULES.EVADE_ON = false;
import { setSkillData, initPlayers, placeUnit, skillsOf, ACTIVE, useSkill, skillState, turnStart, turnEnd, setRng, TURN, checkDeath, refreshAll, setEmitter, onLevelChange, damageUnit, aiPickSkill } from '../js/skills.js';
if (process.env.DBG) setEmitter(e => console.log('  ev', e.type, e.unit?.card?.name || '', e.text || e.name || e.dmg || ''));
setSkillData(JSON.parse(fs.readFileSync('data/skills.json')), JSON.parse(fs.readFileSync('data/combos.json')));
const cards = parseCSV(fs.readFileSync('data/cards.csv', 'utf8')); const C = id => cards.find(c => String(c.id) === id);
const mk = (c, uid) => { const u = makeUnit(c, uid); u.sk = skillsOf(c.id); return u; };
setCardPool(cards);
let fails = 0; const ok = (n, c, extra = '') => { console.log((c ? 'PASS ' : 'FAIL ') + n + (extra ? ' — ' + extra : '')); if (!c) { fails++; process.exitCode = 1; } };
const sides = (aIds, bIds, lv = 10) => {
  const a = { name: 'A', field: [], hand: [], deck: [], mana: 99, hp: 3000, maxHp: 3000, turnsTaken: 9 }, b = { name: 'B', field: [], hand: [], deck: [], mana: 99, hp: 3000, maxHp: 3000, turnsTaken: 9 };
  initPlayers(a, b); TURN.p = a;
  const A = aIds.map(id => placeUnit(a, C(id), mk)), B = bIds.map(id => placeUnit(b, C(id), mk));
  [...A, ...B].forEach(u => { u.level = lv; u.mp = u.maxMp; u.canAttack = true; onLevelChange(u); }); refreshAll(a);
  return { a, b, A, B };
};
const sk = (u, name) => u.sk.find(s => s.name === name);
const cast = (u, name) => { u.canAttack = true; u.mp = u.maxMp; u.cd = {}; return useSkill(u, sk(u, name)); };
const H = '1100000001', N = ['1000100009', '1000100010', '2000100003'];
ok('하승진 카드 (UR·FIRE·DISTURB·72933·50)', C(H)?.name === '하승진' && C(H).grade === 'ULTRA RARE' && C(H).power === 72933 && C(H).cost === 50 && skillsOf(H).length === 3);
{ const { A, B } = sides([H], N); const before = B.map(t => t.mp); const r = cast(A[0], '처음부터...다시.');
  ok('처음부터...다시.: 적 MP 50% 제거', r.ok && B.every((t, i) => t.mp === before[i] - Math.round(before[i] * 0.5)), B.map(t => t.mp).join('/')); }
{ const { A, B } = sides([H], N); B.forEach(t => t.cd = {}); const r = cast(A[0], '그게...최선인가?');
  ok('그게...최선인가?: 적 액티브 쿨타임 +2', r.ok && B.every(t => t.sk.filter(s => s.mode === 'active').every(s => t.cd[s.name] === 2)), JSON.stringify(B.map(t => t.cd))); }
{ const { A, B } = sides([H], N); B[0].mp = 5; B[1].mp = 50; B[2].mp = 60; const t = B[0]; const r = cast(A[0], '힘들면...죽어');
  ok('힘들면...죽어: MP 최저 적 즉사', r.ok && t.hp <= 0 && B[1].hp > 0); }
{ let n = 0; for (let i = 0; i < 200; i++) { const { A, B } = sides([H], N); cast(A[0], '처음부터...다시.'); n += B.filter(t => t.st.para).length; } const rate = n / 600;
  ok('마비 확률 약 40%', rate > 0.3 && rate < 0.5, rate.toFixed(2)); }
console.log(fails ? `\n${fails} FAIL` : '\nALL PASS');
