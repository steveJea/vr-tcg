-- Staging only: phase7 engine_hash after storyLevel intrusion + mustSummon derivation.
-- system_identifier 7703759698107299042 (staging project cuyqchmdcnsgzkwyclji).
do $$
declare
  old_7 text := '0178e4a7e0fcdedce4815b75c2a9449782f93b3d7df1277d0943a532ff3659d2';
  new_7 text := 'fe63c33c17f3019f771b7b393cd7c53325cb743aefe9ebc476ce082c3a0a68f7';
begin
  if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7703759698107299042' then
    raise exception 'STOP: phase7 storyLevel hash update is staging only; production forbidden';
  end if;
  if to_regclass('public.battle_replay_policy_v7') is null then
    raise notice 'battle_replay_policy_v7 not present; skip hash update';
    return;
  end if;
  update public.battle_replay_policy_v7 set engine_hash=new_7 where singleton and engine_hash=old_7;
end $$;
