// Only rotates the two engine pins. No live DB, game-state changes or reward unlocks.
import {readFile,writeFile} from 'node:fs/promises';
import {PVP_ENGINE_VERSION} from '../js/pvp-engine-version.js';
import {GUILDBATTLE_ENGINE_VERSION} from '../js/guildbattle-engine-version.js';
const root=new URL('../',import.meta.url);
const sql=`-- GENERATED: node tools/build_feedback16_sql.mjs. Existing STAGING only.
-- Finish old PvP/raid/war battles first. No resets, refunds or reward-policy changes.
-- Then redeploy BOTH pvp-verify-v3 and guildbattle-verify-v4 + refresh the web client.
begin;
set local lock_timeout='5s';
do $feedback16_guard$ begin
 if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7703759698107299042' then raise exception 'STOP: feedback16 only staging cuyqchmdcnsgzkwyclji; production forbidden'; end if;
 if to_regclass('public.pvp_policy_v3') is null or to_regclass('public.guildbattle_policy_v4') is null or to_regclass('public.pvp_sessions_v3') is null or to_regclass('public.guildbattle_sessions_v4') is null then raise exception 'STOP: install security phases 1-4 first'; end if;
end $feedback16_guard$;
-- Start/settle read these relations. Drain those transactions and prevent new
-- issuance between the active-session check and the atomic two-policy change.
lock table public.pvp_policy_v3,public.guildbattle_policy_v4 in access exclusive mode;
do $feedback16_engines$
declare
 old_pvp constant text := 'ff3c2c77c26429a0fbf85f1d1ab73edb882af342a152727c1aed64c49160dd2a';
 new_pvp constant text := '${PVP_ENGINE_VERSION}';
 old_guild constant text := 'a00f5c9824515cfce4fcbd6d579deb5e971335035b264454d427fdb93669819e';
 new_guild constant text := '${GUILDBATTLE_ENGINE_VERSION}';
 p text; g text;
begin
 select engine_hash into p from public.pvp_policy_v3 where singleton;
 select engine_hash into g from public.guildbattle_policy_v4 where singleton;
 if p is null or p not in(old_pvp,new_pvp) then raise exception 'STOP: unexpected PvP engine version; do not overwrite another rollout'; end if;
 if g is null or g not in(old_guild,new_guild) then raise exception 'STOP: unexpected guildbattle engine version; do not overwrite another rollout'; end if;
 if exists(select 1 from public.pvp_sessions_v3 where status='issued' and engine_hash<>new_pvp and expires_at>clock_timestamp()) then raise exception 'STOP: active old PvP sessions; finish on old client/Edge first or wait for expiry (up to 1 hour)'; end if;
 if exists(select 1 from public.guildbattle_sessions_v4 where status='issued' and engine_hash<>new_guild and expires_at>clock_timestamp()) then raise exception 'STOP: active old raid/war sessions; finish on old client/Edge first or wait for expiry (up to 20 minutes)'; end if;
 -- Preserve enabled kill switches, all receipts, HP, attempts, wallets, decks,
 -- training/level gates, fixture clock and refill allowances. No old replays.
 update public.pvp_policy_v3 set engine_hash=new_pvp where singleton and engine_hash=old_pvp;
 update public.guildbattle_policy_v4 set engine_hash=new_guild where singleton and engine_hash=old_guild;
end $feedback16_engines$;
commit;
select 'pvp' as mode,engine_hash,enabled from public.pvp_policy_v3 where singleton
union all select 'raid/war',engine_hash,enabled from public.guildbattle_policy_v4 where singleton;
`;
const path=new URL('supabase/security_feedback16_skill_lock_staging.sql',root);
if(process.argv.includes('--check')){if(await readFile(path,'utf8')!==sql)throw Error('stale feedback16 engine upgrade SQL');}
else await writeFile(path,sql);
console.log('Feedback16 atomic staging engine upgrade: '+PVP_ENGINE_VERSION.slice(0,12)+' / '+GUILDBATTLE_ENGINE_VERSION.slice(0,12));
