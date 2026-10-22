// ===== VR TCG 규칙 (순수 함수: UI와 분리, 테스트 가능) =====
import { skillsOf, damageUnit, damageHero, checkDeath, afterBasicHit, refreshAll, onLevelChange, redirectAttack, counterMult, heal, maleLure, rollEvade } from './skills.js';
export const RULES = {
  HERO_HP: 3000,          // 영웅 HP
  DAMAGE_MULT: 1.5,       // ATK에 곱하는 전체 데미지 배율 (DEF 차감 전)
  FIELD_MAX: 5, DECK_SIZE: 30, OPENING_HAND: 4,
  MANA_START: 40, MANA_PER_TURN: 20, MANA_MAX: 100, MAX_ABYSS_PER_DECK: 1, // 마나는 이월: 첫 턴 40, 이후 매 턴 +20(+가속기), 최대 100
  COUNTER_RATIO: 0.5,         // 반격 = 대상 피해 계산 × 반격 배율(패시브) × 0.5. 대상이 쓰러지면 반격 없음, 반격으로는 공격자가 쓰러지지 않음(HP 1)
  MAX_TURNS: 40,              // 전체 40턴(각자 20턴) 후 판정승
  MR_HERO_DMG_RATIO: 0.2,     // MYTHIC RARE 카드가 진영(영웅)에 주는 피해 배율 (일반·스킬·초과 피해)
  SACRIFICE_RATIO: 0.5,       // 희생: 필드 카드 1장 제거 → 코스트 × 0.5 마나 (턴당 1회)
  ACCEL_COST: 30, ACCEL_BONUS: 5, ACCEL_MAX: 5, // 마나 가속기: 다음 턴부터 매 턴 +5, 최대 5회
  // 덱 구성 (등급별 장수, 합계 30)
  DECK_COMPOSITION: { 'NORMAL': 10, 'RARE': 8, 'HIGH RARE': 6, 'SUPER RARE': 4, 'ULTRA RARE': 2 },
  MYTHIC_CHANCE: 0.15,
  SECOND_PLAYER_BONUS_CARDS: 1,
  RECALL_COST_RATIO: 0.5,  // 회수 비용 = ceil(코스트 × 비율)
  AI_RECALL_MIN_COST: 30,  // AI가 회수를 고려하는 최소 코스트
  KILL_MANA_RATIO: 0.3,       // 처치 시 즉시 마나 = round(처치 카드 코스트 × 0.3), 최대 마나까지
  // 레벨/경험치: XP: 처치(killXp) + 공격 + 턴 종료 생존. 다음 레벨 필요 XP = round(XP_BASE × 레벨^XP_EXP)
  LEVEL_MAX: 10,              // Lv10 = 영웅 카드
  XP_BASE: 5.5, XP_EXP: 1.3,  // Lv1→2: 6, Lv5→6: 45, Lv9→10: 96 (누적 약 430)
  KILL_XP_LEVEL_BONUS: 0.2,   // 처치 XP = round(처치 카드 코스트 × (1 + 처치 카드 레벨 × 0.2))
  ATTACK_XP: 5,               // 공격할 때마다 (살아남으면) 공격 카드 XP
  TURN_END_XP: 4,             // 내 턴 종료 시 필드에 살아있는 카드마다 XP
  LEVEL_UP_RATIO: 0.1,        // Lv2~5: 레벨업마다 원본 ATK·HP의 +10%
  LEVEL_UP_RATIO_HIGH: 0.05,  // Lv6~10: 원본의 +5% (체감)
  LEVEL_HIGH_FROM: 6,
  // 영웅 공격 제한
  HERO_GUARD_FIELD: 4,        // 상대 필드가 이 장수 이상이면 영웅 공격 불가 (카드만 공격)
  HERO_LOCK_TURNS: 2,         // 자기 첫 N턴 동안은 영웅 공격·초과 피해 불가
  // 아이템 (마나로 구매, 카드당 무기 1 + 방어구 1)
  WEAPON_COST: 30, WEAPON_ATK_RATIO: 0.15,
  ARMOR_COST: 30, ARMOR_HP_RATIO: 0.2,
  FIELD_HEAL_COST: 20, FIELD_HEAL_RATIO: 0.1, // 필드 회복: 내 필드 전체 최대 HP의 10% 회복
  OVERFLOW_TO_HERO: true,
  // 마나 액션 (모두 턴당 1회)
  SHUFFLE_COST: 50,       // 패 섞기: 손패 전부 덱에 넣고 섞은 뒤 같은 장수 드로우
  HEAL_COST: 20,          // 기지 보강: 영웅 HP 회복
  HEAL_AMOUNT: 200,
  BUFF_COST: 30,          // 공격력 강화: 내 필드 카드 이번 턴 ATK +20%
  BUFF_RATIO: 0.2,
  // 아케이드 등급별 뽑기 확률 (덱 30장 슬롯마다 등급 추첨, 등급 제한 시 남은 등급끼리 재정규화)
  DRAW_RATES: { 'NORMAL': 0.50, 'RARE': 0.30, 'HIGH RARE': 0.11, 'SUPER RARE': 0.05, 'ULTRA RARE': 0.03, 'MYTHIC RARE': 0.01 },
  MAX_MYTHIC_PER_DECK: 1,
  // 성별 간 피해 (모든 모드): 남→여 85%, 여→남 105%, 동성 100%. 스킬의 [여성에게]/[남성에게] 추가 %와 곱연산
  GENDER_ON: true, GENDER_M2F: 0.85, GENDER_F2M: 1.05,
  // 기본 공격 회피 (속성별 기본값, 스킬 회피와 합산, 상한)
  EVADE_ON: true, EVADE_BASE: { WIND: 0.10 }, EVADE_DEFAULT: 0.04, EVADE_CAP: 0.6,
};
export const GRADES = ['NORMAL', 'RARE', 'HIGH RARE', 'SUPER RARE', 'ULTRA RARE', 'MYTHIC RARE'];
export const GRADE_SHORT = { 'NORMAL': 'N', 'RARE': 'R', 'HIGH RARE': 'HR', 'SUPER RARE': 'SR', 'ULTRA RARE': 'UR', 'MYTHIC RARE': 'MR' };
/** 성별 피해 배율 (공격 카드 → 대상 카드). 영웅·성별 미상은 1 */
export function genderMult(att, def) {
  if (!RULES.GENDER_ON || !att || !def) return 1;
  if (att.gender === 'MALE' && def.gender === 'FEMALE') return RULES.GENDER_M2F;
  if (att.gender === 'FEMALE' && def.gender === 'MALE') return RULES.GENDER_F2M;
  return 1;
}
/** 속성 기본 회피율 */
export const baseEvade = card => !RULES.EVADE_ON || !card ? 0 : (RULES.EVADE_BASE[card.class] ?? RULES.EVADE_DEFAULT);
/** 아케이드 옵션 → 허용 등급 집합 (null = 전체) */
export function allowedGrades(opts) {
  const g = opts?.grades; if (!g || !g.length || g.length >= GRADES.length) return null;
  return new Set(g);
}

