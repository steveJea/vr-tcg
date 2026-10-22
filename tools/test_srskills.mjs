// SR 스킬·임씨 스킬 엔진 검증: node tools/test_srskills.mjs
import './seed_rng.mjs';   // 고정 시드 난수 (치명타·회피·속성 패시브 등 확률 결과 고정)
import fs from 'fs';
import { parseCSV, makeUnit, resolveAttack, calcDamage, RULES } from '../js/rules.js';
// 스킬 수치 검증용: 성별 피해(7-1)·속성 회피(7-2)는 끄고 확인 (해당 규칙은 test_batchB.mjs에서 검증)
RULES.GENDER_ON = false; RULES.EVADE_ON = false;
import { setSkillData, initPlayers, placeUnit, skillsOf, ACTIVE, useSkill, skillState, turnStart, turnEnd, setRng, TURN, checkDeath, refreshAll, setEmitter } from '../js/skills.js';
if (process.env.DBG) setEmitter(e => console.log('  ev', e.type, e.unit?.card?.name || '', e.text || e.name || e.dmg || ''));
setSkillData(JSON.parse(fs.readFileSync('data/skills.json')), JSON.parse(fs.readFileSync('data/combos.json')));
const cards = parseCSV(fs.readFileSync('data/cards.csv', 'utf8')); const C = id => cards.find(c => String(c.id) === id);
const mk = (c, uid) => { const u = makeUnit(c, uid); u.sk = skillsOf(c.id); return u; };
let fails = 0; const ok = (n, c, extra = '') => { console.log((c ? 'PASS ' : 'FAIL ') + n + (extra ? ' — ' + extra : '')); if (!c) { fails++; process.exitCode = 1; } };
const sides = (aIds, bIds, lv = 10, noBase = false) => {
  const a = { name: 'A', field: [], hand: [], deck: [], mana: 99, hp: 3000, maxHp: 3000, turnsTaken: 9 }, b = { name: 'B', field: [], hand: [], deck: [], mana: 99, hp: 3000, maxHp: 3000, turnsTaken: 9, noBase };
  initPlayers(a, b); TURN.p = a;
  const A = aIds.map(id => placeUnit(a, C(id), mk)), B = bIds.map(id => placeUnit(b, C(id), mk));
  [...A, ...B].forEach(u => { u.level = lv; u.mp = u.maxMp; u.canAttack = true; }); refreshAll(a);
  return { a, b, A, B };
};
const sk = (u, name) => u.sk.find(s => s.name === name);
const cast = (u, name) => { u.canAttack = true; u.mp = u.maxMp; u.cd = {}; return useSkill(u, sk(u, name)); };
const N = ['1000100012', '1000100013', '1000100014', '1000100016', '1000200020'];   // 상대용 아무 카드

