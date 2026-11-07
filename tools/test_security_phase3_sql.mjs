// No network/keys. PGlite SQL + the REAL trusted handler/engine behind a simulated Auth/REST boundary.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { PGlite } from '@electric-sql/pglite';
import { buildSql, INSTALL_ACK } from './build_staging_sql.mjs';
import { ENGINE_VERSION, verifyBattle } from '../supabase/functions/_shared/pvp-engine-v3.mjs';
import { dashboardHandler } from './load_phase3_dashboard.mjs';
import { createHandler } from '../supabase/functions/pvp-verify-v3/handler.mjs';
import { setSkillData, skillsOf } from '../js/skills.js';
import { parseCSV, setCardPool } from '../js/rules.js';
import { manualMatch, snapCard, MODES, roundSeed } from '../js/pvp-core.js';
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
const signatures={pvp_start_v3:['p_league','p_mode','p_request','p_control','p_engine_hash'],pvp_engine_session_v3:['p_uid','p_id'],pvp_engine_settle_v3:['p_uid','p_id','p_engine_hash','p_submission','p_result']};
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
 else assert.equal(name,'pvp_start_v3');
 const uid=opts.headers.authorization==='Bearer fixture-other'?other:me;
 const ps=signatures[name].map(k=>typeof args[k]==='object'&&args[k]!==null?JSON.stringify(args[k]):args[k]);
 try { const data=await as(trusted?null:uid,()=>val(`select public.${name}(${ps.map((_,i)=>'$'+(i+1)).join(',')}) v`,ps),trusted?'service_role':'authenticated'); return Response.json(data); }
 catch(e) { return Response.json({message:e.message},{status:400}); }
};
const factory=process.argv.includes('--dashboard')?dashboardHandler:createHandler;
const handler=factory(env,fetcher);
const http=async(body,token='fixture-me',h=handler)=>{
 const r=await h(new Request('https://example.invalid/pvp-verify-v3',{method:'POST',headers:{'content-type':'application/json',authorization:'Bearer '+token},body:JSON.stringify(body)}));
 return {status:r.status,data:await r.json()};
};
let serial=0;
const start=async(mode='1v1',control='auto',token='fixture-me')=>{
 await q(`update pvp_attempts set created_at=clock_timestamp()-interval '3 seconds'`);
 const r=await http({op:'start',league:'open',mode,request:req(++serial),control,version:ENGINE_VERSION},token);
 assert.equal(r.status,200,JSON.stringify(r)); return r.data;
};
const finish=(s,actions=null,token='fixture-me')=>http({op:'finish',id:s.id,actions},token);
async function winningSession() {
 const s=await start();
 for(let seed=1;seed<300;seed++) {
  if(verifyBattle({...s,seed},null).win) {
   // ADMIN-ONLY deterministic fixture of the server RNG, NOT a client API.
   await q(`update pvp_attempts set seed=$1 where id=$2`,[seed,s.id]); return {...s,seed};
  }
 }
 throw Error('no winning seed for fixture');
}

const eco=()=>q(`select user_id,gold,gem_free,gem_paid,(select tickets from story_gacha g where g.user_id=w.user_id) tickets,
 (select count(*)::int from reward_claims c where c.user_id=w.user_id) claims from player_wallet w order by user_id`);
