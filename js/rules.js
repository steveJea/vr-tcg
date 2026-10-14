// ===== VR TCG 규칙 (순수 함수: UI와 분리, 테스트 가능) =====
export const RULES = {
  HERO_HP: 3000,          // 영웅 HP
  DAMAGE_MULT: 1.5,       // ATK에 곱하는 전체 데미지 배율 (DEF 차감 전)
  FIELD_MAX: 5, DECK_SIZE: 30, OPENING_HAND: 4,
  MANA_PER_TURN: 10, MANA_MAX: 100, MAX_ABYSS_PER_DECK: 1,
  // 덱 구성 (등급별 장수, 합계 30)
  DECK_COMPOSITION: { 'NORMAL': 10, 'RARE': 8, 'HIGH RARE': 6, 'SUPER RARE': 4, 'ULTRA RARE': 2 },
  MYTHIC_CHANCE: 0.15,
  SECOND_PLAYER_BONUS_CARDS: 1,
  RECALL_COST_RATIO: 0.5,  // 회수 비용 = ceil(코스트 × 비율)
  AI_RECALL_MIN_COST: 30,  // AI가 회수를 고려하는 최소 코스트
  KILL_MANA_REFUND_RATIO: 0.2, // 처치 시 다음 턴 보너스 마나 = ceil(처치 카드 코스트 × 비율), 그 턴만 최대치 초과 가능
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
};

