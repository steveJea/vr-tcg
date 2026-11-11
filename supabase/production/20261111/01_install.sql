-- GENERATED DELTA ONLY (tools/build_production_release.mjs): existing production DB after release 20261108. NEVER staging_install/seed/payments/shop SQL.
-- Target: htarwisgkkphutxxnuak; production baseline main 12c5e005ce4c1e184b6e4ffe013aa2a21e6329f5; staging target = this commit's reviewed sources.
-- Production system_identifier 7692130048193495360 (owner-confirmed for release 20261108) pinned; re-check it in 00_preflight_readonly.sql first.
-- One transaction + ledger: rerun is a no-op, changed content is refused. No user rows are deleted or reset.
-- Phase 6/7 replay switches are installed OFF (battle_replay_policy_v6/v7.enabled=false).
begin;
do $production_guard$
declare expected_system_id text := '7692130048193495360'; actual_system_id text;
begin
 select system_identifier::text into actual_system_id from pg_catalog.pg_control_system();
 if expected_system_id !~ '^[1-9][0-9]{15,19}$' or expected_system_id='7703759698107299042' or actual_system_id is distinct from expected_system_id then
  raise exception 'STOP: production system_identifier must be explicitly pinned and match; staging/unknown DB refused';
 end if;
end $production_guard$;
set local lock_timeout='5s';
set local statement_timeout='180s';
select pg_advisory_xact_lock(hashtext('vr:production:20261111'));
do $production_install$
declare h text; f record;
begin
 if to_regclass('vr_rollout_private.releases') is null or not exists(select 1 from vr_rollout_private.releases where release_id='20261108') then
  raise exception 'STOP: release 20261108 is not installed on this DB; refusing 20261111';
 end if;
 select bundle_hash into h from vr_rollout_private.releases where release_id='20261111';
 if found then
  if h is distinct from 'dd2b7a28c5ddb524ab2c5f86da9fbae096e7926bdcc231332ff52d5f24a241da' then raise exception 'STOP: release content changed after installation; use a reviewed follow-up migration'; end if;
  raise notice 'Production release 20261111 already installed: no data/function/policy changes'; return;
 end if;
 -- Do not rotate an unknown live engine silently; v6/v7 must not exist yet.
 execute 'select engine_hash from public.pvp_policy_v3 where singleton' into h; if h is distinct from '5a38b4b72651fcb8632fb1bfe14e1cd18a758d08249dbb18b0cfd223123c7a67' then raise exception 'STOP: unexpected existing pvp_policy_v3 engine (%); review before proceeding', h; end if;
 execute 'select engine_hash from public.guildbattle_policy_v4 where singleton' into h; if h is distinct from 'c570973669776971316dfb650482e1401c5628c5ba73e57d23b879b9320c719a' then raise exception 'STOP: unexpected existing guildbattle_policy_v4 engine (%); review before proceeding', h; end if;
 execute 'select engine_hash from public.arcade_policy_v5 where singleton' into h; if h is distinct from 'e792c491ffafe19d047aa6f58db1920e5767e4059e14816611dd38d473871161' then raise exception 'STOP: unexpected existing arcade_policy_v5 engine (%); review before proceeding', h; end if;
 if to_regclass('public.battle_replay_policy_v6') is not null or to_regclass('public.battle_replay_policy_v7') is not null then
  raise exception 'STOP: phase6/7 replay tables already exist in production; review before proceeding';
 end if;
 perform set_config('check_function_bodies','off',true);
 execute $vr_production_payload$
-- ===== REVIEWED NEW SOURCE: security_phase6_story_tower.sql (dropped: cluster guard) =====
create table if not exists public.battle_replay_policy_v6 (
 singleton boolean primary key default true check (singleton),
 enabled boolean not null default false,
 engine_hash text not null check (engine_hash ~ '^[a-f0-9]{64}$'));

insert into public.battle_replay_policy_v6(singleton, enabled, engine_hash)
 values (true, false, '32f0e5059ddb994d56865b16054d64f3f2c1f389df672be4f113e13c5d4112c2')
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

select 'phase6 tower sweep replay installed — staging only, story and manual tower remain plausibility-v3' as result;

-- ===== REVIEWED NEW SOURCE: security_phase7_direct_replay.sql (dropped: cluster guard) =====
create table if not exists public.battle_replay_policy_v7 (
 singleton boolean primary key default true check (singleton),
 enabled boolean not null default false,
 engine_hash text not null check (engine_hash ~ '^[a-f0-9]{64}$'));

insert into public.battle_replay_policy_v7(singleton, enabled, engine_hash)
 values (true, false, 'fe63c33c17f3019f771b7b393cd7c53325cb743aefe9ebc476ce082c3a0a68f7')
 on conflict (singleton) do update set engine_hash = excluded.engine_hash;

alter table public.battle_replay_policy_v7 enable row level security;

revoke all on public.battle_replay_policy_v7 from public, anon, authenticated;

create or replace function public._phase7_replayable(p_mode text, p_target text, p_stage jsonb) returns boolean
language sql stable as $$
select p_mode = 'story' and p_target ~ '^[0-9]+:[0-9]+$'
 or p_mode = 'tower' and split_part(p_target, ':', 2) ~ '^[0-9]+$'
  and split_part(p_target, ':', 2)::int between 1 and 350
$$;

do $$ begin
 if to_regprocedure('public._phase7_prev_finish_v2(uuid,jsonb)') is null then
  alter function public.battle_session_finish_v2(uuid, jsonb) rename to _phase7_prev_finish_v2;
 end if;
end $$;

create or replace function public.battle_session_finish_v2(p_session uuid, p_report jsonb) returns jsonb
language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare m text; target_ text; stage_ jsonb;
begin
 select mode, target, snapshot->'stage' into m, target_, stage_
  from public.battle_sessions_v2 where id = p_session and user_id = auth.uid();
 if m = 'tower_sweep' and coalesce((select enabled from public.battle_replay_policy_v6 where singleton), false) then
  raise exception 'sweep replay required';
 end if;
 if coalesce((select enabled from public.battle_replay_policy_v7 where singleton), false)
  and public._phase7_replayable(m, target_, stage_) then
  raise exception 'direct replay required';
 end if;
 return public._phase7_prev_finish_v2(p_session, p_report);
end $$;

create or replace function public.battle_direct_session_v7(p_uid uuid, p_id uuid) returns jsonb
language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare s public.battle_sessions_v2;
begin
 if p_uid is null or p_id is null then raise exception 'battle session not found'; end if;
 select * into s from public.battle_sessions_v2 where id = p_id and user_id = p_uid;
 if not found or s.mode not in ('story', 'tower') then raise exception 'battle session not found'; end if;
 return jsonb_build_object('ok', true, 'id', s.id, 'mode', s.mode, 'target', s.target, 'seed', s.seed,
  'snapshot', s.snapshot, 'status', s.status, 'expires_at', s.expires_at, 'submission', s.submission, 'settlement', s.settlement,
  'enabled', coalesce((select enabled from public.battle_replay_policy_v7 where singleton), false));
end $$;

create or replace function public.battle_direct_settle_v7(p_uid uuid, p_id uuid, p_engine_hash text, p_result jsonb, p_client jsonb) returns jsonb
language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare s public.battle_sessions_v2; pol public.battle_replay_policy_v7; tp public.tower_progress;
 cfg jsonb; d jsonb; res jsonb := '{}'::jsonb; x jsonb; o jsonb; stats jsonb := '[]'::jsonb;
 tw text; fl int; win_ boolean; reason_ text; scripted_ text; tr int; mt int; first_ boolean; baseline int;
 rw jsonb; cur jsonb; pay jsonb := '{}'::jsonb; ch int; ph int; stars_ int := 0; mana_ int; maxmana int;
 kills_ int; blocks_ int; ksum int := 0; bsum int := 0; seen text[] := '{}'; uid_ text; cap_ int; clear_ boolean;
