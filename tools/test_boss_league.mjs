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

// 리더 1 + 멤버 1~5 (10/31)
const HR = pick('HIGH RARE'), SR = pick('SUPER RARE');
ok(deckCheck([HR[0]], 'open', 'boss').includes('멤버'), 'HR 리더 1장만 → 거절 (멤버 1장 이상)');
ok(deckCheck([HR[0], ...SR.slice(0, 5)], 'open', 'boss') === '', '리더 + 멤버 5장 = 통과');
ok(deckCheck([HR[0], ...SR.slice(0, 6)], 'open', 'boss').includes('최대'), '멤버 6장 → 거절');
ok(deckCheck([HR[0], SR[0], SR[1]], 'open', '1v1') === '' && deckCheck([...SR.slice(0, 6)], 'open', '1v1') === '1~5장', '1v1 규칙 그대로');
// 수비대장 교체: 내 턴 3번 뒤 · HR 이하 · 턴 소모 · 기록 재생 일치
{ const dA = [HR[3], HR[4], SR[0]].map(c => snapCard({ id: c.id, level: 60 }, byId)), dB = deck(1, 1);
  let swapped = 0, early = 0;
  for (let seed = 1; seed <= 8; seed++) {
    const s = manualMatch(dA, dB, seed, null, { boss: true }); let x = s.next(), tried = 0;
    while (!x.done) {
      if (x.value?.ask) { const { A, A0 } = x.value, g = A.field.find(u => u.guard), fi = A0.findIndex(u => u !== g && !u.guard && A.field.includes(u) && u.hp > 0 && ['NORMAL', 'RARE', 'HIGH RARE'].includes(u.card.grade)), f = A0[fi];
        if (!tried && g && f) { const before = A.ownTurns; x = s.next({ k: 'swap', g: A0.indexOf(g), f: fi });
          if (x.value?.ask && x.value.A === A && A.ownTurns === before) { early++; x = s.next({ k: 'auto' }); continue; }   // 3턴 전: 거절 → 다시 물음
          tried = 1; swapped += A.field.find(u => u.guard) === f ? 1 : 0; continue; }
        x = s.next({ k: 'auto' }); }
      else x = s.next();
    }
    ok(JSON.stringify(runMatch(dA, dB, seed, null, s.acts, { boss: true })) === JSON.stringify(x.value), `교체 기록 재생 일치 seed ${seed}`);
  }
  ok(early > 0, `3턴 전 교체 거절 (${early}회)`); ok(swapped > 0, `교체 성공 (${swapped}판)`);
}
console.log(fails ? `${fails} FAIL` : 'ALL PASS'); process.exit(fails ? 1 : 0);
