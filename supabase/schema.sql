-- =====================================================================
-- VR: Abyss Gate - Supabase 스키마 (계정 / 클라우드 저장 / 전적 / 랭킹)
-- 사용법: Supabase 대시보드 > SQL Editor > New query 에 전체 붙여넣고 Run.
-- 여러 번 실행해도 안전하도록(idempotent) 작성됨.
-- =====================================================================

-- 1) 프로필: 로그인 유저 1명당 1행 (닉네임/아바타)
create table if not exists public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  nickname    text not null default '플레이어' check (char_length(nickname) between 1 and 20),
  avatar_url  text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- 2) 클라우드 세이브: 브라우저 localStorage 내용(전적·설정)을 jsonb로 저장
create table if not exists public.saves (
  user_id     uuid primary key references auth.users(id) on delete cascade,
  data        jsonb not null default '{}'::jsonb,
  updated_at  timestamptz not null default now()
);

-- 3) 판별 결과 기록 (랭킹 계산용)
create table if not exists public.matches (
  id          bigint generated always as identity primary key,
  user_id     uuid not null references auth.users(id) on delete cascade default auth.uid(),
  result      text not null check (result in ('win','lose','draw')),
  reason      text check (char_length(reason) <= 20),
  turns       int  not null default 0 check (turns between 0 and 200),
  damage      int  not null default 0 check (damage between 0 and 10000000),
  skills      int  not null default 0 check (skills between 0 and 1000),
  mvp_id      text check (char_length(mvp_id) <= 40),
  mvp_name    text check (char_length(mvp_name) <= 40),
  merc_id     text check (char_length(merc_id) <= 40),
  created_at  timestamptz not null default now()
);
create index if not exists matches_user_created_idx on public.matches (user_id, created_at desc);
create index if not exists matches_created_idx on public.matches (created_at desc);

-- 4) 신규 가입 시 프로필 자동 생성 (구글 이름/사진 사용)
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, nickname, avatar_url)
  values (
    new.id,
    left(coalesce(new.raw_user_meta_data->>'name', new.raw_user_meta_data->>'full_name', split_part(new.email, '@', 1), '플레이어'), 20),
    new.raw_user_meta_data->>'avatar_url'
  )
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- 5) RLS: 본인 행만 읽기/쓰기
alter table public.profiles enable row level security;
alter table public.saves    enable row level security;
alter table public.matches  enable row level security;

drop policy if exists "profiles_own_select" on public.profiles;
drop policy if exists "profiles_own_insert" on public.profiles;
drop policy if exists "profiles_own_update" on public.profiles;
create policy "profiles_own_select" on public.profiles for select using (auth.uid() = id);
create policy "profiles_own_insert" on public.profiles for insert with check (auth.uid() = id);
create policy "profiles_own_update" on public.profiles for update using (auth.uid() = id) with check (auth.uid() = id);

drop policy if exists "saves_own_select" on public.saves;
drop policy if exists "saves_own_insert" on public.saves;
drop policy if exists "saves_own_update" on public.saves;
create policy "saves_own_select" on public.saves for select using (auth.uid() = user_id);
create policy "saves_own_insert" on public.saves for insert with check (auth.uid() = user_id);
create policy "saves_own_update" on public.saves for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- 전적은 기록(insert)과 조회만 가능. 수정/삭제 불가.
drop policy if exists "matches_own_select" on public.matches;
drop policy if exists "matches_own_insert" on public.matches;
create policy "matches_own_select" on public.matches for select using (auth.uid() = user_id);
create policy "matches_own_insert" on public.matches for insert with check (auth.uid() = user_id);

-- 간단한 도배 방지: 같은 유저가 20초 안에 연속 기록 불가
create or replace function public.matches_rate_limit()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from public.matches
             where user_id = new.user_id and created_at > now() - interval '20 seconds') then
    raise exception 'too many matches';
  end if;
  new.created_at := now();
  return new;
end $$;
drop trigger if exists matches_rate_limit on public.matches;
create trigger matches_rate_limit before insert on public.matches
  for each row execute function public.matches_rate_limit();

