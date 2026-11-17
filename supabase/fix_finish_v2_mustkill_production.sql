-- PRODUCTION ONLY. Run in the production SQL Editor as one script.
-- battle_session_finish_v2 (legacy finish path, used while battle_replay_policy_v7 is off):
-- accept win + reason 'mustkill' when the stage snapshot has rules.mustKill.
--   Before: 16-11 (최국선 mustKill) clears were rejected with 'implausible end reason'
--   because the client ends that battle with reason 'mustkill', which was only taught to
--   battle_direct_settle_v7 (#563), not to the legacy finish.
-- Patches only the reason check in the installed body (pg_get_functiondef + replace).
-- Grants, security definer and search_path are kept. Safe to run more than once.
-- No engine_hash change, no Edge redeploy. system_identifier 7692130048193495360.
do $$
declare
  f record; def_ text; found_ int := 0; patched_ int := 0;
  old_list text := $q$'mustsummon','hp','cards','draw')$q$;
  new_list text := $q$'mustsummon','hp','cards','draw','mustkill')$q$;
  old_rule text := $q$ or (reason_='survive' and (not win_$q$;
  new_rule text := $q$ or (reason_='mustkill' and (not win_ or jsonb_typeof(cfg->'rules'->'mustKill') is distinct from 'array' or cfg->'rules'->'mustKill'='[]'::jsonb))
 or (reason_='survive' and (not win_$q$;
begin
  if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7692130048193495360' then
    raise exception 'STOP: this file is for production only (staging uses fix_finish_v2_mustkill_staging.sql)';
  end if;
  -- Find every installed copy of the legacy finish body (phase6/phase7 renamed it, a re-run may have restored it).
  for f in
    select p.oid, p.oid::regprocedure::text sig, p.prosrc
      from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('battle_session_finish_v2', '_phase7_prev_finish_v2', '_phase6_old_finish_v2')
       and p.prosrc like '%implausible end reason%'
  loop
    found_ := found_ + 1;
    if f.prosrc like '%''mustkill''%' then
      raise notice '% already accepts mustkill; skip', f.sig;
      continue;
    end if;
    if (length(f.prosrc) - length(replace(f.prosrc, old_list, ''))) / length(old_list) <> 1
       or (length(f.prosrc) - length(replace(f.prosrc, old_rule, ''))) / length(old_rule) <> 1 then
      raise exception 'STOP: % body differs from the expected phase2 finish; not patched', f.sig;
    end if;
    def_ := pg_catalog.pg_get_functiondef(f.oid);
    def_ := replace(replace(def_, old_list, new_list), old_rule, new_rule);
    execute def_;
    patched_ := patched_ + 1;
    raise notice '% patched (mustkill)', f.sig;
  end loop;
  if found_ = 0 then
    raise exception 'STOP: legacy battle_session_finish_v2 body not found';
  end if;
  raise notice 'mustkill finish fix: % found, % patched', found_, patched_;
end $$;
