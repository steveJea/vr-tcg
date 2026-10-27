// ===== 조직 전쟁 「구역 전쟁」 전투 코어 (화면 없음 · 브라우저/노드 공용) =====
// 서버(war_start)가 준 seed + 양쪽 덱 스냅샷(현재 HP 포함) + 역할 버프로 양쪽 자동 전투(auto-ai.js).
// 남은 HP 를 카드별로 돌려준다 → 서버가 저장, 다음 전투에 그대로 (쓰러진 카드는 빠짐). 같은 입력이면 결과가 같아 tools/war_verify.mjs 로 재검증.
import { initPlayers, placeUnit, turnStart, turnEnd, useSkill, refreshAll, setRng, setEmitter, getEmitter } from './skills.js';
import { makeUnit, resolveAttack, refillMana, clearBuff, endTurnXp } from './rules.js';
import { autoNext, noteUsed } from './auto-ai.js';
import { rngOf, snapCard } from './pvp-core.js';

export const WAR_TURNS = 40;
// 역할 (서버 _war_numbers 의 roles 와 같음)
export const WAR_ROLES = {
  def: { label: '방어조', icon: '🛡️', atk: 1, def: 1.2 }, atk: { label: '돌격조', icon: '⚔️', atk: 1.2, def: 1 },
  mid: { label: '중간보스', icon: '💀', atk: 1.15, def: 1.15 }, boss: { label: '보스', icon: '👑', atk: 1.25, def: 1.25 }, etc: { label: '조직원', icon: '🏠', atk: 1, def: 1 },
};
/** 스냅샷 1장 → 전투 카드 (NPC 는 scale 배율, 역할 버프, 현재 HP) */
export function warCard(o, cardById, buff = {}) {
  const c = snapCard(o, cardById); if (!c) return null;
  const s = +o.scale || 1, a = (buff.atk || 1) * s, d = (buff.def || 1) * s;
  const HP = Math.max(1, Math.round(c.HP * s));
  return { ...c, ATK: Math.round(c.ATK * a), DEF: Math.round(c.DEF * d), HP, _uid: o.uid, _hp: o.hp == null ? HP : Math.max(0, Math.min(HP, +o.hp)) };
}
export const warDeck = (snap, cardById, buff) => (snap || []).map(o => warCard(o, cardById, buff)).filter(c => c && c._hp > 0);
/** 한 판: A(공격) vs B(방어 아지트). 반환 { win, turns, aHp:{uid:hp}, bHp:{uid:hp} } (살아남은 카드만) */
export function runWar(deckA, deckB, seed, rec = null) {
  const r = rngOf(seed), oldR = Math.random, oldE = getEmitter();
  Math.random = r; setRng(r); setEmitter(() => {});
  try {
    const mk = name => ({ name, hp: 1, maxHp: 1, deck: [], hand: [], field: [], mana: 0, maxMana: 0, noBase: true, once: {}, grave: [] });
    const A = mk('A'), B = mk('B'), aFirst = r() < 0.5;
    initPlayers(A, B, aFirst ? A : B);
    const put = (p, c) => { const u = placeUnit(p, { ...c }, makeUnit); u.hp = Math.max(1, Math.min(u.maxHp, c._hp)); };
    deckA.forEach(c => put(A, c)); deckB.forEach(c => put(B, c));
    refreshAll(A); refreshAll(B);
    const hpOf = p => Object.fromEntries(p.field.map(u => [u.uid, u.hp]));
    const push = rec ? (x = {}) => rec.push({ ...x, A: hpOf(A), B: hpOf(B) }) : () => {};
    if (rec) { rec.roster = { A: A.field.map(u => ({ uid: u.uid, id: u.base.id, max: u.maxHp })), B: B.field.map(u => ({ uid: u.uid, id: u.base.id, max: u.maxHp })) }; rec.aFirst = aFirst; push({ k: 'start' }); }
    const live = p => p.field.filter(u => u.hp > 0).length;
    const left = p => { const o = {}; for (const u of p.field) if (u.hp > 0 && u.base._uid != null) o[u.base._uid] = Math.min(u.hp, u.base._hp); return o; };   // 전투 중 늘어난 HP 는 버림 (서버도 이전 HP 를 넘지 않게 자름)
    const out = (w, t) => ({ win: !!w, turns: t, aHp: left(A), bHp: w ? {} : left(B), aFirst });
    const end = () => !live(B) ? 1 : !live(A) ? 0 : -1;
    for (let t = 0; t < WAR_TURNS; t++) {
      const cur = (t % 2 === 0) === aFirst ? A : B, op = cur.foe;
      clearBuff(op); refillMana(cur); cur.field.forEach(u => u.canAttack = true); turnStart(cur);
      push({ k: 'turn', side: cur === A ? 'A' : 'B', t: t + 1 });
      let e = end(); if (e >= 0) return out(e, t + 1);
      const turn = { used: new Set(), scopes: new Set() };
      for (let k = 0; k < 40; k++) {
        const a = autoNext(cur, op, turn); if (!a) break;
        if (a.kind === 'skill') { noteUsed(turn, a.s); useSkill(a.u, a.s); } else if (a.t) resolveAttack(cur, op, a.u, a.t);
        push({ k: a.kind === 'skill' ? 'skill' : 'atk', side: cur === A ? 'A' : 'B', u: a.u.uid, to: a.t?.uid, s: a.kind === 'skill' ? (a.s?.label || a.s?.name || '') : '' });
        a.u.canAttack = false;
        e = end(); if (e >= 0) return out(e, t + 1);
      }
      endTurnXp(cur); turnEnd(cur);
      e = end(); if (e >= 0) return out(e, t + 1);
    }
    return out(0, WAR_TURNS);   // 시간 초과 = 공격 측 패배
  } finally { Math.random = oldR; setRng(oldR); setEmitter(oldE); }
}