export const ELEMENTS = {
  FIRE:  { label: '불',   icon: '🔥', color: 'text-orange-400', ring: 'ring-orange-500' },
  WIND:  { label: '바람', icon: '🌪️', color: 'text-teal-300',   ring: 'ring-teal-400' },
  ICE:   { label: '얼음', icon: '❄️', color: 'text-sky-300',    ring: 'ring-sky-400' },
  DARK:  { label: '어둠', icon: '🌑', color: 'text-purple-400', ring: 'ring-purple-500' },
  LIGHT: { label: '빛',   icon: '✨', color: 'text-yellow-300', ring: 'ring-yellow-400' },
  ABYSS: { label: '심연', icon: '💀', color: 'text-rose-500',   ring: 'ring-rose-600' },
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

/** 데미지 = max(1, floor(ATK × DAMAGE_MULT × 속성배율 − 대상DEF/2)). 영웅은 DEF 0, 속성 없음. */
export function calcDamage(attacker, target) {
  const mult = target ? elementMultiplier(attacker.class, target.class) : 1;
  const def = target ? target.DEF : 0;
  return Math.max(1, Math.floor(attacker.ATK * RULES.DAMAGE_MULT * mult - def / 2));
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
  return { uid, base: card, card: { ...card }, hp: card.HP, maxHp: card.HP, level: 1, xp: 0, items: {}, skills: [...(card.skills || [])], canAttack: false };
}

// ===== 스킬 훅 (아직 카드에 배정하지 않음). 카드 데이터에 skills: ['taunt'] 형태로 지정 =====
export const SKILLS = {
  taunt: { label: '도발', icon: '🎯', desc: '상대는 도발 카드부터 공격해야 합니다' },
};
export const hasSkill = (u, id) => !!u.skills?.includes(id);

/** 처치 XP: 레벨 높은 카드를 잡을수록 더 많이 */
export function killXp(victim) { return Math.round(victim.card.cost * (1 + victim.level * RULES.KILL_XP_LEVEL_BONUS)); }

/** 다음 레벨까지 필요 XP */
export function xpToNext(level) { return level >= RULES.LEVEL_MAX ? Infinity : Math.round(RULES.XP_BASE * Math.pow(level, RULES.XP_EXP)); }

/** 한 번 레벨업 (원본 기준 증가, Lv6부터 체감) */
function levelUpOnce(u) {
  const next = u.level + 1;
  const r = next >= RULES.LEVEL_HIGH_FROM ? RULES.LEVEL_UP_RATIO_HIGH : RULES.LEVEL_UP_RATIO;
  const dAtk = Math.max(1, Math.round(u.base.ATK * r));
  const dHp = Math.max(1, Math.round(u.base.HP * r));
  u.level = next; u.card.ATK += dAtk; u.maxHp += dHp; u.card.HP = u.maxHp; u.hp += dHp;
  return { dAtk, dHp };
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
export function attackTargets(me, opp) {
  const taunts = opp.field.filter(u => hasSkill(u, 'taunt'));
  if (taunts.length) return { units: taunts, hero: false, reason: '도발 카드부터 공격해야 합니다' };
  if (heroLocked(me)) return { units: [...opp.field], hero: false, reason: `첫 ${RULES.HERO_LOCK_TURNS}턴에는 영웅을 공격할 수 없습니다` };
  if (opp.field.length >= RULES.HERO_GUARD_FIELD) return { units: [...opp.field], hero: false, reason: `상대 필드에 ${RULES.HERO_GUARD_FIELD}장 이상 있으면 카드만 공격할 수 있습니다` };
  return { units: [...opp.field], hero: true, reason: '' };
}
export function canTarget(me, opp, target) {
  const t = attackTargets(me, opp);
  return target ? t.units.includes(target) : t.hero;
}

/** 일괄 공격/강제 공격용 대상: 처치 가능(+생존) → 처치 가능 → HP 낮은 순. 영웅 공격 가능하면 null(영웅) */
export function pickFieldTarget(u, units) {
  let best, bestScore = -Infinity;
  for (const t of units) {
    const kill = calcDamage(u.card, t.card) >= t.hp, die = calcDamage(t.card, u.card) >= u.hp;
    const score = (kill ? 2e6 : 0) + (kill && !die ? 1e6 : 0) + (kill ? t.card.cost * 1000 : 0) - t.hp;
    if (score > bestScore) { bestScore = score; best = t; }
  }
  return best;
}
/** 공격 대상 선택 (null=영웅, undefined=공격 불가) */
export function autoTarget(u, me, opp) {
  const t = attackTargets(me, opp);
  if (t.hero) return null;
  return t.units.length ? pickFieldTarget(u, t.units) : undefined;
}

// ===== 아이템 =====
export const ITEMS = {
  weapon: { label: '무기', icon: '🗡️', cost: () => RULES.WEAPON_COST, desc: () => `ATK +${Math.round(RULES.WEAPON_ATK_RATIO * 100)}%` },
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
  if (type === 'weapon') { const d = Math.max(1, Math.round(unit.base.ATK * RULES.WEAPON_ATK_RATIO)); unit.card.ATK += d; return { ok: true, d }; }
  const d = Math.max(1, Math.round(unit.base.HP * RULES.ARMOR_HP_RATIO));
  unit.maxHp += d; unit.card.HP = unit.maxHp; unit.hp += d;
  return { ok: true, d };
}

/**
 * 전투 처리 (게임·시뮬레이션 공용). me/opp: 플레이어 객체, unit: 공격자, target: 대상 유닛 또는 null(영웅).
 * 처치 보상: 공격자 처치 → 레벨업 + 마나 환급 + 초과 피해 영웅에게 / 반격 처치 → 레벨업 + 마나 환급(초과 피해 없음).
 * 반환: 이벤트 목록 (로그·연출용)
 */
export function resolveAttack(me, opp, unit, target) {
  const ev = [];
  unit.canAttack = false;
  const locked = heroLocked(me);
  if (!target) {
    if (locked) return ev;
    const dmg = calcDamage(unit.card, null);
    opp.hp = Math.max(0, opp.hp - dmg);
    ev.push({ type: 'hero', who: 'me', unit, dmg });
    const lv = gainXp(unit, RULES.ATTACK_XP);
    if (lv) ev.push({ type: 'levelup', unit, ...lv });
    return ev;
  }
  const d1 = calcDamage(unit.card, target.card), d2 = calcDamage(target.card, unit.card);
  const tHpBefore = target.hp;
  target.hp -= d1; unit.hp -= d2;
  ev.push({ type: 'hit', unit, target, d1, d2, mult: elementMultiplier(unit.card.class, target.card.class) });
  const reward = (killer, killerOwner, victim, isAttacker) => {
    const refund = Math.ceil(victim.card.cost * RULES.KILL_MANA_REFUND_RATIO);
    killerOwner.bonusMana = (killerOwner.bonusMana || 0) + refund;
    ev.push({ type: 'refund', owner: killerOwner, killer, refund });
    const lv = gainXp(killer, killXp(victim) + (isAttacker ? RULES.ATTACK_XP : 0));
    if (lv) ev.push({ type: 'levelup', unit: killer, ...lv });
    if (isAttacker && RULES.OVERFLOW_TO_HERO && !locked) {
      const over = d1 - tHpBefore;
      if (over > 0) { opp.hp = Math.max(0, opp.hp - over); ev.push({ type: 'overflow', unit: killer, dmg: over }); }
    }
  };
  if (target.hp <= 0) { opp.field.splice(opp.field.indexOf(target), 1); ev.push({ type: 'destroy', unit: target }); }
  if (unit.hp <= 0) { me.field.splice(me.field.indexOf(unit), 1); ev.push({ type: 'destroy', unit }); }
  if (unit.hp > 0 && target.hp > 0) { const lv = gainXp(unit, RULES.ATTACK_XP); if (lv) ev.push({ type: 'levelup', unit, ...lv }); }
  if (target.hp <= 0) reward(unit, me, target, true);
  if (unit.hp <= 0) reward(target, opp, unit, false);
  return ev;
}

/** 턴 시작 마나: 기본 충전 + 처치 보너스(그 턴만 최대치 초과 가능) */
export function refillMana(p) {
  p.turnsTaken = (p.turnsTaken || 0) + 1;   // 자기 턴 수 (영웅 공격 잠금 판정용)
  p.used = {};                            // 턴당 1회 액션 사용 기록 초기화
  p.maxMana = Math.min(RULES.MANA_MAX, p.maxMana + RULES.MANA_PER_TURN);
  p.mana = p.maxMana + (p.bonusMana || 0);
  const bonus = p.bonusMana || 0; p.bonusMana = 0;
  return bonus;
}

// ===== 마나 액션 =====
export const ACTIONS = {
  shuffle: { label: '패 섞기', icon: '🔀', cost: () => RULES.SHUFFLE_COST },
  heal:    { label: '기지 보강', icon: '🏰', cost: () => RULES.HEAL_COST },
  buff:    { label: '공격력 강화', icon: '⚔️', cost: () => RULES.BUFF_COST },
  fieldheal: { label: '필드 회복', icon: '💚', cost: () => RULES.FIELD_HEAL_COST },
};

/** 액션 사용 가능 여부 */
export function canAction(type, p) {
  const cost = ACTIONS[type].cost();
  if (p.used?.[type]) return { ok: false, cost, reason: '이번 턴 사용함' };
  if (p.mana < cost) return { ok: false, cost, reason: `마나 부족 (${p.mana}/${cost})` };
  if (type === 'shuffle' && !p.hand.length) return { ok: false, cost, reason: '손패 없음' };
  if (type === 'heal' && p.hp >= RULES.HERO_HP) return { ok: false, cost, reason: 'HP 최대' };
  if (type === 'buff' && !p.field.length) return { ok: false, cost, reason: '필드 카드 없음' };
  if (type === 'fieldheal' && !p.field.some(u => u.hp < u.maxHp)) return { ok: false, cost, reason: '회복할 카드 없음' };
  return { ok: true, cost };
}

/** 액션 실행. 결과 정보 반환 (실패 시 ok:false) */
export function doAction(type, p) {
  const c = canAction(type, p);
  if (!c.ok) return c;
  p.mana -= c.cost; p.used = { ...(p.used || {}), [type]: true };
  if (type === 'shuffle') {
    const n = p.hand.length;
    p.deck = shuffle([...p.deck, ...p.hand]); p.hand = p.deck.splice(0, n);
    return { ok: true, n };
  }
  if (type === 'heal') {
    const before = p.hp; p.hp = Math.min(RULES.HERO_HP, p.hp + RULES.HEAL_AMOUNT);
    return { ok: true, healed: p.hp - before };
  }
  if (type === 'fieldheal') {
    let total = 0;
    p.field.forEach(u => { const h = Math.min(u.maxHp - u.hp, Math.max(1, Math.round(u.maxHp * RULES.FIELD_HEAL_RATIO))); u.hp += h; total += h; });
    return { ok: true, n: p.field.length, healed: total };
  }
  // buff: 이번 턴 동안만. 늘어난 양을 기록해 두었다가 턴이 끝나면 되돌림
  p.field.forEach(u => { const d = Math.max(1, Math.round(u.card.ATK * RULES.BUFF_RATIO)); u.card.ATK += d; u.buff = (u.buff || 0) + d; });
  return { ok: true, n: p.field.length };
}

/** 턴 종료 시 강화 해제 */
export function clearBuff(p) { p.field.forEach(u => { if (u.buff) { u.card.ATK -= u.buff; u.buff = 0; } }); }

// ===== AI 액션 정책 (게임·시뮬레이션 공용) =====
/** 소환 전: 낼 수 있는 카드가 없고 마나가 넉넉하면 패 섞기 */
export function aiWantShuffle(me, opp) {
  if (!canAction('shuffle', me).ok || me.hand.length < 2 || me.field.length >= RULES.FIELD_MAX || !me.deck.length) return false;
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
export function aiWantHeal(me) { return canAction('heal', me).ok && me.hp <= RULES.HERO_HP * 0.5; }

export function shuffle(a) { a = [...a]; for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; } return a; }

/** 등급 가중 30장 덱: DECK_COMPOSITION대로 뽑고, MYTHIC_CHANCE 확률로 NORMAL 1장을 MYTHIC 1장으로 교체 (심연 최대 1장) */
export function buildDeck(pool, rng = Math.random) {
  const comp = { ...RULES.DECK_COMPOSITION };
  const deck = [];
  if (rng() < RULES.MYTHIC_CHANCE) {
    const myth = pool.filter(c => c.grade === 'MYTHIC RARE');
    if (myth.length) { deck.push(myth[Math.floor(rng() * myth.length)]); comp['NORMAL']--; }
  }
  let abyss = deck.filter(c => c.class === 'ABYSS').length;
  for (const [grade, n] of Object.entries(comp)) {
    let got = 0;
    for (const c of shuffle(pool.filter(c => c.grade === grade))) {
      if (got >= n) break;
      if (c.class === 'ABYSS') { if (abyss >= RULES.MAX_ABYSS_PER_DECK) continue; abyss++; }
      deck.push(c); got++;
    }
  }
  // 부족분은 아무 카드로 채움
  for (const c of shuffle(pool)) {
    if (deck.length >= RULES.DECK_SIZE) break;
    if (deck.includes(c) || c.grade === 'MYTHIC RARE' || c.class === 'ABYSS') continue;
    deck.push(c);
  }
  return shuffle(deck);
}

/** AI: 소환 순서 (비싼 카드 우선) */
export function aiSummonOrder(hand) { return [...hand].sort((a, b) => b.cost - a.cost || b.power - a.power); }

/** AI: 공격 대상. 유리한 교환 우선, 없으면 영웅(null). 영웅 공격 불가면 강제로 필드 카드 선택, 대상 없으면 undefined */
export function aiPickTarget(u, me, opp) {
  const allowed = attackTargets(me, opp);
  let best = null, bestScore = 0;
  for (const t of allowed.units) {
    const kill = calcDamage(u.card, t.card) >= t.hp;
    const die = calcDamage(t.card, u.card) >= u.hp;
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
