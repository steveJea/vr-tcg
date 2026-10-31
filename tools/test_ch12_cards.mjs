// CH12 NPC (10505~10508) 스킬 검사: node tools/test_ch12_cards.mjs
import { readFileSync } from 'fs';
import { setSkillData, initPlayers, placeUnit, ACTIVE } from '../js/skills.js';
import { parseCSV, makeUnit, setCardPool } from '../js/rules.js';
const rd = f => readFileSync(new URL('../data/' + f, import.meta.url), 'utf8');
const pool = [...parseCSV(rd('cards.csv')), ...parseCSV(rd('npc_cards.csv'))];
setCardPool(pool); setSkillData(JSON.parse(rd('skills.json')), JSON.parse(rd('combos.json')));
let fails = 0; const ok = (c, m) => { if (!c) { fails++; console.log('FAIL', m); } else console.log('ok  ', m); };
const C = id => pool.find(c => String(c.id) === id);
const fresh = () => { const A = { name: 'A', hp: 9999, field: [], hand: [], deck: [], mana: 0 }, B = { name: 'B', hp: 9999, field: [], hand: [], deck: [], mana: 0 }; initPlayers(A, B, A); return [A, B]; };
ok(['10505', '10506', '10507'].every(i => C(i)?.cost === 30) && C('10508')?.cost === 45, '코스트 HR 30 · SR 45');
const run = (id, name) => { const [A, B] = fresh(); const u = placeUnit(A, C(id), makeUnit); u.mp = u.maxMp = 999; const fs = ['10051', '10053', '10054'].map(i => placeUnit(B, C(i), makeUnit)); fs.forEach(t => { t.hp = t.maxHp = 99999; }); ACTIVE[name](u, A, B); return fs; };
let fs = run('10505', '이게 답입니다!'); ok(fs.every(t => t.hp < 99999), '안혜진: 전체 피해');
fs = run('10506', '불쌍해라..'); ok(fs.filter(t => t.hp < 99999).length === 1, '한서린: 단일 3회');
fs = run('10507', '아무렇지 않죠?'); ok(fs.every(t => t.hp < 99999), '도예나: 전체 2회');
fs = run('10508', '계약 성사'); ok(fs.every(t => t.st.dot?.t === 2 && t.st.dot.pct === 0.03), '최태석: 중독 2턴 -3%');
let para = 0; for (let i = 0; i < 500; i++) para += run('10508', '계약 성사').filter(t => t.st.para).length; ok(para > 200 && para < 400, `최태석 마비 ${(para / 15).toFixed(1)}%`);
console.log(fails ? `${fails} FAIL` : 'ALL OK'); process.exit(fails ? 1 : 0);
