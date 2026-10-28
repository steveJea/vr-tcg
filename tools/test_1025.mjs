// 2026-10-25 유가을 신규 · 민홍기 [용서는 없다] 검증: node tools/test_1025.mjs
import './seed_rng.mjs';   // 고정 시드 난수 (치명타·회피·속성 패시브 등 확률 결과 고정)
import fs from 'fs';
import { parseCSV, makeUnit, resolveAttack, calcDamage, RULES } from '../js/rules.js';
RULES.GENDER_ON = false; RULES.EVADE_ON = false;   // 스킬 수치 검증용 (성별·속성 회피는 test_batchB.mjs)
import { setSkillData, initPlayers, placeUnit, skillsOf, ACTIVE, useSkill, skillState, turnStart, turnEnd, setRng, TURN, checkDeath, refreshAll, setEmitter, damageUnit } from '../js/skills.js';
const evs = []; setEmitter(e => { evs.push(e); if (process.env.DBG) console.log('  ev', e.type, e.unit?.card?.name || '', e.text || e.name || e.dmg || ''); });
setSkillData(JSON.parse(fs.readFileSync('data/skills.json')), JSON.parse(fs.readFileSync('data/combos.json')));
const cards = parseCSV(fs.readFileSync('data/cards.csv', 'utf8')); const C = id => cards.find(c => String(c.id) === id);
const mk = (c, uid) => { const u = makeUnit(c, uid); u.sk = skillsOf(c.id); return u; };
let fails = 0; const ok = (n, c, extra = '') => { console.log((c ? 'PASS ' : 'FAIL ') + n + (extra ? ' — ' + extra : '')); if (!c) { fails++; process.exitCode = 1; } };
const sides = (aIds, bIds, lv = 10) => {
  const a = { name: 'A', field: [], hand: [], deck: [], mana: 99, hp: 3000, maxHp: 3000, turnsTaken: 9 }, b = { name: 'B', field: [], hand: [], deck: [], mana: 99, hp: 3000, maxHp: 3000, turnsTaken: 9 };
  initPlayers(a, b); TURN.p = a;
  const A = aIds.map(id => placeUnit(a, C(id), mk)), B = bIds.map(id => placeUnit(b, C(id), mk));
  [...A, ...B].forEach(u => { u.level = lv; u.mp = u.maxMp; u.canAttack = true; }); refreshAll(a);
  return { a, b, A, B };
};
const sk = (u, name) => u.sk.find(s => s.name === name);
const cast = (u, name) => { u.canAttack = true; u.mp = u.maxMp; u.cd = {}; return useSkill(u, sk(u, name)); };
const N = ['10074', '10080', '10445', '10375', '10404'];   // 남성 N
const F = ['10411', '10443', '10305'];                             // 여성 N

// 카드 데이터
const MH = '10118', YU = '10115', GA = '10267', EN = ['10414', '10110', '10413'];
ok('유가을 카드 (HR·ICE·DEFENSE·22283·35)', C(GA)?.name === '유가을' && C(GA).grade === 'HIGH RARE' && C(GA).power === 22283 && C(GA).cost === 35);
ok('민홍기 2번 = 용서는 없다 (액티브, 해금 5, MP50, 쿨4) · 아기토끼 제거', (() => { const s = skillsOf(MH)[1]; return s.name === '용서는 없다' && s.mode === 'active' && s.unlock === 5 && s.mp === 50 && s.cooldown === 4 && ACTIVE['용서는 없다'] && !skillsOf(MH).some(x => x.name === '아기토끼'); })());
{ const { B, A } = sides([MH], EN); const hp0 = B.map(u => u.hp); const r = cast(A[0], '용서는 없다');
  const exp = B.map(u => 2 * Math.max(1, Math.round(calcDamage(A[0].card, u.card) * 0.2)));
  ok('용서는 없다: 적 전체 2회 타격', r.ok && B.every((u, i) => hp0[i] - u.hp >= 2), JSON.stringify(B.map((u, i) => hp0[i] - u.hp)) + ' ~ ' + JSON.stringify(exp)); }
{ let n = 0, tot = 0; for (let k = 0; k < 200; k++) { const { B, A } = sides([MH], EN); cast(A[0], '용서는 없다'); B.forEach(u => { tot++; if (u.st.bleed) n++; }); }
  ok('용서는 없다: 출혈 약 30%', n / tot > 0.2 && n / tot < 0.4, `${n}/${tot}`); }
// 사랑하는 친구거든!: 민유연 대신 피격, 30% 감면, 반격 없음
{ const { a, b, A, B } = sides([EN[0]], [YU, GA]); TURN.p = a; const att = A[0], yu = B[0], ga = B[1]; const ah = att.hp, yh = yu.hp, gh = ga.hp;
  resolveAttack(a, b, att, yu); ok('사랑하는 친구거든!: 유가을이 대신 맞음 · 반격 없음', yu.hp === yh && ga.hp < gh && att.hp === ah, `yu ${yh}->${yu.hp} ga ${gh}->${ga.hp} att ${ah}->${att.hp}`);
  const full = Math.max(1, Math.round(calcDamage(att.card, ga.card))); ok('사랑하는 친구거든!: 피해 30% 감면', gh - ga.hp <= Math.round(full * 0.7) + 1, `${gh - ga.hp} vs full ${full}`); }
{ const { a, b, A, B } = sides([EN[0]], [YU, GA]); TURN.p = a; B[1].st.para = { t: 1 }; const yh = B[0].hp; resolveAttack(a, b, A[0], B[0]); ok('사랑하는 친구거든!: 유가을 마비면 발동 안 함', B[0].hp < yh); }
{ const { a, b, A, B } = sides([MH], [YU, GA]); TURN.p = a; const gh = B[1].hp, yh = B[0].hp; cast(A[0], '용서는 없다'); ok('사랑하는 친구거든!: 스킬 피격엔 발동 안 함', B[0].hp < yh); }
// 도저히 용서 못해!: 민유연 사망 시 1회, 유가을 필드에 있을 때
{ const { a, b, A, B } = sides(EN, [YU, GA]); const yu = B[0]; yu.hp = 0; checkDeath(yu, A[0]);
  ok('도저히 용서 못해!: 상대 전체 DEF -20% 2턴 + 출혈', A.every(u => u.st['도저히 용서 못해!']?.t >= 2 && u.st['도저히 용서 못해!'].def < 0 && u.st.bleed), JSON.stringify(A.map(u => Object.keys(u.st))));
  const y2 = placeUnit(b, C(YU), mk); y2.level = 10; A.forEach(u => { delete u.st['도저히 용서 못해!']; delete u.st.bleed; }); y2.hp = 0; checkDeath(y2, A[0]);
  ok('도저히 용서 못해!: 전투당 1회', A.every(u => !u.st['도저히 용서 못해!'])); }
{ const { A, B } = sides(EN, [YU]); B[0].hp = 0; checkDeath(B[0], A[0]); ok('도저히 용서 못해!: 유가을 없으면 발동 안 함', A.every(u => !u.st['도저히 용서 못해!'])); }
console.log(fails ? `${fails} FAIL` : 'ALL PASS');
