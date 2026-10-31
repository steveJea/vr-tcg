// 강보람 10509 스킬 검사: node tools/test_10509.mjs
import { readFileSync } from 'fs';
import { setSkillData, initPlayers, placeUnit, turnStart, ACTIVE } from '../js/skills.js';
import { parseCSV, makeUnit, setCardPool } from '../js/rules.js';
const rd = f => readFileSync(new URL('../data/' + f, import.meta.url), 'utf8');
const cards = parseCSV(rd('cards.csv')), pool = [...cards, ...parseCSV(rd('npc_cards.csv'))];
setCardPool(pool); setSkillData(JSON.parse(rd('skills.json')), JSON.parse(rd('combos.json')));
let fails = 0; const ok = (c, m) => { if (!c) { fails++; console.log('FAIL', m); } else console.log('ok  ', m); };
const C = id => pool.find(c => String(c.id) === id);
ok(cards.some(c => String(c.id) === '10509') && C('10509').cost === 33 && C('10509').grade === 'HIGH RARE', '플레이어 카드(cards.csv) · HR · 코스트 33');
const fresh = () => { const A = { name: 'A', hp: 9999, field: [], hand: [], deck: [], mana: 0 }, B = { name: 'B', hp: 9999, field: [], hand: [], deck: [], mana: 0 }; initPlayers(A, B, A); const u = placeUnit(A, C('10509'), makeUnit); const fs = ['10051', '10372', '10367'].map(i => placeUnit(B, { ...C(i), HP: 99999 }, makeUnit)); return { A, B, u, fs }; };
let { A, B, u, fs } = fresh(); ACTIVE['한 번 맞아봐!'](u, A, B);
const top = fs.reduce((a, b) => (b.card.cost > a.card.cost ? b : a)); ok(top.hp < 99999 && fs.filter(t => t.hp < 99999).length === 1, '한 번 맞아봐!: 코스트 최고 1명만 타격');
({ A, B, u } = fresh()); u.hp = Math.round(u.maxHp * 0.5); ACTIVE['휴식도 수련이야'](u, A, B);
ok(u.st.regen?.t >= 2 && u.st.regen.pct === 0.05 && u.st['휴식도 수련이야']?.def === 0.05, '휴식: 회복 5%×2턴 · DEF +5% 2턴');
const h0 = u.hp; turnStart(A); ok(u.hp > h0, `휴식: 턴 시작 회복 ${h0} → ${u.hp}`);
console.log(fails ? `${fails} FAIL` : 'ALL OK'); process.exit(fails ? 1 : 0);
