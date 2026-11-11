-- Staging only: phase7 engine_hash after 16-11 become (윤진아 → [각성] 윤진아) lookup fix.
-- system_identifier 7703759698107299042 (staging project cuyqchmdcnsgzkwyclji).
do $$
declare
  old_7 text := 'fe63c33c17f3019f771b7b393cd7c53325cb743aefe9ebc476ce082c3a0a68f7';
  new_7 text := 'c7957db40094278cd3593d56a0cb993634cbabdbdc565d2eb6827a2472b3c05e';
begin
  if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7703759698107299042' then
    raise exception 'STOP: phase7 become-hash update is staging only; production forbidden';
  end if;
  if to_regclass('public.battle_replay_policy_v7') is null then
    raise notice 'battle_replay_policy_v7 not present; skip hash update';
    return;
  end if;
  update public.battle_replay_policy_v7 set engine_hash=new_7 where singleton and engine_hash=old_7;
end $$;
