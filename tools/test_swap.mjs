import { swapField } from '../js/rules.js';
let fails = 0; const ok = (n, c) => { console.log((c ? 'PASS ' : 'FAIL ') + n); if (!c) { fails++; process.exitCode = 1; } };
const u = (uid, x = {}) => ({ uid, ...x });
const A = u(1), B = u(2), C = u(3), p = { field: [A, B, C] };
ok('1↔3 자리 바꾸기', swapField(p, A, C) && p.field.map(x => x.uid).join() === '3,2,1');
ok('같은 카드 불가', !swapField(p, B, B) && p.field.map(x => x.uid).join() === '3,2,1');
ok('다른 진영 카드 불가', !swapField(p, A, u(9)) && p.field.length === 3);
const boss = u(5, { undying: true }); p.field.push(boss);
ok('보스 불가', !swapField(p, A, boss) && p.field[3] === boss);
ok('객체(uid) 유지 — DOM 키 그대로', p.field.includes(A) && p.field.includes(C));
// game.js 연결 확인
import fs from 'fs'; const g = fs.readFileSync('js/game.js', 'utf8');
ok('onUnitClick 에서 swapField 사용', /swapField\(S\.me, cur, u\)/.test(g));
ok('공격 불가 카드 선택 시 공격 안 함', /a\?\.canAttack\) \{ attack/.test(g) && /a\?\.canAttack\) attack\('me', a, null\)/.test(g));
