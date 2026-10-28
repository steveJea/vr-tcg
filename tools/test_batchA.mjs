// 2026-10-22 신규·변경 스킬 검증: node tools/test_batchA.mjs
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
ok('하지혜 10440 = UR', C('10440')?.name === '하지혜' && C('10440').grade === 'ULTRA RARE');
ok('허유희 10452 유지(HR)', C('10452')?.name === '허유희' && C('10452').grade === 'HIGH RARE');
ok('황예영 = SR', C('10465')?.grade === 'SUPER RARE');
ok('신규 4장 (박인영·하지은·정미선·정지선)', ['10127', '10439', '10355', '10367'].every(id => C(id) && C(id).power > 0 && C(id).cost > 0));
ok('모든 신규 스킬 구현됨', ['10465', '10440', '10439', '10127', '10300'].every(id => skillsOf(id).every(s => s.mode === 'passive' || ACTIVE[s.name])));

// 김기림 아파하라: 코스트 최고
{ setRng(() => 0.99); const { A, B } = sides(['10051'], ['10074', '10024']); const h = B.map(t => t.hp);
  cast(A[0], '아파하라'); ok('아파하라: 코스트가 가장 높은 적', B[1].hp < h[1] && B[0].hp === h[0]); }
// [각성] 임유리 眞: 고정 120 / 300
{ setRng(() => 0.99); const { A, B } = sides(['10326'], ['10024']); const t = B[0]; t.maxHp = t.hp = 5000;
  cast(A[0], '아름다운 고통의 키스(眞)'); ok('키스(眞): 고정 120', t.hp === 4880, t.hp);
  cast(A[0], '더 울어, 예쁘게!(眞)'); ok('더 울어(眞): 고정 300', t.hp === 4580, t.hp); }
// 송지은 귀여운 고문자: 마비 / 처치 시 쿨타임 리셋
{ setRng(() => 0.99); const { A, B } = sides(['10208'], ['10024']); cast(A[0], '귀여운 고문자');
  ok('귀여운 고문자: 생존 시 1턴 마비', !!B[0].st.para);
  const r = sides(['10208'], F.slice(0, 1)); r.B[0].hp = 1; cast(r.A[0], '귀여운 고문자'); ok('귀여운 고문자: 처치 시 쿨타임 리셋', r.A[0].cd['귀여운 고문자'] === 0); }
// 윤진아 검은 늪 20%
{ const { a, A } = sides(['10290', '10024'], ['10074']); const t = A[1]; t.hp = 10;
  turnStart(a); ok('검은 늪: 가장 다친 아군 20% 회복', t.hp === 10 + Math.round(t.maxHp * 0.2), t.hp); }
// 황예영
{ setRng(() => 0.99); const { a, b, A, B } = sides(['10465', '10466'], ['10074']); const yy = A[0], ye = A[1], foe = B[0];
  cast(yy, '언니니까!'); yy.hp = 3; damageUnit(yy, 999, foe); checkDeath(yy, foe); ok('언니니까!: HP 1 유지', yy.hp === 1 && a.field.includes(yy));
  ok('언니니까!: 반격 ×2.4', yy.st.thorns?.cm === 2.4);
  yy.hp = yy.maxHp; delete yy.st.endure; delete yy.st.thorns;
  yy.canAttack = true; yy.mp = yy.maxMp; yy.cd = {}; ok('내 동생 건드리지마!: 예은 있으면 사용 가능', skillState(yy, sk(yy, '내 동생 건드리지마!')).ok);
  cast(yy, '내 동생 건드리지마!'); TURN.p = b; foe.canAttack = true; const h = ye.hp, hy = yy.hp; resolveAttack(b, a, foe, ye);
  ok('내 동생 건드리지마!: 예은 대신 예영이 맞음', ye.hp === h && yy.hp < hy);
  ye.hp = 10; turnEnd(b); turnStart(a); ok('내 동생 건드리지마!: 턴 시작 시 예은 10% 회복', ye.hp === 10 + Math.round(ye.maxHp * 0.1), ye.hp);
  const r = sides(['10465'], ['10074']); ok('내 동생 건드리지마!: 예은·준태 없으면 사용 불가', !skillState(r.A[0], sk(r.A[0], '내 동생 건드리지마!')).ok);
  cast(r.A[0], '누나니까!'); ok('누나니까!: 도발 + DEF +20%', r.A[0].st.taunt && r.A[0].st['누나니까!']?.def === 0.2); }
// 이민채 카르밀라: 소환 직후 2턴 불사
{ const { a, A } = sides(['10300'], ['10074'], 1); const m = A[0];
  ok('카르밀라...사랑해: 소환 시 불사', !!m.st.endure); m.hp = 1; damageUnit(m, 500); checkDeath(m); ok('카르밀라: 쓰러지지 않음', a.field.includes(m) && m.hp === 1);
  m.hp = 0; checkDeath(m); ok('카르밀라: 즉사도 버팀', a.field.includes(m)); }
