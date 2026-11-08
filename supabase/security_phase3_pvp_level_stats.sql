-- STAGING ONLY: existing phase3 level-stat engine upgrade. Do NOT run the full
-- staging installer or reset any data. Finish active PvP battles on the OLD
-- client/Edge first; this patch refuses to invalidate an unexpired old session.
-- Then deploy pvp-verify-v3/dashboard_single_file.ts and the new web build.
-- Defense snapshots need NO rewrite: v3 refreshes both sides from owned metadata.
begin;
do $pvp_level_staging_guard$
begin
 if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7703759698107299042' then
  raise exception 'STOP: PvP level stats only on staging cuyqchmdcnsgzkwyclji; production htarwisgkkphutxxnuak forbidden';
 end if;
end $pvp_level_staging_guard$;

-- Existing start/settle transactions hold a relation read lock on this table.
-- Exclusive locking drains those transactions and blocks new starts until commit,
-- so the active-session check and policy change cannot race an old engine start.
lock table public.pvp_policy_v3 in access exclusive mode;
do $pvp_level_engine_upgrade$
declare
 old_hash constant text := '16b61abb1c42f29f063b9b84de938ef950363cdd2a23262cddf05c27c0c038a6';
 new_hash constant text := '5a38b4b72651fcb8632fb1bfe14e1cd18a758d08249dbb18b0cfd223123c7a67'; -- GENERATED level-stat engine hash
 actual text;
begin
 select engine_hash into actual from public.pvp_policy_v3 where singleton;
 if actual is null then raise exception 'STOP: install security phase3 first'; end if;
 if actual not in(old_hash,new_hash) then raise exception 'STOP: unexpected PvP engine version; do not overwrite another rollout'; end if;
 if exists(select 1 from public.pvp_sessions_v3 where status='issued' and engine_hash<>new_hash and expires_at>clock_timestamp()) then
  raise exception 'STOP: active old PvP sessions; finish them with the old Edge/client first, or wait for their expiry (at most one hour)';
 end if;
 -- Preserve kill switch, ratings, wallets, attempts, receipts and deck snapshots.
 update public.pvp_policy_v3 set engine_hash=new_hash where singleton and engine_hash=old_hash;
end $pvp_level_engine_upgrade$;
commit;
select engine_hash,enabled from public.pvp_policy_v3 where singleton;
