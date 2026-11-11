// supabase/fix_unlock_policy_staging.sql: staging-guarded, restores the exact 2026-11-08 unlock functions. Offline (PGlite).
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {execFileSync} from 'node:child_process';
import {PGlite} from '@electric-sql/pglite';
const rd=p=>readFile(new URL('../'+p,import.meta.url),'utf8');
const fix=await rd('supabase/fix_unlock_policy_staging.sql');
const db=new PGlite();
// 11-08 reference = level_unlocks_staging.sql at the production release commit.
const ref=execFileSync('git',['show','12c5e005ce4c1e184b6e4ffe013aa2a21e6329f5:supabase/level_unlocks_staging.sql'],{cwd:new URL('..',import.meta.url),encoding:'utf8'});
const fnOf=(sql,name)=>sql.match(new RegExp('create or replace function public\\.'+name+'\\([\\s\\S]*?\\$\\$;'))[0];
await db.exec(fnOf(ref,'_player_unlock_level')+fnOf(ref,'_tower_min_level'));
const src=async()=>(await db.query(`select string_agg(proname||':'||md5(prosrc),',' order by proname) v from pg_proc where proname in('_player_unlock_level','_tower_min_level')`)).rows[0].v;
const want=await src();
// Regress exactly like the old story_ch16_17.sql did.
const old=execFileSync('git',['show','8355ae8102554a5f7804bfef3828aceeb3d9401e:supabase/story_ch16_17.sql'],{cwd:new URL('..',import.meta.url),encoding:'utf8'});
await db.exec(fnOf(old,'_player_unlock_level'));
assert.equal((await db.query(`select public._player_unlock_level('chapter_16') v`)).rows[0].v,26);
// Guard: a non-staging DB gets nothing.
await assert.rejects(db.exec(fix),/STOP: staging only/);
assert.equal((await db.query(`select public._player_unlock_level('chapter_16') v`)).rows[0].v,26);
const id=(await db.query(`select system_identifier::text v from pg_control_system()`)).rows[0].v;
const local=fix.replace("<> '7703759698107299042' then","<> '"+id+"' then");
assert.notEqual(local,fix);
await db.exec(local);await db.exec(local);
assert.equal(await src(),want,'byte-identical 11-08 function bodies');
const r=(await db.query(`select _player_unlock_level('chapter_16') a,_player_unlock_level('chapter_2') b,_player_unlock_level('skill') s,_player_unlock_level('equip') e,_tower_min_level('light') l`)).rows[0];
assert.deepEqual(r,{a:1,b:1,s:13,e:3,l:40});
assert.equal((fix.match(/^do \$/gm)||[]).length,1,'one DO block');
console.log('Unlock policy restore: staging guard, exact 11-08 bodies, idempotent OK');
await db.close();