// 1) 임유리: 현재 HP 8% (최대 120) / 12% (최대 180)
{ setRng(() => 0.99); const { A, B } = sides(['2000100001'], N.slice(0, 3)); const yu = A[0]; const hp = B.map(t => t.hp);
  ok('임유리 스킬 존재', !!sk(yu, '아름다운 고통의 키스'), yu.sk.map(s => s.name).join(','));
  cast(yu, '아름다운 고통의 키스'); ok('키스: 현재 HP 8% 제거 (cap 120)', B.every((t, i) => hp[i] - t.hp === Math.min(120, Math.max(1, Math.round(hp[i] * 0.08)))), B.map((t, i) => hp[i] - t.hp).join('/'));
  B[0].hp = 3000; B[0].maxHp = 3000; const h2 = B.map(t => t.hp); cast(yu, '더 울어, 예쁘게!'); ok('더 울어: 12% cap 180', B[0].hp === 3000 - 180 && B.slice(1).every((t, i) => h2[i + 1] - t.hp === Math.max(1, Math.round(h2[i + 1] * 0.12))));
}
// 2) 임예리 장미가시: 10% 피해 + 도발 + 일반 반격 대신 100% 반격, 공격자 HP 1
{ setRng(() => 0.99); const { a, b, A, B } = sides(['2001100243', '2000500111'], ['1000500107']); const ye = A[0], foe = B[0]; const h = foe.hp;
  cast(ye, '장미가시의 세레나데'); ok('장미가시: 적 피해 + ATK -20% + 임예리 도발', foe.hp < h && foe.st['장미가시의 세레나데'] && ye.st.taunt);
  ye.hp = ye.maxHp; foe.hp = foe.maxHp; foe.canAttack = true; TURN.p = b;
  const exp = Math.round(calcDamage(ye.card, foe.card)); const ev = resolveAttack(b, a, foe, ye);
  ok('장미가시 반격 = 기본 공격 100% (일반 반격 대체, 1회)', ev[0].d2 === exp && foe.hp === foe.maxHp - exp, `d2=${ev[0].d2} exp=${exp}`);
  foe.hp = 5; foe.canAttack = true; ye.hp = ye.maxHp; resolveAttack(b, a, foe, ye); ok('장미가시 반격으로는 HP 1에서 멈춤', foe.hp === 1 && b.field.includes(foe));
}
// 3) 정치욱 회피 40%
{ const { a, b, A, B } = sides(['1000000003'], ['1000100012']); const j = A[0], foe = B[0];
  cast(j, '그렇게 느려도 되겠어?'); ok('정치욱 회피 상태', j.st.evade?.p === 0.4); TURN.p = b;
  setRng(() => 0.1); let h = j.hp, fh = foe.hp; foe.canAttack = true; let ev = resolveAttack(b, a, foe, j); ok('회피 성공: 피해 0, 반격 없음', j.hp === h && foe.hp === fh && ev[0].type === 'evade');
  setRng(() => 0.9); foe.canAttack = true; ev = resolveAttack(b, a, foe, j); ok('회피 실패: 정상 피격', j.hp < h && ev[0].type === 'hit');
  setRng(() => 0.1); h = j.hp; ACTIVE['건드리지마!'](foe.card && placeUnit(b, C('1000400092'), mk), b, a); ok('스킬은 회피 불가', j.hp < h);
}
// 4) 반격 ×2 (선미영 에메랄드 쇼크) + 피해 50% 감소, 고정태 반격 흡혈
{ setRng(() => 0.99); const { a, b, A, B } = sides(['2000400094', '1000600125'], ['1000500107']); const sm = A[0], gj = A[1], foe = B[0];
  const base = Math.round(calcDamage(sm.card, foe.card) * RULES.COUNTER_RATIO); const hitRaw = calcDamage(foe.card, sm.card);
  cast(sm, '에메랄드 쇼크'); TURN.p = b; foe.canAttack = true; let h = sm.hp; let ev = resolveAttack(b, a, foe, sm);
  ok('에메랄드 쇼크: 받는 피해 50%', h - sm.hp === Math.round(hitRaw * 0.5), `${h - sm.hp} vs ${hitRaw}`);
  ok('에메랄드 쇼크: 반격 ×2', ev[0].d2 === Math.round(calcDamage(sm.card, foe.card) * 2 * RULES.COUNTER_RATIO) && ev[0].d2 === 2 * base, `d2=${ev[0].d2} base=${base}`);
  TURN.p = a; cast(gj, '불을 훔친 자'); TURN.p = b; gj.hp = gj.maxHp - 200; foe.hp = foe.maxHp; foe.canAttack = true; h = gj.hp; ev = resolveAttack(b, a, foe, gj);
  const taken = Math.round(calcDamage(foe.card, gj.card)); ok('불을 훔친 자: 반격 ×2 + 반격 피해 10% 흡혈', gj.hp === h - taken + Math.round(ev[0].d2 * 0.1), `d2=${ev[0].d2}`);
}
// 5) 민지은 이런 경험 있나요?: 중간 전이 (남은 횟수 -1)
{ setRng(() => 0.99); const { A, B } = sides(['2001100235'], N.slice(0, 3)); const mj = A[0];
  B.forEach((t, i) => { t.level = 3 + i; }); B[2].hp = 1; const second = B[1], h = second.hp;
  cast(mj, '이런 경험 있나요?'); ok('최고 레벨 사망 → 다음 레벨로 전이', !B[2].owner.field.includes(B[2]) && second.hp < h);
}
// 6) 정다윤 영혼 강탈 MP -20%, 김소영 종료 시 MP -30%
{ setRng(() => 0.99); const { a, b, A, B } = sides(['2000800186', '2000700146'], ['1000100012']); const dy = A[0], ks = A[1], foe = B[0];
  cast(dy, '영혼을 강탈합니다'); TURN.p = b; foe.mp = 50; foe.canAttack = true; resolveAttack(b, a, foe, dy); ok('영혼 강탈: 기본 공격한 적 MP 20% 제거', foe.mp === 40, `mp=${foe.mp}`);
  TURN.p = a; cast(ks, '저기…나랑 갈래?'); foe.mp = 50; turnEnd(a); turnStart(b); turnEnd(b); turnStart(a); turnEnd(a); turnStart(b); const before = foe.mp; turnEnd(b);
  ok('저기…나랑 갈래?: 종료 시 MP 30% 하락', foe.mp === before - Math.round(before * 0.3) && !foe.st.dot, `${before}→${foe.mp}`);
}
// 7) 정하루 드론 폭격 초과 피해 → 본진, 일반전은 무효
{ setRng(() => 0.99); let { a, b, A, B } = sides(['2001100230'], N.slice(0, 2)); B[0].hp = 5; let h = b.hp; cast(A[0], '드론 폭격!');
  ok('드론 폭격: 처치 초과 피해가 본진으로', b.hp < h, `${h}→${b.hp}`);
  ({ a, b, A, B } = sides(['2001100230'], N.slice(0, 2), 10, true)); B[0].hp = 5; const h1 = B[1].hp; cast(A[0], '드론 폭격!'); ok('드론 폭격: 일반전(진영 없음) 초과 피해 무효', B[1].hp === h1 - (h1 - B[1].hp) && b.hp === 3000);
  ({ a, b, A, B } = sides(['2001100230'], N.slice(0, 2), 10, true)); const hs = B.map(t => t.hp); cast(A[0], '드론 연사!'); ok('드론 연사: 진영 없으면 전체 30%', B.every((t, i) => t.hp < hs[i]));
}
// 8) 강준철 내가 오빠잖아: 강재아 대신 맞음 (30% 감소) + 반격
{ setRng(() => 0.99); const { a, b, A, B } = sides(['1002000355', '2002000354'], ['1000100012']); const kj = A[0], ja = A[1], foe = B[0]; TURN.p = b;
  const h = ja.hp, hk = kj.hp; const ev = resolveAttack(b, a, foe, ja); ok('강재아 피격 → 강준철이 대신 맞고 반격', ja.hp === h && kj.hp < hk && ev[0].target === kj && ev[0].d2 > 0);
}
// 9) 금어진 조건 (최창원), 서오성 조건 (여성)
{ let { A, B } = sides(['1000400092', '1001500311'], ['1000100012']); ok('금어진: 최창원 없으면 비활성', !skillState(A[0], sk(A[0], '너는 내가 끝낸다!')).ok, skillState(A[0], sk(A[0], '너는 내가 끝낸다!')).reason);
  ok('서오성: 여성 없으면 비활성', !skillState(A[1], sk(A[1], '진짜 악당')).ok);
  ({ A, B } = sides(['1000400092'], ['1002100371', '1000100007'])); B[0].hp = 10; const mp0 = 0; A[0].mp = A[0].maxMp; const r = cast(A[0], '너는 내가 끝낸다!');
  ok('금어진: 최창원 처치 시 MP 50% 회복', r.ok && !B[0].owner.field.includes(B[0]) && A[0].mp >= Math.round(A[0].maxMp * 0.5) - 1, `mp=${A[0].mp}/${A[0].maxMp}`);
}
// 10) 문지철 사망 패시브, 고세린 후속 재생, 패시브 턴 시작 피해, 스탯 패시브
{ setRng(() => 0.99); let { a, b, A, B } = sides(['1000600130'], N.slice(0, 3)); const low = B.slice().sort((x, y) => (x.base.MOR || 0) - (y.base.MOR || 0))[0]; const h = low.hp;
  A[0].hp = 0; checkDeath(A[0], B[0]); ok('문지철 사망 → 품성 최저 250 고정', h - low.hp === 250 || !b.field.includes(low));
  ({ a, b, A, B } = sides(['2002400374'], ['1000100012'])); cast(A[0], '때리지 말라니까!'); turnEnd(a); turnStart(b); turnEnd(b); turnStart(a); turnEnd(a);
  ok('고세린: 때리지 말라니까 종료 → 아..기분좋아~ 3턴 재생 7%', A[0].st.regen?.pct === 0.07);
  ({ a, b, A, B } = sides(['2000900215', '2001400246', '2001400263', '1000300056'], N.slice(0, 2))); const hs = B.map(t => t.hp); TURN.p = b; turnEnd(b); turnStart(a);
  ok('오설화·김재신 패시브: 턴 시작 시 적 전체 8%×2', B.every((t, i) => t.hp < hs[i]));
  const ar = A[2], st = A[3]; ok('유아리 마르쉐 DEF +5%, 서태우 ATK +10%', Math.abs(ar.mods.def - 0.05) < 1e-9 || ar.mods.def >= 0.05, `${ar.mods.def} / ${st.mods.atk}`);
  ok('서태우 ATK +10%', st.mods.atk >= 0.1 - 1e-9);
}
console.log(fails ? `${fails} FAIL` : 'ALL PASS');
