// No network/keys. PGlite SQL + the REAL trusted handler/engine behind a simulated Auth/REST boundary.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { PGlite } from '@electric-sql/pglite';
import { buildSql, INSTALL_ACK } from './build_staging_sql.mjs';
import { ENGINE_VERSION, verifyBattle } from '../supabase/functions/_shared/guildbattle-engine-v4.mjs';
import { dashboardHandler } from './load_phase4_dashboard.mjs';
import { createHandler } from '../supabase/functions/guildbattle-verify-v4/handler.mjs';
import { setSkillData, skillsOf } from '../js/skills.js';
import { parseCSV, setCardPool } from '../js/rules.js';
import {snapCard} from '../js/pvp-core.js';
import {manualRaid} from '../js/raid-core.js';
import {warSession,warDeck} from '../js/war-core.js';
const rd=p=>readFile(new URL('../'+p,import.meta.url),'utf8');
const db=new PGlite(), me='11111111-1111-4111-8111-111111111111', other='22222222-2222-4222-8222-222222222222';
const q=async(s,p=[]) => (await db.query(s,p)).rows, val=async(s,p=[]) => (await q(s,p))[0]?.v;
async function as(u,fn,role='authenticated') {
 await q(`select set_config('request.jwt.claim.sub',$1,false)`,[u||'']); await db.exec(`set role ${role}`);
 try { return await fn(); } finally { await db.exec('reset role'); }
}
const rpc=(s,p=[],u=me)=>as(u,()=>val(s,p));
const reject=(s,p=[],pat=/permission denied/,u=me)=>as(u,()=>assert.rejects(q(s,p),pat));
const req=n=>`aaaaaaaa-aaaa-4aaa-8aaa-${String(n).padStart(12,'0')}`;
const env={SUPABASE_URL:'https://cuyqchmdcnsgzkwyclji.supabase.co',SUPABASE_PUBLISHABLE_KEYS:JSON.stringify({default:'sb_publishable_fixture'}),SUPABASE_SECRET_KEYS:JSON.stringify({default:'sb_secret_fixture'})};
let restCalls=0, authCalls=0;
const signatures={guildbattle_start_v4:['p_kind','p_payload','p_request','p_control','p_engine_hash'],guildbattle_engine_session_v4:['p_uid','p_id'],guildbattle_engine_settle_v4:['p_uid','p_id','p_engine_hash','p_submission','p_result']};
const fetcher=async(url,opts)=>{
 assert(url.startsWith(env.SUPABASE_URL));
 if(url.endsWith('/auth/v1/user')) {
  authCalls++; assert.equal(opts.headers.apikey,'sb_publishable_fixture');
  const id=opts.headers.authorization==='Bearer fixture-me'?me:opts.headers.authorization==='Bearer fixture-other'?other:null;
  return Response.json(id?{id}:{error:'invalid JWT'},{status:id?200:401});
 }
 restCalls++; const name=url.split('/').at(-1), args=JSON.parse(opts.body); assert(signatures[name]);
 const trusted=opts.headers.apikey==='sb_secret_fixture';
 if(trusted) assert.equal(opts.headers.authorization,undefined,'new secret keys must NOT be sent as Bearer JWT');
 else assert.equal(name,'guildbattle_start_v4');
 const uid=opts.headers.authorization==='Bearer fixture-other'?other:me;
 const ps=signatures[name].map(k=>typeof args[k]==='object'&&args[k]!==null?JSON.stringify(args[k]):args[k]);
 try { const data=await as(trusted?null:uid,()=>val(`select public.${name}(${ps.map((_,i)=>'$'+(i+1)).join(',')}) v`,ps),trusted?'service_role':'authenticated'); return Response.json(data); }
 catch(e) { if(process.env.DEBUG_PHASE4)console.error('RPC',name,e.message,e.where||''); return Response.json({message:e.message},{status:400}); }
};
const factory=process.argv.includes('--dashboard')?dashboardHandler:createHandler;
const handler=factory(env,fetcher);
const http=async(body,token='fixture-me',h=handler)=>{
 const r=await h(new Request('https://example.invalid/guildbattle-verify-v4',{method:'POST',headers:{'content-type':'application/json',authorization:'Bearer '+token},body:JSON.stringify(body)}));
 return {status:r.status,data:await r.json()};
};

