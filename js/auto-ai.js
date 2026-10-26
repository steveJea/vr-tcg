// ===== 자동 전투 (스토리·탑 전용, 내 진영) =====
// 적 AI의 스킬 점수(aiSkillScores)를 그대로 쓰고, 무작위 대신 아래 규칙으로 '다음 한 수'를 고른다.
// 우선순위: ① 위급 회복 ② 한 방 처치(기본 공격) ③ 디버프 ④ 버프·도발 ⑤ 공격 스킬 ⑥ 기본 공격(집중 공격)
// 도발: 한 번에 한 명만 — 아군에 도발이 살아 있으면 다시 안 씀, 후보 중 가장 오래 버티는 탱커(유효 HP·DEF·회피·무적/불사·지속 턴)
// 같은 턴에 같은 스킬 중복 금지 · 같은 범위의 버프/도발 겹치기 금지 · 기본 공격으로 다 잡히면 MP 아낌 · 무적/불사류는 위급할 때만
import { aiSkillScores, spareBlocked, isTauntSkill } from './skills.js';
import { attackTargets, calcDamageG } from './rules.js';

const PH = { heal: 600, kill: 500, debuff: 400, buff: 300, atkSkill: 200, attack: 100 };
const alive = u => u && u.hp > 0;
const hpPct = u => u.hp / (u.maxHp || 1);
const SAVE_RX = /무적|불사|면역|부활|피해를 입지/;
const DRAIN_RX = /MP[^.]*흡수|흡수[^.]*MP|MP[^.]*감소|MP[^.]*빼앗/;
/** 위협도: 전투력 + 남은 체력 대비 공격력, MP 흡수·감소 스킬 보유 시 가산 */
export function threat(t) {
  let v = (t.card.power || 0) + (t.card.ATK || 0) * 4;
  if ((t.sk || []).some(s => DRAIN_RX.test(s.desc || ''))) v *= 1.3;
  if (t.isLeader) v *= 1.15;
  return v;
}
/** 도발 효율: 유효 HP(HP × DEF 보정 ÷ (1-회피)) × 지속 턴, 무적·불사·면역 포함 시 크게 가산 */
export function tankScore(u, s) {
  const def = u.card.DEF || 0, ev = Math.min(0.6, u.card.evade || u.evade || 0);
  let v = u.hp * (1 + def / 100) / (1 - ev) * Math.max(1, s.duration || 1);
  if (SAVE_RX.test(s.desc || '')) v *= 2.5;
  if (/DEF/.test(s.desc || '')) v *= 1.3;
  return v;
}
const kills = (u, t) => calcDamageG(u.card, t.card) >= t.hp;

/** 스킬 분류 */
function phaseOf(s, ctx) {
  if (isTauntSkill(s)) return 'buff';
  if (s.type === '회복') return ctx.lowAllies ? 'heal' : null;
  if (s.type === '디버프') return 'debuff';
  if (s.type === '버프') return 'buff';
  return 'atkSkill';
}

/** 다음 한 수: { kind:'skill', u, s } | { kind:'attack', u, t } | null(턴 종료). turn = { used:Set(스킬명), scopes:Set(종류|대상) } */
export function autoNext(me, opp, turn = { used: new Set(), scopes: new Set() }) {
  const ready = me.field.filter(u => alive(u) && u.canAttack && !spareBlocked(u));
  if (!ready.length) return null;
  const foes = opp.field.filter(alive);
  const lowAllies = me.field.filter(a => alive(a) && hpPct(a) < 0.5).length;
  const ctx = { lowAllies };
  const tauntUp = me.field.some(a => alive(a) && a.st?.taunt);
  // 기본 공격만으로 남은 적을 모두 잡을 수 있나 (그러면 공격 스킬 MP 아낌)
  const easy = foes.length > 0 && foes.length <= ready.length && foes.every(t => ready.some(u => attackTargets(me, opp, u).units.includes(t) && kills(u, t)));
  let best = null;
  const offer = (sc, act) => { if (!best || sc > best.sc) best = { sc, ...act }; };
  for (const u of ready) {
    for (const [s, base] of aiSkillScores(u, { noSave: true })) {
      if (turn.used.has(s.name)) continue;                                  // (a) 같은 스킬은 한 명만
      const ph = phaseOf(s, ctx); if (!ph) continue;
      if (isTauntSkill(s) && (tauntUp || turn.used.has('#taunt'))) continue;   // 도발은 한 명만, 살아 있으면 재사용 금지
      const scope = `${s.type}|${s.target || ''}`;
      if ((ph === 'buff' || ph === 'heal') && turn.scopes.has(scope) && /전체|아군/.test(s.target || '')) continue;   // 같은 범위 버프 겹치기 금지
      if (ph === 'buff' && SAVE_RX.test(s.desc || '') && !lowAllies) continue;   // 무적·불사류는 위급할 때만
      if (ph === 'atkSkill' && easy) continue;                               // 오버킬 방지
      if (ph === 'debuff' && !foes.length) continue;
      offer(isTauntSkill(s) ? PH.buff + 50 + Math.min(49, tankScore(u, s) / 1000) : PH[ph] + base, { kind: 'skill', u, s });
    }
    const tg = attackTargets(me, opp, u);
    for (const t of tg.units) {
      if (!alive(t)) continue;
      if (kills(u, t)) offer(PH.kill + threat(t) / 1000 - (u.card.ATK || 0) / 1e5, { kind: 'attack', u, t });   // (b) 한 방 처치: 위협 큰 적부터, 약한 아군으로
      else { const d = calcDamageG(u.card, t.card); offer(PH.attack + d / t.hp * 50 + threat(t) / 1e4, { kind: 'attack', u, t }); }   // 집중 공격: 체력 대비 피해가 큰 적
    }
    if (!tg.units.length && tg.hero) offer(PH.attack - 1, { kind: 'attack', u, t: null });
  }
  return best;
}
/** 스킬을 쓴 뒤 호출: 같은 턴 중복 방지 기록 */
export function noteUsed(turn, s) { turn.used.add(s.name); if (isTauntSkill(s)) turn.used.add('#taunt'); turn.scopes.add(`${s.type}|${s.target || ''}`); }
