-- =====================================================================
-- 🎨 꾸미기 1차 — 칭호 + 프로필 프레임 (전투 보드·카드 테두리는 이후)
-- Supabase SQL Editor 에서 실행. 여러 번 실행해도 안전
-- 선행: profiles · phaseE_2(player_state) · tower_v2 · gallery · story_progress
--       · pvp_tier(pvp_titles · pvp_ratings) · guild(guild_titles) · gem.sql(_gem_spend)
--       · achievements.sql(_ach_score) 선택 · daily_social(_gallery_have · _gallery_total) 선택
-- 공개 RPC: cosmetics_status() · cosmetics_equip(title, frame) · cosmetics_buy(kind, id)
--           · cosmetics_lookup(ids)
-- 확인용: select public.cosmetics_status();
-- 소유 = 조건 달성(소급) 또는 심연석 구매. 장착은 보유만. profiles.cosmo_* 에 저장 → 남에게 표시
-- =====================================================================

alter table public.profiles add column if not exists cosmo_title text;
alter table public.profiles add column if not exists cosmo_frame text;

create table if not exists public.cosmetic_purchases (
  user_id uuid not null references auth.users(id) on delete cascade,
  kind    text not null check (kind in ('title', 'frame')),
  id      text not null check (char_length(id) between 1 and 40),
  bought_at timestamptz not null default now(),
  primary key (user_id, kind, id)
);
alter table public.cosmetic_purchases enable row level security;
revoke all on public.cosmetic_purchases from public, anon, authenticated;

-- 칭호 정의
create or replace function public._cosmo_title_defs() returns jsonb language sql immutable as $$ select '[
  {"id":"recruit","name":"신입 대원","how":"기본"},
  {"id":"story_walker","name":"스토리 워커","how":"챕터 5 클리어"},
  {"id":"abyss_witness","name":"심연의 목격자","how":"챕터 15 클리어"},
  {"id":"tower_climber","name":"탑 등반가","how":"일반탑 50층"},
  {"id":"tower_conqueror","name":"탑의 정복자","how":"일반탑 100층"},
  {"id":"collector","name":"수집가","how":"도감 50%"},
  {"id":"pvp_gold","name":"골드","how":"PvP 골드 티어"},
  {"id":"pvp_platinum","name":"플래티넘","how":"PvP 플래티넘 티어"},
  {"id":"pvp_diamond","name":"다이아","how":"PvP 다이아 티어"},
  {"id":"abyss_pioneer","name":"심연 개척자","how":"업적 점수 350"},
  {"id":"abyss","name":"심연","how":"PvP 심연 시즌"}
]'::jsonb $$;

-- 프레임 정의. shop=심연석 가격(없으면 구매 불가)
create or replace function public._cosmo_frame_defs() returns jsonb language sql immutable as $$ select '[
  {"id":"frame_basic","name":"기본","how":"기본","shop":null},
  {"id":"frame_bronze","name":"청동","how":"일반탑 30층","shop":300},
  {"id":"frame_silver","name":"은","how":"도감 25%","shop":300},
  {"id":"frame_gold","name":"금","how":"챕터 10 클리어","shop":300},
  {"id":"frame_abyss","name":"심연","how":"업적 200점 또는 PvP 심연","shop":null},
  {"id":"frame_guild","name":"조직","how":"조직 상점","shop":null}
]'::jsonb $$;

create or replace function public._cosmo_ch_need(p_ch int) returns int language sql immutable as $$
  select case p_ch
    when 0 then 5 when 1 then 5 when 2 then 10 when 3 then 10 when 4 then 10 when 5 then 10
    when 6 then 10 when 7 then 10 when 8 then 15 when 9 then 18 when 10 then 17
    when 11 then 16 when 12 then 21 when 13 then 15 when 14 then 18 when 15 then 16
    else 0 end $$;

