// ===== 비동기 PvP 전투 코어 (화면 없음 · 브라우저/노드 공용) =====
// 서버(pvp_start)가 준 seed + 양쪽 덱 스냅샷(서버가 story_progress 에서 읽은 id·level·ex·exb·boost·skillLv)으로
// 양쪽 모두 자동 전투 AI(auto-ai.js)로 싸운다. 같은 seed·같은 스냅샷이면 결과가 항상 같아 tools/pvp_verify.mjs 로 재검증 가능.
import { initPlayers, placeUnit, turnStart, turnEnd, useSkill, skillState, refreshAll, setRng, setEmitter, getEmitter, skillsOf } from './skills.js';
import { makeUnit, resolveAttack, refillMana, clearBuff, endTurnXp, skillLvPowerMult, attackTargets } from './rules.js';
import { autoNext, noteUsed } from './auto-ai.js';

export const MAX_TURNS = 40;
export const LEAGUES = { open: { label: '무제한', grades: null, costCap: null }, hr: { label: 'HR↓', grades: ['NORMAL', 'RARE', 'HIGH RARE'], costCap: 150 } };
export const MODES = { '1v1': { decks: 1, need: 1 }, '3v3': { decks: 3, need: 2 } };
// 스토리 카드 스탯 규칙 (js/story.js boosted 와 같음)
const LV_RATE = { 'NORMAL': 0.01, 'RARE': 0.02, 'HIGH RARE': 0.03, 'SUPER RARE': 0.04, 'ULTRA RARE': 0.05, 'MYTHIC RARE': 0.06, 'LEGENDARY RARE': 0.05 };
const PER_PT = { ATK: 1, HP: 5, DEF: 1 }, PT_FULL = 5;
const ptGain = (s, n) => { n = Math.max(0, n | 0); const k = PER_PT[s]; return k * Math.min(n, PT_FULL) + Math.floor(k * Math.max(0, n - PT_FULL) / 2); };
/** 스냅샷 한 장 → 전투 카드 */
export function snapCard(o, cardById) {
  const c = cardById(o.id); if (!c) return null;
  const lv = Math.max(1, o.level | 0 || 1), lp = Math.round((LV_RATE[c.grade] || 0.01) * (lv - 1) * 100), exb = Math.max(0, +o.exb || 0), ex = Math.max(0, o.ex | 0);
  const st = s => Math.round(c[s] * (1 + exb / 100) * (1 + lp / 100)) + ptGain(s, (o.boost || {})[s]);
  return { ...c, name: ex ? `[EX${ex}] ${c.name}` : c.name, ex, slv: lv, ATK: st('ATK'), HP: st('HP'), DEF: st('DEF'), power: Math.round((+c.power || 0) * (1 + exb / 100) * (1 + lp / 100) * skillLvPowerMult(skillsOf(o.id), o.skillLv)),
    ...(o.skillLv && typeof o.skillLv === 'object' ? { skillLv: { ...o.skillLv } } : {}) };
}
/** 덱 규칙 검사 (서버 _pvp_check 와 같은 규칙, 화면 안내용) */
export function deckCheck(cards, league) {
  const L = LEAGUES[league]; if (!L) return '리그';
  if (!cards.length || cards.length > 5) return '1~5장';
  if (new Set(cards.map(c => String(c.id))).size !== cards.length) return '중복';
  if (L.grades && cards.some(c => !L.grades.includes(c.grade))) return 'HR 이하만';
  if (L.costCap && cards.reduce((a, c) => a + (+c.cost || 0), 0) > L.costCap) return `코스트 ${L.costCap} 초과`;
  return '';
}
/** 32비트 시드 난수 (mulberry32) */
export function rngOf(seed) { let a = (Number(seed) >>> 0) || 1; return () => { a = (a + 0x6D2B79F5) >>> 0; let t = a; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; }
// ---- 수동 전투 공용 ----
// 전투를 제너레이터로 돌린다. 내(A) 턴에 행동이 필요하면 yield 로 화면에 묻고, 받은 입력을 acts 에 기록한다.
// 입력: { k:'skill', i, s } · { k:'atk', i, t } · { k:'auto' }(AI 가 하나 고름) · { k:'end' }. i·t = 처음 배치 순서(번호). 기록(acts)은 그대로 다시 넣으면 같은 결과.
// 난수는 한 걸음(next)마다만 seed 난수로 바꿔 끼움 → 화면이 Math.random 을 써도 전투 결과는 안 바뀜.
export function stepper(gen, r, sink = null) {
  return { events: sink, next(input) { const oldR = Math.random, oldE = getEmitter(); Math.random = r; setRng(r); setEmitter(sink ? e => sink.push(e) : () => {});
    try { return gen.next(input); } finally { Math.random = oldR; setRng(oldR); setEmitter(oldE); } } };
}
/** 기록(acts)을 순서대로 넣어 끝까지 (다 쓰면 턴 종료). 수동 판 재검증용 */
export function replay(st, acts) {
  let i = 0, x = st.next();
  for (let g = 0; !x.done && g < 20000; g++) x = st.next(!x.value?.ask ? undefined : i < (acts || []).length ? acts[i++] : { k: 'end' });   // anim 멈춤(화면용)은 입력 없이 넘김
  return x.value;
}
/** 내 턴 입력 하나 → 실제 행동 (안 되는 입력이면 null) */
export function resolveAct(inp, me, op, A0, B0, turn, autoPick) {
  if (!inp || inp.k === 'end') return null;
  if (inp.k === 'auto') { const a = autoPick(me, op, turn); return a ? { ...a, rec: a.kind === 'skill' ? { k: 'skill', i: A0.indexOf(a.u), s: a.s.name } : { k: 'atk', i: A0.indexOf(a.u), t: a.t ? B0.indexOf(a.t) : -1 } } : { none: true }; }
  const u = A0[inp.i | 0]; if (!u || u.hp <= 0 || !me.field.includes(u) || !u.canAttack) return false;
  if (inp.k === 'skill') { const s = u.sk.find(x => x.name === inp.s); if (!s || !skillState(u, s).ok) return false; return { kind: 'skill', u, s, rec: { k: 'skill', i: inp.i | 0, s: s.name } }; }
  if (inp.k === 'atk') { const t = B0[inp.t | 0]; if (!t || t.hp <= 0 || !attackTargets(me, op, u).units.includes(t)) return false; return { kind: 'attack', u, t, rec: { k: 'atk', i: inp.i | 0, t: inp.t | 0 } }; }
  return false;
}
/** 한 판 (제너레이터). manual=true 면 A 턴마다 yield { ask:true, A, B, A0, B0, t }
 *  opt.view: 행동마다 yield { anim:{ k, side, u, t, s, hits } } (전투 화면 연출용 · 결과에 영향 없음)
 *  opt.put(p, c): 카드 배치 (구역 전쟁: 현재 HP) · opt.maxTurns · opt.out(A, B, win, turns, aFirst)
 *  PvP·구역 전쟁은 마나 없음: 플레이어 마나는 항상 0 (소환·패 섞기·강화·아이템·용병 등 마나 행동 없음, 처치 마나도 0) */
export function* matchGen(deckA, deckB, r, rec = null, manual = false, acts = null, opt = {}) {
    const mk = name => ({ name, hp: 1, maxHp: 1, deck: [], hand: [], field: [], mana: 0, maxMana: 0, noBase: true, once: {}, grave: [], noMana: true });
    const A = mk('A'), B = mk('B'), aFirst = r() < 0.5, view = !!opt.view, MAXT = opt.maxTurns || MAX_TURNS;
    initPlayers(A, B, aFirst ? A : B);
    const put = opt.put || ((p, c) => placeUnit(p, { ...c }, makeUnit));
    deckA.forEach(c => put(A, c)); deckB.forEach(c => put(B, c));
    refreshAll(A); refreshAll(B);
    const A0 = [...A.field], B0 = [...B.field];
    const noMana = () => { A.mana = B.mana = 0; A.maxMana = B.maxMana = 0; A.bonusMana = B.bonusMana = 0; };
    // 재생용 기록 (읽기만 함 · 난수/결과에 영향 없음)
    const hpOf = p => Object.fromEntries(p.field.map(u => [u.uid, u.hp]));
    const push = rec ? (x = {}) => rec.push({ ...x, A: hpOf(A), B: hpOf(B) }) : () => {};
    if (rec) { rec.roster = { A: A.field.map(u => ({ uid: u.uid, id: u.base.id, max: u.maxHp })), B: B.field.map(u => ({ uid: u.uid, id: u.base.id, max: u.maxHp })) }; rec.aFirst = aFirst; push({ k: 'start' }); }
    const live = p => p.field.filter(u => u.hp > 0).length;
    const end = () => !live(B) ? 1 : !live(A) ? 0 : -1;
    const out = (w, t) => opt.out ? opt.out(A, B, !!w, t, aFirst) : ({ win: !!w, turns: t, aLeft: live(A), bLeft: live(B), aFirst });
    for (let t = 0; t < MAXT; t++) {
      const cur = (t % 2 === 0) === aFirst ? A : B, op = cur.foe;
      clearBuff(op); refillMana(cur); noMana(); cur.field.forEach(u => u.canAttack = true); turnStart(cur);
      push({ k: 'turn', side: cur === A ? 'A' : 'B', t: t + 1 });
      if (view) yield { anim: { k: 'turn', side: cur === A ? 'A' : 'B', t: t + 1 }, A, B, A0, B0 };
      let e = end(); if (e >= 0) return out(e, t + 1);
      const turn = { used: new Set(), scopes: new Set() };
      for (let k = 0; k < 40; k++) {
        let a;
        if (manual && cur === A) {
          if (!A.field.some(u => u.hp > 0 && u.canAttack)) break;
          const inp = yield { ask: true, A, B, A0, B0, t: t + 1 };
          a = resolveAct(inp, A, B, A0, B0, turn, autoNext);
          if (a === null) { acts?.push({ k: 'end' }); break; }
          if (a === false) { k--; continue; }
          if (a.none) { acts?.push({ k: 'end' }); break; }
          acts?.push(a.rec);
        } else { a = autoNext(cur, op, turn); if (!a) break; }
        let hits = null;
        if (a.kind === 'skill') { noteUsed(turn, a.s); useSkill(a.u, a.s); } else if (a.t) hits = resolveAttack(cur, op, a.u, a.t);
        noMana();
        push({ k: a.kind === 'skill' ? 'skill' : 'atk', side: cur === A ? 'A' : 'B', u: a.u.uid, to: a.t?.uid, s: a.kind === 'skill' ? (a.s?.label || a.s?.name || '') : '' });
        a.u.canAttack = false;
        if (view) yield { anim: { k: a.kind === 'skill' ? 'skill' : 'atk', side: cur === A ? 'A' : 'B', u: a.u, t: a.t || null, s: a.s || null, hits }, A, B, A0, B0 };
        e = end(); if (e >= 0) return out(e, t + 1);
      }
      endTurnXp(cur); turnEnd(cur); noMana();
      if (view) yield { anim: { k: 'end', side: cur === A ? 'A' : 'B' }, A, B, A0, B0 };
      e = end(); if (e >= 0) return out(e, t + 1);
    }
    return out(0, MAXT);   // 시간 초과 = 공격 측 패배 (방어 유리)
}
/** 한 판: A(공격) vs B(방어). actions 없으면 둘 다 자동 AI, 있으면 A 는 그 기록대로(수동 판 재검증). 반환 { win: A 승리?, turns, aLeft, bLeft } */
export function runMatch(deckA, deckB, seed, rec = null, actions = null) {
  const r = rngOf(seed), st = stepper(matchGen(deckA, deckB, r, rec, !!actions), r);
  return actions ? replay(st, actions) : st.next().value;
}
/** 수동 한 판 세션: s.next(입력) 으로 진행, s.acts 가 기록 */
export function manualMatch(deckA, deckB, seed, rec = null, opt = {}) {
  const r = rngOf(seed), acts = [], st = stepper(matchGen(deckA, deckB, r, rec, opt.manual !== false, acts, opt), r, opt.view ? [] : null); st.acts = acts; return st;
}
export const roundSeed = (seed, i) => (Number(seed) + i * 7919) >>> 0;
/** 시리즈: 1v1 = 1판, 3v3 = 덱 i vs 덱 i 로 최대 3판 (2선승). 판마다 seed + i */
export function runSeries(mode, decksA, decksB, seed, withLog = false, actions = null) {
  const M = MODES[mode], rounds = []; let w = 0, l = 0;
  for (let i = 0; i < M.decks; i++) {
    const log = withLog ? [] : null;
    const m = runMatch(decksA[i], decksB[i], roundSeed(seed, i), log, actions ? actions[i] || [] : null); if (log) m.log = log; rounds.push(m); m.win ? w++ : l++;
    if (w >= M.need || l >= M.need) break;
  }
  return { win: w >= M.need, wins: w, losses: l, rounds };
}
