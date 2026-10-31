// 스토리 rules: blind(고정 명중 저하) 검사: node tools/test_story_turn_rules.mjs (survive·maxTurns 는 game.js 경로)
import { readFileSync } from 'fs';
import { setSkillData, initPlayers, placeUnit, statusIcons } from '../js/skills.js';
import { parseCSV, makeUnit, resolveAttack, setCardPool } from '../js/rules.js';
const rd = f => readFileSync(new URL('../data/' + f, import.meta.url), 'utf8');
const pool = [...parseCSV(rd('cards.csv')), ...parseCSV(rd('npc_cards.csv'))];
setCardPool(pool); setSkillData(JSON.parse(rd('skills.json')), JSON.parse(rd('combos.json')));
let fails = 0; const ok = (c, m) => { if (!c) { fails++; console.log('FAIL', m); } else console.log('ok  ', m); };
const C = id => pool.find(c => String(c.id) === id);
const A = { name: 'A', hp: 9999, field: [], hand: [], deck: [], mana: 0 }, B = { name: 'B', hp: 9999, field: [], hand: [], deck: [], mana: 0 }; initPlayers(A, B, A);
const me = placeUnit(A, { ...C('10072'), blindP: 0.4 }, makeUnit), foe = placeUnit(B, C('10051'), makeUnit);
ok(me.card.blindP === 0.4, 'card.blindP 전달');
ok(statusIcons(me).some(s => s.kind === 'blind'), '명중 저하 아이콘');
let miss = 0; for (let i = 0; i < 2000; i++) { me.canAttack = true; me.hp = me.maxHp; foe.hp = foe.maxHp = 999999; foe.st = {}; if (resolveAttack(A, B, me, foe).some(e => e.blind)) miss++; }
ok(miss > 700 && miss < 900, `빗나감 ${(miss / 20).toFixed(1)}% (≈40%)`);
console.log(fails ? `${fails} FAIL` : 'ALL OK'); process.exit(fails ? 1 : 0);
