// 0턴(시작 배치) 상태 지속 · 조윤하 회피 · 이윤이 면역 회귀 테스트: node tools/test_turn_buff.mjs
import './seed_rng.mjs';
import fs from 'fs';
import { parseCSV, makeUnit, RULES } from '../js/rules.js';
import { setSkillData, initPlayers, placeUnit, skillsOf, useSkill, turnStart, turnEnd, TURN, damageUnit, checkDeath, refreshAll, onLevelChange, evadeChance, rollEvade, setEmitter } from '../js/skills.js';
setEmitter(() => {});
setSkillData(JSON.parse(fs.readFileSync('data/skills.json')), JSON.parse(fs.readFileSync('data/combos.json')));
const cards = parseCSV(fs.readFileSync('data/cards.csv', 'utf8')); const C = id => cards.find(c => String(c.id) === id);
const mk = (c, uid) => { const u = makeUnit(c, uid); u.sk = skillsOf(c.id); return u; };
let fails = 0; const ok = (n, c, x = '') => { console.log((c ? 'PASS ' : 'FAIL ') + n + (x ? ' — ' + x : '')); if (!c) { fails++; process.exitCode = 1; } };
const pl = n => ({ name: n, field: [], hand: [], deck: [], mana: 99, hp: 3000, maxHp: 3000, turnsTaken: 9 });
const YJ = '2000800171', YH = '2000500111', YI = '2000400086', FOE = '1002400375';
// 내 턴 → 상대 턴 한 바퀴
const myTurnThenFoe = (a, b) => { turnEnd(a); TURN.p = b; turnStart(b); };
const foeThenMine = (a, b) => { turnEnd(b); TURN.p = a; turnStart(a); };

// 3) 선공일 때 0턴 1턴짜리 상태(예유진 불사·도발)가 내 턴 종료에 바로 꺼지던 문제
{ const a = pl('A'), b = pl('B'); TURN.p = null; initPlayers(a, b, a); const yj = placeUnit(a, C(YJ), mk); placeUnit(b, C(FOE), mk); refreshAll(a);
  ok('예유진 0턴 불사 부여', !!yj.st.endure);
  turnStart(a); myTurnThenFoe(a, b);
  ok('선공: 첫 상대 턴에 예유진 불사·도발 유지', !!yj.st.endure && !!yj.st.taunt, JSON.stringify(Object.keys(yj.st)));
  damageUnit(yj, 9999, null); ok('상대 턴 피해에도 HP 1 유지', !checkDeath(yj, null) && yj.hp === 1);
  foeThenMine(a, b); turnEnd(a); ok('다음 내 턴 종료에 해제 (1턴)', !yj.st.endure); }
{ const a = pl('A'), b = pl('B'); TURN.p = null; initPlayers(a, b, b); const yj = placeUnit(a, C(YJ), mk); placeUnit(b, C(FOE), mk);
  turnStart(b); turnEnd(b); TURN.p = a; turnStart(a); ok('후공: 첫 상대 턴(선공 턴) 동안 유지', !!yj.st.endure);
  myTurnThenFoe(a, b); ok('후공: 내 첫 턴 종료에 해제', !yj.st.endure); }
// 2) 조윤하 [미쳐간다] 회피 +20% 2턴: 선공 0턴 배치 시 상대 턴 2번 유지
{ const a = pl('A'), b = pl('B'); initPlayers(a, b, a); const c = { ...C(YH) }; const yh = placeUnit(a, c, mk); yh.level = 2; onLevelChange(yh); placeUnit(b, C(FOE), mk);
  ok('조윤하 회피 버프 부여', yh.st.evade?.p === 0.2);
  turnStart(a); myTurnThenFoe(a, b); const e1 = !!yh.st.evade; foeThenMine(a, b); myTurnThenFoe(a, b); const e2 = !!yh.st.evade; foeThenMine(a, b); turnEnd(a);
  ok('조윤하 회피: 상대 턴 2번 동안 유지 후 해제', e1 && e2 && !yh.st.evade); }
{ const a = pl('A'), b = pl('B'); initPlayers(a, b, a); const yh = placeUnit(a, C(YH), mk); const foe = placeUnit(b, C(FOE), mk); RULES.EVADE_ON = true;
  const N = 4000, rate = () => { let e = 0; for (let i = 0; i < N; i++) if (rollEvade(yh, foe)) e++; return e / N; };
  delete yh.st.evade; const base = rate(), pBase = evadeChance(yh); yh.st.evade = { kind: 'evade', p: 0.2, t: 2 }; const buff = rate(), pBuff = evadeChance(yh);
  ok('조윤하 회피율: 버프 없음 ≈ 기본, 버프 ≈ 기본+20%p', Math.abs(base - pBase) < 0.02 && Math.abs(buff - pBuff) < 0.02 && pBuff - pBase > 0.19, `없음 ${(base * 100).toFixed(1)}% (기대 ${(pBase * 100).toFixed(0)}%) · 버프 ${(buff * 100).toFixed(1)}% (기대 ${(pBuff * 100).toFixed(0)}%)`); }
// 1) 이윤이 면역 뒤 조윤하 패시브 발동해도 면역 유지, 상대 턴 2번 보호
{ const a = pl('A'), b = pl('B'); initPlayers(a, b, a); const yh = placeUnit(a, C(YH), mk), yi = placeUnit(a, C(YI), mk); placeUnit(b, C(FOE), mk);
  turnStart(a); [yh, yi].forEach(u => { u.level = 2; u.mp = u.maxMp; u.canAttack = true; u.cd = {}; }); yh.fired = {};
  useSkill(yi, yi.sk.find(s => s.name === '더 이상의 비극은 없어!')); onLevelChange(yh);
  ok('조윤하 패시브 뒤에도 이윤이·조윤하 면역 유지', !!yi.st.immune && !!yh.st.immune && !!yh.st.evade);
  let hurt = 0; for (let r = 0; r < 2; r++) { myTurnThenFoe(a, b); const h = yi.hp; damageUnit(yi, 9999, null); hurt += h - yi.hp; foeThenMine(a, b); }
  ok('이윤이: 상대 턴 2번 피해 0', hurt === 0 && yi.hp > 0, `hurt ${hurt}`); }
console.log(fails ? `${fails} FAIL` : 'ALL PASS');
