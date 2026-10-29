// [염원] 최윤아·최윤정 패시브 (지켜주고 싶어 · 너무너무 사랑해 · 절대 무너지지 마). 실행: node tools/test_wish_passives.mjs
import './seed_rng.mjs';
import fs from 'fs';
import { setCardPool, parseCSV, makeUnit } from '../js/rules.js';
import { setSkillData, initPlayers, placeUnit, skillsOf, turnStart, TURN, checkDeath, refreshAll, onLevelChange } from '../js/skills.js';
setSkillData(JSON.parse(fs.readFileSync('data/skills.json')), JSON.parse(fs.readFileSync('data/combos.json')));
const cards = [...parseCSV(fs.readFileSync('data/cards.csv', 'utf8')), ...parseCSV(fs.readFileSync('data/npc_cards.csv', 'utf8'))]; const C = id => cards.find(c => String(c.id) === id);
const mk = (c, uid) => { const u = makeUnit(c, uid); u.sk = skillsOf(c.id); return u; };
setCardPool(cards);
let fails = 0; const ok = (n, c, x = '') => { console.log((c ? 'PASS ' : 'FAIL ') + n + (x ? ' — ' + x : '')); if (!c) { fails++; process.exitCode = 1; } };
const sides = (aIds, bIds = ['10144'], lv = 10) => {
  const a = { name: 'A', field: [], hand: [], deck: [], mana: 99, hp: 3000, maxHp: 3000, turnsTaken: 9 }, b = { name: 'B', field: [], hand: [], deck: [], mana: 99, hp: 3000, maxHp: 3000, turnsTaken: 9 };
  initPlayers(a, b); TURN.p = a;
  const A = aIds.map(id => placeUnit(a, C(id), mk)), B = bIds.map(id => placeUnit(b, C(id), mk));
  [...A, ...B].forEach(u => { u.level = lv; onLevelChange(u); }); refreshAll(a); return { a, b, A, B };
};
const YA = '10490', YJ = '10491', X = '10415';
{ const { a, A } = sides([YA, X]); A.forEach(u => u.hp = Math.round(u.maxHp * 0.5)); const h0 = A.map(u => u.hp); turnStart(a);
  ok('지켜주고 싶어: 매 턴 아군 전체 HP 10% 회복', A.every((u, i) => u.hp >= h0[i] + Math.round(u.maxHp * 0.1) - 1), A.map(u => `${u.hp}/${u.maxHp}`).join(' ')); }
{ const { a, A } = sides([YJ]); const u = A[0]; u.hp = 0; const d1 = checkDeath(u);
  ok('너무너무 사랑해: 사망 시 즉시 부활 (HP 50%)', !d1 && a.field.includes(u) && u.hp === Math.round(u.maxHp * 0.5), `${u.hp}/${u.maxHp}`);
  u.hp = 0; const d2 = checkDeath(u); ok('너무너무 사랑해: 한 게임 1회', d2 && !a.field.includes(u)); }
{ const { a, A } = sides([YJ, YA]); const ya = A[1]; ya.hp = 0; const d1 = checkDeath(ya);
  ok('절대 무너지지 마: [염원] 최윤아 사망 시 부활', !d1 && a.field.includes(ya) && ya.hp > 0, `${ya.hp}/${ya.maxHp}`);
  ya.hp = 0; ok('절대 무너지지 마: 1회', checkDeath(ya) && !a.field.includes(ya)); }
{ const { a, A } = sides([YJ, YA], ['10144'], 1); const ya = A[1]; ya.hp = 0; ok('절대 무너지지 마: Lv2 해금 전 미발동', checkDeath(ya)); }
{ const { a, A } = sides([X, YA]); const x = A[0]; x.hp = 0; ok('절대 무너지지 마: 다른 인재는 대상 아님', checkDeath(x)); }
console.log(fails ? `${fails} FAIL` : 'ALL OK');