export const ELEMENTS = {
  FIRE:  { label: '불',   icon: '🔥', img: 'el_fire', color: 'text-orange-400', ring: 'ring-orange-500' },
  WIND:  { label: '바람', icon: '🌪️', img: 'el_wind', color: 'text-teal-300',   ring: 'ring-teal-400' },
  ICE:   { label: '얼음', icon: '❄️', img: 'el_ice', color: 'text-sky-300',    ring: 'ring-sky-400' },
  DARK:  { label: '어둠', icon: '🌑', img: 'el_dark', color: 'text-purple-400', ring: 'ring-purple-500' },
  LIGHT: { label: '빛',   icon: '✨', img: 'el_light', color: 'text-yellow-300', ring: 'ring-yellow-400' },
  ABYSS: { label: '심연', icon: '💀', img: 'el_death', color: 'text-rose-500',   ring: 'ring-rose-600' },
};

const BEATS = { FIRE: 'WIND', WIND: 'ICE', ICE: 'FIRE' };

/** 공격 속성 att → 방어 속성 def 배율. def가 null이면(영웅) 1. */
export function elementMultiplier(att, def) {
  if (!def) return 1;
  if (def === 'ABYSS') return att === 'LIGHT' ? 2 : (att === 'ABYSS' ? 1.25 : 1);
  if (att === 'ABYSS') return 1.25;
  if ((att === 'LIGHT' && def === 'DARK') || (att === 'DARK' && def === 'LIGHT')) return 2;
  if (BEATS[att] === def) return 1.5;
  if (BEATS[def] === att) return 0.75;
  return 1;
}

/** 데미지 = max(1, floor(ATK × DAMAGE_MULT × 속성배율 − 대상DEF/2)). 영웅은 DEF 0, 속성 없음.
 *  성별 배율은 여기서 곱하지 않고 damageUnit(실제 적용 지점)에서 모든 카드 간 피해에 곱함. 예측용은 calcDamageG */
export function calcDamage(attacker, target) {
  const mult = target ? elementMultiplier(attacker.class, target.class) : 1;
  const def = target ? target.DEF : 0;
  return Math.max(1, Math.floor(attacker.ATK * RULES.DAMAGE_MULT * mult - def / 2));
}
/** 성별 배율까지 반영한 예상 피해 (AI·일괄공격 처치 예측용) */
export function calcDamageG(attacker, target) {
  return Math.max(1, Math.round(calcDamage(attacker, target) * (target ? genderMult(attacker, target) : 1)));
}

/** 소환 가능 여부와 사유 */
export function canSummon(card, me, opp) {
  if (me.field.length >= RULES.FIELD_MAX) return { ok: false, reason: '필드가 가득 찼습니다 (최대 5장)' };
  if (card.cost > me.mana) return { ok: false, reason: `마나가 부족합니다 (${me.mana}/${card.cost})` };
  if (card.class === 'ABYSS' && opp.field.some(u => u.card.class === 'LIGHT'))
    return { ok: false, reason: '상대 필드에 빛(LIGHT) 카드가 있어 심연(ABYSS) 카드를 소환할 수 없습니다' };
  return { ok: true };
}

