// 장비·증표 전투 반영 검증 (PR3): node tools/test_gear_battle.mjs
import './seed_rng.mjs';
import fs from 'fs';
import { parseCSV, makeUnit, RULES } from '../js/rules.js';
RULES.GENDER_ON = false; RULES.EVADE_ON = false; RULES.CRIT_ON = false; RULES.EL_PASSIVE_ON = false;
import { setSkillData, initPlayers, placeUnit, skillsOf, useSkill, skillState, skillCd, skillMp, TURN, refreshAll, setRng, evadeChance } from '../js/skills.js';
import { applyGear, GEAR_MODE } from '../js/gear-core.js';
import { snapCard, runMatch } from '../js/pvp-core.js';
setSkillData(JSON.parse(fs.readFileSync('data/skills.json')), JSON.parse(fs.readFileSync('data/combos.json')));
const cards = parseCSV(fs.readFileSync('data/cards.csv', 'utf8')); const C = id => cards.find(c => String(c.id) === id);
const mk = (c, uid) => { const u = makeUnit(c, uid); u.sk = skillsOf(c.id); return u; };
let fails = 0; const ok = (n, c, extra = '') => { console.log((c ? 'PASS ' : 'FAIL ') + n + (extra ? ' — ' + extra : '')); if (!c) { fails++; process.exitCode = 1; } };
const sides = (aCards, bIds) => {
  const a = { name: 'A', field: [], hand: [], deck: [], mana: 99, hp: 3000, maxHp: 3000, turnsTaken: 9 }, b = { name: 'B', field: [], hand: [], deck: [], mana: 99, hp: 3000, maxHp: 3000, turnsTaken: 9 };
  initPlayers(a, b); TURN.p = a;
  const A = aCards.map(c => placeUnit(a, c, mk)), B = bIds.map(id => placeUnit(b, { ...C(id), HP: 20000 }, mk));
  [...A, ...B].forEach(u => { u.level = 10; u.mp = u.maxMp; u.canAttack = true; }); refreshAll(a);
  return { a, b, A, B };
};
const sk = (u, n) => u.sk.find(s => s.name === n);
const cast = (u, n) => { u.canAttack = true; u.mp = u.maxMp; u.cd = {}; return useSkill(u, sk(u, n)); };
const MIN = '10118', YUN = '10415', YURI = '10325';
const FOE = ['10074', '10080', '10445'];
const W4 = { stat: 'atk', pct: 8, plus: 0, opts: [{ opt: 'crit', v: 2 }] }, A5 = { stat: 'hp', pct: 10, plus: 5, opts: [{ opt: 'dmg_reduce', v: 5 }] };