try {
 await db.exec(`create role anon; create role authenticated; create role service_role; create schema auth;
 create table auth.users(id uuid primary key,email text,raw_user_meta_data jsonb default '{}',raw_app_meta_data jsonb default '{}',created_at timestamptz default now(),last_sign_in_at timestamptz,email_confirmed_at timestamptz);
 create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
 create function auth.jwt() returns jsonb language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb $$;
 grant usage on schema auth,public to anon,authenticated,service_role;
 alter default privileges in schema public grant all on tables to anon,authenticated;
 alter default privileges in schema public grant all on sequences to anon,authenticated;
 alter default privileges in schema public grant execute on functions to anon,authenticated,service_role;`);
 let base=await buildSql(); const at=base.indexOf('-- ===== SOURCE: security_phase3_pvp.sql =====');
 assert(at>0); base=base.slice(0,at)+base.slice(base.indexOf('-- 공개 게임 설정만 명시적으로 조회 허용',at));
 await db.exec(base.replace(`confirmed_ref text := '${INSTALL_ACK}'`,`confirmed_ref text := 'abcdefghijklmnopqrst'`));
 await q(`insert into auth.users(id,email) values($1,'one@example.invalid'),($2,'two@example.invalid')`,[me,other]);
 await q(`insert into player_wallet(user_id,gold,gem_free) values($1,100,500),($2,200,700)`,[me,other]);
 const owned=[]; for(const id of ['10111','10224','10225','10226','10227','10228','10229','10230','10231','10232','10233','10234','10235','10236','10237']) {
  // Catalog-independent fixture selection below replaces unknown IDs.
  if(await val(`select exists(select 1 from pvp_card_meta where id=$1) v`,[id])) owned.push(await val(`select _story_new_card($1) v`,[id]));
 }
 const ids=await q(`select id from pvp_card_meta where grade in('NORMAL','RARE','HIGH RARE') order by id limit 18`);
 for(const {id} of ids) if(!owned.some(o=>o.id===id)) owned.push(await val(`select _story_new_card($1) v`,[id]));
 owned.forEach(o=>o.level=80);
 const enemy=owned.map(o=>({...o,uid:'enemy-'+o.uid,level:1}));
 await q(`insert into story_progress(user_id,data) values($1,$2),($3,$4)`,[me,JSON.stringify({owned}),other,JSON.stringify({owned:enemy})]);
 await q(`insert into player_state(user_id,level) values($1,80),($2,80)`,[me,other]);
 await q(`insert into pvp_ratings(user_id,league,mode,season,rating,wins) values($1,'open','1v1',_pvp_season(),9999,999)`,[me]);
 await db.exec(`create function public.pvp_report(integer,integer,integer) returns jsonb language sql as $$ select '{"fake":true}'::jsonb $$; grant execute on function public.pvp_report(integer,integer,integer) to authenticated; grant update(rating) on pvp_ratings to authenticated;`);
 const before=await eco(), legacy=await q(`select * from pvp_ratings`);
 const migration=await rd('supabase/security_phase3_pvp.sql');
 await assert.rejects(db.exec(migration),/STOP: phase3 only/); await db.exec('rollback');
 const system=await val(`select system_identifier::text v from pg_control_system()`);
 const sql=migration.replaceAll("'7703759698107299042'",`'${system}'`); // IN-MEMORY binding only. Production SQL guard stays fixed.
 await db.exec(sql); await db.exec(sql);
 assert.deepEqual(await eco(),before); assert.deepEqual(await q(`select * from pvp_ratings`),legacy);
 const pool=parseCSV(await rd('data/cards.csv')); setCardPool(pool); setSkillData(JSON.parse(await rd('data/skills.json')),JSON.parse(await rd('data/combos.json')));
 const byId=id=>pool.find(c=>String(c.id)===String(id));
 for(const u of [me,other]) for(const mode of ['1v1','3v3','boss']) for(let i=0;i<MODES[mode].decks;i++) {
  const cards=(u===me?owned:enemy).slice(i*5,i*5+(mode==='boss'?6:5));
  assert(cards.length>=2); await rpc(`select pvp_set_deck('open',$1,$2,$3) v`,[mode,i,JSON.stringify(cards.map(o=>o.uid))],u);
 }
 assert.equal((await rpc(`select pvp_status('open','1v1') v`)).rating,1000);
 assert.equal((await rpc(`select pvp_status('open','1v1') v`)).legacy_rating,9999);
 await reject(`select pvp_report(1,1,0)`); await reject(`select pvp_start('open','1v1')`); await reject(`select pvp_log(1,'[]')`);
 await reject(`select pvp_engine_session_v3($1,1)`,[me]);
 await reject(`select pvp_engine_settle_v3($1,1,$2,'{}','{}')`,[me,ENGINE_VERSION]);
 for(const table of ['pvp_ratings','pvp_attempts','pvp_decks','pvp_ratings_v3','pvp_sessions_v3','pvp_events_v3','pvp_policy_v3','pvp_titles','pvp_tier_claims','pvp_reward_claims']) {
  await reject(`update ${table} set user_id=$1`,[me],/permission denied|does not exist/);
 }
 assert.equal(await val(`select count(*)::int v from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in('pvp_start','pvp_log','pvp_report','pvp_engine_settle_v3','pvp_engine_session_v3') and (has_function_privilege('anon',p.oid,'execute') or has_function_privilege('authenticated',p.oid,'execute'))`),0);
 await reject(`update pvp_ratings set rating=99999`); await reject(`update pvp_policy_v3 set enabled=true`);
 const c=restCalls;
 assert.equal((await http({op:'start',league:'open',mode:'1v1',request:req(999),control:'auto',version:ENGINE_VERSION},'forged-jwt')).status,401);
 assert.equal(restCalls,c);
 assert.equal((await http({op:'finish',id:'1',actions:null,wins:99})).status,400);
 assert.equal((await http({op:'finish',id:'1',actions:[[{k:'auto'}]]})).status,400);
 assert.equal((await http({op:'start',league:'open',mode:'1v1',request:req(999),control:'auto',version:'stale'})).status,409);
 assert.equal((await http({op:'forfeit',id:'1'},'fixture-me',factory({...env,SUPABASE_URL:'https://htarwisgkkphutxxnuak.supabase.co'},fetcher))).status,503);
 // Progression after deck save: both attacker and defender MUST be refreshed
 // from owned metadata, not the stored defense cache. No backfill/re-save needed.
 const savedDecks=await q(`select user_id,mode,slot,snap from pvp_decks order by user_id,mode,slot`);
 const fresh=(list,level,exb)=>list.map(o=>({...o,level,ex:2,exb,boost:{ATK:7,HP:8,DEF:3},skillLv:Object.fromEntries(skillsOf(o.id).flatMap((s,i)=>s.mode==='active'?[[String(i+1),3]]:[]))}));
 const mineFresh=fresh(owned,40,12.5), enemyFresh=fresh(enemy,7,5);
 await q(`update story_progress set data=jsonb_set(data,'{owned}',$2) where user_id=$1`,[me,JSON.stringify(mineFresh)]);
 await q(`update story_progress set data=jsonb_set(data,'{owned}',$2) where user_id=$1`,[other,JSON.stringify(enemyFresh)]);
 const assertFresh=s=>{ for(const [key,list] of [['me',mineFresh],['opp',enemyFresh]]) for(const d of s[key]) for(const o of d) {
  const raw=list.find(x=>x.uid===o.uid); assert(raw,'both snapshots must be the real stored player, not bot metadata');
  for(const k of ['level','ex','exb','boost','skillLv']) assert.deepEqual(o[k],raw[k],key+' fresh '+k);
 }};
 const first=await start(); assertFresh(first);
 assert.deepEqual(await q(`select user_id,mode,slot,snap from pvp_decks order by user_id,mode,slot`),savedDecks,'fresh snapshots do not mutate cached defense data');
 const reqBody={op:'start',league:'open',mode:'1v1',request:req(serial),control:'auto',version:ENGINE_VERSION};
 assert.equal((await http(reqBody)).data.id,first.id,'idempotent start reserves one try');
 assert.equal(await val(`select count(*)::int v from pvp_sessions_v3`),1);
 assert.equal((await http({...reqBody,request:req(999)})).data.error,'rate limited');
 assert.equal((await http({...reqBody,control:'actions'})).status,409);
 assert.equal((await finish(first,null,'fixture-other')).status,409,'other user cannot get/settle session');
 assert.equal((await finish(first,[[{k:'end'}]])).status,422,'auto cannot replace AI actions');
 const derived=verifyBattle(first,null), result=await finish(first); assert.equal(result.status,200,JSON.stringify(result));
 assert.equal(result.data.win,derived.win); assert(result.data.verified);
 assert.equal((await http({op:'status',id:first.id},'fixture-other')).status,409);
 const savedStatus=await http({op:'status',id:first.id}); assert.deepEqual(savedStatus.data.result,result.data);
 const after=await eco(); assert.deepEqual(await finish(first),result); assert.deepEqual(await eco(),after);
 const rr=await q(`select * from pvp_ratings_v3 where mode='1v1' order by user_id`);
 assert.equal(rr[0].rating,first.rating+(derived.win?first.dw:-first.dl));
 assert.equal(rr[1].rating,first.opp_rating+(derived.win?-Math.trunc(first.dw/2):Math.trunc(first.dl/2)));
 assert.equal(rr[0].games_verified,1); assert.equal(rr[0].wins,derived.win?1:0); assert.equal(rr[1].def_losses,derived.win?1:0);
 assert.equal((await http({op:'forfeit',id:first.id})).status,409,'changed replays rejected');
 assert.equal(await val(`select _ach_prog($1,'pvp_wins') v`,[me]),derived.win?1:0);
 assert.equal(await val(`select _clear_mission_prog_v2($1,'win',false) v`,[me]),derived.win?1:0);
 const pvpAchievements=(await rpc('select achievements_status() v')).cats.flatMap(c=>c.items).filter(a=>a.id==='pvp_wins'||a.id==='pvp_tier');
 assert(pvpAchievements.length>0 && pvpAchievements.every(a=>!a.held));
 // AUTO matching across all modes. No client result fields ever reach the settlement call.
 for(const mode of ['3v3','boss']) { const s=await start(mode); assertFresh(s); const got=await finish(s); assert.equal(got.status,200,JSON.stringify(got)); assert.equal(got.data.win,verifyBattle(s,null).win); }
 // Real live/manual transcript, including SKIP/AUTO canonical records, strict early/trailing/illegal input.
 const s=await start('1v1','actions'), st=manualMatch(s.me[0].map(o=>snapCard(o,byId)),s.opp[0].map(o=>snapCard(o,byId)),roundSeed(s.seed,0),null,{view:true,manual:true});
 let x=st.next(); while(!x.done) x=st.next(x.value.ask?{k:'auto'}:undefined);
 assertFresh(s);
 const acts=[st.acts]; assert.equal((await finish(s,[[]])).status,422);
 assert.equal((await finish(s,[[{k:'skill',i:0,s:'forged'}]])).status,422);
 const longer=structuredClone(acts); longer[0].push({k:'end'}); assert.equal((await finish(s,longer)).status,422);
 assert.equal((await finish(s,acts)).status,200);
 assert.equal((await finish(s,[[]])).status,409);
 const guild=await val(`insert into guilds(name,name_key,boss) values('fixture','fixture',$1) returning id v`,[me]);
 await q(`insert into guild_members(user_id,guild_id,role) values($1,$2,'boss')`,[me,guild]);
 // A 3-win streak gives exactly the configured server reward, once, atomic with both ratings.
 for(let i=0;i<3;i++) {
  const s=await winningSession(); const result=verifyBattle(s,null); assert(result.win);
  if(i===0) await q(`update pvp_ratings_v3 set streak=2 where user_id=$1 and league='open' and mode='1v1' and season=_pvp_season()`,[me]);
  const before=await eco(); const r=await finish(s); assert.equal(r.status,200);
  if(i===0) { assert.deepEqual(r.data.streak_reward,{gold:300}); assert.equal((await eco())[0].gold,before[0].gold+300); }
  const loyalty=await val(`select balance::int v from loyalty_wallet where user_id=$1`,[me]);
  assert.equal(loyalty,10*(i+1));
  assert.deepEqual(await finish(s),r);
  assert.equal(await val(`select balance::int v from loyalty_wallet where user_id=$1`,[me]),loyalty);
 }
 // Failure after rating mutation rolls EVERYTHING back (including ledger/event/session).
 const rollbackSession=await winningSession();
 await q(`update pvp_ratings_v3 set streak=2 where user_id=$1 and league='open' and mode='1v1' and season=_pvp_season()`,[me]);
 await db.exec(`create function public.test_pvp_fail() returns trigger language plpgsql as $$ begin raise exception 'test rollback'; end $$; create trigger pvp_fail before insert on reward_claims for each row execute function public.test_pvp_fail();`);
 const rs=await q(`select * from pvp_ratings_v3 order by user_id,mode`), eb=await eco(), loyaltyBefore=await val(`select balance::int v from loyalty_wallet where user_id=$1`,[me]);
 assert.equal((await finish(rollbackSession)).status,409); assert.deepEqual(await eco(),eb); assert.deepEqual(await q(`select * from pvp_ratings_v3 order by user_id,mode`),rs);
 assert.equal(await val(`select status v from pvp_sessions_v3 where id=$1`,[rollbackSession.id]),'issued');
 assert.equal(await val(`select balance::int v from loyalty_wallet where user_id=$1`,[me]),loyaltyBefore,'guild feed must roll back too');
 await db.exec('drop trigger pvp_fail on reward_claims; drop function test_pvp_fail()'); assert.equal((await finish(rollbackSession)).status,200);
 // Expiry, explicit quit, replacement: fixed losses only, no verified evidence or money.
 const expired=await start(); await q(`update pvp_sessions_v3 set expires_at=clock_timestamp()-interval '1 second' where id=$1`,[expired.id]);
 const expEco=await eco(), exp=await finish(expired); assert(exp.data.forfeit && !exp.data.verified); assert.deepEqual(await finish(expired),exp,'expired first finish is also idempotent'); assert.deepEqual(await eco(),expEco);
 const giveup=await start(); assert((await http({op:'forfeit',id:giveup.id})).data.forfeit);
 const replaced=await start(); const replacement=await start(); assert.equal(await val(`select verified v from pvp_sessions_v3 where id=$1`,[replaced.id]),false);
 assert((await http({op:'forfeit',id:replacement.id})).data.forfeit);
 // Daily caps include legacy attempts; tampered start RPC cannot get more sessions.
 await q(`insert into pvp_attempts(user_id,league,mode,season,day,opp_name,seed,my_snap,opp_snap,my_rating,opp_rating,dw,dl)
 select $1,'hr','1v1',_pvp_season(),_pvp_day(),'legacy',1,'[]','[]',1000,1000,1,1 from generate_series(1,10)`,[me]);
 const legacyId=await val(`select id::text v from pvp_attempts where league='hr' order by id limit 1`);
 assert.equal((await http({op:'finish',id:legacyId,actions:null})).data.error,'session not found');
 const cap=await http({op:'start',league:'hr',mode:'1v1',request:req(++serial),control:'auto',version:ENGINE_VERSION}); assert.equal(cap.status,409); assert.match(cap.data.error,/attempts/);
 // Season claims require NEW verified games, not the preserved 9999 rating or reserved forfeits.
 await reject(`select pvp_claim_tier('open','1v1')`,[],/not eligible/);
 const season=await val(`select _pvp_season() v`), prevSeason=await val(`select (_pvp_season()-7)::text v`);
 await reject(`select pvp_claim_reward('open','1v1',$1)`,[season],/season not ended/);
 await q(`insert into pvp_ratings(user_id,league,mode,season,rating,wins) values($1,'open','1v1',_pvp_season()-7,9999,999)`,[me]);
 await reject(`select pvp_claim_reward('open','1v1',$1)`,[prevSeason],/not ranked/);
 // Moving existing completed evidence to an ended season is an ADMIN-ONLY test clock fixture.
 await q(`update pvp_ratings_v3 set season=season-7 where league='open' and mode='1v1'`);
 const prev=(await rpc(`select pvp_status('open','1v1') v`)); assert(prev.pending && prev.pending_rank);
 const pay=await rpc(`select pvp_claim_tier('open','1v1') v`); assert(pay.reward.gold>0);
 await reject(`select pvp_claim_tier('open','1v1')`,[],/already claimed/);
 const rank=await rpc(`select pvp_claim_reward('open','1v1',$1) v`,[prevSeason]); assert(rank.reward.tickets>0);
 await reject(`select pvp_claim_reward('open','1v1',$1)`,[prevSeason],/already claimed/);
 const claims=await q(`select reward_kind from reward_claims where reward_kind like 'pvp_%_v3'`); assert(claims.some(c=>c.reward_kind==='pvp_tier_v3')&&claims.some(c=>c.reward_kind==='pvp_rank_v3'));
 // Existing-install engine upgrade: wrong DB/version/active sessions fail
 // closed; expired old transcripts are NEVER replayed under new rules.
 const upgradeRaw=await rd('supabase/security_phase3_pvp_level_stats.sql');
 await assert.rejects(db.exec(upgradeRaw),/STOP: PvP level stats only/); await db.exec('rollback');
 const upgrade=upgradeRaw.replaceAll("'7703759698107299042'",`'${system}'`);
 const oldHash='16b61abb1c42f29f063b9b84de938ef950363cdd2a23262cddf05c27c0c038a6';
 await q(`update pvp_policy_v3 set engine_hash=$1`,['0'.repeat(64)]);
 await assert.rejects(db.exec(upgrade),/unexpected PvP engine version/); await db.exec('rollback');
 assert.equal(await val(`select engine_hash v from pvp_policy_v3`),'0'.repeat(64));
 await q(`update pvp_policy_v3 set engine_hash=$1`,[oldHash]);
 const oldSession=await rpc(`select pvp_start_v3('open','boss',$1,'actions',$2) v`,[req(++serial),oldHash],other);
 const reserved=await q(`select * from pvp_ratings_v3 order by user_id,league,mode,season`), upgradeEco=await eco(), evidence=await val(`select count(*)::int v from pvp_events_v3`);
 await assert.rejects(db.exec(upgrade),/active old PvP sessions/); await db.exec('rollback');
 assert.equal(await val(`select engine_hash v from pvp_policy_v3`),oldHash);
 assert.deepEqual(await q(`select * from pvp_ratings_v3 order by user_id,league,mode,season`),reserved);
 assert.equal((await finish(oldSession,[[]],'fixture-other')).status,409,'active old transcript cannot be silently upgraded');
 assert.equal(await val(`select status v from pvp_sessions_v3 where id=$1`,[oldSession.id]),'issued');
 await q(`update pvp_sessions_v3 set expires_at=clock_timestamp()-interval '1 second' where id=$1`,[oldSession.id]);
 await db.exec(upgrade); await db.exec(upgrade);
 assert.equal(await val(`select engine_hash v from pvp_policy_v3`),ENGINE_VERSION);
 assert.deepEqual(await q(`select * from pvp_ratings_v3 order by user_id,league,mode,season`),reserved,'upgrade never resets/rewards/re-rates');
 assert.deepEqual(await eco(),upgradeEco); assert.equal(await val(`select count(*)::int v from pvp_events_v3`),evidence);
 assert.deepEqual(await q(`select user_id,mode,slot,snap from pvp_decks order by user_id,mode,slot`),savedDecks);
 const oldExpired=await finish(oldSession,[[]],'fixture-other'); assert.equal(oldExpired.status,200,JSON.stringify(oldExpired));
 assert(oldExpired.data.forfeit && !oldExpired.data.verified,'SQL closes expired old session without a new-engine replay');
 assert.deepEqual(await finish(oldSession,[[]],'fixture-other'),oldExpired);
 assert.equal(await val(`select count(*)::int v from pvp_events_v3`),evidence);
 // Kill switch survives rerunning migration, cannot be flipped by ordinary roles.
 await q(`update pvp_policy_v3 set enabled=false`); await db.exec(sql); await db.exec(upgrade);
 assert.equal(await val(`select enabled v from pvp_policy_v3`),false);
 await reject(`select pvp_claim_tier('open','1v1')`,[],/verification pending/);
 assert.equal((await rpc(`select pvp_status('open','1v1') v`)).reward_held,true);
 assert(authCalls>10 && restCalls>10);
 console.log((process.argv.includes('--dashboard')?'Dashboard standalone / ':'')+'Phase3 PGlite + real handler: staging guard/idempotency, JWT/ACL/ownership, canonical auto/manual replay, both ratings, rewards/events, transaction rollback, legacy isolation, expiry/forfeit, season claims, fresh attacker/defender upgrade metadata, guarded engine rollout/old-session expiry and kill switch OK');
} finally { await db.close(); }
