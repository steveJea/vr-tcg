import './seed_rng.mjs';   // 고정 시드 난수 (치명타·회피·속성 패시브 등 확률 결과 고정)
import fs from 'fs';
import { setCardPool, parseCSV, makeUnit, resolveAttack, calcDamage, RULES, cardElemMult, elementMultiplier, buildDeck, deckClassError, calcPower, GRADE_SHORT } from '../js/rules.js';
// 스킬 수치 검증용: 성별 피해(7-1)·속성 회피(7-2)는 끄고 확인 (해당 규칙은 test_batchB.mjs에서 검증)
RULES.GENDER_ON = false; RULES.EVADE_ON = false;
import { setSkillData, initPlayers, placeUnit, skillsOf, ACTIVE, useSkill, skillState, turnStart, turnEnd, setRng, TURN, checkDeath, refreshAll, setEmitter, onLevelChange, damageUnit, aiPickSkill, addStatus } from '../js/skills.js';
if (process.env.DBG) setEmitter(e => console.log('  ev', e.type, e.unit?.card?.name || '', e.text || e.name || e.dmg || ''));
setSkillData(JSON.parse(fs.readFileSync('data/skills.json')), JSON.parse(fs.readFileSync('data/combos.json')));
const cards = [...parseCSV(fs.readFileSync('data/cards.csv', 'utf8')), ...parseCSV(fs.readFileSync('data/npc_cards.csv', 'utf8'))]; const C = id => cards.find(c => String(c.id) === id);
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
const S1 = '10335', S2 = '10334', YURI = '10326', N = ['10019', '10018', '10300'];
// 카드·전투력
ok('장서현 MR·ABYSS·BALANCE·cost 100', C(S1)?.grade === 'MYTHIC RARE' && C(S1).class === 'ABYSS' && C(S1).attribute === 'BALANCE' && C(S1).cost === 100);
ok('장서아 LR·VOID·UNLIMITED·cost 185', C(S2)?.grade === 'LEGENDARY RARE' && C(S2).class === 'VOID' && C(S2).attribute === 'UNLIMITED' && C(S2).cost === 185 && GRADE_SHORT['LEGENDARY RARE'] === 'LR');
ok('전투력 = 옵션 B (LR ×10, 스킬 3액티브·3패시브)', calcPower(C(S2), skillsOf(S2)) === C(S2).power && C(S2).power === 1883130 && calcPower(C(S1), skillsOf(S1)) === C(S1).power, `${C(S2).power}`);
// 속성·클래스
const F = { class: 'FIRE', attribute: 'CHARGE' }, W = { class: 'WIND', attribute: 'CHARGE' }, I = { class: 'ICE', attribute: 'CHARGE' };
ok('VOID 공격 ×1.5 · VOID 방어 약점 없음', elementMultiplier('VOID', 'FIRE') === 1.5 && elementMultiplier('LIGHT', 'VOID') === 1 && elementMultiplier('VOID', 'VOID') === 1.25);
ok('BALANCE: 불리 없음 + 받는 피해 −15%', cardElemMult(F, { class: 'WIND', attribute: 'BALANCE' }) === 0.85 && cardElemMult({ class: 'WIND', attribute: 'BALANCE' }, F) === 1);
ok('UNLIMITED: 항상 유리(×1.5) + 주는 피해 +25%', Math.abs(cardElemMult({ class: 'ICE', attribute: 'UNLIMITED' }, F) - 1.875) < 1e-9 && Math.abs(cardElemMult({ class: 'FIRE', attribute: 'UNLIMITED' }, W) - 1.875) < 1e-9);
ok('UNLIMITED끼리 보정 없음', cardElemMult({ class: 'FIRE', attribute: 'UNLIMITED' }, { class: 'FIRE', attribute: 'UNLIMITED' }) === 1);
// 덱 규칙
ok('VOID 1장·ABYSS와 같은 덱 불가', deckClassError([C(S2), C(S1)]) && deckClassError([C(S2), C(S2)]) && !deckClassError([C(S2), C(N[0])]));
{ const pool = [...cards.filter(c => c.grade !== 'LEGENDARY RARE'), C(S2), { ...C(S2), id: 'v2' }]; let bad = 0; for (let i = 0; i < 30; i++) if (deckClassError(buildDeck(pool, Math.random))) bad++; ok('buildDeck: 공허·심연 규칙 지킴', bad === 0, `${bad}`); }
// 디버프 반사 + 즉사 면역
{ const sk = await import('../js/skills.js'); const { A, B } = sides(['10070'], [S1]); const caster = A[0], t = B[0];
  // 시전 중(ACTOR) 디버프 → 반사: ACTIVE 직접 호출 대신 useSkill 로 임의 디버프 스킬
  sk.ACTIVE['__probe'] = (u, p, f) => sk.addStatus(f.field[0], 'probe', 2, { atk: -0.3, label: 'probe' }, 'mod');
  caster.sk = [...caster.sk, { name: '__probe', mode: 'active', mp: 0, cooldown: 0, unlock: 1, type: '디버프', target: '적 단일', desc: '' }];
  caster.canAttack = true; const r = sk.useSkill(caster, caster.sk.at(-1));
  ok('반사 패시브: 디버프 면역 + 시전자에게 반환', r.ok && !t.st.probe && caster.st.probe?.atk === -0.3); }
{ const { A, B } = sides(['10054'], [S1]); const r = cast(A[0], '러시안룰렛'); ok('반사 패시브: 즉사 면역', r.ok && B[0].hp > 0 && B[0].owner.field.includes(B[0])); }
// 장서현 액티브
{ const { A, B } = sides([S1], N); B.forEach(t => { t.st = {}; t.paraBlock = 2; }); const r = cast(A[0], '안타까운 거죠!');
  ok('안타까운 거죠!: 연속 마비 금지 예외 · 2턴 · HP 고갈 · DEF −20%', r.ok && B.every(t => t.st.para && t.st.para.t >= 2 && t.st.dot?.pct === 0.1 && t.st['안타까운 거죠!']?.def === -0.2)); }
{ const { A, B } = sides([S1], [...N, S2]); B.forEach(t => addStatus(t, 'immune', 3, {}, 'immune')); const r = cast(A[0], '이게...되네요?');
  ok('이게...되네요?: 코스트 50 이하 전원 소멸 (면역 무시)', r.ok && B.filter(t => t.card.cost <= 50).every(t => !t.owner.field.includes(t)) && B.find(t => t.base.id === S2).owner.field.length === 1); }
{ const { A, B } = sides([S1], [N[0]]); const r = cast(A[0], '왜 그러는 건디...'); B[0].canAttack = true; TURN.p = B[0].owner; const ev = resolveAttack(B[0].owner, A[0].owner, B[0], A[0]);
  ok('왜 그러는 건디...: 도발 + 반격 시 출혈', r.ok && A[0].st.taunt && B[0].st.bleed); }
