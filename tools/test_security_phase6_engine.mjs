// Local fixtures only. Proves the sweep engine is deterministic and ignores a client win flag.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { ENGINE_VERSION, verifySweep as sourceVerify } from '../supabase/functions/_shared/sweep-engine-v6.mjs';
import { SWEEP_ENGINE_VERSION } from '../js/sweep-engine-version.js';

assert.equal(ENGINE_VERSION, SWEEP_ENGINE_VERSION);
assert.match(ENGINE_VERSION, /^[a-f0-9]{64}$/);

function session(seed, level, extra = {}) {
  return {
    mode: 'tower_sweep', target: 'normal:1', seed,
    snapshot: { leader: 'me-1', cards: [
      { uid: 'me-1', id: '10111', level, ex: 0, exb: 0, boost: {}, skillLv: {} },
    ] },
    ...extra,
  };
}

const weak = sourceVerify(session(1, 1));
const weakAgain = sourceVerify(session(1, 1));
assert.deepEqual(weakAgain, weak, 'same seed and snapshot replay the same result');
assert.equal(weak.my_turns, Math.ceil(weak.turns / 2));
assert.ok(weak.turns >= 1 && weak.turns <= 40);
assert.equal(sourceVerify(session(1, 1, { win: true, reason: 'wipe', turns: 1 })).win, weak.win, 'a client win flag is not an input');

const outcomes = new Set();
for (let seed = 1; seed <= 12; seed++) {
  const a = sourceVerify(session(seed, 1));
  assert.deepEqual(sourceVerify(session(seed, 1)), a);
  outcomes.add(a.win + ':' + a.turns + ':' + a.reason);
}
assert.ok(outcomes.size >= 1);

const strong = sourceVerify(session(7, 80));
assert.equal(strong.win, true, 'a high-level snapshot of the same floor can win');
assert.equal(strong.reason, 'wipe');
assert.notDeepEqual(strong, sourceVerify(session(7, 1)), 'card level changes the replay');
const loss = sourceVerify({ ...session(3, 1), target: 'normal:39' });
assert.equal(loss.win, false);
assert.equal(loss.reason, 'wipe');
assert.deepEqual(sourceVerify({ ...session(3, 1), target: 'normal:39' }), loss);
assert.throws(() => sourceVerify({ ...session(1, 80), target: 'normal:10' }), /boss floor/);
assert.throws(() => sourceVerify({ ...session(1, 80), mode: 'story' }), /not a sweep/);
const quest = await readFile(new URL('../js/quest.js', import.meta.url), 'utf8');
const sweepFn = quest.slice(quest.indexOf('async function settleSweep'), quest.indexOf('function mount()'));
assert.match(sweepFn, /story-tower-verify-v6/);
assert.match(sweepFn, /settleSweep\(session\)/);
assert.match(quest, new RegExp(ENGINE_VERSION));
assert.doesNotMatch(sweepFn, /battle_session_finish_v2/);

let losses = 0, wins = 0;
for (let seed = 1; seed <= 12; seed++) {
  const row = sourceVerify({ ...session(seed, 1), target: 'normal:2' });
  if (row.win) wins++; else losses++;
  assert.ok(row.win ? row.reason === 'wipe' : row.reason === 'wipe' || row.reason === 'timeout');
}
assert.ok(wins + losses === 12);
console.log(`phase6 sweep engine: deterministic replay, client win ignored, level ${strong.win ? 'win' : 'loss'} vs weak outcomes ${[...outcomes].join(', ')}; bundle ${ENGINE_VERSION.slice(0, 12)}`);
