// [염원] 최윤정 '너무너무 사랑해' (사망 시 1회 즉시 부활 HP 50%) 회귀 테스트
// 부활해도 같은 진영 다른 카드의 행동(canAttack)·공격 대상이 그대로여야 하고, 두 번째 사망은 진짜 사망
import { readFileSync } from 'fs';
import { setSkillData, initPlayers, placeUnit, checkDeath, setEmitter } from '../js/skills.js';
import { parseCSV, makeUnit, setCardPool, resolveAttack, attackTargets } from '../js/rules.js';
const rd = f => readFileSync(new URL('../data/' + f, import.meta.url), 'utf8');
const pool = [...parseCSV(rd('cards.csv')), ...parseCSV(rd('npc_cards.csv'))]; setCardPool(pool);
setSkillData(JSON.parse(rd('skills.json')), JSON.parse(rd('combos.json'))); setEmitter(() => {});
const C = id => pool.find(c => String(c.id) === id);
let fail = 0; const ok = (c, m) => { console.log((c ? '✓ ' : '✗ ') + m); if (!c) fail++; };
const mk = () => { const A = { name: 'A', hp: 9999, field: [], hand: [], deck: [] }, B = { name: 'B', hp: 9999, field: [], hand: [], deck: [] }; initPlayers(A, B, A); return [A, B]; };
{ // 내 최윤정 부활 → 내 다른 카드 행동 유지
  const [A, B] = mk(); const yj = placeUnit(A, C('10491'), makeUnit), mate = placeUnit(A, C('10051'), makeUnit), foe = placeUnit(B, C('10051'), makeUnit);
  A.field.forEach(u => u.canAttack = true); yj.hp = 0;
  ok(checkDeath(yj, foe) === false && A.field.includes(yj) && yj.hp === Math.round(yj.maxHp * 0.5), '내 최윤정 HP 50% 부활');
  ok(mate.canAttack && yj.canAttack, '부활 뒤 아군 행동 유지');
  ok(attackTargets(A, B, mate).units.includes(foe), '부활 뒤 아군 공격 대상 유지');
  yj.hp = 0; ok(checkDeath(yj, foe) === true && !A.field.includes(yj), '두 번째 사망은 부활 없음 (한 게임 1회)');
}
{ // 적 최윤정 부활 (기본 공격 처치) → 공격자 외 내 카드 행동 유지, 부활한 적은 계속 공격 가능
  const [A, B] = mk(); const a1 = placeUnit(A, C('10051'), makeUnit), a2 = placeUnit(A, C('10051'), makeUnit), yj = placeUnit(B, C('10491'), makeUnit);
  A.field.forEach(u => u.canAttack = true); yj.hp = 1;
  resolveAttack(A, B, a1, yj);
  ok(B.field.includes(yj) && yj.hp > 1, '적 최윤정 부활');
  ok(!a1.canAttack && a2.canAttack, '공격한 카드만 행동 소모');
  ok(attackTargets(A, B, a2).units.includes(yj), '부활한 적 공격 가능');
}
if (fail) { console.log(`실패 ${fail}`); process.exit(1); } console.log('OK');