/** 회수 비용 */
export function recallCost(card) { return Math.ceil(card.cost * RULES.RECALL_COST_RATIO); }

/** 회수 가능 여부와 사유 */
export function canRecall(unit, me) {
  const cost = recallCost(unit.card);
  if (unit.st?.para) return { ok: false, cost, reason: '마비 상태에서는 회수할 수 없습니다' };
  if (unit.st?.disrupt) return { ok: false, cost, reason: '교란 상태에서는 회수할 수 없습니다' };
  if (cost > me.mana) return { ok: false, cost, reason: `마나가 부족합니다 (${me.mana}/${cost})` };
  return { ok: true, cost };
}

/** AI 회수 판단: 고코스트 카드가 다쳤고, 상대 필드의 어떤 카드 공격으로든 죽을 수 있으면 회수 */
export function aiShouldRecall(unit, me, opp) {
  if (unit.card.cost < RULES.AI_RECALL_MIN_COST || unit.hp >= unit.maxHp) return false;
  if (unit.items?.weapon || unit.items?.armor || unit.level >= 3) return false; // 투자한 카드는 회수하지 않음
  if (!canRecall(unit, me).ok) return false;
  return opp.field.some(t => calcDamage(t.card, unit.card) >= unit.hp);
}

/** 필드 유닛 생성: card는 레벨/아이템으로 바뀌는 사본, base는 원본(회수 시 원본으로 복귀 → 레벨·XP·아이템 초기화) */
export function makeUnit(card, uid) {
  return { uid, base: card, card: { ...card }, hp: card.HP, maxHp: card.HP, level: 1, xp: 0, items: {}, skills: [...(card.skills || [])], canAttack: false,
    raw: { ATK: card.ATK, DEF: card.DEF }, cd: {}, st: {}, fired: {}, gains: [], cry: 0, curse: 0, comboHp: 0, sk: skillsOf(card.id), mp: 0, maxMp: 0, mpRegen: 0 };
}

// ===== 스킬 훅 (아직 카드에 배정하지 않음). 카드 데이터에 skills: ['taunt'] 형태로 지정 =====
export const SKILLS = {
  taunt: { label: '도발', icon: '🎯', img: 'taunt', desc: '상대는 도발 카드부터 공격해야 합니다' },
};
export const hasSkill = (u, id) => !!u.skills?.includes(id) || !!u.st?.[id];

/** 처치 XP: 레벨 높은 카드를 잡을수록 더 많이 */
export function killXp(victim) { return Math.round(victim.card.cost * (1 + victim.level * RULES.KILL_XP_LEVEL_BONUS)); }

/** 다음 레벨까지 필요 XP */
export function xpToNext(level) { return level >= RULES.LEVEL_MAX ? Infinity : Math.round(RULES.XP_BASE * Math.pow(level, RULES.XP_EXP)); }

/** 한 번 레벨업 (원본 기준 증가, Lv6부터 체감) */
export function levelUpOnce(u) {
  const next = u.level + 1;
  const r = next >= RULES.LEVEL_HIGH_FROM ? RULES.LEVEL_UP_RATIO_HIGH : RULES.LEVEL_UP_RATIO;
  const dAtk = Math.max(1, Math.round(u.base.ATK * r));
  const dHp = Math.max(1, Math.round(u.base.HP * r));
  u.level = next; u.raw.ATK += dAtk; u.card.ATK += dAtk; u.maxHp += dHp; u.card.HP = u.maxHp; u.hp += dHp;
  u.gains.push({ dAtk, dHp });
  return { dAtk, dHp };
}
/** 레벨 1 하락 (올랐던 만큼 되돌림, XP 0) */
export function levelDown(u) {
  if (u.level <= 1) return;
  const g = u.gains.pop() || { dAtk: 0, dHp: 0 };
  u.level--; u.xp = 0; u.raw.ATK -= g.dAtk; u.maxHp -= g.dHp; u.card.HP = u.maxHp; u.hp = Math.max(1, Math.min(u.hp, u.maxHp));
}

/** XP 획득 → 가능한 만큼 레벨업. 레벨업이 없으면 null */
export function gainXp(u, xp) {
  if (u.hp <= 0 || u.level >= RULES.LEVEL_MAX) return null;
  u.xp += xp;
  let dAtk = 0, dHp = 0, from = u.level;
  while (u.level < RULES.LEVEL_MAX && u.xp >= xpToNext(u.level)) {
    u.xp -= xpToNext(u.level); const d = levelUpOnce(u); dAtk += d.dAtk; dHp += d.dHp;
  }
  if (u.level >= RULES.LEVEL_MAX) u.xp = 0;
  if (u.level > from) onLevelChange(u);
  return u.level > from ? { dAtk, dHp, level: u.level, from } : null;
}