create or replace function public._cosmo_story_ch(p_uid uuid) returns int
language plpgsql stable security definer set search_path = public as $$
declare d jsonb; ch text; arr jsonb; n int; mx int := 0;
begin
  if to_regclass('public.story_progress') is null then return 0; end if;
  select data into d from story_progress where user_id = p_uid;
  if d is null or jsonb_typeof(d->'cleared') is distinct from 'object' then return 0; end if;
  for ch, arr in select key, value from jsonb_each(d->'cleared') loop
    if ch ~ '^[0-9]+$' then
      n := case when jsonb_typeof(arr) = 'array' then jsonb_array_length(arr) else 0 end;
      if n >= _cosmo_ch_need(ch::int) and ch::int > mx then mx := ch::int; end if;
    end if;
  end loop;
  return mx;
end $$;

create or replace function public._cosmo_tower(p_uid uuid) returns int language sql stable security definer set search_path = public as $$
  select coalesce((select best_floor from tower_progress where user_id = p_uid and tower = 'normal'), 0) $$;

create or replace function public._cosmo_gallery_pct(p_uid uuid) returns int
language plpgsql stable security definer set search_path = public as $$
declare have int := 0; tot int := 438;
begin
  if to_regclass('public.gallery') is null then return 0; end if;
  if to_regprocedure('public._gallery_have(uuid)') is not null then have := _gallery_have(p_uid);
  else select count(*)::int into have from gallery where user_id = p_uid; end if;
  if to_regprocedure('public._gallery_total()') is not null then tot := _gallery_total(); end if;
  if tot <= 0 then return 0; end if;
  return least(100, (have * 100) / tot);
end $$;

create or replace function public._cosmo_pvp_ord(p_uid uuid) returns int
language plpgsql stable security definer set search_path = public as $$
declare v int := 0;
begin
  if to_regclass('public.pvp_ratings') is null or to_regclass('public.pvp_tier_table') is null then return 0; end if;
  select coalesce(max((select t.ord from pvp_tier_table t where t.min_rating <= coalesce(r.rating, 1000)
                        order by t.min_rating desc limit 1)), 0) into v
    from pvp_ratings r where r.user_id = p_uid;
  return coalesce(v, 0);
end $$;

create or replace function public._cosmo_ach_score(p_uid uuid) returns int language sql stable security definer set search_path = public as $$
  select case when to_regprocedure('public._ach_score(uuid)') is not null then _ach_score(p_uid) else 0 end $$;

create or replace function public._cosmo_bought(p_uid uuid, p_kind text, p_id text) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from cosmetic_purchases where user_id = p_uid and kind = p_kind and id = p_id) $$;

create or replace function public._cosmo_owned(p_uid uuid, p_kind text, p_id text) returns boolean
language plpgsql stable security definer set search_path = public as $$
begin
  if p_kind = 'title' then
    if p_id = 'recruit' then return true; end if;
    if p_id = 'story_walker' then return _cosmo_story_ch(p_uid) >= 5; end if;
    if p_id = 'abyss_witness' then return _cosmo_story_ch(p_uid) >= 15; end if;
    if p_id = 'tower_climber' then return _cosmo_tower(p_uid) >= 50; end if;
    if p_id = 'tower_conqueror' then return _cosmo_tower(p_uid) >= 100; end if;
    if p_id = 'collector' then return _cosmo_gallery_pct(p_uid) >= 50; end if;
    if p_id = 'pvp_gold' then return _cosmo_pvp_ord(p_uid) >= 2; end if;
    if p_id = 'pvp_platinum' then return _cosmo_pvp_ord(p_uid) >= 3; end if;
    if p_id = 'pvp_diamond' then return _cosmo_pvp_ord(p_uid) >= 4; end if;
    if p_id = 'abyss_pioneer' then return _cosmo_ach_score(p_uid) >= 350; end if;
    if p_id = 'abyss' then
      return _cosmo_pvp_ord(p_uid) >= 5
        or (to_regclass('public.pvp_titles') is not null
            and exists (select 1 from pvp_titles where user_id = p_uid and title = 'abyss'));
    end if;
    return _cosmo_bought(p_uid, 'title', p_id);
  elsif p_kind = 'frame' then
    if p_id = 'frame_basic' then return true; end if;
    if _cosmo_bought(p_uid, 'frame', p_id) then return true; end if;
    if p_id = 'frame_bronze' then return _cosmo_tower(p_uid) >= 30; end if;
    if p_id = 'frame_silver' then return _cosmo_gallery_pct(p_uid) >= 25; end if;
    if p_id = 'frame_gold' then return _cosmo_story_ch(p_uid) >= 10; end if;
    if p_id = 'frame_abyss' then
      return _cosmo_ach_score(p_uid) >= 200
        or _cosmo_pvp_ord(p_uid) >= 5
        or (to_regclass('public.pvp_titles') is not null
            and exists (select 1 from pvp_titles where user_id = p_uid and title = 'abyss'));
    end if;
    if p_id = 'frame_guild' then
      return to_regclass('public.guild_titles') is not null
        and exists (select 1 from guild_titles where user_id = p_uid and title = 'guild_frame');
    end if;
  end if;
  return false;
