-- =====================================================================
-- 👥 친구 (1단계: 검색·신청·수락·거절·취소·삭제·목록·접속 상태) — 여러 번 실행해도 안전, 삭제 없음
-- 선행: schema.sql(profiles) · phaseE_2.sql(player_state, 레벨 표시용)
-- 친구 코드 = user id 앞 8자리 (대문자). 닉네임 부분 검색 또는 코드로 검색
-- 이후 친구 대전/리플레이 공유는 friendships(정렬된 쌍 a<b) 를 기준으로 붙이면 됨
-- 공개 RPC: friends_ping() · friends_list() · friends_search(q) · friend_request(user) · friend_respond(req_id, accept)
--           friend_cancel(req_id) · friend_remove(user) · friends_pending_count()
-- =====================================================================

create table if not exists public.friend_requests (
  id         bigint generated always as identity primary key,
  from_user  uuid not null references auth.users(id) on delete cascade,
  to_user    uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  check (from_user <> to_user),
  unique (from_user, to_user)
);
create index if not exists friend_requests_to_idx on public.friend_requests (to_user);
alter table public.friend_requests enable row level security;
revoke all on public.friend_requests from public, anon, authenticated;

-- 친구 관계: 한 쌍당 한 줄 (user_a < user_b). 친구 대전·리플레이 공유 시 참조
create table if not exists public.friendships (
  user_a     uuid not null references auth.users(id) on delete cascade,
  user_b     uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_a, user_b),
  check (user_a < user_b)
);
create index if not exists friendships_b_idx on public.friendships (user_b);
alter table public.friendships enable row level security;
revoke all on public.friendships from public, anon, authenticated;

-- 접속 기록 (클라이언트가 몇 분마다 friends_ping)
create table if not exists public.player_presence (
  user_id uuid primary key references auth.users(id) on delete cascade,
  seen_at timestamptz not null default now()
);
alter table public.player_presence enable row level security;
revoke all on public.player_presence from public, anon, authenticated;

create or replace function public._friend_cap() returns int language sql immutable as $$ select 50 $$;
create or replace function public._friend_code(p uuid) returns text language sql immutable as $$ select upper(left(replace(p::text, '-', ''), 8)) $$;
create or replace function public._is_friend(p1 uuid, p2 uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from friendships where user_a = least(p1, p2) and user_b = greatest(p1, p2)) $$;
create or replace function public._friend_count(p uuid) returns int language sql stable security definer set search_path = public as $$
  select count(*)::int from friendships where user_a = p or user_b = p $$;
create or replace function public._friend_card(p uuid) returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('user_id', p, 'code', _friend_code(p),
    'name', coalesce((select nickname from profiles where id = p), '플레이어'),
    'avatar', (select avatar_url from profiles where id = p),
    'level', coalesce((select level from player_state where user_id = p), 1),
    'seen_at', (select seen_at from player_presence where user_id = p),
    'online', coalesce((select seen_at > now() - interval '5 minutes' from player_presence where user_id = p), false)) $$;
revoke all on function public._is_friend(uuid, uuid), public._friend_count(uuid), public._friend_card(uuid) from public, anon, authenticated;

create or replace function public.friends_ping() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  insert into player_presence (user_id, seen_at) values (uid, now()) on conflict (user_id) do update set seen_at = now();
  return jsonb_build_object('ok', true, 'pending', (select count(*) from friend_requests where to_user = uid));
end $$;

create or replace function public.friends_pending_count() returns int language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  return (select count(*)::int from friend_requests where to_user = uid);
end $$;

create or replace function public.friends_list() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  insert into player_presence (user_id, seen_at) values (uid, now()) on conflict (user_id) do update set seen_at = now();
  return jsonb_build_object('ok', true, 'me', _friend_card(uid), 'cap', _friend_cap(),
    'friends', (select coalesce(jsonb_agg(_friend_card(o) || jsonb_build_object('since', f.created_at)
                 order by (select seen_at from player_presence where user_id = o) desc nulls last), '[]'::jsonb)
               from (select case when user_a = uid then user_b else user_a end o, created_at from friendships where user_a = uid or user_b = uid) f),
    'incoming', (select coalesce(jsonb_agg(_friend_card(r.from_user) || jsonb_build_object('req_id', r.id, 'at', r.created_at) order by r.id desc), '[]'::jsonb)
               from friend_requests r where r.to_user = uid),
    'outgoing', (select coalesce(jsonb_agg(_friend_card(r.to_user) || jsonb_build_object('req_id', r.id, 'at', r.created_at) order by r.id desc), '[]'::jsonb)
               from friend_requests r where r.from_user = uid));