/** 턴 종료: 살아있는 필드 카드마다 XP. 레벨업 이벤트 목록 반환 */
export function endTurnXp(p) {
  const ev = [];
  for (const u of p.field) { const lv = gainXp(u, RULES.TURN_END_XP); if (lv) ev.push({ type: 'levelup', unit: u, ...lv }); }
  return ev;
}

// ===== 공격 대상 규칙 =====
/** 자기 첫 N턴 동안은 영웅 공격 불가 */
export const heroLocked = me => (me.turnsTaken || 0) <= RULES.HERO_LOCK_TURNS;

/** 공격 가능한 대상 목록: { units: [...], hero: bool, reason } */
export function attackTargets(me, opp, attacker = null) {
  // 도발당함(김후 [나는 약하지 않아]): 그 카드는 도발한 카드만 공격 가능
  const pv = attacker?.st?.provoked?.by;
  if (pv && pv.hp > 0 && opp.field.includes(pv) && !pv.undying) return { units: [pv], hero: false, reason: `도발당함: ${pv.card.name}만 공격할 수 있습니다` };
  // 스토리 보스(undying): 진영 안에 있어 공격 대상이 아니고, 진영 방어(HERO_GUARD_FIELD) 장수에도 세지 않음
  const field = opp.field.filter(u => !u.undying);
  const taunts = field.filter(u => hasSkill(u, 'taunt'));
  if (taunts.length) return { units: taunts, hero: false, reason: '도발 카드부터 공격해야 합니다' };
  if (opp.noBase) return { units: field, hero: false, reason: '일반전: 상대 카드를 모두 쓰러뜨리세요' };
  if (me.clearFirst && field.length) return { units: field, hero: false, reason: '카드 먼저 제거: 상대 카드를 모두 쓰러뜨린 뒤 진영을 공격할 수 있어요' };
  if (heroLocked(me)) return { units: field, hero: false, reason: `첫 ${RULES.HERO_LOCK_TURNS}턴에는 진영을 공격할 수 없습니다` };
  if (field.length >= RULES.HERO_GUARD_FIELD) return { units: field, hero: false, reason: `상대 필드에 ${RULES.HERO_GUARD_FIELD}장 이상 있으면 카드만 공격할 수 있습니다` };
  return { units: field, hero: true, reason: '' };
}
export function canTarget(me, opp, target, attacker = null) {
  const t = attackTargets(me, opp, attacker);
  return target ? t.units.includes(target) : t.hero;
}

/** 일괄 공격/강제 공격용 대상: 처치 가능(+생존) → 처치 가능 → HP 낮은 순. 영웅 공격 가능하면 null(영웅) */
export function pickFieldTarget(u, units) {
  let best, bestScore = -Infinity;
  for (const t of units) {
    const kill = calcDamageG(u.card, t.card) >= t.hp, die = false;   // 반격으로는 쓰러지지 않음
    const score = (kill ? 2e6 : 0) + (kill && !die ? 1e6 : 0) + (kill ? t.card.cost * 1000 : 0) - t.hp;
    if (score > bestScore) { bestScore = score; best = t; }
  }
  return best;
}
/** 공격 대상 선택 (null=영웅, undefined=공격 불가) */
export function autoTarget(u, me, opp) {
  const t = attackTargets(me, opp, u);
  if (t.hero) return null;
  return t.units.length ? pickFieldTarget(u, t.units) : undefined;
}

// ===== 아이템 =====
export const ITEMS = {
  weapon: { label: '무기', icon: '🗡️', img: 'weapon', cost: () => RULES.WEAPON_COST, desc: () => `ATK +${Math.round(RULES.WEAPON_ATK_RATIO * 100)}%` },
  armor:  { label: '방어구', icon: '🛡️', cost: () => RULES.ARMOR_COST, desc: () => `HP +${Math.round(RULES.ARMOR_HP_RATIO * 100)}%` },
};
export function canEquip(type, unit, p) {
  const cost = ITEMS[type].cost();
  if (unit.items?.[type]) return { ok: false, cost, reason: `이미 ${ITEMS[type].label} 장착` };
  if (p.mana < cost) return { ok: false, cost, reason: `마나 부족 (${p.mana}/${cost})` };
  return { ok: true, cost };
}
export function equip(type, unit, p) {
  const c = canEquip(type, unit, p);
  if (!c.ok) return c;
  p.mana -= c.cost; unit.items = { ...unit.items, [type]: true };
  if (type === 'weapon') { const d = Math.max(1, Math.round(unit.base.ATK * RULES.WEAPON_ATK_RATIO)); unit.raw.ATK += d; refreshAll(p); return { ok: true, d }; }
  const d = Math.max(1, Math.round(unit.base.HP * RULES.ARMOR_HP_RATIO));
  unit.maxHp += d; unit.card.HP = unit.maxHp; unit.hp += d;
  return { ok: true, d };
}

/**
 * 전투 처리 (게임·시뮬레이션 공용). me/opp: 플레이어 객체, unit: 공격자, target: 대상 유닛 또는 null(영웅).
 * 처치 보상: 공격자 처치 → 레벨업 + 마나 환급 + 초과 피해 영웅에게. 처치하면 반격 없음, 반격은 50%이고 공격자는 반격으로 쓰러지지 않음(HP 1).
 * 반환: 이벤트 목록 (로그·연출용)
 */
