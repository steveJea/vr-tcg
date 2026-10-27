// js/raid-core.js 검증: 같은 seed = 같은 결과 · 보스 목록 = guild3.sql · 한 판 피해 ≤ 서버 상한
import { readFileSync } from 'fs';
import { setSkillData } from '../js/skills.js';
import { parseCSV, setCardPool } from '../js/rules.js';
import { runRaid, RAID_BOSSES, hitCap } from '../js/raid-core.js';
import { snapCard } from '../js/pvp-core.js';
const rd = p => readFileSync(new URL(p, import.meta.url), 'utf8');
const pool = parseCSV(rd('../data/cards.csv')); setCardPool(pool); setSkillData(JSON.parse(rd('../data/skills.json')), JSON.parse(rd('../data/combos.json')));
const byId = id => pool.find(c => String(c.id) === String(id));
let fails = 0; const ok = (c, m) => { if (!c) { fails++; console.log('FAIL', m); } else console.log('ok  ', m); };
const sql = rd('../supabase/guild3.sql');
for (const b of RAID_BOSSES) ok(sql.includes(`"id":${b.id ? `"${b.id}"` : 'null'},"name":"${b.name}","weak":"${b.weak}"`), `보스 ${b.name} = guild3.sql`);
for (const b of RAID_BOSSES) if (b.id) ok(!!byId(b.id), `${b.name} 카드 있음`);
const N = JSON.parse(sql.match(/_raid_numbers\(\) returns jsonb language sql immutable as \$\$ select '([\s\S]*?)'::jsonb/)[1]);
ok(hitCap(1) === N.hit_cap && hitCap(3) === Math.round(N.hit_cap * N.hit_cap_growth ** 2), '행동 상한 = guild3.sql');
const top = pool.filter(c => ['MYTHIC RARE', 'LEGENDARY RARE'].includes(c.grade)).sort((a, b) => b.power - a.power);
let maxRatio = 0;
for (let k = 0; k < 20; k++) {
  const deck = [0, 1, 2, 3, 4].map(i => snapCard({ id: top[(k * 3 + i) % top.length].id, level: 80, exb: 30 }, byId));
  for (const st of [1, 3, 5]) { const r = runRaid(deck, st, 'normal', 99 + k, byId); maxRatio = Math.max(maxRatio, r.damage / (hitCap(st) * N.attempt_hits)); }
}
ok(maxRatio < 1, `강한 덱도 한 판 상한 안 (최대 ${(maxRatio * 100).toFixed(0)}%)`);
const d = [0, 1, 2].map(i => snapCard({ id: top[i].id, level: 30 }, byId));
const a = runRaid(d, 2, 'hard', 777, byId), b = runRaid(d, 2, 'hard', 777, byId);
ok(a.damage === b.damage && a.hits === b.hits && a.damage > 0, '같은 seed = 같은 결과');
console.log(fails ? `${fails} FAIL` : 'ALL PASS'); process.exit(fails ? 1 : 0);