try {
 await db.exec(`create role anon; create role authenticated; create role service_role; create schema auth;
 create table auth.users(id uuid primary key,email text,raw_user_meta_data jsonb default '{}',raw_app_meta_data jsonb default '{}',created_at timestamptz default now(),last_sign_in_at timestamptz,email_confirmed_at timestamptz);
 create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
 create function auth.jwt() returns jsonb language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb $$;
 grant usage on schema auth,public to anon,authenticated,service_role;
 alter default privileges in schema public grant all on tables to anon,authenticated;
 alter default privileges in schema public grant all on sequences to anon,authenticated;
 alter default privileges in schema public grant execute on functions to anon,authenticated,service_role;`);

 let base=await buildSql();const at=base.indexOf('-- ===== SOURCE: security_phase4_raid_guildwar.sql =====');assert(at>0);base=base.slice(0,at)+base.slice(base.indexOf('-- 공개 게임 설정만 명시적으로 조회 허용',at));
 await db.exec(base.replace(`confirmed_ref text := '${INSTALL_ACK}'`,"confirmed_ref text := 'abcdefghijklmnopqrst'"));
 const system=await val(`select system_identifier::text v from pg_control_system()`);
 const migration=await rd('supabase/security_phase4_raid_guildwar.sql');
 await assert.rejects(db.exec(migration),/STOP: phase4 only/);await db.exec('rollback');
 const sql=migration.replaceAll("'7703759698107299042'",`'${system}'`);await db.exec(sql);await db.exec(sql);
 await q(`insert into auth.users(id,email) values($1,'one@example.invalid'),($2,'two@example.invalid')`,[me,other]);
 await q(`insert into player_wallet(user_id,gold,gem_free) values($1,100,500),($2,200,700)`,[me,other]);
 await q(`insert into story_progress(user_id,data) values($1,'{"starter":"10111","owned":[]}'),($2,'{"starter":"10111","owned":[]}')`,[me,other]);
 await q(`insert into player_state(user_id,level) values($1,80),($2,80)`,[me,other]);
 let seed=(await rd('supabase/staging_seed_raid_guildwar.sql')).replaceAll("'7703759698107299042'",`'${system}'`).replace("user_a uuid := '00000000-0000-0000-0000-000000000000'",`user_a uuid := '${me}'`).replace("user_b uuid := '00000000-0000-0000-0000-000000000000'",`user_b uuid := '${other}'`);
 await db.exec(seed);await db.exec(seed);
 const status0=await rpc('select raid_status() v');assert.equal(status0.attempts_left,3);assert.equal(status0.can_sweep,false);assert.equal((await rpc('select war_status() v')).phase,'live');
 let serial=0;
 const ids=await val(`select jsonb_agg(c->>'uid') v from story_progress,jsonb_array_elements(data->'owned') c where user_id=$1`,[me]);
 async function start(kind='raid',payload={uids:ids},control='auto') {const r=await http({op:'start',kind,payload,request:req(++serial),control,version:ENGINE_VERSION});assert.equal(r.status,200,JSON.stringify(r));return r.data;}
 const finish=(s,actions=null,token='fixture-me')=>http({op:'finish',id:s.id,actions},token);
 const r=await start();assert.equal(r.kind,'raid');const expected=verifyBattle(r,null);assert(expected.damage>0);
 let out=await finish(r);assert.equal(out.status,200,JSON.stringify(out));assert.equal(out.data.result.damage,expected.damage);
 const before=await q('select * from guild_claims order by ref');assert.deepEqual((await finish(r)).data,out.data);assert.deepEqual(await q('select * from guild_claims order by ref'),before);
 assert.equal((await finish(r,null,'fixture-other')).status,409);
 const war=await start('war',{slot:1,deck:1});assert.equal(war.kind,'war');const we=verifyBattle(war,null);out=await finish(war);assert.equal(out.status,200,JSON.stringify(out));assert.equal(out.data.result.win,we.win);

 const eco=()=>q(`select user_id,gold,gem_free,(select count(*)::int from reward_claims r where r.user_id=w.user_id) claims from player_wallet w order by user_id`);
 // All legacy signatures, private helpers, direct column writes and forged overloads close.
 await reject(`select raid_finish(1,999999999)`);await reject(`select war_finish(1,true,'{}','{}')`);await reject(`select raid_log(1,'[]')`);await reject(`select war_start(1,1)`);
 await reject(`select guildbattle_engine_settle_v4($1,1,$2,'{"actions":null}','{"damage":999999}')`,[me,ENGINE_VERSION]);
 await reject(`update guild_raid_attempts_v4 set damage=999`);await reject(`update war_matches_v4 set score_a=999`);await reject(`update guildbattle_policy_v4 set enabled=true`);
 const acl=await val(`select count(*)::int v from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname~'^_(raid_|war_|guildbattle_|guild_reward_v4)' and (has_function_privilege('anon',p.oid,'execute') or has_function_privilege('authenticated',p.oid,'execute'))`);assert.equal(acl,0);
 const stable=await eco();await db.exec(sql);assert.deepEqual(await eco(),stable);
 // Exact start request deduplication and mismatched-payload rejection.
 let body={op:'start',kind:'raid',payload:{uids:ids},request:req(++serial),control:'actions',version:ENGINE_VERSION};
 let a1=await http(body);assert.equal(a1.status,200,JSON.stringify(a1));assert.deepEqual((await http(body)).data,a1.data);
 assert.equal((await http({...body,control:'auto'})).status,409);
 assert.equal((await http({op:'finish',id:a1.data.id,actions:[],damage:999})).status,400);
 assert.equal((await finish(a1.data,[])).status,422);
 assert.equal((await finish(a1.data,[{k:'atk',i:0,t:4}])).status,422);
 // Real browser actions produce the same result after skill/gear-aware replay.
 const pool=parseCSV(await rd('data/cards.csv')),npc=parseCSV(await rd('data/npc_cards.csv'));setCardPool(pool);setSkillData(JSON.parse(await rd('data/skills.json')),JSON.parse(await rd('data/combos.json')));const by=id=>[...pool,...npc].find(c=>String(c.id)===String(id));
 const ses=manualRaid(a1.data.deck.map(o=>snapCard(o,by,'raid')),a1.data.stage,a1.data.difficulty,a1.data.seed,by,[],{view:true});let x=ses.next();while(!x.done)x=ses.next(x.value.ask?{k:'auto'}:undefined);
 let mr=await finish(a1.data,ses.acts);assert.equal(mr.status,200,JSON.stringify(mr));assert.equal(mr.data.result.damage,x.value.damage);
 // Sweep only derives from THIS guild's verified same-day fight; exact request receipts.
 const swreq=req(++serial),sw=await rpc('select raid_sweep_v4($1) v',[swreq]);assert.equal(sw.result.damage,Math.floor(Math.max(expected.damage,x.value.damage)*.9));assert.deepEqual(await rpc('select raid_sweep_v4($1) v',[swreq]),sw);
 assert.equal((await http({op:'start',kind:'raid',payload:{uids:ids},request:req(++serial),control:'auto',version:ENGINE_VERSION})).status,409);
 // Seed reset advances period rather than deleting evidence or resetting balances.
 const oldEco=await eco(),oldEvents=await val('select count(*)::int v from guildbattle_events_v4');await db.exec(seed.replace("action text := 'start'","action text := 'reset'"));assert.deepEqual(await eco(),oldEco);assert.equal(await val('select count(*)::int v from guildbattle_events_v4'),oldEvents);
 // Membership change invalidates a reserved raid without outcome, reward or event.
 const change=await start();const gid=await val('select guild_id v from guild_members where user_id=$1',[me]);await q('delete from guild_members where user_id=$1',[me]);const pre=await eco();out=await finish(change);assert.equal(out.status,200,JSON.stringify(out));assert.equal(out.data.result.expired,true);assert.deepEqual(await eco(),pre);await q(`insert into guild_members(user_id,guild_id,role) values($1,$2,'boss')`,[me,gid]);
 // Expiry persists a consumed, zero-award receipt and can be retried identically.
 const expired=await start();await q(`update guildbattle_sessions_v4 set expires_at=clock_timestamp()-interval '1 second' where id=$1`,[expired.id]);out=await finish(expired);assert.equal(out.data.result.expired,true);assert.deepEqual((await finish(expired)).data,out.data);
 // War lease+CAS: changed defender state cannot be overwritten by an old replay.
 const stale=await start('war',{slot:1,deck:1});await q(`update war_ajits_v4 t set state='{"changed":1}' where exists(select 1 from war_attacks_v4 a join guildbattle_sessions_v4 s on s.attempt_id=a.id and s.kind='war' where s.id=$1 and t.match_id=a.match_id and t.side=1-a.side and t.slot=a.target_slot)`,[stale.id]);const safeEco=await eco();out=await finish(stale);assert.equal(out.status,200,JSON.stringify(out));assert.equal(out.data.result.expired,true);assert.deepEqual(await eco(),safeEco);
 // Strict war manual transcript uses authoritative HP and scores (no client HP fields).
 const wm=await start('war',{slot:2,deck:1},'actions'),ws=warSession(warDeck(wm.atk,by,wm.atk_buff),warDeck(wm.def,by,wm.def_buff),wm.seed,[],{view:true});x=ws.next();while(!x.done)x=ws.next(x.value.ask?{k:'auto'}:undefined);out=await finish(wm,ws.acts);assert.equal(out.status,200,JSON.stringify(out));assert.equal(out.data.result.win,x.value.win);
 // Kill switch survives migration rerun and rejects new attempts/claims/real payouts.
 await q('update guildbattle_policy_v4 set enabled=false');await db.exec(sql);assert.equal(await val('select enabled v from guildbattle_policy_v4'),false);await reject('select raid_claim()',[],/reward verification pending/);assert.equal((await http({op:'start',kind:'raid',payload:{uids:ids},request:req(++serial),control:'auto',version:ENGINE_VERSION})).status,409);await q('update guildbattle_policy_v4 set enabled=true');
 // Forged quest progress is not evidence; verified raid-only proof can pay once.
 await q(`insert into guild_daily_quests(user_id,day,slot,qkey,goal,progress) values($1,_guild_day(),1,'d_boss',999,999) on conflict(user_id,day,slot) do update set qkey='d_boss',goal=999,progress=999,claimed_at=null`,[me]);await reject('select guild_quest_claim(1)',[],/not reached/);await q('update guild_daily_quests set goal=1 where user_id=$1 and slot=1',[me]);const quest=await rpc('select guild_quest_claim(1) v');assert(quest.got.gold>0);await reject('select guild_quest_claim(1)',[],/already claimed/);
 // Transaction rollback includes HP, score, gear, quest feeds, wallet and receipts.
 await db.exec(seed.replace("action text := 'start'","action text := 'reset'"));const rb=await start(),snap=await eco(),hp=await q('select * from guild_raids_v4 order by guild_id,week');
 await db.exec(`create function test_v4_fail() returns trigger language plpgsql as $$ begin raise exception 'fixture rollback';end $$;create trigger v4_fail before insert on reward_claims for each row execute function test_v4_fail()`);
 assert.equal((await finish(rb)).status,409);assert.deepEqual(await eco(),snap);assert.deepEqual(await q('select * from guild_raids_v4 order by guild_id,week'),hp);assert.equal(await val('select status v from guildbattle_sessions_v4 where id=$1',[rb.id]),'issued');await db.exec('drop trigger v4_fail on reward_claims;drop function test_v4_fail()');assert.equal((await finish(rb)).status,200);

 // Two users issued against the same shared HP: overkill carries once and only
 // the actual last hitter gets the stage-1 last-hit ledger entry.
 await db.exec(seed.replace("action text := 'start'","action text := 'reset'"));
 const bgid=await val('select guild_id v from guild_members where user_id=$1',[other]);
 await q(`update guild_members set guild_id=$1,role='member' where user_id=$2`,[gid,other]);
 await q(`update guild_raids_v4 set hp_left=10 where guild_id=$1 and week=_raid_week_v4()`,[gid]);
 const ca=await start(),oids=await val(`select jsonb_agg(c->>'uid') v from story_progress,jsonb_array_elements(data->'owned') c where user_id=$1`,[other]);
 const cbhttp=await http({op:'start',kind:'raid',payload:{uids:oids},request:req(++serial),control:'auto',version:ENGINE_VERSION},'fixture-other');assert.equal(cbhttp.status,200,JSON.stringify(cbhttp));const cb=cbhttp.data;
 const da=verifyBattle(ca,null).damage,dbb=verifyBattle(cb,null).damage;
 assert.equal((await finish(ca)).status,200);assert.equal((await finish(cb,null,'fixture-other')).status,200);
 const shared=(await q(`select * from guild_raids_v4 where guild_id=$1 and week=_raid_week_v4()`,[gid]))[0];assert.equal(shared.total_damage,da+dbb);assert.equal(shared.stage,2);assert.equal(shared.hp_left,shared.hp_max-(da+dbb-10));
 assert.equal(await val(`select count(*)::int v from guild_claims where ref='raidlh:'||$1||':'||_raid_week_v4()||':1:v4'`,[gid]),1);
 const stageClaim=await rpc('select raid_claim() v');assert(stageClaim.got.gem>0);assert.equal(stageClaim.stages.find(x=>x.stage===1).claimed,true);await reject('select raid_claim()',[],/nothing to claim/);
 const ec=await eco();await finish(ca);await finish(cb,null,'fixture-other');assert.deepEqual(await eco(),ec);
 await q(`update guild_members set guild_id=$1,role='boss' where user_id=$2`,[bgid,other]);
 // Past-season lazy settlement is complete before any seasonal rank is claimable.
 const lastSeason=await val('select _war_season_v4()::text v');await db.exec(seed.replace("action text := 'start'","action text := 'reset'"));
 assert.equal(await val(`select count(distinct day)::int v from war_matches_v4 where season=$1 and settled`,[lastSeason]),5);
 assert.equal((await rpc('select war_claim() v')).ok,true);await reject('select war_claim()',[],/nothing to claim/);
 // An optional ally is provisioned into A, not into a third guild, and is fully
 // playable after reset without skipping the battle verifier or daily budgets.
 const ally='33333333-3333-4333-8333-333333333333';await q(`insert into auth.users(id) values($1)`,[ally]);await q(`insert into story_progress(user_id,data) values($1,'{"starter":"10111","owned":[]}')`,[ally]);
 const allySeed=seed.replace("allies_a uuid[] := '{}'",`allies_a uuid[] := '{${ally}}'`).replace("action text := 'start'","action text := 'reset'");await db.exec(allySeed);assert.equal(await val('select guild_id v from guild_members where user_id=$1',[ally]),gid);assert.equal(await val("select jsonb_array_length(data->'owned') v from story_progress where user_id=$1",[ally]),5);

 // Saved defense configuration may reference a card sold before roster freeze.
 // It must become a valid NPC fallback, not JSON-null inside a broken deck array.
 const savedDef=await val('select def1 v from war_decks_v4 where user_id=$1',[me]);await q(`update war_decks_v4 set def1='[{"uid":"sold-card","id":"10111"}]' where user_id=$1`,[me]);
 const future=await val(`select _war_third_wed_v4((_war_season_v4()+interval '1 month')::date)::text v`);await q(`insert into war_entries_v4(season,guild_id) values($1,$2)`,[future,gid]);await q('select _war_lock_v4($1)',[future]);assert.equal(await val('select def_snap v from war_roster_v4 where season=$1 and user_id=$2',[future,me]),null);await q('select _war_pair_v4($1,1)',[future]);await q('update war_decks_v4 set def1=$1 where user_id=$2',[JSON.stringify(savedDef),me]);
 // Auth and strict schemas reject before any trusted settlement.
 assert.equal((await http({op:'finish',id:r.id,actions:null},'forged-token')).status,401);assert.equal((await http({op:'start',kind:'raid',payload:{uids:ids,damage:999},request:req(++serial),control:'auto',version:ENGINE_VERSION})).status,409);
 const noProd=createHandler({...env,SUPABASE_URL:'https://htarwisgkkphutxxnuak.supabase.co'},()=>{throw Error('must not fetch');});assert.equal((await http({},'fixture-me',noProd)).status,503);
 console.log('Phase4 SQL + real '+(process.argv.includes('--dashboard')?'Dashboard':'Edge')+' PASS: issuance, AUTO/manual, snapshots/NPC, ownership, strict input, exact-once, sweeps, limits, expiry, guild switch, stale HP, kill switch, raid quests, atomic rollback, hostile ACL defaults, seed/reset');

} catch(e) {console.error('FAIL',e.message,e.where||'',e.stack?.split('\n').slice(0,3).join('\n'));process.exitCode=1;} finally { await db.close(); }
