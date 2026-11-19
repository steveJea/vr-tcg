// 전투 기록 정리: 설치는 함수만, 자동 삭제 없음. 미리보기는 읽기 전용. 실행/스케줄은 승인 문구.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const root = new URL('../', import.meta.url);
const read = p => readFile(new URL(p, root), 'utf8');

const staging = await read('supabase/battle_log_purge_staging.sql');
const production = await read('supabase/battle_log_purge_production.sql');
const checkS = await read('supabase/battle_log_purge_check_staging.sql');
const checkP = await read('supabase/battle_log_purge_check_production.sql');
const dryS = await read('supabase/battle_log_purge_dryrun_staging.sql');
const dryP = await read('supabase/battle_log_purge_dryrun_production.sql');
const runS = await read('supabase/battle_log_purge_run_staging.sql');
const runP = await read('supabase/battle_log_purge_run_production.sql');
const schS = await read('supabase/battle_log_purge_schedule_staging.sql');
const schP = await read('supabase/battle_log_purge_schedule_production.sql');

assert.match(staging, /7703759698107299042/);
assert.match(production, /7692130048193495360/);
assert.doesNotMatch(staging, /7692130048193495360/);
assert.doesNotMatch(production, /7703759698107299042/);
for (const p of [production, checkP, dryP, runP, schP]) assert.match(p, /아직 실행하지 마세요/);

for (const sql of [staging, production]) {
  assert.match(sql, /battle_log_purge_dryrun\(\)/);
  assert.match(sql, /battle_log_purge\(p_confirm text\)/);
  assert.match(sql, /p_confirm is distinct from 'PURGE'/);
  assert.match(sql, /auto_schedule', false/);
  assert.doesNotMatch(sql, /cron\.schedule/);
  assert.doesNotMatch(sql, /battle_log_purge\('PURGE'\)/);
  for (const keep of [
    'battle_clear_receipts_v2', 'battle_events_v2', 'battle_acquisitions_v2',
    'arcade_records_v5', 'pvp_ratings_v3', 'pvp_events_v3', 'matches'
  ]) assert.match(sql, new RegExp(keep));
}

assert.doesNotMatch(dryS, /battle_log_purge\('PURGE'\)/);
assert.doesNotMatch(dryS, /\bdelete\b/i);
assert.doesNotMatch(dryS, /\bupdate\b/i);
assert.match(dryS, /deleted_nothing/);
assert.equal([...checkS.matchAll(/;\s*$/gm)].length, 1);
assert.equal([...dryS.matchAll(/;\s*$/gm)].length, 1);
assert.equal([...checkP.matchAll(/;\s*$/gm)].length, 1);
assert.equal([...dryP.matchAll(/;\s*$/gm)].length, 1);

assert.match(runS, /형님이 이 정리를 직접 승인한 뒤에만/);
assert.match(runS, /battle_log_purge\('PURGE'\)/);
assert.match(runP, /형님이 이 정리를 직접 승인한 뒤에만/);

assert.match(schS, /예, 자동 삭제를 허용합니다/);
assert.match(schS, /아직 승인하지 않음/);
assert.match(schS, /이 파일을 설치 SQL 과 함께 실행하지 마세요/);
assert.match(schP, /아직 실행하지 마세요/);
// default approval must not already be the yes-phrase assigned
assert.match(schS, /approval text := '아직 승인하지 않음'/);

const secS = await read('supabase/security_rls_check_staging.sql');
const secP = await read('supabase/security_rls_check_production.sql');
assert.match(secS, /7703759698107299042/);
assert.match(secP, /7692130048193495360/);
assert.match(secP, /아직 실행하지 마세요/);
assert.match(secS, /^--[\s\S]*\nselect\n/m);
assert.doesNotMatch(secS, /\b(insert into|update\s+public|delete\s+from|drop\s+|create\s+|alter\s+|grant\s+|revoke\s+|begin;|commit;)/i);
assert.equal([...secS.matchAll(/;\s*$/gm)].length, 1);
assert.equal([...secP.matchAll(/;\s*$/gm)].length, 1);
assert.match(secS, /no_rls/);
assert.match(secS, /anon_writes/);
assert.match(secS, /definer_anon/);

const idxS = await read('supabase/index_hot_filters_staging.sql');
const idxP = await read('supabase/index_hot_filters_production.sql');
const idxCS = await read('supabase/index_hot_filters_check_staging.sql');
const idxCP = await read('supabase/index_hot_filters_check_production.sql');
const pgS = await read('supabase/pg_stat_statements_top_staging.sql');
const pgP = await read('supabase/pg_stat_statements_top_production.sql');
assert.match(idxS, /create index if not exists battle_sessions_v2_expire/);
assert.match(idxS, /create index if not exists arcade_sessions_v5_expire/);
assert.match(idxS, /create index if not exists pvp_sessions_v3_expire/);
assert.match(idxS, /guildbattle_sessions_v4_pending/);
assert.match(idxS, /pvp_attempts_user_recent/);
assert.match(idxS, /CREATE INDEX CONCURRENTLY/);
assert.doesNotMatch(idxS.replace(/--[^\n]*/g, ''), /create index concurrently/i);
assert.match(idxP, /아직 실행하지 마세요/);
assert.equal([...idxCS.matchAll(/;\s*$/gm)].length, 1);
assert.equal([...pgS.matchAll(/;\s*$/gm)].length, 1);
assert.equal([...pgP.matchAll(/;\s*$/gm)].length, 1);
assert.match(pgS, /pg_stat_statements/);
assert.match(pgP, /아직 실행하지 마세요/);

console.log('test_battle_log_purge ok');
