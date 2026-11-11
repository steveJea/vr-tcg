// Re-pairs rows of supabase/staging_sweep_fixture.sql that no longer match verifySweep
// (after a card/skill change moves tower lineups). Same session shape as check_sweep_fixture.mjs.
// Keeps the row's level when possible, picks the closest valid (win, win+1) floor pair. node tools/fix_sweep_fixture.mjs
import { readFile, writeFile } from 'node:fs/promises';
import { verifySweep } from '../supabase/functions/_shared/sweep-engine-v6.mjs';

const url = new URL('../supabase/staging_sweep_fixture.sql', import.meta.url);
const sql = await readFile(url, 'utf8');
const a = sql.indexOf('from (values'), b = sql.indexOf(') as f(id, level, win, lose, name)');
const block = sql.slice(a, b);
const LEVELS = [1, 5, 10, 20, 40, 60, 80];
const memo = new Map();
const wins = (id, level, floor) => {
  const k = `${id}:${level}:${floor}`;
  if (!memo.has(k)) memo.set(k, !!verifySweep({ mode: 'tower_sweep', target: `normal:${floor}`, seed: 7, snapshot: { leader: null, cards: [{ uid: 't', id, level, ex: 0, exb: 0, boost: {}, skillLv: {}, gear: [], sigil: null }] } }).win);
  return memo.get(k);
};
const okFloor = w => w >= 1 && w + 1 <= 349 && w % 10 !== 0 && w % 10 !== 9 && (w + 1) % 10 !== 0;
let fixed = 0, failed = [];
const out = block.replace(/\('(\d+)', (\d+), (\d+), (\d+), '((?:[^']|'')*)'\)/g, (m, id, lv, w, l, name) => {
  lv = Number(lv); w = Number(w);
  if (wins(id, lv, w) && !wins(id, lv, w + 1)) return m;
  for (const level of [lv, ...LEVELS.filter(x => x !== lv).sort((x, y) => Math.abs(x - lv) - Math.abs(y - lv))]) {
    const floors = Array.from({ length: 348 }, (_, i) => i + 1).filter(okFloor).sort((x, y) => Math.abs(x - w) - Math.abs(y - w));
    for (const f of floors) if (wins(id, level, f) && !wins(id, level, f + 1)) { fixed++; console.log(`${id} ${name}: L${lv} ${w}/${w + 1} -> L${level} ${f}/${f + 1}`); return `('${id}', ${level}, ${f}, ${f + 1}, '${name}')`; }
  }
  failed.push(id); return m;
});
await writeFile(url, sql.slice(0, a) + out + sql.slice(b));
console.log(`fixed ${fixed}${failed.length ? `, no pair for ${failed.join(',')}` : ''}`);
if (failed.length) process.exit(1);
