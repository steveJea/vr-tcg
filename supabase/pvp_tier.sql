-- =====================================================================
-- PvP 티어 · 시즌 티어 보상 · 연승 보너스 (pvp.sql 다음에 실행). 여러 번 실행해도 안전.
--   티어(시즌 레이팅): 브론즈 <950 · 실버 950 · 골드 1050 · 플래티넘 1150 · 다이아 1250 · 심연 1400
--   시즌 티어 보상: 지난 시즌 3판 이상 → pvp_claim_tier 로 1회 (리그·모드·시즌별). 심연 = 한정 칭호·프레임(pvp_titles)
--   연승: 이번 시즌 연속 승리 3·5·10 달성 판의 결과 보고 때 서버가 바로 지급 (보고는 판당 1번 → 중복 없음)
--   연승 계산: 같은 리그·모드·시즌 기록에서 가장 최근 패배(미보고 판 = 패배) 이후 승리 수. 진행 중(1시간 안 미보고) 판은 제외
-- =====================================================================

-- 1) 표
create table if not exists public.pvp_tier_table (
  tier text primary key, ord int not null, min_rating int not null, reward jsonb not null);
insert into public.pvp_tier_table (tier, ord, min_rating, reward) values
  ('bronze',   0,    0, '{"gold":200}'),
  ('silver',   1,  950, '{"gold":400,"shard":5,"gem":50}'),
  ('gold',     2, 1050, '{"gold":800,"soul":5,"tickets":3,"gem":100}'),
  ('platinum', 3, 1150, '{"gold":1500,"soul":10,"tickets":5,"gem":200}'),
  ('diamond',  4, 1250, '{"gold":2500,"soul":20,"tickets":10,"gem":400}'),
  ('abyss',    5, 1400, '{"gold":4000,"soul":35,"tickets":20,"gem":1000,"title":"abyss"}')
on conflict (tier) do update set ord = excluded.ord, min_rating = excluded.min_rating, reward = excluded.reward;

create table if not exists public.pvp_streak_table (n int primary key, reward jsonb not null);
insert into public.pvp_streak_table (n, reward) values
  (3, '{"gold":300}'), (5, '{"gold":600,"soul":5}'), (10, '{"gold":1500,"soul":15,"tickets":3,"gem":30}')
on conflict (n) do update set reward = excluded.reward;

create table if not exists public.pvp_tier_claims (
  user_id uuid not null references auth.users(id) on delete cascade,
  league text not null, mode text not null, season date not null, tier text not null, rating int not null, reward jsonb not null,
  claimed_at timestamptz not null default now(), primary key (user_id, league, mode, season));
create table if not exists public.pvp_titles (
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null, league text not null, mode text not null, season date not null,
  granted_at timestamptz not null default now(), primary key (user_id, title, league, mode, season));
alter table public.pvp_attempts add column if not exists streak int;            -- 보고 시점 연승 (승리 판만)
alter table public.pvp_attempts add column if not exists streak_reward jsonb;   -- 연승 보너스 지급 내역

alter table public.pvp_tier_table enable row level security;
alter table public.pvp_streak_table enable row level security;
alter table public.pvp_tier_claims enable row level security;
alter table public.pvp_titles enable row level security;
drop policy if exists pvp_tier_read on public.pvp_tier_table;      create policy pvp_tier_read on public.pvp_tier_table for select using (true);
drop policy if exists pvp_streak_read on public.pvp_streak_table;  create policy pvp_streak_read on public.pvp_streak_table for select using (true);
drop policy if exists pvp_tier_claims_own on public.pvp_tier_claims; create policy pvp_tier_claims_own on public.pvp_tier_claims for select using (auth.uid() = user_id);
drop policy if exists pvp_titles_own on public.pvp_titles;         create policy pvp_titles_own on public.pvp_titles for select using (auth.uid() = user_id);
revoke insert, update, delete on public.pvp_tier_table, public.pvp_streak_table, public.pvp_tier_claims, public.pvp_titles from anon, authenticated;

-- 2) 내부 함수
create or replace function public._pvp_tier(p_rating int) returns text language sql stable set search_path = public as $$
  select tier from pvp_tier_table where min_rating <= coalesce(p_rating, 1000) order by min_rating desc limit 1 $$;
