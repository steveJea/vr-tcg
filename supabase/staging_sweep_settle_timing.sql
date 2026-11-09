-- Staging only. Drop the wall-clock "too fast" check from replayed tower sweeps.
-- Paste this whole file in the staging SQL Editor and Run. One statement, no temp tables.
-- The replay is the result. Daily session issuance and the tower daily floor cap still limit volume.
-- Manual story and manual tower fights keep their own timing checks.

do $sweep_timing$
begin
  if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7703759698107299042' then
    raise exception 'STOP: staging cuyqchmdcnsgzkwyclji only (system_identifier 7703759698107299042)';
  end if;
  if to_regprocedure('public.battle_sweep_settle_v6(uuid,uuid,text,jsonb)') is null then
    raise exception 'STOP: phase6 sweep SQL is not installed';
  end if;
  execute $sql$
create or replace function public.battle_sweep_settle_v6(p_uid uuid, p_id uuid, p_engine_hash text, p_result jsonb) returns jsonb
language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $settle$
declare s public.battle_sessions_v2; pol public.battle_replay_policy_v6; tp public.tower_progress;
 tw text; fl int; win_ boolean; reason_ text; tr int; mt int; first_ boolean; baseline int;
 rw jsonb; cur jsonb; pay jsonb := '{}'::jsonb; res jsonb;
begin
 if p_uid is null or p_id is null then raise exception 'battle session not found'; end if;
 perform pg_advisory_xact_lock(hashtext('battle-v2:' || p_uid::text));
 perform pg_advisory_xact_lock(hashtext('gem:' || p_uid::text));
 select * into pol from public.battle_replay_policy_v6 where singleton;
 select * into s from public.battle_sessions_v2 where id = p_id and user_id = p_uid for update;
 if not found or s.mode <> 'tower_sweep' then raise exception 'battle session not found'; end if;
 if s.status = 'settled' then
  if p_result is null or s.submission is distinct from p_result then raise exception 'submission conflict'; end if;
  return s.settlement;
 end if;
 if s.status <> 'issued' then raise exception 'battle session closed'; end if;
 if s.expires_at <= clock_timestamp() then
  update public.battle_sessions_v2 set status = 'expired', finished_at = clock_timestamp() where id = s.id and status = 'issued';
  return jsonb_build_object('ok', false, 'session', s.id, 'status', 'expired', 'reward_held', true, 'validation', 'replay-v6');
 end if;
 if pol.enabled is not true or pol.engine_hash is distinct from p_engine_hash or p_engine_hash !~ '^[a-f0-9]{64}$' then
  raise exception 'verifier unavailable';
 end if;
 -- The replay is the proof of the floor. min_seconds is a wall-clock stand-in for
 -- client-reported wins. A sweep opens one session per floor and settles it as soon
 -- as the replay returns; the client paces from the sweep start, so a later floor's
 -- session can be younger than 1 second and the check rejects a normal sweep.
 -- Volume stays limited per request by the daily session issuance cap and the tower
 -- daily floor cap, not by a minimum combat duration.
 if not public._clear_enabled_v2('tower') then raise exception 'reward verification pending'; end if;
 if jsonb_typeof(p_result) is distinct from 'object'
  or (select count(*) from jsonb_object_keys(p_result)) <> 4
  or not (p_result ?& array['win','reason','turns','my_turns'])
  or jsonb_typeof(p_result->'win') is distinct from 'boolean'
  or p_result->>'turns' !~ '^[0-9]{1,2}$' or p_result->>'my_turns' !~ '^[0-9]{1,2}$' then raise exception 'invalid replay'; end if;
 win_ := (p_result->>'win')::boolean;
 reason_ := p_result->>'reason';
 tr := (p_result->>'turns')::int;
 mt := (p_result->>'my_turns')::int;
 if tr < 1 or tr > 40 or mt <> ceil(tr / 2.0)::int then raise exception 'invalid replay'; end if;
 if win_ and reason_ <> 'wipe' or not win_ and reason_ not in ('wipe', 'timeout') then raise exception 'invalid replay'; end if;
 tw := split_part(s.target, ':', 1);
 fl := split_part(s.target, ':', 2)::int;
 if fl % 10 = 0 or fl < 1 then raise exception 'boss floor or invalid floor'; end if;
 tp := public._tower_row(p_uid, tw);
 perform public._tower_gate(p_uid, tw, tp);
 if fl > 1 and not public._clear_access_v2(p_uid, 'tower', tw || ':' || (fl - 1)::text) then raise exception 'floor locked'; end if;
 if not win_ then
  res := jsonb_build_object('ok', true, 'session', s.id, 'status', 'settled', 'win', false, 'cleared', false,
   'reward_held', false, 'validation', 'replay-v6', 'reason', reason_, 'turns', tr, 'reward', '{}'::jsonb, 'currency', '{}'::jsonb);
  update public.battle_sessions_v2 set status = 'settled', submission = p_result, settlement = res, finished_at = clock_timestamp() where id = s.id;
  return res;
 end if;
 baseline := coalesce((select (tower_paid->>tw)::int from public.battle_legacy_access_v2 where user_id = p_uid), 0);
 first_ := fl > baseline and not exists(select 1 from public.battle_clear_receipts_v2 where user_id = p_uid and mode = 'tower' and target = s.target);
 rw := case when first_ then public._tower_reward(tw, fl) else '{}'::jsonb end;
 cur := case when first_ then public._tower_currency(tw, fl) else '{}'::jsonb end;
 if first_ then pay := public._clear_grant_v2(p_uid, rw || cur, 'tower_v2', 'tower:' || s.target); end if;
 insert into public.battle_clear_receipts_v2(user_id, mode, target, session_id) values (p_uid, 'tower', s.target, s.id) on conflict do nothing;
 update public.tower_progress set battle = null, clears = clears + 1, day_floors = day_floors + 1, best_floor = greatest(best_floor, fl),
  paid_floor = case when first_ then greatest(paid_floor, fl) else paid_floor end,
  rewards = (select jsonb_object_agg(k, coalesce((rewards->>k)::int, 0) + coalesce((rw->>k)::int, 0) + coalesce((cur->>k)::int, 0)) from unnest(array['tickets','gold','blood','shard','soul']) k),
  updated_at = now()
  where user_id = p_uid and tower = tw;
 insert into public.battle_events_v2(session_id, user_id, mode, win, skills, day, week)
  values (s.id, p_uid, 'tower', true, 0, public._gem_day(), public._weekly_week())
  on conflict (session_id) do update set win = true, skills = 0;
 res := jsonb_build_object('tower', tw, 'floor', fl, 'best_floor', greatest(tp.best_floor, fl), 'first', first_, 'paid', first_,
  'reward', rw, 'currency', cur, 'tickets', pay->'tickets', 'today', tp.day_floors + 1, 'daily', public._tower_daily(tw),
  'ok', true, 'session', s.id, 'status', 'settled', 'win', true, 'cleared', true, 'reward_held', false,
  'validation', 'replay-v6', 'reason', reason_, 'turns', tr);
 update public.battle_sessions_v2 set status = 'settled', submission = p_result, settlement = res, finished_at = clock_timestamp() where id = s.id;
 return res;
end $settle$;
$sql$;
end
$sweep_timing$;
