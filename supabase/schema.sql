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

-- 6) 랭킹 - 닉네임/점수/승무패만 공개, is_me = 로그인한 본인 행 여부 (user_id 비공개)
--    (컬럼은 끝에만 추가 → create or replace 로 재실행 가능)
--    점수: 승 3점, 무 1점, 패 0점 / 주간 = 이번 주 월요일 00:00 (KST) 부터
create or replace view public.rankings_weekly
with (security_invoker = false) as
select
  row_number() over (order by sum(case m.result when 'win' then 3 when 'draw' then 1 else 0 end) desc,
                              count(*) filter (where m.result = 'win') desc,
                              min(m.created_at)) as rank,
  p.nickname,
  sum(case m.result when 'win' then 3 when 'draw' then 1 else 0 end)::int as score,
  (count(*) filter (where m.result = 'win'))::int as wins,
  (count(*) filter (where m.result = 'draw'))::int as draws,
  (count(*) filter (where m.result not in ('win','draw')))::int as losses,
  (m.user_id = auth.uid()) as is_me
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
  (count(*) filter (where m.result = 'win'))::int as wins,
  (count(*) filter (where m.result = 'draw'))::int as draws,
  (count(*) filter (where m.result not in ('win','draw')))::int as losses,
  (m.user_id = auth.uid()) as is_me
from public.matches m
join public.profiles p on p.id = m.user_id
group by m.user_id, p.nickname;

revoke all on public.rankings_weekly, public.rankings_all from anon, authenticated;
grant select on public.rankings_weekly, public.rankings_all to anon, authenticated;
