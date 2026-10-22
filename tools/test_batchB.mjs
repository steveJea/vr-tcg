// Batch B 검증: node tools/test_batchB.mjs
import './seed_rng.mjs';   // 고정 시드 난수 (치명타·회피·속성 패시브 등 확률 결과 고정)
import fs from 'fs';
import { parseCSV, makeUnit, resolveAttack, calcDamage, RULES, buildDeck, genderMult, baseEvade, attackTargets, allowedGrades, GRADES, doAction, setCardPool } from '../js/rules.js';
import { setSkillData, initPlayers, placeUnit, skillsOf, setRng, TURN, refreshAll, setEmitter, damageUnit, evadeChance, rollEvade, aiPickSkill, checkDeath } from '../js/skills.js';
setEmitter(() => {});
setSkillData(JSON.parse(fs.readFileSync('data/skills.json')), JSON.parse(fs.readFileSync('data/combos.json')));
const cards = parseCSV(fs.readFileSync('data/cards.csv', 'utf8')); const C = id => cards.find(c => String(c.id) === id);
setCardPool(cards);
const mk = (c, uid) => { const u = makeUnit(c, uid); u.sk = skillsOf(c.id); return u; };
let fails = 0; const ok = (n, c, extra = '') => { console.log((c ? 'PASS ' : 'FAIL ') + n + (extra ? ' — ' + extra : '')); if (!c) { fails++; process.exitCode = 1; } };
const sides = (aIds, bIds, lv = 1) => {
  const a = { name: 'A', field: [], hand: [], deck: [], mana: 99, hp: 3000, maxHp: 3000, turnsTaken: 9 }, b = { name: 'B', field: [], hand: [], deck: [], mana: 99, hp: 3000, maxHp: 3000, turnsTaken: 9 };
  initPlayers(a, b); TURN.p = a;
  const A = aIds.map(id => placeUnit(a, C(id), mk)), B = bIds.map(id => placeUnit(b, C(id), mk));
  [...A, ...B].forEach(u => { u.level = lv; u.canAttack = true; }); refreshAll(a); refreshAll(b);
  return { a, b, A, B };
};
const pick = (pred) => cards.find(c => pred(c) && !skillsOf(c.id).length);
const M = pick(c => c.gender === 'MALE' && c.grade === 'NORMAL' && c.class === 'FIRE');
const F = pick(c => c.gender === 'FEMALE' && c.grade === 'NORMAL' && c.class === 'FIRE');
const F2 = pick(c => c.gender === 'FEMALE' && c.grade === 'NORMAL' && c.class === 'FIRE' && c.id !== F.id);
const W = pick(c => c.class === 'WIND' && c.grade === 'NORMAL'), I = pick(c => c.class === 'ICE' && c.grade === 'NORMAL');

// ---- 2-3 등급 확률 ----
{ const cnt = {}; let n = 0, maxMr = 0, dup = 0;
  for (let i = 0; i < 3000; i++) { const d = buildDeck(cards); n += d.length; maxMr = Math.max(maxMr, d.filter(c => c.grade === 'MYTHIC RARE').length); if (new Set(d.map(c => c.id)).size !== d.length) dup++; for (const c of d) cnt[c.grade] = (cnt[c.grade] || 0) + 1; }
  const r = g => (cnt[g] || 0) / n;
  const near = (g, p, tol) => Math.abs(r(g) - p) <= tol;
  ok('덱 30장', n === 3000 * 30);
  ok('확률 N50 R30 HR11 SR5 UR3 (±1.5%p)', near('NORMAL', .5, .015) && near('RARE', .3, .015) && near('HIGH RARE', .11, .01) && near('SUPER RARE', .05, .01) && near('ULTRA RARE', .03, .008), GRADES.map(g => `${g} ${(r(g) * 100).toFixed(2)}%`).join(', '));
  ok('MR ≈1% 슬롯 (덱당 최대 1장 상한 때문에 약간 낮음)', r('MYTHIC RARE') > 0.004 && r('MYTHIC RARE') <= 0.011, (r('MYTHIC RARE') * 100).toFixed(2) + '%');
  ok('MR 덱당 최대 1장', maxMr <= 1);
  ok('덱 내 중복 없음 (전 등급)', dup === 0); }
