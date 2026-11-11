// 2026-11-11 신규 카드 10511~10513·10520~10532 (+NPC 10514·10516~10518) 스킬 검사: node tools/test_newcards_1111.mjs
import { readFileSync } from 'fs';
import { setSkillData, setEmitter, setRng, initPlayers, placeUnit, turnStart, turnEnd, refreshAll, useSkill, skillState, aiSkillScores, ACTIVE } from '../js/skills.js';
import { parseCSV, makeUnit, setCardPool } from '../js/rules.js';
const rd = f => readFileSync(new URL('../data/' + f, import.meta.url), 'utf8');
const cards = parseCSV(rd('cards.csv')), npcs = parseCSV(rd('npc_cards.csv')), pool = [...cards, ...npcs];
const SK = JSON.parse(rd('skills.json'));
setCardPool(pool); setSkillData(SK, JSON.parse(rd('combos.json'))); setEmitter(() => {});
let fails = 0; const ok = (c, m) => { if (!c) { fails++; console.log('FAIL', m); } else console.log('ok  ', m); };
const C = id => pool.find(c => String(c.id) === String(id));
const PLAY = ['10511', '10512', '10513', ...Array.from({ length: 13 }, (_, i) => String(10520 + i))];
const NPC = ['10514', '10516', '10517', '10518'];
let R = 0; setRng(() => R);
// 카드 데이터: 시트 기초stat 그대로 (80 초과 포함)
ok(PLAY.every(id => cards.some(c => String(c.id) === id)) && PLAY.every(id => !npcs.some(c => String(c.id) === id)), '플레이 카드 16장 cards.csv');
ok(C('10524').DEF === 88 && C('10525').ATK === 88 && C('10528').DEF === 83 && C('10528').PHY === 88 && C('10511').MOR === 85, '80 초과 스탯 시트 그대로');
ok(C('10513').base_id == 10512 && C('10520').age == 18 && C('10512').age == 22, '각성 base_id·나이');
// 스킬 데이터: 시트 44개 · fx 파일 · 액티브 구현
const all = [...PLAY, ...NPC].flatMap(id => (SK[id] || []).map(s => ({ id, s })));
ok(all.length === 44, `스킬 44개 (${all.length})`);
ok(all.every(({ id, s }) => s.fx && s.fx.startsWith(id + '_') && (() => { try { readFileSync(new URL('../data/fx/' + s.fx, import.meta.url)); return true; } catch { return false; } })()), 'fx 이미지 전부 존재');
ok(all.filter(x => x.s.mode === 'active').every(({ s }) => ACTIVE[s.name]), '액티브 전부 구현');
// 필드 준비
const M = pool.filter(c => c.gender === 'MALE' && c.HP > 0 && !PLAY.includes(String(c.id)) && !NPC.includes(String(c.id))).slice(0, 2);
const F = pool.filter(c => c.gender === 'FEMALE' && c.HP > 0 && !PLAY.includes(String(c.id)) && !NPC.includes(String(c.id)) && c.class !== 'LIGHT').slice(0, 2);
function fresh(id, foes = [...M, ...F], allies = []) {
  const A = { name: 'A', hp: 9999, field: [], hand: [], deck: [], grave: [], mana: 0 }, B = { name: 'B', hp: 9999, field: [], hand: [], deck: [], grave: [], mana: 0 };
  initPlayers(A, B, A);
  const u = placeUnit(A, C(id), makeUnit); u.level = 10; u.mp = 999; u.canAttack = true;
  const al = allies.map(c => placeUnit(A, c, makeUnit));
  const fs = foes.map(c => placeUnit(B, { ...c, HP: 99999 }, makeUnit)); refreshAll(A);
  return { A, B, u, fs, al };
}
const sk = (id, name) => SK[id].find(s => s.name === name);
const use = (u, id, name) => { u.canAttack = true; u.mp = 999; u.cd = {}; return useSkill(u, sk(id, name)); };
// 모든 액티브: 혼성 필드에서 오류 없이 실행 + 피해 or 상태
for (const { id, s } of all.filter(x => x.s.mode === 'active')) {
  R = 0.5; const { u, fs, al } = fresh(id);
  let r; try { r = use(u, id, s.name); } catch (e) { r = { ok: false, reason: e.message }; }
  ok(r.ok, `${id} ${s.name} 실행 ${r.ok ? '' : r.reason}`);
}
// 최수아
{ R = 0.99; const { A, u, al } = fresh('10511', [...M], [C('10051')]); use(u, '10511', '더 이상 슬픔은 없어'); ok([u, ...al].every(a => a.st.regen?.pct === 0.1 && a.st.regen.t >= 2), '최수아: 아군 전체 재생 10% 2턴');
  use(u, '10511', '더 이상 슬픔은 없어'); ok(Object.keys(u.st).filter(k => u.st[k].kind === 'regen').length === 1, '재생 1개만 (덮어쓰기)');
  use(u, '10511', '제발 떠나지 마'); ok([u, ...al].every(a => a.st.endure), '최수아: 아군 전체 불사'); }