end $$;

create or replace function public.friends_search(p_q text) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); q text := btrim(coalesce(p_q, ''));
begin
  if uid is null then raise exception 'login required'; end if;
  if char_length(q) < 2 then raise exception 'query too short'; end if;
  q := replace(replace(replace(q, '\', '\\'), '%', '\%'), '_', '\_');
  return (select coalesce(jsonb_agg(_friend_card(x.id) || jsonb_build_object(
      'state', case when _is_friend(uid, x.id) then 'friend'
                    when exists (select 1 from friend_requests where from_user = uid and to_user = x.id) then 'sent'
                    when exists (select 1 from friend_requests where from_user = x.id and to_user = uid) then 'received'
                    else 'none' end)), '[]'::jsonb)
    from (select p.id from profiles p
          where p.id <> uid and (p.nickname ilike '%' || q || '%' or (char_length(q) = 8 and _friend_code(p.id) = upper(q)))
          order by (_friend_code(p.id) = upper(q)) desc, (p.nickname = btrim(p_q)) desc, char_length(p.nickname) limit 20) x);
end $$;

create or replace function public.friend_request(p_user uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); rid bigint;
begin
  if uid is null then raise exception 'login required'; end if;
  if p_user is null or p_user = uid then raise exception 'invalid user'; end if;
  if not exists (select 1 from profiles where id = p_user) then raise exception 'invalid user'; end if;
  perform pg_advisory_xact_lock(hashtext('friend:' || least(uid, p_user)::text || greatest(uid, p_user)::text));
  if _is_friend(uid, p_user) then raise exception 'already friends'; end if;
  -- 상대가 이미 나에게 신청했다면 바로 수락
  select id into rid from friend_requests where from_user = p_user and to_user = uid;
  if rid is not null then return friend_respond(rid, true); end if;
  if _friend_count(uid) >= _friend_cap() then raise exception 'friend cap'; end if;
  if (select count(*) from friend_requests where from_user = uid) >= 50 then raise exception 'too many requests'; end if;
  insert into friend_requests (from_user, to_user) values (uid, p_user) on conflict do nothing;
  return jsonb_build_object('ok', true, 'state', 'sent');
end $$;

create or replace function public.friend_respond(p_req bigint, p_accept boolean) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); r friend_requests;
begin
  if uid is null then raise exception 'login required'; end if;
  select * into r from friend_requests where id = p_req and to_user = uid;
  if r.id is null then raise exception 'request not found'; end if;
  perform pg_advisory_xact_lock(hashtext('friend:' || least(r.from_user, uid)::text || greatest(r.from_user, uid)::text));
  delete from friend_requests where id = r.id;
  if not coalesce(p_accept, false) then return jsonb_build_object('ok', true, 'state', 'declined'); end if;
  if _friend_count(uid) >= _friend_cap() then raise exception 'friend cap'; end if;
  if _friend_count(r.from_user) >= _friend_cap() then raise exception 'their friend cap'; end if;
  insert into friendships (user_a, user_b) values (least(uid, r.from_user), greatest(uid, r.from_user)) on conflict do nothing;
  delete from friend_requests where from_user = uid and to_user = r.from_user;
  return jsonb_build_object('ok', true, 'state', 'friend');
end $$;

create or replace function public.friend_cancel(p_req bigint) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  delete from friend_requests where id = p_req and from_user = uid;
  if not found then raise exception 'request not found'; end if;
  return jsonb_build_object('ok', true, 'state', 'none');
end $$;

create or replace function public.friend_remove(p_user uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  delete from friendships where user_a = least(uid, p_user) and user_b = greatest(uid, p_user);
  if not found then raise exception 'not friends'; end if;
  return jsonb_build_object('ok', true, 'state', 'none');
end $$;

revoke all on function public.friends_ping(), public.friends_pending_count(), public.friends_list(), public.friends_search(text),
  public.friend_request(uuid), public.friend_respond(bigint, boolean), public.friend_cancel(bigint), public.friend_remove(uuid) from public, anon;
grant execute on function public.friends_ping(), public.friends_pending_count(), public.friends_list(), public.friends_search(text),
  public.friend_request(uuid), public.friend_respond(bigint, boolean), public.friend_cancel(bigint), public.friend_remove(uuid) to authenticated;