-- 보상 지급: gold/blood/shard/soul → 지갑, tickets → 소환권, title → pvp_titles
create or replace function public._pvp_grant(p_uid uuid, p_rw jsonb, p_reason text, p_league text, p_mode text, p_season date) returns void
language plpgsql security definer set search_path = public as $$
declare w jsonb := p_rw - 'tickets' - 'title' - 'gem';
begin
  if w <> '{}'::jsonb then perform _wallet_add(p_uid, w, p_reason); end if;
  if coalesce((p_rw->>'tickets')::int, 0) > 0 then
    insert into story_gacha (user_id, last_draw) values (p_uid, _pvp_day() - 1) on conflict (user_id) do nothing;
    update story_gacha set tickets = tickets + (p_rw->>'tickets')::int, updated_at = now() where user_id = p_uid;
  end if;
  if coalesce((p_rw->>'gem')::int, 0) > 0 and to_regprocedure('public._gem_add(uuid,integer,integer,text,text,jsonb)') is not null then   -- 심연석 (gem.sql)
    perform _gem_add(p_uid, (p_rw->>'gem')::int, 0, p_reason, case when p_reason = 'pvp_tier' then 'pvp_tier:' || p_league || ':' || p_mode || ':' || p_season end, jsonb_build_object('league', p_league, 'mode', p_mode, 'season', p_season));
  end if;
  if p_rw ? 'title' then
    insert into pvp_titles (user_id, title, league, mode, season) values (p_uid, p_rw->>'title', p_league, p_mode, p_season) on conflict do nothing;
  end if;
end $$;
-- 연승 (p_upto: 이 판 id 까지. null = 전부, 진행 중 판 제외)
create or replace function public._pvp_streak(p_uid uuid, p_league text, p_mode text, p_season date, p_upto bigint default null) returns int
language sql stable set search_path = public as $$
  select count(*)::int from pvp_attempts a
  where a.user_id = p_uid and a.league = p_league and a.mode = p_mode and a.season = p_season and a.win
    and (p_upto is null or a.id <= p_upto)
    and a.id > coalesce((select max(b.id) from pvp_attempts b where b.user_id = p_uid and b.league = p_league and b.mode = p_mode and b.season = p_season
                          and not b.win and (p_upto is null or b.id <= p_upto)
                          and (b.reported_at is not null or now() - b.created_at > interval '1 hour')), 0) $$;
revoke all on function public._pvp_tier(int), public._pvp_grant(uuid, jsonb, text, text, text, date), public._pvp_streak(uuid, text, text, date, bigint) from public, anon, authenticated;

-- 3) 상태: 기존 + 연승 · 심연 칭호 · 티어표 · 연승표 · 지난 시즌 미수령 티어 보상
create or replace function public.pvp_status(p_league text, p_mode text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); n int := _pvp_ok(p_league, p_mode); used int; r pvp_ratings; decks jsonb; prev pvp_ratings; pend jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  select count(*) into used from pvp_attempts where user_id = uid and league = p_league and mode = p_mode and day = _pvp_day();
  r := _pvp_rating(uid, p_league, p_mode);
  select coalesce(jsonb_agg(jsonb_build_object('slot', slot, 'uids', uids, 'cost', cost) order by slot), '[]'::jsonb) into decks
    from pvp_decks where user_id = uid and league = p_league and mode = p_mode;
  select * into prev from pvp_ratings where user_id = uid and league = p_league and mode = p_mode and season = _pvp_season() - 7;
  if prev.user_id is not null and prev.wins + prev.losses >= 3
     and not exists (select 1 from pvp_tier_claims where user_id = uid and league = p_league and mode = p_mode and season = prev.season) then
    pend := jsonb_build_object('season', prev.season, 'rating', prev.rating, 'tier', _pvp_tier(prev.rating));
  end if;
  return jsonb_build_object('left', greatest(0, 10 + _pvp_extra(uid, p_league, p_mode) - used), 'max', 10 + _pvp_extra(uid, p_league, p_mode), 'rating', r.rating, 'wins', r.wins, 'losses', r.losses,
    'def_wins', r.def_wins, 'def_losses', r.def_losses, 'decks', decks, 'need', n,
    'season', _pvp_season(), 'season_end', ((_pvp_season() + 7)::timestamp at time zone 'Asia/Seoul'),
    'tier', _pvp_tier(r.rating), 'streak', _pvp_streak(uid, p_league, p_mode, _pvp_season()),
    'abyss', exists (select 1 from pvp_titles where user_id = uid and title = 'abyss'),
    'tiers', (select jsonb_agg(jsonb_build_object('tier', tier, 'min', min_rating, 'reward', reward) order by ord) from pvp_tier_table),
    'streaks', (select jsonb_agg(jsonb_build_object('n', s.n, 'reward', s.reward) order by s.n) from pvp_streak_table s),
    'pending', pend);
end $$;

