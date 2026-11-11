-- Staging only: restore the 2026-11-08 account-level unlock policy.
-- story_ch16_17.sql (before this fix) re-created public._player_unlock_level with old per-chapter
-- level walls (chapter_2=7 … chapter_16=26, chapter_17=27) and skill 10 / equip 15.
-- This puts back the exact 11-08 definition from level_unlocks_staging.sql (main 12c5e00, = production):
--   chapters open by clearing the previous chapter (no level wall), sweep 5, skill 13, equip 3, equip_merge 20.
-- _tower_min_level is re-applied unchanged (normal 10, wind/ice/fire 25, light/dark 40).
-- Paste the whole file into the staging SQL Editor and Run once. Safe to rerun. No data changes.
do $unlock_restore$
begin
  if (select system_identifier::text from pg_control_system()) <> '7703759698107299042' then
    raise exception 'STOP: staging only';
  end if;
  execute $fn$
create or replace function public._player_unlock_level(p_key text) returns int language sql immutable as $$
 select case when p_key ~ '^chapter_[0-9]+$' then 1 else case p_key
 when 'sweep' then 5 when 'skill' then 13 when 'equip' then 3 when 'equip_merge' then 20 else null end end
$$
$fn$;
  execute $fn$
create or replace function public._tower_min_level(p text) returns int language sql immutable as $$
 select case p when 'normal' then 10 when 'light' then 40 when 'dark' then 40 else 25 end
$$
$fn$;
  if public._player_unlock_level('chapter_16') <> 1 or public._player_unlock_level('chapter_17') <> 1
     or public._player_unlock_level('chapter_3') <> 1 or public._player_unlock_level('skill') <> 13
     or public._player_unlock_level('equip') <> 3 or public._player_unlock_level('sweep') <> 5
     or public._player_unlock_level('equip_merge') <> 20 or public._tower_min_level('wind') <> 25
     or public._tower_min_level('light') <> 40 or public._tower_min_level('normal') <> 10 then
    raise exception 'STOP: unlock policy check failed after restore';
  end if;
  raise notice 'Unlock policy restored to the 2026-11-08 version';
end
$unlock_restore$;
-- 확인 (모두 true):
-- select public._player_unlock_level('chapter_16') = 1 ch16, public._player_unlock_level('skill') = 13 skill, public._player_unlock_level('equip') = 3 equip;
