-- =====================================================================
-- 🎨 꾸미기 2차 — 전투 보드 · 카드 테두리 (1차 cosmetics.sql 이후)
-- Supabase SQL Editor 에서 실행. 여러 번 실행해도 안전
-- 선행: cosmetics.sql · gem.sql(_gem_spend) · story/tower/achievements 선택
-- 공개 RPC (교체): cosmetics_status · cosmetics_equip(title,frame,board,border)
--                  · cosmetics_buy(kind,id) · cosmetics_lookup
-- 확인용: select public.cosmetics_status();
-- =====================================================================

alter table public.profiles add column if not exists cosmo_board text;
alter table public.profiles add column if not exists cosmo_border text;

-- kind 확장: title · frame · board · border
alter table public.cosmetic_purchases drop constraint if exists cosmetic_purchases_kind_check;
alter table public.cosmetic_purchases add constraint cosmetic_purchases_kind_check
  check (kind in ('title', 'frame', 'board', 'border'));

create or replace function public._cosmo_board_defs() returns jsonb language sql immutable as $$ select '[
  {"id":"board_basic","name":"기본","how":"기본","shop":null},
  {"id":"board_alley","name":"밤의 골목","how":"일반탑 20층 또는 상점","shop":500},
  {"id":"board_antnest","name":"개미굴","how":"챕터 2 클리어 또는 상점","shop":500},
  {"id":"board_rift","name":"심연 균열","how":"업적 100점·탑 50층 또는 상점","shop":500}
]'::jsonb $$;

create or replace function public._cosmo_border_defs() returns jsonb language sql immutable as $$ select '[
  {"id":"border_basic","name":"기본","how":"기본","shop":null},
  {"id":"border_alley","name":"밤의 골목","how":"일반탑 20층 또는 상점","shop":500},
  {"id":"border_antnest","name":"개미굴","how":"챕터 2 클리어 또는 상점","shop":500},
  {"id":"border_rift","name":"심연 균열","how":"업적 100점·탑 50층 또는 상점","shop":500}
]'::jsonb $$;

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
  elsif p_kind = 'board' then
    if p_id = 'board_basic' then return true; end if;
    if _cosmo_bought(p_uid, 'board', p_id) then return true; end if;
    if p_id = 'board_alley' then return _cosmo_tower(p_uid) >= 20; end if;
    if p_id = 'board_antnest' then return _cosmo_story_ch(p_uid) >= 2; end if;
    if p_id = 'board_rift' then return _cosmo_ach_score(p_uid) >= 100 or _cosmo_tower(p_uid) >= 50; end if;
  elsif p_kind = 'border' then
    if p_id = 'border_basic' then return true; end if;
    if _cosmo_bought(p_uid, 'border', p_id) then return true; end if;
    if p_id = 'border_alley' then return _cosmo_tower(p_uid) >= 20; end if;
    if p_id = 'border_antnest' then return _cosmo_story_ch(p_uid) >= 2; end if;
    if p_id = 'border_rift' then return _cosmo_ach_score(p_uid) >= 100 or _cosmo_tower(p_uid) >= 50; end if;
  end if;
  return false;
end $$;

create or replace function public._cosmo_equip_get(p_uid uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare t text; f text; b text; d text;
begin
  select cosmo_title, cosmo_frame, cosmo_board, cosmo_border into t, f, b, d from profiles where id = p_uid;
  if t is null or not _cosmo_owned(p_uid, 'title', t) then t := 'recruit'; end if;
  if f is null or not _cosmo_owned(p_uid, 'frame', f) then f := 'frame_basic'; end if;
  if b is null or not _cosmo_owned(p_uid, 'board', b) then b := 'board_basic'; end if;
  if d is null or not _cosmo_owned(p_uid, 'border', d) then d := 'border_basic'; end if;
  update profiles set cosmo_title = t, cosmo_frame = f, cosmo_board = b, cosmo_border = d, updated_at = now()
   where id = p_uid and (cosmo_title is distinct from t or cosmo_frame is distinct from f
      or cosmo_board is distinct from b or cosmo_border is distinct from d);
  return jsonb_build_object('title', t, 'frame', f, 'board', b, 'border', d);
end $$;

create or replace function public._cosmo_list(p_uid uuid, p_kind text, p_eq text, p_defs jsonb) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(d || jsonb_build_object(
      'owned', _cosmo_owned(p_uid, p_kind, d->>'id'),
      'equipped', p_eq = (d->>'id'),
      'price', d->'shop') order by ord), '[]'::jsonb)
    from jsonb_array_elements(p_defs) with ordinality t(d, ord) $$;