// [각성] 고세연: 남성 없으면 사용 불가
{ const { u } = fresh('10513', [...F]); u.canAttack = true; ok(!skillState(u, sk('10513', '용서...못해...')).ok, '용서...못해...: 남성 적 없으면 불가');
  R = 0.99; const g = fresh('10513'); const top = g.fs.filter(t => t.base.gender === 'MALE').sort((a, b) => b.hp - a.hp)[0]; const hp0 = g.fs.map(t => t.hp); use(g.u, '10513', '용서...못해...');
  ok(g.fs.filter((t, i) => t.hp < hp0[i]).length === 1 && top.hp < hp0[g.fs.indexOf(top)], '용서...못해...: HP 최고 남성 1명'); }
// 고세연 남성 피해 +10%
{ R = 0.99; const g = fresh('10512', [M[0], M[0]].map((c, i) => i ? { ...c, gender: 'FEMALE' } : c)); const [m, w] = g.fs; g.u.raw.ATK = 3000; use(g.u, '10512', '언니가...잘할게'); ok(99999 - m.hp > 99999 - w.hp, `언니가...잘할게: 남성 피해 더 큼 (${99999 - m.hp} vs ${99999 - w.hp})`); }
// 조태진: 치명타 → 출혈, 치명타 없으면 출혈 없음
{ R = 0; const g = fresh('10526'); use(g.u, '10526', '터프한 사나이다'); const t = g.fs.sort((a, b) => b.card.cost - a.card.cost)[0]; ok(t.st.bleed, '터프한 사나이다: 치명타 시 출혈');
  R = 0.99; const h = fresh('10526'); use(h.u, '10526', '터프한 사나이다'); ok(!h.fs.some(x => x.st.bleed), '터프한 사나이다: 치명타 없으면 출혈 없음');
  const a0 = h.u.card.ATK; for (let i = 0; i < 15; i++) turnStart(h.A); ok(h.u.tjAtk === 10 && h.u.card.ATK > a0, `단단하게 간다: ATK +20% 상한 (${a0}→${h.u.card.ATK})`); }
// 이혜림: 마비 끝나면 혼란
{ R = 0; const g = fresh('10521'); use(g.u, '10521', '그녀를 따라와요'); const m = g.fs.find(t => t.base.gender === 'MALE'); ok(m.st.para && !g.fs.find(t => t.base.gender === 'FEMALE').st.para, '그녀를 따라와요: 남성만 마비');
  turnEnd(g.A); turnStart(g.B); turnEnd(g.B); ok(!m.st.para && m.st.confuse, '마비 종료 → 혼란'); ok(m.paraBlock > 0, '마비 연속 방지 (paraBlock)'); }