// 하지혜
{ setRng(() => 0.99); const { a, b, A, B } = sides(['10440', '10411'], ['10118', '10189']); const jh = A[0], ally = A[1];
  cast(jh, '죽이지 않으면 죽어'); ok('죽이지 않으면 죽어: 2턴 도발 + 반격 ×2.4', jh.st.taunt && jh.st.thorns?.cm === 2.4);
  const hs = B.map(t => t.hp); cast(jh, '죽지 않으려면 죽여'); ok('죽지 않으려면 죽여: 적 전체 타격', B.every((t, i) => !b.field.includes(t) || t.hp < hs[i]));
  B.forEach(t => { t.hp = t.maxHp; delete t.st.bleed; }); delete jh.st.taunt; TURN.p = b; const foe = B[0]; foe.canAttack = true; const fh = foe.hp, mp = jh.mp, other = B[1].hp;
  resolveAttack(b, a, foe, ally); ok('너도 언젠간 죽어: 아군 여성 피격 → 공격자에게 반격 스킬 (MP 소모 없음)', foe.hp < fh - Math.round(calcDamage(ally.card, foe.card) * RULES.COUNTER_RATIO) && jh.mp === mp && B[1].hp === other, `${fh}→${foe.hp}`); }
// 하지은
{ setRng(() => 0.99); const { a, b, A, B } = sides(['10439', '10411', '10024'], ['10074']); const je = A[0], low = A[1], hi = A[2], foe = B[0];
  TURN.p = b; je.mp = 0; foe.canAttack = true; let h = low.hp, hj = je.hp; resolveAttack(b, a, foe, low);
  ok('내가 지켜준다: 코스트 최저 여성 대신 맞음 + MP 20%', low.hp === h && je.hp < hj && je.mp === Math.round(je.maxMp * 0.2), `mp=${je.mp}`);
  foe.canAttack = true; h = hi.hp; resolveAttack(b, a, foe, hi); ok('내가 지켜준다: 다른 여성은 그대로 맞음', hi.hp < h);
  je.hp = 0; checkDeath(je, foe); ok('나는 쓰러지지 않아: 1회 부활 + 면역', a.field.includes(je) && je.hp === Math.round(je.maxHp * 0.5) && !!je.st.immune);
  delete je.st.immune; je.hp = 0; checkDeath(je, foe); ok('나는 쓰러지지 않아: 두 번째는 쓰러짐', !a.field.includes(je));
  TURN.p = a; const r = sides(['10439'], ['10074']); cast(r.A[0], '너가 할 수 있겠어?'); ok('너가 할 수 있겠어?: 도발', !!r.A[0].st.taunt); }
// 박인영
{ setRng(() => 0.99); const { A, B, b } = sides(['10127'], ['10074', '10024', '10080']); const h = B.map(t => t.hp);
  cast(A[0], '내가 간다'); ok('내가 간다: 코스트 최고 3회', B[1].hp < h[1] && B[0].hp === h[0]);
  const r = sides(['10127'], ['10074', '10080', '10445']); const low = r.B.reduce((m, x) => (x.base.MOR < m.base.MOR ? x : m)); low.hp = 1;
  const nb = r.B.filter(x => x !== low); const hh = nb.map(x => x.hp); cast(r.A[0], '정의는 승리한다');
  ok('정의는 승리한다: 처치 → 옆 카드 타격 + 쿨타임 리셋', !r.b.field.includes(low) && nb.some((x, i) => x.hp < hh[i]) && r.A[0].cd['정의는 승리한다'] === 0); }
// 문지예 비오는 밤: 해금 시 패시브 연출 이벤트
{ evs.length = 0; const a = { name: 'A', field: [], hand: [], deck: [], mana: 99, hp: 3000 }, b = { name: 'B', field: [], hand: [], deck: [], mana: 99, hp: 3000 }; initPlayers(a, b);
  placeUnit(a, C('10111'), (c, uid) => { const u = mk(c, uid); u.level = 5; return u; });
  ok('비오는 밤: 해금된 채 소환되면 패시브 컷인 이벤트', evs.some(e => e.type === 'passive' && e.name === '비오는 밤'));
  evs.length = 0; const u = placeUnit(a, C('10111'), (c, uid) => { const x = mk(c, uid); x.level = 1; return x; });
  ok('비오는 밤: 해금 전에는 없음', !evs.some(e => e.type === 'passive')); }
console.log(fails ? `${fails} FAIL` : 'ALL PASS');
