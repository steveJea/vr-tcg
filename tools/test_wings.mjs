// CH11 날개 (10503·10504) 스킬 검사: node tools/test_wings.mjs
import { readFileSync } from 'fs';
import { setSkillData, initPlayers, placeUnit, turnStart, turnEnd, useSkill, ACTIVE } from '../js/skills.js';
import { RULES, parseCSV, makeUnit, resolveAttack, setCardPool } from '../js/rules.js';
const rd = f => readFileSync(new URL('../data/' + f, import.meta.url), 'utf8');
const pool = [...parseCSV(rd('cards.csv')), ...parseCSV(rd('npc_cards.csv'))];
setCardPool(pool); setSkillData(JSON.parse(rd('skills.json')), JSON.parse(rd('combos.json')));
let fails = 0; const ok = (c, m) => { if (!c) { fails++; console.log('FAIL', m); } else console.log('ok  ', m); };
const C = id => pool.find(c => String(c.id) === id);
const fresh = () => { const A = { name: 'A', hp: 9999, field: [], hand: [], deck: [], mana: 0 }, B = { name: 'B', hp: 9999, field: [], hand: [], deck: [], mana: 0 }; initPlayers(A, B, A); return [A, B]; };
const lvl = (u, n) => { u.level = n; u.mp = u.maxMp = 999; };
ok(C('10503')?.cost === 55 && C('10504')?.cost === 55, '코스트 55');
let [A, B] = fresh();
const L = placeUnit(A, C('10504'), makeUnit); lvl(L, 10);
const foes = ['10051', '10053', '10054'].map(id => placeUnit(B, C(id), makeUnit));
ACTIVE['내가 느꼈던 어둠'](L, A, B);
ok(foes.every(t => t.st.burn?.t === 3 && t.st.blind?.p === 0.2), '어둠: 화상 3턴 + 명중 저하');
foes[0].mp = 100; ACTIVE['네가 느껴야 하는 고독'](L, A, B);
ok(foes[0].mp === 50 && foes[0].st.blind.t === 2, '고독: MP 50% + 명중 저하 2턴');
// 명중 저하: 기본 공격 빗나감 비율
foes[0].undying = true; let miss = 0; for (let i = 0; i < 2000; i++) { const t = foes[0]; t.st.blind = { kind: 'blind', p: 0.2, t: 2 }; t.canAttack = true; t.hp = t.maxHp; L.hp = L.maxHp; L.st = {}; const ev = resolveAttack(B, A, t, L); if (ev.some(e => e.blind)) miss++; }
ok(miss > 300 && miss < 520, `명중 저하 빗나감 ${(miss / 20).toFixed(1)}%`);
ACTIVE['암흑 소환'](L, A, B);
const R = A.field.find(x => String(x.base.id) === '10503');
ok(R && R.level === 10 && R.hp === R.maxHp && R.st.wingSummon?.t >= 2, '소환: 오른쪽 날개 Lv 같음 · HP 100%');
ok(ACTIVE['암흑 소환'](L, A, B) === false, '이미 있으면 실패');
foes.forEach(t => { t.st = {}; });R.mp = 999; ACTIVE['모두가 느끼는 지옥'](R, A, B);
ok(foes.every(t => t.st.dot?.pct === 0.03 && t.st.dot.t === 3), '지옥: 중독 -3% 3턴');
const g0 = A.grave.length; turnEnd(A); turnEnd(A); ok(A.field.includes(R), '2번 턴 종료까지 유지'); turnEnd(A);
ok(!A.field.includes(R) && A.grave.length === g0, '2턴 뒤 소환 종료 (무덤 X)');
// 처치 XP 없음
ACTIVE['암흑 소환'](L, A, B); const R2 = A.field.find(x => String(x.base.id) === '10503'); const k = B.field[0], xp0 = k.xp; R2.hp = 1; R2.st = {};
k.canAttack = true; k.st = {}; resolveAttack(B, A, k, R2); ok(!A.field.includes(R2) && k.xp - xp0 < 10 && A.grave.length === g0, '소환 처치: 무덤·처치 XP 없음');
L.hp = 100; turnStart(A); ok(L.hp >= 100 + Math.round(L.maxHp * 0.3) - 1 || L.hp === L.maxHp, '아프지 않아요: 매 턴 30%');
console.log(fails ? `${fails} FAIL` : 'ALL OK'); process.exit(fails ? 1 : 0);
