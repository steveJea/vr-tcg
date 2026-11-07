// Offline plausibility, economics and ACL tests. These do not prove deterministic combat replay.
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
const age=async id => { await q(`update battle_sessions_v2 set issued_at=clock_timestamp()-interval '10 seconds' where id=$1`,[id]); await q(`update story_progress set data=jsonb_set(data,'{battle,at}',to_jsonb((extract(epoch from clock_timestamp())-10)::bigint)) where data->'battle'->>'session'=$1`,[id]); };
const report={win:true,reason:'wipe',turns:4,my_turns:2,mana:100,skills:1,cards:[]};
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
  let base=await buildSql();
  const section=base.indexOf('-- ===== SOURCE: security_phase2_clears.sql =====');
  if(section>=0) base=base.slice(0,section)+base.slice(base.indexOf('-- 공개 게임 설정만 명시적으로 조회 허용',section));
  await db.exec(base.replace(`confirmed_ref text := '${INSTALL_ACK}'`,"confirmed_ref text := 'abcdefghijklmnopqrst'"));
  await q(`insert into auth.users(id,email) values($1,'one@example.invalid'),($2,'two@example.invalid')`,[me,other]);
  await q(`insert into player_wallet(user_id,gold,gem_free) values($1,100,500),($2,200,700)`,[me,other]);
  await q(`insert into story_gacha(user_id,last_draw,tickets) values($1,_gem_day()-1,30),($2,_gem_day()-1,30)`,[me,other]);
  const owned=await val(`select _story_new_card('10111') v`);
  const ownedOther=await val(`select _story_new_card('10224') v`);
  await q(`insert into story_progress(user_id,data) values($1,$2),($3,$4)`,[
    me,JSON.stringify({owned:[owned],starter:'10111',cleared:{1:[1,2,3,4,5]},stars:{1:{1:3}}}),
    other,JSON.stringify({owned:[ownedOther],starter:'10224'})]);
  await q(`insert into player_state(user_id,level,stamina) values($1,50,90),($2,50,90)`,[me,other]);

  await q(`insert into tower_progress(user_id,tower,best_floor,paid_floor) values($1,'normal',3,1)`,[me]);
  const before=await economicSnapshot();
  await db.exec(sql); await db.exec(sql);
  assert.deepEqual(await economicSnapshot(),before);
  await reject(`select arcade_tut_claim(1)`,[],/verified tutorial/);
  await reject(`select battle_session_start_v2('tutorial','2','[]',$1)`,[req(1)],/previous/);
  assert.deepEqual((await rpc('select tower_status() v')).towers.normal.unpaid_floors,[2,3]);
  let first;
  for(let n=1;n<=3;n++) {
    const s=await start('tutorial',String(n),[],req(n)); if(n===1) first=s;
    await age(s.session);
    if(n===1) await reject(`select battle_session_finish_v2($1,$2)`,[s.session,JSON.stringify({...report,turns:0,my_turns:0,skills:0})],/zero-turn/);
    const got=await finish(s.session,report); assert.equal(got.ok,true); assert.equal(got.gave,n===1?10:n===2?100:300);
    assert.deepEqual(await finish(s.session,report),got);
  }
  assert.equal(await val(`select tickets v from story_gacha where user_id=$1`,[me]),40);
  assert.equal(await val(`select gem_free v from player_wallet where user_id=$1`,[me]),900);
  await reject(`select battle_session_finish_v2($1,$2::jsonb)`,[first.session,JSON.stringify({...report,turns:5})],/submission conflict/);
  await reject(`select battle_session_status_v2($1)`,[first.session],/not found/,other);
  const s=await start('story','1:1',[owned.uid,'guest:10112'],req(10)); await age(s.session);
  const r=await finish(s.session,{...report,mana:s.snapshot.mana,cards:[{uid:owned.uid,kills:1,blocks:0}]});
  assert.equal(r.ok,true); assert.equal(r.stars,3); assert(r.exp.length===1);
  const t=await start('tower','normal:1',[owned.uid],req(11)); await age(t.session);
  const tr=await finish(t.session,report); assert.equal(tr.first,false,'old paid floor never paid again'); assert.deepEqual(tr.currency,{});
  const higher=await start('tower','normal:3',[owned.uid],req(13)); await age(higher.session); assert((await finish(higher.session,report)).first);
  const t2=await start('tower','normal:2',[owned.uid],req(12)); await age(t2.session);
  const tr2=await finish(t2.session,report); assert.equal(tr2.first,true,'held lower floor released despite paid_floor already higher'); assert(tr2.currency.gold>0);
  const again=await start('tower','normal:2',[owned.uid],req(14)); await age(again.session); assert.equal((await finish(again.session,report)).first,false);
  const d=await rpc('select daily_status() v'); assert.equal(d.reward_held,false); assert.equal(d.missions.find(m=>m.key==='story').prog,1);
  for(const text of [`select story_complete_phase(1,1,'[]')`,`select story_complete_phase(1,1)`,`select story_set_stars(1,1,3)`,`select tower_complete('normal',1,'{}')`,`select quest_complete(1,'{}')`,`select tower_sweep_complete('normal',1,'{}')`,`select _phase2_old_story_complete_phase(1,1,'[]')`]) await reject(text);
  for(const text of [`select pvp_claim_tier('open','1v1')`,`select raid_claim()`,`select war_claim()`,`select daily_claim('arcade')`,`select daily_claim('all')`]) await reject(text,[],/verification pending/);
  // No legacy JSON stars/counters silently become trustworthy reward evidence.
  assert.equal(await val(`select _ach_prog($1,'story_ch') v`,[me]),0);
  assert.equal((await rpc(`select story_star_status() v`)).find(x=>x.chapter===1).total,3);
  await reject(`select story_sweep(1,2,1)`,[],/verified clear/);
  await reject(`select battle_session_start_v2('story','1:2',$1,$2)`,[JSON.stringify([ownedOther.uid]),req(20)],/phase locked/,other);
  await reject(`select battle_session_start_v2('story','2:1',$1,$2)`,[JSON.stringify([ownedOther.uid]),req(21)],/phase locked/,other);
  await reject(`select battle_session_start_v2('tower','normal:5',$1,$2)`,[JSON.stringify([owned.uid]),req(22)],/floor locked/);
  for(const [mode,target,party] of [['tutorial','01',[]],['tutorial','4',[]],['story','01:1',[]],['tower','bogus:1',[owned.uid]],['tower','normal:0',[owned.uid]]])
    await reject(`select battle_session_start_v2($1,$2,$3,$4)`,[mode,target,JSON.stringify(party),req(23)],/invalid/);
  await reject(`select battle_session_start_v2('tower','normal:1',$1,$2)`,[JSON.stringify([ownedOther.uid]),req(24)],/invalid party|owned/);
  await reject(`select battle_session_start_v2('tower','normal:1',$1,$2)`,[JSON.stringify([owned.uid,owned.uid]),req(25)],/duplicate/);
  await reject(`select battle_session_start_v2('story','1:1',$1,$2)`,[JSON.stringify([owned.uid,'guest:99999']),req(26)],/guest/);

  // Start idempotency, stable retry seed, early time rejection and closed/foreign tokens.
  const issued=await start('tower','normal:4',[owned.uid],req(30));
  const same=await start('tower','normal:4',[owned.uid],req(30)); assert.equal(same.session,issued.session);
  await reject(`select battle_session_start_v2('tower','normal:3',$1,$2)`,[JSON.stringify([owned.uid]),req(30)],/request conflict/);
  await reject(`select battle_session_finish_v2($1,$2)`,[issued.session,JSON.stringify(report)],/too fast/);
  await reject(`select battle_session_finish_v2($1,$2)`,[issued.session,JSON.stringify(report)],/not found/,other);
  await age(issued.session);
  for(const bad of [{...report,turns:-1},{...report,turns:41},{...report,my_turns:4},{...report,turns:40,my_turns:0},{...report,skills:9000},{...report,turns:0,my_turns:0,skills:1},{...report,reason:'giveup'},{...report,win:'true'},{...report,gold:99999},{...report,turns:null},{...report,reason:'survive'}])
    await reject(`select battle_session_finish_v2($1,$2)`,[issued.session,JSON.stringify(bad)],/invalid|implausible/);
  const counterBefore=await val(`select count(*)::int v from battle_events_v2 where user_id=$1`,[me]);
  await abort(issued.session); await abort(issued.session);
  await reject(`select battle_session_finish_v2($1,$2)`,[issued.session,JSON.stringify(report)],/closed/);
  const retried=await start('tower','normal:4',[owned.uid],req(31)); assert.equal(retried.seed,issued.seed); await age(retried.session);
  const settlement=await finish(retried.session,{...report,turns:0,my_turns:0,skills:0}); assert(settlement.first);
  assert.equal(await val(`select count(*)::int v from battle_events_v2 where user_id=$1`,[me]),counterBefore+1,'one attempt per session, finish does not add another');
  assert.deepEqual((await rpc(`select battle_session_status_v2($1) v`,[retried.session])).settlement,settlement);

  // Story invalid telemetry must never alter economic/progression rows.
  const story=await start('story','1:2',[owned.uid],req(40)); await age(story.session);
  const safe=await economicSnapshot();
  for(const bad of [{...report,mana:story.snapshot.mana+1},{...report,mana:-1},{...report,mana:null},{...report,cards:[{uid:ownedOther.uid,kills:0,blocks:0}]},{...report,cards:[{uid:owned.uid,kills:999,blocks:0}]},{...report,cards:[{uid:owned.uid,kills:0,blocks:-1}]},{...report,cards:[{uid:owned.uid,kills:0,blocks:0},{uid:owned.uid,kills:0,blocks:0}]}]) {
    await reject(`select battle_session_finish_v2($1,$2)`,[story.session,JSON.stringify(bad)],/mana|participant|card stats/);
    assert.deepEqual(await economicSnapshot(),safe);
  }
  await finish(story.session,{...report,mana:story.snapshot.mana});
  for(let phase=3;phase<=5;phase++) {
    const v=await start('story',`1:${phase}`,[owned.uid],req(40+phase)); await age(v.session);
    if(phase===5) {
      const snap=await economicSnapshot();
      await db.exec(`create function phase2_test_fault() returns trigger language plpgsql as $$ begin if new.reward_kind='chapter_v2' then raise exception 'injected settlement fault'; end if; return new; end $$; create trigger phase2_test_fault before insert on reward_claims for each row execute function phase2_test_fault();`);
      await reject(`select battle_session_finish_v2($1,$2)`,[v.session,JSON.stringify({...report,mana:v.snapshot.mana})],/injected settlement fault/);
      assert.deepEqual(await economicSnapshot(),snap,'payout failure rolls back stars, XP, cards, chapter claims, currencies');
      assert.equal(await val(`select status v from battle_sessions_v2 where id=$1`,[v.session]),'issued');
      await db.exec('drop trigger phase2_test_fault on reward_claims; drop function phase2_test_fault()');
    }
    const done=await finish(v.session,{...report,mana:v.snapshot.mana});
    if(phase===5) assert.equal(done.chapter_reward.added,10);
  }
  assert.equal(await val(`select _ach_prog($1,'story_ch') v`,[me]),1);
  assert.equal(await val(`select count(*)::int v from reward_claims where user_id=$1 and reward_kind='chapter_v2'`,[me]),1);
  const starStatus=await rpc('select story_star_status() v'); assert.equal(starStatus.find(c=>c.chapter===1).total,15);
  const star=await rpc(`select story_star_claim(1,'all') v`); assert(star.ok);
  await reject(`select story_star_claim(1,'all')`,[],/already claimed/);
  const mission=await rpc(`select daily_claim('story') v`); assert(mission.got);
  await reject(`select daily_claim('story')`,[],/already claimed/);
  const sweep=await rpc(`select story_sweep(1,1,1) v`); assert(sweep.ok);

  // A route must be explicitly chosen, and its real forced guests remain playable.
  await reject(`select battle_session_start_v2('story','2:1',$1,$2)`,[JSON.stringify([owned.uid]),req(55)],/variant required/);
  const route=await val(`select variant v from battle_story_defs_v2 where chapter=2 and phase=1 and variant<>'' order by variant limit 1`);
  await rpc('select story_choose_route(2,$1) v',[route]);
  const forced=await val(`select definition->'party'->'forced' v from battle_story_defs_v2 where chapter=2 and phase=1 and variant=$1`,[route]);
  const routed=await start('story','2:1',forced.map(id=>id===owned.id?owned.uid:'guest:'+id),req(56));
  assert.equal(routed.snapshot.stage.variantKind,'route'); await abort(routed.session);
  // Genuine fresh chapter-zero guest battle returns data and a server-selected card.
  const fresh=await start('story','0:1',['guest:10325'],req(60),other); assert(fresh.data.owned.length);
  await age(fresh.session);
  const beforeFresh=await economicSnapshot();
  await db.exec(`create function phase2_test_event_fault() returns trigger language plpgsql as $$ begin raise exception 'injected event fault'; end $$; create trigger phase2_test_event_fault before insert on battle_events_v2 for each row execute function phase2_test_event_fault();`);
  await reject(`select battle_session_finish_v2($1,$2)`,[fresh.session,JSON.stringify({...report,mana:null})],/injected event fault/,other);
  assert.deepEqual(await economicSnapshot(),beforeFresh,'failure after actual first-card grant rolls back card, XP and acquisition receipt');
  assert.equal(await val(`select count(*)::int v from battle_acquisitions_v2 where user_id=$1`,[other]),0);
  await db.exec('drop trigger phase2_test_event_fault on battle_events_v2; drop function phase2_test_event_fault()');
  const freshResult=await finish(fresh.session,{...report,mana:null},other);
  assert(freshResult.first); assert(freshResult.reward_id);
  assert.equal(await val(`select count(*)::int v from battle_acquisitions_v2 where user_id=$1`,[other]),1);
  assert.equal(await val(`select _gallery_have($1) v`,[other]),1);

  // Automatic replacement, expiry and abort refund one reserved story cost only.
  const stamina=await val(`select stamina v from player_state where user_id=$1`,[me]);
  const reserved=await start('story','1:1',[owned.uid,'guest:10112'],req(61));
  assert((await val(`select stamina v from player_state where user_id=$1`,[me]))<stamina);
  const replacement=await start('tutorial','1',[],req(62)); assert.equal(await val(`select status v from battle_sessions_v2 where id=$1`,[reserved.session]),'aborted');
  assert.equal(await val(`select stamina v from player_state where user_id=$1`,[me]),stamina);
  await abort(replacement.session);
  const expired=await start('story','1:1',[owned.uid,'guest:10112'],req(63));
  await age(expired.session);
  await q(`update battle_sessions_v2 set expires_at=clock_timestamp()-interval '1 second' where id=$1`,[expired.session]);
  const expiry=await finish(expired.session,report); assert.equal(expiry.status,'expired'); assert.equal(expiry.ok,false);
  assert.equal(await val(`select stamina v from player_state where user_id=$1`,[me]),stamina);

  // Per-floor auto-sweep is monotonic and cannot include bosses or ignore daily caps.
  for(let floor=5;floor<=9;floor++) {
    const sf=await start('tower_sweep',`normal:${floor}`,[owned.uid],req(70+floor)); assert.equal(sf.min_seconds,1); await age(sf.session);
    assert((await finish(sf.session,report)).first);
  }
  await reject(`select battle_session_start_v2('tower_sweep','normal:10',$1,$2)`,[JSON.stringify([owned.uid]),req(90)],/boss/);
  await q(`update tower_progress set day_floors=30 where user_id=$1 and tower='normal'`,[me]);
  await reject(`select battle_session_start_v2('tower','normal:10',$1,$2)`,[JSON.stringify([owned.uid]),req(91)],/daily/);
  await q(`update tower_progress set day_floors=0 where user_id=$1 and tower='normal'`,[me]);

  // Successful defeats settle skill telemetry and refund story reservations.
  const loss=await start('story','1:1',[owned.uid,'guest:10112'],req(92)); await age(loss.session);
  const lossState=await finish(loss.session,{...report,win:false}); assert.equal(lossState.cleared,false); assert(lossState.player.refunded);
  for(const key of ['win','tower','skill']) assert((await rpc(`select daily_claim($1) v`,[key])).got);
  const week=await rpc('select weekly_status() v'); const towerMission=week.missions.find(m=>m.key==='tower'); assert(!towerMission.held);
  assert(towerMission.prog>=towerMission.goal);assert((await rpc(`select weekly_claim('tower') v`)).got);
  await reject(`select weekly_claim('tower')`,[],/already claimed/);
  const dowDef=await val(`select pg_get_functiondef('public._tower_dow()'::regprocedure) v`);
  await db.exec(`create or replace function public._tower_dow() returns int language sql stable as $$ select 6 $$`);
  const opened=await val(`select t v from unnest(array['wind','ice','fire','light','dark']) t where _tower_dow()=any(_tower_days(t)) and upper(t)<>(select definition->>'class' from battle_card_meta_v2 where id='10111') limit 1`);
  await reject(`select battle_session_start_v2('tower',$1,$2,$3)`,[opened+':1',JSON.stringify([owned.uid]),req(93)],/tower element/);
  await db.exec(`create or replace function public._tower_dow() returns int language sql stable as $$ select 1 $$`);
  const closed=await val(`select t v from unnest(array['wind','ice','fire','light','dark']) t where not _tower_dow()=any(_tower_days(t)) limit 1`);
  await reject(`select battle_session_start_v2('tower',$1,$2,$3)`,[closed+':1',JSON.stringify([owned.uid]),req(94)],/closed today/);
  await db.exec(dowDef);
  await reject(`select battle_session_start_v2('tutorial','1','[]',$1)`,[req(95)],/login required/,'');
  for(const text of [`select story_start_phase(1,1)`,`select tower_start('normal',1)`,`select quest_start(1)`,`select tower_sweep_start('normal')`,`select quest_sweep_start()`,`update tower_progress set best_floor=999`]) await reject(text);
  // ACL hardening covers rogue overloads and column grants on migration reruns.
  await db.exec(`create function story_complete_phase(bigint,bigint) returns jsonb language sql security definer as $$ select '{}'::jsonb $$; grant execute on function story_complete_phase(bigint,bigint) to authenticated; grant select(seed),update(status) on battle_sessions_v2 to authenticated;`);
  const applied=await economicSnapshot(); await db.exec(sql); assert.deepEqual(await economicSnapshot(),applied);
  await reject(`select story_complete_phase(1::bigint,1::bigint)`);
  await reject(`select seed from battle_sessions_v2`);await reject(`update battle_sessions_v2 set status='aborted'`);
  for(const table of ['battle_sessions_v2','battle_clear_receipts_v2','battle_events_v2','battle_acquisitions_v2','battle_policy_v2','battle_legacy_access_v2','battle_session_seeds_v2']) await reject(`select * from ${table}`);
  const exposed=await q(`select proname from pg_proc where pronamespace='public'::regnamespace and left(proname,1)='_' and prosecdef and pg_get_function_result(oid)<>'trigger' and (has_function_privilege('authenticated',oid,'execute') or has_function_privilege('anon',oid,'execute'))`); assert.deepEqual(exposed,[]);
  await q(`update battle_policy_v2 set enabled=false where mode='tutorial'`);
  await reject(`select battle_session_start_v2('tutorial','1','[]',$1)`,[req(100)],/verification pending/);
  await db.exec(sql); assert.equal(await val(`select enabled v from battle_policy_v2 where mode='tutorial'`),false,'rerun preserves emergency stop');
  await q(`update battle_policy_v2 set enabled=true where mode='tutorial'`);
  // Only synthetic admin fixture rows here: clients cannot manufacture issuance history.
  await q(`insert into battle_sessions_v2(request_id,user_id,mode,target,party,seed,snapshot,status,finished_at) select gen_random_uuid(),$1,'tutorial','1','[]',123,'{}','aborted',clock_timestamp() from generate_series(1,500)`,[other]);
  await reject(`select battle_session_start_v2('tutorial','1','[]',$1)`,[req(101)],/issuance limit/,other);
  console.log('Phase 2 tutorial rewards, story XP/stars, tower once-only payouts, missions, legacy closure: OK');
} catch(e) { console.error(e.message, e.where || String(e.stack).split('\n').slice(1,4).join('\n')); process.exitCode=1; } finally { await db.close(); }
