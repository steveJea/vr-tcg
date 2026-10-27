// 구역 전쟁 결과 재검증: node tools/war_verify.mjs attacks.json
// attacks.json = SQL Editor 에서 내려받은 행 배열:
//   select id, seed, atk_snap, def_snap, atk_buff, def_buff, win, reported from war_attacks where finished_at is not null and not voided and reported is not null and match_id in (select id from war_matches where not settled);
// 같은 seed·스냅샷으로 다시 돌려 승패·남은 HP 가 다르면 출력하고 admin_war_void SQL 을 만든다. (cards.csv·npc_cards.csv·skills.json 은 그 시점 버전이어야 함)
import { readFileSync } from 'fs';
import { setSkillData } from '../js/skills.js';
import { parseCSV, setCardPool } from '../js/rules.js';
import { runWar, warDeck } from '../js/war-core.js';
const rd = p => readFileSync(new URL(p, import.meta.url), 'utf8');
const pool = parseCSV(rd('../data/cards.csv')), npc = parseCSV(rd('../data/npc_cards.csv')); setCardPool(pool); setSkillData(JSON.parse(rd('../data/skills.json')), JSON.parse(rd('../data/combos.json')));
const byId = id => pool.find(c => String(c.id) === String(id)) || npc.find(c => String(c.id) === String(id));
const J = v => typeof v === 'string' ? JSON.parse(v) : v;
const bad = []; let good = 0;
for (const a of JSON.parse(readFileSync(process.argv[2] || 'attacks.json', 'utf8'))) {
  const r = runWar(warDeck(J(a.atk_snap), byId, J(a.atk_buff)), warDeck(J(a.def_snap), byId, J(a.def_buff)), a.seed), rep = J(a.reported);
  const same = r.win === !!rep.win && JSON.stringify(r.aHp) === JSON.stringify(rep.atk || {}) && (r.win || JSON.stringify(r.bHp) === JSON.stringify(rep.def || {}));
  if (same) good++; else { bad.push(a.id); console.log(`✕ #${a.id} 보고 ${rep.win ? '승' : '패'} / 재계산 ${r.win ? '승' : '패'}`); }
}
console.log(`일치 ${good} · 불일치 ${bad.length}`);
for (const id of bad) console.log(`select admin_war_void(${id}, '재계산 불일치');`);