// 1) 스탯 반영
{ const c = C(MIN), s = applyGear(c, { gear: [W4, A5] }, 'story'), p = applyGear(c, { gear: [W4, A5] }, 'pvp');
  ok('스토리: ATK +8%', s.ATK === Math.round(c.ATK * 1.08), `${c.ATK}→${s.ATK}`);
  ok('스토리: HP +10%×1.7(+5강)', s.HP === Math.round(c.HP * 1.17), `${c.HP}→${s.HP}`);
  ok('PvP: 절반 (ATK +4%)', p.ATK === Math.round(c.ATK * 1.04), `${p.ATK}`);
  ok('부옵션: 치명 +2%p, 피해 감소 5% (PvP 1%p·2.5%)', s.gear.crit === 0.02 && s.gear.dr === 5 && p.gear.crit === 0.01 && p.gear.dr === 2.5);
  ok('상한 45%', applyGear(c, { gear: [{ stat: 'atk', pct: 14, plus: 5 }, { stat: 'atk', pct: 14, plus: 5 }] }, 'story').ATK === Math.round(c.ATK * 1.45));
  ok('아케이드: 장비 없음', applyGear(c, { gear: [W4], sigil: 5 }, 'arcade').ATK === c.ATK && !applyGear(c, { gear: [W4], sigil: 5 }, 'arcade').sigil);
  ok('PvP 증표 +5 → +3으로', applyGear(c, { sigil: 5 }, 'pvp').sigil.plus === 3 && applyGear(c, { sigil: 5 }, 'raid').sigil.plus === 5);
  ok('모드 상수', GEAR_MODE.pvp.gear === 0.5 && GEAR_MODE.war.sigilMax === 3);
  const sn = snapCard({ id: MIN, level: 1, gear: [W4], sigil: 4 }, C, 'war'); ok('snapCard(war): 장비 50% + 증표 +3', sn.ATK === Math.round(C(MIN).ATK * 1.04) && sn.sigil.plus === 3);
}
// 2) 민홍기 무답무용: 증표 없으면 30%×5, +0 35%×6, +5 50%×7 쿨 3
{ setRng(() => 0.99);
  const dmg = sig => { const { A, B } = sides([applyGear(C(MIN), { sigil: sig }, 'story')], FOE); const t = B.reduce((m, x) => x.card.ATK > m.card.ATK ? x : m), h = t.hp; cast(A[0], '무답무용'); return { d: h - t.hp, u: A[0] }; };
  const d0 = dmg(null).d, d1 = dmg(0).d, r5 = dmg(5);
  ok('무답무용 +0 > 없음', d1 > d0 * 1.3, `${d0} → ${d1}`);
  ok('무답무용 +5 ≈ 350/150 배', r5.d > d0 * 2.1, `${d0} → ${r5.d}`);
  ok('무답무용 +2 이상 쿨 3, MP 30 그대로', skillCd(r5.u, sk(r5.u, '무답무용')) === 3 && skillMp(r5.u, sk(r5.u, '무답무용')) === 30);
}
// 3) 최윤희 제발 그냥 가줘: 쿨 9→6(+0)→3(+5), MP 90→75→50, 남성 없으면 +0 40% 대체
{ setRng(() => 0.99);
  const { A } = sides([applyGear(C(YUN), { sigil: 0 }, 'story')], FOE); const u = A[0], s = sk(u, '제발 그냥 가줘');
  ok('최윤희 +0: 쿨 6, MP 75', skillCd(u, s) === 6 && skillMp(u, s) === 75, `${skillCd(u, s)}/${skillMp(u, s)}`);
  const { A: A5 } = sides([applyGear(C(YUN), { sigil: 5 }, 'story')], FOE); const u5 = A5[0];
  ok('최윤희 +5: 쿨 3, MP 50', skillCd(u5, s) === 3 && skillMp(u5, sk(u5, '제발 그냥 가줘')) === 50);
  const fem = cards.filter(c => c.gender === 'FEMALE' && c.grade === 'RARE').slice(0, 2).map(c => String(c.id));
  const n = sides([C(YUN)], fem); ok('증표 없음: 남성 없으면 사용 불가', !skillState(n.A[0], sk(n.A[0], '제발 그냥 가줘')).ok);
  const g = sides([applyGear(C(YUN), { sigil: 0 }, 'story')], fem), hi = g.B.reduce((m, x) => x.card.cost > m.card.cost ? x : m), h = hi.hp;
  ok('증표 +0: 남성 없으면 코스트 최고 적 HP 40%', cast(g.A[0], '제발 그냥 가줘').ok !== false && h - hi.hp === Math.ceil(h * 0.4), `${h - hi.hp}`);
  const males = cards.filter(c => c.gender === 'MALE' && c.grade === 'RARE').slice(0, 3).map(c => String(c.id));
  const t2 = sides([applyGear(C(YUN), { sigil: 5 }, 'story')], males), hs = t2.B.map(x => x.hp); cast(t2.A[0], '제발 그냥 가줘');
  ok('증표 +5: 남성 2명 80%', t2.B.filter((x, i) => x.hp < hs[i]).length === 2);
}
// 4) 임유리: 천천히 찢는 사랑 40%×2 → +0 55%×2, +5 65%×3 · 키스 HP%·상한·혼란 확률
{ setRng(() => 0.99);
  const tear = sig => { const { A, B } = sides([applyGear(C(YURI), { sigil: sig }, 'story')], FOE); const h = B.map(x => x.hp); cast(A[0], '천천히 찢는 사랑'); return B.reduce((a, x, i) => a + h[i] - x.hp, 0); };
  const t0 = tear(null), t1 = tear(0), t5 = tear(5);
  ok('천천히 찢는 사랑 +0 > 없음', t1 > t0 * 1.25, `${t0} → ${t1}`); ok('+5 ≈ 195/80 배', t5 > t0 * 2.2, `${t5}`);
  const kiss = sig => { const { A, B } = sides([applyGear(C(YURI), { sigil: sig }, 'story')], FOE); const h = B.map(x => x.hp); cast(A[0], '더 울어, 예쁘게!'); return h[0] - B[0].hp; };
  ok('더 울어: 없음 180 상한 → +0 240 → +5 340', kiss(null) === 180 && kiss(0) === 240 && kiss(5) === 340, `${kiss(null)}/${kiss(0)}/${kiss(5)}`);
  const { A } = sides([applyGear(C(YURI), { sigil: 3 }, 'story')], FOE);
  ok('+3 키스 MP 35', skillMp(A[0], sk(A[0], '아름다운 고통의 키스')) === 35 && skillMp(A[0], sk(A[0], '천천히 찢는 사랑')) === 50);
  setRng(() => 0.45); const c = sides([applyGear(C(YURI), { sigil: 5 }, 'story')], FOE); cast(c.A[0], '아름다운 고통의 키스');
  ok('+5 혼란 60% (난수 0.45 → 걸림, 기본 30%면 안 걸림)', c.B.some(x => x.st.confuse));
  setRng(() => 0.45); const d = sides([C(YURI)], FOE); cast(d.A[0], '아름다운 고통의 키스'); ok('증표 없음: 0.45 → 안 걸림', !d.B.some(x => x.st.confuse));
}
// 5) 장비 부옵션: 회피·시작 MP
{ const { A } = sides([applyGear(C(MIN), { gear: [{ stat: 'evade', pct: 5, plus: 0 }, { stat: 'mp', pct: 5, plus: 0 }] }, 'story')], FOE);
  RULES.EVADE_ON = true; ok('회피 +5%p', Math.abs(evadeChance(A[0]) - (RULES.EVADE_BASE[C(MIN).class] ?? RULES.EVADE_DEFAULT) - 0.05) < 1e-9); RULES.EVADE_ON = false; }
// 6) 전투 끝까지 (증표 덱 PvP 한 판)
{ const deck = [MIN, YUN, YURI, '10051', '10060'].map(id => snapCard({ id, level: 30, gear: [W4, A5], sigil: 5 }, C, 'pvp'));
  const foe = ['10074', '10080', '10445', '10375', '10404'].map(id => snapCard({ id, level: 30 }, C, 'pvp'));
  let r; try { r = runMatch(deck, foe, 12345); } catch (e) { r = { err: e.message }; } ok('PvP 한 판 오류 없음', r && !r.err, r?.err || `win=${r.win}`); }
console.log(fails ? `\n${fails} FAIL` : '\nALL PASS');
