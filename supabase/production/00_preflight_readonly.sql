-- READ ONLY. Open the PRODUCTION htarwisgkkphutxxnuak SQL Editor yourself first.
-- Return production_system_identifier (not a password/key) so the installer can be pinned.
select system_identifier::text as production_system_identifier,
       current_database() as database_name, current_user as sql_role
from pg_catalog.pg_control_system();

-- Presence only, no player/private content. Missing prerequisites must be reviewed first.
select name, to_regclass('public.'||name) is not null as present
from unnest(array['player_wallet','player_state','story_progress','tower_progress','gallery',
'daily_progress','weekly_progress','achievement_claims','pvp_decks','pvp_attempts',
'guild_raids','guild_raid_attempts','war_entries','war_decks','war_matches','war_attacks']) name;

-- Review outstanding battles/progress BEFORE scheduling maintenance; do not delete these rows.
select 'PvP 최근 진행중' as item,count(*) as count from public.pvp_attempts where reported_at is null and created_at>now()-interval '20 minutes'
union all select '토벌 최근 진행중',count(*) from public.guild_raid_attempts where finished_at is null and started_at>now()-interval '20 minutes'
union all select '조직전 최근 진행중',count(*) from public.war_attacks where finished_at is null and started_at>now()-interval '20 minutes'
union all select '토벌 이번 주 진행 있는 조직',count(*) from public.guild_raids where week=public._guild_week() and (total_damage>0 or stage>1)
union all select '조직전 미정산 경기',count(*) from public.war_matches where not settled;