// 이수영: ATK/DEF 매 턴 +3%
{ R = 0.99; const g = fresh('10522'); const a0 = g.u.raw.ATK; use(g.u, '10522', '다음에 또 볼까요?'); const s = g.u.st['다음에 또 볼까요?']; ok(s && Math.abs(s.atk - 0.03) < 1e-9, '다음에 또 볼까요?: +3%'); turnEnd(g.A); turnStart(g.B); turnEnd(g.B); turnStart(g.A); ok(Math.abs(g.u.st['다음에 또 볼까요?'].atk - 0.06) < 1e-9 && g.u.st.regen?.pct === 0.1, '다음 턴 +6% · 재생 유지'); }
// 천혜영 오라
{ const g = fresh('10523'); const t = g.fs[0]; const on = { ...t.mods }; g.u.level = 1; refreshAll(g.A); const off = { ...t.mods }; ok(Math.abs(off.atk - on.atk - 0.1) < 1e-9 && Math.abs(off.def - on.def - 0.1) < 1e-9, '쉽게 보면 죽을 걸?: 적 ATK·DEF -10% (Lv5 해금)'); }
// 김수진 패시브
{ const g = fresh('10525'); const m = g.fs.find(t => t.base.gender === 'MALE'), w = g.fs.find(t => t.base.gender === 'FEMALE'); turnStart(g.B); turnStart(g.B); ok(m.sujin === 2 && m.hp === 99999 - 2 * Math.round(m.maxHp * 0.05) && w.hp === 99999, '하지만 넌 안 될 거야: 남성만 매 턴 5%·DEF 누적'); const on = m.mods.def; g.u.level = 1; refreshAll(g.A); ok(Math.abs(m.mods.def - on - 0.04) < 1e-9, 'DEF -4% (2턴 누적)'); }
// 임재만: 딸 + 빛 아닌 적
{ const g = fresh('10517', [C('10325'), C('10324')]); const [y] = g.fs; turnStart(g.B); ok(y.hp === 99999 - 2 * Math.round(y.maxHp * 0.05), '임재만: 딸은 5%+5%');
  const h = fresh('10517', [C('10325')]); h.fs[0].hp = Math.round(h.fs[0].maxHp * 0.04); turnStart(h.B); ok(!h.B.field.length, '5% 미만이면 사망'); }
// 이동주 흡혈
{ R = 0.99; const g = fresh('10524'); g.u.hp = 10; use(g.u, '10524', '괴팍하지만 친절합니다.'); ok(g.u.hp > 10, `괴팍하지만 친절합니다.: 준 피해 5% 회복 (HP ${g.u.hp})`); }
// 천기철: 쓰러지면 남은 타격 무작위
{ R = 0.99; const g = fresh('10532'); const low = g.fs.filter(t => t.base.gender === 'MALE').sort((a, b) => a.hp - b.hp)[0]; low.hp = 1; use(g.u, '10532', '피곤한 저녁이 왔습니다'); ok(!g.B.field.includes(low) && g.fs.some(t => t !== low && t.hp < 99999), '피곤한 저녁: 사망 후 다른 적 타격'); }
// 김한철 동결 연속 방지
{ R = 0; const g = fresh('10527'); use(g.u, '10527', '가짜는 진짜를 못 이겨'); ok(g.fs.every(t => t.st.freeze || !g.B.field.includes(t)), '가짜는 진짜를 못 이겨: 동결'); }
// AI 점수: 회복/버프 스킬도 상황 따라 선택
{ const g = fresh('10511', [...M], [C('10051')]); g.al[0].hp = 1; g.u.hp = 1; ok(aiSkillScores(g.u, { noSave: true }).some(([s]) => s.name === '더 이상 슬픔은 없어'), 'AI: 다친 아군 있으면 재생 스킬 후보'); }
console.log(fails ? `${fails} FAIL` : 'ALL OK'); process.exit(fails ? 1 : 0);