-- 6) 랭킹 (다음 단계 UI용) - 닉네임과 점수만 공개
--    점수: 승 3점, 무 1점, 패 0점 / 주간 = 이번 주 월요일 00:00 (KST) 부터
create or replace view public.rankings_weekly
with (security_invoker = false) as
select
  row_number() over (order by sum(case m.result when 'win' then 3 when 'draw' then 1 else 0 end) desc,
                              count(*) filter (where m.result = 'win') desc,
                              min(m.created_at)) as rank,
  p.nickname,
  sum(case m.result when 'win' then 3 when 'draw' then 1 else 0 end)::int as score,
  (count(*) filter (where m.result = 'win'))::int as wins
from public.matches m
join public.profiles p on p.id = m.user_id
where m.created_at >= (date_trunc('week', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul')
group by m.user_id, p.nickname;

create or replace view public.rankings_all
with (security_invoker = false) as
select
  row_number() over (order by sum(case m.result when 'win' then 3 when 'draw' then 1 else 0 end) desc,
                              count(*) filter (where m.result = 'win') desc,
                              min(m.created_at)) as rank,
  p.nickname,
  sum(case m.result when 'win' then 3 when 'draw' then 1 else 0 end)::int as score,
  (count(*) filter (where m.result = 'win'))::int as wins
from public.matches m
join public.profiles p on p.id = m.user_id
group by m.user_id, p.nickname;

revoke all on public.rankings_weekly, public.rankings_all from anon, authenticated;
grant select on public.rankings_weekly, public.rankings_all to anon, authenticated;

-- =====================================================================
-- [카드 갤러리] (gallery) - 이 블록만 따로 실행해도 됨. 여러 번 실행해도 안전.
-- =====================================================================
create table if not exists public.gallery (
  user_id    uuid not null references auth.users(id) on delete cascade default auth.uid(),
  card_id    text not null check (char_length(card_id) between 1 and 40),
  count      int  not null default 0 check (count >= 0),
  mvp_count  int  not null default 0 check (mvp_count >= 0),
  first_at   timestamptz not null default now(),
  last_at    timestamptz not null default now(),
  primary key (user_id, card_id)
);

alter table public.gallery enable row level security;
drop policy if exists "gallery_own_select" on public.gallery;
create policy "gallery_own_select" on public.gallery for select using (auth.uid() = user_id);
-- 쓰기는 아래 RPC(gallery_register)로만. 직접 insert/update/delete 정책 없음.
revoke insert, update, delete on public.gallery from anon, authenticated;
grant select on public.gallery to authenticated;

-- 판 종료 시 카드 등록: 카드별 count +1, MVP는 mvp_count +1. 새로 수집된 카드 여부 반환.
create or replace function public.gallery_register(p_cards text[], p_mvp text default null)
returns table (card_id text, count int, mvp_count int, is_new boolean)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare uid uuid := auth.uid(); ids text[];
begin
  if uid is null then raise exception 'not logged in'; end if;
  select array_agg(distinct x) into ids
    from unnest(coalesce(p_cards, '{}') || case when p_mvp is null then '{}'::text[] else array[p_mvp] end) x
    where x is not null and char_length(x) between 1 and 40;
  if ids is null then return; end if;
  if array_length(ids, 1) > 12 then raise exception 'too many cards'; end if;
  -- 도배 방지: 15초 안에 연속 등록 불가
  if exists (select 1 from public.gallery g where g.user_id = uid and g.last_at > now() - interval '15 seconds') then
    raise exception 'too fast';
  end if;
  return query
  insert into public.gallery as g (user_id, card_id, count, mvp_count, first_at, last_at)
  select uid, x, 1, (x = p_mvp)::int, now(), now() from unnest(ids) x
  on conflict (user_id, card_id) do update
    set count = g.count + 1, mvp_count = g.mvp_count + excluded.mvp_count, last_at = now()
  returning g.card_id, g.count, g.mvp_count, (g.count = 1);
end $$;

revoke all on function public.gallery_register(text[], text) from public, anon;
grant execute on function public.gallery_register(text[], text) to authenticated;