/** 반격 피해: 받는 쪽은 HP 1 아래로 내려가지 않음. 실제 깎인 양 반환 */
export function counterHit(u, dmg, src) {
  if (dmg <= 0 || u.hp <= 0) return 0;
  const before = u.hp, r = damageUnit(u, dmg, src, { silent: true });
  if (u.hp < 1) u.hp = 1;
  return Math.min(r, before - u.hp);
}
export function resolveAttack(me, opp, unit, target) {
  const ev = [];
  unit.canAttack = false;
  refreshAll(me);
  const locked = heroLocked(me);
  const lure = maleLure(unit, opp);   // 최윤희·이혜경: 남성 기본 공격(영웅 포함) 유도
  if (lure && lure !== target) target = lure;
  if (!target) {
    if (locked) return ev;
    const dmg = damageHero(opp, calcDamage(unit.card, null), me, 'attack', unit);
    ev.push({ type: 'hero', who: 'me', unit, dmg });
    gainXp(unit, RULES.ATTACK_XP);
    return ev;
  }
  const rd = redirectAttack(unit, target);
  if (rd.decoyOf) {   // 대신 맞기: 공격자 쪽 카드가 맞고 반격 없음, 처치 XP는 시전자
    const proxy = rd.target, caster = rd.decoyOf;
    const r1 = damageUnit(proxy, calcDamage(unit.card, proxy.card), unit, { silent: true });
    ev.push({ type: 'hit', unit, target: proxy, d1: r1, d2: 0, mult: elementMultiplier(unit.card.class, proxy.card.class) });
    if (proxy.hp <= 0 && checkDeath(proxy, caster) && caster.st.decoy?.healOnKill) heal(caster, caster.maxHp, '배신의 향연');
    return ev;
  }
  const ratio = rd.ratio || 1; target = rd.target;
  // 회피(정치욱 [그렇게 느려도 되겠어?]): 피해·반격 없음
  if (rollEvade(target, unit)) { ev.push({ type: 'evade', unit, target }); gainXp(unit, RULES.ATTACK_XP); return ev; }
  const d1 = Math.max(1, Math.round(calcDamage(unit.card, target.card) * ratio));
  const tHpBefore = target.hp;
  const r1 = damageUnit(target, d1, unit, { silent: true });
  // 반격: 대상이 쓰러졌으면 없음. 살아 있으면 (피해 × 반격 배율 × 50%), 공격자는 반격으로 쓰러지지 않음(HP 1 남김)
  const killed = target.hp <= 0, d2 = killed ? 0 : Math.max(0, Math.round(calcDamage(target.card, unit.card) * counterMult(target, unit) * RULES.COUNTER_RATIO));
  const r2 = counterHit(unit, d2, target);
  if (r2 > 0 && target.st.thorns?.leech) heal(target, Math.round(r2 * target.st.thorns.leech), '반격 흡혈');   // 고정태 [불을 훔친 자]
  ev.push({ type: 'hit', unit, target, d1: r1, d2: r2, mult: elementMultiplier(unit.card.class, target.card.class), killed, survived: r2 > 0 && unit.hp === 1 });
  const tDead = target.hp <= 0, uDead = unit.hp <= 0;
  if (!uDead) gainXp(unit, RULES.ATTACK_XP);
  if (tDead) checkDeath(target, unit);
  if (uDead) checkDeath(unit, target);
  if (tDead && RULES.OVERFLOW_TO_HERO && !locked) {
    const over = r1 - tHpBefore;
    if (over > 0) { const d = damageHero(opp, over, me, 'overflow', unit); if (d > 0) ev.push({ type: 'overflow', unit, dmg: d }); }
  }
  afterBasicHit(unit, target);
  return ev;
}

/** 턴 시작 마나: 기본 충전 + 처치 보너스(그 턴만 최대치 초과 가능) */
/** 플레이어가 이미 이 카드를 갖고 있는지 (덱·손패·필드) */
export function ownsCard(p, id) { id = String(id); return [...p.deck, ...p.hand, ...p.field.map(u => u.base)].some(c => String(c.id) === id); }

export function refillMana(p) {
  p.turnsTaken = (p.turnsTaken || 0) + 1;   // 자기 턴 수 (영웅 공격 잠금 판정용)
  p.used = {};                            // 턴당 1회 액션 사용 기록 초기화
  p.maxMana = RULES.MANA_MAX;
  const gain = p.turnsTaken === 1 ? RULES.MANA_START : RULES.MANA_PER_TURN + (p.accel || 0) * RULES.ACCEL_BONUS;
  p.mana = Math.min(RULES.MANA_MAX, Math.max(p.mana || 0, 0) + gain) + (p.bonusMana || 0);
  const bonus = p.bonusMana || 0; p.bonusMana = 0;
  return bonus;
}

