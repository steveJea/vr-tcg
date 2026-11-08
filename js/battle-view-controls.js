// Presentation-only controls. Use the exact shared targeting rules; null means
// a legal base attack, while undefined means there is no legal target.
import { autoTarget } from './rules.js';
export const batchAttackReady = (me, opp) => me.field.some(u => u.hp > 0 && u.canAttack && autoTarget(u, me, opp) !== undefined);
export function nextBatchAttack(view, me, opp) {
  while (view.batch?.length) {
    const u = view.batch.shift();
    if (!me.field.includes(u) || !u.canAttack || u.hp <= 0) continue;
    const target = autoTarget(u, me, opp);
    if (target === undefined) continue;
    const i = view.A0.indexOf(u), t = target === null ? -1 : view.B0.indexOf(target);
    if (i >= 0 && (target === null || t >= 0)) return { k: 'atk', i, t };
  }
  return null;
}
