// ===== 조직 토벌 「균열 토벌」 전투 코어 (화면 없음 · 브라우저/노드 공용) =====
// 서버(raid_start)가 준 seed + 내 덱 스냅샷 + 보스 정보로 자동 전투(auto-ai.js). 같은 입력이면 결과가 항상 같아 tools/raid_verify.mjs 로 재검증.
// 보스는 쓰러지지 않음(즉사 시 되돌림). 매 행동 뒤 입힌 피해를 세고(행동 1번당 상한) HP 를 다시 채운다 → 즉사·%피해 스킬도 상한까지만.
import { initPlayers, placeUnit, turnStart, turnEnd, useSkill, refreshAll, setRng, setEmitter, getEmitter } from './skills.js';
import { makeUnit, resolveAttack, refillMana, clearBuff, endTurnXp } from './rules.js';
import { autoNext, noteUsed } from './auto-ai.js';
import { rngOf } from './pvp-core.js';

export const RAID_TURNS = 15;              // 내 턴 15번 (보스 턴 포함 30)
export const BOSS_BAR = 1e7;               // 보스 HP 막대 (실제 공유 HP 는 서버)
// 단계 → 보스 (5단계 뒤 다시 1번부터, HP 는 계속 ×1.35). 서버 _raid_boss_of 와 같음
export const RAID_BOSSES = [
  { id: '2000100001', name: '임유리', weak: 'CHARGE', icon: '🖤' },
  { id: '2000000008', name: '[각성] 임유리', weak: 'DEFENSE', icon: '🌑' },
  { id: '2000900234', name: '김신현', weak: 'CRUSH', icon: '⛓️' },
  { id: '1000200030', name: '김성진', weak: 'SUPPORT', icon: '🔥' },
  { id: null, name: '이지용', weak: 'DISTURB', icon: '👁️', stand: '1000200030' },   // 카드 없음 → 임시로 김성진 능력치·그림 없음
];
export const RAID_DIFF = { normal: { label: '일반', atk: 1, def: 1 }, hard: { label: '어려움', atk: 1.6, def: 1.3 }, abyss: { label: '심연', atk: 2.4, def: 1.7 } };
export const WEAK_MULT = 1.25;
export const bossOf = stage => RAID_BOSSES[(Math.max(1, stage) - 1) % RAID_BOSSES.length];
/** 행동 1번 피해 상한 (서버 _raid_hit_cap 과 같음) */
export const hitCap = stage => Math.round(6000 * Math.pow(1.1, Math.max(0, stage - 1)));
/** 보스 전투 카드 */
export function bossCard(stage, diff, cardById) {
  const b = bossOf(stage), c = cardById(b.id || b.stand); if (!c) return null;
  const D = RAID_DIFF[diff] || RAID_DIFF.normal, up = 1 + 0.12 * (Math.max(1, stage) - 1);
  return { ...c, id: c.id, name: b.name, HP: BOSS_BAR, ATK: Math.round(c.ATK * 0.8 * D.atk * up), DEF: Math.round(c.DEF * 0.2 * D.def * up) };
}
/** 한 판. 반환 { damage, hits, turns, alive } */
export function runRaid(deck, stage, diff, seed, cardById, rec = null) {
  const r = rngOf(seed), oldR = Math.random, oldE = getEmitter();
  Math.random = r; setRng(r); setEmitter(() => {});
  try {
    const mk = name => ({ name, hp: 1, maxHp: 1, deck: [], hand: [], field: [], mana: 0, maxMana: 0, noBase: true, once: {}, grave: [] });
    const A = mk('A'), B = mk('B');
    initPlayers(A, B, A);
    deck.forEach(c => placeUnit(A, { ...c }, makeUnit));
    const bc = bossCard(stage, diff, cardById), boss = placeUnit(B, bc, makeUnit);
    refreshAll(A); refreshAll(B);
    const weak = bossOf(stage).weak, cap = hitCap(stage);
    let damage = 0, hits = 0;
    const settle = () => {
      if (!B.field.includes(boss)) B.field.push(boss);
      let d = Math.max(0, BOSS_BAR - boss.hp); boss.hp = BOSS_BAR;
      if (!d) return 0;
      d = Math.min(cap, d); hits++; damage += d; return d;
    };
    const hpOf = p => Object.fromEntries(p.field.map(u => [u.uid, u.hp]));
    const push = rec ? (x = {}) => rec.push({ ...x, A: hpOf(A), dmg: damage }) : () => {};
    if (rec) { rec.roster = { A: A.field.map(u => ({ uid: u.uid, id: u.base.id, max: u.maxHp })), boss: { uid: boss.uid, id: bc.id } }; push({ k: 'start' }); }
    const live = () => A.field.filter(u => u.hp > 0).length;
    let t = 0;
    for (; t < RAID_TURNS * 2; t++) {
      const cur = t % 2 === 0 ? A : B, op = cur.foe;
      clearBuff(op); refillMana(cur); cur.field.forEach(u => u.canAttack = true); turnStart(cur); settle();
      if (cur === A) push({ k: 'turn', t: t / 2 + 1 });
      if (!live()) break;
      const turn = { used: new Set(), scopes: new Set() };
      for (let k = 0; k < 40; k++) {
        const a = autoNext(cur, op, turn); if (!a) break;
        // 약점 속성: 내 카드 공격력 +25% (행동하는 동안만)
        const wk = cur === A && a.u.card.attribute === weak, atk0 = a.u.card.ATK;
        if (wk) a.u.card.ATK = Math.round(atk0 * WEAK_MULT);
        if (a.kind === 'skill') { noteUsed(turn, a.s); useSkill(a.u, a.s); } else if (a.t) resolveAttack(cur, op, a.u, a.t);
        if (wk && a.u.card) a.u.card.ATK = atk0;
        a.u.canAttack = false;
        const d = settle();
        push({ k: a.kind === 'skill' ? 'skill' : 'atk', side: cur === A ? 'A' : 'B', u: a.u.uid, to: a.t?.uid, d, s: a.kind === 'skill' ? (a.s?.label || a.s?.name || '') : '' });
        if (!live()) break;
      }
      endTurnXp(cur); turnEnd(cur); settle();
      if (!live()) break;
    }
    return { damage, hits, turns: Math.min(RAID_TURNS, Math.ceil((t + 1) / 2)), alive: live() };
  } finally { Math.random = oldR; setRng(oldR); setEmitter(oldE); }
}