// ---- 2-1 등급 룰 ----
{ const g = allowedGrades({ grades: ['NORMAL'] }); const d = buildDeck(cards, Math.random, g); ok('N만: 30장 전부 N', d.length === 30 && d.every(c => c.grade === 'NORMAL')); }
{ const g = allowedGrades({ grades: ['NORMAL', 'RARE', 'HIGH RARE'] }); let bad = 0, hr = 0, tot = 0; for (let i = 0; i < 500; i++) { const d = buildDeck(cards, Math.random, g); bad += d.filter(c => !g.has(c.grade)).length; hr += d.filter(c => c.grade === 'HIGH RARE').length; tot += d.length; }
  ok('HR 이하: 상위 등급 없음', bad === 0); ok('HR 이하: 재정규화 HR ≈ 11/91 = 12.1%', Math.abs(hr / tot - 0.11 / 0.91) < 0.015, (hr / tot * 100).toFixed(1) + '%'); }
{ const g = allowedGrades({ grades: GRADES.filter(x => x !== 'NORMAL') }); let n = 0, r = 0, tot = 0; for (let i = 0; i < 500; i++) { const d = buildDeck(cards, Math.random, g); n += d.filter(c => c.grade === 'NORMAL').length; r += d.filter(c => c.grade === 'RARE').length; tot += d.length; }
  ok('N 제외: N 없음, R ≈ 60%', n === 0 && Math.abs(r / tot - 0.6) < 0.03, (r / tot * 100).toFixed(1) + '%'); }
{ const g = allowedGrades({ grades: ['ULTRA RARE'] }); const d = buildDeck(cards, Math.random, g); ok('UR만(16종 < 30장): 중복 허용으로 30장 채움', d.length === 30 && d.every(c => c.grade === 'ULTRA RARE')); }
ok('전체 선택 = 제한 없음(null)', allowedGrades({ grades: [...GRADES] }) === null && allowedGrades({ grades: null }) === null);
{ const g = allowedGrades({ grades: ['NORMAL'] }); const p = { hand: buildDeck(cards, Math.random, g).slice(0, 5), deck: [], field: [], grave: [], mana: 99, pool: cards.filter(c => g.has(c.grade)), used: {} };
  doAction('shuffle', p); ok('패 섞기도 허용 등급에서만', p.hand.length === 5 && p.hand.every(c => c.grade === 'NORMAL')); }

// ---- 7-1 성별 피해 ----
ok('genderMult 남→여 0.85 / 여→남 1.05 / 동성 1', genderMult(M, F) === 0.85 && genderMult(F, M) === 1.05 && genderMult(M, M) === 1 && genderMult(F, F2) === 1 && genderMult(M, null) === 1);
{ const { A, B } = sides([M.id], [F.id]); setRng(() => 0.99); const t = B[0]; t.maxHp = t.hp = 99999; const h = t.hp; damageUnit(t, 1000, A[0]); ok('damageUnit 남→여 1000 → 850', h - t.hp === 850, String(h - t.hp)); }
{ const { A, B } = sides([F.id], [M.id]); setRng(() => 0.99); const t = B[0]; t.maxHp = t.hp = 99999; const h = t.hp; damageUnit(t, 1000, A[0]); ok('damageUnit 여→남 1000 → 1050', h - t.hp === 1050, String(h - t.hp)); }
{ const { A, B } = sides([F.id], [F2.id]); setRng(() => 0.99); const t = B[0]; t.maxHp = t.hp = 99999; const h = t.hp; damageUnit(t, 1000, A[0]); ok('damageUnit 여→여 그대로', h - t.hp === 1000); }
{ const { a, b, A, B } = sides([M.id], [F.id]); setRng(() => 0.99); const t = B[0]; t.maxHp = t.hp = 99999; const h = t.hp; resolveAttack(a, b, A[0], t);
  const exp = Math.round(calcDamage(A[0].card, t.card) * 0.85); ok('기본 공격 남→여 85%', h - t.hp === exp, `${h - t.hp} vs ${exp}`); }
{ const { a, b, A, B } = sides([M.id], [F.id]); setRng(() => 0.99); const u = A[0], t = B[0]; t.maxHp = t.hp = 99999; u.maxHp = u.hp = 99999; const h = u.hp; resolveAttack(a, b, u, t);
  const exp = Math.round(Math.round(calcDamage(t.card, u.card) * RULES.COUNTER_RATIO) * 1.05); ok('반격 여→남 105%', Math.abs((h - u.hp) - exp) <= 1, `${h - u.hp} vs ${exp}`); }
{ const { a, b, A } = sides([M.id], [F.id]); setRng(() => 0.99); const h = b.hp; b.field = []; resolveAttack(a, b, A[0], null); ok('진영 피해는 성별 영향 없음', h - b.hp === calcDamage(A[0].card, null), `${h - b.hp}`); }

