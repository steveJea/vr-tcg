-- =====================================================================
-- 🎁 방치 보상 상자 — 꺼둔 동안 골드·이상한 조각·순수한 피·장비 가루 누적
-- Supabase SQL Editor 에서 실행. 여러 번 실행해도 안전 (테이블·데이터 삭제 없음)
-- 선행: phaseE_1.sql(_wallet_add) · phaseE_2.sql(player_state) · gem.sql(_gem_spend · _gem_day)
--       · gear_craft.sql(_gear_dust_add) · gear_v1.sql(_gear_meta)
-- 시간: 서버 now(). 첫 생성 시 last_claim = now() (소급 없음). 상한 8시간
-- 시간당(플레이어 Lv): 골드 400+Lv×20 · 조각 1+floor(Lv/10) · 피 1+floor(Lv/20) · 가루 1+floor(Lv/25)
-- 빠른 보상: 심연석 30 → 4시간분 즉시 · 하루 2회(KST _gem_day)
-- 공개 RPC: idle_box_status() · idle_box_claim() · idle_box_boost()
-- 확인용: select public.idle_box_status();
-- =====================================================================

create table if not exists public.idle_box (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  last_claim timestamptz not null default now(),
  boost_day  date,
  boost_n    int not null default 0 check (boost_n >= 0),
  updated_at timestamptz not null default now()
);
alter table public.idle_box enable row level security;
revoke all on public.idle_box from public, anon, authenticated;

create or replace function public._idle_max_hours() returns numeric language sql immutable as $$ select 8 $$;
create or replace function public._idle_boost_hours() returns numeric language sql immutable as $$ select 4 $$;
create or replace function public._idle_boost_cost() returns int language sql immutable as $$ select 30 $$;
create or replace function public._idle_boost_max() returns int language sql immutable as $$ select 2 $$;

create or replace function public._idle_rate(p_lv int) returns jsonb language sql immutable as $$
  select jsonb_build_object(
    'gold',  400 + 20 * greatest(p_lv, 1),
    'shard', 1 + (greatest(p_lv, 1) / 10),
    'blood', 1 + (greatest(p_lv, 1) / 20),
    'dust',  1 + (greatest(p_lv, 1) / 25)) $$;

create or replace function public._idle_amt(p_rate jsonb, p_hrs numeric) returns jsonb language sql immutable as $$
  select jsonb_build_object(
    'gold',  floor((p_rate->>'gold')::numeric  * p_hrs)::int,
    'shard', floor((p_rate->>'shard')::numeric * p_hrs)::int,
    'blood', floor((p_rate->>'blood')::numeric * p_hrs)::int,
    'dust',  floor((p_rate->>'dust')::numeric  * p_hrs)::int) $$;

create or replace function public._idle_plv(p_uid uuid) returns int language plpgsql stable security definer set search_path = public as $$
declare lv int := 1;
begin
  if to_regclass('public.player_state') is not null then
    select coalesce(level, 1) into lv from player_state where user_id = p_uid;
  end if;
  return greatest(coalesce(lv, 1), 1);
end $$;

create or replace function public._idle_row(p_uid uuid) returns public.idle_box
language plpgsql security definer set search_path = public as $$
declare r idle_box;
begin
  insert into idle_box (user_id, last_claim) values (p_uid, now()) on conflict do nothing;
  select * into r from idle_box where user_id = p_uid for update;
  return r;
end $$;

create or replace function public._idle_hours(p_last timestamptz) returns numeric language sql stable as $$
  select least(_idle_max_hours(), greatest(0, extract(epoch from (now() - p_last)) / 3600.0)) $$;

