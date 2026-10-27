// PvP 결과 재검증: node tools/pvp_verify.mjs attempts.json
// attempts.json = SQL Editor 에서 내려받은 행 배열:
//   select id, mode, seed, my_snap, opp_snap, actions, wins, losses from pvp_attempts where reported_at is not null and verified is null;
// 같은 seed·스냅샷으로 다시 돌려 보고한 결과와 다르면 출력하고, verified 갱신 SQL 을 만든다. (cards.csv·skills.json 은 그 시점 버전이어야 함)
import { readFileSync } from 'fs';
import { setSkillData } from '../js/skills.js';
import { parseCSV, setCardPool } from '../js/rules.js';
import { runSeries, snapCard } from '../js/pvp-core.js';
const rd = p => readFileSync(new URL(p, import.meta.url), 'utf8');
const pool = parseCSV(rd('../data/cards.csv')); setCardPool(pool); setSkillData(JSON.parse(rd('../data/skills.json')), JSON.parse(rd('../data/combos.json')));
const byId = id => pool.find(c => String(c.id) === String(id));
const rows = JSON.parse(readFileSync(process.argv[2] || 'attempts.json', 'utf8'));
const good = [], bad = [];
for (const a of rows) {
  const J = v => typeof v === 'string' ? JSON.parse(v) : v, cards = d => d.map(o => snapCard(o, byId)).filter(Boolean);
  const r = runSeries(a.mode, J(a.my_snap).map(cards), J(a.opp_snap).map(cards), a.seed, false, a.actions ? J(a.actions) : null);   // actions 있으면 수동 판
  (r.wins === +a.wins && r.losses === +a.losses ? good : bad).push(a.id);
  if (r.wins !== +a.wins || r.losses !== +a.losses) console.log(`✕ #${a.id} 보고 ${a.wins}-${a.losses} / 재계산 ${r.wins}-${r.losses}`);
}
console.log(`일치 ${good.length} · 불일치 ${bad.length}`);
if (good.length) console.log(`update pvp_attempts set verified = true where id in (${good.join(',')});`);
if (bad.length) console.log(`update pvp_attempts set verified = false where id in (${bad.join(',')});`);
