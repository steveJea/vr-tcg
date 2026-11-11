// Offline PostgreSQL/WASM only. No keys, network, or live user data.
import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
import {buildSql,INSTALL_ACK} from './build_staging_sql.mjs';
const migration=await readFile(new URL('../supabase/security_phase1_rewards.sql',import.meta.url),'utf8');
const full=await buildSql();
// Exercise an upgrade over the previous schema, not just a clean installation.
const section=full.indexOf('-- ===== SOURCE: security_phase1_rewards.sql =====');
assert(section>0, 'migration section missing');
const suffix=full.indexOf('-- 공개 게임 설정만 명시적으로 조회 허용',section);
assert(suffix>section);
const old=full.slice(0,section)+full.slice(suffix);
const db=new PGlite();
const me='11111111-1111-4111-8111-111111111111', other='22222222-2222-4222-8222-222222222222';
const q=async(s,p=[]) => (await db.query(s,p)).rows;
const val=async(s,p=[]) => (await q(s,p))[0]?.v;
async function role(who,fn,uid=me) {
  await db.exec(`reset role; select set_config('request.jwt.claim.sub','${uid}',false); set role ${who}`);
  try {return await fn();} finally {await db.exec('reset role');}
}
async function reject(s,pattern=/permission denied|reward verification pending/,uid=me) {
  await role('authenticated',()=>assert.rejects(q(s),pattern),uid);
}
async function snapshot() {return q(`select user_id,gold,gem_free,gem_paid,
  (select tickets from story_gacha g where g.user_id=w.user_id) tickets,
  (select count(*)::int from gem_ledger l where l.user_id=w.user_id) ledger
  from player_wallet w order by user_id`);}
