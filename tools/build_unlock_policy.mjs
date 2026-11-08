import {readFile,writeFile} from 'node:fs/promises';
const root=new URL('../',import.meta.url), rd=p=>readFile(new URL(p,root),'utf8');
const p=JSON.parse(await rd('tools/unlocks/policy.json')), rules=JSON.parse(await rd('tools/unlocks/rpc_gates.json'));
const json=x=>JSON.stringify(x).replaceAll("'","''");
const header=`-- GENERATED: node tools/build_unlock_policy.mjs. Run ONLY on staging, after security phases 1-4.\n-- Production is explicitly forbidden. No existing user state is reset.\nbegin;\ndo $guard$ begin\n if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7703759698107299042' then raise exception 'STOP: unlock policy only staging cuyqchmdcnsgzkwyclji; production forbidden'; end if;\n if to_regprocedure('public.guildbattle_start_v4(text,jsonb,uuid,text,text)') is null then raise exception 'STOP: install security phases 1-4 first'; end if;\nend $guard$;\n`;
const sql=header+`create or replace function public._unlock_levels() returns jsonb language sql immutable as $$select '${json(p.features)}'::jsonb$$;\ncreate or replace function public._unlock_intros() returns jsonb language sql immutable as $$select '${json(p.entries)}'::jsonb$$;\n`+(await rd('tools/unlocks/migration.sql')).replace('__RPC_GATES__',json(rules));
const js=`// GENERATED from tools/unlocks/policy.json; do not edit.\nwindow.VR_UNLOCK_POLICY = ${JSON.stringify(p,null,2)};\n`;
for(const [path,text]of [['supabase/level_unlocks_staging.sql',sql],['js/unlock-policy.js',js]]) {
 if(process.argv.includes('--check')) {if(await rd(path)!==text)throw Error(path+' stale');}
 else await writeFile(new URL(path,root),text);
}
