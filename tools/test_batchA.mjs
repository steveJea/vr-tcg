// 2026-10-22 신규·변경 스킬 검증: node tools/test_batchA.mjs
import fs from 'fs';
import { parseCSV, makeUnit, resolveAttack, calcDamage, RULES } from '../js/rules.js';
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
const N = ['1000100012', '1000100013', '1000100014', '1000100016', '1000200020'];   // 남성 N
const F = ['2002400383', '2002300373', '2002100365'];                             // 여성 N

// 카드 데이터
ok('하지혜 2000000012 = UR', C('2000000012')?.name === '하지혜' && C('2000000012').grade === 'ULTRA RARE');
ok('신규 4장 (박인영·하지은·정미선·정지선)', ['2000000013', '2000000014', '2000000015', '2000000016'].every(id => C(id) && C(id).power > 0 && C(id).cost > 0));
ok('모든 신규 스킬 구현됨', ['2000200051', '2000000012', '2000000014', '2000000013', '2000100003'].every(id => skillsOf(id).every(s => s.mode === 'passive' || ACTIVE[s.name])));

// 지세강 아파하라: 코스트 최고
{ setRng(() => 0.99); const { A, B } = sides(['1000200018'], ['1000100012', '2002400374']); const h = B.map(t => t.hp);
  cast(A[0], '아파하라'); ok('아파하라: 코스트가 가장 높은 적', B[1].hp < h[1] && B[0].hp === h[0]); }
// [각성] 임유리 眞: 고정 120 / 300
{ setRng(() => 0.99); const { A, B } = sides(['2000000008'], ['2002400374']); const t = B[0]; t.maxHp = t.hp = 5000;
  cast(A[0], '아름다운 고통의 키스(眞)'); ok('키스(眞): 고정 120', t.hp === 4880, t.hp);
  cast(A[0], '더 울어, 예쁘게!(眞)'); ok('더 울어(眞): 고정 300', t.hp === 4580, t.hp); }
// 송지은 귀여운 고문자: 마비 / 처치 시 쿨타임 리셋
{ setRng(() => 0.99); const { A, B } = sides(['2000900207'], ['2002400374']); cast(A[0], '귀여운 고문자');
  ok('귀여운 고문자: 생존 시 1턴 마비', !!B[0].st.para);
  const r = sides(['2000900207'], F.slice(0, 1)); r.B[0].hp = 1; cast(r.A[0], '귀여운 고문자'); ok('귀여운 고문자: 처치 시 쿨타임 리셋', r.A[0].cd['귀여운 고문자'] === 0); }
// 윤진아 검은 늪 20%
{ const { a, A } = sides(['2000500110', '2002400374'], ['1000100012']); const t = A[1]; t.hp = 10;
  turnStart(a); ok('검은 늪: 가장 다친 아군 20% 회복', t.hp === 10 + Math.round(t.maxHp * 0.2), t.hp); }
// 황예영
{ setRng(() => 0.99); const { a, b, A, B } = sides(['2000200051', '2000200053'], ['1000100012']); const yy = A[0], ye = A[1], foe = B[0];
  cast(yy, '언니니까!'); yy.hp = 3; damageUnit(yy, 999, foe); checkDeath(yy, foe); ok('언니니까!: HP 1 유지', yy.hp === 1 && a.field.includes(yy));
  ok('언니니까!: 반격 ×2.4', yy.st.thorns?.cm === 2.4);
  yy.hp = yy.maxHp; delete yy.st.endure; delete yy.st.thorns;
  yy.canAttack = true; yy.mp = yy.maxMp; yy.cd = {}; ok('내 동생 건드리지마!: 예은 있으면 사용 가능', skillState(yy, sk(yy, '내 동생 건드리지마!')).ok);
  cast(yy, '내 동생 건드리지마!'); TURN.p = b; foe.canAttack = true; const h = ye.hp, hy = yy.hp; resolveAttack(b, a, foe, ye);
  ok('내 동생 건드리지마!: 예은 대신 예영이 맞음', ye.hp === h && yy.hp < hy);
  ye.hp = 10; turnEnd(b); turnStart(a); ok('내 동생 건드리지마!: 턴 시작 시 예은 10% 회복', ye.hp === 10 + Math.round(ye.maxHp * 0.1), ye.hp);
  const r = sides(['2000200051'], ['1000100012']); ok('내 동생 건드리지마!: 예은·준태 없으면 사용 불가', !skillState(r.A[0], sk(r.A[0], '내 동생 건드리지마!')).ok);
  cast(r.A[0], '누나니까!'); ok('누나니까!: 도발 + DEF +20%', r.A[0].st.taunt && r.A[0].st['누나니까!']?.def === 0.2); }