create or replace function public._idle_grant(p_uid uuid, p_got jsonb, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare w jsonb := null; d bigint := null; cur jsonb := '{}'::jsonb;
begin
  if coalesce((p_got->>'gold')::int, 0) > 0 then cur := cur || jsonb_build_object('gold', (p_got->>'gold')::int); end if;
  if coalesce((p_got->>'shard')::int, 0) > 0 then cur := cur || jsonb_build_object('shard', (p_got->>'shard')::int); end if;
  if coalesce((p_got->>'blood')::int, 0) > 0 then cur := cur || jsonb_build_object('blood', (p_got->>'blood')::int); end if;
  if cur <> '{}'::jsonb then w := _wallet_add(p_uid, cur, p_reason); end if;
  if coalesce((p_got->>'dust')::int, 0) > 0 then
    if to_regprocedure('public._gear_dust_add(uuid,bigint)') is null then raise exception 'dust unavailable'; end if;
    d := _gear_dust_add(p_uid, (p_got->>'dust')::bigint);
  end if;
  return jsonb_build_object('wallet', w, 'dust', d);
end $$;

create or replace function public._idle_json(p_uid uuid, p_r idle_box) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare lv int := _idle_plv(p_uid); rate jsonb := _idle_rate(lv); hrs numeric; got jsonb;
  today date := _gem_day(); boost_left int; boost_n int;
begin
  hrs := _idle_hours(p_r.last_claim);
  got := _idle_amt(rate, hrs);
  boost_n := case when p_r.boost_day = today then p_r.boost_n else 0 end;
  boost_left := greatest(0, _idle_boost_max() - boost_n);
  return jsonb_build_object('ok', true, 'now', now(), 'level', lv, 'rate', rate, 'hours', round(hrs::numeric, 3),
    'max_hours', _idle_max_hours(), 'full', hrs >= _idle_max_hours(),
    'pending', got, 'ready', (got->>'gold')::int > 0 or (got->>'shard')::int > 0 or (got->>'blood')::int > 0 or (got->>'dust')::int > 0,
    'last_claim', p_r.last_claim,
    'boost', jsonb_build_object('cost', _idle_boost_cost(), 'hours', _idle_boost_hours(), 'left', boost_left, 'max', _idle_boost_max(),
      'reward', _idle_amt(rate, _idle_boost_hours())));
end $$;

revoke all on function public._idle_max_hours(), public._idle_boost_hours(), public._idle_boost_cost(), public._idle_boost_max(),
  public._idle_rate(int), public._idle_amt(jsonb, numeric), public._idle_plv(uuid), public._idle_row(uuid),
  public._idle_hours(timestamptz), public._idle_grant(uuid, jsonb, text), public._idle_json(uuid, idle_box)
  from public, anon, authenticated;

create or replace function public.idle_box_status() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); r idle_box;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('idle:' || uid::text));
  r := _idle_row(uid);
  return _idle_json(uid, r);
end $$;

create or replace function public.idle_box_claim() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); r idle_box; j jsonb; got jsonb; res jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('idle:' || uid::text));
  r := _idle_row(uid);
  j := _idle_json(uid, r);
  if not coalesce((j->>'ready')::boolean, false) then raise exception 'not done'; end if;
  got := j->'pending';
  res := _idle_grant(uid, got, 'idle_box');
  update idle_box set last_claim = now(), updated_at = now() where user_id = uid;
  select * into r from idle_box where user_id = uid;
  return _idle_json(uid, r) || res || jsonb_build_object('got', got);
end $$;

create or replace function public.idle_box_boost() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); r idle_box; today date := _gem_day(); boost_n int; got jsonb; res jsonb; gem jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('idle:' || uid::text));
  perform pg_advisory_xact_lock(hashtext('gem:' || uid::text));
  r := _idle_row(uid);
  boost_n := case when r.boost_day = today then r.boost_n else 0 end;
  if boost_n >= _idle_boost_max() then raise exception 'daily limit'; end if;
  got := _idle_amt(_idle_rate(_idle_plv(uid)), _idle_boost_hours());
  gem := _gem_spend(uid, _idle_boost_cost(), 'idle_boost', jsonb_build_object('hours', _idle_boost_hours()));
  res := _idle_grant(uid, got, 'idle_boost');
  update idle_box set boost_day = today, boost_n = boost_n + 1, updated_at = now() where user_id = uid;
  select * into r from idle_box where user_id = uid;
  return _idle_json(uid, r) || res || jsonb_build_object('got', got, 'gem', gem);
end $$;

revoke all on function public.idle_box_status(), public.idle_box_claim(), public.idle_box_boost() from public, anon;
grant execute on function public.idle_box_status(), public.idle_box_claim(), public.idle_box_boost() to authenticated;
