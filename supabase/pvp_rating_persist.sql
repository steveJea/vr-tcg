-- PvP 점수 유지 (시트 33). Supabase SQL Editor 에 이 파일 전체를 붙여 실행.
-- 주간 시즌 행은 보상 정산용으로 남고, 레이팅·승패는 다음 주로 이어진다.
-- TOP10 은 이번 주만 보지 않고, 검증 경기가 있는 플레이어의 가장 최근 점수를 보여 준다.
-- 검증 래더(v3) 이전의 pvp_ratings 점수는 복사하지 않는다. 가짜 플레이어도 넣지 않는다.

create or replace function public._pvp_rating_v3(u uuid, l text, m text, s date) returns public.pvp_ratings_v3
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare r public.pvp_ratings_v3; p public.pvp_ratings_v3;
begin
  select * into p from public.pvp_ratings_v3
   where user_id = u and league = l and mode = m and season < s
   order by season desc limit 1;
  insert into public.pvp_ratings_v3(user_id, league, mode, season, rating, wins, losses, def_wins, def_losses)
  values (u, l, m, s, coalesce(p.rating, 1000), coalesce(p.wins, 0), coalesce(p.losses, 0), coalesce(p.def_wins, 0), coalesce(p.def_losses, 0))
  on conflict do nothing;
  select * into r from public.pvp_ratings_v3 where user_id = u and league = l and mode = m and season = s;
  return r;
end $$;

revoke all on function public._pvp_rating_v3(uuid, text, text, date) from public, anon, authenticated;

create or replace function public.pvp_rankings(p_league text, p_mode text, p_season date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
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
end $$;

revoke all on function public.pvp_rankings(text, text, date) from public;
grant execute on function public.pvp_rankings(text, text, date) to anon, authenticated;

create or replace function public.pvp_user_info(p_league text, p_mode text, p_rank int) returns jsonb
language plpgsql stable security definer set search_path = public as $$
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
end $$;

revoke all on function public.pvp_user_info(text, text, int) from public, anon;
grant execute on function public.pvp_user_info(text, text, int) to authenticated;
