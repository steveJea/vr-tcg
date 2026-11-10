-- 보안 7단계: 스토리·시련의 탑 직접 전투 중, 서버가 다시 계산할 수 있는 판만 재계산 결과로 보상을 준다.
-- 소탕(6단계) 함수와 스위치는 건드리지 않는다. 이 파일은 그 소탕 정산을 지우거나 되돌리지 않는다.
-- 기존 스테이징 업그레이드 전용. 전체 파일 1회 실행(재실행 안전). 운영 금지.
-- 진행·잔액·이미 받은 보상은 지우거나 다시 주지 않는다. 스위치는 꺼진 채로 둔다.
begin;
do $phase7_staging_guard$
begin
 if (select system_identifier::text from pg_control_system()) <> '7703759698107299042' then
  raise exception 'STOP: phase7 only staging cuyqchmdcnsgzkwyclji';
 end if;
 if to_regprocedure('public._phase6_old_finish_v2(uuid,jsonb)') is null
  or to_regprocedure('public.battle_sweep_settle_v6(uuid,uuid,text,jsonb)') is null
  or to_regprocedure('public._phase2_old_story_complete_phase(integer,integer,jsonb)') is null then
  raise exception 'phase6 required';
 end if;
end $phase7_staging_guard$;

create table if not exists public.battle_replay_policy_v7 (
 singleton boolean primary key default true check (singleton),
 enabled boolean not null default false,
 engine_hash text not null check (engine_hash ~ '^[a-f0-9]{64}$'));
-- Starts off. Re-running this file updates the engine hash only and does not turn enforcement on.
insert into public.battle_replay_policy_v7(singleton, enabled, engine_hash)
 values (true, false, '5cc704e71c18e79f046e9a090fe2461fd92d5583d1e8e8c0b3f3f9f81ff56873')
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
notify pgrst, 'reload schema';
commit;
select 'phase7 direct replay installed — staging only, switch off, phase6 sweep untouched' as result;
