// Production release 20261111: delta for the EXISTING production DB (main 12c5e00 + release 20261108).
// Offline only: builds two PGlite DBs (production baseline vs reviewed staging target), diffs the
// catalog and config rows, emits the final-state delta, re-applies it and proves parity. Never connects
// to a real database, deploys, or reads credentials.
import {readFile,writeFile,mkdir,rm,symlink,mkdtemp} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {execFileSync} from 'node:child_process';
import os from 'node:os';
import path from 'node:path';
import {PGlite} from '@electric-sql/pglite';
import {splitStatements,stripLeadingComments} from './sql_statements.mjs';
import {buildSql,INSTALL_ACK} from './build_staging_sql.mjs';
import {productionStatements} from './build_production_rollout.mjs';
export const root=new URL('../',import.meta.url);
const rootDir=fileURLToPath(root);
export const config=JSON.parse(await readFile(new URL('tools/production/release-20261111.json',root),'utf8'));
export const rd=p=>readFile(new URL(p,root),'utf8');
const STAGING_ID=config.stagingSystemId;
export const PRELUDE=`create role anon;create role authenticated;create role service_role;create schema auth;
 create table auth.users(id uuid primary key,email text,raw_user_meta_data jsonb default '{}',raw_app_meta_data jsonb default '{}',created_at timestamptz default now(),last_sign_in_at timestamptz,email_confirmed_at timestamptz);
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
 grant usage on schema auth,public to anon,authenticated,service_role;
 alter default privileges in schema public grant all on tables to anon,authenticated;
 alter default privileges in schema public grant all on sequences to anon,authenticated;
 alter default privileges in schema public grant execute on functions to anon,authenticated,service_role;`;

// ---- Reviewed source transforms (each must match exactly once) ----
const once=(s,a,b,label)=>{const n=s.split(a).length-1;if(n!==1)throw Error(label+' transform drift ('+n+')');return s.replace(a,b);};
export async function newSourceStatements(){
 const out=[];
 for(const name of config.newSources){
  const sql=await rd('supabase/'+name);let kept=[],dropped=[];
  for(let st of splitStatements(sql)){
   const s=stripLeadingComments(st).trim();
   if(!s||/^(begin|commit);$/i.test(s)||/^notify pgrst/i.test(s))continue;
   if(/^do \$(phase6|phase7)_staging_guard\$/.test(s)){dropped.push('cluster guard');continue;}
   if(name==='story_ch16_17.sql'){
    if(/^do \$\$\s*begin\s*if \(select system_identifier::text from pg_catalog\.pg_control_system\(\)\) is distinct from '7703759698107299042' then\s*raise exception 'STOP: story ch16\/17 staging[^']*';\s*end if;\s*end \$\$;$/.test(s)){dropped.push('cluster guard');continue;}
    // Production keeps release 20261108 level policy (story walls removed, skill 13 / equip 3); the ch16/17 file must never override it.
    if(s.startsWith('create or replace function public._player_unlock_level('))throw Error('story_ch16_17.sql must not redefine _player_unlock_level (2026-11-08 level policy)');
    // Staging-only engine hash rotation 3f9d..->0178..; production installs phase7 with 0178.. directly.
    if(s.includes("old_7 text := '3f9d8fd104b5ea50305841c1516780d03b1be6bdf1996d37a2d203ff6a5fbf9c'")){dropped.push('staging v7 hash rotation');continue;}
    if(s.startsWith('create or replace function public.story_complete_scene(')){
     st=once(st,"  if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7703759698107299042' then\n    raise exception 'STOP: story_complete_scene staging only';\n  end if;\n",'','story_complete_scene guard');
    }
   }
   kept.push(stripLeadingComments(st).trim());
  }
  const expectDrop={ 'security_phase6_story_tower.sql':1,'security_phase7_direct_replay.sql':1,'story_ch16_17.sql':2 }[name];
  if(dropped.length!==expectDrop)throw Error(name+' drop drift: '+dropped.join(', '));
  out.push({name,statements:kept,dropped});
 }
 return out;
}

