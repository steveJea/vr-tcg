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
  LEVEL_MAX: 3,               // 처치로 오르는 카드 최대 레벨
  LEVEL_UP_RATIO: 0.1,        // 레벨업마다 ATK·최대HP +10% (최소 +1), 늘어난 만큼 HP 회복
  OVERFLOW_TO_HERO: true,
  // 마나 액션 (모두 턴당 1회)
  SHUFFLE_COST: 50,       // 패 섞기: 손패 전부 덱에 넣고 섞은 뒤 같은 장수 드로우
  HEAL_COST: 20,          // 기지 보강: 영웅 HP 회복
  HEAL_AMOUNT: 300,
  BUFF_COST: 30,          // 공격력 강화: 내 필드 카드 이번 턴 ATK +20%
  BUFF_RATIO: 0.2,     // 공격으로 처치 시 남는 피해를 상대 영웅에게 // 후공 플레이어 시작 손패 추가 장수    // 덱에 MYTHIC(대부분 ABYSS) 1장이 NORMAL 1장 대신 들어갈 확률
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
  if (unit.card.cost < RULES.AI_RECALL_MIN_COST || unit.hp >= unit.card.HP) return false;
  if (!canRecall(unit, me).ok) return false;
  return opp.field.some(t => calcDamage(t.card, unit.card) >= unit.hp);
}

/** 필드 유닛 생성: card는 레벨에 따라 바뀌는 사본, base는 원본(회수 시 원본으로 복귀) */
export function makeUnit(card, uid) {
  return { uid, base: card, card: { ...card }, hp: card.HP, maxHp: card.HP, level: 1, canAttack: false };
}

function levelUp(u) {
  if (u.level >= RULES.LEVEL_MAX || u.hp <= 0) return null;
  const dAtk = Math.max(1, Math.round(u.card.ATK * RULES.LEVEL_UP_RATIO));
  const dHp = Math.max(1, Math.round(u.maxHp * RULES.LEVEL_UP_RATIO));
  u.level++; u.card.ATK += dAtk; u.maxHp += dHp; u.card.HP = u.maxHp; u.hp += dHp;
  return { dAtk, dHp, level: u.level };
}

/**
 * 전투 처리 (게임·시뮬레이션 공용). me/opp: 플레이어 객체, unit: 공격자, target: 대상 유닛 또는 null(영웅).
 * 처치 보상: 공격자 처치 → 레벨업 + 마나 환급 + 초과 피해 영웅에게 / 반격 처치 → 레벨업 + 마나 환급(초과 피해 없음).
 * 반환: 이벤트 목록 (로그·연출용)
 */
export function resolveAttack(me, opp, unit, target) {
  const ev = [];
  unit.canAttack = false;
  if (!target) {
    const dmg = calcDamage(unit.card, null);
    opp.hp = Math.max(0, opp.hp - dmg);
    ev.push({ type: 'hero', who: 'me', unit, dmg });
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
    const lv = levelUp(killer);
    if (lv) ev.push({ type: 'levelup', unit: killer, ...lv });
    if (isAttacker && RULES.OVERFLOW_TO_HERO) {
      const over = d1 - tHpBefore;
      if (over > 0) { opp.hp = Math.max(0, opp.hp - over); ev.push({ type: 'overflow', unit: killer, dmg: over }); }
    }
  };
  if (target.hp <= 0) { opp.field.splice(opp.field.indexOf(target), 1); ev.push({ type: 'destroy', unit: target }); }
  if (unit.hp <= 0) { me.field.splice(me.field.indexOf(unit), 1); ev.push({ type: 'destroy', unit }); }
  if (target.hp <= 0) reward(unit, me, target, true);
  if (unit.hp <= 0) reward(target, opp, unit, false);
  return ev;
}

/** 턴 시작 마나: 기본 충전 + 처치 보너스(그 턴만 최대치 초과 가능) */
export function refillMana(p) {
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
};

/** 액션 사용 가능 여부 */
export function canAction(type, p) {
  const cost = ACTIONS[type].cost();
  if (p.used?.[type]) return { ok: false, cost, reason: '이번 턴 사용함' };
  if (p.mana < cost) return { ok: false, cost, reason: `마나 부족 (${p.mana}/${cost})` };
  if (type === 'shuffle' && !p.hand.length) return { ok: false, cost, reason: '손패 없음' };
  if (type === 'heal' && p.hp >= RULES.HERO_HP) return { ok: false, cost, reason: 'HP 최대' };
  if (type === 'buff' && !p.field.length) return { ok: false, cost, reason: '필드 카드 없음' };
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

/** AI: 공격 대상 (유리한 교환 우선, 없으면 null = 영웅) */
export function aiPickTarget(u, enemyField) {
  let best = null, bestScore = 0;
  for (const t of enemyField) {
    const kill = calcDamage(u.card, t.card) >= t.hp;
    const die = calcDamage(t.card, u.card) >= u.hp;
    let score = 0;
    if (kill && !die) score = 100 + t.card.power;
    else if (kill && die && t.card.power > u.card.power) score = 50 + t.card.power - u.card.power;
    if (score > bestScore) { bestScore = score; best = t; }
  }
  return best;
}

export function parseCSV(text) {
  const lines = text.replace(/^\uFEFF/, '').trim().split(/\r?\n/);
  const headers = lines[0].split(',').map(h => h.trim());
  const NUM = ['age', 'power', 'HP', 'ATK', 'DEF', 'PHY', 'MEN', 'MOR', 'cost'];
  return lines.slice(1).filter(l => l.trim()).map(l => {
    const v = l.split(','); const o = {};
    headers.forEach((h, i) => { const s = (v[i] || '').trim(); o[h] = NUM.includes(h) ? Number(s) : s; });
    return o;
  });
}