end $$;

create or replace function public._cosmo_equip_get(p_uid uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare t text; f text;
begin
  select cosmo_title, cosmo_frame into t, f from profiles where id = p_uid;
  if t is null or not _cosmo_owned(p_uid, 'title', t) then t := 'recruit'; end if;
  if f is null or not _cosmo_owned(p_uid, 'frame', f) then f := 'frame_basic'; end if;
  update profiles set cosmo_title = t, cosmo_frame = f, updated_at = now() where id = p_uid
    and (cosmo_title is distinct from t or cosmo_frame is distinct from f);
  return jsonb_build_object('title', t, 'frame', f);
end $$;

create or replace function public._cosmo_json(p_uid uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare eq jsonb; titles jsonb; frames jsonb;
begin
  eq := _cosmo_equip_get(p_uid);
  select coalesce(jsonb_agg(d || jsonb_build_object(
      'owned', _cosmo_owned(p_uid, 'title', d->>'id'),
      'equipped', (eq->>'title') = (d->>'id')) order by ord), '[]'::jsonb)
    into titles from jsonb_array_elements(_cosmo_title_defs()) with ordinality t(d, ord);
  select coalesce(jsonb_agg(d || jsonb_build_object(
      'owned', _cosmo_owned(p_uid, 'frame', d->>'id'),
      'equipped', (eq->>'frame') = (d->>'id'),
      'price', d->'shop') order by ord), '[]'::jsonb)
    into frames from jsonb_array_elements(_cosmo_frame_defs()) with ordinality t(d, ord);
  return jsonb_build_object('ok', true, 'equipped', eq, 'titles', titles, 'frames', frames);
end $$;

revoke all on function public._cosmo_title_defs(), public._cosmo_frame_defs(), public._cosmo_ch_need(int),
  public._cosmo_story_ch(uuid), public._cosmo_tower(uuid), public._cosmo_gallery_pct(uuid),
  public._cosmo_pvp_ord(uuid), public._cosmo_ach_score(uuid), public._cosmo_bought(uuid, text, text),
  public._cosmo_owned(uuid, text, text), public._cosmo_equip_get(uuid), public._cosmo_json(uuid)
  from public, anon, authenticated;

create or replace function public.cosmetics_status() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('cosmo:' || uid::text));
  insert into profiles (id) values (uid) on conflict do nothing;
  return _cosmo_json(uid);
end $$;

create or replace function public.cosmetics_equip(p_title text, p_frame text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('cosmo:' || uid::text));
  if p_title is null or p_frame is null then raise exception 'invalid'; end if;
  if not _cosmo_owned(uid, 'title', p_title) then raise exception 'not owned'; end if;
  if not _cosmo_owned(uid, 'frame', p_frame) then raise exception 'not owned'; end if;
  update profiles set cosmo_title = p_title, cosmo_frame = p_frame, updated_at = now() where id = uid;
  return _cosmo_json(uid);
end $$;

create or replace function public.cosmetics_buy(p_kind text, p_id text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb; price int; ok boolean;
begin
  if uid is null then raise exception 'login required'; end if;
  if p_kind is distinct from 'frame' then raise exception 'invalid'; end if;
  select x into d from jsonb_array_elements(_cosmo_frame_defs()) x where x->>'id' = p_id;
  if d is null then raise exception 'invalid'; end if;
  if d->'shop' is null or jsonb_typeof(d->'shop') = 'null' then raise exception 'not for sale'; end if;
  price := (d->>'shop')::int;
  perform pg_advisory_xact_lock(hashtext('cosmo:' || uid::text));
  perform pg_advisory_xact_lock(hashtext('gem:' || uid::text));
  if _cosmo_owned(uid, 'frame', p_id) then raise exception 'already owned'; end if;
  perform _gem_spend(uid, price, 'cosmo_buy', jsonb_build_object('id', p_id));
  insert into cosmetic_purchases (user_id, kind, id) values (uid, 'frame', p_id) on conflict do nothing returning true into ok;
  if not coalesce(ok, false) then raise exception 'already owned'; end if;
  return _cosmo_json(uid) || jsonb_build_object('bought', p_id, 'price', price);
end $$;

create or replace function public.cosmetics_lookup(p_ids uuid[]) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  return coalesce((select jsonb_object_agg(id::text, jsonb_build_object(
      'title', coalesce(cosmo_title, 'recruit'),
      'frame', coalesce(cosmo_frame, 'frame_basic'),
      'title_name', coalesce((select d->>'name' from jsonb_array_elements(_cosmo_title_defs()) d where d->>'id' = coalesce(p.cosmo_title, 'recruit')), ''),
      'frame_name', coalesce((select d->>'name' from jsonb_array_elements(_cosmo_frame_defs()) d where d->>'id' = coalesce(p.cosmo_frame, 'frame_basic')), '')))
    from profiles p where p.id = any(coalesce(p_ids, '{}'::uuid[]))), '{}'::jsonb);
end $$;

revoke all on function public.cosmetics_status(), public.cosmetics_equip(text, text), public.cosmetics_buy(text, text), public.cosmetics_lookup(uuid[]) from public, anon;
grant execute on function public.cosmetics_status(), public.cosmetics_equip(text, text), public.cosmetics_buy(text, text) to authenticated;
grant execute on function public.cosmetics_lookup(uuid[]) to anon, authenticated;

-- 친구 카드에 칭호·프레임
create or replace function public._friend_card(p uuid) returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('user_id', p, 'code', _friend_code(p),
    'name', coalesce((select nickname from profiles where id = p), '플레이어'),
    'avatar', (select avatar_url from profiles where id = p),
    'level', coalesce((select level from player_state where user_id = p), 1),
    'seen_at', (select seen_at from player_presence where user_id = p),
    'online', coalesce((select seen_at > now() - interval '5 minutes' from player_presence where user_id = p), false),
    'title', coalesce((select cosmo_title from profiles where id = p), 'recruit'),
    'frame', coalesce((select cosmo_frame from profiles where id = p), 'frame_basic'),
    'title_name', coalesce((select d->>'name' from jsonb_array_elements(_cosmo_title_defs()) d
      where d->>'id' = coalesce((select cosmo_title from profiles where id = p), 'recruit')), '신입 대원')) $$;

-- 랭킹에 칭호·프레임
create or replace function public.tower_rankings(p_tower text default 'normal') returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); top jsonb; mine jsonb;
begin
  if p_tower not in ('normal', 'wind', 'ice', 'fire', 'light', 'dark') then raise exception 'bad tower'; end if;
  with t as (select g.user_id, g.best_floor, g.clears, rank() over (order by g.best_floor desc) rk, row_number() over (order by g.best_floor desc, g.updated_at) rn
             from tower_progress g where g.tower = p_tower and g.best_floor > 0)
  select coalesce(jsonb_agg(jsonb_build_object('rank', rk, 'name', coalesce(p.nickname, '플레이어'), 'floor', best_floor, 'me', t.user_id = uid,
           'title', coalesce(p.cosmo_title, 'recruit'), 'frame', coalesce(p.cosmo_frame, 'frame_basic'),
           'title_name', coalesce((select d->>'name' from jsonb_array_elements(_cosmo_title_defs()) d where d->>'id' = coalesce(p.cosmo_title, 'recruit')), '')) order by rn), '[]'::jsonb)
    into top from (select * from t order by rn limit 50) t left join profiles p on p.id = t.user_id;
  with t as (select g.user_id, g.best_floor, rank() over (order by g.best_floor desc) rk
             from tower_progress g where g.tower = p_tower and g.best_floor > 0)
  select jsonb_build_object('rank', rk, 'floor', best_floor) into mine from t where t.user_id = uid;
  return jsonb_build_object('top', top, 'me', mine);
end $$;

create or replace function public.story_rankings() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); top jsonb; mine jsonb;
begin
  with c as (
    select s.user_id, s.updated_at, (k.key)::int ch, max((v.value)::int) ph, count(*) n
      from story_progress s, jsonb_each(case when jsonb_typeof(s.data->'cleared') = 'object' then s.data->'cleared' else '{}'::jsonb end) k,
           jsonb_array_elements_text(case when jsonb_typeof(k.value) = 'array' then k.value else '[]'::jsonb end) v
     where k.key ~ '^[0-9]{1,3}$' and v.value ~ '^[0-9]{1,3}$'
     group by s.user_id, s.updated_at, k.key),
  b as (select distinct on (user_id) user_id, updated_at, ch, ph from c order by user_id, ch desc),
  tot as (select user_id, sum(n)::int total from c group by user_id),
  t as (select b.*, tot.total, rank() over (order by ch desc, ph desc) rk, row_number() over (order by ch desc, ph desc, tot.total desc, b.updated_at) rn
          from b join tot using (user_id))
  select coalesce((select jsonb_agg(jsonb_build_object('rank', rk, 'name', coalesce(p.nickname, '플레이어'), 'ch', ch, 'ph', ph, 'total', total, 'me', t.user_id = uid,
                     'title', coalesce(p.cosmo_title, 'recruit'), 'frame', coalesce(p.cosmo_frame, 'frame_basic'),
                     'title_name', coalesce((select d->>'name' from jsonb_array_elements(_cosmo_title_defs()) d where d->>'id' = coalesce(p.cosmo_title, 'recruit')), '')) order by rn)
                     from (select * from t order by rn limit 50) t left join profiles p on p.id = t.user_id), '[]'::jsonb),
         (select jsonb_build_object('rank', rk, 'ch', ch, 'ph', ph, 'total', total) from t where t.user_id = uid)
    into top, mine;
  return jsonb_build_object('top', top, 'me', mine);