// 장서아
{ const { A, B } = sides([S2], [YURI, N[0]]); const r = cast(A[0], '있으면 안 되잖아?'); ok('있으면 안 되잖아?: [각성] 임유리 무조건 사망', r.ok && !B.find(t => t.base.id === YURI).owner.field.includes(B.find(t => t.base.id === YURI))); }
{ const { a, A } = sides([S2, N[0], N[1]], [N[2]]); const d = A[1]; d.hp = 0; checkDeath(d); A[2].hp = 10; const before = a.field.length; const r = cast(A[0], '무극');
  ok('무극: 사망 아군 부활 + HP 100% + 2턴 면역', r.ok && a.field.length === before + 1 && a.field.every(x => x.hp === x.maxHp && x.st.immune)); }
{ const { a, b, A, B } = sides([S2], [N[0]]); B[0].base.MOR = 10; B[0].mp = 0; B[0].st = {}; B[0].paraBlock = 0; TURN.p = b; turnStart(b);
  ok('사필귀정: 품성 50 미만 MP 회복 50%', B[0].mp === Math.round(B[0].mpRegen * 0.5), `${B[0].mp}/${B[0].mpRegen}`); }
// 상태이상 확률 절반
{ let n = 0; for (let i = 0; i < 400; i++) { const { B } = sides([N[0]], [S2]); B[0].sk = []; B[0].st = {}; if (addStatus(B[0], 'burn', 1, {}, 'burn')) n++; } ok('UNLIMITED: 상태이상 약 50% 저항', n > 150 && n < 250, `${n}/400`); }
console.log(fails ? `\n${fails} FAIL` : '\nALL PASS');
