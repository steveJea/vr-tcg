-- Staging only: 16-11 mustKill (최국선) + phase7 engine_hash.
-- Supersedes supabase/fix_direct_v7_become.sql (9c9edd82).
-- Accepts either the pre-become hash (fe63c33c, if that file was not run) or the
-- become hash (c7957db4) and rotates to this engine. system_identifier 7703759698107299042.
do $$
declare
  old_fe63 text := 'fe63c33c17f3019f771b7b393cd7c53325cb743aefe9ebc476ce082c3a0a68f7';
  old_c795 text := 'c7957db40094278cd3593d56a0cb993634cbabdbdc565d2eb6827a2472b3c05e';
  new_7 text := 'c128e31ac46bd40d34f934af334021693f998f48a6d5b47ad8c414a62588688e';
begin
  if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7703759698107299042' then
    raise exception 'STOP: 16-11 mustKill + phase7 hash update is staging only; production forbidden';
  end if;

  if to_regclass('public.battle_story_defs_v2') is not null then
    update public.battle_story_defs_v2
       set definition = jsonb_set(coalesce(definition, '{}'::jsonb), '{rules,mustKill}', '["10406"]'::jsonb, true)
     where chapter = 16 and phase = 11 and variant = '';
    if not found then
      raise notice 'battle_story_defs_v2 16-11 row not found; skip catalog update';
    end if;
  else
    raise notice 'battle_story_defs_v2 not present; skip catalog update';
  end if;

  if to_regclass('public.battle_replay_policy_v7') is null then
    raise notice 'battle_replay_policy_v7 not present; skip hash update';
    return;
  end if;
  update public.battle_replay_policy_v7
     set engine_hash = new_7
   where singleton and engine_hash in (old_fe63, old_c795);
end $$;
