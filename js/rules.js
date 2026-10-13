// ===== VR TCG 규칙 (순수 함수: UI와 분리, 테스트 가능) =====
export const RULES = {
  HERO_HP: 3000,          // 영웅 HP
  DAMAGE_MULT: 1.5,       // ATK에 곱하는 전체 데미지 배율 (DEF 차감 전)
  FIELD_MAX: 5, DECK_SIZE: 30, OPENING_HAND: 4,
  MANA_PER_TURN: 10, MANA_MAX: 100, MAX_ABYSS_PER_DECK: 1,
  // 덱 구성 (등급별 장수, 합계 30)
  DECK_COMPOSITION: { 'NORMAL': 10, 'RARE': 8, 'HIGH RARE': 6, 'SUPER RARE': 4, 'ULTRA RARE': 2 },
  MYTHIC_CHANCE: 0.15,    // 덱에 MYTHIC(대부분 ABYSS) 1장이 NORMAL 1장 대신 들어갈 확률
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
