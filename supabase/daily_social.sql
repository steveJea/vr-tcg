-- =====================================================================
-- 🎁 도감 수집률 보상 + 👥 친구 일일 선물 + 📋 개인 주간 미션
-- Supabase SQL Editor 에서 실행. 여러 번 실행해도 안전 (테이블·데이터 삭제 없음)
-- 선행: daily.sql(_daily_grant · _gem_day) · friends.sql · gallery(schema) · phaseE_2(_player_stamina_add)
-- 시간: 전부 서버 now() / _gem_day() (한국 시간). 주간 = 월요일 00:00 KST 시작
-- 공개 RPC
--   gallery_rewards() · gallery_reward_claim(pct)
--   friend_gift_send(user) · friend_gift_claim(id) · friend_gift_claim_all()
--   friends_list() · friends_ping()  — 선물 정보 포함으로 교체
--   weekly_status() · weekly_track(kind, n) · weekly_claim(key)
-- 확인용: select public.gallery_rewards(); select public.weekly_status();
-- =====================================================================

-- =====================================================================
-- 1) 도감 수집률 구간 보상 (25 · 50 · 75 · 100%)
-- =====================================================================
create table if not exists public.gallery_claims (
  user_id   uuid not null references auth.users(id) on delete cascade,
  pct       int  not null check (pct in (25, 50, 75, 100)),
  claimed_at timestamptz not null default now(),
  primary key (user_id, pct)
);
alter table public.gallery_claims enable row level security;
revoke all on public.gallery_claims from public, anon, authenticated;

-- data/cards.csv 장수(헤더 제외)와 맞출 것. 새 카드 넣으면 여기도 올리기
create or replace function public._gallery_total() returns int language sql immutable as $$ select 438 $$;

create or replace function public._gallery_reward_defs() returns jsonb language sql immutable as $$ select '[
  {"pct":25,"reward":{"gold":15000,"tickets":10}},
  {"pct":50,"reward":{"gold":45000,"gem":50,"tickets":20}},
  {"pct":75,"reward":{"gold":90000,"gem":100,"tickets":30}},
  {"pct":100,"reward":{"gold":150000,"gem":300,"tickets":50}}
]'::jsonb $$;

create or replace function public._gallery_have(p_uid uuid) returns int language sql stable security definer set search_path = public as $$
  select count(*)::int from gallery where user_id = p_uid $$;
revoke all on function public._gallery_have(uuid) from public, anon, authenticated;

create or replace function public._gallery_rewards_json(p_uid uuid) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare have int := _gallery_have(p_uid); tot int := _gallery_total(); pct int;
begin
  pct := case when tot <= 0 then 0 else least(100, (have * 100) / tot) end;
  return jsonb_build_object('ok', true, 'have', have, 'total', tot, 'pct', pct,
    'milestones', (select jsonb_agg(m || jsonb_build_object(
        'ready', pct >= (m->>'pct')::int,
        'claimed', exists (select 1 from gallery_claims c where c.user_id = p_uid and c.pct = (m->>'pct')::int))
      order by (m->>'pct')::int)
      from jsonb_array_elements(_gallery_reward_defs()) m));
end $$;
revoke all on function public._gallery_rewards_json(uuid) from public, anon, authenticated;

create or replace function public.gallery_rewards() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  return _gallery_rewards_json(uid);
end $$;

create or replace function public.gallery_reward_claim(p_pct int) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); m jsonb; have int; tot int; pct int; res jsonb; ok boolean;
begin
  if uid is null then raise exception 'login required'; end if;
  select x into m from jsonb_array_elements(_gallery_reward_defs()) x where (x->>'pct')::int = p_pct;
  if m is null then raise exception 'invalid pct'; end if;
  perform pg_advisory_xact_lock(hashtext('galrw:' || uid::text));
  perform pg_advisory_xact_lock(hashtext('gem:' || uid::text));
  have := _gallery_have(uid); tot := _gallery_total();
  pct := case when tot <= 0 then 0 else least(100, (have * 100) / tot) end;
  if pct < p_pct then raise exception 'not done'; end if;
  insert into gallery_claims (user_id, pct) values (uid, p_pct) on conflict do nothing returning true into ok;
  if not coalesce(ok, false) then raise exception 'already claimed'; end if;
  res := _daily_grant(uid, m->'reward', 'gallery', 'gallery:' || p_pct);
  return _gallery_rewards_json(uid) || res || jsonb_build_object('got', m->'reward');