// ---- 7-2 회피 ----
ok('속성 기본 회피 바람 7% / 그 외 4%', baseEvade(W) === 0.07 && baseEvade(I) === 0.04 && baseEvade(F) === 0.04);
{ const { a, b, A, B } = sides([M.id], [W.id]); const t = B[0]; t.maxHp = t.hp = 9999;
  setRng(() => 0.065); let ev = resolveAttack(a, b, A[0], t); ok('바람: 0.065 < 7% → 회피', ev[0]?.type === 'evade');
  A[0].canAttack = true; setRng(() => 0.105); ev = resolveAttack(a, b, A[0], t); ok('바람: 0.105 → 명중', ev[0]?.type === 'hit'); }
{ const { a, b, A, B } = sides([M.id], [I.id]); const t = B[0]; t.maxHp = t.hp = 9999;
  setRng(() => 0.035); let ev = resolveAttack(a, b, A[0], t); ok('얼음: 0.035 < 4% → 회피', ev[0]?.type === 'evade');
  A[0].canAttack = true; setRng(() => 0.045); ev = resolveAttack(a, b, A[0], t); ok('얼음: 0.045 → 명중', ev[0]?.type === 'hit'); }
{ const { B } = sides([M.id], [W.id]); const t = B[0]; t.st.evade = { p: 0.4 }; ok('스킬 회피 40% + 바람 7% = 47%', Math.abs(evadeChance(t) - 0.47) < 1e-9);
  t.st.evade = { p: 0.9 }; ok('상한 60%', evadeChance(t) === 0.6); }

// ---- 2-4 카드 먼저 제거 ----
{ const { a, b, A, B } = sides([M.id], [F.id]); ok('기본: 상대 1장이면 진영 공격 가능', attackTargets(a, b, A[0]).hero === true);
  a.clearFirst = b.clearFirst = true; ok('카드 먼저 제거: 상대 1장 남으면 진영 불가', attackTargets(a, b, A[0]).hero === false);
  b.field = []; ok('카드 먼저 제거: 0장이면 진영 공격', attackTargets(a, b, A[0]).hero === true); }
{ // 상대 카드가 없으면 적 대상 스킬 사용 안 함
  const ids = Object.keys(JSON.parse(fs.readFileSync('data/skills.json'))).filter(id => C(id));
  let bad = 0, checked = 0;
  for (const id of ids) { const { b, A } = sides([id], [], 10); b.field = []; const u = A[0]; u.mp = u.maxMp; setRng(() => 0.5);
    for (let k = 0; k < 4; k++) { const s = aiPickSkill(u); if (s) { checked++; if (/적/.test(s.target || '') && !/본진|진영/.test(s.desc || '')) { bad++; console.log('   ', C(id).name, s.name, s.target); } } } }
  ok('상대 카드 0장: AI가 적 카드 대상 스킬을 고르지 않음', bad === 0, `선택된 스킬 ${checked}회`); }

// ---- 7-3 처치 시 MP 흡수 (기존) ----
{ const { a, b, A, B } = sides([M.id], [F.id]); setRng(() => 0.99); const u = A[0], t = B[0]; t.hp = 1; t.mp = 50; u.mp = 0; resolveAttack(a, b, u, t); ok('처치 시 MP 20% 흡수 (최소 3)', u.mp >= 10, `mp ${u.mp}`); }

// ---- 에셋 ----
{ const idx = new Set(JSON.parse(fs.readFileSync('data/voice/index.json')));
  const miss = [...idx].filter(k => !fs.existsSync(`data/voice/${k}.mp3`)); ok('voice index 파일 모두 존재', !miss.length, miss.join(','));
  ok('등장 보이스 _0 13장 · 승리 보이스 _9 13장', [...idx].filter(k => k.endsWith('_0')).length === 13 && [...idx].filter(k => k.endsWith('_9')).length === 13);
  ok('2000000012_* 없음 (하지혜 = 2000000017)', ![...idx].some(k => k.startsWith('2000000012_')) && idx.has('2000000017_0') && fs.existsSync('data/fx/2000000017_0.webp')); }
{ const ev = JSON.parse(fs.readFileSync('data/events.json'));
  ok('events.json: 이벤트 파일 존재', ev.events.every(e => (!e.image || fs.existsSync(e.image)) && (!e.voice || fs.existsSync(e.voice))));
  ok('유리x나리 카드 id 유효', ev.events[0].sides.flat().every(id => C(id)), ev.events[0].sides.flat().map(id => C(id)?.name).join(','));
  ok('entry.fx에 이성호 1002400378 포함', ev.entry.fx.includes('1002400378'));
  ok('entry.fx 이미지 존재', ev.entry.fx.every(id => fs.existsSync(`data/fx/${id}_0.webp`))); }
{ const se = { 1: 4, 2: 2, 3: 4, 4: 3, 5: 1, 6: 1, 7: 3 }; const miss = [];
  for (const [c, n] of Object.entries(se)) for (let i = 1; i <= n; i++) { const f = `audio/se/00${c}_0${i}.mp3`; if (!fs.existsSync(f)) miss.push(f); }
  ok('SE 18개 파일', !miss.length, miss.join(',')); }
console.log(fails ? `${fails} FAIL` : 'ALL PASS');