// ---- Databases ----
async function freshDb(){const db=new PGlite();await db.exec(PRELUDE);return db;}
export async function withBaselineTree(fn){
 const dir=await mkdtemp(path.join(os.tmpdir(),'vr-prod-base-'));
 execFileSync('git',['worktree','add','-q','--detach',dir,config.baselineCommit],{cwd:rootDir});
 try{await symlink(path.join(rootDir,'node_modules'),path.join(dir,'node_modules'));return await fn(dir);}
 finally{execFileSync('git',['worktree','remove','--force',dir],{cwd:rootDir});await rm(dir,{recursive:true,force:true});}
}
// Production today = main legacy installer (all non-security SQL at main) + shipped release 20261108.
export async function baselineSql(){
 return withBaselineTree(async dir=>{
  const mod=await import(pathToFileURL(path.join(dir,'tools/build_staging_sql.mjs')).href);
  const full=await mod.buildSql(),at=full.indexOf('-- ===== SOURCE: security_phase1_rewards.sql =====');
  if(at<0)throw Error('baseline phase1 marker missing');
  const legacy=full.slice(0,at)+full.slice(full.indexOf('-- 공개 게임 설정만 명시적으로 조회 허용',at));
  return {legacy:legacy.replace(`confirmed_ref text := '${mod.INSTALL_ACK}'`,`confirmed_ref text := 'abcdefghijklmnopqrst'`),release1108:await readFile(path.join(dir,'supabase/production/01_install.sql'),'utf8')};
 });
}
export async function baselineDb(base){
 const db=await freshDb();await db.exec(base.legacy);
 const id=(await db.query(`select system_identifier::text v from pg_control_system()`)).rows[0].v;
 await db.exec(base.release1108.replace("expected_system_id text := '7692130048193495360'","expected_system_id text := '"+id+"'"));
 return db;
}
export async function targetDb(news){
 const db=await freshDb();
 await db.exec((await buildSql()).replace(`confirmed_ref text := '${INSTALL_ACK}'`,`confirmed_ref text := 'abcdefghijklmnopqrst'`));
 for(const src of news)if(src.name!=='security_phase6_story_tower.sql')await db.exec(src.statements.join('\n'));
 // Production phase4 (same reviewed transform as release 20261108): real clock/budget, no staging test clock.
 const p4=productionStatements('security_phase4_raid_guildwar.sql',await rd('supabase/security_phase4_raid_guildwar.sql')).statements
  .filter(s=>/^create or replace function public\.(_guildbattle_now_v4|_guildbattle_used_v4|_war_auto_enter_v4)\(/.test(s));
 if(p4.length!==3)throw Error('phase4 production overlay drift');
 const acl=(await db.query(`select p.oid::regprocedure::text sig from pg_proc p where p.proname in('_guildbattle_now_v4','_guildbattle_used_v4','_war_auto_enter_v4') and p.pronamespace='public'::regnamespace`)).rows;
 await db.exec('set check_function_bodies=off;'+p4.join('\n')+';reset check_function_bodies;drop table public.guildbattle_test_refills_v4, public.guildbattle_test_clock_v4;');
 if(acl.length!==3)throw Error('phase4 overlay signature drift');
 return db;
}

// ---- Catalog / data snapshot ----
const rows=async(db,sql)=>(await db.query(sql)).rows;
export async function snapshotCatalog(db){
 const fns=await rows(db,`select p.oid::regprocedure::text sig,pg_get_functiondef(p.oid) def,md5(p.prosrc) src,
   coalesce((select string_agg(case when a.grantee=0 then 'public' else a.grantee::regrole::text end,',' order by 1) from aclexplode(coalesce(p.proacl,acldefault('f'::"char",p.proowner))) a where a.privilege_type='EXECUTE' and (a.grantee=0 or a.grantee::regrole::text in('anon','authenticated','service_role'))),'') acl
   from pg_proc p where p.pronamespace='public'::regnamespace and p.prokind in('f','p') order by 1`);
 const struct=(await rows(db,`
  select 'col '||table_name||'.'||column_name||' '||data_type||' '||coalesce(column_default,'')||' '||is_nullable v from information_schema.columns where table_schema='public'
  union all select 'con '||conrelid::regclass::text||' '||conname||' '||pg_get_constraintdef(oid) from pg_constraint where connamespace='public'::regnamespace
  union all select 'idx '||indexdef from pg_indexes where schemaname='public'
  union all select 'pol '||tablename||' '||policyname||' '||cmd::text||' '||array_to_string(roles,',')||' '||coalesce(qual,'')||' '||coalesce(with_check,'') from pg_policies where schemaname='public'
  union all select 'trg '||pg_get_triggerdef(t.oid) from pg_trigger t join pg_class c on c.oid=t.tgrelid where c.relnamespace='public'::regnamespace and not t.tgisinternal
  union all select 'rel '||c.relkind::text||' '||c.relname||' rls='||c.relrowsecurity||' acl='||coalesce((select string_agg(case when a.grantee=0 then 'public' else a.grantee::regrole::text end||':'||a.privilege_type,',' order by 1) from aclexplode(coalesce(c.relacl,acldefault((case when c.relkind='S' then 's' else 'r' end)::"char",c.relowner))) a where a.grantee=0 or a.grantee::regrole::text in('anon','authenticated','service_role')),'') from pg_class c where c.relnamespace='public'::regnamespace and c.relkind in('r','v','m','S','p')
  union all select 'view '||viewname||' '||definition from pg_views where schemaname='public'
  union all select 'type '||t.typname||' '||t.typtype::text from pg_type t where t.typnamespace='public'::regnamespace and t.typtype in('e','d','c') and not exists(select 1 from pg_class c where c.reltype=t.oid and c.relkind<>'c')
 `)).map(r=>r.v).sort();
 return {fns:new Map(fns.map(f=>[f.sig,f])),struct};
}
const VOLATILE=/now\(\)|clock_timestamp|current_timestamp|statement_timestamp|transaction_timestamp|gen_random_uuid|random\(\)/i;
export async function snapshotData(db){
 const tabs=await rows(db,`select c.oid::regclass::text t,c.relname n,
   (select array_agg(a.attname order by k.ord) from pg_index i cross join lateral unnest(i.indkey) with ordinality k(attnum,ord) join pg_attribute a on a.attrelid=i.indrelid and a.attnum=k.attnum where i.indrelid=c.oid and i.indisprimary) pk,
   (select array_agg(column_name::text) from information_schema.columns where table_schema='public' and table_name=c.relname and column_default ~* '${VOLATILE.source.replace(/\\/g,'\\\\').replace(/'/g,"''")}') vol
   from pg_class c where c.relnamespace='public'::regnamespace and c.relkind in('r','p') order by 1`);
 // Foreign-key order: parents first so new config rows insert cleanly.
 const fk=await rows(db,`select conrelid::regclass::text c,confrelid::regclass::text p from pg_constraint where contype='f' and connamespace='public'::regnamespace and confrelid<>conrelid`);
 const order=[],seen=new Set(),visit=t=>{if(seen.has(t))return;seen.add(t);for(const e of fk)if(e.c===t)visit(e.p);order.push(t);};
 for(const t of tabs)visit(t.t);
 tabs.sort((a,b)=>order.indexOf(a.t)-order.indexOf(b.t));
 const out=new Map();
 for(const t of tabs){
  const data=(await rows(db,`select to_jsonb(x) j from ${t.t} x`)).map(r=>r.j);
  out.set(t.t,{pk:t.pk,vol:t.vol||[],data});
 }
 return out;
}
const stable=v=>JSON.stringify(v,(k,x)=>x&&typeof x==='object'&&!Array.isArray(x)?Object.fromEntries(Object.keys(x).sort().map(k=>[k,x[k]])):x);
const lit=s=>"'"+String(s).replaceAll("'","''")+"'";
export function diffData(A,B){
 const upserts=[],problems=[];
 for(const [t,b] of B){
  const a=A.get(t);if(!a){if(b.data.length)problems.push('new table rows '+t);continue;}
  // Install/build timestamps are not configuration: never copy or compare them.
  const strip=r=>{const o={...r};for(const c of [...b.vol,'installed_at','created_at','updated_at'])delete o[c];return o;};
  if(!b.pk){
   const as=a.data.map(r=>stable(strip(r))).sort(),bs=b.data.map(r=>stable(strip(r))).sort();
   if(stable(as)!==stable(bs))problems.push('no-PK table differs '+t);continue;
  }
  const key=r=>stable(b.pk.map(k=>r[k]));
  const am=new Map(a.data.map(r=>[key(r),strip(r)]));
  const bm=new Map(b.data.map(r=>[key(r),strip(r)]));
  for(const [k,r] of [...bm].sort((x,y)=>x[0]<y[0]?-1:x[0]>y[0]?1:0)){
   const old=am.get(k);
   if(!old){upserts.push({t,pk:b.pk,row:r,cols:null});continue;}
   const cols=Object.keys(r).filter(c=>stable(r[c])!==stable(old[c]));
   if(cols.length)upserts.push({t,pk:b.pk,row:r,cols});
  }
  for(const k of am.keys())if(!bm.has(k))problems.push('row removed in target '+t+' '+k);
 }
 return {upserts,problems};
}
export function upsertSql(u){
 const json=lit(stable(u.row));
 if(!u.cols)return `insert into ${u.t} select * from jsonb_populate_record(null::${u.t}, ${json}::jsonb) on conflict (${u.pk.join(',')}) do nothing;`;
 // Only the reviewed changed columns of an existing config row: operator switches (enabled etc.) stay as they are.
 return `update ${u.t} set ${u.cols.map(c=>c+'=r.'+c).join(', ')} from jsonb_populate_record(null::${u.t}, ${json}::jsonb) r where ${u.pk.map(k=>u.t+'.'+k+'=r.'+k).join(' and ')};`;
}
export function aclSql(sig,acl){
 const g=acl?acl.split(','):[];
 return `revoke all on function ${sig} from public, anon, authenticated, service_role;`+(g.length?`\ngrant execute on function ${sig} to ${g.join(', ')};`:'');
}
export async function diffCatalog(a,b){
 const fnDefs=[],acls=[],orphans=[];
 for(const [sig,f] of b.fns){
  const o=a.fns.get(sig);
  if(!o||o.def!==f.def)fnDefs.push(f);
  if(!o||o.def!==f.def||o.acl!==f.acl)acls.push(aclSql(sig,f.acl));
 }
 for(const sig of a.fns.keys())if(!b.fns.has(sig))orphans.push(sig);
 const sa=new Set(a.struct),sb=new Set(b.struct);
 const structural=[...b.struct.filter(x=>!sa.has(x)).map(x=>'+ '+x),...a.struct.filter(x=>!sb.has(x)).map(x=>'- '+x)];
 return {fnDefs,acls,orphans,structural};
}

// ---- Payload ----
export async function payload({verbose=false}={}){
 const news=await newSourceStatements(),base=await baselineSql();
 const A=await baselineDb(base),B=await targetDb(news);
 try{
  const step1=news.map(s=>'-- ===== REVIEWED NEW SOURCE: '+s.name+' (dropped: '+s.dropped.join('; ')+') =====\n'+s.statements.join('\n\n')).join('\n\n');
  await A.exec('set check_function_bodies=off;'+news.map(s=>s.statements.join('\n')).join('\n')+';reset check_function_bodies;');
  const [ca,cb,da,db]=[await snapshotCatalog(A),await snapshotCatalog(B),await snapshotData(A),await snapshotData(B)];
  const cat=await diffCatalog(ca,cb),data=diffData(da,db);
  const ignoredOrphans=cat.orphans;
  const structural=cat.structural;
  if(structural.length||data.problems.length){
   const msg=['structural:',...structural.slice(0,80),'data:',...data.problems.slice(0,40)].join('\n');
   if(verbose)console.error(msg);throw Error('unreviewed production drift\n'+msg.slice(0,6000));
  }
  const fnSection=cat.fnDefs.map(f=>f.def.trim()+';').join('\n\n');
  const aclSection=cat.acls.join('\n');
  const dataSection=data.upserts.map(upsertSql).join('\n');
  const sql=[step1,'-- ===== FINAL-STATE FUNCTIONS: '+cat.fnDefs.length+' changed/new (pg_get_functiondef of reviewed staging target) =====\n'+fnSection,
   '-- ===== EXECUTE GRANTS for every changed function (Supabase default privileges are not trusted) =====\n'+aclSection,
   '-- ===== CONFIG ROWS: '+data.upserts.length+' (new rows insert-only; existing rows update only changed columns) =====\n'+dataSection].join('\n\n');
  if(sql.includes(STAGING_ID))throw Error('staging-only capability leaked: '+STAGING_ID);
  if(/cuyqchmdcnsgzkwyclji|guildbattle_test_|sec4_fixture|sec4fixture|_payment_|shop_buy|shop_status/.test(sql))throw Error('staging-only capability leaked');
  for(const st of splitStatements(sql)){const s=stripLeadingComments(st).trim();if(/^(delete\s+from|truncate|drop\s+(table|schema|function)|alter\s+table\s+\S+\s+drop)/i.test(s))throw Error('unreviewed destructive statement: '+s.slice(0,100));}
  // Parity proof: apply the emitted remainder to the baseline and require an identical catalog and config.
  await A.exec('set check_function_bodies=off;'+fnSection+'\n'+aclSection+'\n'+dataSection+';reset check_function_bodies;');
  const again=await diffCatalog(await snapshotCatalog(A),cb),againData=diffData(await snapshotData(A),db);
  if(again.fnDefs.length||again.acls.length||again.structural.length||againData.upserts.length||againData.problems.length)throw Error('delta does not reproduce target: '+JSON.stringify({f:again.fnDefs.map(f=>f.sig).slice(0,10),a:again.acls.slice(0,5),s:again.structural.slice(0,10),d:againData.upserts.slice(0,3).map(u=>u.t)}));
  const newFns=news.flatMap(n=>n.statements.map(st=>st.match(/^create or replace function public\.([a-zA-Z0-9_]+)\(/)?.[1]).filter(Boolean));
  const fnNames=[...new Set([...cat.fnDefs.map(f=>f.sig.replace(/^public\./,'').replace(/\(.*$/,'')),...newFns])].sort();
  const expectedSrc=cat.fnDefs.map(f=>[f.sig,ca.fns.get(f.sig)?.src||null,f.src]);
  return {sql,fnNames,expectedSrc,orphans:ignoredOrphans,tables:[...new Set(data.upserts.map(u=>u.t))].sort(),upserts:data.upserts.length,news};
 }finally{await A.close();await B.close();}
}
export function wrapInstall(p,{systemId=config.productionSystemId}={}){
 const hash=createHash('sha256').update(p.sql).digest('hex'),pin=systemId??'PRODUCTION_SYSTEM_ID_REQUIRED';
 if(systemId!==null&&(!/^[1-9]\d{15,19}$/.test(systemId)||systemId===STAGING_ID))throw Error('Invalid production system ID');
 const policyCheck=Object.entries(config.expectedExisting).map(([t,h])=>` execute 'select engine_hash from public.${t} where singleton' into h; if h is distinct from '${h}' then raise exception 'STOP: unexpected existing ${t} engine (%); review before proceeding', h; end if;`).join('\n');
 return `-- GENERATED DELTA ONLY (tools/build_production_release.mjs): existing production DB after release ${config.previousRelease}. NEVER staging_install/seed/payments/shop SQL.
-- Target: ${config.productionProject}; production baseline main ${config.baselineCommit}; staging target = this commit's reviewed sources.
-- ${systemId?'Production system_identifier '+systemId+' (owner-confirmed for release '+config.previousRelease+') pinned; re-check it in 00_preflight_readonly.sql first.':'BLOCKED until the production system_identifier is pinned.'}
-- One transaction + ledger: rerun is a no-op, changed content is refused. No user rows are deleted or reset.
-- Phase 6/7 replay switches are installed OFF (battle_replay_policy_v6/v7.enabled=false).
begin;
do $production_guard$
declare expected_system_id text := '${pin}'; actual_system_id text;
begin
 select system_identifier::text into actual_system_id from pg_catalog.pg_control_system();
 if expected_system_id !~ '^[1-9][0-9]{15,19}$' or expected_system_id='${STAGING_ID}' or actual_system_id is distinct from expected_system_id then
  raise exception 'STOP: production system_identifier must be explicitly pinned and match; staging/unknown DB refused';
 end if;
end $production_guard$;
set local lock_timeout='5s';
set local statement_timeout='180s';
select pg_advisory_xact_lock(hashtext('vr:production:${config.release}'));
do $production_install$
declare h text; f record;
begin
 if to_regclass('vr_rollout_private.releases') is null or not exists(select 1 from vr_rollout_private.releases where release_id='${config.previousRelease}') then
  raise exception 'STOP: release ${config.previousRelease} is not installed on this DB; refusing ${config.release}';
 end if;
 select bundle_hash into h from vr_rollout_private.releases where release_id='${config.release}';
 if found then
  if h is distinct from '${hash}' then raise exception 'STOP: release content changed after installation; use a reviewed follow-up migration'; end if;
  raise notice 'Production release ${config.release} already installed: no data/function/policy changes'; return;
 end if;
 -- Do not rotate an unknown live engine silently; v6/v7 must not exist yet.
${policyCheck}
 if to_regclass('public.battle_replay_policy_v6') is not null or to_regclass('public.battle_replay_policy_v7') is not null then
  raise exception 'STOP: phase6/7 replay tables already exist in production; review before proceeding';
 end if;
 perform set_config('check_function_bodies','off',true);
 execute $vr_production_payload$
${p.sql}
$vr_production_payload$;
 perform set_config('check_function_bodies','on',true);
 for f in select pg_get_functiondef(oid) ddl from pg_proc where pronamespace='public'::regnamespace and prokind='f' and proname=any(array[${p.fnNames.map(x=>"'"+x+"'").join(',')}]) loop execute f.ddl; end loop;
 if exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosecdef and left(p.proname,1)='_' and pg_get_function_result(p.oid)<>'trigger' and (has_function_privilege('anon',p.oid,'execute') or has_function_privilege('authenticated',p.oid,'execute'))) then raise exception 'STOP: public-callable internal definer function'; end if;
 insert into vr_rollout_private.releases(release_id,bundle_hash,db_id) values('${config.release}','${hash}',(select system_identifier::text from pg_catalog.pg_control_system()));
end $production_install$;
notify pgrst,'reload schema';
commit;
select 'Production DB delta ${config.release} installed; deploy all FIVE production Edge bundles before the Worker/main release' as result;
`;
}
const fnCheck=(rowsList,which)=>`with expected(sig,src) as (values\n${rowsList.map(([sig,a,b])=>` (${lit(sig)},${(which==='before'?a:b)?lit(which==='before'?a:b):'null'})`).join(',\n')}\n)\nselect count(*) filter (where e.src is not distinct from md5(p.prosrc)) as ${which==='before'?'baseline_match':'target_match'}, count(*) filter (where e.src is distinct from md5(p.prosrc)) as ${which==='before'?'differs_from_main_baseline':'mismatch_must_be_0'}, string_agg(case when e.src is distinct from md5(p.prosrc) then e.sig end, ', ') as ${which==='before'?'differs_list':'mismatch_list'}\nfrom expected e left join pg_proc p on to_regprocedure(e.sig)=p.oid;`;
export function preflightSql(p){
 return `-- READ-ONLY preflight for production release ${config.release}. Run in the production SQL Editor; changes nothing.
-- 1) Must be ${config.productionSystemId}. If not: STOP.
select system_identifier::text as production_system_identifier, system_identifier::text='${config.productionSystemId}' as pinned_ok from pg_control_system();
-- 2) Release ledger: ${config.previousRelease} must exist; ${config.release} must NOT exist yet.
select release_id, completed_at from vr_rollout_private.releases order by completed_at;
-- 3) Live engine hashes must equal release ${config.previousRelease} values (all true).
${Object.entries(config.expectedExisting).map(([t,h])=>`select '${t}' as policy, engine_hash='${h}' as ok, enabled from public.${t};`).join('\n')}
select to_regclass('public.battle_replay_policy_v6') is null and to_regclass('public.battle_replay_policy_v7') is null as phase67_not_installed_ok;
-- 4) Story CH15 already in production? Expect 16 phases. 0 means story_ch15.sql was never applied: STOP and tell the agent.
select count(*) as ch15_phases from public.story_phase_config where chapter=15;
select count(*) as ch16_17_phases_must_be_0 from public.story_phase_config where chapter in (16,17);
-- 5) Open battles (should be 0 or near 0 inside the maintenance window).
select mode, count(*) as open_sessions from public.battle_sessions_v2 where status='issued' and expires_at>now() group by 1;
-- 6) Drift: functions this release replaces vs the main baseline. differs_from_main_baseline should be 0;
--    otherwise someone hot-fixed production by hand: send the list before running 01_install.sql.
${fnCheck(p.expectedSrc.filter(x=>x[1]),'before')}
`;
}
export function postflightSql(p){
 return `-- READ-ONLY postflight for production release ${config.release}. Every check must be true / 0.
select release_id, completed_at from vr_rollout_private.releases where release_id in ('${config.previousRelease}','${config.release}') order by 1;
select (select engine_hash from public.pvp_policy_v3)=${lit(p.policy.pvp_policy_v3)} pvp_ok,
 (select engine_hash from public.guildbattle_policy_v4)=${lit(p.policy.guildbattle_policy_v4)} guild_ok,
 (select engine_hash from public.arcade_policy_v5)=${lit(p.policy.arcade_policy_v5)} arcade_ok,
 (select engine_hash from public.battle_replay_policy_v6)=${lit(p.policy.battle_replay_policy_v6)} sweep_v6_ok,
 (select engine_hash from public.battle_replay_policy_v7)=${lit(p.policy.battle_replay_policy_v7)} direct_v7_ok,
 (select enabled from public.battle_replay_policy_v6)=false v6_off_ok, (select enabled from public.battle_replay_policy_v7)=false v7_off_ok;
select (select count(*) from public.story_phase_config where chapter=16)=12 ch16_ok, (select count(*) from public.story_phase_config where chapter=17)=15 ch17_ok,
 (select count(*) from public.battle_story_defs_v2 where chapter in (16,17))=27 ch16_17_defs_ok,
 (select count(*) from public.battle_card_meta_v2 where id in ('10511','10512','10513','10520','10521','10522','10523','10524','10525','10526','10527','10528','10529','10530','10531','10532'))=16 new_cards_ok,
 public._player_unlock_level('chapter_16')=1 and public._player_unlock_level('skill')=13 level_policy_kept_ok;
select count(*)=0 as no_public_internal_definer_ok from pg_proc p where p.pronamespace='public'::regnamespace and p.prosecdef and left(p.proname,1)='_' and pg_get_function_result(p.oid)<>'trigger' and (has_function_privilege('anon',p.oid,'execute') or has_function_privilege('authenticated',p.oid,'execute'));
select not has_function_privilege('anon','public.story_complete_scene(integer,integer)','execute') and has_function_privilege('authenticated','public.story_complete_scene(integer,integer)','execute') scene_acl_ok;
${fnCheck(p.expectedSrc,'after')}
`;
}
export async function productionBundle(name){
 const source=await rd('supabase/functions/'+name+'/dashboard_single_file.ts');
 const staging='cuyqchmdcnsgzkwyclji';
 if(source.split(staging).length-1!==2||source.split('staging verifier unavailable').length-1!==1)throw Error(name+' target transform drift');
 const out='// PRODUCTION ONLY — generated from the unchanged, regression-tested staging handler/engine.\n'+source.replaceAll(staging,config.productionProject).replaceAll('Staging ','Production ').replaceAll('staging verifier unavailable','production verifier unavailable').replace(/node tools\/build_phase[34567]_dashboard\.mjs/g,'node tools/build_production_release.mjs');
 if(out.includes(staging)||out.includes(STAGING_ID))throw Error(name+' staging leak');
 return out;
}
export async function policyHashes(){
 const pick=async(f,re)=>{const s=await rd(f);const m=s.match(re);if(!m)throw Error('hash missing '+f);return m[1];};
 const h={};
 for(const [t,f] of [['pvp_policy_v3','security_phase3_pvp.sql'],['guildbattle_policy_v4','security_phase4_raid_guildwar.sql'],['arcade_policy_v5','security_phase5_arcade.sql'],['battle_replay_policy_v6','security_phase6_story_tower.sql'],['battle_replay_policy_v7','security_phase7_direct_replay.sql']])
  h[t]=await pick('supabase/'+f,new RegExp('insert into public\\.'+t+'\\(singleton,\\s*(?:enabled,\\s*)?engine_hash\\)\\s*values\\s*\\(true,\\s*(?:false,\\s*)?\'([a-f0-9]{64})\''));
 return h;
}
export async function files(){
 const p=await payload();p.policy=await policyHashes();
 const out=new Map([[config.outDir+'/00_preflight_readonly.sql',preflightSql(p)],[config.outDir+'/01_install.sql',wrapInstall(p)],[config.outDir+'/02_postflight_readonly.sql',postflightSql(p)]]);
 for(const name of config.edges)out.set(config.outDir+'/functions/'+name+'/dashboard_single_file.ts',await productionBundle(name));
 out.set(config.outDir+'/MANIFEST.txt',[`release ${config.release} (after ${config.previousRelease})`,`functions created/replaced (new sources + final-state diff): ${p.fnNames.length} names`,...p.fnNames.map(n=>'  fn '+n),`config tables touched (${p.upserts} rows):`,...p.tables.map(t=>'  '+t),`functions in production but not in target (left untouched): ${p.orphans.length}`,...p.orphans.map(o=>'  '+o),'policy hashes after install:',...Object.entries(p.policy).map(([k,v])=>'  '+k+' '+v),''].join('\n'));
 return {out,p};
}
if(process.argv[1]===fileURLToPath(import.meta.url)){
 const {out}=await files();
 for(const [name,content]of out){const url=new URL(name,root);if(process.argv.includes('--check')){let cur='';try{cur=await readFile(url,'utf8');}catch{}if(cur!==content)throw Error('stale '+name+' — run: node tools/build_production_release.mjs');}else{await mkdir(new URL('.',url),{recursive:true});await writeFile(url,content);}}
 console.log(`Production release ${config.release}: preflight + delta + postflight + ${config.edges.length} production Edge bundles ${process.argv.includes('--check')?'up to date':'written'}`);
}
