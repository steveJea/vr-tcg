// Seeded tower-sweep battle. Same decisions as js/quest-sim.js, with the session seed
// driving every combat roll. Callers pass the skill/rules module they already use
// so the browser sim stays isolated from the on-screen battle.
export function rngOf(seed) {
  let a = (Number(seed) >>> 0) || 1;
  return () => {
    a = (a + 0x6D2B79F5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// js/story-data.js leader table. Sweep applies it only when that exact card is on the field.
const LEADER = {
  deathPenalty: 0.3,
  el: {
    FIRE: { atk: 0.05 }, ICE: { def: 0.05 }, WIND: { hp: 0.05 },
    DARK: { atk: 0.03, hp: 0.03 }, LIGHT: { def: 0.03, hp: 0.03 }, ABYSS: { atk: 0.04, def: 0.02 }, VOID: { atk: 0.05, def: 0.03 },
  },
  cls: {
    CHARGE: { atk: 0.03 }, DEFENSE: { def: 0.04 }, CRUSH: { atk: 0.02, def: 0.02 }, SUPPORT: { hp: 0.04 },
    DISTURB: { eAtk: 0.03 }, FASCINATION: { eDef: 0.03 },
    OVERWHELMING: { atk: 0.05, def: 0.05 }, FURIOUS: { atk: 0.05, eDef: 0.05 },
    PHENOMENAL: { atk: 0.03, def: 0.03, hp: 0.04 }, EXTERMINATE: { atk: 0.04, eDef: 0.03, eAtk: 0.02 },
    BALANCE: { def: 0.04, hp: 0.04 }, UNLIMITED: { atk: 0.06, eDef: 0.03 },
  },
};
export function leaderSkill(card) {
  if (!card) return null;
  const el = LEADER.el[card.class] || {}, cl = LEADER.cls[card.attribute] || {}, e = { deathPenalty: LEADER.deathPenalty };
  for (const k of ['atk', 'def', 'hp', 'eAtk', 'eDef']) {
    const v = Math.round(((el[k] || 0) + (cl[k] || 0)) * 1000) / 1000;
    if (v) e[k] = v;
  }
  return e;
}

export function runSweep(SK, R, { me, ai, maxTurns = 40, leader = null, seed }) {
  if (!Number.isSafeInteger(seed) || seed < 1 || seed > 2147483646) throw new Error('invalid sweep seed');
  if (!Array.isArray(me) || !Array.isArray(ai) || !me.length || !ai.length) throw new Error('invalid sweep decks');
  const r = rngOf(seed);
  const oldRandom = Math.random;
  const oldEmit = SK.getEmitter();
  Math.random = r;
  SK.setRng(r);
  SK.setEmitter(() => {});
  try {
    const mk = name => ({ name, hp: 1, maxHp: 1, deck: [], hand: [], field: [], mana: 0, maxMana: 0, noBase: true });
    const P = [mk('나'), mk('적')];
    const firstMe = r() < 0.5;
    SK.initPlayers(P[0], P[1], firstMe ? P[0] : P[1]);
    for (const c of me) {
      const u = SK.placeUnit(P[0], { ...c }, R.makeUnit);
      if (leader && c.uid && c.uid === leader.uid && !P[0].field.some(x => x.isLeader)) {
        u.isLeader = true;
        P[0].leaderSkill = leader;
      }
    }
    for (const c of ai) SK.placeUnit(P[1], { ...c }, R.makeUnit);
    SK.refreshAll(P[0]);
    SK.refreshAll(P[1]);
    const gone = p => !p.field.some(u => u.hp > 0);
    const end = () => gone(P[1]) ? 1 : gone(P[0]) ? 0 : -1;
    const turns = Math.max(1, Math.min(40, maxTurns | 0 || 40));
    for (let t = 0; t < turns; t++) {
      const cur = P[(t + (firstMe ? 0 : 1)) % 2], op = cur.foe;
      R.clearBuff(op);
      R.refillMana(cur);
      cur.field.forEach(u => { u.canAttack = true; });
      SK.turnStart(cur);
      let e = end();
      if (e >= 0) return { win: !!e, turns: t + 1, timeout: false };
      for (const u of [...cur.field]) {
        if (!cur.field.includes(u) || !u.canAttack) continue;
        const sk = SK.aiPickSkill(u);
        if (sk) SK.useSkill(u, sk);
        else {
          const tg = R.aiPickTarget(u, cur, op);
          if (tg === undefined || tg === null) continue;
          R.resolveAttack(cur, op, u, tg);
        }
        e = end();
        if (e >= 0) return { win: !!e, turns: t + 1, timeout: false };
      }
      R.endTurnXp(cur);
      SK.turnEnd(cur);
      e = end();
      if (e >= 0) return { win: !!e, turns: t + 1, timeout: false };
    }
    return { win: false, turns, timeout: true };
  } finally {
    Math.random = oldRandom;
    SK.setRng(oldRandom);
    SK.setEmitter(oldEmit);
  }
}
