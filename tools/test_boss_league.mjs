// 보스리그 (pvp-core boss 모드) 테스트: 진영 HP 0 = 결과, 수비대장 안 쓰러짐, 같은 seed 재현, 수동 기록 재생
import './seed_rng.mjs';
import { readFileSync } from 'fs';
import { setSkillData } from '../js/skills.js';
import { parseCSV, setCardPool } from '../js/rules.js';
import { runMatch, runSeries, snapCard, deckCheck, manualMatch } from '../js/pvp-core.js';
const rd = p => readFileSync(new URL(p, import.meta.url), 'utf8');
const pool = parseCSV(rd('../data/cards.csv')); setCardPool(pool); setSkillData(JSON.parse(rd('../data/skills.json')), JSON.parse(rd('../data/combos.json')));
const byId = id => pool.find(c => String(c.id) === String(id));
let fails = 0; const ok = (c, m) => { if (!c) { fails++; console.log('FAIL', m); } else console.log('ok  ', m); };
const pick = g => pool.filter(c => c.grade === g);
const deck = (k, lv) => [pick('HIGH RARE')[k], ...pick('SUPER RARE').slice(k * 4, k * 4 + 4)].map(c => snapCard({ id: c.id, level: lv }, byId));
let ends = 0, err = 0; const N = 30;
for (let i = 1; i <= N; i++) { try { const r = runMatch(deck(i % 3, 30), deck((i + 1) % 3, 30), i * 31, null, null, { boss: true }); if (typeof r.win === 'boolean') ends++; } catch (e) { err++; console.log(e); } }
ok(!err && ends === N, `보스리그 ${N}판 오류 없음`);
ok(JSON.stringify(runSeries('boss', [deck(0, 30)], [deck(1, 30)], 99)) === JSON.stringify(runSeries('boss', [deck(0, 30)], [deck(1, 30)], 99)), '같은 seed 재현');
ok(deckCheck([byId(pick('SUPER RARE')[0].id)], 'open', 'boss').includes('HR'), '첫 장 HR 이하 검사');
let same = 0; for (let i = 1; i <= 10; i++) { const s = manualMatch(deck(0, 30), deck(2, 30), i, null, { boss: true }); let x = s.next(); while (!x.done) x = s.next(x.value?.ask ? { k: 'auto' } : undefined);
  same += JSON.stringify(runMatch(deck(0, 30), deck(2, 30), i, null, s.acts, { boss: true })) === JSON.stringify(x.value); }
ok(same === 10, `수동 기록 재생 일치 (${same}/10)`);
console.log(fails ? `${fails} FAIL` : 'ALL PASS'); process.exit(fails ? 1 : 0);
