// READ-ONLY audit. This tool never certifies legacy rows or emits settlement/UPDATE SQL.
// node tools/pvp_verify.mjs attempts.json
// Export current-version attempts with their session metadata:
// select a.id,a.mode,a.seed,a.my_snap,a.opp_snap,a.actions,a.wins,a.losses,s.control,s.engine_hash
// from pvp_attempts a join pvp_sessions_v3 s using(id) where s.verified;
import { readFileSync } from 'node:fs';
import { ENGINE_VERSION, verifyBattle } from '../supabase/functions/_shared/pvp-engine-v3.mjs';
const rows=JSON.parse(readFileSync(process.argv[2]||'attempts.json','utf8'));
const J=v=>typeof v==='string'?JSON.parse(v):v;
let good=0,bad=0,skipped=0;
for(const a of rows) {
 if(a.engine_hash!==ENGINE_VERSION || !['auto','actions'].includes(a.control)) {
  console.log(`SKIP #${a.id}: legacy/unsupported engine; NOT certified`); skipped++; continue;
 }
 try {
  const r=verifyBattle({mode:a.mode,seed:a.seed,me:J(a.my_snap),opp:J(a.opp_snap),control:a.control},a.control==='auto'?null:J(a.actions));
  if(r.wins!==+a.wins || r.losses!==+a.losses) throw Error(`reported ${a.wins}-${a.losses}, replay ${r.wins}-${r.losses}`);
  good++;
 } catch(e) { bad++; console.log(`FAIL #${a.id}: ${e.message}`); }
}
console.log(`Read-only replay: match ${good}, mismatch/illegal ${bad}, unsupported ${skipped}. No database writes; rewards settle only through pvp-verify-v3.`);
if(bad) process.exitCode=1;
