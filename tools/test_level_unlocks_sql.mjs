// Offline DB tests: real full staging stack + authenticated RPCs, never live Supabase.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
import {buildSql,INSTALL_ACK} from './build_staging_sql.mjs';
const rd=p=>readFile(new URL('../'+p,import.meta.url),'utf8');
const db=new PGlite(), me='11111111-1111-4111-8111-111111111111', other='22222222-2222-4222-8222-222222222222';
const q=async(s,p=[]) => (await db.query(s,p)).rows;
const val=async(s,p=[]) => (await q(s,p))[0]?.v;
async function as(fn,uid=me,role='authenticated') {
 await q("select set_config('request.jwt.claim.sub',$1,false)",[uid || '']);await db.exec('set role '+role);
 try{return await fn();}finally{await db.exec('reset role');}
}
const rpc=(s,p=[])=>as(()=>val(s,p));
const reject=(s,p=[],pat=/permission denied/)=>as(()=>assert.rejects(q(s,p),e=>pat.test(e.message)));
const lv=n=>q('update player_state set level=$1 where user_id=$2',[n,me]);
const progression=()=>val("select jsonb_build_object('level',level,'xp',xp) v from player_state where user_id=$1",[me]);
try {
 await db.exec(`create role anon;create role authenticated;create role service_role;create schema auth;
 create table auth.users(id uuid primary key,email text,raw_user_meta_data jsonb default '{}',raw_app_meta_data jsonb default '{}',created_at timestamptz default now(),last_sign_in_at timestamptz,email_confirmed_at timestamptz);
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
 grant usage on schema auth,public to anon,authenticated,service_role;
 alter default privileges in schema public grant all on tables to anon,authenticated;
 alter default privileges in schema public grant all on sequences to anon,authenticated;
 alter default privileges in schema public grant execute on functions to anon,authenticated,service_role;`);
 await db.exec((await buildSql()).replace(`confirmed_ref text := '${INSTALL_ACK}'`,"confirmed_ref text := 'abcdefghijklmnopqrst'"));
 const migration=await rd('supabase/level_unlocks_staging.sql');
 await assert.rejects(db.exec(migration),/STOP: unlock policy only staging/);await db.exec('rollback');
 const id=await val('select system_identifier::text v from pg_control_system()');
 const approved=migration.replaceAll("'7703759698107299042'",`'${id}'`);
 const acls=await q("select oid,proacl::text from pg_proc where pronamespace='public'::regnamespace order by oid");
 await db.exec(approved);await db.exec(approved);
 assert.deepEqual(await q("select oid,proacl::text from pg_proc where oid=any($1::oid[]) order by oid",[acls.map(x=>x.oid)]),acls,'upgrade preserves all prior function OIDs and ACLs');
 await q("insert into auth.users(id,email,created_at) values($1,'one@example.invalid',now()-interval '8 days'),($2,'two@example.invalid',now()-interval '8 days')",[me,other]);
 await q('insert into player_state(user_id,level,xp) values($1,1,17),($2,1,0)',[me,other]);
 await q("insert into story_progress(user_id,data) values($1,'{\"starter\":\"10111\",\"owned\":[],\"cleared\":{\"1\":[1,3]}}'),($2,'{\"owned\":[]}')",[me,other]);
 await q("insert into player_wallet(user_id,gold,blood,soul) values($1,0,0,0),($2,0,0,0)",[me,other]);
 await q("insert into story_gacha(user_id,last_draw,tickets) values($1,_gem_day()-1,10)",[me]);
 const policy=JSON.parse(await rd('tools/unlocks/policy.json'));
 assert.deepEqual(await val('select _unlock_levels() v'),policy.features);
 for(let c=0;c<=15;c++) assert.equal(await val('select _player_unlock_level($1) v',['chapter_'+c]),1);
 assert.equal(await val("select val v from trade_config where key='min_level'"),15);
 assert.equal(await val("select val v from trade_config where key='min_account_days'"),7);
 assert.equal(await val('select _camp_need_level(1) v'),12);
 assert.equal(await val('select _guild_min_level() v'),6);
 assert.equal(await val('select _lend_min_level() v'),13);
 for(const [t,n] of [['normal',10],['wind',25],['ice',25],['fire',25],['light',40],['dark',40]]) assert.equal(await val('select _tower_min_level($1) v',[t]),n);
 // Facilities deliberately unchanged pending the owner's balance decision.
 assert.equal(await val('select _camp_lv_need(_camp_forge_lv()) v'),35);
 assert.equal(await val('select _camp_lv_need(_camp_dojo_lv()) v'),50);
 assert.equal(await val('select _camp_lv_mult(8) v'),'1.35');
 const rules=JSON.parse(await rd('tools/unlocks/rpc_gates.json'));
 let gated=0;
 for(const rule of rules) {
  const f=(await q(`select p.proname,pg_get_function_identity_arguments(p.oid) args,p.proargnames,
   array(select format_type(t,null) from unnest(p.proargtypes::oid[]) t) types,
   has_function_privilege('authenticated',p.oid,'execute') allowed
   from pg_proc p where p.pronamespace='public'::regnamespace and p.proname=$1`,[rule.name]))[0];
  assert(f,rule.name);
  if(!f.allowed) continue; // Phase1 revocations must stay revoked.
  const key=rule.name.startsWith('pvp_')?'pvp_hr':rule.name==='guildbattle_start_v4'?'raid':rule.gate.match(/_unlock_require\('([^']+)'/)[1];
  const args=f.types.map((t,i)=> f.proargnames?.[i]==='p_league'?"'hr'::text":f.proargnames?.[i]==='p_mode'?"'1v1'::text":f.proargnames?.[i]==='p_kind'&&rule.name==='guildbattle_start_v4'?"'raid'::text":`null::${t}`);
  const call=`select public.${rule.name}(${args.join(',')})`;
  await lv(policy.features[key]-1);await reject(call,[],new RegExp('^Lv'+policy.features[key]+'$'));
  await lv(policy.features[key]);
  try {await as(()=>q(call));} catch(e) {assert.notEqual(e.message,'Lv'+policy.features[key],rule.name+' unlocks at exact boundary');}
  gated++;
 }
 assert(gated>=40);
 for(const [league,mode,n] of [['hr','1v1',3],['open','1v1',15],['hr','3v3',17],['open','3v3',17],['hr','boss',20],['open','boss',20]]) {
  await lv(n-1);await reject('select pvp_set_deck($1,$2,0,\'[]\')',[league,mode],new RegExp('^Lv'+n+'$'));
  await lv(n);try{await rpc('select pvp_set_deck($1,$2,0,\'[]\') v',[league,mode]);}catch(e){assert.notEqual(e.message,'Lv'+n);}
 }
 // Raw client progress edits are NOT trusted clear evidence, even when migration is reapplied.
 await lv(1);await reject("select unlock_intro_claim('leader')",[],/intro locked/);
 await reject("select battle_session_start_v2('story','1:1','[]','aaaaaaaa-aaaa-4aaa-8aaa-000000000001')",[],/previous chapter required/);
 await q("insert into battle_legacy_access_v2(user_id,cleared) values($1,'{\"0\":[1,2,3,4,5],\"1\":[1,3]}') on conflict(user_id) do update set cleared=excluded.cleared",[me]);
 const tk=await val('select tickets v from story_gacha where user_id=$1',[me]);
 await rpc("select unlock_intro_claim('ch0') v");assert.equal(await val('select tickets v from story_gacha where user_id=$1',[me]),tk,'existing CH0 ten-ticket chapter reward not doubled');
 let before=await progression();await rpc("select unlock_intro_claim('leader') v");assert.deepEqual(await progression(),before);
 assert.equal(await val('select blood v from player_wallet where user_id=$1',[me]),5000);
 const gold=await val('select gold v from player_wallet where user_id=$1',[me]);
 assert.equal((await rpc("select unlock_intro_claim('leader') v")).already,true);
 assert.equal(await val('select gold v from player_wallet where user_id=$1',[me]),gold);
 await lv(3);before=await progression();await rpc("select unlock_intro_claim('pvp_hr') v");assert.deepEqual(await progression(),before);
 await reject("select unlock_intro_claim('attr40')",[],/intro locked/);
 await reject("select unlock_intro_claim('forged')",[],/invalid intro/);
 await reject('select * from unlock_intro_receipts');
 await reject('insert into unlock_intro_receipts(user_id,event,reward) values(auth.uid(),\'forged\',\'{}\')');
 await reject("select _unlock_require('guild')");
 await as(()=>assert.rejects(q('select unlock_status()'),/permission denied/),null,'anon');
 await lv(14);
 for(const key of ['guild','tower','camp','sigil']) {before=await progression();await rpc('select unlock_intro_claim($1) v',[key]);assert.deepEqual(await progression(),before);}
 assert.equal(await val("select count(*)::int v from player_mail where user_id=$1 and reason like 'unlock_intro:%' and kind='box'",[me]),6);
 assert.equal(await val("select count(*)::int v from player_mail where user_id=$1 and reason='unlock_intro:sigil' and kind='sigil_frag'",[me]),10);
 // A failed reward grant rolls back receipt and currencies together.
 await db.exec(`create function unlock_test_fail() returns trigger language plpgsql as $$begin if new.reason='unlock_intro:dispatch' then raise exception 'injected grant failure';end if;return new;end$$;
 create trigger unlock_test_fail after insert on wallet_log for each row execute function unlock_test_fail();`);
 const snap=await val('select gold v from player_wallet where user_id=$1',[me]);
 await reject("select unlock_intro_claim('dispatch')",[],/injected grant failure/);
 assert.equal(await val("select count(*)::int v from unlock_intro_receipts where user_id=$1 and event='dispatch'",[me]),0);
 assert.equal(await val('select gold v from player_wallet where user_id=$1',[me]),snap);
 await db.exec('drop trigger unlock_test_fail on wallet_log;drop function unlock_test_fail()');
 await rpc("select unlock_intro_claim('dispatch') v");
 const receipts=await q('select * from unlock_intro_receipts order by event');await db.exec(approved);assert.deepEqual(await q('select * from unlock_intro_receipts order by event'),receipts);
 const status=await rpc('select unlock_status() v');assert(status.entries.find(e=>e.key==='guild').claimed);
 assert.equal((await as(()=>val('select unlock_status() v'),other)).entries.some(e=>e.claimed),false);
 // Central membership gate also checks the applicant when an officer approves an OLD request.
 const gid=await val("insert into guilds(name,name_key,emblem,boss) values('unlock fixture','unlock fixture',1,$1) returning id v",[me]);
 await q("insert into guild_members(user_id,guild_id,role) values($1,$2,'boss')",[me,gid]);
 const invite=await val("insert into guild_requests(guild_id,user_id,kind,by_user) values($1,$2,'apply',$2) returning id v",[gid,other]);
 await reject('select guild_respond($1,true)',[invite],/^Lv6$/);
 assert.equal(await val('select count(*)::int v from guild_members where user_id=$1',[other]),0);
 // Market mutations retain the account-age prerequisite in addition to Lv15.
 await lv(14);await reject("select trade_list('{}','{}','')",[],/trade level/);
 await lv(15);await q('update auth.users set created_at=now() where id=$1',[me]);
 await reject("select trade_list('{}','{}','')",[],/trade account age/);
 await q("update auth.users set created_at=now()-interval '8 days' where id=$1",[me]);
 try{await rpc("select trade_list('{}','{}','') v");}catch(e){assert(!/trade level|trade account age/.test(e.message));}
 // With a trainable card, a real player-selected camp_put is needed (no materials/guild).
 const trainee=await val("select _story_new_card('10111') v");
 await q("update story_progress set data=jsonb_set(data,'{owned}',$1::jsonb) where user_id=$2",[JSON.stringify([trainee]),other]);
 await q('update player_state set level=12 where user_id=$1',[other]);
 let os=await as(()=>val('select unlock_status() v'),other);assert.equal(os.entries.find(e=>e.key==='camp').action_done,false);
 await as(()=>assert.rejects(q("select unlock_intro_claim('camp')"),/tutorial action required/),other);
 await as(()=>val('select camp_status() v'),other);
 await as(()=>val('select camp_put(1,$1) v',[trainee.uid]),other);
 await as(()=>val('select camp_remove(1) v'),other);
 os=await as(()=>val('select unlock_status() v'),other);assert.equal(os.entries.find(e=>e.key==='camp').action_done,true,'chosen assignment proof survives removal');
 await as(()=>val("select unlock_intro_claim('camp') v"),other);
 // One normal battle is enough, even on defeat; tower_sweep is not required.
 os=await as(()=>val('select unlock_status() v'),other);assert.equal(os.entries.find(e=>e.key==='tower').action_done,false);
 await as(()=>assert.rejects(q("select unlock_intro_claim('tower')"),/tutorial action required/),other);
 const trial=await as(()=>val("select battle_session_start_v2('tower','normal:1',$1,'aaaaaaaa-aaaa-4aaa-8aaa-000000000088') v",[JSON.stringify([trainee.uid])]),other);
 await q("update battle_sessions_v2 set issued_at=clock_timestamp()-interval '10 seconds' where id=$1",[trial.session]);
 await as(()=>val('select battle_session_finish_v2($1,$2) v',[trial.session,JSON.stringify({win:false,reason:'wipe',turns:4,my_turns:2,mana:100,skills:0,cards:[]})]),other);
 os=await as(()=>val('select unlock_status() v'),other);assert.equal(os.entries.find(e=>e.key==='tower').action_done,true);
 await as(()=>val("select unlock_intro_claim('tower') v"),other);
 assert.equal(await val('select xp v from player_state where user_id=$1',[other]),0,'camp/tower intro rewards do not add account EXP');
 const weak=await q("select proname from pg_proc where pronamespace='public'::regnamespace and prosecdef and left(proname,1)='_' and pg_get_function_result(oid)<>'trigger' and (has_function_privilege('anon',oid,'execute') or has_function_privilege('authenticated',oid,'execute'))");assert.deepEqual(weak,[]);
 console.log(`Level unlock SQL: ${gated} direct RPC boundaries, six PvP combinations, previous clears, atomic/idempotent rewards, no EXP, RLS/ACL, wrong-DB guard: OK`);
} catch(e) {console.error('UNLOCK SQL FAILURE:',e.message,e.where || '');process.exitCode=1;}
finally {await db.close();}