// 이민채 카르밀라: 소환 직후 2턴 불사
{ const { a, A } = sides(['2000100003'], ['1000100012'], 1); const m = A[0];
  ok('카르밀라...사랑해: 소환 시 불사', !!m.st.endure); m.hp = 1; damageUnit(m, 500); checkDeath(m); ok('카르밀라: 쓰러지지 않음', a.field.includes(m) && m.hp === 1);
  m.hp = 0; checkDeath(m); ok('카르밀라: 즉사도 버팀', a.field.includes(m)); }
// 하지혜
{ setRng(() => 0.99); const { a, b, A, B } = sides(['2000000012', '2002400383'], ['1000100007', '1000200024']); const jh = A[0], ally = A[1];
  cast(jh, '죽이지 않으면 죽어'); ok('죽이지 않으면 죽어: 2턴 도발 + 반격 ×2.4', jh.st.taunt && jh.st.thorns?.cm === 2.4);
  const hs = B.map(t => t.hp); cast(jh, '죽지 않으려면 죽여'); ok('죽지 않으려면 죽여: 적 전체 타격', B.every((t, i) => !b.field.includes(t) || t.hp < hs[i]));
  B.forEach(t => { t.hp = t.maxHp; delete t.st.bleed; }); delete jh.st.taunt; TURN.p = b; const foe = B[0]; foe.canAttack = true; const fh = foe.hp, mp = jh.mp, other = B[1].hp;
  resolveAttack(b, a, foe, ally); ok('너도 언젠간 죽어: 아군 여성 피격 → 공격자에게 반격 스킬 (MP 소모 없음)', foe.hp < fh - Math.round(calcDamage(ally.card, foe.card) * RULES.COUNTER_RATIO) && jh.mp === mp && B[1].hp === other, `${fh}→${foe.hp}`); }
// 하지은
{ setRng(() => 0.99); const { a, b, A, B } = sides(['2000000014', '2002400383', '2002400374'], ['1000100012']); const je = A[0], low = A[1], hi = A[2], foe = B[0];
  TURN.p = b; je.mp = 0; foe.canAttack = true; let h = low.hp, hj = je.hp; resolveAttack(b, a, foe, low);
  ok('내가 지켜준다: 코스트 최저 여성 대신 맞음 + MP 20%', low.hp === h && je.hp < hj && je.mp === Math.round(je.maxMp * 0.2), `mp=${je.mp}`);
  foe.canAttack = true; h = hi.hp; resolveAttack(b, a, foe, hi); ok('내가 지켜준다: 다른 여성은 그대로 맞음', hi.hp < h);
  je.hp = 0; checkDeath(je, foe); ok('나는 쓰러지지 않아: 1회 부활 + 면역', a.field.includes(je) && je.hp === Math.round(je.maxHp * 0.5) && !!je.st.immune);
  delete je.st.immune; je.hp = 0; checkDeath(je, foe); ok('나는 쓰러지지 않아: 두 번째는 쓰러짐', !a.field.includes(je));
  TURN.p = a; const r = sides(['2000000014'], ['1000100012']); cast(r.A[0], '너가 할 수 있겠어?'); ok('너가 할 수 있겠어?: 도발', !!r.A[0].st.taunt); }
// 박인영
{ setRng(() => 0.99); const { A, B, b } = sides(['2000000013'], ['1000100012', '2002400374', '1000100013']); const h = B.map(t => t.hp);
  cast(A[0], '내가 간다'); ok('내가 간다: 코스트 최고 3회', B[1].hp < h[1] && B[0].hp === h[0]);
  const r = sides(['2000000013'], ['1000100012', '1000100013', '1000100014']); const low = r.B.reduce((m, x) => (x.base.MOR < m.base.MOR ? x : m)); low.hp = 1;
  const nb = r.B.filter(x => x !== low); const hh = nb.map(x => x.hp); cast(r.A[0], '정의는 승리한다');
  ok('정의는 승리한다: 처치 → 옆 카드 타격 + 쿨타임 리셋', !r.b.field.includes(low) && nb.some((x, i) => x.hp < hh[i]) && r.A[0].cd['정의는 승리한다'] === 0); }
// 문지예 비오는 밤: 해금 시 패시브 연출 이벤트
{ evs.length = 0; const a = { name: 'A', field: [], hand: [], deck: [], mana: 99, hp: 3000 }, b = { name: 'B', field: [], hand: [], deck: [], mana: 99, hp: 3000 }; initPlayers(a, b);
  placeUnit(a, C('2000600126'), (c, uid) => { const u = mk(c, uid); u.level = 5; return u; });
  ok('비오는 밤: 해금된 채 소환되면 패시브 컷인 이벤트', evs.some(e => e.type === 'passive' && e.name === '비오는 밤'));
  evs.length = 0; const u = placeUnit(a, C('2000600126'), (c, uid) => { const x = mk(c, uid); x.level = 1; return x; });
  ok('비오는 밤: 해금 전에는 없음', !evs.some(e => e.type === 'passive')); }
console.log(fails ? `${fails} FAIL` : 'ALL PASS');