end $$;

create or replace function public.pvp_rankings(p_league text, p_mode text, p_season date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); s date := p_season; top jsonb; mine jsonb;
begin
  perform _pvp_ok(p_league, p_mode);
  with latest as (
    select distinct on (r.user_id) r.user_id, r.rating, r.wins, r.losses
      from pvp_ratings r
     where r.league = p_league and r.mode = p_mode and (s is null or r.season = s) and r.wins + r.losses > 0
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
      from pvp_ratings r
     where r.league = p_league and r.mode = p_mode and (s is null or r.season = s) and r.wins + r.losses > 0
     order by r.user_id, r.season desc),
  t as (select user_id, rating, wins, losses, rank() over (order by rating desc, wins desc) rk from latest)
  select jsonb_build_object('rank', rk, 'rating', rating, 'wins', wins, 'losses', losses, 'tier', _pvp_tier(rating)) into mine from t where t.user_id = uid;
  return jsonb_build_object('season', coalesce(s, _pvp_season()), 'top', top, 'me', mine);
end $$;

revoke all on function public.tower_rankings(text), public.story_rankings(), public.pvp_rankings(text, text, date) from public;
grant execute on function public.tower_rankings(text), public.story_rankings(), public.pvp_rankings(text, text, date) to anon, authenticated;
