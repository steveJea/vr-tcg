// Offline (PGlite): debug 57 — camp_status() applies pending camp EXP exactly like camp_claim(), idempotent, staging-guarded, reversible.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
import {buildSql,INSTALL_ACK} from './build_staging_sql.mjs';
const rd=p=>readFile(new URL('../'+p,import.meta.url),'utf8');
const db=new PGlite(), u='22222222-2222-4222-8222-222222222222';
const q=async(s,p=[])=>(await db.query(s,p)).rows, val=async(s,p=[])=>(await q(s,p))[0]?.v;
async function as(fn){await q("select set_config('request.jwt.claim.sub',$1,false)",[u]);await db.exec('set role authenticated');try{return await fn();}finally{await db.exec('reset role');}}
const rpc=s=>as(()=>val(s));
const card=async()=>(await val("select data->'owned'->0 v from story_progress where user_id=$1",[u]));
const age=h=>q(`update camp_slots set last_at=now()-interval '${h} hours' where user_id=$1 and slot=1`,[u]);
try{
 await db.exec(`create role anon;create role authenticated;create role service_role;create schema auth;
 create table auth.users(id uuid primary key,email text,raw_user_meta_data jsonb default '{}',raw_app_meta_data jsonb default '{}',created_at timestamptz default now(),last_sign_in_at timestamptz,email_confirmed_at timestamptz);
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
 grant usage on schema auth,public to anon,authenticated,service_role;
 alter default privileges in schema public grant all on tables to anon,authenticated;
 alter default privileges in schema public grant all on sequences to anon,authenticated;
 alter default privileges in schema public grant execute on functions to anon,authenticated,service_role;`);
 await db.exec((await buildSql()).replace(`confirmed_ref text := '${INSTALL_ACK}'`,"confirmed_ref text := 'abcdefghijklmnopqrst'"));
 const id=await val('select system_identifier::text v from pg_control_system()');
 for(const f of ['supabase/level_unlocks_staging.sql','supabase/level_unlocks_facilities_staging.sql'])await db.exec((await rd(f)).replaceAll("'7703759698107299042'",`'${id}'`));
 const raw=f=>rd('supabase/'+f), pin=s=>s.replaceAll("'7703759698107299042'",`'${id}'`);
 const B1=await raw('camp_auto_exp_staging.sql'), B2=await raw('camp_auto_exp_check_staging.sql'), B3=await raw('camp_auto_exp_rollback_staging.sql');
 await assert.rejects(db.exec(B1),/STOP: 스테이징 DB 가 아님/);await db.exec('rollback').catch(()=>{});
 assert.equal((await q(B2))[0].item,'STOP');
 await q("insert into auth.users(id,email,created_at) values($1,'t@example.invalid',now()-interval '8 days')",[u]);
 await q('insert into player_state(user_id,level,xp) values($1,30,0)',[u]);
 const trainee=await val("select _story_new_card('10111') v");
 await q(`insert into story_progress(user_id,data) values($1,jsonb_build_object('owned',jsonb_build_array($2::jsonb)))`,[u,JSON.stringify(trainee)]);
 await rpc('select camp_status() v');await rpc(`select camp_put(1,'${trainee.uid}') v`);
 // Baseline: what the existing camp_claim gives for 5h.
 await age(5);const pend5=(await rpc('select camp_status() v')).slots[0].pending;assert(pend5>0);
 const before=await card();await rpc('select camp_claim() v');const viaClaim=await card();
 // Restore the same card + 5h, install B1, then camp_status alone must give the identical result.
 await q("update story_progress set data=jsonb_set(data,'{owned,0}',$2::jsonb) where user_id=$1",[u,JSON.stringify(before)]);await age(5);
 // Real staging has camp.sql's body pasted with CRLF line endings (md5 b82026c8…): B1 must accept it, and a CRLF paste of B1 itself too.
 const orig=(await rd('supabase/camp.sql')).match(/create or replace function public\.camp_status\(\)[^]*?as \$\$[^]*?\$\$;/)[0];
 await db.exec(orig.replace(/\n/g,'\r\n'));
 assert.equal(await val("select md5(prosrc) v from pg_proc where oid='public.camp_status()'::regprocedure"),'b82026c8e244f95c7920fd74537e38a8');
 assert.match((await q(pin(B2))).find(r=>r.item==='camp_status').note,/원본/);
 const p=pin(B1);await db.exec(p.replace(/\n/g,'\r\n'));await db.exec(p);
 assert.match((await q(pin(B2))).find(r=>r.item==='camp_status').note,/installed=true/);
 const r1=await rpc('select camp_status() v');
 assert.equal(r1.auto,true);assert.equal(r1.got[0].exp,pend5);assert.deepEqual(await card(),viaClaim,'same EXP/level as camp_claim');
 assert.equal(r1.slots[0].pending,0);
 const r2=await rpc('select camp_status() v');assert.equal(r2.auto,undefined);assert.deepEqual(await card(),viaClaim,'re-call adds nothing');
 // 24h limit unchanged: 30h idle == 24h idle.
 const snap=await card();await age(30);const p30=(await rpc('select camp_status() v')).got?.[0]?.exp;
 await q("update story_progress set data=jsonb_set(data,'{owned,0}',$2::jsonb) where user_id=$1",[u,JSON.stringify(snap)]);await age(24);
 const p24=(await rpc('select camp_status() v')).got?.[0]?.exp;assert.equal(p30,p24,'24h cap kept');
 // Anonymous still refused; rollback restores the original; rollback twice is safe; reinstall works.
 await q("select set_config('request.jwt.claim.sub','',false)");await assert.rejects(q('select camp_status()'),/login required/);
 const r3=pin(B3);await db.exec(r3);await db.exec(r3);
 assert.match((await q(pin(B2))).find(r=>r.item==='camp_status').note,/원본/);
 await age(5);const r4=await rpc('select camp_status() v');assert.equal(r4.got,undefined);assert(r4.slots[0].pending>0,'original status does not settle');
 await db.exec(p);
 console.log(`Camp auto EXP SQL: identical to camp_claim (+${pend5} EXP/5h), idempotent re-call, 24h cap kept (${p24}), guard/rerun/rollback: OK`);
}catch(e){console.error('CAMP AUTO SQL FAILURE:',e.message,e.where||'');process.exitCode=1;}
finally{await db.close();}
