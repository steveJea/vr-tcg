// Offline only: simulated production (main legacy + shipped 20261108) -> shipped 20261111 delta.
// No network, real keys, or real databases.
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFile} from 'node:fs/promises';
import {config,rd,baselineSql,baselineDb,targetDb,newSourceStatements,snapshotCatalog,snapshotData,diffCatalog,diffData,payload,wrapInstall,productionBundle,policyHashes,files} from './build_production_release.mjs';
const me='11111111-1111-4111-8111-111111111111',other='22222222-2222-4222-8222-222222222222';
// 1) Shipped files are exactly what the generator produces from this commit.
const {out,p}=await files();
for(const [name,content] of out)assert.equal(await rd(name),content,'stale '+name+' — run node tools/build_production_release.mjs');
const shipped=await rd(config.outDir+'/01_install.sql');
assert(shipped.includes("expected_system_id text := '"+config.productionSystemId+"'"));
assert(!/cuyqchmdcnsgzkwyclji|7703759698107299042'(?! or actual)|shop_buy|payment_create_v1|guildbattle_test_/.test(shipped.replace("expected_system_id='7703759698107299042'",'')),'no staging-only capability');
assert(!/story_complete_scene staging only|STOP: story ch16\/17 staging/.test(shipped),'staging guards removed from production story SQL');
assert(!/create or replace function public\._player_unlock_level\(/.test(shipped),'level policy of 20261108 is kept');
const base=await baselineSql(),db=await baselineDb(base);
const q=async(s,a=[])=>(await db.query(s,a)).rows,val=async(s,a=[])=>(await q(s,a))[0]?.v;
const as=async(u,fn)=>{await q(`select set_config('request.jwt.claim.sub',$1,false)`,[u]);await db.exec('set role authenticated');try{return await fn();}finally{await db.exec('reset role');}};
try{
 // Existing players (balances, story, history) must be untouched.
 await q(`insert into auth.users(id,email) values($1,'one@example.invalid'),($2,'two@example.invalid')`,[me,other]);
 await q(`insert into player_wallet(user_id,gold,gem_free,gem_paid) values($1,12345,234,345),($2,999,87,65)`,[me,other]);
 await q(`insert into player_state(user_id,level) values($1,30),($2,80)`,[me,other]);
 await q(`insert into story_progress(user_id,data) values($1,$2)`,[me,JSON.stringify({owned:[],starter:'10111',cleared:{15:[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16]},stars:{}})]);
 await q(`insert into pvp_ratings_v3(user_id,league,mode,season,rating,wins,games_verified) values($1,'open','1v1',_pvp_season()-7,1777,9,9)`,[me]);
 const preserved=['auth.users','public.player_wallet','public.player_state','public.story_progress','public.pvp_ratings_v3','public.saves','public.matches','public.story_gacha','public.gem_ledger'];
 const snap=async()=>Promise.all(preserved.map(t=>q(`select to_jsonb(t) v from ${t} t order by to_jsonb(t)::text`)));
 const before=await snap();
 // 2) Fail closed: the real pin refuses this DB, with NO DDL.
 await assert.rejects(db.exec(shipped),/STOP: production system_identifier/);await db.exec('rollback');
 assert.equal(await val(`select to_regclass('public.battle_replay_policy_v6')::text v`),null);
 assert.throws(()=>wrapInstall(p,{systemId:config.stagingSystemId}),/Invalid production system ID/);
 const id=await val(`select system_identifier::text v from pg_control_system()`),sql=wrapInstall(p,{systemId:id});
 // 3) Prerequisite + live-engine checks.
 await q(`update vr_rollout_private.releases set release_id='x20261108' where release_id='20261108'`);
 await assert.rejects(db.exec(sql),/release 20261108 is not installed/);await db.exec('rollback');
 await q(`update vr_rollout_private.releases set release_id='20261108' where release_id='x20261108'`);
 await q(`update pvp_policy_v3 set engine_hash=repeat('0',64)`);
 await assert.rejects(db.exec(sql),/unexpected existing pvp_policy_v3/);await db.exec('rollback');
 await q(`update pvp_policy_v3 set engine_hash=$1`,[config.expectedExisting.pvp_policy_v3]);
 // Late failure rolls everything back.
 await assert.rejects(db.exec(sql.replace("insert into vr_rollout_private.releases(","raise exception 'fixture late failure'; insert into vr_rollout_private.releases(")),/fixture late failure/);await db.exec('rollback');
 assert.equal(await val(`select to_regclass('public.battle_replay_policy_v7')::text v`),null);
 assert.deepEqual(await snap(),before);
 // 4) Preflight is read-only and reports zero drift on an untouched main baseline.
 const pre=(await db.exec(await rd(config.outDir+'/00_preflight_readonly.sql')));
 const drift=pre.at(-1).rows[0];assert.equal(Number(drift.differs_from_main_baseline),0,'preflight drift: '+drift.differs_list);
 assert.equal(pre[3].rows[0].ok,true);assert.equal(Number(pre.find(r=>r.fields.some(f=>f.name==='ch15_phases')).rows[0].ch15_phases)>0,true);
 // 5) Install.
 await db.exec(sql);
 assert.deepEqual(await snap(),before,'existing player data preserved exactly');
 // Catalog + config parity with the reviewed staging target.
 const B=await targetDb(await newSourceStatements());
 try{
  const d=await diffCatalog(await snapshotCatalog(db),await snapshotCatalog(B));
  assert.deepEqual([d.fnDefs.map(f=>f.sig),d.acls,d.structural],[[],[],[]],'function/ACL/structure parity');
  const dd=diffData(await snapshotData(db),await snapshotData(B));
  const userTables=new Set(preserved.map(t=>t.replace(/^public\./,'')));
  assert.deepEqual(dd.upserts.filter(u=>!userTables.has(u.t)&&!/vr_rollout/.test(u.t)).map(u=>u.t),[],'config row parity');
 }finally{await B.close();}
 const post=await db.exec(await rd(config.outDir+'/02_postflight_readonly.sql'));
 for(const r of post.slice(1))for(const row of r.rows)for(const [k,v] of Object.entries(row)){if(typeof v==='boolean')assert.equal(v,true,'postflight '+k);if(k==='mismatch_must_be_0')assert.equal(Number(v),0);}
 const pol=await policyHashes();
 for(const [t,h] of Object.entries(pol))assert.equal(await val(`select engine_hash v from ${t}`),h);
 assert.equal(await val(`select enabled v from battle_replay_policy_v6`),false);assert.equal(await val(`select enabled v from battle_replay_policy_v7`),false);
 assert.equal(await val(`select _player_unlock_level('chapter_16') v`),1);assert.equal(await val(`select _player_unlock_level('skill') v`),13);
 assert.equal(await val(`select prosrc like '%pg_control_system%' v from pg_proc where proname='story_complete_scene'`),false);
 // Rating carry-over (sheet 33) and scene completion actually work on the migrated DB.
 const info=await as(me,()=>val(`select pvp_rankings('open','1v1') v`));assert(JSON.stringify(info).includes('1777'),'PvP rating carries over');
 await q(`update story_progress set data=jsonb_set(data,'{cleared,16}',to_jsonb(array[1,2,3,4,5,6,7,8,9,10,11])) where user_id=$1`,[me]);
 const scene=await as(me,()=>val(`select story_complete_scene(16,12) v`));assert.equal(scene.first,true);assert.equal(scene.points,3);
 // 6) Rerun is a complete no-op; changed content refused; operator switches preserved.
 await q(`update arcade_policy_v5 set enabled=false`);
 const all=(await q(`select schemaname||'.'||tablename v from pg_tables where schemaname in('public','vr_rollout_private') order by 1`)).map(x=>x.v);
 const snapAll=async()=>Promise.all(all.map(t=>q(`select to_jsonb(t) v from ${t} t order by to_jsonb(t)::text`)));
 const s1=await snapAll();await db.exec(sql);assert.deepEqual(await snapAll(),s1,'rerun is a data no-op');
 assert.equal(await val(`select enabled v from arcade_policy_v5`),false,'kill switch preserved');
 const h=await val(`select bundle_hash v from vr_rollout_private.releases where release_id=$1`,[config.release]);
 await q(`update vr_rollout_private.releases set bundle_hash=repeat('0',64) where release_id=$1`,[config.release]);
 await assert.rejects(db.exec(sql),/release content changed/);await db.exec('rollback');
 await q(`update vr_rollout_private.releases set bundle_hash=$1 where release_id=$2`,[h,config.release]);
 assert.equal(await val(`select count(*)::int v from pg_proc p where pronamespace='public'::regnamespace and p.prosecdef and left(proname,1)='_' and pg_get_function_result(oid)<>'trigger' and (has_function_privilege('anon',oid,'execute') or has_function_privilege('authenticated',oid,'execute'))`),0);
}finally{await db.close();}
// 7) Five production Edge bundles: only the project pin/labels differ; staging/unknown projects get 503 before any call.
function handler(source,env,fetcher){let captured;const context=vm.createContext({Response,Request,TextDecoder,TextEncoder,Uint8Array,structuredClone,crypto,console:{info(){},warn(){},error(){}},fetch:fetcher,Deno:{env:{toObject:()=>({...env})},serve:h=>{captured=h;}}});new vm.Script(source).runInContext(context);assert.equal(typeof captured,'function');return captured;}
const env={SUPABASE_URL:'https://'+config.productionProject+'.supabase.co',SUPABASE_PUBLISHABLE_KEYS:JSON.stringify({default:'sb_publishable_fixture'}),SUPABASE_SECRET_KEYS:JSON.stringify({default:'sb_secret_fixture'})};
for(const name of config.edges){
 const source=await rd(config.outDir+'/functions/'+name+'/dashboard_single_file.ts');assert.equal(source,await productionBundle(name));assert(!/^import /m.test(source));
 const n=name.match(/v(\d)$/)[1];
 const reverse=source.slice(source.indexOf('\n')+1).replaceAll(config.productionProject,'cuyqchmdcnsgzkwyclji').replaceAll('Production ','Staging ').replaceAll('production verifier unavailable','staging verifier unavailable').replaceAll('node tools/build_production_release.mjs','node tools/build_phase'+n+'_dashboard.mjs');
 assert.equal(reverse,await rd('supabase/functions/'+name+'/dashboard_single_file.ts'),name+' engine bytes identical to staging');
 let calls=0;const fake=async url=>{calls++;return Response.json({});};
 for(const host of ['https://cuyqchmdcnsgzkwyclji.supabase.co','https://unknown.invalid']){
  const h=handler(source,{...env,SUPABASE_URL:host},fake);
  const r=await h(new Request('https://example.invalid',{method:'POST',headers:{'content-type':'application/json',authorization:'Bearer x'},body:JSON.stringify({op:'status',id:'1'})}));
  assert.equal(r.status,503,name+' must refuse '+host);
 }
 assert.equal(calls,0);
}
console.log(`Production ${config.release} PASS: pinned/fail-closed, needs ${config.previousRelease}, engine pre-check, atomic, preflight drift 0, player data preserved, catalog+config parity with staging target, postflight all true, v6/v7 OFF, level policy kept, rating carry-over + scene clear work, idempotent rerun, kill switch kept, ${config.edges.length} Edge bundles byte-parity + project guard`);