end $$;

revoke all on function public.gallery_rewards(), public.gallery_reward_claim(int) from public, anon;
grant execute on function public.gallery_rewards(), public.gallery_reward_claim(int) to authenticated;

-- =====================================================================
-- 2) 친구 일일 선물 (친구 1명당 하루 1회 보내기 · 하루 최대 20개 받기)
-- =====================================================================
create table if not exists public.friend_gifts (
  id         bigint generated always as identity primary key,
  from_user  uuid not null references auth.users(id) on delete cascade,
  to_user    uuid not null references auth.users(id) on delete cascade,
  day        date not null,
  claimed_at timestamptz,
  created_at timestamptz not null default now(),
  check (from_user <> to_user),
  unique (from_user, to_user, day)
);
create index if not exists friend_gifts_to_day_idx on public.friend_gifts (to_user, day) where claimed_at is null;
create index if not exists friend_gifts_to_claimed_idx on public.friend_gifts (to_user, day) where claimed_at is not null;
alter table public.friend_gifts enable row level security;
revoke all on public.friend_gifts from public, anon, authenticated;

create or replace function public._friend_gift_reward() returns jsonb language sql immutable as $$ select '{"stamina":5}'::jsonb $$;
create or replace function public._friend_gift_claim_cap() returns int language sql immutable as $$ select 20 $$;

create or replace function public._friend_gift_grant(p_uid uuid, p_rw jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare res jsonb := '{}'::jsonb; st int;
begin
  if coalesce((p_rw->>'stamina')::int, 0) > 0 then
    st := _player_stamina_add(p_uid, (p_rw->>'stamina')::int);
    res := res || jsonb_build_object('stamina', st);
  end if;
  if coalesce((p_rw->>'gold')::int, 0) > 0 or coalesce((p_rw->>'gem')::int, 0) > 0 or coalesce((p_rw->>'tickets')::int, 0) > 0 then
    res := res || _daily_grant(p_uid, p_rw - 'stamina', 'friend_gift', 'friend_gift');
  end if;
  return res;
end $$;
revoke all on function public._friend_gift_grant(uuid, jsonb) from public, anon, authenticated;

create or replace function public.friend_gift_send(p_user uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); today date := _gem_day(); gid bigint;
begin
  if uid is null then raise exception 'login required'; end if;
  if p_user is null or p_user = uid then raise exception 'invalid user'; end if;
  if not _is_friend(uid, p_user) then raise exception 'not friends'; end if;
  perform pg_advisory_xact_lock(hashtext('fgift:' || uid::text));
  insert into friend_gifts (from_user, to_user, day) values (uid, p_user, today)
    on conflict (from_user, to_user, day) do nothing returning id into gid;
  if gid is null then raise exception 'already sent'; end if;
  return jsonb_build_object('ok', true, 'id', gid, 'day', today);
end $$;

create or replace function public.friend_gift_claim(p_id bigint) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); today date := _gem_day(); g friend_gifts; n int; rw jsonb := _friend_gift_reward(); res jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('fgift:' || uid::text));
  select * into g from friend_gifts where id = p_id and to_user = uid for update;
  if g.id is null then raise exception 'gift not found'; end if;
  if g.claimed_at is not null then raise exception 'already claimed'; end if;
  select count(*) into n from friend_gifts where to_user = uid and day = today and claimed_at is not null;
  if n >= _friend_gift_claim_cap() then raise exception 'claim cap'; end if;
  update friend_gifts set claimed_at = now() where id = g.id;
  res := _friend_gift_grant(uid, rw);
  return jsonb_build_object('ok', true, 'got', rw, 'claimed_today', n + 1, 'cap', _friend_gift_claim_cap()) || res;
end $$;

create or replace function public.friend_gift_claim_all() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); today date := _gem_day(); g friend_gifts; n int; left_n int; tot int := 0; rw jsonb := _friend_gift_reward(); st int := 0;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('fgift:' || uid::text));
  select count(*) into n from friend_gifts where to_user = uid and day = today and claimed_at is not null;
  left_n := greatest(0, _friend_gift_claim_cap() - n);
  if left_n <= 0 then raise exception 'claim cap'; end if;
  for g in select * from friend_gifts where to_user = uid and claimed_at is null order by id limit left_n for update loop
    update friend_gifts set claimed_at = now() where id = g.id;
    tot := tot + 1;
  end loop;
  if tot <= 0 then raise exception 'nothing to claim'; end if;
  if coalesce((rw->>'stamina')::int, 0) > 0 then st := _player_stamina_add(uid, (rw->>'stamina')::int * tot); end if;
  return jsonb_build_object('ok', true, 'n', tot, 'got', jsonb_build_object('stamina', coalesce((rw->>'stamina')::int, 0) * tot),
    'stamina', st, 'claimed_today', n + tot, 'cap', _friend_gift_claim_cap());
