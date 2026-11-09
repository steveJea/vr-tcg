// Replays every row embedded in supabase/staging_sweep_fixture.sql.
// Same call the staging Edge function makes: verifySweep -> runSweep, seed 7,
// one card, no leader skill, no gear, no sigil, no boost/ex/skill levels.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { verifySweep } from '../supabase/functions/_shared/sweep-engine-v6.mjs';

const sql = await readFile(new URL('../supabase/staging_sweep_fixture.sql', import.meta.url), 'utf8');
assert.match(sql, /7703759698107299042/);
assert.match(sql, /insert into _sweep_cfg\(nick, action\) values \('드리고니아', 'apply'\)/);
assert.match(sql, /staging_sweep_fixture_backup/);
assert.match(sql, /v_action = 'revert'/);
assert.doesNotMatch(sql, /_wallet_add|_gem_add|gem_ledger|player_wallet|update public\.story_gacha[^_]/);
assert.match(sql, /story_gacha_log/);
assert.doesNotMatch(sql, /has no story card list/);

const block = sql.slice(sql.indexOf('insert into _sweep_fix'), sql.indexOf('create temp table _sweep_out'));
const rows = [...block.matchAll(/\('(\d+)', (\d+), (\d+), (\d+), '((?:[^']|'')*)'\)/g)].map(m => ({
  id: m[1], level: Number(m[2]), win: Number(m[3]), lose: Number(m[4]), name: m[5].replaceAll("''", "'"),
}));
assert.equal(new Set(rows.map(r => r.id)).size, rows.length);
assert.ok(rows.length >= 300, `expected the solo pair table, got ${rows.length}`);

const levels = new Set([1, 5, 10, 20, 40, 60, 80]);
let bad = 0;
for (const row of rows) {
  assert.equal(row.lose, row.win + 1, row.id);
  assert.ok(row.win % 10 !== 0 && row.lose % 10 !== 0 && row.win % 10 !== 9, row.id);
  assert.ok(levels.has(row.level), row.id);
  const session = floor => ({
    mode: 'tower_sweep',
    target: `normal:${floor}`,
    seed: 7,
    snapshot: {
      leader: null,
      cards: [{ uid: 't', id: row.id, level: row.level, ex: 0, exb: 0, boost: {}, skillLv: {}, gear: [], sigil: null }],
    },
  });
  const win = verifySweep(session(row.win));
  const lose = verifySweep(session(row.lose));
  if (!win.win || lose.win) {
    bad++;
    console.error('mismatch', row, win, lose);
  }
}
assert.equal(bad, 0, `${bad} fixture rows do not match verifySweep`);
console.log(`sweep fixture ${rows.length} solo pairs match verifySweep seed 7`);
