// Real full staging schema, synthetic admin fixture only. Never live Supabase.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
import {buildSql,INSTALL_ACK} from './build_staging_sql.mjs';
import {PVP_ENGINE_VERSION as P} from '../js/pvp-engine-version.js';
import {GUILDBATTLE_ENGINE_VERSION as G} from '../js/guildbattle-engine-version.js';
const db=new PGlite(),q=async(s,p=[]) => (await db.query(s,p)).rows,val=async(s,p=[]) => (await q(s,p))[0]?.v;
const u='16161616-1616-4616-8616-161616161616',oldP='ff3c2c77c26429a0fbf85f1d1ab73edb882af342a152727c1aed64c49160dd2a',oldG='a00f5c9824515cfce4fcbd6d579deb5e971335035b264454d427fdb93669819e';
try {
 await db.exec(`create role anon;create role authenticated;create role service_role;create schema auth;
 create table auth.users(id uuid primary key,email text,raw_user_meta_data jsonb default '{}',raw_app_meta_data jsonb default '{}',created_at timestamptz default now(),last_sign_in_at timestamptz,email_confirmed_at timestamptz);
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 create function auth.jwt() returns jsonb language sql stable as $$select '{}'::jsonb$$;
 grant usage on schema auth,public to anon,authenticated,service_role;`);
 await db.exec((await buildSql()).replace(`confirmed_ref text := '${INSTALL_ACK}'`,"confirmed_ref text := 'abcdefghijklmnopqrst'"));
 const raw=await readFile(new URL('../supabase/security_feedback16_skill_lock_staging.sql',import.meta.url),'utf8');
 await assert.rejects(db.exec(raw),/STOP: feedback16 only staging/);await db.exec('rollback');
 const id=await val('select system_identifier::text v from pg_control_system()'),sql=raw.replaceAll("'7703759698107299042'",`'${id}'`);
 const reject=async(pattern)=>{await assert.rejects(db.exec(sql),pattern);await db.exec('rollback');};
 const pins=()=>q('select engine_hash,enabled from pvp_policy_v3 union all select engine_hash,enabled from guildbattle_policy_v4');
 await q("insert into auth.users(id,email) values($1,'fixture16@example.invalid')",[u]);
 await q('insert into player_state(user_id,level,xp) values($1,25,17)',[u]);
 await q('insert into player_wallet(user_id,gold) values($1,12345)',[u]);
 const aid=await val(`insert into pvp_attempts(user_id,league,mode,season,day,opp_name,seed,my_snap,opp_snap,my_rating,opp_rating,dw,dl) values($1,'open','1v1',_pvp_season(),_pvp_day(),'fixture',1,'[]','[]',1000,1000,1,1) returning id v`,[u]);
 await q("insert into pvp_sessions_v3(id,user_id,request_id,control,engine_hash,expires_at) values($1,$2,gen_random_uuid(),'auto',$3,clock_timestamp()+interval '1 hour')",[aid,u,oldP]);
 await q("insert into guildbattle_sessions_v4(user_id,kind,attempt_id,request_id,control,engine_hash,payload,snapshot,expires_at) values($1,'raid',777777,gen_random_uuid(),'auto',$2,'{}','{}',clock_timestamp()+interval '20 minutes')",[u,oldG]);
 await q('update pvp_policy_v3 set engine_hash=$1,enabled=false',[oldP]);await q('update guildbattle_policy_v4 set engine_hash=$1,enabled=false',[oldG]);
 const tables=['player_state','player_wallet','pvp_attempts','pvp_sessions_v3','guildbattle_sessions_v4','pvp_decks','pvp_ratings_v3','reward_claims','war_ajits_v4','war_atk_state_v4','guild_raids_v4','guildbattle_test_clock_v4','guildbattle_test_refills_v4'];
 await q("update guildbattle_test_clock_v4 set at=clock_timestamp(),expires_at=clock_timestamp()+interval '2 hours',run=7,guild_ids='{111,222}'");
 await q("insert into guildbattle_test_refills_v4(user_id,guild_id,kind,day,match_id,run,clock_set_at,used_base) select $1,111,'raid',current_date,null,run,set_at,3 from guildbattle_test_clock_v4",[u]);
 const present=tables;for(const t of present)assert(await val('select to_regclass($1)::text v',['public.'+t]),t);
 const acl=await q("select oid,proacl::text,md5(prosrc) as body from pg_proc where pronamespace='public'::regnamespace order by oid");
 const snap=async()=>Object.fromEntries(await Promise.all(present.map(async t=>[t,await q(`select * from public.${t} order by to_jsonb(${t})::text`)])));
 let before=await snap(),policy=await pins();await reject(/active old PvP/);assert.deepEqual(await snap(),before);assert.deepEqual(await pins(),policy);
 await q("update pvp_sessions_v3 set expires_at=clock_timestamp()-interval '1 second'");before=await snap();
 await reject(/active old raid\/war/);assert.deepEqual(await snap(),before);assert.deepEqual(await pins(),policy);
 await q("update guildbattle_sessions_v4 set expires_at=clock_timestamp()-interval '1 second'");before=await snap();
 await q('update pvp_policy_v3 set engine_hash=$1',['0'.repeat(64)]);await reject(/unexpected PvP engine version/);assert.equal(await val('select engine_hash v from pvp_policy_v3'),'0'.repeat(64));await q('update pvp_policy_v3 set engine_hash=$1',[oldP]);
 await q('update guildbattle_policy_v4 set engine_hash=$1',['0'.repeat(64)]);await reject(/unexpected guildbattle engine version/);assert.equal(await val('select engine_hash v from pvp_policy_v3'),oldP);await q('update guildbattle_policy_v4 set engine_hash=$1',[oldG]);
 await db.exec(sql);await db.exec(sql);assert.deepEqual(await q("select oid,proacl::text,md5(prosrc) as body from pg_proc where pronamespace='public'::regnamespace order by oid"),acl);assert.deepEqual(await pins(),[{engine_hash:P,enabled:false},{engine_hash:G,enabled:false}]);assert.deepEqual(await snap(),before,'successful reruns change only the two policy hashes');
 // A previously upgraded half is valid, but both move atomically and preserve switches.
 await q('update guildbattle_policy_v4 set engine_hash=$1',[oldG]);await db.exec(sql);assert.equal(await val('select engine_hash v from guildbattle_policy_v4'),G);
 await db.exec('set role authenticated');await assert.rejects(q("update pvp_policy_v3 set engine_hash='forged'"),/permission denied/);await db.exec('reset role');
 console.log('Feedback16 SQL PASS: real full schema, staging guard, both active-session blockers, unknown-version atomic rejection, idempotent two-engine rotation, kill switches/state/HP/clock/receipts unchanged, ACL');
}finally{await db.close();}
