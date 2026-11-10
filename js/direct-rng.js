// Seeded RNG for direct story/tower fights. No card data, so the battle page can import it.
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

/** Same rank-band draw as js/story.js pickEnemies. pool is the NORMAL list already sliced by the caller, or the full normal pool. */
export function rollRank(stage, rng, pool) {
  const [a, b] = stage?.enemies?.rank || [0, 0];
  const list = pool.slice(a, b);
  const out = [];
  const count = stage?.enemies?.count | 0;
  while (out.length < count && list.length) out.push(list.splice(Math.floor(rng() * list.length), 1)[0]);
  return out;
}

if (typeof window !== 'undefined') window.VRDirect = { rngOf, rollRank };