// ===== 마나 액션 =====
export const ACTIONS = {
  shuffle: { label: '패 섞기', icon: '🔀', img: 'shuffle', cost: () => RULES.SHUFFLE_COST },
  heal:    { label: '기지 보강', icon: '🏰', img: 'base', cost: () => RULES.HEAL_COST },
  buff:    { label: '공격력 강화', icon: '⚔️', img: 'atk', cost: () => RULES.BUFF_COST },
  fieldheal: { label: '필드 회복', icon: '💚', img: 'heal', cost: () => RULES.FIELD_HEAL_COST },
  accel:   { label: '마나 가속기', icon: '⚙️', img: 'gear', cost: () => RULES.ACCEL_COST },
};

/** 셔플용 전체 카드 풀 */
let CARD_POOL = [];
export function setCardPool(pool) { CARD_POOL = pool; }

/** 희생: 필드 카드 제거 → 코스트 × 비율 마나. 턴당 1회 */
export const sacrificeGain = card => Math.ceil(card.cost * RULES.SACRIFICE_RATIO);
export function canSacrifice(unit, p) {
  const gain = sacrificeGain(unit.card);
  if (p.used?.sacrifice) return { ok: false, gain, reason: '이번 턴 희생함' };
  if (!p.field.includes(unit)) return { ok: false, gain, reason: '필드 카드 아님' };
  if (unit.undying) return { ok: false, gain, reason: '보스는 희생할 수 없음' };
  return { ok: true, gain };
}
export function sacrifice(unit, p) {
  const c = canSacrifice(unit, p);
  if (!c.ok) return c;
  p.used = { ...(p.used || {}), sacrifice: true };
  p.field.splice(p.field.indexOf(unit), 1);
  (p.grave ||= []).push(unit.base);
  p.mana += c.gain;
  refreshAll(p);
  return { ok: true, gain: c.gain };
}
/** AI 희생: 손패 카드를 희생 마나로 낼 수 있게 되고, 희생 카드가 그보다 훨씬 싸고 투자 안 된 경우 */
export function aiPickSacrifice(me, opp) {
  if (me.used?.sacrifice || !me.field.length) return null;
  const cands = me.field.filter(u => !u.undying && u.level <= 2 && !u.items?.weapon && !u.items?.armor).sort((a, b) => a.card.cost - b.card.cost);
  for (const u of cands) {
    const gain = sacrificeGain(u.card);
    const want = me.hand.filter(c => c.cost > me.mana && c.cost <= me.mana + gain && c.cost >= u.card.cost * 2 && !(c.class === 'ABYSS' && opp.field.some(x => x.card.class === 'LIGHT')));
    if (want.length) return u;
  }
  return null;
}
/** AI 가속기: 초반(자기 8턴 이내)에 마나가 남으면 투자 */
export function aiWantAccel(me, early = false) {
  if (!canAction('accel', me).ok) return false;
  const t = me.turnsTaken || 0;
  return early ? t >= 2 && t <= 6 && (me.accel || 0) < 3 : t <= 10;
}

/** 턴 제한 판정: 진영 HP → 필드 카드 수 → 무승부. a,b 플레이어. 반환 { winner: a|b|null, reason } */
export function judgeTimeout(a, b) {
  if (a.hp !== b.hp) return { winner: a.hp > b.hp ? a : b, reason: 'hp' };
  if (a.field.length !== b.field.length) return { winner: a.field.length > b.field.length ? a : b, reason: 'cards' };
  return { winner: null, reason: 'draw' };
}
export const JUDGE_LABEL = { ko: 'KO', hp: '진영 HP 우세', cards: '남은 카드 수 우세', draw: '무승부' };

/** 액션 사용 가능 여부 */
/** 스토리 전투에서 쓰지 않는 고유기술 (양쪽 모두) */
export const STORY_NO_ACTS = new Set(['accel', 'fieldheal']);   // 스토리·퀘스트: 공격력 강화는 사용 가능 (2026-10-22)
/** 아케이드 일반대전(기본 설정) 이외 모드에서 막는 전투 보조: 기지 보강·필드 회복 (용병 고용은 game.js) */
export const LIMITED_NO_ACTS = new Set(['heal', 'fieldheal']);
export function canAction(type, p) {
  const cost = ACTIONS[type].cost();
  if (type === 'heal' && p.noBase) return { ok: false, cost, reason: '일반전 불가' };
  if (p.noActs && STORY_NO_ACTS.has(type)) return { ok: false, cost, reason: '스토리 불가' };
  if (p.limitedAids && LIMITED_NO_ACTS.has(type)) return { ok: false, cost, reason: '일반대전 전용' };
  if (p.actionLock > 0) return { ok: false, cost, reason: '고유기술 봉인' };
  if (type === 'accel' && (p.accel || 0) >= RULES.ACCEL_MAX) return { ok: false, cost, reason: `최대 ${RULES.ACCEL_MAX}회` };
  if (type !== 'accel' && p.used?.[type]) return { ok: false, cost, reason: '이번 턴 사용함' };
  if (p.mana < cost) return { ok: false, cost, reason: `마나 부족 (${p.mana}/${cost})` };
  if (type === 'shuffle' && !p.hand.length) return { ok: false, cost, reason: '손패 없음' };
  if (type === 'heal' && p.hp >= (p.maxHp || RULES.HERO_HP)) return { ok: false, cost, reason: 'HP 최대' };
  if (type === 'buff' && !p.field.length) return { ok: false, cost, reason: '필드 카드 없음' };
  if (type === 'fieldheal' && !p.field.some(u => u.hp < u.maxHp)) return { ok: false, cost, reason: '회복할 카드 없음' };
  return { ok: true, cost };
}

