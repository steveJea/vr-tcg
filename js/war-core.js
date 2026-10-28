// ===== 조직 전쟁 「구역 전쟁」 전투 코어 (화면 없음 · 브라우저/노드 공용) =====
// 서버(war_start)가 준 seed + 양쪽 덱 스냅샷(현재 HP 포함) + 역할 버프로 양쪽 자동 전투(auto-ai.js).
// 남은 HP 를 카드별로 돌려준다 → 서버가 저장, 다음 전투에 그대로 (쓰러진 카드는 빠짐). 같은 입력이면 결과가 같아 tools/war_verify.mjs 로 재검증.
import { placeUnit } from './skills.js';
import { makeUnit } from './rules.js';
import { rngOf, snapCard, stepper, replay, matchGen } from './pvp-core.js';

export const WAR_TURNS = 40;
// 역할 (서버 _war_numbers 의 roles 와 같음)
export const WAR_ROLES = {
  def: { label: '방어조', icon: '🛡️', atk: 1, def: 1.2 }, atk: { label: '돌격조', icon: '⚔️', atk: 1.2, def: 1 },
  mid: { label: '중간보스', icon: '💀', atk: 1.15, def: 1.15 }, boss: { label: '보스', icon: '👑', atk: 1.25, def: 1.25 }, etc: { label: '조직원', icon: '🏠', atk: 1, def: 1 },
};
/** 스냅샷 1장 → 전투 카드 (NPC 는 scale 배율, 역할 버프, 현재 HP) */
export function warCard(o, cardById, buff = {}) {
  const c = snapCard(o, cardById, 'war'); if (!c) return null;
  const s = +o.scale || 1, a = (buff.atk || 1) * s, d = (buff.def || 1) * s;
  const HP = Math.max(1, Math.round(c.HP * s));
  return { ...c, ATK: Math.round(c.ATK * a), DEF: Math.round(c.DEF * d), HP, _uid: o.uid, _hp: o.hp == null ? HP : Math.max(0, Math.min(HP, +o.hp)) };
}
export const warDeck = (snap, cardById, buff) => (snap || []).map(o => warCard(o, cardById, buff)).filter(c => c && c._hp > 0);
// 전투는 pvp-core 의 matchGen 과 같은 엔진 (마나 없음 · 수동/화면 연출 공용). 구역 전쟁: 현재 HP 로 배치, 40턴, 남은 HP 반환
const warPut = (p, c) => { const u = placeUnit(p, { ...c }, makeUnit); u.hp = Math.max(1, Math.min(u.maxHp, c._hp)); };
const left = p => { const o = {}; for (const u of p.field) if (u.hp > 0 && u.base._uid != null) o[u.base._uid] = Math.min(u.hp, u.base._hp); return o; };   // 전투 중 늘어난 HP 는 버림 (서버도 이전 HP 를 넘지 않게 자름)
export const warOpt = (extra = {}) => ({ put: warPut, maxTurns: WAR_TURNS, out: (A, B, w, t, aFirst) => ({ win: w, turns: t, aHp: left(A), bHp: w ? {} : left(B), aFirst }), ...extra });
/** 한 판: A(공격) vs B(방어 아지트). actions 있으면 A 는 기록대로(수동 판 재검증). 반환 { win, turns, aHp:{uid:hp}, bHp:{uid:hp} } (살아남은 카드만) */
export function runWar(deckA, deckB, seed, rec = null, actions = null) {
  const r = rngOf(seed), st = stepper(matchGen(deckA, deckB, r, rec, !!actions, null, warOpt()), r);
  return actions ? replay(st, actions) : st.next().value;
}
/** 수동/화면 세션 (pvp-core manualMatch 와 같음) */
export function warSession(deckA, deckB, seed, rec = null, extra = {}) {
  const r = rngOf(seed), acts = [], st = stepper(matchGen(deckA, deckB, r, rec, extra.manual !== false, acts, warOpt(extra)), r, extra.view ? [] : null); st.acts = acts; return st;
}