-- 4) 결과 보고: 기존 + 연승 계산·보너스 지급
create or replace function public.pvp_report(p_id bigint, p_wins int, p_losses int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); a pvp_attempts; n int; need int; v_win boolean; r int; sk int := 0; srw jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  select * into a from pvp_attempts where id = p_id and user_id = uid for update;
  if a.id is null then raise exception 'not found'; end if;
  if a.reported_at is not null then raise exception 'already reported'; end if;
  if now() - a.created_at > interval '1 hour' then raise exception 'expired'; end if;
  n := _pvp_ok(a.league, a.mode); need := case when n = 3 then 2 else 1 end;
  if p_wins is null or p_losses is null or p_wins < 0 or p_losses < 0 or p_wins > need or p_losses > need
     or not (p_wins = need or p_losses = need) or (p_wins = need and p_losses = need) then raise exception 'bad result'; end if;
  v_win := p_wins = need;
  update pvp_attempts set reported_at = now(), wins = p_wins, losses = p_losses, win = v_win where id = p_id;
  if v_win then
    update pvp_ratings set rating = rating + a.dl + a.dw, wins = wins + 1, losses = losses - 1, updated_at = now()
      where user_id = uid and league = a.league and mode = a.mode and season = a.season;
    if a.opp_user is not null then
      update pvp_ratings set rating = rating - a.dl / 2 - a.dw / 2, def_wins = def_wins - 1, def_losses = def_losses + 1, updated_at = now()
        where user_id = a.opp_user and league = a.league and mode = a.mode and season = a.season;
    end if;
    sk := _pvp_streak(uid, a.league, a.mode, a.season, p_id);
    select reward into srw from pvp_streak_table where pvp_streak_table.n = sk;
    if srw is not null then perform _pvp_grant(uid, srw, 'pvp_streak', a.league, a.mode, a.season); end if;
    update pvp_attempts set streak = sk, streak_reward = srw where id = p_id;
    -- 조직 세력 (guild.sql): 승리당 +10 (하루 상한은 _guild_feed 가 처리)
    if to_regprocedure('public._guild_feed(uuid,text,integer)') is not null then perform _guild_feed(uid, 'pvp', 10); end if;
  end if;
  select rating into r from pvp_ratings where user_id = uid and league = a.league and mode = a.mode and season = a.season;
  return jsonb_build_object('ok', true, 'win', v_win, 'rating', r, 'delta', case when v_win then a.dw else -a.dl end,
    'tier', _pvp_tier(r), 'streak', sk, 'streak_reward', srw);
end $$;

-- 5) 랭킹: 기존 + 티어 · 심연 칭호
create or replace function public.pvp_rankings(p_league text, p_mode text, p_season date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); s date := coalesce(p_season, _pvp_season()); top jsonb; mine jsonb;
begin
  perform _pvp_ok(p_league, p_mode);
  with t as (select r.user_id, r.rating, r.wins, r.losses, rank() over (order by r.rating desc, r.wins desc) rk
             from pvp_ratings r where r.league = p_league and r.mode = p_mode and r.season = s and r.wins + r.losses > 0)
  select coalesce(jsonb_agg(jsonb_build_object('rank', rk, 'name', coalesce(p.nickname, '플레이어'), 'rating', rating, 'wins', wins, 'losses', losses,
           'me', t.user_id = uid, 'tier', _pvp_tier(rating), 'abyss', exists (select 1 from pvp_titles x where x.user_id = t.user_id and x.title = 'abyss')) order by rk), '[]'::jsonb)
    into top from (select * from t order by rk limit 100) t left join profiles p on p.id = t.user_id;
  with t as (select r.user_id, r.rating, r.wins, r.losses, rank() over (order by r.rating desc, r.wins desc) rk
             from pvp_ratings r where r.league = p_league and r.mode = p_mode and r.season = s and r.wins + r.losses > 0)
  select jsonb_build_object('rank', rk, 'rating', rating, 'wins', wins, 'losses', losses, 'tier', _pvp_tier(rating)) into mine from t where t.user_id = uid;
  return jsonb_build_object('season', s, 'top', top, 'me', mine);
end $$;

-- 6) 지난 시즌 티어 보상 받기 (리그·모드·시즌별 1회, 3판 이상)
create or replace function public.pvp_claim_tier(p_league text, p_mode text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); s date := _pvp_season() - 7; r pvp_ratings; t text; rw jsonb; ok boolean;
begin
  if uid is null then raise exception 'login required'; end if;
  perform _pvp_ok(p_league, p_mode);
  perform pg_advisory_xact_lock(hashtext('pvptier:' || uid::text));
  select * into r from pvp_ratings where user_id = uid and league = p_league and mode = p_mode and season = s;
  if r.user_id is null or r.wins + r.losses < 3 then raise exception 'not eligible'; end if;
  t := _pvp_tier(r.rating);
  select reward into rw from pvp_tier_table where tier = t;
  insert into pvp_tier_claims (user_id, league, mode, season, tier, rating, reward) values (uid, p_league, p_mode, s, t, r.rating, rw)
    on conflict do nothing returning true into ok;
  if not coalesce(ok, false) then raise exception 'already claimed'; end if;
  perform _pvp_grant(uid, rw, 'pvp_tier', p_league, p_mode, s);
  return jsonb_build_object('ok', true, 'season', s, 'tier', t, 'rating', r.rating, 'reward', rw);
end $$;

revoke all on function public.pvp_status(text, text), public.pvp_report(bigint, int, int), public.pvp_claim_tier(text, text) from public, anon;
grant execute on function public.pvp_status(text, text), public.pvp_report(bigint, int, int), public.pvp_claim_tier(text, text) to authenticated;
revoke all on function public.pvp_rankings(text, text, date) from public;
grant execute on function public.pvp_rankings(text, text, date) to anon, authenticated;
