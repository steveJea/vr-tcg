// Offline only: existing-user legacy DB -> production delta. No network or real keys.
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {PGlite} from '@electric-sql/pglite';
import {buildSql,INSTALL_ACK} from './build_staging_sql.mjs';
import {buildProductionSql,productionBundle,versions,config,rd,payload} from './build_production_rollout.mjs';
import {fixture} from './phase5_fixture.mjs';
const db=new PGlite(),me='11111111-1111-4111-8111-111111111111',other='22222222-2222-4222-8222-222222222222';
const q=async(s,p=[]) => (await db.query(s,p)).rows,val=async(s,p=[]) => (await q(s,p))[0]?.v;
const as=async(u,fn,role='authenticated')=>{await q(`select set_config('request.jwt.claim.sub',$1,false)`,[u||'']);await db.exec('set role '+role);try{return await fn();}finally{await db.exec('reset role');}};
function handler(source,env,fetcher){let captured;const context=vm.createContext({Response,Request,TextDecoder,Uint8Array,structuredClone,crypto,console:{info(){}},fetch:fetcher,Deno:{env:{toObject:()=>({...env})},serve:h=>{captured=h;}}});new vm.Script(source).runInContext(context);assert.equal(typeof captured,'function');return captured;}
const http=async(h,body,token='fixture-me')=>{const r=await h(new Request('https://example.invalid',{method:'POST',headers:{'content-type':'application/json',authorization:'Bearer '+token},body:JSON.stringify(body)}));const data=await r.json();if(data.trace){assert.match(data.trace,/^[a-f0-9-]{36}$/);delete data.trace;}return {status:r.status,data};};
try{
 await db.exec(`create role anon;create role authenticated;create role service_role;create schema auth;
 create table auth.users(id uuid primary key,email text,raw_user_meta_data jsonb default '{}',raw_app_meta_data jsonb default '{}',created_at timestamptz default now(),last_sign_in_at timestamptz,email_confirmed_at timestamptz);
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
 grant usage on schema auth,public to anon,authenticated,service_role;
 alter default privileges in schema public grant all on tables to anon,authenticated;
 alter default privileges in schema public grant all on sequences to anon,authenticated;
 alter default privileges in schema public grant execute on functions to anon,authenticated,service_role;`);
 const full=await buildSql(),at=full.indexOf('-- ===== SOURCE: security_phase1_rewards.sql =====');assert(at>0);
 const legacy=full.slice(0,at)+full.slice(full.indexOf('-- 공개 게임 설정만 명시적으로 조회 허용',at));
 await db.exec(legacy.replace(`confirmed_ref text := '${INSTALL_ACK}'`,`confirmed_ref text := 'abcdefghijklmnopqrst'`));
 await q(`insert into auth.users(id,email) values($1,'one@example.invalid'),($2,'two@example.invalid')`,[me,other]);
 await q(`insert into player_wallet(user_id,gold,gem_free,gem_paid) values($1,12345,234,345),($2,999,87,65)`,[me,other]);
 await q(`insert into player_state(user_id,level) values($1,2),($2,80)`,[me,other]);
 const owned=await val(`select _story_new_card('10111') v`);owned.level=42;
 await q(`insert into story_progress(user_id,data) values($1,$2),($3,$4)`,[me,JSON.stringify({owned:[owned],starter:'10111',cleared:{1:[1,2,3]},stars:{1:{1:3}}}),other,JSON.stringify({owned:[],starter:'10111'})]);
 await q(`insert into tower_progress(user_id,tower,best_floor,paid_floor) values($1,'normal',3,1)`,[me]);
 await q(`insert into war_decks(user_id,def1,atk1) values($1,$2,$2)`,[me,JSON.stringify([owned])]);
 await q(`insert into pvp_ratings(user_id,league,mode,season,rating,wins) values($1,'open','1v1',_pvp_season(),1999,88)`,[me]);
 await q(`insert into matches(user_id,result) values($1,'win')`,[me]);
 await q(`insert into saves(user_id,data) values($1,'{"private_fixture":"preserve","vrTcgStats.v5":{"wins":999}}')`,[me]);
 const preserved=['auth.users','public.player_wallet','public.player_state','public.story_progress','public.pvp_ratings','public.matches','public.saves','public.story_gacha','public.gem_ledger','public.pvp_reward_claims','public.pvp_tier_claims','public.tower_progress','public.war_decks'];
 const snapshot=async(tables=preserved)=>Promise.all(tables.map(t=>q(`select to_jsonb(t) v from ${t} t order by to_jsonb(t)::text`)));
 const before=await snapshot(),shipped=await rd('supabase/production/01_install.sql');
 assert.equal(shipped,await buildProductionSql());
 if(config.productionSystemId){
  assert(shipped.includes("expected_system_id text := '"+config.productionSystemId+"'"));
  assert(!shipped.includes('PRODUCTION_SYSTEM_ID_REQUIRED'));
 }
 // The actual shipped production pin must reject the local DB; null must remain fail-closed too.
 for(const guarded of [shipped,await buildProductionSql({systemId:null})]){
  await assert.rejects(db.exec(guarded),/STOP: production system_identifier/);await db.exec('rollback');
  assert.equal(await val(`select to_regnamespace('vr_rollout_private')::text v`),null,'wrong/unbound DB must receive NO DDL');
 }
 const system=await val(`select system_identifier::text v from pg_control_system()`),sql=await buildProductionSql({systemId:system});
 const bad=await buildProductionSql({systemId:system==='1111111111111111111'?'2222222222222222222':'1111111111111111111'});
 await assert.rejects(db.exec(bad),/STOP: production system_identifier/);await db.exec('rollback');
 const failing=sql.replace('insert into vr_rollout_private.releases(',"raise exception 'fixture late failure'; insert into vr_rollout_private.releases(");
 await assert.rejects(db.exec(failing),/fixture late failure/);await db.exec('rollback');
 assert.deepEqual(await snapshot(),before,'late migration failure rolls back ALL legacy-row changes');
 assert.equal(await val(`select to_regclass('public.arcade_policy_v5')::text v`),null);
 assert.equal(await val(`select to_regnamespace('vr_rollout_private')::text v`),null);
 await assert.rejects(buildProductionSql({systemId:config.stagingSystemId}),/Invalid production system ID/);
 await db.exec(`create table public.pvp_policy_v3(singleton boolean primary key,engine_hash text,enabled boolean default true);insert into pvp_policy_v3 values(true,repeat('0',64),true)`);
 await assert.rejects(db.exec(sql),/unexpected existing pvp_policy_v3 engine/);await db.exec('rollback');
 assert.equal(await val('select engine_hash v from pvp_policy_v3'),'0'.repeat(64));
 await db.exec('drop table public.pvp_policy_v3');
 await db.exec(sql);
 await db.exec(await rd('supabase/production/00_preflight_readonly.sql'));
 assert.deepEqual(await q('select * from war_decks_v4'),await q('select * from war_decks'));
 assert.deepEqual(await val(`select cleared v from battle_legacy_access_v2 where user_id=$1`,[me]),{1:[1,2,3]});
 await db.exec(await rd('supabase/production/02_postflight_readonly.sql'));
 assert.deepEqual(await snapshot(),before,'ALL existing player balances/state/history/claims preserved exactly');
 for(const [table,hash]of Object.entries(versions))assert.equal(await val('select engine_hash v from '+table),hash);
 for(const name of ['guildbattle_test_clock_v4','guildbattle_test_refills_v4'])assert.equal(await val('select to_regclass($1)::text v',['public.'+name]),null);
 assert.equal(await val(`select _guildbattle_now_v4()=now() v`),true);
 const body=(await payload()).sql;assert(!/guildbattle_test_|sec4fixture|sec4_fixture/.test(body));
 assert.equal(await val(`select _guildbattle_used_v4($1,'raid')::int v`,[me]),0);
 await q(`insert into guild_raid_attempts(user_id,guild_id,week,day,kind,stage,difficulty,finished_at) select $1,99,_raid_week_v4(),_raid_day_v4(),'fight',1,'normal',now() from generate_series(1,3)`,[me]);
 assert.equal(await val(`select _guildbattle_used_v4($1,'raid')::int v`,[me]),3,'legacy same-day attempts count: no production refill/reset');
 const oldMatch=await val(`insert into war_matches(season,day,guild_a) values(_war_season_v4(),1,99) returning id v`),newMatch=await val(`insert into war_matches_v4(season,day,guild_a) values(_war_season_v4(),1,99) returning id v`);
 for(const [table,id,n]of [['war_attacks',oldMatch,2],['war_attacks_v4',newMatch,3]])await q(`insert into ${table}(match_id,user_id,side,target_slot,atk_deck,def_deck,seed,atk_snap,def_snap,atk_buff,def_buff,before,finished_at) select $1,$2,0,1,1,1,1,'[]','[]','{}','{}','{}',now() from generate_series(1,$3)`,[id,me,n]);
 assert.equal(await val(`select _guildbattle_used_v4($1,'war',$2)::int v`,[me,newMatch]),5,'production war budget sums old + verified attempts');
 for(const role of ['anon','authenticated','service_role'])assert.equal(await val(`select has_function_privilege($1,'public._guildbattle_used_v4(uuid,text,bigint)','execute') v`,[role]),false);

 assert.equal(await val(`select _player_unlock_level('chapter_3') v`),1,'story removes level walls');
 assert.equal(await val(`select _tower_min_level('wind') v`),25);
 assert.equal(await val(`select _tower_min_level('light') v`),40);
 await q(`select set_config('request.jwt.claim.sub',$1,false)`,[me]);
 await assert.rejects(q(`select _unlock_require('trade')`),/Lv15/);
 await q(`select set_config('request.jwt.claim.sub','',false)`);
 const all=(await q(`select schemaname||'.'||tablename v from pg_tables where schemaname in('public','vr_rollout_private') order by 1`)).map(x=>x.v);
 const allBefore=await snapshot(all);await db.exec(sql);assert.deepEqual(await snapshot(all),allBefore,'rerun is a complete data no-op');
 const ledgerHash=await val(`select bundle_hash v from vr_rollout_private.releases where release_id='20261108'`);
 await q(`update vr_rollout_private.releases set bundle_hash=repeat('0',64)`);
 await assert.rejects(db.exec(sql),/release content changed after installation/);await db.exec('rollback');
 await q(`update vr_rollout_private.releases set bundle_hash=$1`,[ledgerHash]);

 await q(`update arcade_policy_v5 set enabled=false`);await db.exec(sql);assert.equal(await val(`select enabled v from arcade_policy_v5`),false,'rerun preserves operator kill switch');await q(`update arcade_policy_v5 set enabled=true`);
 for(const role of ['anon','authenticated','service_role'])await as(me,()=>assert.rejects(q('select * from vr_rollout_private.releases'),/permission denied/),role);
 assert.equal(await val(`select count(*)::int v from pg_proc p where pronamespace='public'::regnamespace and p.prosecdef and left(proname,1)='_' and pg_get_function_result(oid)<>'trigger' and (has_function_privilege('anon',oid,'execute') or has_function_privilege('authenticated',oid,'execute'))`),0);
 await as(me,()=>assert.rejects(q(`insert into matches(user_id,result) values($1,'win')`,[me]),/permission denied/));
 // Production bundles differ ONLY by project pin/header/error label; engines remain byte-identical.
 const env={SUPABASE_URL:'https://'+config.productionProject+'.supabase.co',SUPABASE_PUBLISHABLE_KEYS:JSON.stringify({default:'sb_publishable_fixture'}),SUPABASE_SECRET_KEYS:JSON.stringify({default:'sb_secret_fixture'})};
 for(const name of config.edges){
  const source=await rd('supabase/production/functions/'+name+'/dashboard_single_file.ts');assert.equal(source,await productionBundle(name));assert(!/^import /m.test(source));
  const reverse=source.slice(source.indexOf('\n')+1).replaceAll(config.productionProject,'cuyqchmdcnsgzkwyclji').replaceAll('Production ','Staging ').replaceAll('production verifier unavailable','staging verifier unavailable').replaceAll('node tools/build_production_rollout.mjs','node tools/build_phase'+(name.includes('v3')?'3':name.includes('v4')?'4':'5')+'_dashboard.mjs');
  assert.equal(reverse,await rd('supabase/functions/'+name+'/dashboard_single_file.ts'));
  let calls=0;const fake=async(url)=>{calls++;assert(url.startsWith(env.SUPABASE_URL));if(url.endsWith('/auth/v1/user'))return Response.json({id:me});return Response.json({status:'settled',result:{verified:true}});};
  const h=handler(source,env,fake);assert.equal((await http(h,{op:'status',id:'1'})).status,200);assert.equal(calls,2);
  for(const host of ['https://cuyqchmdcnsgzkwyclji.supabase.co','https://unknown.invalid']){const before=calls;assert.equal((await http(handler(source,{...env,SUPABASE_URL:host},fake),{op:'status',id:'1'})).status,503);assert.equal(calls,before);}
 }
 // Real production arcade bundle -> real migrated production SQL -> strict replay -> once-only mission credit.
 const signatures={arcade_start_v5:['p_request','p_options','p_engine_hash'],arcade_engine_session_v5:['p_uid','p_id'],arcade_engine_settle_v5:['p_uid','p_id','p_engine_hash','p_submission','p_result']};
 const fetcher=async(url,opts)=>{assert(url.startsWith(env.SUPABASE_URL));if(url.endsWith('/auth/v1/user'))return Response.json(opts.headers.authorization==='Bearer fixture-me'?{id:me}:{error:'bad JWT'},{status:opts.headers.authorization==='Bearer fixture-me'?200:401});const name=url.split('/').at(-1),args=JSON.parse(opts.body),trusted=opts.headers.apikey==='sb_secret_fixture';assert(signatures[name]);if(trusted)assert.equal(opts.headers.authorization,undefined);const ps=signatures[name].map(k=>typeof args[k]==='object'&&args[k]!==null?JSON.stringify(args[k]):args[k]);try{return Response.json(await as(trusted?null:me,()=>val(`select ${name}(${ps.map((_,i)=>'$'+(i+1)).join(',')}) v`,ps),trusted?'service_role':'authenticated'));}catch(e){return Response.json({message:e.message},{status:400});}};
 const arcade=handler(await productionBundle('arcade-verify-v5'),env,fetcher),options={grades:null,turns:10,clearFirst:false};
 let r=await http(arcade,{op:'start',request:'aaaaaaaa-aaaa-4aaa-8aaa-000000000001',options,version:versions.arcade_policy_v5});assert.equal(r.status,200,JSON.stringify(r));const s=r.data,f=fixture(s.seed,options),finish={op:'finish',id:s.id,actions:f.actions};
 r=await http(arcade,finish);assert.equal(r.status,200,JSON.stringify(r));assert.equal(r.data.result.verified,true);const receipt=r.data;assert.deepEqual((await http(arcade,finish)).data,receipt);assert.equal(await val('select count(*)::int v from arcade_records_v5'),1);
 assert.equal(await as(me,()=>val(`select (x->>'prog')::int v from jsonb_array_elements(daily_status()->'missions') x where x->>'key'='arcade'`)),1);
 console.log('Production PASS: fail-closed pin, legacy upgrade/data preservation, atomic ledger/idempotency/ACL, no fixtures, levels, THREE bundle parity/project guards, actual arcade replay + once-only settlement');
}finally{await db.close();}