try {
  await db.exec(`create role anon; create role authenticated; create schema auth;
    create table auth.users(id uuid primary key,email text,raw_user_meta_data jsonb default '{}',raw_app_meta_data jsonb default '{}',created_at timestamptz default now(),last_sign_in_at timestamptz,email_confirmed_at timestamptz);
    create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
    create function auth.jwt() returns jsonb language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb $$;
    grant usage on schema auth,public to anon,authenticated;
    alter default privileges in schema public grant all on tables to anon,authenticated;
    alter default privileges in schema public grant all on sequences to anon,authenticated;
    alter default privileges in schema public grant execute on functions to anon,authenticated;`);
  await db.exec(old.replace(`confirmed_ref text := '${INSTALL_ACK}'`,"confirmed_ref text := 'abcdefghijklmnopqrst'"));
  await q(`insert into auth.users(id,email,raw_user_meta_data) values ($1,'one@example.invalid','{"name":"보안하나"}'),($2,'two@example.invalid','{"name":"보안둘"}')`,[me,other]);
  await db.exec(`select set_config('request.jwt.claim.sub','${me}',false);
    insert into player_wallet(user_id,gold,gem_free) values ('${me}',100,500),('${other}',200,700);
    insert into story_gacha(user_id,last_draw,tickets) values ('${me}',_gem_day()-1,30),('${other}',_gem_day()-1,30);
    insert into daily_progress(user_id,day,prog) values ('${me}',_gem_day(),'{"arcade":999,"win":999,"story":999,"tower":999,"skill":999}');
    insert into weekly_progress(user_id,week,prog) values ('${me}',_weekly_week(),'{"arcade":999,"win":999,"story":999,"tower":999,"skill":999}');
    insert into ach_counters(user_id,kind,n) values ('${me}','skill_uses',999999),('${me}','arcade_wins',999999);
    insert into gallery(user_id,card_id,count,mvp_count) select '${me}',id,1,999 from story_card_pool;
    insert into achievement_claims(user_id,key) values ('${me}','arcade_wins:300'),('${me}','skill_uses:3000');
    create function public.daily_track(text,bigint) returns jsonb language sql security definer as $$ select '{}'::jsonb $$;
    grant execute on function public.daily_track(text,bigint) to public,anon,authenticated;
    grant update(tickets) on story_gacha to authenticated;
    grant insert(prog) on daily_progress to authenticated;`);
  const before=await snapshot();
  await db.exec(migration);
  await db.exec(migration);
  assert.deepEqual(await snapshot(),before,'migration cannot change balances or ledger');
  assert.equal(await val(`select count(*)::int v from verified_game_events`),0,'no legacy certification');
  const csv=await readFile(new URL('../data/cards.csv',import.meta.url),'utf8');
  const lines=csv.trim().split(/\r?\n/), idColumn=lines.shift().split(',').indexOf('id');
  const cardIds=lines.map(l=>l.split(',')[idColumn]).sort();
  assert.deepEqual((await q('select card_id from reward_card_catalog order by card_id')).map(r=>r.card_id),cardIds,'release gallery catalog must match cards.csv');
  assert.equal(await val(`select count(*)::int v from ach_counters`),2,'legacy counters kept');
  assert.equal(await val(`select count(*)::int v from achievement_claims`),2,'legacy claims kept');
  assert.equal(await val(`select count(*)::int v from gallery where user_id=$1`,[me]),await val(`select count(*)::int v from story_card_pool`),'legacy gallery kept');
  assert.equal(await val(`select _ach_score($1) v`,[me]),0,'tainted legacy claims cannot unlock score rewards');
  assert.equal(await val(`select _gallery_have($1) v`,[me]),0);
  for(const s of [
    `select daily_track('skill',2147483647::integer)`, `select daily_track('win',-1::integer)`,
    `select daily_track('skill',null::integer)`, `select daily_track('win',1::bigint)`,
    `select weekly_track('win',100::integer)`,`select ach_track('skill',2147483647)`,
    `select gallery_register(array['fake','10001'],'10001')`, `select gallery_register(null,null)`,
    `select daily_claim('all')`,`select weekly_claim('all')`,
    `select arcade_tut_claim(1)`,`select arcade_tut_claim(2)`,`select arcade_tut_claim(3)`,
    `select story_star_claim(1,'all')`,`select pvp_claim_tier('open','1v1')`,
    `select pvp_claim_reward('open','1v1','2000-01-01')`,`select raid_claim()`,`select war_claim()`,
    `select _daily_grant('${other}','{"gem":999}','attend','forged')`,
    `select _gem_add('${me}',999,0,'admin','forged','{}')`,
    `select _story_ticket_sync('${me}')`,`select _gallery_sync_owned('${me}','{"owned":[{"id":"10001"}]}')`,
    `insert into verified_game_events(user_id,source_kind,source_id,event_kind,card_id) values ('${me}','gacha','forged','card_acquired','10001')`,
    `insert into reward_claims(user_id,reward_kind,source_or_period,reward) values ('${me}','ach','forged','{}')`,
    `insert into gallery(user_id,card_id) values ('${me}','fake')`,
    `update story_gacha set tickets=9999 where user_id='${me}'`,
    `update daily_progress set prog='{"skill":999}' where user_id='${me}'`,
    `insert into story_gacha_log(user_id,card_id,grade) values ('${me}','10001','NORMAL')`,
    `update reward_security_policy set enabled=true`,
  ]) await reject(s);
  await reject(`select achievements_claim('skill_uses:50')`,/not done/);
  await reject(`select achievements_claim('gallery_n:30')`,/not done/);
  await reject(`select achievements_claim('score:100')`,/not done/);
  await reject(`select achievements_claim('score:000100')`,/invalid key/);
  assert.deepEqual(await snapshot(),before,'arbitrary RPCs and raw writes pay nothing');
  const daily=await role('authenticated',()=>val(`select daily_status() v`));
  const weekly=await role('authenticated',()=>val(`select weekly_status() v`));
  for(const status of [daily,weekly]) {
    assert.equal(status.reward_held,true);
    assert.equal(status.all.done,0);
    assert(status.missions.every(m=>m.prog===0));
  }
  console.log('Upgrade twice, no reset; fake counters/gallery/overloads/raw writes/score aliases blocked: OK');
  // Genuine server draw is the sole event producer today. No browser field/stat inputs.
  const draw=await role('authenticated',()=>val('select story_daily_draw() v'));
  assert(draw && !draw.already);
  assert.equal(await val(`select count(*)::int v from verified_game_events where user_id=$1`,[me]),1);
  assert.equal(await val(`select _gallery_have($1) v`,[me]),1);
  await role('authenticated',()=>val('select story_daily_draw() v')); // same KST day retry
  assert.equal(await val(`select count(*)::int v from verified_game_events where user_id=$1`,[me]),1);
  assert.equal(await val(`select _gallery_have($1) v`,[other]),0,'no cross-account event credit');
  const cid=await val(`select card_id v from verified_game_events where user_id=$1`,[me]);
  // Selling/changing owned JSON cannot erase acquired evidence or create another.
  await q(`update story_progress set data=jsonb_set(data,'{owned}','[]') where user_id=$1`,[me]);
  assert.equal(await val(`select _gallery_have($1) v`,[me]),1);
  assert.equal(await val(`select mvp_count v from gallery where user_id=$1 and card_id=$2`,[me,cid]),999,'draw does not alter legacy MVP');
  await db.exec(`insert into verified_game_events(user_id,source_kind,source_id,event_kind,card_id)
    select user_id,source_kind,source_id,event_kind,card_id from verified_game_events on conflict do nothing`);
  assert.equal(await val(`select count(*)::int v from verified_game_events`),1);
  const td=await role('authenticated',()=>val(`select story_ticket_draw(10) v`));
  assert.equal(td.ok,true);
  assert.equal(await val(`select count(*)::int v from verified_game_events where user_id=$1`,[me]),11);
  assert.equal(await val(`select _ach_prog($1,'gacha_n') v`,[me]),11);
  await reject(`select gallery_reward_claim(25)`,/not done/);
  console.log('Real daily/ticket draws -> canonical event + gallery; duplicate/date/owner/sold-card rules: OK');
  // Two independent consumers of the same acquisition evidence: collect + draw
  // achievements. Neither browser kind/n nor another account's rows can advance them.
  // 25% milestone needs a quarter of the catalog (grows with cards.csv): keep 110 as the floor.
  const have=Math.max(110,Math.ceil(await val(`select count(*)::int v from reward_card_catalog`)*0.25)+1);
  await q(`insert into story_gacha_log(user_id,card_id,grade)
    select $1,c.card_id,p.grade from reward_card_catalog c join story_card_pool p on p.id=c.card_id
    order by c.card_id limit ${have}`,[other]);
  assert.equal(await val(`select _gallery_have($1) v`,[other]),have);
  const milestone=await role('authenticated',()=>val('select gallery_reward_claim(25) v'),other);
  assert.equal(milestone.got.tickets,10);
  const afterMilestone=await snapshot();
  await reject(`select gallery_reward_claim(25)`,/already claimed/,other);
  assert.deepEqual(await snapshot(),afterMilestone);
  const oneAch=await role('authenticated',()=>val("select achievements_claim('gallery_n:30') v"),other);
  assert.equal(oneAch.got.tickets,1);
  await reject(`select achievements_claim('gallery_n:30')`,/already claimed/,other);
  const achAll=await role('authenticated',()=>val('select achievements_claim_all() v'),other);
  assert(achAll.claimed_n>0);
  const afterAll=await snapshot();
  await reject(`select achievements_claim_all()`,/not done/,other);
  assert.deepEqual(await snapshot(),afterAll);
  assert.equal(await val(`select _ach_prog($1,'skill_uses') v`,[other]),0);
  assert.equal(await val(`select _cosmo_ach_score($1) v`,[me]),40,'legacy cosmetic titles retained');
  console.log('Normal gallery and multi-achievement claims; duplicates and legacy cosmetics: OK');
  // Auth + KST attendance still pays once, with a whole-bundle receipt.
  const a=await role('authenticated',()=>val('select attend_claim() v'));
  assert.equal(a.got_day,1);
  assert.equal(a.got.gold,3000);
  const afterAttend=await snapshot();
  await reject(`select attend_claim()`,/already claimed/);
  assert.deepEqual(await snapshot(),afterAttend);
  assert.equal(await val(`select count(*)::int v from reward_claims where user_id=$1 and reward_kind='attend'`,[me]),1);
  await role('anon',()=>assert.rejects(q('select attend_claim()'),/permission denied/));
  await role('authenticated',()=>assert.rejects(q('select attend_claim()'),/login required/),'');
  // Private receipt tests using the DB owner as a server-only fixture.
  const rw='{"gold":5000,"gem":30,"tickets":2}';
  await q(`select _daily_grant($1,$2,'attend','receipt-test')`,[me,rw]);
  const afterGrant=await snapshot();
  await Promise.all(Array.from({length:8},()=>q(`select _daily_grant($1,$2,'attend','receipt-test')`,[me,rw])));
  assert.deepEqual(await snapshot(),afterGrant,'all currencies exactly once on retries');
  await assert.rejects(q(`select _daily_grant($1,'{"tickets":99}','attend','receipt-test')`,[me]),/reward conflict/);
  for(const rw of ['{"tickets":-1}','{"tickets":1.5}','{"evil":1}','{"gold":2147483648}','[]'])
    await assert.rejects(q(`select _daily_grant($1,$2,'attend','bad-input')`,[me,rw]),/invalid reward/);
  const oldRef='legacy-gem-only';
  await q(`select _gem_add($1,1,0,'attend',$2,'{}')`,[me,oldRef]);
  const beforeOld=await snapshot();
  await assert.rejects(q(`select _daily_grant($1,$2,'attend',$3)`,[me,rw,oldRef]),/already claimed/);
  assert.deepEqual(await snapshot(),beforeOld,'old gem receipt does not repay gold/tickets');
  const tickets=await val(`select tickets v from story_gacha where user_id=$1`,[me]);
  await q(`update story_gacha set tickets=2147483647 where user_id=$1`,[me]);
  const overflowBefore=await snapshot();
  await assert.rejects(q(`select _daily_grant($1,$2,'attend','rollback-test')`,[me,rw]),/out of range/);
  assert.deepEqual(await snapshot(),overflowBefore,'ticket failure rolls back gem/gold/ledger');
  assert.equal(await val(`select count(*)::int v from reward_claims where source_or_period='rollback-test'`),0);
  await q(`update story_gacha set tickets=$2 where user_id=$1`,[me,tickets]);
  console.log('KST attendance, bundle idempotency, legacy refs, input validation, rollback: OK');
  // Combat reports remain playable, but cannot produce a grant or consume claim IDs.
  await q(`insert into player_state(user_id,level) values ($1,10) on conflict(user_id) do update set level=10`,[me]);
  const towerStart=await role('authenticated',()=>val("select tower_start('normal',1) v"));
  assert.equal(towerStart.floor,1);
  await q(`update tower_progress set battle=jsonb_set(battle,'{at}',to_jsonb(extract(epoch from now()-interval '1 minute')::bigint)) where user_id=$1 and tower='normal'`,[me]);
  const towerBefore=await snapshot();
  const tower=await role('authenticated',()=>val(`select quest_complete(1,'{"turns":3}') v`));
  assert.equal(tower.reward_held,true);
  assert.equal(tower.paid,false);
  assert.equal(await val(`select paid_floor v from tower_progress where user_id=$1 and tower='normal'`,[me]),0);
  assert.deepEqual(await snapshot(),towerBefore);
  // An old reporter with a 10-win streak would normally trigger a direct grant.
  await db.exec(`insert into pvp_ratings(user_id,league,mode,season,wins,losses) values ('${me}','open','1v1',_pvp_season(),9,1);
    insert into pvp_attempts(user_id,league,mode,season,day,seed,my_snap,opp_snap,my_rating,opp_rating,dw,dl,reported_at,win)
    select '${me}','open','1v1',_pvp_season(),_pvp_day(),1,'[]','[]',1000,1000,10,10,now()-interval '1 minute',true from generate_series(1,9);`);
  const aid=await val(`insert into pvp_attempts(user_id,league,mode,season,day,seed,my_snap,opp_snap,my_rating,opp_rating,dw,dl)
    values ($1,'open','1v1',_pvp_season(),_pvp_day(),1,'[]','[]',1000,1000,10,10) returning id v`,[me]);
  const pvpBefore=await snapshot();
  const report=await role('authenticated',()=>val(`select pvp_report(${aid},1,0) v`));
  assert.equal(report.reward_held,true);
  assert.equal(report.streak_reward,null);
  assert.deepEqual(await snapshot(),pvpBefore);
  assert.equal(await val(`select count(*)::int v from pvp_tier_claims`),0);
  await reject(`select pvp_report(${aid},1,0)`,/already reported/);
  await reject(`select pvp_report(${aid},1,0)`,/not found/,other);
  // Source-period boundaries are always server KST; controlled clock is DB-owner test code only.
  const originalClock=await val(`select pg_get_functiondef('public._gem_day()'::regprocedure) v`);
  await db.exec(`create or replace function _gem_day() returns date language sql stable as $$ select date '2026-12-07' $$;
    update daily_attend set last_day='2026-12-06',step=6,total=6 where user_id='${me}';
    insert into gem_login(user_id,last_day,streak) values ('${me}','2026-12-06',6) on conflict(user_id) do update set last_day=excluded.last_day,streak=6;`);
  const seventh=await role('authenticated',()=>val('select attend_claim() v'));
  assert.equal(seventh.got_day,7);
  assert.deepEqual(seventh.got,{gem:100,tickets:2});
  const login=await role('authenticated',()=>val('select gem_status() v'));
  assert.equal(login.granted.length,1);
  assert.equal(login.granted[0].reason,'login_7');
  const boundaryBefore=await snapshot();
  await role('authenticated',()=>val('select gem_status() v'));
  await reject('select attend_claim()',/already claimed/);
  assert.deepEqual(await snapshot(),boundaryBefore);
  assert.equal(await val('select _weekly_week()::text v'),'2026-12-07');
  await db.exec(`create or replace function _gem_day() returns date language sql stable as $$ select date '2026-12-08' $$;`);
  const nextDay=await role('authenticated',()=>val('select attend_claim() v'));
  assert.equal(nextDay.got_day,1);
  await db.exec(originalClock);
  console.log('Tower/PvP play without payment; KST day/week/7-day login boundaries: OK');
  // Staging feedback #5: a free accumulated claim and a 30-gem instant boost are distinct.
  // All data here is a disposable local fixture; never a live database.
  await q('update player_wallet set gem_free=0,gem_paid=0 where user_id=$1',[other]);
  const idleStatus=await role('authenticated',()=>val('select idle_box_status() v'),other);
  assert.equal(idleStatus.boost.cost,30);
  assert.equal(idleStatus.boost.hours,4);
  await q("update idle_box set last_claim=now()-interval '2 hours' where user_id=$1",[other]);
  const idleFree=await role('authenticated',()=>val('select idle_box_claim() v'),other);
  assert(idleFree.got.gold>0,'accumulated rewards must work with zero gems');
  assert.equal(await val('select gem_free+gem_paid v from player_wallet where user_id=$1',[other]),0);
  const idleBefore=await val(`select jsonb_build_object('wallet',to_jsonb(w),'idle',to_jsonb(i),'gear',to_jsonb(g)) v
    from player_wallet w join idle_box i using(user_id) left join player_gear_meta g using(user_id) where w.user_id=$1`,[other]);
  await reject('select idle_box_boost()',/not enough gem/,other);
  const idleAfter=await val(`select jsonb_build_object('wallet',to_jsonb(w),'idle',to_jsonb(i),'gear',to_jsonb(g)) v
    from player_wallet w join idle_box i using(user_id) left join player_gear_meta g using(user_id) where w.user_id=$1`,[other]);
  assert.deepEqual(idleAfter,idleBefore,'failed paid boost cannot change rewards or daily count');
  await q('update player_wallet set gem_free=100 where user_id=$1',[other]);
  const boost1=await role('authenticated',()=>val('select idle_box_boost() v'),other);
  assert.equal(boost1.gem.gem,70); assert.equal(boost1.boost.left,1); assert(boost1.got.gold>0);
  const boost2=await role('authenticated',()=>val('select idle_box_boost() v'),other);
  assert.equal(boost2.gem.gem,40); assert.equal(boost2.boost.left,0);
  await reject('select idle_box_boost()',/daily limit/,other);
  assert.equal(await val('select gem_free+gem_paid v from player_wallet where user_id=$1',[other]),40);
  console.log('Idle rewards: zero-gem free claim, 30-gem paid boost, rollback and daily limit: OK');
  const exposed=await q(`select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and left(p.proname,1)='_' and
    (has_function_privilege('anon',p.oid,'execute') or has_function_privilege('authenticated',p.oid,'execute'))`);
  assert.deepEqual(exposed,[]);
  const inventory=await q(`select p.oid::regprocedure::text signature,p.prosecdef security_definer,
    has_function_privilege('authenticated',p.oid,'execute') authenticated_execute,
    has_function_privilege('anon',p.oid,'execute') anon_execute, md5(pg_get_functiondef(p.oid)) definition_hash
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.prokind='f' and p.oid<>'public.daily_track(text,bigint)'::regprocedure
    order by p.proname,p.oid::regprocedure::text`);
  if(process.argv.includes('--inventory')) await writeFile(new URL('../docs/SECURITY_PHASE1_RPC_INVENTORY.json',import.meta.url),JSON.stringify(inventory,null,2)+'\n');
  console.log('All private helpers deny anon/authenticated; grant RPC inventory: OK');
} finally {await db.close();}
