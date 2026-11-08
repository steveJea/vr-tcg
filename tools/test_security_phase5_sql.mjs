// No network/keys. PGlite SQL + the REAL trusted handler/engine behind a simulated Auth/REST boundary.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { PGlite } from '@electric-sql/pglite';
import { buildSql, INSTALL_ACK } from './build_staging_sql.mjs';
import { ENGINE_VERSION, verifyBattle } from '../supabase/functions/_shared/arcade-engine-v5.mjs';
import { dashboardHandler } from './load_phase5_dashboard.mjs';
import { createHandler } from '../supabase/functions/arcade-verify-v5/handler.mjs';
import { setSkillData, skillsOf } from '../js/skills.js';
import { parseCSV, setCardPool } from '../js/rules.js';
import {fixture} from './phase5_fixture.mjs';
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
let restCalls=0,authCalls=0;
const signatures={arcade_start_v5:['p_request','p_options','p_engine_hash'],arcade_engine_session_v5:['p_uid','p_id'],arcade_engine_settle_v5:['p_uid','p_id','p_engine_hash','p_submission','p_result']};
const fetcher=async(url,opts)=>{
 assert(url.startsWith(env.SUPABASE_URL));
 if(url.endsWith('/auth/v1/user')){authCalls++;const id=opts.headers.authorization==='Bearer fixture-me'?me:opts.headers.authorization==='Bearer fixture-other'?other:null;return Response.json(id?{id}:{error:'invalid JWT'},{status:id?200:401});}
 restCalls++;const name=url.split('/').at(-1),args=JSON.parse(opts.body);assert(signatures[name]);const trusted=opts.headers.apikey==='sb_secret_fixture';
 if(trusted)assert.equal(opts.headers.authorization,undefined);else assert.equal(name,'arcade_start_v5');
 const uid=opts.headers.authorization==='Bearer fixture-other'?other:me,ps=signatures[name].map(k=>typeof args[k]==='object'&&args[k]!==null?JSON.stringify(args[k]):args[k]);
 try{return Response.json(await as(trusted?null:uid,()=>val(`select public.${name}(${ps.map((_,i)=>'$'+(i+1)).join(',')}) v`,ps),trusted?'service_role':'authenticated'));}
 catch(e){if(process.env.DEBUG_PHASE5)console.error(name,e.message,e.where||'');return Response.json({message:e.message},{status:400});}
};
const factory=process.argv.includes('--dashboard')?dashboardHandler:createHandler,handler=factory(env,fetcher);
const http=async(body,token='fixture-me',h=handler)=>{const r=await h(new Request('https://example.invalid/arcade-verify-v5',{method:'POST',headers:{'content-type':'application/json',authorization:'Bearer '+token},body:JSON.stringify(body)}));const data=await r.json();assert.match(data.trace||'',/^[a-f0-9-]{36}$/);delete data.trace;return{status:r.status,data};};
try {
 await db.exec(`create role anon; create role authenticated; create role service_role; create schema auth;
 create table auth.users(id uuid primary key,email text,raw_user_meta_data jsonb default '{}',raw_app_meta_data jsonb default '{}',created_at timestamptz default now(),last_sign_in_at timestamptz,email_confirmed_at timestamptz);
 create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
 create function auth.jwt() returns jsonb language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb $$;
 grant usage on schema auth,public to anon,authenticated,service_role;
 alter default privileges in schema public grant all on tables to anon,authenticated;
 alter default privileges in schema public grant all on sequences to anon,authenticated;
 alter default privileges in schema public grant execute on functions to anon,authenticated,service_role;`);

 let base=await buildSql();const at=base.indexOf('-- ===== SOURCE: security_phase5_arcade.sql =====');assert(at>0);base=base.slice(0,at)+base.slice(base.indexOf('-- 공개 게임 설정만 명시적으로 조회 허용',at));
 await db.exec(base.replace(`confirmed_ref text := '${INSTALL_ACK}'`,"confirmed_ref text := 'abcdefghijklmnopqrst'"));
 const system=await val('select system_identifier::text v from pg_control_system()'),migration=await rd('supabase/security_phase5_arcade.sql');
 await assert.rejects(db.exec(migration),/STOP: phase5 only/);await db.exec('rollback');
 // Simulate older column-level grants and raw self-reported victories before the migration.
 await q(`insert into auth.users(id,email) values($1,'one@example.invalid'),($2,'two@example.invalid')`,[me,other]);
 await db.exec('grant insert(result) on public.matches to authenticated');
 await rpc(`insert into matches(user_id,result) values($1,'win')`,[me]);
 await q(`insert into player_wallet(user_id,gold,gem_free) values($1,0,0),($2,0,0) on conflict(user_id) do update set gold=0,gem_free=0`,[me,other]);
 const sql=migration.replaceAll("'7703759698107299042'",`'${system}'`);await db.exec(sql);await db.exec(sql);
 await reject(`insert into public.matches(user_id,result) values($1,'win')`,[me]);
 await reject(`update public.matches set result='win' where user_id=$1`,[me]);
 assert.equal((await rpc('select arcade_record_v5() v')).wins,0);
 assert.equal((await q('select * from rankings_all')).length,0,'legacy forged wins excluded, not deleted');
 assert.equal(await val('select count(*)::int v from matches'),1);
 for(const table of ['arcade_sessions_v5','arcade_records_v5','arcade_policy_v5'])for(const role of ['anon','authenticated'])await as(me,()=>assert.rejects(q('select * from '+table),/permission denied/),role);
 await reject('select public.arcade_engine_session_v5($1,1)',[me]);
 await reject('select public.arcade_engine_settle_v5($1,1,$2,$3,$4)',[me,ENGINE_VERSION,'{}','{}']);
 const opts={grades:null,turns:10,clearFirst:false},start={op:'start',request:req(1),options:opts,version:ENGINE_VERSION};
 assert.equal((await http(start,'invalid')).status,401);
 assert.equal((await http({...start,seed:1})).status,400);
 assert.equal((await http({...start,version:'0'.repeat(64)})).status,409);
 let r=await http(start);assert.equal(r.status,200,JSON.stringify(r));const session=r.data;
 assert.deepEqual((await http(start)).data,session,'lost start response is idempotent');
 assert.equal((await http({...start,options:{...opts,turns:40}})).status,409);
 assert.equal((await http({...start,request:req(2)})).status,409,'cannot reroll active session');
 assert.equal((await http({op:'status',id:session.id},'fixture-other')).status,409);
 assert.equal((await http({op:'finish',id:session.id,actions:[]})).status,422);
 assert.equal((await http({op:'finish',id:session.id,actions:null})).status,400);
 assert.equal((await http({op:'finish',id:session.id,actions:[{k:'end',win:true}]})).status,400);
 const f=fixture(session.seed,opts),finish={op:'finish',id:session.id,actions:f.actions};r=await http(finish);assert.equal(r.status,200,JSON.stringify(r));assert.equal(r.data.result.result,f.result.result);
 const receipt=r.data;assert.equal(receipt.result.verified,true);assert.deepEqual((await http(finish)).data,receipt);
 assert.equal(await val('select count(*)::int v from arcade_records_v5'),1);
 assert.equal((await http({...finish,actions:[...f.actions,{k:'end'}]})).status,409);
 assert.equal((await rpc(`select daily_status() v`)).missions.find(x=>x.key==='arcade').prog,1);
 assert.equal((await rpc(`select weekly_status() v`)).missions.find(x=>x.key==='arcade').prog,1);
 assert.equal((await rpc(`select daily_status() v`)).all.held,false);
 const before=await val('select gold::int v from player_wallet where user_id=$1',[me]);await rpc(`select daily_claim('arcade') v`);assert.equal(await val('select gold::int v from player_wallet where user_id=$1',[me]),before+1000);
 await as(me,()=>assert.rejects(q(`select daily_claim('arcade')`),/already claimed/));
 await as(me,()=>assert.rejects(q(`select daily_claim('all')`),/not done/));
 const stats=await rpc('select arcade_record_v5() v');assert.equal(stats.wins+stats.losses+stats.draws,1);
 assert.equal(await val(`select _ach_prog($1,'arcade_wins') v`,[me]),f.result.result==='win'?1:0);
 assert.equal(await val(`select _ach_prog($1,'skill_uses') v`,[me]),f.result.skills);
 // Server-trusted fixtures fill remaining daily/weekly goals; browser attempts to write these are denied.
 for(const mode of ['story','tower'])await q(`with sessions as (insert into battle_sessions_v2(user_id,request_id,mode,target,party,seed,snapshot,status) select $1,gen_random_uuid(),$2,'fixture','[]',1,'{}','settled' from generate_series(1,50) returning id,user_id,mode) insert into battle_events_v2(session_id,user_id,mode,win,skills,day,week) select id,user_id,mode,true,100,_gem_day(),_weekly_week() from sessions`,[me,mode]);
 await rpc(`select daily_claim('all') v`);await as(me,()=>assert.rejects(q(`select daily_claim('all')`),/already claimed/));
 await q(`update arcade_sessions_v5 set created_at=created_at-interval '3 seconds' where user_id=$1`,[me]);
 r=await http({...start,request:req(3)});assert.equal(r.status,200);const giveup=r.data;
 r=await http({op:'forfeit',id:giveup.id});assert.equal(r.status,200);assert.equal(r.data.result.result,'lose');assert.equal(r.data.result.verified,false);
 assert.equal((await rpc(`select daily_status() v`)).missions.find(x=>x.key==='arcade').prog,1,'forfeits grant no progress');
 // Reopen weekly all-complete only after seven actual engine-verified receipts.
 for(let n=10;n<16;n++){
  await q(`update arcade_sessions_v5 set created_at=created_at-interval '3 seconds' where user_id=$1`,[me]);
  const t=await http({...start,request:req(n)});assert.equal(t.status,200);const f=fixture(t.data.seed,opts);
  assert.equal((await http({op:'finish',id:t.data.id,actions:f.actions})).status,200);
 }
 assert.equal((await rpc(`select weekly_status() v`)).missions.find(x=>x.key==='arcade').prog,7);
 await rpc(`select weekly_claim('arcade') v`);await rpc(`select weekly_claim('all') v`);
 await as(me,()=>assert.rejects(q(`select weekly_claim('all')`),/already claimed/));
 // Untrusted legacy JSON/counters cannot change official records or progress.
 const official=await rpc('select arcade_record_v5() v');
 await rpc(`insert into public.saves(user_id,data) values($1,'{"vrTcgStats.v5":{"wins":999999},"arcade_win":999999}') on conflict(user_id) do update set data=excluded.data`,[me]);
 await reject(`select ach_track('arcade_win',999999)`,[],/reward verification pending/);
 assert.deepEqual(await rpc('select arcade_record_v5() v'),official);
 // Expired valid replay is a server-owned, unrewarded loss. No backdated completion.
 const t=await http({...start,request:req(30)},'fixture-other');assert.equal(t.status,200);const expiredFixture=fixture(t.data.seed,opts);
 await q(`update arcade_sessions_v5 set expires_at=now()-interval '1 second' where id=$1`,[t.data.id]);
 const expired=await http({op:'finish',id:t.data.id,actions:expiredFixture.actions},'fixture-other');assert.equal(expired.status,200);assert.equal(expired.data.result.verified,false);assert.equal(expired.data.result.result,'lose');
 assert.equal((await rpc('select daily_status() v',[],other)).missions.find(x=>x.key==='arcade').prog,0);
 // The server—not client clocks—bounds start frequency and total daily issuance.
 await q(`insert into arcade_sessions_v5(user_id,request,seed,options,engine_hash,status,created_at) select $1,gen_random_uuid(),1,$2,$3,'settled',now()-interval '3 seconds' from generate_series(1,500)`,[other,JSON.stringify(opts),ENGINE_VERSION]);
 assert.equal((await http({...start,request:req(31)},'fixture-other')).data.error,'rate limited');
 await q(`update arcade_policy_v5 set enabled=false`);assert.equal((await http({...start,request:req(4)})).status,409);await db.exec(sql);assert.equal(await val('select enabled v from arcade_policy_v5'),false,'rerun never re-enables the kill switch');
 assert.equal((await rpc('select daily_status() v')).all.held,true);
 await as(me,()=>assert.rejects(q(`select weekly_claim('all')`),/reward verification pending/));
 assert.deepEqual((await q(`select proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosecdef and left(p.proname,1)='_' and pg_get_function_result(p.oid)<>'trigger' and (has_function_privilege('anon',p.oid,'execute') or has_function_privilege('authenticated',p.oid,'execute'))`)),[]);
 const calls=restCalls;assert.equal((await http(start,'bad')).status,401);assert.equal(restCalls,calls);
 assert.equal((await http(start,'fixture-me',factory({...env,SUPABASE_URL:'https://htarwisgkkphutxxnuak.supabase.co'},fetcher))).status,503);
 console.log('phase5 SQL + '+(process.argv.includes('--dashboard')?'Dashboard':'modular')+' handler: ACL, legacy exclusion, strict replay, ownership, retries/conflicts, missions/all, kill switch OK');
}finally{await db.close();}