end $$;

-- friends_list / friends_ping 에 선물 상태 추가 (기존 필드 유지)
create or replace function public.friends_list() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); today date := _gem_day(); claimed_n int; inbox jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  insert into player_presence (user_id, seen_at) values (uid, now()) on conflict (user_id) do update set seen_at = now();
  select count(*) into claimed_n from friend_gifts where to_user = uid and day = today and claimed_at is not null;
  select coalesce(jsonb_agg(_friend_card(g.from_user) || jsonb_build_object('gift_id', g.id, 'at', g.created_at) order by g.id), '[]'::jsonb)
    into inbox from friend_gifts g where g.to_user = uid and g.claimed_at is null;
  return jsonb_build_object('ok', true, 'me', _friend_card(uid), 'cap', _friend_cap(),
    'friends', (select coalesce(jsonb_agg(_friend_card(o) || jsonb_build_object('since', f.created_at,
                   'gift_sent', exists (select 1 from friend_gifts g where g.from_user = uid and g.to_user = o and g.day = today))
                 order by (select seen_at from player_presence where user_id = o) desc nulls last), '[]'::jsonb)
               from (select case when user_a = uid then user_b else user_a end o, created_at from friendships where user_a = uid or user_b = uid) f),
    'incoming', (select coalesce(jsonb_agg(_friend_card(r.from_user) || jsonb_build_object('req_id', r.id, 'at', r.created_at) order by r.id desc), '[]'::jsonb)
               from friend_requests r where r.to_user = uid),
    'outgoing', (select coalesce(jsonb_agg(_friend_card(r.to_user) || jsonb_build_object('req_id', r.id, 'at', r.created_at) order by r.id desc), '[]'::jsonb)
               from friend_requests r where r.from_user = uid),
    'gifts', jsonb_build_object('inbox', inbox, 'reward', _friend_gift_reward(), 'claimed_today', claimed_n, 'cap', _friend_gift_claim_cap(),
               'left', greatest(0, _friend_gift_claim_cap() - claimed_n)));
end $$;

create or replace function public.friends_ping() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  insert into player_presence (user_id, seen_at) values (uid, now()) on conflict (user_id) do update set seen_at = now();
  return jsonb_build_object('ok', true,
    'pending', (select count(*) from friend_requests where to_user = uid),
    'gifts', (select count(*) from friend_gifts where to_user = uid and claimed_at is null));
end $$;

revoke all on function public.friend_gift_send(uuid), public.friend_gift_claim(bigint), public.friend_gift_claim_all(),
  public.friends_list(), public.friends_ping() from public, anon;
grant execute on function public.friend_gift_send(uuid), public.friend_gift_claim(bigint), public.friend_gift_claim_all(),
  public.friends_list(), public.friends_ping() to authenticated;

-- =====================================================================
-- 3) 개인 주간 미션 (월요일 00:00 KST 초기화)
-- =====================================================================
create table if not exists public.weekly_progress (
  user_id uuid not null references auth.users(id) on delete cascade,
  week    date not null,
  prog    jsonb not null default '{}'::jsonb,
  claimed jsonb not null default '[]'::jsonb,
  primary key (user_id, week)
);
alter table public.weekly_progress enable row level security;
revoke all on public.weekly_progress from public, anon, authenticated;

-- 주 시작일 = 그 주의 월요일 (KST 날짜 기준). PG date_trunc('week') 는 월요일 시작
create or replace function public._weekly_week() returns date language sql stable as $$
  select date_trunc('week', _gem_day()::timestamp)::date $$;

create or replace function public._weekly_defs() returns jsonb language sql immutable as $$ select '[
  {"key":"arcade","name":"아케이드 플레이 x 7","goal":7,"per":2,"reward":{"gold":8000,"tickets":1}},
  {"key":"win","name":"전투 승리 x 15","goal":15,"per":3,"reward":{"gold":10000,"gem":30}},
  {"key":"story","name":"스토리 스테이지 클리어 x 10","goal":10,"per":2,"reward":{"gold":10000,"gem":30}},
  {"key":"tower","name":"시련의 탑 도전 x 5","goal":5,"per":1,"reward":{"gold":8000,"gem":20}},
  {"key":"skill","name":"고유기술 사용 x 50","goal":50,"per":40,"reward":{"gold":8000,"gem":20}}
]'::jsonb $$;
create or replace function public._weekly_all_reward() returns jsonb language sql immutable as $$ select '{"gem":100,"tickets":2}'::jsonb $$;

