// 수동 전투 코어: 토벌·PvP — 기록 재생 = 같은 결과 · 전부 AUTO 입력 = 자동 전투와 같음 · 잘못된 입력 무시 · 15턴 · 피해 상한
import fs from 'fs';
import { parseCSV, setCardPool, attackTargets } from '../js/rules.js';
import { setSkillData, skillState } from '../js/skills.js';
import { snapCard, runMatch, runSeries, manualMatch, roundSeed } from '../js/pvp-core.js';
import { runRaid, manualRaid, hitCap, RAID_TURNS } from '../js/raid-core.js';
const pool = parseCSV(fs.readFileSync('data/cards.csv', 'utf8')); setCardPool(pool);
setSkillData(JSON.parse(fs.readFileSync('data/skills.json')), JSON.parse(fs.readFileSync('data/combos.json')));
const by = id => pool.find(c => String(c.id) === String(id));
let fails = 0; const ok = (c, m) => { console.log((c ? 'ok   ' : 'FAIL ') + m); if (!c) { fails++; process.exitCode = 1; } };
const deck = (o, lv = 20) => pool.slice(o % 420, o % 420 + 5).map(c => snapCard({ id: c.id, level: lv }, by));
// 사람 흉내: 시드 난수(테스트 고정)로 스킬/공격/턴종료를 고름
const human = k => { let x = k; const rnd = () => ((x = (x * 1103515245 + 12345) >>> 0) / 4294967296); return st => {
  const ready = st.A0.map((u, i) => [u, i]).filter(([u]) => u.hp > 0 && st.A.field.includes(u) && u.canAttack);
  if (!ready.length || rnd() < 0.08) return { k: 'end' };
  const [u, i] = ready[Math.floor(rnd() * ready.length)];
  const sk = u.sk.filter(s => skillState(u, s).ok);
  if (sk.length && rnd() < 0.5) return { k: 'skill', i, s: sk[Math.floor(rnd() * sk.length)].name };
  const tg = attackTargets(st.A, st.B, u).units; if (!tg.length) return { k: 'end' };
  return { k: 'atk', i, t: st.B0.indexOf(tg[Math.floor(rnd() * tg.length)]) };
}; };
const drive = (s, pick) => { let x = s.next(); let g = 0; while (!x.done && g++ < 5000) x = s.next(pick(x.value)); return x.value; };
let same = 0, autoSame = 0, rSame = 0, rAuto = 0, capOk = true, turnsOk = true; const N = 25;
for (let k = 1; k <= N; k++) {
  const A = deck(k * 17), B = deck(k * 29), seed = k * 4567;
  const s = manualMatch(A, B, seed), res = drive(s, human(k));
  same += JSON.stringify(runMatch(A, B, seed, null, s.acts)) === JSON.stringify(res);
  autoSame += JSON.stringify(drive(manualMatch(A, B, seed), () => ({ k: 'auto' }))) === JSON.stringify(runMatch(A, B, seed));
  const stg = 1 + k % 6, df = ['normal', 'hard', 'abyss'][k % 3];
  const rs = manualRaid(A, stg, df, seed, by), rr = drive(rs, human(k + 99));
  rSame += JSON.stringify(runRaid(A, stg, df, seed, by, null, rs.acts)) === JSON.stringify(rr);
  rAuto += JSON.stringify(drive(manualRaid(A, stg, df, seed, by), () => ({ k: 'auto' }))) === JSON.stringify(runRaid(A, stg, df, seed, by));
  if (rr.damage > rr.hits * hitCap(stg)) capOk = false; if (rr.turns > RAID_TURNS) turnsOk = false;
}
ok(same === N, `PvP 수동: 기록 재생 = 같은 결과 (${same}/${N})`);
ok(autoSame === N, `PvP 수동 전부 AUTO = 자동 전투 (${autoSame}/${N})`);
ok(rSame === N, `토벌 수동: 기록 재생 = 같은 피해 (${rSame}/${N})`);
ok(rAuto === N, `토벌 수동 전부 AUTO = 자동 전투 (${rAuto}/${N})`);
ok(capOk && turnsOk, '토벌 수동도 행동당 피해 상한 · 15턴');
// 잘못된 입력은 무시 (기록 안 됨) · 화면 쪽 Math.random 은 전투에 영향 없음
{ const A = deck(50), B = deck(80), s = manualMatch(A, B, 77); let x = s.next(); const before = s.acts.length;
  x = s.next({ k: 'atk', i: 99, t: 0 }); x = s.next({ k: 'skill', i: 0, s: '없는스킬' });
  ok(s.acts.length === before && x.value?.ask, '없는 카드·스킬 입력 무시');
  Math.random(); Math.random();
  const r1 = drive(s, () => ({ k: 'auto' })), r2 = runMatch(A, B, 77, null, s.acts);
  ok(JSON.stringify(r1) === JSON.stringify(r2), '중간에 Math.random 써도 재생 결과 같음'); }
// 3v3 시리즈 재생
{ const As = [deck(3), deck(6), deck(9)], Bs = [deck(12), deck(15), deck(18)], seed = 999, acts = [], res = [];
  for (let i = 0; i < 3; i++) { const s = manualMatch(As[i], Bs[i], roundSeed(seed, i)); res.push(drive(s, human(i + 5)).win); acts.push(s.acts); }
  const want = (() => { let w = 0, l = 0; for (const x of res) { x ? w++ : l++; if (w >= 2 || l >= 2) break; } return [w, l]; })();
  const r = runSeries('3v3', As, Bs, seed, false, acts); ok(r.wins === want[0] && r.losses === want[1], `3v3 수동 기록 재생 ${r.wins}-${r.losses}`); }
// 전투 화면(view) 멈춤은 결과에 영향 없음 · 마나 0 · 구역 전쟁 수동 재생
{ const { warSession, runWar, warDeck, WAR_ROLES } = await import('../js/war-core.js');
  let okV = 0, okM = true, okW = 0;
  for (let k = 1; k <= 10; k++) {
    const A = deck(k * 31), B = deck(k * 37), seed = k * 777;
    const v = manualMatch(A, B, seed, null, { view: true, manual: true }); let x = v.next(), g = 0;
    while (!x.done && g++ < 20000) { if (x.value.A && (x.value.A.mana || x.value.B.mana)) okM = false; x = v.next(x.value.ask ? human(k)(x.value) : undefined); }
    okV += JSON.stringify(runMatch(A, B, seed, null, v.acts)) === JSON.stringify(x.value);
    const wa = warDeck(A.map((c, i) => ({ uid: 'a' + i, id: c.id, level: 20 })), by, WAR_ROLES.atk), wb = warDeck(B.map((c, i) => ({ uid: 'b' + i, id: c.id, level: 20 })), by, WAR_ROLES.def);
    const w = warSession(wa, wb, seed, null, { view: true }); let y = w.next(); const h = human(k + 3);
    while (!y.done) y = w.next(y.value.ask ? h(y.value) : undefined);
    okW += JSON.stringify(runWar(wa, wb, seed, null, w.acts)) === JSON.stringify(y.value);
  }
  ok(okV === 10, `화면 모드 수동 PvP 재생 일치 (${okV}/10)`); ok(okM, 'PvP·전쟁 마나 항상 0'); ok(okW === 10, `구역 전쟁 수동 재생 일치 (${okW}/10)`); }
console.log(fails ? `FAIL ${fails}` : 'ALL PASS');