/** 액션 실행. 결과 정보 반환 (실패 시 ok:false) */
export function doAction(type, p) {
  const c = canAction(type, p);
  if (!c.ok) return c;
  p.mana -= c.cost; p.used = { ...(p.used || {}), [type]: true };
  if (type === 'accel') { p.accel = (p.accel || 0) + 1; return { ok: true, n: p.accel }; }
  if (type === 'shuffle') {
    // 손패를 버리고 전체 카드 풀에서 완전히 새 카드를 뽑음 (MYTHIC 제외, 심연은 덱 제한 준수)
    const n = p.hand.length;
    // 중복 금지: 덱·손패·필드·무덤(부활 가능)에 있는 카드는 제외
    const own = new Set([...p.deck, ...p.hand, ...p.field.map(u => u.base), ...(p.grave || [])].map(c => c.id));
    let abyss = [...p.deck, ...p.field.map(u => u.base)].filter(c => c.class === 'ABYSS').length;
    const fresh = [];
    for (const c of shuffle(p.pool?.length ? p.pool : CARD_POOL.length ? CARD_POOL : [...p.deck, ...p.hand])) {   // p.pool: 아케이드 등급 제한 시 허용 카드만
      if (fresh.length >= n) break;
      if (own.has(c.id) || c.grade === 'MYTHIC RARE') continue;
      if (c.class === 'ABYSS') { if (abyss >= RULES.MAX_ABYSS_PER_DECK) continue; abyss++; }
      fresh.push(c); own.add(c.id);
    }
    for (const c of p.hand) { if (fresh.length >= n) break; if (!fresh.includes(c)) fresh.push(c); }   // 허용 카드가 부족하면(등급 제한) 기존 손패로 채움
    p.hand = fresh;
    return { ok: true, n };
  }
  if (type === 'heal') {
    const before = p.hp; p.hp = Math.min(p.maxHp || RULES.HERO_HP, p.hp + Math.round(RULES.HEAL_AMOUNT * (p.maxHp || RULES.HERO_HP) / RULES.HERO_HP));
    return { ok: true, healed: p.hp - before };
  }
  if (type === 'fieldheal') {
    let total = 0;
    p.field.forEach(u => { const h = Math.min(u.maxHp - u.hp, Math.max(1, Math.round(u.maxHp * RULES.FIELD_HEAL_RATIO))); u.hp += h; total += h; });
    return { ok: true, n: p.field.length, healed: total };
  }
  // buff: 이번 턴 동안만. 늘어난 양을 기록해 두었다가 턴이 끝나면 되돌림
  p.field.forEach(u => { const d = Math.max(1, Math.round(u.raw.ATK * RULES.BUFF_RATIO)); u.raw.ATK += d; u.buff = (u.buff || 0) + d; });
  refreshAll(p);
  return { ok: true, n: p.field.length };
}

/** 턴 종료 시 강화 해제 */
export function clearBuff(p) { p.field.forEach(u => { if (u.buff) { u.raw.ATK -= u.buff; u.buff = 0; } }); refreshAll(p); }

// ===== AI 액션 정책 (게임·시뮬레이션 공용) =====
/** 소환 전: 낼 수 있는 카드가 없고 마나가 넉넉하면 패 섞기 */
export function aiWantShuffle(me, opp) {
  if (!canAction('shuffle', me).ok || me.hand.length < 2 || me.field.length >= RULES.FIELD_MAX) return false;
  const playable = me.hand.some(c => canSummon(c, me, opp).ok);
  return !playable && me.mana - RULES.SHUFFLE_COST >= 10;
}
/** 공격 전: 공격 가능한 카드 3장 이상이면 강화 */
export function aiWantBuff(me) { return canAction('buff', me).ok && me.field.filter(u => u.canAttack).length >= 3; }
/** 턴 끝: 영웅 HP 50% 이하이고 마나가 남으면 보강 */
/** 필드 카드 2장 이상이 최대 HP의 80% 미만이면 필드 회복 */
export function aiWantFieldHeal(me) { return canAction('fieldheal', me).ok && me.field.filter(u => u.hp < u.maxHp * 0.8).length >= 2; }
/** 아이템: 남은 마나로 가장 비싼 카드부터 무기 → 방어구 (마나 10은 남김). 장착할 [type, unit] 반환 */
export function aiPickItem(me, opp) {
  const enemies = opp ? opp.field : [];
  for (const u of [...me.field].sort((a, b) => b.card.cost - a.card.cost)) {
    if (u.card.cost < 15 || u.hp < u.maxHp * 0.5) continue;               // 저가치·빈사 카드엔 투자 안 함
    const threatened = enemies.some(t => calcDamage(t.card, u.card) >= u.hp);
    for (const type of ['weapon', 'armor']) {
      if (threatened && type === 'weapon') continue;                       // 곧 죽을 카드에 무기 X (방어구는 살릴 수 있으면 OK)
      if (threatened && type === 'armor' && enemies.some(t => calcDamage(t.card, u.card) >= u.hp + Math.round(u.base.HP * RULES.ARMOR_HP_RATIO))) continue;
      if (canEquip(type, u, me).ok && me.mana - ITEMS[type].cost() >= 10) return [type, u];
    }
  }
  return null;
}
export function aiWantHeal(me) { return canAction('heal', me).ok && me.hp <= (me.maxHp || RULES.HERO_HP) * 0.5; }