create or replace function public._cosmo_json(p_uid uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare eq jsonb;
begin
  eq := _cosmo_equip_get(p_uid);
  return jsonb_build_object('ok', true, 'equipped', eq,
    'titles', _cosmo_list(p_uid, 'title', eq->>'title', _cosmo_title_defs()),
    'frames', _cosmo_list(p_uid, 'frame', eq->>'frame', _cosmo_frame_defs()),
    'boards', _cosmo_list(p_uid, 'board', eq->>'board', _cosmo_board_defs()),
    'borders', _cosmo_list(p_uid, 'border', eq->>'border', _cosmo_border_defs()));
end $$;

revoke all on function public._cosmo_board_defs(), public._cosmo_border_defs(), public._cosmo_list(uuid, text, text, jsonb)
  from public, anon, authenticated;

-- drop old 2-arg equip so 4-arg replaces cleanly for PostgREST
drop function if exists public.cosmetics_equip(text, text);

create or replace function public.cosmetics_equip(p_title text, p_frame text, p_board text default null, p_border text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); cur jsonb; t text; f text; b text; d text;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('cosmo:' || uid::text));
  cur := _cosmo_equip_get(uid);
  t := coalesce(p_title, cur->>'title'); f := coalesce(p_frame, cur->>'frame');
  b := coalesce(nullif(p_board, ''), cur->>'board'); d := coalesce(nullif(p_border, ''), cur->>'border');
  if not _cosmo_owned(uid, 'title', t) then raise exception 'not owned'; end if;
  if not _cosmo_owned(uid, 'frame', f) then raise exception 'not owned'; end if;
  if not _cosmo_owned(uid, 'board', b) then raise exception 'not owned'; end if;
  if not _cosmo_owned(uid, 'border', d) then raise exception 'not owned'; end if;
  update profiles set cosmo_title = t, cosmo_frame = f, cosmo_board = b, cosmo_border = d, updated_at = now() where id = uid;
  return _cosmo_json(uid);
end $$;

create or replace function public.cosmetics_buy(p_kind text, p_id text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb; price int; ok boolean; defs jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  if p_kind = 'frame' then defs := _cosmo_frame_defs();
  elsif p_kind = 'board' then defs := _cosmo_board_defs();
  elsif p_kind = 'border' then defs := _cosmo_border_defs();
  else raise exception 'invalid'; end if;
  select x into d from jsonb_array_elements(defs) x where x->>'id' = p_id;
  if d is null then raise exception 'invalid'; end if;
  if d->'shop' is null or jsonb_typeof(d->'shop') = 'null' then raise exception 'not for sale'; end if;
  price := (d->>'shop')::int;
  perform pg_advisory_xact_lock(hashtext('cosmo:' || uid::text));
  perform pg_advisory_xact_lock(hashtext('gem:' || uid::text));
  if _cosmo_owned(uid, p_kind, p_id) then raise exception 'already owned'; end if;
  perform _gem_spend(uid, price, 'cosmo_buy', jsonb_build_object('kind', p_kind, 'id', p_id));
  insert into cosmetic_purchases (user_id, kind, id) values (uid, p_kind, p_id) on conflict do nothing returning true into ok;
  if not coalesce(ok, false) then raise exception 'already owned'; end if;
  return _cosmo_json(uid) || jsonb_build_object('bought', p_id, 'kind', p_kind, 'price', price);
end $$;

create or replace function public.cosmetics_status() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('cosmo:' || uid::text));
  insert into profiles (id) values (uid) on conflict do nothing;
  return _cosmo_json(uid);
end $$;

create or replace function public.cosmetics_lookup(p_ids uuid[]) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  return coalesce((select jsonb_object_agg(id::text, jsonb_build_object(
      'title', coalesce(cosmo_title, 'recruit'),
      'frame', coalesce(cosmo_frame, 'frame_basic'),
      'board', coalesce(cosmo_board, 'board_basic'),
      'border', coalesce(cosmo_border, 'border_basic'),
      'title_name', coalesce((select d->>'name' from jsonb_array_elements(_cosmo_title_defs()) d where d->>'id' = coalesce(p.cosmo_title, 'recruit')), ''),
      'frame_name', coalesce((select d->>'name' from jsonb_array_elements(_cosmo_frame_defs()) d where d->>'id' = coalesce(p.cosmo_frame, 'frame_basic')), '')))
    from profiles p where p.id = any(coalesce(p_ids, '{}'::uuid[]))), '{}'::jsonb);
end $$;

revoke all on function public.cosmetics_status(), public.cosmetics_equip(text, text, text, text), public.cosmetics_buy(text, text), public.cosmetics_lookup(uuid[]) from public, anon;
grant execute on function public.cosmetics_status(), public.cosmetics_equip(text, text, text, text), public.cosmetics_buy(text, text) to authenticated;
grant execute on function public.cosmetics_lookup(uuid[]) to anon, authenticated;
