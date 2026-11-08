// Delta-only production package. Never executes SQL, deploys, or reads credentials.
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {splitStatements,stripLeadingComments} from './sql_statements.mjs';
export const root=new URL('../',import.meta.url);
export const config=JSON.parse(await readFile(new URL('tools/production/config.json',root),'utf8'));
export const rd=p=>readFile(new URL(p,root),'utf8');
export const versions={pvp_policy_v3:'5a38b4b72651fcb8632fb1bfe14e1cd18a758d08249dbb18b0cfd223123c7a67',guildbattle_policy_v4:'c570973669776971316dfb650482e1401c5628c5ba73e57d23b879b9320c719a',arcade_policy_v5:'e792c491ffafe19d047aa6f58db1920e5767e4059e14816611dd38d473871161'};
const guards={ 'security_phase3_pvp.sql':'phase3_staging_guard','security_phase4_raid_guildwar.sql':'phase4_staging_guard','level_unlocks_staging.sql':'guard','security_phase5_arcade.sql':'phase5_staging_guard'};
const productionBudget=`create or replace function public._guildbattle_used_v4(p_uid uuid,p_kind text,p_mid bigint default null) returns bigint language plpgsql stable security definer set search_path=pg_catalog,public,pg_temp as $budget$
declare total_ bigint; mt war_matches_v4; d date:=_raid_day_v4();
begin
 if p_kind='raid' then
  select (select count(*) from guild_raid_attempts where user_id=p_uid and day=d)+(select count(*) from guild_raid_attempts_v4 where user_id=p_uid and day=d) into total_;
 elsif p_kind='war' and p_mid is not null then
  select * into mt from war_matches_v4 where id=p_mid;
  if mt.id is null then raise exception 'bad budget match'; end if;
  select (select count(*) from war_attacks_v4 where match_id=p_mid and user_id=p_uid)+(select count(*) from war_attacks a join war_matches m on m.id=a.match_id where a.user_id=p_uid and m.season=mt.season and m.day=mt.day) into total_;
 else raise exception 'bad budget kind'; end if;
 return total_;
end $budget$;`;
export async function payload() {
 const sections=[],names=new Set();
 for(const name of config.sources){
  let sql=await rd('supabase/'+name),guardCount=0,clockCount=0,budgetCount=0,entryCount=0;
  const statements=[];
  for(let statement of splitStatements(sql)){
   let s=stripLeadingComments(statement);
   if(/^(begin|commit);$/i.test(s.trim()))continue;
   if(guards[name]&&s.startsWith('do $'+guards[name]+'$')){guardCount++;continue;}
   if(name==='security_phase4_raid_guildwar.sql'){
    if(s.startsWith('create or replace function public._guildbattle_now_v4(')){
     statement="create or replace function public._guildbattle_now_v4() returns timestamptz language sql stable security definer set search_path=pg_catalog,public,pg_temp as $$ select now() $$;";clockCount++;
    }else if(s.startsWith('create or replace function public._guildbattle_used_v4(')){
     statement=productionBudget;budgetCount++;
    }else if(s.includes('guildbattle_test_clock_v4')||s.includes('guildbattle_test_refills_v4')){
     if(s.startsWith('create or replace function public._war_auto_enter_v4(')){
      const filter=' and (not exists(select 1 from guildbattle_test_clock_v4 where expires_at>clock_timestamp()) or g.id in(select unnest(guild_ids) from guildbattle_test_clock_v4 where singleton))';
      if(!statement.includes(filter))throw Error('phase4 entry filter drift');
      statement=statement.replace(filter,'');entryCount++;
     }else if(!/^(create table if not exists|create index if not exists|insert into|alter table|revoke all|do \$refill_acl\$)/.test(s))throw Error('unreviewed fixture statement: '+s.slice(0,120));
     else continue;
    }
   }
   s=stripLeadingComments(statement);
   if(/^(delete\s+from|truncate|drop\s+(table|schema)|update\s+(?!public\.trade_config\b))/i.test(s))throw Error('unreviewed destructive top-level statement: '+s.slice(0,100));
   const fn=s.match(/^create or replace function public\.([a-zA-Z0-9_]+)\(/)?.[1];if(fn)names.add(fn);
   statements.push(statement.trim());
  }
  if(guards[name]&&guardCount!==1)throw Error(name+' guard drift');
  if(name==='security_phase4_raid_guildwar.sql'&&(clockCount!==1||budgetCount!==1||entryCount!==1))throw Error('phase4 production transform drift');
  sections.push('-- ===== REVIEWED DELTA SOURCE: '+name+' =====\n'+statements.join('\n\n'));
 }
 const sql=sections.join('\n\n');
 if(/guildbattle_test_|sec4_fixture|sec4fixture|7703759698107299042/.test(sql))throw Error('staging-only capability leaked');
 return {sql,names:[...names].sort()};
}
export async function buildProductionSql({systemId=config.productionSystemId}={}){
 const {sql,names}=await payload(),hash=createHash('sha256').update(sql).digest('hex'),pin=systemId??'PRODUCTION_SYSTEM_ID_REQUIRED';
 if(systemId!==null&&(!/^[1-9]\d{15,19}$/.test(systemId)||systemId===config.stagingSystemId))throw Error('Invalid production system ID');
 const policyCheck=Object.entries(versions).map(([table,hash])=>` if to_regclass('public.${table}') is not null then execute 'select engine_hash from public.${table} where singleton' into h; if h is distinct from '${hash}' then raise exception 'STOP: unexpected existing ${table} engine; review upgrade before proceeding'; end if; end if;`).join('\n');
 return `-- GENERATED DELTA ONLY: existing production DB, NEVER staging_install/seed SQL.
-- Target: ${config.productionProject}; baseline main ${config.mainCommit}; staging ${config.stagingCommit}.
-- BLOCKED until the owner reads the production system_identifier and it is pinned in config + regenerated.
-- Do not guess/substitute the current DB ID automatically. See docs/PRODUCTION_ROLLOUT_20261108.md.
-- Atomic + ledger-protected rerun. Existing user rows are not deleted or reset.
begin;
do $production_guard$
declare expected_system_id text := '${pin}'; actual_system_id text;
begin
 select system_identifier::text into actual_system_id from pg_catalog.pg_control_system();
 if expected_system_id !~ '^[1-9][0-9]{15,19}$' or expected_system_id='${config.stagingSystemId}' or actual_system_id is distinct from expected_system_id then
  raise exception 'STOP: production system_identifier must be explicitly pinned and match; staging/unknown DB refused';
 end if;
end $production_guard$;
set local lock_timeout='5s';
set local statement_timeout='120s';
select pg_advisory_xact_lock(hashtext('vr:production:20261108'));
create schema if not exists vr_rollout_private;
revoke all on schema vr_rollout_private from public,anon,authenticated,service_role;
create table if not exists vr_rollout_private.releases(release_id text primary key,bundle_hash text not null,db_id text not null,completed_at timestamptz not null default now());
alter table vr_rollout_private.releases enable row level security;
revoke all on vr_rollout_private.releases from public,anon,authenticated,service_role;
do $production_install$
declare h text; f record;
begin
 select bundle_hash into h from vr_rollout_private.releases where release_id='${config.release}';
 if found then
  if h is distinct from '${hash}' then raise exception 'STOP: release content changed after installation; use a reviewed follow-up migration'; end if;
  raise notice 'Production release ${config.release} already installed: no data/function/policy changes'; return;
 end if;
 -- Do not rotate an unknown/future live engine silently.
${policyCheck}
 -- All users must have left the game; backups and the war/raid boundary must be agreed first.
 perform set_config('check_function_bodies','off',true);
 execute $vr_production_payload$
${sql}
$vr_production_payload$;
 perform set_config('check_function_bodies','on',true);
 -- Compile only release-managed functions after forward dependencies exist.
 for f in select pg_get_functiondef(oid) ddl from pg_proc where pronamespace='public'::regnamespace and prokind='f' and proname=any(array[${names.map(x=>"'"+x+"'").join(',')}]) loop execute f.ddl; end loop;
 if exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosecdef and left(p.proname,1)='_' and pg_get_function_result(p.oid)<>'trigger' and (has_function_privilege('anon',p.oid,'execute') or has_function_privilege('authenticated',p.oid,'execute'))) then raise exception 'STOP: public-callable internal definer function'; end if;
 insert into vr_rollout_private.releases(release_id,bundle_hash,db_id) values('${config.release}','${hash}',(select system_identifier::text from pg_catalog.pg_control_system()));
end $production_install$;
notify pgrst,'reload schema';
commit;
select 'Production DB delta installed; deploy all THREE production Edge bundles before main merge' as result;
`;
}
export async function productionBundle(name){
 const source=await rd('supabase/functions/'+name+'/dashboard_single_file.ts');
 const staging='cuyqchmdcnsgzkwyclji';
 if(source.split(staging).length-1!==2||source.split('staging verifier unavailable').length-1!==1)throw Error(name+' target transform drift');
 return '// PRODUCTION ONLY — generated from the unchanged, regression-tested staging handler/engine.\n'+source.replaceAll(staging,config.productionProject).replaceAll('Staging ','Production ').replaceAll('staging verifier unavailable','production verifier unavailable').replace(/node tools\/build_phase[345]_dashboard\.mjs/g,'node tools/build_production_rollout.mjs');
}
if(process.argv[1]===fileURLToPath(import.meta.url)){
 const files=new Map([['supabase/production/01_install.sql',await buildProductionSql()]]);
 for(const name of config.edges)files.set('supabase/production/functions/'+name+'/dashboard_single_file.ts',await productionBundle(name));
 for(const [name,content]of files){const url=new URL(name,root);if(process.argv.includes('--check')){if(await readFile(url,'utf8')!==content)throw Error('stale '+name);}else{await mkdir(new URL('.',url),{recursive:true});await writeFile(url,content);}}
 console.log('Production delta + 3 pinned-project Edge bundles: '+(config.productionSystemId?'DB ID PINNED':'BLOCKED: production system_identifier needed'));
}