export function shuffle(a) { a = [...a]; for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; } return a; }

/** 등급 확률 30장 덱: 슬롯마다 DRAW_RATES로 등급 추첨 → 그 등급에서 중복 없이 1장. 심연 최대 1장, MR 최대 1장.
 *  grades(Set|null): 허용 등급(양측 공통). 제외 등급은 확률 0 → 남은 등급끼리 재정규화. 허용 카드가 30장보다 적으면 중복 허용 */
export function buildDeck(pool, rng = Math.random, grades = null) {
  const allowed = pool.filter(c => !grades || grades.has(c.grade));
  if (!allowed.length) return [];
  const by = {}; for (const c of allowed) (by[c.grade] ||= []).push(c);
  const deck = [], used = new Set(); let abyss = 0, myth = 0;
  const ok = c => !(c.class === 'ABYSS' && abyss >= RULES.MAX_ABYSS_PER_DECK) && !(c.grade === 'MYTHIC RARE' && myth >= RULES.MAX_MYTHIC_PER_DECK);
  const take = c => { deck.push(c); used.add(c); if (c.class === 'ABYSS') abyss++; if (c.grade === 'MYTHIC RARE') myth++; };
  for (let guard = 0; deck.length < RULES.DECK_SIZE && guard < 2000; guard++) {
    const gs = Object.keys(by).filter(g => by[g].some(c => !used.has(c) && ok(c)));
    if (!gs.length) break;
    const tot = gs.reduce((t, g) => t + (RULES.DRAW_RATES[g] || 0), 0);
    let r = rng() * tot, g = gs[gs.length - 1];
    if (tot > 0) for (const x of gs) { if ((r -= RULES.DRAW_RATES[x] || 0) < 0) { g = x; break; } }
    else g = gs[Math.floor(rng() * gs.length)];
    const cand = by[g].filter(c => !used.has(c) && ok(c));
    take(cand[Math.floor(rng() * cand.length)]);
  }
  // 허용 카드가 부족하면(예: UR만) 중복으로 채움
  const filler = allowed.filter(c => c.class !== 'ABYSS' && c.grade !== 'MYTHIC RARE');
  const fill = filler.length ? filler : allowed;
  while (deck.length < RULES.DECK_SIZE) deck.push(fill[Math.floor(rng() * fill.length)]);
  return shuffle(deck);
}

/** AI: 소환 순서 (비싼 카드 우선) */
export function aiSummonOrder(hand) { return [...hand].sort((a, b) => b.cost - a.cost || b.power - a.power); }

/** AI: 공격 대상. 유리한 교환 우선, 없으면 영웅(null). 영웅 공격 불가면 강제로 필드 카드 선택, 대상 없으면 undefined */
export function aiPickTarget(u, me, opp) {
  const allowed = attackTargets(me, opp, u);
  let best = null, bestScore = 0;
  for (const t of allowed.units) {
    const kill = calcDamageG(u.card, t.card) >= t.hp;
    const die = false;   // 처치하면 반격 없음 · 반격으로는 쓰러지지 않음
    let score = 0;
    if (kill && !die) score = 100 + t.card.power;
    else if (kill && die && t.card.power > u.card.power) score = 50 + t.card.power - u.card.power;
    if (score > bestScore) { bestScore = score; best = t; }
  }
  if (best) return best;
  if (allowed.hero) return null;
  return allowed.units.length ? pickFieldTarget(u, allowed.units) : undefined;
}

export function parseCSV(text) {
  const lines = text.replace(/^\uFEFF/, '').trim().split(/\r?\n/);
  const headers = lines[0].split(',').map(h => h.trim());
  const NUM = ['age', 'power', 'HP', 'ATK', 'DEF', 'PHY', 'MEN', 'MOR', 'cost'];
  return lines.slice(1).filter(l => l.trim()).map(l => {
    const v = l.split(','); const o = {};
    headers.forEach((h, i) => { const s = (v[i] || '').trim(); o[h] = NUM.includes(h) ? Number(s) : h === 'skills' ? s.split('|').filter(Boolean) : s; });
    return o;
  });
}
