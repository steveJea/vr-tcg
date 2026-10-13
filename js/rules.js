// ===== VR TCG 규칙 (순수 함수: UI와 분리, 테스트 가능) =====
export const RULES = {
  HERO_HP: 5000, FIELD_MAX: 5, DECK_SIZE: 30, OPENING_HAND: 4,
  MANA_PER_TURN: 10, MANA_MAX: 100, MAX_ABYSS_PER_DECK: 1,
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

/** 데미지 = max(1, floor(ATK × 배율 − 대상DEF/2)). 영웅은 DEF 0, 속성 없음. */
export function calcDamage(attacker, target) {
  const mult = target ? elementMultiplier(attacker.class, target.class) : 1;
  const def = target ? target.DEF : 0;
  return Math.max(1, Math.floor(attacker.ATK * mult - def / 2));
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

/** 30장 랜덤 덱 (심연 최대 1장) */
export function buildDeck(pool) {
  const deck = []; let abyss = 0;
  for (const c of shuffle(pool)) {
    if (deck.length >= RULES.DECK_SIZE) break;
    if (c.class === 'ABYSS') { if (abyss >= RULES.MAX_ABYSS_PER_DECK) continue; abyss++; }
    deck.push(c);
  }
  return deck;
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
