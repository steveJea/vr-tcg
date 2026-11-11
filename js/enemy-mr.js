// Pre-nerf base stats for Mythic Rare cards when they are tower or raid enemies.
// Player-owned copies keep the nerfed numbers in data/cards.csv. LV_RATE stays 6%.
import { calcPower } from './rules.js';
import { skillsOf } from './skills.js';

export const ENEMY_MR_BASE = {
  '10060': { HP: 1850, ATK: 460, DEF: 440 }, // 김성진
  '10062': { HP: 1900, ATK: 400, DEF: 460 }, // 김신현
  '10311': { HP: 1850, ATK: 450, DEF: 450 }, // 이지영
  '10326': { HP: 1750, ATK: 400, DEF: 385 }, // [각성] 임유리
};

export function applyEnemyMr(card) {
  if (!card) return card;
  const row = ENEMY_MR_BASE[String(card.id)];
  if (!row) return card;
  const next = { ...card, HP: row.HP, ATK: row.ATK, DEF: row.DEF };
  next.power = calcPower(next, skillsOf(card.id));
  return next;
}

globalThis.VREnemyMrApply = applyEnemyMr;
