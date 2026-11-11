// Tower floor lineups must match the pre-nerf composition. Selection uses enemy-side
// power from js/enemy-mr.js, which equals the pre-#539 cards.csv power for the four MR cards.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { towerEnemies } from '../supabase/functions/story-direct-verify-v7/engine.mjs';
import { applyEnemyMr } from '../js/enemy-mr.js';
import { bossOf } from '../js/raid-core.js';
import quest from '../data/quest.json' with { type: 'json' };

const PRE_POWER = {
  '10060': 308411, // 김성진
  '10062': 290980, // 김신현
  '10311': 480048, // 이지영
  '10326': 273975, // [각성] 임유리
};
const TOWERS = ['normal', 'wind', 'ice', 'fire', 'light', 'dark'];
const floors = quest.floors.map(f => f.floor);

function lineups(apply) {
  const prev = globalThis.VREnemyMrApply;
  globalThis.VREnemyMrApply = apply;
  try {
    const out = new Map();
    for (const tower of TOWERS) {
      for (const floor of floors) {
        out.set(`${tower}:${floor}`, towerEnemies(tower, floor).enemies.map(c => String(c.id)).join(','));
      }
    }
    return out;
  } finally {
    globalThis.VREnemyMrApply = prev;
  }
}

const prenef = lineups(c => PRE_POWER[String(c.id)] ? { ...c, power: PRE_POWER[String(c.id)] } : c);
const current = lineups(applyEnemyMr);
const diffs = [];
for (const [key, ids] of prenef) if (current.get(key) !== ids) diffs.push(key);
assert.deepEqual(diffs, [], `tower lineups drifted from pre-nerf power: ${diffs.slice(0, 12).join(' ')}`);

const floor349 = current.get('normal:349').split(',');
const prenef349 = prenef.get('normal:349').split(',');
assert.deepEqual(floor349, prenef349);
const yuri = id => id === '10326';
assert.equal(floor349.filter(yuri).length, prenef349.filter(yuri).length);

assert.deepEqual([1, 2, 3, 4, 5].map(stage => bossOf(stage).id), ['10325', '10326', '10062', '10060', '10311']);

console.log(`tower compositions match pre-nerf power on ${prenef.size} floors; normal:349 ${floor349.join(',')}`);
