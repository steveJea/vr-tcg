// 전체 대상 확률 상태이상: 대상마다 따로 판정 (10/31) — node tools/test_status_per_target.mjs
import fs from 'fs';
import { parseCSV, makeUnit, setCardPool } from '../js/rules.js';
import { setSkillData, initPlayers, placeUnit, ACTIVE, setRng } from '../js/skills.js';
const rd = f => fs.readFileSync(new URL('../data/' + f, import.meta.url), 'utf8');
const pool = [...parseCSV(rd('cards.csv')), ...parseCSV(rd('npc_cards.csv'))]; setCardPool(pool);
setSkillData(JSON.parse(rd('skills.json')), JSON.parse(rd('combos.json')));
const C = id => pool.find(c => String(c.id) === id);
let fails = 0; const ok = (c, m) => { if (!c) { fails++; console.log('FAIL', m); } else console.log('ok  ', m); };
const fresh = casterId => { const A = { name: 'A', hp: 9999, field: [], hand: [], deck: [], mana: 0 }, B = { name: 'B', hp: 9999, field: [], hand: [], deck: [], mana: 0, actionLock: 0 }; initPlayers(A, B, A);
  const u = placeUnit(A, C(casterId), makeUnit); const fs = ['10051', '10053', '10054'].map(i => placeUnit(B, { ...C(i), HP: 99999 }, makeUnit)); return { A, B, u, fs }; };
const seq = arr => { let i = 0; setRng(() => arr[i++ % arr.length]); };
for (const [name, kind] of [['아름다운 고통의 키스(眞)', 'confuse'], ['더 울어, 예쁘게!(眞)', 'disrupt']]) {
  const { A, B, u, fs } = fresh('10325'); seq([0.1, 0.9, 0.1]); ACTIVE[name](u, A, B);
  ok(fs[0].st[kind] && !fs[1].st[kind] && fs[2].st[kind], `${name}: 대상마다 판정 (걸림·안 걸림·걸림)`);
  ok(B.actionLock >= 1, `${name}: 고유기술 봉인은 항상`);
  const r = fresh('10325'); seq([0.99]); ACTIVE[name](r.u, r.A, r.B); ok(r.fs.every(t => !t.st[kind]) && r.B.actionLock >= 1, `${name}: 전부 실패해도 봉인`);
}
// 확률 분포: 30% 키스 → 3명 중 걸린 수가 0~3 고르게 섞임 (예전: 0 또는 3만)
setRng(Math.random); const cnt = [0, 0, 0, 0];
for (let i = 0; i < 2000; i++) { const { A, B, u, fs } = fresh('10325'); u.level = 1; ACTIVE['아름다운 고통의 키스'](u, A, B); cnt[fs.filter(t => t.st.confuse).length]++; }
ok(cnt[1] > 500 && cnt[2] > 200, `키스 30%: 걸린 수 분포 ${cnt.join('/')}`);
const g = fresh('10325'); seq([0.1, 0.9, 0.9]); ACTIVE['고갈될 예정입니다.'](g.u, g.A, g.B);
ok(g.fs[0].st.confuse && !g.fs[1].st.confuse && !g.fs[2].st.confuse, '고갈될 예정입니다.: 대상마다 판정');
console.log(fails ? `${fails} FAIL` : 'ALL OK'); process.exit(fails ? 1 : 0);
