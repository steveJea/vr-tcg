// Offline protocol/ACL tests only. These deliberately DO NOT assert combat verification.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { PGlite } from '@electric-sql/pglite';
import { buildSql, INSTALL_ACK } from './build_staging_sql.mjs';
const sql = await readFile(new URL('../supabase/security_phase2_clears.sql', import.meta.url), 'utf8');
const db = new PGlite();
const me='11111111-1111-4111-8111-111111111111', other='22222222-2222-4222-8222-222222222222';
const req=n => `aaaaaaaa-aaaa-4aaa-8aaa-${String(n).padStart(12,'0')}`;
const q=async(s,p=[]) => (await db.query(s,p)).rows;
const val=async(s,p=[]) => (await q(s,p))[0]?.v;
async function as(uid, fn, role='authenticated') {
  await q(`select set_config('request.jwt.claim.sub',$1,false)`,[uid]);
  await db.exec(`set role ${role}`);
  try { return await fn(); } finally { await db.exec('reset role'); }
}
const rpc=(s,p=[],uid=me) => as(uid,()=>val(s,p));
const reject=async(s,p=[],pat=/permission denied/,uid=me) => as(uid,()=>assert.rejects(q(s,p),pat));
const start=(m,t,p,r,uid=me) => rpc(`select battle_session_start_v2($1,$2,$3,$4) v`,[m,t,JSON.stringify(p),r],uid);
const finish=(id,a,uid=me) => rpc(`select battle_session_finish_v2($1::uuid,$2::jsonb) v`,[id,JSON.stringify(a)],uid);
const abort=id => rpc(`select battle_session_abort_v2($1) v`,[id]);
const age=id => q(`update battle_sessions_v2 set issued_at=clock_timestamp()-interval '10 seconds' where id=$1`,[id]);
const actions=[{k:'end',turn:1}];
async function economicSnapshot() {
  return q(`select user_id,gold,gem_free,gem_paid,
    (select tickets from story_gacha g where g.user_id=w.user_id) tickets,
    (select count(*)::int from gem_ledger l where l.user_id=w.user_id) ledger,
    (select count(*)::int from reward_claims c where c.user_id=w.user_id) claims,
    (select count(*)::int from verified_game_events e where e.user_id=w.user_id) events,
    (select data from story_progress sp where sp.user_id=w.user_id) story
    from player_wallet w order by user_id`);
}
try {
  await db.exec(`create role anon; create role authenticated; create schema auth;
    create table auth.users(id uuid primary key,email text,raw_user_meta_data jsonb default '{}',raw_app_meta_data jsonb default '{}',created_at timestamptz default now(),last_sign_in_at timestamptz,email_confirmed_at timestamptz);
    create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
    create function auth.jwt() returns jsonb language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb $$;
    grant usage on schema auth,public to anon,authenticated;
    alter default privileges in schema public grant all on tables to anon,authenticated;
    alter default privileges in schema public grant all on sequences to anon,authenticated;
    alter default privileges in schema public grant execute on functions to anon,authenticated;`);
  const base=await buildSql();
  await db.exec(base.replace(`confirmed_ref text := '${INSTALL_ACK}'`,"confirmed_ref text := 'abcdefghijklmnopqrst'"));
  await q(`insert into auth.users(id,email) values($1,'one@example.invalid'),($2,'two@example.invalid')`,[me,other]);
  await q(`insert into player_wallet(user_id,gold,gem_free) values($1,100,500),($2,200,700)`,[me,other]);
  await q(`insert into story_gacha(user_id,last_draw,tickets) values($1,_gem_day()-1,30),($2,_gem_day()-1,30)`,[me,other]);
  const owned=await val(`select _story_new_card('10111') v`);
  const ownedOther=await val(`select _story_new_card('10224') v`);
  await q(`insert into story_progress(user_id,data) values($1,$2),($3,$4)`,[
    me,JSON.stringify({owned:[owned],starter:'10111',cleared:{1:[1,2,3,4,5]},stars:{1:{1:3}}}),
    other,JSON.stringify({owned:[ownedOther],starter:'10224'})]);
  await q(`insert into player_state(user_id,level) values($1,50),($2,50)`,[me,other]);
  const before=await economicSnapshot();
  await db.exec(sql);
  await db.exec(`grant update(seed) on battle_session_seeds_v2 to authenticated;
    create function battle_session_finish_v2(uuid,json) returns jsonb language sql security definer as $$select '{}'::jsonb$$;
    grant execute on function battle_session_finish_v2(uuid,json) to authenticated;`);
  await db.exec(sql);
  assert.deepEqual(await economicSnapshot(),before,'idempotent install cannot pay/reset/backfill');
  assert.equal(await val(`select count(*)::int v from battle_clear_receipts_v2`),0);
  for(const t of ['battle_sessions_v2','battle_session_seeds_v2','battle_clear_receipts_v2','battle_tutorial_defs_v2']) {
    await reject(`select * from ${t}`);
    await reject(`update ${t} set ${t==='battle_sessions_v2'?"status='submitted'":t==='battle_session_seeds_v2'?'seed=5':t==='battle_clear_receipts_v2'?"result='{}'":"definition='{}'"}`);
  }
  await reject(`select _battle_session_gate_v2($1,'tutorial','1')`,[me]);
  await reject(`select battle_session_finish_v2(null,'[]'::json)`);
  await as(me,()=>assert.rejects(q(`select battle_session_start_v2('tutorial','1','[]',$1)`,[req(1)]),/permission denied/),'anon');
  await reject(`select battle_session_start_v2('tutorial','1','[]',$1)`,[req(1)],/login required/,'');
  console.log('Upgrade twice, restrictive defaults, column grants, overloads, helper/table/anon ACL: OK');
  for(const [m,t] of [['tutorial','01'],['tutorial','4'],['story','01:1'],['story','1:01'],['story','99:99'],['tower','normal:0'],['tower','normal:351'],['bad','1']]) {
    await reject(`select battle_session_start_v2($1,$2,'[]',$3)`,[m,t,req(1)],/invalid/);
  }
  await reject(`select battle_session_start_v2('tutorial','2','[]',$1)`,[req(1)],/previous tutorial/);
  await reject(`select battle_session_start_v2('story','1:2',$1,$2)`,[JSON.stringify([owned.uid]),req(1)],/phase locked/);
  await reject(`select battle_session_start_v2('tower','normal:2',$1,$2)`,[JSON.stringify([owned.uid]),req(1)],/floor locked/);
  await reject(`select battle_session_start_v2('story','0:1',$1,$2)`,[JSON.stringify([ownedOther.uid]),req(1)],/card not owned/);
  await reject(`select battle_session_start_v2('tutorial','1','[1]',$1)`,[req(1)],/invalid party/);
  await reject(`select battle_session_start_v2('tutorial','1','["fake"]',$1)`,[req(1)],/party is fixed/);
  const st=await start('tutorial','1',[],req(1));
  assert.equal(st.shadow,true); assert.equal(st.reward_held,true); assert.equal(st.status,'issued');
  assert(st.seed>0); assert.equal(st.verification,'replay_not_installed');
  assert.deepEqual(await start('tutorial','1',[],req(1)),st,'retry must reuse same token, seed and snapshot');
  await reject(`select battle_session_start_v2('tutorial','2','[]',$1)`,[req(1)],/request conflict/);
  await reject(`select battle_session_start_v2('tutorial','1','[]',$1)`,[req(2)],/already active/);
  await reject(`select battle_session_status_v2($1)`,[st.session],/not found/,other);
  await reject(`select battle_session_finish_v2($1::uuid,$2::jsonb)`,[st.session,JSON.stringify(actions)],/not found/,other);
  await reject(`select battle_session_abort_v2($1)`,[st.session],/not found/,other);
  await q(`update battle_sessions_v2 set issued_at=clock_timestamp() where id=$1`,[st.session]);
  await reject(`select battle_session_finish_v2($1::uuid,$2::jsonb)`,[st.session,JSON.stringify(actions)],/too fast/);
  await abort(st.session);
  const st2=await start('tutorial','1',[],req(2));
  assert.notEqual(st2.session,st.session); assert.equal(st2.seed,st.seed,'abandon cannot reroll seed');
  await age(st2.session);
  for(const a of [[],{},[{k:'end',turn:0}],[{k:'end',turn:41}],[{k:'end',turn:1.5}],[{k:'win',turn:1}],[{k:'end',turn:2},{k:'end',turn:1}],Array(2001).fill(actions[0])]) {
    await reject(`select battle_session_finish_v2($1::uuid,$2::jsonb)`,[st2.session,JSON.stringify(a)],/invalid/);
  }
  const submitted=await finish(st2.session,actions);
  assert.equal(submitted.status,'submitted'); assert.equal(submitted.reward_held,true);
  assert.deepEqual(await finish(st2.session,actions),submitted);
  await reject(`select battle_session_finish_v2($1::uuid,$2::jsonb)`,[st2.session,JSON.stringify([{k:'skill',turn:1}])],/submission conflict/);
  await reject(`select battle_session_abort_v2($1)`,[st2.session],/cannot be discarded/);
  assert.equal(await val(`select count(*)::int v from battle_clear_receipts_v2`),0,'a shaped transcript is NOT proof');
  console.log('Canonical/order/ownership/expiry/one-active/idempotence/seed-retention/transport bounds: OK');
  const os=await start('story','0:1',[ownedOther.uid],req(3),other);
  assert.equal(os.snapshot.cards[0].uid,ownedOther.uid);
  assert.equal(os.snapshot.cards[0].level,1);
  await q(`update story_progress set data=jsonb_set(data,'{owned,0,level}','99') where user_id=$1`,[other]);
  assert.equal((await rpc(`select battle_session_status_v2($1) v`,[os.session],other)).snapshot.cards[0].level,1);
  // Restore admin-only fixture change, which was not a client/API operation.
  await q(`update story_progress set data=jsonb_set(data,'{owned,0,level}','1') where user_id=$1`,[other]);
  await q(`update battle_sessions_v2 set issued_at=clock_timestamp()-interval '3 hours',expires_at=clock_timestamp()-interval '1 second' where id=$1`,[os.session]);
  const ex=await finish(os.session,actions,other); assert.equal(ex.status,'expired');
  await reject(`select battle_session_finish_v2($1::uuid,$2::jsonb)`,[os.session,JSON.stringify(actions)],/closed/,other);
  const ts=await start('tower','normal:1',[ownedOther.uid],req(4),other);
  assert.equal(ts.snapshot.stage.floor,1);
  for(const s of [`select arcade_tut_claim(1)`,`select story_star_claim(1,'all')`,`select daily_claim('all')`,
    `select pvp_claim_tier('open','1v1')`,`select raid_claim()`,`select war_claim()`]) await reject(s,[],/reward verification pending/);
  assert.deepEqual(await economicSnapshot(),before,'tokens/transcripts/old legacy clears must release NO held reward');
  await db.exec(sql);
  assert.equal(await val(`select count(*)::int v from battle_sessions_v2`),4,'rerun preserves session evidence');
  console.log('Server snapshot immutability, expired-state persistence, no legacy certification, all reward holds unchanged: OK');
  console.log('PHASE 2 PREPARATION ONLY: replay/settlement/client integration NOT implemented or tested.');
} finally { await db.close(); }
