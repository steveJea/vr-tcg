// 스토리 적 턴 대본: forceSkill (해금·MP·쿨타임 무시) + game.js 훅 존재 검사 — node tools/test_ai_script.mjs
import { readFileSync } from 'fs';
import { setSkillData, initPlayers, placeUnit, forceSkill, skillState, skillsOf } from '../js/skills.js';
import { parseCSV, makeUnit, setCardPool } from '../js/rules.js';
const rd = f => readFileSync(new URL('../data/' + f, import.meta.url), 'utf8');
const pool = [...parseCSV(rd('cards.csv')), ...parseCSV(rd('npc_cards.csv'))]; setCardPool(pool);
setSkillData(JSON.parse(rd('skills.json')), JSON.parse(rd('combos.json')));
let fails = 0; const ok = (c, m) => { if (!c) { fails++; console.log('FAIL', m); } else console.log('ok  ', m); };
const C = id => pool.find(c => String(c.id) === id);
const A = { name: 'A', hp: 9999, field: [], hand: [], deck: [], mana: 0, actionLock: 0 }, B = { name: 'B', hp: 9999, field: [], hand: [], deck: [], mana: 0, actionLock: 0 }; initPlayers(B, A, B);
const y = placeUnit(B, C('10325'), makeUnit); y.sk = skillsOf('10325'); const t = placeUnit(A, { ...C('10229'), HP: 9999 }, makeUnit);
const s = y.sk.find(x => x.name === '아름다운 고통의 키스');
ok(!skillState(y, s).ok, '레벨 1 · MP 0: 평소엔 못 씀');
const h0 = t.hp, mp0 = y.mp; forceSkill(y, s); ok(t.hp < h0 && y.mp === mp0 && !y.cd[s.name] && A.actionLock >= 1, '대본 스킬: 피해 · MP/쿨타임 소모 없음 · 봉인');
const g = readFileSync(new URL('../js/game.js', import.meta.url), 'utf8');
ok(/rules\?\.aiScript/.test(g) && /force \? forceSkill/.test(g), 'game.js aiScript 훅');
console.log(fails ? `${fails} FAIL` : 'ALL OK'); process.exit(fails ? 1 : 0);
