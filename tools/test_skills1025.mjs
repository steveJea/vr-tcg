// 10/25 신규·변경 스킬 검증: node tools/test_skills1025.mjs
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
const ID = { 김동욱: '1001500315', 조윤하: '2000500111', 이영아: '2000600132', 서진성: '1001500285', 정지선: '2000000016', 류하예: '2000200031', 지세련: '2000200019', 홍다영: '2001500292', 신아린: '2001400261', 최국선: '1000500107', 허유희: '2000000012', 이윤이: '2000400086', 예유진: '2000800171', 남태은: '2001700341', 선나영: '2000400085', 반지아: '2001100231', 선미영: '2000400094' };
const N = ['1000100012', '1000100013', '1000100014'];
setRng(() => 0.99);
// 김동욱: 즉사 + 자신 현재 HP 99% 하락, 면역·불사 중엔 하락 없음
{ const { A, B } = sides([ID.김동욱], N); const c = A[0]; delete c.st.immune; c.hp = 300; const low = B.slice().sort((x, y) => x.card.cost - y.card.cost)[0];
  cast(c, '러시안룰렛'); ok('러시안룰렛: 최저 코스트 적 즉사', !B[0].owner.field.includes(low));
  ok('러시안룰렛: 현재 HP 300 → 3 (99% 하락)', c.hp === 3, c.hp);
  c.hp = 300; c.st.immune = { kind: 'immune', t: 2 }; cast(c, '러시안룰렛'); ok('피해 면역 중엔 HP 그대로', c.hp === 300, c.hp);
  delete c.st.immune; c.hp = 1; cast(c, '러시안룰렛'); ok('HP 1이면 그대로 (죽지 않음)', c.hp === 1); }
// 조윤하: 출전 시 회피 +20% 2턴
{ const { A } = sides([ID.조윤하], N); ok('조윤하 미쳐간다: 회피 +20%', A[0].st.evade?.p === 0.2); }
// 이영아: 출전 즉시 아군 전체 불사 2턴, 즉사도 막음
{ const { a, A, B } = sides([ID.김동욱, ID.이영아], [ID.김동욱]); const [c] = A;
  ok('이영아 잔상: 아군 전체 불사', A.every(x => x.st.endure));
  const cheap = A.slice().sort((x, y) => x.card.cost - y.card.cost)[0]; TURN.p = B[0].owner; cast(B[0], '러시안룰렛');
  ok('잔상: 즉사도 막음 (HP 1)', a.field.includes(cheap) && cheap.hp === 1); }
// 피해 면역 버프들
{ const { A, B } = sides([ID.류하예, ID.조윤하, ID.이윤이, ID.서진성], N); cast(A[0], '무시하지 마세요.');
  ok('류하예: RARE 이하 여성만 면역', A[0].st.immune && A[1].st.immune && !A[2].st.immune && !A[3].st.immune); }
{ const { A } = sides([ID.이윤이, ID.선미영, ID.류하예, ID.서진성], N); cast(A[0], '더 이상의 비극은 없어!');
  ok('이윤이: HR 이하 여성만 면역 (SR·남성 제외)', A[0].st.immune && A[2].st.immune && !A[1].st.immune && !A[3].st.immune); }
for (const [n, s] of [['지세련', '약육강식? 웃기지 마세요.'], ['홍다영', '부드러움은 강함을 이깁니다'], ['신아린', '당하고만 살진 않아요']]) { const { A } = sides([ID[n], ID.류하예], N); cast(A[0], s); ok(`${n}: HR 이하 여성 면역`, A[0].st.immune && A[1].st.immune); }
{ const { A } = sides([ID.허유희, ID.류하예, ID.이윤이], N); cast(A[0], '귀족이...전부 악인은 아니랍니다.');
  ok('허유희: 성품 50 이상 여성 면역 (이윤이 55 포함)', A.every(x => x.st.immune)); }
{ const { A } = sides([ID.남태은, ID.예유진, ID.선미영], N); cast(A[0], '약해 보인다고 무시하지 마!');
  ok('남태은: 코스트 35 미만 여성 1턴 면역 (선미영 37 제외)', A[0].st.immune && A[1].st.immune && !A[2].st.immune); }
{ const { A } = sides([ID.최국선], N); cast(A[0], '내가 누군지 아냐?'); ok('최국선: 자신 피해 면역', !!A[0].st.immune); }
{ const { A } = sides([ID.서진성, ID.류하예], N); cast(A[0], '핑핑 돌지?'); ok('서진성: 아군 회피 +10%', A.every(x => x.st.evade?.p === 0.1)); }
{ const { A } = sides([ID.정지선, ID.예유진, ID.이윤이], N); ok('정지선: 코스트 낮은 여성 면역 (자신·고코스트 제외)', A[1].st.immune && !A[0].st.immune && !A[2].st.immune); }
{ const { A } = sides([ID.예유진], N); ok('예유진: 도발 + 불사 1턴', A[0].st.taunt && A[0].st.endure); }
{ const { a, b, A, B } = sides([ID.반지아], N); const atk = B.map(t => t.card.ATK); A[0].hp = 0; checkDeath(A[0], B[0]);
  ok('반지아 사망 시 적 전체 ATK -70%', B.every((t, i) => t.st['지아는 약하지 않아!']?.atk === -0.7 && t.card.ATK < atk[i]), B.map(t => t.card.ATK).join('/')); }
// 선나영 → 선미영
{ const lvCard = { ...C(ID.선나영), slv: 11 }; const a = { name: 'A', field: [], hand: [], deck: [], mana: 99, hp: 3000, maxHp: 3000, turnsTaken: 9 }, b = { name: 'B', field: [], hand: [], deck: [], mana: 99, hp: 3000, maxHp: 3000, turnsTaken: 9 };
  initPlayers(a, b); TURN.p = a; const u = placeUnit(a, lvCard, mk); placeUnit(b, C(N[0]), mk); u.level = 10; onLevelChange(u); u.hp = 10;
  cast(u, '언니...도와줘요.'); const mc = C(ID.선미영);
  ok('선나영 → 선미영 교체 (같은 레벨 Lv.11: SR +40%)', String(u.base.id) === ID.선미영 && u.maxHp === Math.round(mc.HP * 1.4) && u.hp === u.maxHp, `${u.base.name} ${u.hp}/${u.maxHp}`);
  ok('교체 중 선미영 스킬', u.sk.some(s => skillsOf(ID.선미영).includes(s)));
  for (let i = 0; i < 4 && u.swap; i++) { turnEnd(a); turnStart(b); turnEnd(b); turnStart(a); }
  ok('2턴 후 선나영 복귀 + HP 100%', String(u.base.id) === ID.선나영 && u.hp === u.maxHp && !u.swap, `${u.base.name} ${u.hp}/${u.maxHp}`);
  cast(u, '언니...도와줘요.'); u.hp = 0; checkDeath(u, null);
  ok('선미영이 쓰러지면 선나영이 쓰러진 것으로 (무덤 = 선나영)', !a.field.includes(u) && String(a.grave.at(-1).id) === ID.선나영); }
// AI가 새 버프 스킬을 씀
{ const { A } = sides([ID.이윤이, ID.류하예, ID.예유진], [ID.선미영]); A[0].hp = A[0].maxHp; ok('AI: 이윤이 면역 스킬 선택', aiPickSkill(A[0])?.name === '더 이상의 비극은 없어!'); }
console.log(fails ? `${fails} FAILED` : 'ALL PASS');
