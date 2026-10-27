// 균열 토벌 결과 재검증: node tools/raid_verify.mjs attempts.json
// attempts.json = SQL Editor 에서 내려받은 행 배열:
//   select id, stage, difficulty, seed, snap, actions, reported, damage from guild_raid_attempts where kind = 'fight' and finished_at is not null and not voided and week = date_trunc('week', now() at time zone 'Asia/Seoul')::date;
// 같은 seed·스냅샷으로 다시 돌려 보고한 피해와 다르면 출력하고, admin_raid_void SQL 을 만든다. (cards.csv·skills.json 은 그 시점 버전이어야 함)
import { readFileSync } from 'fs';
import { setSkillData } from '../js/skills.js';
import { parseCSV, setCardPool } from '../js/rules.js';
import { runRaid } from '../js/raid-core.js';
import { snapCard } from '../js/pvp-core.js';
const rd = p => readFileSync(new URL(p, import.meta.url), 'utf8');
const pool = parseCSV(rd('../data/cards.csv')); setCardPool(pool); setSkillData(JSON.parse(rd('../data/skills.json')), JSON.parse(rd('../data/combos.json')));
const byId = id => pool.find(c => String(c.id) === String(id));
const rows = JSON.parse(readFileSync(process.argv[2] || 'attempts.json', 'utf8'));
const bad = []; let good = 0;
for (const a of rows) {
  const J = v => typeof v === 'string' ? JSON.parse(v) : v;
  const r = runRaid(J(a.snap).map(o => snapCard(o, byId)).filter(Boolean), +a.stage, a.difficulty, a.seed, byId, null, a.actions ? J(a.actions) : null);   // actions 있으면 수동 판: 기록대로 재생
  if (r.damage === +a.reported) good++; else { bad.push(a.id); console.log(`✕ #${a.id} 보고 ${a.reported} / 재계산 ${r.damage}`); }
}
console.log(`일치 ${good} · 불일치 ${bad.length}`);
for (const id of bad) console.log(`select admin_raid_void(${id}, '재계산 불일치');`);