create or replace function public._weekly_json(p_uid uuid) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare wp weekly_progress; week date := _weekly_week(); done int; next_reset timestamptz;
begin
  select * into wp from weekly_progress where user_id = p_uid and week = week;
  select count(*) into done from jsonb_array_elements(_weekly_defs()) m where coalesce((wp.prog->>(m->>'key'))::int, 0) >= (m->>'goal')::int;
  next_reset := ((week + 7)::timestamp at time zone 'Asia/Seoul');
  return jsonb_build_object('ok', true, 'week', week, 'next_reset', next_reset,
    'missions', (select jsonb_agg(m || jsonb_build_object('prog', least((m->>'goal')::int, coalesce((wp.prog->>(m->>'key'))::int, 0)),
                   'claimed', coalesce(wp.claimed, '[]'::jsonb) ? (m->>'key'))) from jsonb_array_elements(_weekly_defs()) m),
    'all', jsonb_build_object('reward', _weekly_all_reward(), 'done', done, 'goal', jsonb_array_length(_weekly_defs()),
                   'claimed', coalesce(wp.claimed, '[]'::jsonb) ? 'all'));
end $$;
revoke all on function public._weekly_json(uuid) from public, anon, authenticated;

create or replace function public.weekly_status() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  return _weekly_json(uid);
end $$;

create or replace function public.weekly_track(p_kind text, p_n int default 1) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); m jsonb; week date := _weekly_week(); cur int; nv int;
begin
  if uid is null then raise exception 'login required'; end if;
  select x into m from jsonb_array_elements(_weekly_defs()) x where x->>'key' = p_kind;
  if m is null then raise exception 'invalid kind'; end if;
  perform pg_advisory_xact_lock(hashtext('weekly:' || uid::text));
  insert into weekly_progress (user_id, week) values (uid, week) on conflict do nothing;
  select coalesce((prog->>p_kind)::int, 0) into cur from weekly_progress where user_id = uid and week = week;
  nv := least((m->>'goal')::int, cur + greatest(0, least(coalesce(p_n, 1), (m->>'per')::int)));
  if nv <> cur then update weekly_progress set prog = prog || jsonb_build_object(p_kind, nv) where user_id = uid and week = week; end if;
  return jsonb_build_object('ok', true, 'kind', p_kind, 'prog', nv, 'goal', (m->>'goal')::int);
end $$;

create or replace function public.weekly_claim(p_key text) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); m jsonb; week date := _weekly_week(); wp weekly_progress; rw jsonb; res jsonb; done int;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('weekly:' || uid::text));
  perform pg_advisory_xact_lock(hashtext('gem:' || uid::text));
  insert into weekly_progress (user_id, week) values (uid, week) on conflict do nothing;
  select * into wp from weekly_progress where user_id = uid and week = week for update;
  if wp.claimed ? p_key then raise exception 'already claimed'; end if;
  if p_key = 'all' then
    select count(*) into done from jsonb_array_elements(_weekly_defs()) x where coalesce((wp.prog->>(x->>'key'))::int, 0) >= (x->>'goal')::int;
    if done < jsonb_array_length(_weekly_defs()) then raise exception 'not done'; end if;
    rw := _weekly_all_reward();
  else
    select x into m from jsonb_array_elements(_weekly_defs()) x where x->>'key' = p_key;
    if m is null then raise exception 'invalid key'; end if;
    if coalesce((wp.prog->>p_key)::int, 0) < (m->>'goal')::int then raise exception 'not done'; end if;
    rw := m->'reward';
  end if;
  update weekly_progress set claimed = claimed || to_jsonb(p_key) where user_id = uid and week = week;
  res := _daily_grant(uid, rw, 'weekly', 'weekly:' || week || ':' || p_key);
  return _weekly_json(uid) || res || jsonb_build_object('got', rw);
end $$;

revoke all on function public.weekly_status(), public.weekly_track(text, int), public.weekly_claim(text) from public, anon;
grant execute on function public.weekly_status(), public.weekly_track(text, int), public.weekly_claim(text) to authenticated;