begin
 if p_uid is null or p_id is null then raise exception 'battle session not found'; end if;
 perform pg_advisory_xact_lock(hashtext('battle-v2:' || p_uid::text));
 perform pg_advisory_xact_lock(hashtext('gem:' || p_uid::text));
 select * into pol from public.battle_replay_policy_v7 where singleton;
 select * into s from public.battle_sessions_v2 where id = p_id and user_id = p_uid for update;
 if not found or s.mode not in ('story', 'tower') then raise exception 'battle session not found'; end if;
 if s.status = 'settled' then
  if p_result is null or s.submission is distinct from p_result then raise exception 'submission conflict'; end if;
  return s.settlement;
 end if;
 if s.status <> 'issued' then raise exception 'battle session closed'; end if;
 if s.expires_at <= clock_timestamp() then
  update public.battle_sessions_v2 set status = 'expired', finished_at = clock_timestamp() where id = s.id and status = 'issued';
  return jsonb_build_object('ok', false, 'session', s.id, 'status', 'expired', 'reward_held', true, 'validation', 'replay-v7');
 end if;
 if pol.enabled is not true or pol.engine_hash is distinct from p_engine_hash or p_engine_hash !~ '^[a-f0-9]{64}$' then
  raise exception 'verifier unavailable';
 end if;
 if not public._phase7_replayable(s.mode, s.target, s.snapshot->'stage') then raise exception 'unsupported battle'; end if;
 if not public._clear_enabled_v2(case when s.mode = 'tower' then 'tower' else 'story' end) then raise exception 'reward verification pending'; end if;
 if (select count(*) from public.battle_events_v2 where user_id = p_uid and day = public._gem_day() and session_id <> s.id) >= 500 then
  raise exception 'completion rate limit';
 end if;
 if jsonb_typeof(p_result) is distinct from 'object'
  or not (p_result ?& array['win','reason','turns','my_turns','mana','max_mana'])
  or exists (select 1 from jsonb_object_keys(p_result) k where k not in ('win','reason','turns','my_turns','mana','max_mana','scripted'))
  or jsonb_typeof(p_result->'win') is distinct from 'boolean'
  or p_result->>'turns' !~ '^[0-9]{1,2}$' or p_result->>'my_turns' !~ '^[0-9]{1,2}$' then raise exception 'invalid replay'; end if;
 win_ := (p_result->>'win')::boolean;
 reason_ := p_result->>'reason';
 scripted_ := p_result->>'scripted';
 tr := (p_result->>'turns')::int;
 mt := (p_result->>'my_turns')::int;
 cfg := s.snapshot->'stage';
 if tr < 1 or tr > 80 or mt < 1 or mt > tr then raise exception 'invalid replay'; end if;
 if scripted_ is not null and scripted_ <> 'loseClears' then raise exception 'invalid replay'; end if;
 if scripted_ = 'loseClears' and (not coalesce((cfg->>'loseClears')::boolean, false) or win_ or reason_ = 'giveup') then raise exception 'invalid replay'; end if;
 if reason_ = 'giveup' and win_ then raise exception 'invalid replay'; end if;
 if scripted_ is null and reason_ <> 'giveup' then
  if win_ and reason_ = 'survive' and cfg->'rules'->>'survive' is null then raise exception 'invalid replay'; end if;
  if win_ and reason_ not in ('wipe', 'survive', 'ko') then raise exception 'invalid replay'; end if;
  if not win_ and reason_ not in ('wipe', 'timeout', 'incomplete', 'ko') then raise exception 'invalid replay'; end if;
 end if;
 if jsonb_typeof(p_client) is distinct from 'object'
  or exists (select 1 from jsonb_object_keys(p_client) k where k not in ('mana','cards'))
  or jsonb_typeof(p_client->'cards') is distinct from 'array' then raise exception 'invalid replay'; end if;
 clear_ := coalesce(scripted_ = 'loseClears', false) or (reason_ <> 'giveup' and win_);
 if s.mode = 'story' then
  ch := split_part(s.target, ':', 1)::int;
  ph := split_part(s.target, ':', 2)::int;
  perform set_config('request.jwt.claim.sub', p_uid::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  d := public._story_lock(p_uid);
  if d->'battle'->>'session' is distinct from s.id::text then raise exception 'battle not started'; end if;
  if clear_ then
   if jsonb_array_length(p_client->'cards') > 30 then raise exception 'invalid card stats'; end if;
   select enemy_count into cap_ from public.story_phase_config where chapter = ch and phase = ph;
   for x in select * from jsonb_array_elements(p_client->'cards') loop
    uid_ := x->>'uid';
    if uid_ is null or uid_ = any(seen) then raise exception 'duplicate or missing participant'; end if;
    seen := seen || uid_;
    select c into o from jsonb_array_elements(s.snapshot->'cards') c where c->>'uid' = uid_ and not coalesce((c->>'guest')::boolean, false);
    if o is null then raise exception 'unselected XP participant'; end if;
    if jsonb_typeof(x->'kills') is distinct from 'number' or x->>'kills' !~ '^[0-9]{1,3}$'
     or jsonb_typeof(x->'blocks') is distinct from 'number' or x->>'blocks' !~ '^[0-9]{1,3}$' then raise exception 'invalid card stats'; end if;
    kills_ := (x->>'kills')::int; blocks_ := (x->>'blocks')::int;
    if kills_ > 200 or blocks_ > 200 then raise exception 'implausible card stats'; end if;
    kills_ := least(kills_, greatest(0, cap_ - ksum)); ksum := ksum + kills_;
    blocks_ := least(blocks_, 3, greatest(0, cap_ * 2 - bsum)); bsum := bsum + blocks_;
    stats := stats || jsonb_build_object('uid', uid_, 'kills', kills_, 'blocks', blocks_);
   end loop;
   maxmana := case when jsonb_typeof(p_result->'max_mana') = 'number' then (p_result->>'max_mana')::int else null end;
   mana_ := case when jsonb_typeof(p_result->'mana') = 'number' then (p_result->>'mana')::int else null end;
   if maxmana is not null and maxmana >= 0 and mana_ is not null and mana_ >= 0 and mana_ <= maxmana then
    stars_ := 1 + case when mt <= coalesce((cfg->>'starTurns')::int, 10) then 1 else 0 end
     + case when mana_ >= ceil(maxmana * coalesce((cfg->>'starMana')::numeric, 0.3)) then 1 else 0 end;
   elsif maxmana is not null then
    raise exception 'invalid replay';
   end if;
   if coalesce((cfg->>'loseClears')::boolean, false) then stars_ := 3; end if;
   res := public._phase2_old_story_complete_phase(ch, ph, stats);
   insert into public.battle_clear_receipts_v2(user_id, mode, target, session_id, stars)
    values (p_uid, 'story', s.target, s.id, stars_)
    on conflict (user_id, mode, target) do update set stars = greatest(battle_clear_receipts_v2.stars, excluded.stars);
   d := res->'data';
   if stars_ > 0 then
    if jsonb_typeof(d->'stars') is distinct from 'object' then d := jsonb_set(d, '{stars}', '{}'); end if;
    if jsonb_typeof(d->'stars'->ch::text) is distinct from 'object' then d := jsonb_set(d, array['stars', ch::text], '{}'); end if;
    d := jsonb_set(d, array['stars', ch::text, ph::text], to_jsonb(greatest(stars_, coalesce((d->'stars'->ch::text->>ph::text)::int, 0))));
    d := public._story_save(p_uid, d);
    res := res || jsonb_build_object('data', d);
   end if;
   if res->>'reward_id' is not null then
    insert into public.battle_acquisitions_v2(session_id, user_id, card_id) values (s.id, p_uid, res->>'reward_id');
    insert into public.gallery(user_id, card_id, count, mvp_count) values (p_uid, res->>'reward_id', 0, 0) on conflict do nothing;
   end if;
   res := res || jsonb_build_object('stars', stars_, 'chapter_reward', public._story_ticket_sync(p_uid));
  else
   res := public._phase2_old_story_abort_phase();
   res := jsonb_build_object('player', res, 'win', false, 'data', (select data from public.story_progress where user_id = p_uid));
  end if;
 else
  tw := split_part(s.target, ':', 1);
  fl := split_part(s.target, ':', 2)::int;
  if fl < 1 or fl > 350 then raise exception 'boss floor or invalid floor'; end if;
  tp := public._tower_row(p_uid, tw);
  perform public._tower_gate(p_uid, tw, tp);
  if not clear_ then
   res := jsonb_build_object('ok', true, 'win', false, 'cleared', false, 'tower', tw, 'floor', fl, 'best_floor', tp.best_floor, 'reward', '{}'::jsonb, 'currency', '{}'::jsonb);
  else
   if tp.day_floors >= public._tower_daily(tw) then raise exception 'daily limit'; end if;
   if fl > 1 and not public._clear_access_v2(p_uid, 'tower', tw || ':' || (fl - 1)::text) then raise exception 'floor locked'; end if;
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
   res := jsonb_build_object('tower', tw, 'floor', fl, 'best_floor', greatest(tp.best_floor, fl), 'first', first_, 'paid', first_,
    'reward', rw, 'currency', cur, 'tickets', pay->'tickets', 'today', tp.day_floors + 1, 'daily', public._tower_daily(tw));
  end if;
 end if;
 insert into public.battle_events_v2(session_id, user_id, mode, win, skills, day, week)
  values (s.id, p_uid, s.mode, clear_, 0, public._gem_day(), public._weekly_week())
  on conflict (session_id) do update set win = excluded.win, skills = 0;
 res := res || jsonb_build_object('ok', true, 'session', s.id, 'status', 'settled',
  'win', (s.mode = 'tower' and clear_) or (s.mode = 'story' and clear_ and scripted_ is null and win_),
  'cleared', clear_, 'reward_held', false, 'validation', 'replay-v7', 'reason', reason_, 'turns', tr);
 if scripted_ = 'loseClears' then res := res || jsonb_build_object('win', false, 'cleared', true); end if;
 update public.battle_sessions_v2 set status = 'settled', submission = p_result, settlement = res, finished_at = clock_timestamp() where id = s.id;
 return res;
end $$;

revoke all on function public._phase7_replayable(text, text, jsonb), public._phase7_prev_finish_v2(uuid, jsonb),
 public.battle_session_finish_v2(uuid, jsonb), public.battle_direct_session_v7(uuid, uuid),
 public.battle_direct_settle_v7(uuid, uuid, text, jsonb, jsonb) from public, anon, authenticated;

grant execute on function public.battle_session_finish_v2(uuid, jsonb) to authenticated;

do $$ begin
 if exists (select 1 from pg_roles where rolname = 'service_role') then
  revoke all on function public._phase7_prev_finish_v2(uuid, jsonb), public.battle_session_finish_v2(uuid, jsonb),
   public._phase7_replayable(text, text, jsonb), public.battle_direct_session_v7(uuid, uuid),
   public.battle_direct_settle_v7(uuid, uuid, text, jsonb, jsonb) from service_role;
  revoke all on public.battle_replay_policy_v7 from service_role;
  grant execute on function public.battle_direct_session_v7(uuid, uuid), public.battle_direct_settle_v7(uuid, uuid, text, jsonb, jsonb) to service_role;
 end if;
end $$;

select 'phase7 direct replay installed — staging only, switch off, phase6 sweep untouched' as result;

-- ===== REVIEWED NEW SOURCE: story_ch16_17.sql (dropped: cluster guard; staging v7 hash rotation) =====
insert into public.story_phase_config (chapter, phase, type, points, reward_grade, enemy_count) values
  (16,1,'normal',3,null,5), (16,2,'normal',3,null,5), (16,3,'normal',3,null,5), (16,4,'normal',3,null,5),
  (16,5,'normal',3,null,5), (16,6,'normal',3,null,1), (16,7,'normal',3,null,5), (16,8,'normal',3,null,5),
  (16,9,'normal',3,null,5), (16,10,'normal',3,null,5), (16,11,'normal',3,null,6), (16,12,'normal',3,null,0),
  (17,1,'normal',3,null,5), (17,2,'normal',3,null,5), (17,3,'normal',3,null,5), (17,4,'normal',3,null,5),
  (17,5,'normal',3,null,5), (17,6,'normal',3,null,5), (17,7,'normal',3,null,0), (17,8,'normal',3,null,5),
  (17,9,'normal',3,null,5), (17,10,'normal',3,null,5), (17,11,'normal',3,null,5), (17,12,'normal',3,null,0),
  (17,13,'normal',3,null,5), (17,14,'normal',3,null,6), (17,15,'normal',3,null,0)
on conflict (chapter, phase) do update set type = excluded.type, points = excluded.points, reward_grade = excluded.reward_grade, enemy_count = excluded.enemy_count;

create or replace function public.story_complete_scene(p_chapter int, p_phase int) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare
  uid uuid := auth.uid(); d jsonb; cfg public.story_phase_config; cl jsonb; first boolean; prev int;
  need int; lv int; tickets jsonb;
begin
  if uid is null then raise exception 'not signed in'; end if;
  select * into cfg from public.story_phase_config where chapter = p_chapter and phase = p_phase;
  if cfg is null or coalesce(cfg.enemy_count, 0) <> 0 then raise exception 'invalid scene phase'; end if;
  need := public._player_unlock_level('chapter_' || p_chapter);
  begin
    lv := coalesce((public._player_json(uid)->>'level')::int, 1);
  exception when others then lv := 1; end;
  if need is not null and lv < need then raise exception 'level required: level %', need; end if;
  d := public._story_lock(uid);
  cl := coalesce(d->'cleared'->(p_chapter::text), '[]'::jsonb);
  if p_phase > 1 then
    prev := p_phase - 1;
    if not cl @> to_jsonb(prev) then raise exception 'previous phase not cleared'; end if;
  end if;
  first := not cl @> to_jsonb(p_phase);
  if first then
    if d->'cleared' is null or jsonb_typeof(d->'cleared') <> 'object' then d := jsonb_set(d, '{cleared}', '{}'::jsonb); end if;
    d := jsonb_set(d, array['cleared', p_chapter::text], cl || to_jsonb(p_phase));
    d := jsonb_set(d, '{points}', to_jsonb(coalesce((d->>'points')::int, 0) + cfg.points));
  end if;
  d := public._story_save(uid, d);
  begin tickets := public._story_ticket_sync(uid); exception when others then tickets := null; end;
  return jsonb_build_object('data', d, 'first', first, 'points', case when first then cfg.points else 0 end, 'chapter_reward', tickets, 'exp', '[]'::jsonb);
end $$;

revoke all on function public.story_complete_scene(int, int) from public, anon;

grant execute on function public.story_complete_scene(int, int) to authenticated;

do $cat$
begin
  if to_regclass('public.battle_story_defs_v2') is null then
    raise notice 'battle_story_defs_v2 not present; skip ch16/17 catalog';
    return;
  end if;
  execute $s0$insert into public.battle_story_defs_v2(chapter,phase,variant,definition) values
(16,1,'','{"no":1,"type":"normal","enemies":{"ids":["10514","10143","10144","10145","10146"],"boost":{"10143":{"HP":72,"ATK":16,"DEF":12,"storyLv":45,"power":985},"10144":{"HP":72,"ATK":17,"DEF":13,"storyLv":45,"power":1018},"10145":{"HP":86,"ATK":19,"DEF":14,"storyLv":45,"power":1170},"10146":{"HP":101,"ATK":20,"DEF":16,"storyLv":45,"power":1393},"10514":{"HP":113,"ATK":19,"DEF":19,"storyLv":45,"power":3412}}},"party":{"forced":["10406"],"mustLive":["10406"],"levels":{"10406":40},"battleLevels":{"10406":1},"noFemale":true,"maxGrade":"SUPER RARE"},"bossId":"10514","mana":100,"rules":{"maxTurns":20},"hero":"10406","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(16,2,'','{"no":2,"type":"normal","enemies":{"ids":["10147","10143","10144","10145","10146"],"boost":{"10143":{"HP":72,"ATK":16,"DEF":12,"storyLv":45,"power":985},"10144":{"HP":72,"ATK":17,"DEF":13,"storyLv":45,"power":1018},"10145":{"HP":86,"ATK":19,"DEF":14,"storyLv":45,"power":1170},"10146":{"HP":101,"ATK":20,"DEF":16,"storyLv":45,"power":1393},"10147":{"HP":115,"ATK":22,"DEF":17,"storyLv":45,"power":1553}}},"party":{"forced":["10406"],"mustLive":["10406"],"levels":{"10406":40},"battleLevels":{"10406":1},"noFemale":true,"maxGrade":"SUPER RARE"},"bossId":"10147","mana":100,"rules":{"maxTurns":20},"hero":"10406","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(16,3,'','{"no":3,"type":"normal","enemies":{"ids":["10155","10154","10155","10143","10144"],"boost":{"10143":{"HP":72,"ATK":16,"DEF":12,"storyLv":45,"power":985},"10144":{"HP":72,"ATK":17,"DEF":13,"storyLv":45,"power":1018},"10154":{"HP":101,"ATK":16,"DEF":12,"storyLv":45,"power":1257},"10155":{"HP":115,"ATK":17,"DEF":13,"storyLv":45,"power":1399}}},"party":{"forced":["10406"],"mustLive":["10406"],"levels":{"10406":40},"battleLevels":{"10406":1},"noFemale":true,"maxGrade":"SUPER RARE"},"bossId":"10155","mana":100,"rules":{"maxTurns":20},"hero":"10406","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(16,4,'','{"no":4,"type":"normal","enemies":{"ids":["10157","10145","10146","10156","10152"],"boost":{"10145":{"HP":86,"ATK":19,"DEF":14,"storyLv":45,"power":1170},"10146":{"HP":101,"ATK":20,"DEF":16,"storyLv":45,"power":1393},"10152":{"HP":534,"ATK":104,"DEF":104,"storyLv":45,"power":34342},"10156":{"HP":130,"ATK":19,"DEF":14,"storyLv":45,"power":1664},"10157":{"HP":144,"ATK":20,"DEF":16,"storyLv":45,"power":1831}}},"party":{"forced":["10406"],"mustLive":["10406"],"levels":{"10406":40},"battleLevels":{"10406":1},"noFemale":true,"maxGrade":"SUPER RARE"},"bossId":"10157","mana":100,"rules":{"maxTurns":20},"hero":"10406","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(16,5,'','{"no":5,"type":"normal","enemies":{"ids":["10158","10159","10160","10147","10148"],"boost":{"10147":{"HP":115,"ATK":22,"DEF":17,"storyLv":45,"power":1553},"10148":{"HP":169,"ATK":28,"DEF":19,"storyLv":45,"power":5275},"10158":{"HP":144,"ATK":22,"DEF":22,"storyLv":45,"power":1969},"10159":{"HP":188,"ATK":38,"DEF":30,"storyLv":45,"power":6526},"10160":{"HP":226,"ATK":47,"DEF":39,"storyLv":45,"power":8019}}},"party":{"forced":["10406"],"mustLive":["10406"],"levels":{"10406":40},"battleLevels":{"10406":1},"noFemale":true,"maxGrade":"SUPER RARE"},"bossId":"10158","mana":100,"rules":{"maxTurns":20},"hero":"10406","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(16,6,'','{"no":6,"type":"normal","enemies":{"ids":["10383"],"boost":{"10383":{"HP":966,"ATK":124,"DEF":138,"storyLv":45,"power":116253}}},"party":{"forced":["10123","10025","10183"],"mustLive":["10123","10025","10183"],"levels":{"10025":50,"10123":50,"10183":50},"battleLevels":{"10025":1,"10123":1,"10183":1},"solo":true},"bossId":"10383","mana":200,"rules":{"maxTurns":20},"hero":"10406","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(16,7,'','{"no":7,"type":"normal","enemies":{"ids":["10150","10149","10145","10144","10143"],"boost":{"10143":{"HP":72,"ATK":16,"DEF":12,"storyLv":45,"power":985},"10144":{"HP":72,"ATK":17,"DEF":13,"storyLv":45,"power":1018},"10145":{"HP":86,"ATK":19,"DEF":14,"storyLv":45,"power":1170},"10149":{"HP":207,"ATK":38,"DEF":28,"storyLv":45,"power":7240},"10150":{"HP":282,"ATK":56,"DEF":47,"storyLv":45,"power":10434}}},"party":{"forced":["10406"],"mustLive":["10406"],"levels":{"10406":40},"battleLevels":{"10406":1},"noFemale":true,"maxGrade":"SUPER RARE"},"bossId":"10150","mana":100,"rules":{"maxTurns":20},"hero":"10406","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(16,8,'','{"no":8,"type":"normal","enemies":{"ids":["10151","10161","10162","10163","10164"],"boost":{"10151":{"HP":464,"ATK":70,"DEF":70,"storyLv":45,"power":25251},"10161":{"HP":244,"ATK":51,"DEF":43,"storyLv":45,"power":9248},"10162":{"HP":282,"ATK":56,"DEF":49,"storyLv":45,"power":10515},"10163":{"HP":418,"ATK":70,"DEF":60,"storyLv":45,"power":23092},"10164":{"HP":441,"ATK":70,"DEF":60,"storyLv":45,"power":23844}}},"party":{"forced":["10406"],"mustLive":["10406"],"levels":{"10406":40},"battleLevels":{"10406":1},"noFemale":true,"maxGrade":"SUPER RARE"},"bossId":"10151","mana":100,"rules":{"maxTurns":20},"hero":"10406","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(16,9,'','{"no":9,"type":"normal","enemies":{"ids":["10152","10146","10165","10166","10167"],"boost":{"10146":{"HP":101,"ATK":20,"DEF":16,"storyLv":45,"power":1393},"10152":{"HP":534,"ATK":104,"DEF":104,"storyLv":45,"power":34342},"10165":{"HP":464,"ATK":70,"DEF":70,"storyLv":45,"power":25251},"10166":{"HP":487,"ATK":81,"DEF":81,"storyLv":45,"power":27586},"10167":{"HP":534,"ATK":93,"DEF":93,"storyLv":45,"power":30851}}},"party":{"forced":["10406"],"mustLive":["10406"],"levels":{"10406":40},"battleLevels":{"10406":1},"noFemale":true,"maxGrade":"SUPER RARE"},"bossId":"10152","mana":100,"rules":{"maxTurns":20},"hero":"10406","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(16,10,'','{"no":10,"type":"normal","enemies":{"ids":["10025","10143","10144","10153","10154"],"boost":{"10025":{"HP":966,"ATK":152,"DEF":179,"storyLv":45,"power":85539},"10143":{"HP":72,"ATK":16,"DEF":12,"storyLv":45,"power":985},"10144":{"HP":72,"ATK":17,"DEF":13,"storyLv":45,"power":1018},"10153":{"HP":86,"ATK":14,"DEF":10,"storyLv":45,"power":1074},"10154":{"HP":101,"ATK":16,"DEF":12,"storyLv":45,"power":1257}},"levels":{"10025":2,"10143":2,"10144":2,"10153":2,"10154":2}},"party":{"forced":["10406"],"mustLive":["10406"],"levels":{"10406":40},"battleLevels":{"10406":1},"noFemale":true,"maxGrade":"SUPER RARE"},"bossId":"10025","mana":100,"rules":{"maxTurns":20},"hero":"10406","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(16,11,'','{"no":11,"type":"normal","enemies":{"ids":["10406","10290","10383","10097","10393","10306"],"boost":{"10097":{"HP":235,"ATK":30,"DEF":56,"storyLv":45,"power":10455},"10290":{"HP":179,"ATK":19,"DEF":21,"storyLv":45,"power":7682},"10306":{"HP":179,"ATK":30,"DEF":34,"storyLv":45,"power":7943},"10383":{"HP":966,"ATK":124,"DEF":138,"storyLv":45,"power":116253},"10393":{"HP":499,"ATK":70,"DEF":81,"storyLv":45,"power":38466},"10406":{"HP":580,"ATK":81,"DEF":81,"storyLv":45,"power":38309}}},"party":{"forced":["10200"],"mustLive":["10200"],"levels":{"10200":60},"battleLevels":{"10200":1},"noFemale":true},"bossId":"10406","mana":200,"rules":{"maxTurns":20,"revive":[{"id":"10290","become":"10291","delay":0,"storyLevel":100,"battleLevel":10}]},"hero":"10406","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(16,12,'','{"no":12,"type":"normal","hero":"10406","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none","party":{"forced":["10406"]}}'::jsonb),
(17,1,'','{"no":1,"type":"normal","enemies":{"ids":["10147","10146","10145","10144","10143"],"boost":{"10143":{"HP":70,"ATK":15,"DEF":11,"storyLv":40,"power":938},"10144":{"HP":70,"ATK":17,"DEF":13,"storyLv":40,"power":1003},"10145":{"HP":83,"ATK":18,"DEF":14,"storyLv":40,"power":1131},"10146":{"HP":97,"ATK":19,"DEF":15,"storyLv":40,"power":1328},"10147":{"HP":111,"ATK":21,"DEF":17,"storyLv":40,"power":1503}}},"party":{"forced":["10307"],"mustLive":["10307"],"levels":{"10307":45},"battleLevels":{"10307":1},"noMale":true,"maxGrade":"SUPER RARE"},"bossId":"10147","mana":100,"rules":{"maxTurns":20},"hero":"10307","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(17,2,'','{"no":2,"type":"normal","enemies":{"ids":["10152","10149","10148","10160","10146"],"boost":{"10146":{"HP":97,"ATK":19,"DEF":15,"storyLv":40,"power":1328},"10148":{"HP":160,"ATK":27,"DEF":18,"storyLv":40,"power":5017},"10149":{"HP":196,"ATK":36,"DEF":27,"storyLv":40,"power":6877},"10152":{"HP":499,"ATK":98,"DEF":98,"storyLv":40,"power":32215},"10160":{"HP":214,"ATK":44,"DEF":37,"storyLv":40,"power":7573}}},"party":{"forced":["10307"],"mustLive":["10307"],"levels":{"10307":45},"battleLevels":{"10307":1},"noMale":true,"maxGrade":"SUPER RARE"},"bossId":"10152","mana":100,"rules":{"maxTurns":20},"hero":"10307","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(17,3,'','{"no":3,"type":"normal","enemies":{"ids":["10025","10152","10152","10152","10152"],"boost":{"10025":{"HP":896,"ATK":141,"DEF":166,"storyLv":40,"power":79339},"10152":{"HP":499,"ATK":98,"DEF":98,"storyLv":40,"power":32215}}},"party":{"forced":["10307"],"mustLive":["10307"],"levels":{"10307":45},"battleLevels":{"10307":1},"noMale":true},"bossId":"10025","mana":100,"rules":{"maxTurns":20},"hero":"10307","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(17,4,'','{"no":4,"type":"normal","enemies":{"ids":["10158","10157","10156","10155","10154"],"boost":{"10154":{"HP":97,"ATK":15,"DEF":11,"storyLv":40,"power":1192},"10155":{"HP":111,"ATK":17,"DEF":13,"storyLv":40,"power":1368},"10156":{"HP":125,"ATK":18,"DEF":14,"storyLv":40,"power":1604},"10157":{"HP":139,"ATK":19,"DEF":15,"storyLv":40,"power":1754},"10158":{"HP":139,"ATK":21,"DEF":21,"storyLv":40,"power":1892}}},"party":{"forced":["10307"],"mustLive":["10307"],"levels":{"10307":45},"battleLevels":{"10307":1},"maxGrade":"HIGH RARE"},"bossId":"10158","mana":100,"rules":{"maxTurns":20},"hero":"10307","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(17,5,'','{"no":5,"type":"normal","enemies":{"ids":["10158","10149","10147","10146","10153"],"boost":{"10146":{"HP":97,"ATK":19,"DEF":15,"storyLv":40,"power":1328},"10147":{"HP":111,"ATK":21,"DEF":17,"storyLv":40,"power":1503},"10149":{"HP":196,"ATK":36,"DEF":27,"storyLv":40,"power":6877},"10153":{"HP":83,"ATK":14,"DEF":10,"storyLv":40,"power":1051},"10158":{"HP":139,"ATK":21,"DEF":21,"storyLv":40,"power":1892}}},"party":{"forced":["10307"],"mustLive":["10307"],"levels":{"10307":45},"battleLevels":{"10307":1},"maxGrade":"HIGH RARE"},"bossId":"10158","mana":100,"rules":{"maxTurns":20},"hero":"10307","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(17,6,'','{"no":6,"type":"normal","enemies":{"ids":["10161","10149","10149","10149","10149"],"boost":{"10149":{"HP":196,"ATK":36,"DEF":27,"storyLv":40,"power":6877},"10161":{"HP":231,"ATK":48,"DEF":41,"storyLv":40,"power":8753}}},"party":{"forced":["10307"],"mustLive":["10307"],"levels":{"10307":45},"battleLevels":{"10307":1},"maxGrade":"HIGH RARE"},"bossId":"10161","mana":100,"rules":{"maxTurns":20},"hero":"10307","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(17,7,'','{"no":7,"type":"normal","hero":"10307","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none","party":{"forced":["10307"]}}'::jsonb),
(17,8,'','{"no":8,"type":"normal","enemies":{"ids":["10025","10164","10164","10164","10164"],"boost":{"10025":{"HP":896,"ATK":141,"DEF":166,"storyLv":40,"power":79339},"10164":{"HP":412,"ATK":65,"DEF":56,"storyLv":40,"power":22242}}},"party":{"forced":["10307"],"mustLive":["10307"],"levels":{"10307":45},"battleLevels":{"10307":1},"maxGrade":"SUPER RARE"},"bossId":"10025","mana":100,"rules":{"maxTurns":20},"hero":"10307","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(17,9,'','{"no":9,"type":"normal","enemies":{"ids":["10166","10166","10166","10166","10166"],"boost":{"10166":{"HP":456,"ATK":76,"DEF":76,"storyLv":40,"power":25853}}},"party":{"forced":["10307"],"mustLive":["10307"],"levels":{"10307":45},"battleLevels":{"10307":1},"maxGrade":"HIGH RARE"},"bossId":"10166","mana":100,"rules":{"maxTurns":20},"hero":"10307","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(17,10,'','{"no":10,"type":"normal","enemies":{"ids":["10025","10166","10166","10166","10166"],"boost":{"10025":{"HP":966,"ATK":152,"DEF":179,"storyLv":45,"power":85539},"10166":{"HP":487,"ATK":81,"DEF":81,"storyLv":45,"power":27586}}},"party":{"forced":["10307"],"mustLive":["10307"],"levels":{"10307":45},"battleLevels":{"10307":1},"maxGrade":"HIGH RARE"},"bossId":"10025","mana":100,"rules":{"maxTurns":20},"hero":"10307","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(17,11,'','{"no":11,"type":"normal","enemies":{"ids":["10025","10166","10166","10166","10166"],"boost":{"10025":{"HP":966,"ATK":152,"DEF":179,"storyLv":45,"power":85539},"10166":{"HP":487,"ATK":81,"DEF":81,"storyLv":45,"power":27586}}},"party":{"forced":["10307"],"mustLive":["10307"],"levels":{"10307":45},"battleLevels":{"10307":1},"maxGrade":"HIGH RARE"},"bossId":"10025","mana":100,"rules":{"maxTurns":20},"hero":"10307","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(17,12,'','{"no":12,"type":"normal","hero":"10307","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none","party":{"forced":["10307"]}}'::jsonb),
(17,13,'','{"no":13,"type":"normal","enemies":{"ids":["10200","10025","10151","10151","10151"],"boost":{"10025":{"HP":1036,"ATK":163,"DEF":192,"storyLv":50,"power":91739},"10151":{"HP":494,"ATK":74,"DEF":74,"storyLv":50,"power":26808},"10200":{"HP":1140,"ATK":207,"DEF":104,"storyLv":50,"power":98609}}},"party":{"forced":["10307"],"mustLive":["10307"],"levels":{"10307":45},"battleLevels":{"10307":1},"maxGrade":"SUPER RARE"},"bossId":"10200","mana":100,"rules":{"maxTurns":20},"hero":"10307","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(17,14,'','{"no":14,"type":"normal","enemies":{"ids":["10200","10025","10151","10151","10151","10151"],"boost":{"10025":{"HP":1036,"ATK":163,"DEF":192,"storyLv":50,"power":91739},"10151":{"HP":494,"ATK":74,"DEF":74,"storyLv":50,"power":26808},"10200":{"HP":1140,"ATK":207,"DEF":104,"storyLv":50,"power":98609}}},"party":{"forced":["10307"],"mustLive":["10311"],"levels":{"10307":45},"battleLevels":{"10307":1},"solo":true},"bossId":"10200","enemyFirst":true,"mana":200,"rules":{"maxTurns":20},"awaken":{"on":"10307","id":"10311","storyLevel":50,"battleLevel":1},"hero":"10307","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(17,15,'','{"no":15,"type":"normal","hero":"10307","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none","party":{"forced":["10307"]}}'::jsonb)
on conflict (chapter,phase,variant) do update set definition=excluded.definition;$s0$;
end $cat$;

-- ===== FINAL-STATE FUNCTIONS: 10 changed/new (pg_get_functiondef of reviewed staging target) =====
CREATE OR REPLACE FUNCTION public._daily_defs()
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
AS $function$ select '[
  {"key":"arcade","name":"아케이드 플레이 x 1","goal":1,"per":1,"reward":{"gold":1000}},
  {"key":"win","name":"전투 승리 x 3","goal":3,"per":1,"reward":{"gold":2000}},
  {"key":"story","name":"스토리 스테이지 클리어 x 2","goal":2,"per":1,"reward":{"gold":2000,"gem":10}},
  {"key":"tower","name":"시련의 탑 도전 x 1","goal":1,"per":1,"reward":{"gold":1500,"gem":10}},
  {"key":"skill","name":"고유기술 사용 x 10","goal":10,"per":20,"reward":{"gold":1500}}
]'::jsonb $function$;

CREATE OR REPLACE FUNCTION public._drink_json(p_uid uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r player_items; w player_wallet;
begin
  select * into r from player_items where user_id = p_uid and item = 'drink';
  select * into w from player_wallet where user_id = p_uid;
  return jsonb_build_object('ok', true, 'tradable', coalesce(r.tradable, 0), 'bound', coalesce(r.bound, 0), 'locked', coalesce(r.locked, 0),
    'total', coalesce(r.tradable, 0) + coalesce(r.bound, 0), 'paid_gem', coalesce(w.gem_paid, 0), 'free_gem', coalesce(w.gem_free, 0),
    'per', _drink_cfg('stamina_per'), 'cap', _drink_cfg('stamina_cap'),
    'shop', (select coalesce(jsonb_agg(jsonb_build_object('sku', sku, 'qty', qty, 'price', price) order by ord), '[]'::jsonb) from drink_shop where active));
end $function$;

CREATE OR REPLACE FUNCTION public._dsp_fill(p_uid uuid, p_all boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare best int; s int; z text; els text[] := array['WIND','FIRE','ICE','DARK','LIGHT']; cl text[] := array['CHARGE','CRUSH','DEFENSE','SUPPORT','DISTURB','FASCINATION'];
begin
  select coalesce(max(m.grade), 0) into best from jsonb_array_elements(_dsp_owned(p_uid)) o join dispatch_card_meta m on m.id = o->>'id' where m.grade <= 4;
  if p_all then delete from dispatch_offers where user_id = p_uid; end if;
  for s in 1..6 loop
    if not p_all and exists (select 1 from dispatch_offers where user_id = p_uid and slot = s and taken) then continue; end if;
    -- 높은 단계일수록 조금 더 자주 (ord 가중치)
    select id into z from dispatch_zones where grp = case when s <= 4 then 'exile' else 'safe' end and min_grade <= best
      order by -ln(greatest(random(), 1e-9)) / (1 + min_grade) limit 1;
    insert into dispatch_offers (user_id, slot, day, zone, el, cls, taken) values (p_uid, s, _dsp_day(), z, els[1 + floor(random() * 5)::int], cl[1 + floor(random() * 6)::int], false)
      on conflict (user_id, slot) do update set day = excluded.day, zone = excluded.zone, el = excluded.el, cls = excluded.cls, taken = false
      where dispatch_offers.taken = false;
  end loop;
end $function$;

CREATE OR REPLACE FUNCTION public._pvp_rating_v3(u uuid, l text, m text, s date)
 RETURNS pvp_ratings_v3
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$ declare r public.pvp_ratings_v3; p public.pvp_ratings_v3; begin
 select * into p from public.pvp_ratings_v3 where user_id=u and league=l and mode=m and season<s order by season desc limit 1;
 insert into public.pvp_ratings_v3(user_id,league,mode,season,rating,wins,losses,def_wins,def_losses)
  values(u,l,m,s,coalesce(p.rating,1000),coalesce(p.wins,0),coalesce(p.losses,0),coalesce(p.def_wins,0),coalesce(p.def_losses,0))
  on conflict do nothing;
 select * into r from public.pvp_ratings_v3 where user_id=u and league=l and mode=m and season=s; return r;
end $function$;

CREATE OR REPLACE FUNCTION public._unlock_intros()
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
AS $function$select '[{"key": "ch0", "text": "🎟️ 프리미엄 10회 소환 오픈", "level": 1, "route": "summon", "title": "프리미엄 소환", "reward": {}, "trigger": "ch0", "source_text": "챕터0 클리어- 소환(프리미엄) 10회"}, {"key": "leader", "text": "리더 레벨업 (+1 / +10)", "level": 1, "route": "cards", "title": "인재 레벨업", "reward": {"gold": 5000, "blood": 5000}, "trigger": "1:1", "source_text": "ch1 P1클리어- 지급된 리더 레벨업. lv1업, lv10업"}, {"key": "deck", "text": "🗂 덱 설정 오픈", "level": 1, "route": "decks", "title": "덱 설정", "reward": {"gold": 5000}, "trigger": "1:3", "source_text": "ch1 p3클리어- 덱 설정 및 방법 설명"}, {"key": "pvp_hr", "text": "⚔️ HR 이하 1대1 리그 오픈", "level": 3, "route": "pvp", "title": "PvP · 장비 가방", "reward": {"gold": 5000}, "trigger": "", "source_text": "pvp덱배치 및 다른 pvp설명."}, {"key": "dispatch", "text": "🧭 파견 오픈 · 시간 지나면 보상", "level": 5, "route": "dispatch", "title": "파견", "reward": {"gold": 5000}, "trigger": "", "source_text": "레벨5 되면 파견 설명 및 실행"}, {"key": "guild", "text": "조직 오픈 · 가입/창설", "level": 6, "route": "guild", "title": "조직", "reward": {"gold": 5000, "boxes": 2}, "trigger": "", "source_text": "레벨6 되면 조직 가입 또는 창설 설명"}, {"key": "friends", "text": "👥 친구 오픈 · 🎁 행동력 선물", "level": 8, "route": "friends", "title": "친구 · 선물", "reward": {}, "trigger": "", "source_text": "친구를 추가하고 행동력 선물을 주고받을 수 있어요."}, {"key": "tower", "text": "🗼 시련의 탑 오픈", "level": 10, "route": "tower", "title": "시련의 탑", "reward": {"gold": 5000, "boxes": 2}, "trigger": "", "source_text": "시련의탑 설명, 강제 실행(일반+소탕)"}, {"key": "raid", "text": "🐉 토벌 오픈", "level": 11, "route": "raid", "title": "토벌", "reward": {"tickets": 10}, "trigger": "", "source_text": "토벌 방법 및 내용 설명, 시행(길드 가입자 한정)"}, {"key": "camp", "text": "🏋️ 훈련소 오픈 · 맡기면 EXP", "level": 12, "route": "camp", "title": "훈련소", "reward": {"gold": 5000, "boxes": 2}, "trigger": "", "source_text": "훈련소 설명 및 강제 배정(가장 레벨 낮은 캐릭터)"}, {"key": "skill", "text": "EX 합성 · 스킬 강화 · 대여 오픈", "level": 13, "route": "cards", "title": "EX 합성 · 스킬 강화 · 대여", "reward": {"gold": 5000, "soul": 1000}, "trigger": "", "source_text": "스킬 강화 방법 알려줌"}, {"key": "sigil", "text": "증표 오픈 · 📬 선택 상자", "level": 14, "route": "cards", "title": "증표", "reward": {"sigil_boxes": 10}, "trigger": "", "source_text": "증표 설명"}, {"key": "trade", "text": "무제한 1대1 · 거래소 오픈 (가입 7일 후)", "level": 15, "route": "trade", "title": "무제한 1대1 · 거래소", "reward": {"tickets": 10}, "trigger": "", "source_text": "거래소 설명 및 방법"}, {"key": "pvp_3v3", "text": "3대3 리그 오픈", "level": 17, "route": "pvp", "title": "3대3 리그", "reward": {}, "trigger": "", "source_text": "세 덱으로 겨루는 3대3 리그가 열렸어요. 두 리그에서 모두 도전할 수 있어요."}, {"key": "war", "text": "🏴 구역 전쟁 오픈", "level": 18, "route": "war", "title": "조직전", "reward": {}, "trigger": "", "source_text": "조직원들과 방어 덱을 배치하고 상대 조직에 도전해 보세요."}, {"key": "pvp_boss", "text": "👑 보스 리그 오픈", "level": 20, "route": "pvp", "title": "보스 리그", "reward": {}, "trigger": "", "source_text": "진영 보스를 지키는 보스 리그가 열렸어요. 두 리그에서 모두 도전할 수 있어요."}, {"key": "facilities", "text": "⚒️ 연마소 · 🥋 도장 오픈", "level": 20, "route": "camp", "title": "연마소 · 도장", "reward": {"gold": 5000}, "trigger": "", "source_text": "연마소, 도장 설명"}, {"key": "attr25", "text": "속성 탑 3곳 오픈 · 요일별", "level": 25, "route": "tower", "title": "바람 · 얼음 · 불의 탑", "reward": {}, "trigger": "", "source_text": "같은 속성 인재로 도전하는 세 탑이 열렸어요. 각 탑의 개방 요일에 도전해 보세요."}, {"key": "attr40", "text": "빛·어둠 탑 오픈 · 요일별", "level": 40, "route": "tower", "title": "빛의 섬 · 어둠의 늪", "reward": {}, "trigger": "", "source_text": "빛과 어둠의 인재를 위한 두 탑이 열렸어요. 각 탑의 개방 요일에 도전해 보세요."}]'::jsonb$function$;

CREATE OR REPLACE FUNCTION public._weekly_defs()
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
AS $function$ select '[
  {"key":"arcade","name":"아케이드 플레이 x 7","goal":7,"per":2,"reward":{"gold":8000,"tickets":1}},
  {"key":"win","name":"전투 승리 x 15","goal":15,"per":3,"reward":{"gold":10000,"gem":30}},
  {"key":"story","name":"스토리 스테이지 클리어 x 10","goal":10,"per":2,"reward":{"gold":10000,"gem":30}},
  {"key":"tower","name":"시련의 탑 도전 x 5","goal":5,"per":1,"reward":{"gold":8000,"gem":20}},
  {"key":"skill","name":"고유기술 사용 x 50","goal":50,"per":40,"reward":{"gold":8000,"gem":20}}
]'::jsonb $function$;

CREATE OR REPLACE FUNCTION public.dispatch_start(p_slot integer, p_uids text[], p_hours integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare uid uuid := auth.uid(); o dispatch_offers; z dispatch_zones; owned jsonb; n int; mx int; bon int := 0; ne int; nc int; over boolean; k text; v numeric; rw jsonb := '{}'::jsonb; f numeric; great boolean := false; cnt int; d dispatch_daily;
begin
 -- unlock-policy-v1
 perform public._unlock_require('dispatch');

  if uid is null then raise exception 'login required'; end if;
  if p_hours not in (1, 4, 8, 12) then raise exception 'bad hours'; end if;
  perform pg_advisory_xact_lock(hashtext('dsp:' || uid::text));
  select * into o from dispatch_offers where user_id = uid and slot = p_slot for update;
  if o.user_id is null or o.day <> _dsp_day() then raise exception 'no offer'; end if;
  if o.taken then raise exception 'taken'; end if;
  select * into z from dispatch_zones where id = o.zone;
  if (select count(*) from dispatch_runs where user_id = uid and claimed_at is null) >= _dsp_slots(_dsp_level(uid)) then raise exception 'slots full'; end if;
  select * into d from dispatch_daily where user_id = uid and day = _dsp_day();
  if coalesce(d.starts, 0) >= _dsp_cap() then raise exception 'daily cap'; end if;
  n := coalesce(array_length(p_uids, 1), 0);
  if n < 1 or n > z.size or (select count(distinct u) from unnest(p_uids) u) <> n then raise exception 'bad cards'; end if;
  owned := _dsp_owned(uid);
  create temp table if not exists _dsp_pick (uid text, id text, grade int, el text, cls text) on commit drop; delete from _dsp_pick where true;
  insert into _dsp_pick select u, ox.x->>'id', m.grade, m.el, m.cls from unnest(p_uids) u
    join lateral (select x from jsonb_array_elements(owned) x where x->>'uid' = u limit 1) ox on true
    join dispatch_card_meta m on m.id = ox.x->>'id';
  if (select count(*) from _dsp_pick) <> n then raise exception 'not owned'; end if;
  if (select count(*) from _dsp_pick) <> (select count(distinct id) from _dsp_pick) then raise exception 'duplicate card'; end if;
  if exists (select 1 from dispatch_runs r where r.user_id = uid and r.claimed_at is null and r.uids && p_uids) then raise exception 'busy'; end if;
  -- 이미 파견 나간 인재(같은 카드 id, 다른 사본)도 막음
  if exists (
    select 1 from dispatch_runs r, unnest(r.uids) ru
      join lateral (select x->>'id' as id from jsonb_array_elements(owned) x where x->>'uid' = ru limit 1) ox on true
      join _dsp_pick p on p.id = ox.id
    where r.user_id = uid and r.claimed_at is null
  ) then raise exception 'busy'; end if;
  if exists (select 1 from _dsp_pick where grade >= 5) then raise exception 'banned grade'; end if;
  select max(grade) into mx from _dsp_pick;
  if mx < z.min_grade then raise exception 'need grade'; end if;
  select count(*) filter (where el = o.el), count(*) filter (where cls = o.cls) into ne, nc from _dsp_pick;
  bon := least(60, 15 * (ne + nc)) + case when mx > z.min_grade then 10 else 0 end;
  great := least(60, 15 * (ne + nc)) >= 60 and random() < 0.10;
  f := _dsp_mult(p_hours) * (1 + bon / 100.0) * case when great then 2 else 1 end;
  for k, v in select key, value::numeric from jsonb_each_text(z.rw) loop
    v := v * f; cnt := floor(v)::int + case when random() < v - floor(v) then 1 else 0 end;
    if cnt > 0 then rw := rw || jsonb_build_object(k, cnt); end if;
  end loop;
  update dispatch_offers set taken = true where user_id = uid and slot = p_slot;
  insert into dispatch_daily (user_id, day, starts) values (uid, _dsp_day(), 1) on conflict (user_id, day) do update set starts = dispatch_daily.starts + 1;
  insert into dispatch_runs (user_id, zone, el, cls, hours, uids, bonus, great, reward, ends_at)
    values (uid, z.id, o.el, o.cls, p_hours, p_uids, bon, great, rw, now() + make_interval(hours => p_hours));
  return _dsp_json(uid);
end $function$;

CREATE OR REPLACE FUNCTION public.drink_buy(p_sku text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare uid uuid := auth.uid(); s drink_shop; g jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('gem:' || uid::text));
  select * into s from drink_shop where sku = p_sku and active;
  if s.sku is null then raise exception 'invalid item'; end if;
  insert into player_wallet (user_id) values (uid) on conflict (user_id) do nothing;
  g := _gem_spend(uid, s.price, 'buy:' || s.sku, jsonb_build_object('qty', s.qty, 'price', s.price));
  perform _item_add(uid, 'drink', s.qty, 0, 'buy:' || s.sku, null, jsonb_build_object('price', s.price));
  return _drink_json(uid) || jsonb_build_object('gem', g, 'bought', s.qty);
end $function$;

CREATE OR REPLACE FUNCTION public.pvp_rankings(p_league text, p_mode text, p_season date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare uid uuid := auth.uid(); s date := p_season; top jsonb; mine jsonb;
begin
  perform _pvp_ok(p_league, p_mode);
  with latest as (
    select distinct on (r.user_id) r.user_id, r.rating, r.wins, r.losses
      from pvp_ratings_v3 r
     where r.league = p_league and r.mode = p_mode and (s is null or r.season = s) and r.games_verified > 0
     order by r.user_id, r.season desc),
  t as (select user_id, rating, wins, losses, rank() over (order by rating desc, wins desc) rk from latest)
  select coalesce(jsonb_agg(jsonb_build_object('rank', rk, 'name', coalesce(p.nickname, '플레이어'), 'rating', rating, 'wins', wins, 'losses', losses,
           'me', t.user_id = uid, 'tier', _pvp_tier(rating),
           'abyss', exists (select 1 from pvp_titles x where x.user_id = t.user_id and x.title = 'abyss'),
           'title', coalesce(p.cosmo_title, 'recruit'), 'frame', coalesce(p.cosmo_frame, 'frame_basic'),
           'title_name', coalesce((select d->>'name' from jsonb_array_elements(_cosmo_title_defs()) d where d->>'id' = coalesce(p.cosmo_title, 'recruit')), '')) order by rk), '[]'::jsonb)
    into top from (select * from t order by rk limit 100) t left join profiles p on p.id = t.user_id;
  with latest as (
    select distinct on (r.user_id) r.user_id, r.rating, r.wins, r.losses
      from pvp_ratings_v3 r
     where r.league = p_league and r.mode = p_mode and (s is null or r.season = s) and r.games_verified > 0
     order by r.user_id, r.season desc),
  t as (select user_id, rating, wins, losses, rank() over (order by rating desc, wins desc) rk from latest)
  select jsonb_build_object('rank', rk, 'rating', rating, 'wins', wins, 'losses', losses, 'tier', _pvp_tier(rating)) into mine from t where t.user_id = uid;
  return jsonb_build_object('season', coalesce(s, _pvp_season()), 'top', top, 'me', mine);
end $function$;

CREATE OR REPLACE FUNCTION public.pvp_user_info(p_league text, p_mode text, p_rank integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare uid uuid := auth.uid(); t uuid; g record; deck jsonb; lead text;
begin
  if uid is null then raise exception 'login required' using errcode = '42501'; end if;
  perform _pvp_ok(p_league, p_mode);
  if p_rank is null or p_rank < 1 or p_rank > 100 then raise exception 'bad rank'; end if;
  select x.user_id into t from (
    select user_id, row_number() over (order by rating desc, wins desc, user_id) rn from (
      select distinct on (r.user_id) r.user_id, r.rating, r.wins, r.losses
        from pvp_ratings_v3 r
       where r.league = p_league and r.mode = p_mode and r.games_verified > 0
       order by r.user_id, r.season desc) z) x where x.rn = p_rank;
  if t is null then raise exception 'not found'; end if;
  select o->>'id' into lead from story_progress sp, jsonb_array_elements(case when jsonb_typeof(sp.data->'owned') = 'array' then sp.data->'owned' else '[]'::jsonb end) o
    where sp.user_id = t and o->>'uid' = sp.data->>'leader' limit 1;
  select coalesce(jsonb_agg(jsonb_build_object('slot', d.slot, 'cards',
      (select coalesce(jsonb_agg(jsonb_build_object('id', c->>'id', 'level', coalesce((c->>'level')::int, 1))), '[]'::jsonb)
         from jsonb_array_elements(case when jsonb_typeof(d.snap->'cards') = 'array' then d.snap->'cards' when jsonb_typeof(d.snap) = 'array' then d.snap else '[]'::jsonb end) c)) order by d.slot), '[]'::jsonb)
    into deck from pvp_decks d where d.user_id = t and d.league = p_league and d.mode = p_mode;
  select gg.name, gg.emblem into g from guild_members m join guilds gg on gg.id = m.guild_id where m.user_id = t;
  return jsonb_build_object('ok', true, 'rank', p_rank, 'me', t = uid,
    'name', coalesce((select nickname from profiles where id = t), '플레이어'),
    'level', coalesce((select level from player_state where user_id = t), 1),
    'leader', lead, 'decks', deck,
    'guild', case when g.name is null then null else jsonb_build_object('name', g.name, 'emblem', g.emblem) end);
end $function$;

-- ===== EXECUTE GRANTS for every changed function (Supabase default privileges are not trusted) =====
revoke all on function _daily_defs() from public, anon, authenticated, service_role;
revoke all on function _drink_json(uuid) from public, anon, authenticated, service_role;
revoke all on function _dsp_fill(uuid,boolean) from public, anon, authenticated, service_role;
revoke all on function _pvp_rating_v3(uuid,text,text,date) from public, anon, authenticated, service_role;
revoke all on function _unlock_intros() from public, anon, authenticated, service_role;
grant execute on function _unlock_intros() to service_role;
revoke all on function _weekly_defs() from public, anon, authenticated, service_role;
revoke all on function dispatch_start(integer,text[],integer) from public, anon, authenticated, service_role;
grant execute on function dispatch_start(integer,text[],integer) to authenticated, service_role;
revoke all on function drink_buy(text) from public, anon, authenticated, service_role;
grant execute on function drink_buy(text) to authenticated, service_role;
revoke all on function pvp_rankings(text,text,date) from public, anon, authenticated, service_role;
grant execute on function pvp_rankings(text,text,date) to authenticated, anon;
revoke all on function pvp_user_info(text,text,integer) from public, anon, authenticated, service_role;
grant execute on function pvp_user_info(text,text,integer) to authenticated;

-- ===== CONFIG ROWS: 126 (new rows insert-only; existing rows update only changed columns) =====
update arcade_policy_v5 set engine_hash=r.engine_hash from jsonb_populate_record(null::arcade_policy_v5, '{"enabled":true,"engine_hash":"7c47d4ccb224c0cd7cf8ff9a11a465e68fd645510588249fabb6c8859a39663a","singleton":true}'::jsonb) r where arcade_policy_v5.singleton=r.singleton;
insert into story_card_pool select * from jsonb_populate_record(null::story_card_pool, '{"gacha":false,"grade":"SUPER RARE","id":"10511","name":"최수아"}'::jsonb) on conflict (id) do nothing;
insert into story_card_pool select * from jsonb_populate_record(null::story_card_pool, '{"gacha":false,"grade":"HIGH RARE","id":"10512","name":"고세연"}'::jsonb) on conflict (id) do nothing;
insert into story_card_pool select * from jsonb_populate_record(null::story_card_pool, '{"gacha":false,"grade":"ULTRA RARE","id":"10513","name":"[각성] 고세연"}'::jsonb) on conflict (id) do nothing;
insert into story_card_pool select * from jsonb_populate_record(null::story_card_pool, '{"gacha":false,"grade":"RARE","id":"10520","name":"황경민"}'::jsonb) on conflict (id) do nothing;
insert into story_card_pool select * from jsonb_populate_record(null::story_card_pool, '{"gacha":false,"grade":"SUPER RARE","id":"10521","name":"이혜림"}'::jsonb) on conflict (id) do nothing;
insert into story_card_pool select * from jsonb_populate_record(null::story_card_pool, '{"gacha":false,"grade":"ULTRA RARE","id":"10522","name":"이수영"}'::jsonb) on conflict (id) do nothing;
insert into story_card_pool select * from jsonb_populate_record(null::story_card_pool, '{"gacha":false,"grade":"SUPER RARE","id":"10523","name":"천혜영"}'::jsonb) on conflict (id) do nothing;
insert into story_card_pool select * from jsonb_populate_record(null::story_card_pool, '{"gacha":false,"grade":"ULTRA RARE","id":"10524","name":"이동주"}'::jsonb) on conflict (id) do nothing;
insert into story_card_pool select * from jsonb_populate_record(null::story_card_pool, '{"gacha":false,"grade":"ULTRA RARE","id":"10525","name":"김수진"}'::jsonb) on conflict (id) do nothing;
insert into story_card_pool select * from jsonb_populate_record(null::story_card_pool, '{"gacha":false,"grade":"SUPER RARE","id":"10526","name":"조태진"}'::jsonb) on conflict (id) do nothing;
insert into story_card_pool select * from jsonb_populate_record(null::story_card_pool, '{"gacha":false,"grade":"ULTRA RARE","id":"10527","name":"김한철"}'::jsonb) on conflict (id) do nothing;
insert into story_card_pool select * from jsonb_populate_record(null::story_card_pool, '{"gacha":false,"grade":"ULTRA RARE","id":"10528","name":"김진호"}'::jsonb) on conflict (id) do nothing;
insert into story_card_pool select * from jsonb_populate_record(null::story_card_pool, '{"gacha":false,"grade":"SUPER RARE","id":"10529","name":"김태희"}'::jsonb) on conflict (id) do nothing;
insert into story_card_pool select * from jsonb_populate_record(null::story_card_pool, '{"gacha":false,"grade":"SUPER RARE","id":"10530","name":"박승규"}'::jsonb) on conflict (id) do nothing;
insert into story_card_pool select * from jsonb_populate_record(null::story_card_pool, '{"gacha":false,"grade":"SUPER RARE","id":"10531","name":"김경섭"}'::jsonb) on conflict (id) do nothing;
insert into story_card_pool select * from jsonb_populate_record(null::story_card_pool, '{"gacha":false,"grade":"SUPER RARE","id":"10532","name":"천기철"}'::jsonb) on conflict (id) do nothing;
insert into battle_card_meta_v2 select * from jsonb_populate_record(null::battle_card_meta_v2, '{"definition":{"MOR":85,"class":"FIRE","cost":42,"gender":"FEMALE","grade":"SUPER RARE"},"id":"10511"}'::jsonb) on conflict (id) do nothing;
insert into battle_card_meta_v2 select * from jsonb_populate_record(null::battle_card_meta_v2, '{"definition":{"MOR":80,"class":"WIND","cost":27,"gender":"FEMALE","grade":"HIGH RARE"},"id":"10512"}'::jsonb) on conflict (id) do nothing;
insert into battle_card_meta_v2 select * from jsonb_populate_record(null::battle_card_meta_v2, '{"definition":{"MOR":80,"class":"WIND","cost":53,"gender":"FEMALE","grade":"ULTRA RARE"},"id":"10513"}'::jsonb) on conflict (id) do nothing;
insert into battle_card_meta_v2 select * from jsonb_populate_record(null::battle_card_meta_v2, '{"definition":{"MOR":20,"class":"FIRE","cost":20,"gender":"MALE","grade":"RARE"},"id":"10514"}'::jsonb) on conflict (id) do nothing;
insert into battle_card_meta_v2 select * from jsonb_populate_record(null::battle_card_meta_v2, '{"definition":{"MOR":77,"class":"FIRE","cost":10,"gender":"FEMALE","grade":"NORMAL"},"id":"10515"}'::jsonb) on conflict (id) do nothing;
insert into battle_card_meta_v2 select * from jsonb_populate_record(null::battle_card_meta_v2, '{"definition":{"MOR":80,"class":"ICE","cost":30,"gender":"FEMALE","grade":"HIGH RARE"},"id":"10516"}'::jsonb) on conflict (id) do nothing;
insert into battle_card_meta_v2 select * from jsonb_populate_record(null::battle_card_meta_v2, '{"definition":{"MOR":3,"class":"DARK","cost":55,"gender":"MALE","grade":"ULTRA RARE"},"id":"10517"}'::jsonb) on conflict (id) do nothing;
insert into battle_card_meta_v2 select * from jsonb_populate_record(null::battle_card_meta_v2, '{"definition":{"MOR":21,"class":"DARK","cost":30,"gender":"MALE","grade":"HIGH RARE"},"id":"10518"}'::jsonb) on conflict (id) do nothing;
insert into battle_card_meta_v2 select * from jsonb_populate_record(null::battle_card_meta_v2, '{"definition":{"MOR":16,"class":"WIND","cost":10,"gender":"MALE","grade":"NORMAL"},"id":"10519"}'::jsonb) on conflict (id) do nothing;
insert into battle_card_meta_v2 select * from jsonb_populate_record(null::battle_card_meta_v2, '{"definition":{"MOR":12,"class":"FIRE","cost":18,"gender":"MALE","grade":"RARE"},"id":"10520"}'::jsonb) on conflict (id) do nothing;
insert into battle_card_meta_v2 select * from jsonb_populate_record(null::battle_card_meta_v2, '{"definition":{"MOR":80,"class":"ICE","cost":44,"gender":"FEMALE","grade":"SUPER RARE"},"id":"10521"}'::jsonb) on conflict (id) do nothing;
insert into battle_card_meta_v2 select * from jsonb_populate_record(null::battle_card_meta_v2, '{"definition":{"MOR":75,"class":"WIND","cost":54,"gender":"FEMALE","grade":"ULTRA RARE"},"id":"10522"}'::jsonb) on conflict (id) do nothing;
insert into battle_card_meta_v2 select * from jsonb_populate_record(null::battle_card_meta_v2, '{"definition":{"MOR":80,"class":"DARK","cost":45,"gender":"FEMALE","grade":"SUPER RARE"},"id":"10523"}'::jsonb) on conflict (id) do nothing;
insert into battle_card_meta_v2 select * from jsonb_populate_record(null::battle_card_meta_v2, '{"definition":{"MOR":65,"class":"ICE","cost":53,"gender":"MALE","grade":"ULTRA RARE"},"id":"10524"}'::jsonb) on conflict (id) do nothing;
insert into battle_card_meta_v2 select * from jsonb_populate_record(null::battle_card_meta_v2, '{"definition":{"MOR":55,"class":"FIRE","cost":49,"gender":"FEMALE","grade":"ULTRA RARE"},"id":"10525"}'::jsonb) on conflict (id) do nothing;
insert into battle_card_meta_v2 select * from jsonb_populate_record(null::battle_card_meta_v2, '{"definition":{"MOR":76,"class":"FIRE","cost":41,"gender":"MALE","grade":"SUPER RARE"},"id":"10526"}'::jsonb) on conflict (id) do nothing;
insert into battle_card_meta_v2 select * from jsonb_populate_record(null::battle_card_meta_v2, '{"definition":{"MOR":78,"class":"ICE","cost":46,"gender":"MALE","grade":"ULTRA RARE"},"id":"10527"}'::jsonb) on conflict (id) do nothing;
insert into battle_card_meta_v2 select * from jsonb_populate_record(null::battle_card_meta_v2, '{"definition":{"MOR":65,"class":"FIRE","cost":53,"gender":"MALE","grade":"ULTRA RARE"},"id":"10528"}'::jsonb) on conflict (id) do nothing;
insert into battle_card_meta_v2 select * from jsonb_populate_record(null::battle_card_meta_v2, '{"definition":{"MOR":80,"class":"WIND","cost":43,"gender":"FEMALE","grade":"SUPER RARE"},"id":"10529"}'::jsonb) on conflict (id) do nothing;
insert into battle_card_meta_v2 select * from jsonb_populate_record(null::battle_card_meta_v2, '{"definition":{"MOR":68,"class":"WIND","cost":37,"gender":"MALE","grade":"SUPER RARE"},"id":"10530"}'::jsonb) on conflict (id) do nothing;
insert into battle_card_meta_v2 select * from jsonb_populate_record(null::battle_card_meta_v2, '{"definition":{"MOR":25,"class":"WIND","cost":35,"gender":"MALE","grade":"SUPER RARE"},"id":"10531"}'::jsonb) on conflict (id) do nothing;
insert into battle_card_meta_v2 select * from jsonb_populate_record(null::battle_card_meta_v2, '{"definition":{"MOR":77,"class":"ICE","cost":35,"gender":"MALE","grade":"SUPER RARE"},"id":"10532"}'::jsonb) on conflict (id) do nothing;
insert into dispatch_card_meta select * from jsonb_populate_record(null::dispatch_card_meta, '{"cls":"-","el":"-","grade":3,"id":"10511"}'::jsonb) on conflict (id) do nothing;
insert into dispatch_card_meta select * from jsonb_populate_record(null::dispatch_card_meta, '{"cls":"-","el":"-","grade":2,"id":"10512"}'::jsonb) on conflict (id) do nothing;
insert into dispatch_card_meta select * from jsonb_populate_record(null::dispatch_card_meta, '{"cls":"-","el":"-","grade":4,"id":"10513"}'::jsonb) on conflict (id) do nothing;
insert into dispatch_card_meta select * from jsonb_populate_record(null::dispatch_card_meta, '{"cls":"-","el":"-","grade":1,"id":"10520"}'::jsonb) on conflict (id) do nothing;
insert into dispatch_card_meta select * from jsonb_populate_record(null::dispatch_card_meta, '{"cls":"-","el":"-","grade":3,"id":"10521"}'::jsonb) on conflict (id) do nothing;
insert into dispatch_card_meta select * from jsonb_populate_record(null::dispatch_card_meta, '{"cls":"-","el":"-","grade":4,"id":"10522"}'::jsonb) on conflict (id) do nothing;
insert into dispatch_card_meta select * from jsonb_populate_record(null::dispatch_card_meta, '{"cls":"-","el":"-","grade":3,"id":"10523"}'::jsonb) on conflict (id) do nothing;
insert into dispatch_card_meta select * from jsonb_populate_record(null::dispatch_card_meta, '{"cls":"-","el":"-","grade":4,"id":"10524"}'::jsonb) on conflict (id) do nothing;
insert into dispatch_card_meta select * from jsonb_populate_record(null::dispatch_card_meta, '{"cls":"-","el":"-","grade":4,"id":"10525"}'::jsonb) on conflict (id) do nothing;
insert into dispatch_card_meta select * from jsonb_populate_record(null::dispatch_card_meta, '{"cls":"-","el":"-","grade":3,"id":"10526"}'::jsonb) on conflict (id) do nothing;
insert into dispatch_card_meta select * from jsonb_populate_record(null::dispatch_card_meta, '{"cls":"-","el":"-","grade":4,"id":"10527"}'::jsonb) on conflict (id) do nothing;
insert into dispatch_card_meta select * from jsonb_populate_record(null::dispatch_card_meta, '{"cls":"-","el":"-","grade":4,"id":"10528"}'::jsonb) on conflict (id) do nothing;
insert into dispatch_card_meta select * from jsonb_populate_record(null::dispatch_card_meta, '{"cls":"-","el":"-","grade":3,"id":"10529"}'::jsonb) on conflict (id) do nothing;
insert into dispatch_card_meta select * from jsonb_populate_record(null::dispatch_card_meta, '{"cls":"-","el":"-","grade":3,"id":"10530"}'::jsonb) on conflict (id) do nothing;
insert into dispatch_card_meta select * from jsonb_populate_record(null::dispatch_card_meta, '{"cls":"-","el":"-","grade":3,"id":"10531"}'::jsonb) on conflict (id) do nothing;
insert into dispatch_card_meta select * from jsonb_populate_record(null::dispatch_card_meta, '{"cls":"-","el":"-","grade":3,"id":"10532"}'::jsonb) on conflict (id) do nothing;
update guildbattle_policy_v4 set engine_hash=r.engine_hash from jsonb_populate_record(null::guildbattle_policy_v4, '{"enabled":true,"engine_hash":"819b116c1e1ccd7d66ba589e3bc5e4e8d436a43ebf2dfe4543c250cbf5166cd0","singleton":true}'::jsonb) r where guildbattle_policy_v4.singleton=r.singleton;
insert into pvp_card_meta select * from jsonb_populate_record(null::pvp_card_meta, '{"cost":42,"grade":"SUPER RARE","id":"10511"}'::jsonb) on conflict (id) do nothing;
insert into pvp_card_meta select * from jsonb_populate_record(null::pvp_card_meta, '{"cost":27,"grade":"HIGH RARE","id":"10512"}'::jsonb) on conflict (id) do nothing;
insert into pvp_card_meta select * from jsonb_populate_record(null::pvp_card_meta, '{"cost":53,"grade":"ULTRA RARE","id":"10513"}'::jsonb) on conflict (id) do nothing;
insert into pvp_card_meta select * from jsonb_populate_record(null::pvp_card_meta, '{"cost":18,"grade":"RARE","id":"10520"}'::jsonb) on conflict (id) do nothing;
insert into pvp_card_meta select * from jsonb_populate_record(null::pvp_card_meta, '{"cost":44,"grade":"SUPER RARE","id":"10521"}'::jsonb) on conflict (id) do nothing;
insert into pvp_card_meta select * from jsonb_populate_record(null::pvp_card_meta, '{"cost":54,"grade":"ULTRA RARE","id":"10522"}'::jsonb) on conflict (id) do nothing;
insert into pvp_card_meta select * from jsonb_populate_record(null::pvp_card_meta, '{"cost":45,"grade":"SUPER RARE","id":"10523"}'::jsonb) on conflict (id) do nothing;
insert into pvp_card_meta select * from jsonb_populate_record(null::pvp_card_meta, '{"cost":53,"grade":"ULTRA RARE","id":"10524"}'::jsonb) on conflict (id) do nothing;
insert into pvp_card_meta select * from jsonb_populate_record(null::pvp_card_meta, '{"cost":49,"grade":"ULTRA RARE","id":"10525"}'::jsonb) on conflict (id) do nothing;
insert into pvp_card_meta select * from jsonb_populate_record(null::pvp_card_meta, '{"cost":41,"grade":"SUPER RARE","id":"10526"}'::jsonb) on conflict (id) do nothing;
insert into pvp_card_meta select * from jsonb_populate_record(null::pvp_card_meta, '{"cost":46,"grade":"ULTRA RARE","id":"10527"}'::jsonb) on conflict (id) do nothing;
insert into pvp_card_meta select * from jsonb_populate_record(null::pvp_card_meta, '{"cost":53,"grade":"ULTRA RARE","id":"10528"}'::jsonb) on conflict (id) do nothing;
insert into pvp_card_meta select * from jsonb_populate_record(null::pvp_card_meta, '{"cost":43,"grade":"SUPER RARE","id":"10529"}'::jsonb) on conflict (id) do nothing;
insert into pvp_card_meta select * from jsonb_populate_record(null::pvp_card_meta, '{"cost":37,"grade":"SUPER RARE","id":"10530"}'::jsonb) on conflict (id) do nothing;
insert into pvp_card_meta select * from jsonb_populate_record(null::pvp_card_meta, '{"cost":35,"grade":"SUPER RARE","id":"10531"}'::jsonb) on conflict (id) do nothing;
insert into pvp_card_meta select * from jsonb_populate_record(null::pvp_card_meta, '{"cost":35,"grade":"SUPER RARE","id":"10532"}'::jsonb) on conflict (id) do nothing;
update pvp_policy_v3 set engine_hash=r.engine_hash from jsonb_populate_record(null::pvp_policy_v3, '{"enabled":true,"engine_hash":"bef887c77a009121ae99301ca91db7d73a7bd9ce30d70e1ec7a18d10742cd16f","singleton":true}'::jsonb) r where pvp_policy_v3.singleton=r.singleton;
insert into reward_card_catalog select * from jsonb_populate_record(null::reward_card_catalog, '{"card_id":"10511"}'::jsonb) on conflict (card_id) do nothing;
insert into reward_card_catalog select * from jsonb_populate_record(null::reward_card_catalog, '{"card_id":"10512"}'::jsonb) on conflict (card_id) do nothing;
insert into reward_card_catalog select * from jsonb_populate_record(null::reward_card_catalog, '{"card_id":"10513"}'::jsonb) on conflict (card_id) do nothing;
insert into reward_card_catalog select * from jsonb_populate_record(null::reward_card_catalog, '{"card_id":"10520"}'::jsonb) on conflict (card_id) do nothing;
insert into reward_card_catalog select * from jsonb_populate_record(null::reward_card_catalog, '{"card_id":"10521"}'::jsonb) on conflict (card_id) do nothing;
insert into reward_card_catalog select * from jsonb_populate_record(null::reward_card_catalog, '{"card_id":"10522"}'::jsonb) on conflict (card_id) do nothing;
insert into reward_card_catalog select * from jsonb_populate_record(null::reward_card_catalog, '{"card_id":"10523"}'::jsonb) on conflict (card_id) do nothing;
insert into reward_card_catalog select * from jsonb_populate_record(null::reward_card_catalog, '{"card_id":"10524"}'::jsonb) on conflict (card_id) do nothing;
insert into reward_card_catalog select * from jsonb_populate_record(null::reward_card_catalog, '{"card_id":"10525"}'::jsonb) on conflict (card_id) do nothing;
insert into reward_card_catalog select * from jsonb_populate_record(null::reward_card_catalog, '{"card_id":"10526"}'::jsonb) on conflict (card_id) do nothing;
insert into reward_card_catalog select * from jsonb_populate_record(null::reward_card_catalog, '{"card_id":"10527"}'::jsonb) on conflict (card_id) do nothing;
insert into reward_card_catalog select * from jsonb_populate_record(null::reward_card_catalog, '{"card_id":"10528"}'::jsonb) on conflict (card_id) do nothing;
insert into reward_card_catalog select * from jsonb_populate_record(null::reward_card_catalog, '{"card_id":"10529"}'::jsonb) on conflict (card_id) do nothing;
insert into reward_card_catalog select * from jsonb_populate_record(null::reward_card_catalog, '{"card_id":"10530"}'::jsonb) on conflict (card_id) do nothing;
insert into reward_card_catalog select * from jsonb_populate_record(null::reward_card_catalog, '{"card_id":"10531"}'::jsonb) on conflict (card_id) do nothing;
insert into reward_card_catalog select * from jsonb_populate_record(null::reward_card_catalog, '{"card_id":"10532"}'::jsonb) on conflict (card_id) do nothing;
insert into story_skill_meta select * from jsonb_populate_record(null::story_skill_meta, '{"card_id":"10511","idx":1,"unlock":2}'::jsonb) on conflict (card_id,idx) do nothing;
insert into story_skill_meta select * from jsonb_populate_record(null::story_skill_meta, '{"card_id":"10511","idx":2,"unlock":5}'::jsonb) on conflict (card_id,idx) do nothing;
insert into story_skill_meta select * from jsonb_populate_record(null::story_skill_meta, '{"card_id":"10512","idx":1,"unlock":2}'::jsonb) on conflict (card_id,idx) do nothing;
insert into story_skill_meta select * from jsonb_populate_record(null::story_skill_meta, '{"card_id":"10512","idx":2,"unlock":5}'::jsonb) on conflict (card_id,idx) do nothing;
insert into story_skill_meta select * from jsonb_populate_record(null::story_skill_meta, '{"card_id":"10513","idx":1,"unlock":2}'::jsonb) on conflict (card_id,idx) do nothing;
insert into story_skill_meta select * from jsonb_populate_record(null::story_skill_meta, '{"card_id":"10513","idx":2,"unlock":5}'::jsonb) on conflict (card_id,idx) do nothing;
insert into story_skill_meta select * from jsonb_populate_record(null::story_skill_meta, '{"card_id":"10513","idx":3,"unlock":7}'::jsonb) on conflict (card_id,idx) do nothing;
insert into story_skill_meta select * from jsonb_populate_record(null::story_skill_meta, '{"card_id":"10520","idx":1,"unlock":2}'::jsonb) on conflict (card_id,idx) do nothing;
insert into story_skill_meta select * from jsonb_populate_record(null::story_skill_meta, '{"card_id":"10521","idx":1,"unlock":2}'::jsonb) on conflict (card_id,idx) do nothing;
insert into story_skill_meta select * from jsonb_populate_record(null::story_skill_meta, '{"card_id":"10521","idx":2,"unlock":5}'::jsonb) on conflict (card_id,idx) do nothing;
insert into story_skill_meta select * from jsonb_populate_record(null::story_skill_meta, '{"card_id":"10522","idx":1,"unlock":2}'::jsonb) on conflict (card_id,idx) do nothing;
insert into story_skill_meta select * from jsonb_populate_record(null::story_skill_meta, '{"card_id":"10522","idx":2,"unlock":5}'::jsonb) on conflict (card_id,idx) do nothing;
insert into story_skill_meta select * from jsonb_populate_record(null::story_skill_meta, '{"card_id":"10522","idx":3,"unlock":7}'::jsonb) on conflict (card_id,idx) do nothing;
insert into story_skill_meta select * from jsonb_populate_record(null::story_skill_meta, '{"card_id":"10523","idx":1,"unlock":2}'::jsonb) on conflict (card_id,idx) do nothing;
insert into story_skill_meta select * from jsonb_populate_record(null::story_skill_meta, '{"card_id":"10523","idx":2,"unlock":5}'::jsonb) on conflict (card_id,idx) do nothing;
insert into story_skill_meta select * from jsonb_populate_record(null::story_skill_meta, '{"card_id":"10524","idx":1,"unlock":2}'::jsonb) on conflict (card_id,idx) do nothing;
insert into story_skill_meta select * from jsonb_populate_record(null::story_skill_meta, '{"card_id":"10524","idx":2,"unlock":5}'::jsonb) on conflict (card_id,idx) do nothing;
insert into story_skill_meta select * from jsonb_populate_record(null::story_skill_meta, '{"card_id":"10524","idx":3,"unlock":7}'::jsonb) on conflict (card_id,idx) do nothing;
insert into story_skill_meta select * from jsonb_populate_record(null::story_skill_meta, '{"card_id":"10525","idx":1,"unlock":2}'::jsonb) on conflict (card_id,idx) do nothing;
insert into story_skill_meta select * from jsonb_populate_record(null::story_skill_meta, '{"card_id":"10525","idx":2,"unlock":5}'::jsonb) on conflict (card_id,idx) do nothing;
insert into story_skill_meta select * from jsonb_populate_record(null::story_skill_meta, '{"card_id":"10525","idx":3,"unlock":7}'::jsonb) on conflict (card_id,idx) do nothing;
insert into story_skill_meta select * from jsonb_populate_record(null::story_skill_meta, '{"card_id":"10526","idx":1,"unlock":2}'::jsonb) on conflict (card_id,idx) do nothing;
insert into story_skill_meta select * from jsonb_populate_record(null::story_skill_meta, '{"card_id":"10526","idx":2,"unlock":5}'::jsonb) on conflict (card_id,idx) do nothing;
insert into story_skill_meta select * from jsonb_populate_record(null::story_skill_meta, '{"card_id":"10527","idx":1,"unlock":2}'::jsonb) on conflict (card_id,idx) do nothing;
insert into story_skill_meta select * from jsonb_populate_record(null::story_skill_meta, '{"card_id":"10527","idx":2,"unlock":5}'::jsonb) on conflict (card_id,idx) do nothing;
insert into story_skill_meta select * from jsonb_populate_record(null::story_skill_meta, '{"card_id":"10527","idx":3,"unlock":7}'::jsonb) on conflict (card_id,idx) do nothing;
insert into story_skill_meta select * from jsonb_populate_record(null::story_skill_meta, '{"card_id":"10528","idx":1,"unlock":2}'::jsonb) on conflict (card_id,idx) do nothing;
insert into story_skill_meta select * from jsonb_populate_record(null::story_skill_meta, '{"card_id":"10528","idx":2,"unlock":5}'::jsonb) on conflict (card_id,idx) do nothing;
insert into story_skill_meta select * from jsonb_populate_record(null::story_skill_meta, '{"card_id":"10528","idx":3,"unlock":7}'::jsonb) on conflict (card_id,idx) do nothing;
insert into story_skill_meta select * from jsonb_populate_record(null::story_skill_meta, '{"card_id":"10529","idx":1,"unlock":2}'::jsonb) on conflict (card_id,idx) do nothing;
insert into story_skill_meta select * from jsonb_populate_record(null::story_skill_meta, '{"card_id":"10529","idx":2,"unlock":5}'::jsonb) on conflict (card_id,idx) do nothing;
insert into story_skill_meta select * from jsonb_populate_record(null::story_skill_meta, '{"card_id":"10530","idx":1,"unlock":2}'::jsonb) on conflict (card_id,idx) do nothing;
insert into story_skill_meta select * from jsonb_populate_record(null::story_skill_meta, '{"card_id":"10530","idx":2,"unlock":5}'::jsonb) on conflict (card_id,idx) do nothing;
insert into story_skill_meta select * from jsonb_populate_record(null::story_skill_meta, '{"card_id":"10531","idx":1,"unlock":2}'::jsonb) on conflict (card_id,idx) do nothing;
insert into story_skill_meta select * from jsonb_populate_record(null::story_skill_meta, '{"card_id":"10531","idx":2,"unlock":5}'::jsonb) on conflict (card_id,idx) do nothing;
insert into story_skill_meta select * from jsonb_populate_record(null::story_skill_meta, '{"card_id":"10532","idx":1,"unlock":2}'::jsonb) on conflict (card_id,idx) do nothing;
insert into story_skill_meta select * from jsonb_populate_record(null::story_skill_meta, '{"card_id":"10532","idx":2,"unlock":5}'::jsonb) on conflict (card_id,idx) do nothing;
$vr_production_payload$;
 perform set_config('check_function_bodies','on',true);
 for f in select pg_get_functiondef(oid) ddl from pg_proc where pronamespace='public'::regnamespace and prokind='f' and proname=any(array['_daily_defs','_drink_json','_dsp_fill','_phase7_replayable','_pvp_rating_v3','_unlock_intros','_weekly_defs','battle_direct_session_v7','battle_direct_settle_v7','battle_session_finish_v2','battle_sweep_session_v6','battle_sweep_settle_v6','dispatch_start','drink_buy','pvp_rankings','pvp_user_info','story_complete_scene']) loop execute f.ddl; end loop;
 if exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosecdef and left(p.proname,1)='_' and pg_get_function_result(p.oid)<>'trigger' and (has_function_privilege('anon',p.oid,'execute') or has_function_privilege('authenticated',p.oid,'execute'))) then raise exception 'STOP: public-callable internal definer function'; end if;
 insert into vr_rollout_private.releases(release_id,bundle_hash,db_id) values('20261111','dd2b7a28c5ddb524ab2c5f86da9fbae096e7926bdcc231332ff52d5f24a241da',(select system_identifier::text from pg_catalog.pg_control_system()));
end $production_install$;
notify pgrst,'reload schema';
commit;
select 'Production DB delta 20261111 installed; deploy all FIVE production Edge bundles before the Worker/main release' as result;
