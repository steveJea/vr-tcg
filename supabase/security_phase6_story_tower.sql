-- 보안 6단계: 시련의 탑 소탕만 서버가 같은 전투를 다시 계산한다.
-- 스토리·수동 탑·특강은 기존 plausibility-v3 그대로다. 이 파일은 그 승패를 다시 증명하지 않는다.
-- 기존 스테이징 업그레이드 전용. 전체 파일 1회 실행(재실행 안전). 운영 금지.
-- 진행·잔액·이미 받은 보상은 지우거나 다시 주지 않는다.
begin;
do $phase6_staging_guard$
begin
 if (select system_identifier::text from pg_control_system()) <> '7703759698107299042' then
  raise exception 'STOP: phase6 only staging cuyqchmdcnsgzkwyclji';
 end if;
 if to_regclass('public.battle_sessions_v2') is null or to_regprocedure('public.battle_session_finish_v2(uuid,jsonb)') is null then
  raise exception 'phase2 required';
 end if;
end $phase6_staging_guard$;

create table if not exists public.battle_replay_policy_v6 (
 singleton boolean primary key default true check (singleton),
 enabled boolean not null default false,
 engine_hash text not null check (engine_hash ~ '^[a-f0-9]{64}$'));
-- Starts off. Re-running this file updates the engine hash only and does not turn enforcement on.
insert into public.battle_replay_policy_v6(singleton, enabled, engine_hash)
 values (true, false, '1dbdb45994799cdcf3db14bd6eb44689d35678a733774caffcfd9867df85685c')
 on conflict (singleton) do update set engine_hash = excluded.engine_hash;
alter table public.battle_replay_policy_v6 enable row level security;
revoke all on public.battle_replay_policy_v6 from public, anon, authenticated;

do $$ begin
 if to_regprocedure('public._phase6_old_finish_v2(uuid,jsonb)') is null then
  alter function public.battle_session_finish_v2(uuid, jsonb) rename to _phase6_old_finish_v2;
 end if;
end $$;

create or replace function public.battle_session_finish_v2(p_session uuid, p_report jsonb) returns jsonb
language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare m text;
begin
 select mode into m from public.battle_sessions_v2 where id = p_session and user_id = auth.uid();
 if m = 'tower_sweep' and coalesce((select enabled from public.battle_replay_policy_v6 where singleton), false) then
  raise exception 'sweep replay required';
 end if;
 return public._phase6_old_finish_v2(p_session, p_report);
end $$;

create or replace function public.battle_sweep_session_v6(p_uid uuid, p_id uuid) returns jsonb
language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare s public.battle_sessions_v2;
begin
 if p_uid is null or p_id is null then raise exception 'battle session not found'; end if;
 select * into s from public.battle_sessions_v2 where id = p_id and user_id = p_uid;
 if not found or s.mode <> 'tower_sweep' then raise exception 'battle session not found'; end if;
 return jsonb_build_object('ok', true, 'id', s.id, 'mode', s.mode, 'target', s.target, 'seed', s.seed,
  'snapshot', s.snapshot, 'status', s.status, 'expires_at', s.expires_at, 'submission', s.submission, 'settlement', s.settlement);
end $$;

create or replace function public.battle_sweep_settle_v6(p_uid uuid, p_id uuid, p_engine_hash text, p_result jsonb) returns jsonb
language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
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
 if clock_timestamp() - s.issued_at < make_interval(secs => (s.snapshot->>'min_seconds')::double precision) then raise exception 'too fast'; end if;
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
end $$;

revoke all on function public._phase6_old_finish_v2(uuid, jsonb), public.battle_session_finish_v2(uuid, jsonb),
 public.battle_sweep_session_v6(uuid, uuid), public.battle_sweep_settle_v6(uuid, uuid, text, jsonb) from public, anon, authenticated;
grant execute on function public.battle_session_finish_v2(uuid, jsonb) to authenticated;
do $$ begin
 if exists (select 1 from pg_roles where rolname = 'service_role') then
  revoke all on function public._phase6_old_finish_v2(uuid, jsonb), public.battle_session_finish_v2(uuid, jsonb),
   public.battle_sweep_session_v6(uuid, uuid), public.battle_sweep_settle_v6(uuid, uuid, text, jsonb) from service_role;
  revoke all on public.battle_replay_policy_v6 from service_role;
  grant execute on function public.battle_sweep_session_v6(uuid, uuid), public.battle_sweep_settle_v6(uuid, uuid, text, jsonb) to service_role;
 end if;
end $$;
notify pgrst, 'reload schema';
commit;
select 'phase6 tower sweep replay installed — staging only, story and manual tower remain plausibility-v3' as result;
