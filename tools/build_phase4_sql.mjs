// Explicit, reviewable legacy rule extraction: no live DB, no wildcard SQL execution.
import {readFile,writeFile} from 'node:fs/promises';
import {splitStatements,stripLeadingComments} from './sql_statements.mjs';
const root=new URL('../',import.meta.url),rd=p=>readFile(new URL(p,root),'utf8');
const names=['guild_raids','guild_raid_stages','guild_raid_attempts','guild_raid_damage','war_decks','war_entries','war_roster','war_matches','war_ajits','war_atk_state','war_attacks'];
const sources=['guild2.sql','guild3.sql','guild4.sql','manual_battle.sql','war_manual.sql','guild4_ui.sql','war_auto.sql','card_id_remap.sql'];
const funcs=new Map(),tables=[];
for(const f of sources)for(const stmt of splitStatements(await rd('supabase/'+f))){const s=stripLeadingComments(stmt);let m=s.match(/^create or replace function public\.((?:_?raid_|_?war_)[a-z_]+|_guild_reward)\(/i);if(m)funcs.set(m[1],s);if(f==='guild3.sql'||f==='guild4.sql')if(/^create table if not exists public\./i.test(s)&&names.some(n=>s.startsWith('create table if not exists public.'+n+' ')))tables.push(s);}
const excluded=new Set(['raid_log','war_log','raid_start','raid_finish','raid_sweep','war_start','war_finish','war_signup']);
const mappings=new Map(names.map(n=>[n,n+'_v4']));for(const n of funcs.keys())mappings.set(n,n==='_guild_reward'?'_guild_reward_v4':(n.startsWith('_')?n+'_v4':'_'+n+'_v4'));
function map(s){return s.replace(/\b[a-z_][a-z0-9_]*\b/g,n=>mappings.get(n)||n).replaceAll('_guild_week()','_raid_week_v4()').replaceAll('_guild_day()','_raid_day_v4()').replace(/set search_path\s*=\s*public(?:, auth)?/g,'set search_path=pg_catalog,public,pg_temp');}
let out=await rd('tools/phase4/head.sql');out+='\n-- ISOLATED VERIFIED TABLES: legacy rows remain untouched.\n'+tables.map(map).join('\n');
out+='\nalter table guild_raid_attempts_v4 add column if not exists actions jsonb;\nalter table war_attacks_v4 add column if not exists actions jsonb;\ncreate unique index if not exists war_roster_user_v4 on war_roster_v4(season,user_id) where user_id is not null;\ninsert into war_decks_v4 select * from war_decks on conflict do nothing;\n';
for(const [n,s] of funcs){if(excluded.has(n))continue;let body=map(s);
 if(n==='_raid_now'||n==='_war_now')body=body.replace('select now()','select public._guildbattle_now_v4()');
 if(n==='_guild_reward')body=body.replace('begin\n','begin\n  perform _guildbattle_guard_v4();\n  p_ref := p_ref || \':v4\';\n');
 // Claim checks must reference the same namespace as the payout ledger.
 if(['raid_status','raid_claimable','raid_claim','_war_pending'].includes(n))body=body.replace(/ref = ('raidst:' \|\| w \|\| ':' \|\| s\.stage|'raidrk:' \|\| w|'warm:' \|\| r\.id|'wars:' \|\| r\.season)/g,"ref = $1 || ':v4'");
 if(n==='_war_pending')body=body.replace("and e.status = 'in'","and e.status = 'in' and e.locked and (select count(distinct wm.day) from war_matches_v4 wm where wm.season=wr.season and (wm.guild_a=wr.guild_id or wm.guild_b=wr.guild_id) and wm.settled)=5");
 if(n==='_war_lock'||n==='war_set_slot')body=body.replace('case when d.def1 is null then null', 'case when _war_refresh_v4(r.user_id,d.def1) is null then null').replace('jsonb_build_array(d.def1, coalesce(d.def2, \'[]\'::jsonb))',"jsonb_build_array(_war_refresh_v4(r.user_id,d.def1),coalesce(_war_refresh_v4(r.user_id,d.def2),'[]'::jsonb))");
 // The isolated test clock only auto-enters its named fixture guilds.
 if(n==='_war_auto_enter')body=body.replace('where g.level >= _war_min_level_v4()',"where g.level >= _war_min_level_v4() and (not exists(select 1 from guildbattle_test_clock_v4 where expires_at>clock_timestamp()) or g.id in(select unnest(guild_ids) from guildbattle_test_clock_v4 where singleton))");
 if(n==='_guild_reward')body=body.replace("  insert into guild_claims","  if p_reason not in('raid_attempt','raid_last_hit','raid_stage','raid_rank','war_reward','guild_daily','guild_weekly') then raise exception 'invalid reward reason'; end if;\n  insert into reward_claims(user_id,reward_kind,source_or_period,reward,rule_version) values(p_uid,'guild_'||p_reason||'_v4',p_ref,p_rw,4);\n  insert into guild_claims").replace("  return jsonb_build_object('reward', p_rw, 'wallet', w);","  update reward_claims set result=jsonb_build_object('reward',p_rw,'wallet',w) where user_id=p_uid and reward_kind='guild_'||p_reason||'_v4' and source_or_period=p_ref;\n  return jsonb_build_object('reward', p_rw, 'wallet', w);");
 if(n==='raid_status')body=body.replace("where kind = 'fight' and finished_at is not null and not voided","where kind = 'fight' and finished_at is not null and not voided and guild_id=m.guild_id and week=w").replace("bool_or(kind = 'fight' and finished_at is not null)","bool_or(kind = 'fight' and finished_at is not null and not voided and guild_id=m.guild_id and week=w)").replace("'attempts_left', greatest(0, (N->>'attempts_per_day')::int - used)","'attempts_left', greatest(0, (N->>'attempts_per_day')::int - used-(select count(*) from guild_raid_attempts where user_id=uid and day=_raid_day_v4()))").replace("'can_set_diff', m.role in ('boss', 'officer') and r.total_damage = 0","'can_set_diff', m.role in ('boss', 'officer') and r.total_damage = 0 and not exists(select 1 from guild_raid_attempts_v4 where guild_id=m.guild_id and week=w)");
 if(n==='raid_set_difficulty')body=body.replace('if r.total_damage > 0',"if exists(select 1 from guild_raid_attempts_v4 where guild_id=m.guild_id and week=w) or r.total_damage > 0");
 if(n==='raid_claim'||n==='raid_claimable')body=body.replace('if _raid_now_v4() >= _raid_end_v4(w)',"if exists(select 1 from guild_raid_damage_v4 where guild_id=m.guild_id and week=w and damage>0) and _raid_now_v4() >= _raid_end_v4(w)");
 // Guild EXP uses its own idempotency namespace too.
 body=body.replace("'raid:' || p_week","'raid:v4:' || p_week").replace("'war:' || p_mid","'war:v4:' || p_mid");
 out+='\n'+body+'\n';}
// Keep only private start/war settlement implementations, NEVER expose report inputs.
for(const n of ['raid_start','war_start','war_finish']){
 let body=map(funcs.get(n));

 if(n==='war_start')body=body.replace('insert into war_atk_state_v4 (match_id',"snap := _war_refresh_v4(uid,snap); if snap is null then raise exception 'card not owned'; end if;\n    insert into war_atk_state_v4 (match_id").replace("make_interval(mins => (N->>'lock_minutes')::int)","make_interval(mins => (N->>'open_minutes')::int)");
 if(n==='war_finish'){body=body.replace('(p_id bigint, p_win boolean, p_atk_hp jsonb, p_def_hp jsonb)','(p_uid uuid,p_id bigint, p_win boolean, p_atk_hp jsonb, p_def_hp jsonb)').replace('uid uuid := auth.uid()','uid uuid := p_uid').replaceAll('return _war_status_v4() ||','return').replace(/  if now\(\) - a.started_at <[^\n]+\n/,'');}
 if(n==='war_start')body=body.replace("if (select count(*) from war_attacks_v4 where match_id = mt.id and user_id = uid)","if (select count(*) from war_attacks_v4 where match_id = mt.id and user_id = uid)+(select count(*) from war_attacks legacy_attempt join war_matches legacy_match on legacy_match.id=legacy_attempt.match_id where legacy_attempt.user_id=uid and legacy_match.season=s and legacy_match.day=d)");
 out+='\n'+body+'\n';
}
out+='\n'+await rd('tools/phase4/tail.sql');
const quest=splitStatements(await rd('supabase/guild2.sql')).map(stripLeadingComments).find(s=>s.startsWith('create or replace function public.guild_quests('));
let questUi=quest.replace(/set search_path\s*=\s*public/g,'set search_path=pg_catalog,public,pg_temp');
const proof="(case when p.event='raid' then _guildbattle_raid_count_v4(case when p.kind='daily' then uid else null end,m.guild_id,case when p.kind='daily' then d else w end,case when p.kind='daily' then d else w+6 end) else q.progress end)";
questUi=questUi.replaceAll('q.progress',proof).replace("'mine', coalesce((select amount from guild_weekly_contrib c where c.guild_id = q.guild_id and c.week = w and c.slot = q.slot and c.user_id = uid), 0)","'mine', case when p.event='raid' then _guildbattle_raid_count_v4(uid,m.guild_id,w,w+6) else coalesce((select amount from guild_weekly_contrib c where c.guild_id = q.guild_id and c.week = w and c.slot = q.slot and c.user_id = uid),0) end").replace("ref = 'wq:' || w || ':' || q.slot || ':' || (t->>'tier')","ref = 'wq:' || w || ':' || q.slot || ':' || (t->>'tier') || case when p.event='raid' then ':v4' else '' end");
out+='\n'+questUi+'\n';

for(const [n,source] of funcs){if(n.startsWith('_')||excluded.has(n)||n==='war_enter'||n==='war_withdraw')continue;const m=source.match(/^create or replace function public\.\w+\(([^)]*)\) returns ([\w.]+) /);if(!m)throw Error('wrapper signature '+n);const args=m[1].split(',').filter(x=>x.trim()).map(x=>x.trim().split(/\s+/)[0]).join(',');out+=`\ncreate or replace function public.${n}(${m[1]}) returns ${m[2]} language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$ begin perform _guildbattle_guard_v4(); perform pg_advisory_xact_lock(hashtext('guildbattle:v4')); return ${mappings.get(n)}(${args}); end $$;\nrevoke all on function public.${n}(${m[1].split(',').filter(x=>x.trim()).map(x=>x.trim().split(/\s+/).slice(1).join(' ')).join(',')}) from public,anon;\ngrant execute on function public.${n}(${m[1].split(',').filter(x=>x.trim()).map(x=>x.trim().split(/\s+/).slice(1).join(' ')).join(',')}) to authenticated;\n`;}
out+='\ncommit;\n';
const p=new URL('supabase/security_phase4_raid_guildwar.sql',root);if(process.argv.includes('--check')){if(await readFile(p,'utf8')!==out)throw Error('stale phase4 SQL');}else await writeFile(p,out);
console.log('Phase4 SQL '+Buffer.byteLength(out)+' bytes');
