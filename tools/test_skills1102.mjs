// 11/02 시트 신규 노멀 사망 패시브 검증: node tools/test_skills1102.mjs
import './seed_rng.mjs';
import fs from 'fs';
import { setCardPool, parseCSV, makeUnit, RULES } from '../js/rules.js';
RULES.GENDER_ON = false; RULES.EVADE_ON = false;
import { setSkillData, initPlayers, placeUnit, skillsOf, TURN, checkDeath, refreshAll, onLevelChange, setRng } from '../js/skills.js';
setSkillData(JSON.parse(fs.readFileSync('data/skills.json')), JSON.parse(fs.readFileSync('data/combos.json')));
const cards = parseCSV(fs.readFileSync('data/cards.csv', 'utf8')); const C = id => cards.find(c => String(c.id) === id);
const mk = (c, uid) => { const u = makeUnit(c, uid); u.sk = skillsOf(c.id); return u; };
setCardPool(cards); setRng(() => 0.99);
let fails = 0; const ok = (n, c, x = '') => { console.log((c ? 'PASS ' : 'FAIL ') + n + (x !== '' ? ' — ' + x : '')); if (!c) { fails++; process.exitCode = 1; } };
const sides = (aIds, bIds) => { const a = { name: 'A', field: [], hand: [], deck: [], mana: 99, hp: 3000, maxHp: 3000, turnsTaken: 9 }, b = { name: 'B', field: [], hand: [], deck: [], mana: 99, hp: 3000, maxHp: 3000, turnsTaken: 9 };
  initPlayers(a, b); TURN.p = a; const A = aIds.map(id => placeUnit(a, C(id), mk)), B = bIds.map(id => placeUnit(b, C(id), mk));
  [...A, ...B].forEach(u => { u.level = 10; onLevelChange(u); for (const k of Object.keys(u.st)) delete u.st[k]; }); refreshAll(a); return { a, b, A, B }; };
const kill = u => { u.hp = 0; return checkDeath(u, null); };
const N = ['10074', '10080', '10445'];
{ const { A, B } = sides(['10395'], N); kill(A[0]); ok('지유현: 적 전원 마비', B.every(t => t.st.para), B.map(t => !!t.st.para));
  ok('지유현: 적 전원 DEF -40% 2턴', B.every(t => Object.values(t.st).some(s => s.def < 0 && s.t >= 2))); }
{ const { A } = sides(['10462', '10074', '10080'], N); const hi = A.slice(1).sort((x, y) => y.card.cost - x.card.cost)[0]; kill(A[0]);
  ok('황보예: HR 이하 최고 코스트 아군 피해 면역 2턴', hi.st.immune && hi.st.immune.t >= 2, hi.card.name); ok('다른 아군은 면역 없음', A.slice(1).filter(x => x !== hi).every(x => !x.st.immune)); }
{ const { A, B } = sides(['10247'], N); const before = B.map(t => t.hp); kill(A[0]);
  ok('예유나: SR 미만 적 HP 70% 하락', B.every((t, i) => t.hp === before[i] - Math.floor(before[i] * 0.7)), B.map(t => t.hp) + ' / ' + before); }
console.log(fails ? `${fails} FAIL` : 'ALL PASS');
