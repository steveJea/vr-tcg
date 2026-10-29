-- ⚠⚠ 다시 돌리지 마세요, 최신 아님 ⚠⚠ 예전 통합본이라 이후 파일들이 고친 함수·권한을 예전 것으로 되돌려요. 실행 순서·최신 파일: supabase/README.md
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
  select uid, x, 1, coalesce((x = p_mvp)::int, 0), now(), now() from unnest(ids) x
  on conflict (user_id, card_id) do update
    set count = g.count + 1, mvp_count = g.mvp_count + excluded.mvp_count, last_at = now()
  returning g.card_id, g.count, g.mvp_count, (g.xmax = 0);   -- 새로 insert 된 행만 NEW (gallery_register_new.sql)
end $$;

revoke all on function public.gallery_register(text[], text) from public, anon;
grant execute on function public.gallery_register(text[], text) to authenticated;

-- ===== 스토리 모드 (supabase/story.sql 과 동일) =====
create table if not exists public.story_progress (
  user_id     uuid primary key references auth.users(id) on delete cascade default auth.uid(),
  data        jsonb not null default '{}'::jsonb check (pg_column_size(data) < 200000),
  updated_at  timestamptz not null default now()
);
alter table public.story_progress enable row level security;
drop policy if exists "story_select_own" on public.story_progress;
create policy "story_select_own" on public.story_progress for select using (user_id = auth.uid());
drop policy if exists "story_insert_own" on public.story_progress;
create policy "story_insert_own" on public.story_progress for insert with check (user_id = auth.uid());
drop policy if exists "story_update_own" on public.story_progress;
create policy "story_update_own" on public.story_progress for update using (user_id = auth.uid()) with check (user_id = auth.uid());
grant select, insert, update on public.story_progress to authenticated;

-- ===== 일일 카드 뽑기 (supabase/gacha.sql 과 동일) =====

-- 1) 뽑기 카드 풀 (data/cards.csv 기준, MR 제외). 카드가 추가되면 이 부분만 다시 실행
create table if not exists public.story_card_pool (
  id     text primary key,
  grade  text not null check (grade in ('NORMAL','RARE','HIGH RARE','SUPER RARE','ULTRA RARE'))
);
alter table public.story_card_pool enable row level security;
drop policy if exists "pool_read" on public.story_card_pool;
create policy "pool_read" on public.story_card_pool for select using (true);
insert into public.story_card_pool (id, grade) values
  ('10118','SUPER RARE'),
  ('10019','RARE'),
  ('10018','RARE'),
  ('10299','HIGH RARE'),
  ('10074','NORMAL'),
  ('10080','NORMAL'),
  ('10445','NORMAL'),
  ('10375','NORMAL'),
  ('10051','ULTRA RARE'),
  ('10404','NORMAL'),
  ('10049','NORMAL'),
  ('10048','NORMAL'),
  ('10189','SUPER RARE'),
  ('10071','NORMAL'),
  ('10086','NORMAL'),
  ('10169','NORMAL'),
  ('10137','HIGH RARE'),
  ('10138','HIGH RARE'),
  ('10020','RARE'),
  ('10463','HIGH RARE'),
  ('10228','RARE'),
  ('10453','NORMAL'),
  ('10293','RARE'),
  ('10010','NORMAL'),
  ('10380','RARE'),
  ('10114','NORMAL'),
  ('10401','NORMAL'),
  ('10315','NORMAL'),
  ('10026','NORMAL'),
  ('10191','NORMAL'),
  ('10469','NORMAL'),
  ('10001','NORMAL'),
  ('10183','SUPER RARE'),
  ('10064','NORMAL'),
  ('10444','NORMAL'),
  ('10279','NORMAL'),
  ('10225','RARE'),
  ('10431','NORMAL'),
  ('10332','NORMAL'),
  ('10201','NORMAL'),
  ('10346','NORMAL'),
  ('10275','NORMAL'),
  ('10124','RARE'),
  ('10134','RARE'),
  ('10037','NORMAL'),
  ('10031','NORMAL'),
  ('10180','RARE'),
  ('10390','NORMAL'),
  ('10027','NORMAL'),
  ('10033','NORMAL'),
  ('10353','NORMAL'),
  ('10244','NORMAL'),
  ('10245','NORMAL'),
  ('10292','HIGH RARE'),
  ('10076','NORMAL'),
  ('10045','SUPER RARE'),
  ('10409','NORMAL'),
  ('10407','RARE'),
  ('10036','HIGH RARE'),
  ('10075','NORMAL'),
  ('10173','NORMAL'),
  ('10406','HIGH RARE'),
  ('10328','NORMAL'),
  ('10329','SUPER RARE'),
  ('10098','RARE'),
  ('10187','RARE'),
  ('10319','RARE'),
  ('10081','HIGH RARE'),
  ('10252','NORMAL'),
  ('10298','HIGH RARE'),
  ('10125','NORMAL'),
  ('10025','SUPER RARE'),
  ('10035','HIGH RARE'),
  ('10112','SUPER RARE'),
  ('10270','RARE'),
  ('10069','NORMAL'),
  ('10088','NORMAL'),
  ('10004','NORMAL'),
  ('10420','RARE'),
  ('10408','RARE'),
  ('10205','HIGH RARE'),
  ('10139','NORMAL'),
  ('10347','RARE'),
  ('10023','NORMAL'),
  ('10448','NORMAL'),
  ('10067','SUPER RARE'),
  ('10005','NORMAL'),
  ('10276','RARE'),
  ('10259','RARE'),
  ('10386','RARE'),
  ('10105','RARE'),
  ('10077','HIGH RARE'),
  ('10212','NORMAL'),
  ('10065','HIGH RARE'),
  ('10008','NORMAL'),
  ('10425','HIGH RARE'),
  ('10107','NORMAL'),
  ('10032','NORMAL'),
  ('10142','NORMAL'),
  ('10089','RARE'),
  ('10094','NORMAL'),
  ('10350','HIGH RARE'),
  ('10366','NORMAL'),
  ('10016','RARE'),
  ('10385','RARE'),
  ('10474','NORMAL'),
  ('10287','RARE'),
  ('10182','RARE'),
  ('10136','HIGH RARE'),
  ('10209','NORMAL'),
  ('10170','NORMAL'),
  ('10128','NORMAL'),
  ('10433','HIGH RARE'),
  ('10374','HIGH RARE'),
  ('10218','NORMAL'),
  ('10441','NORMAL'),
  ('10349','RARE'),
  ('10314','NORMAL'),
  ('10337','NORMAL'),
  ('10038','NORMAL'),
  ('10365','NORMAL'),
  ('10278','RARE'),
  ('10251','NORMAL'),
  ('10109','SUPER RARE'),
  ('10017','HIGH RARE'),
  ('10015','HIGH RARE'),
  ('10028','NORMAL'),
  ('10181','SUPER RARE'),
  ('10333','SUPER RARE'),
  ('10054','ULTRA RARE'),
  ('10046','RARE'),
  ('10066','NORMAL'),
  ('10195','RARE'),
  ('10283','NORMAL'),
  ('10284','RARE'),
  ('10321','SUPER RARE'),
  ('10320','NORMAL'),
  ('10371','HIGH RARE'),
  ('10345','RARE'),
  ('10021','RARE'),
  ('10424','RARE'),
  ('10398','RARE'),
  ('10318','NORMAL'),
  ('10458','RARE'),
  ('10464','RARE'),
  ('10233','NORMAL'),
  ('10034','NORMAL'),
  ('10171','NORMAL'),
  ('10119','NORMAL'),
  ('10226','RARE'),
  ('10307','RARE'),
  ('10402','NORMAL'),
  ('10009','NORMAL'),
  ('10055','NORMAL'),
  ('10013','SUPER RARE'),
  ('10313','NORMAL'),
  ('10106','NORMAL'),
  ('10316','NORMAL'),
  ('10416','NORMAL'),
  ('10057','NORMAL'),
  ('10220','NORMAL'),
  ('10340','NORMAL'),
  ('10309','HIGH RARE'),
  ('10070','SUPER RARE'),
  ('10113','NORMAL'),
  ('10364','NORMAL'),
  ('10410','NORMAL'),
  ('10419','HIGH RARE'),
  ('10053','ULTRA RARE'),
  ('10176','ULTRA RARE'),
  ('10200','SUPER RARE'),
  ('10234','RARE'),
  ('10123','HIGH RARE'),
  ('10304','ULTRA RARE'),
  ('10435','ULTRA RARE'),
  ('10434','NORMAL'),
  ('10430','NORMAL'),
  ('10379','NORMAL'),
  ('10325','ULTRA RARE'),
  ('10260','NORMAL'),
  ('10300','RARE'),
  ('10462','RARE'),
  ('10072','HIGH RARE'),
  ('10256','RARE'),
  ('10115','RARE'),
  ('10348','NORMAL'),
  ('10339','NORMAL'),
  ('10394','HIGH RARE'),
  ('10047','HIGH RARE'),
  ('10188','HIGH RARE'),
  ('10132','RARE'),
  ('10087','HIGH RARE'),
  ('10202','RARE'),
  ('10184','NORMAL'),
  ('10103','RARE'),
  ('10265','RARE'),
  ('10266','RARE'),
  ('10465','NORMAL'),
  ('10466','RARE'),
  ('10002','NORMAL'),
  ('10289','NORMAL'),
  ('10083','NORMAL'),
  ('10079','NORMAL'),
  ('10338','HIGH RARE'),
  ('10336','HIGH RARE'),
  ('10418','SUPER RARE'),
  ('10323','ULTRA RARE'),
  ('10403','NORMAL'),
  ('10185','NORMAL'),
  ('10308','HIGH RARE'),
  ('10413','HIGH RARE'),
  ('10415','SUPER RARE'),
  ('10414','HIGH RARE'),
  ('10186','SUPER RARE'),
  ('10295','NORMAL'),
  ('10297','RARE'),
  ('10317','SUPER RARE'),
  ('10108','SUPER RARE'),
  ('10417','RARE'),
  ('10172','NORMAL'),
  ('10262','NORMAL'),
  ('10261','RARE'),
  ('10290','RARE'),
  ('10384','RARE'),
  ('10383','SUPER RARE'),
  ('10110','HIGH RARE'),
  ('10442','HIGH RARE'),
  ('10129','RARE'),
  ('10014','NORMAL'),
  ('10235','NORMAL'),
  ('10111','RARE'),
  ('10357','RARE'),
  ('10360','NORMAL'),
  ('10306','RARE'),
  ('10285','RARE'),
  ('10343','HIGH RARE'),
  ('10271','NORMAL'),
  ('10003','NORMAL'),
  ('10095','RARE'),
  ('10096','HIGH RARE'),
  ('10342','NORMAL'),
  ('10327','NORMAL'),
  ('10286','NORMAL'),
  ('10273','NORMAL'),
  ('10253','NORMAL'),
  ('10061','SUPER RARE'),
  ('10460','NORMAL'),
  ('10459','NORMAL'),
  ('10461','RARE'),
  ('10296','RARE'),
  ('10246','RARE'),
  ('10204','RARE'),
  ('10447','RARE'),
  ('10429','RARE'),
  ('10211','NORMAL'),
  ('10193','NORMAL'),
  ('10120','NORMAL'),
  ('10101','NORMAL'),
  ('10099','NORMAL'),
  ('10241','RARE'),
  ('10044','RARE'),
  ('10043','HIGH RARE'),
  ('10376','NORMAL'),
  ('10377','NORMAL'),
  ('10322','ULTRA RARE'),
  ('10239','HIGH RARE'),
  ('10039','NORMAL'),
  ('10310','NORMAL'),
  ('10247','NORMAL'),
  ('10248','NORMAL'),
  ('10221','NORMAL'),
  ('10011','NORMAL'),
  ('10140','NORMAL'),
  ('10388','NORMAL'),
  ('10121','RARE'),
  ('10236','SUPER RARE'),
  ('10102','HIGH RARE'),
  ('10092','RARE'),
  ('10194','RARE'),
  ('10361','HIGH RARE'),
  ('10354','SUPER RARE'),
  ('10254','RARE'),
  ('10222','RARE'),
  ('10470','RARE'),
  ('10059','RARE'),
  ('10428','NORMAL'),
  ('10471','NORMAL'),
  ('10450','NORMAL'),
  ('10432','RARE'),
  ('10359','ULTRA RARE'),
  ('10362','HIGH RARE'),
  ('10454','RARE'),
  ('10363','NORMAL'),
  ('10436','NORMAL'),
  ('10412','NORMAL'),
  ('10040','NORMAL'),
  ('10042','RARE'),
  ('10237','RARE'),
  ('10207','HIGH RARE'),
  ('10208','HIGH RARE'),
  ('10303','NORMAL'),
  ('10468','NORMAL'),
  ('10467','NORMAL'),
  ('10294','NORMAL'),
  ('10258','RARE'),
  ('10056','NORMAL'),
  ('10041','HIGH RARE'),
  ('10255','SUPER RARE'),
  ('10141','RARE'),
  ('10133','RARE'),
  ('10091','RARE'),
  ('10090','RARE'),
  ('10344','NORMAL'),
  ('10330','NORMAL'),
  ('10263','NORMAL'),
  ('10249','NORMAL'),
  ('10063','NORMAL'),
  ('10052','SUPER RARE'),
  ('10190','NORMAL'),
  ('10174','NORMAL'),
  ('10122','NORMAL'),
  ('10029','RARE'),
  ('10232','NORMAL'),
  ('10104','RARE'),
  ('10378','RARE'),
  ('10126','HIGH RARE'),
  ('10203','HIGH RARE'),
  ('10097','RARE'),
  ('10280','NORMAL'),
  ('10352','NORMAL'),
  ('10277','NORMAL'),
  ('10100','NORMAL'),
  ('10451','NORMAL'),
  ('10389','NORMAL'),
  ('10264','NORMAL'),
  ('10438','NORMAL'),
  ('10177','NORMAL'),
  ('10178','NORMAL'),
  ('10372','RARE'),
  ('10373','SUPER RARE'),
  ('10130','NORMAL'),
  ('10131','HIGH RARE'),
  ('10341','SUPER RARE'),
  ('10272','NORMAL'),
  ('10117','SUPER RARE'),
  ('10078','HIGH RARE'),
  ('10084','NORMAL'),
  ('10085','NORMAL'),
  ('10217','SUPER RARE'),
  ('10216','SUPER RARE'),
  ('10324','ULTRA RARE'),
  ('10006','NORMAL'),
  ('10068','SUPER RARE'),
  ('10400','HIGH RARE'),
  ('10331','ULTRA RARE'),
  ('10250','NORMAL'),
  ('10022','NORMAL'),
  ('10437','RARE'),
  ('10426','RARE'),
  ('10381','NORMAL'),
  ('10179','NORMAL'),
  ('10215','NORMAL'),
  ('10214','HIGH RARE'),
  ('10223','NORMAL'),
  ('10269','SUPER RARE'),
  ('10268','HIGH RARE'),
  ('10473','HIGH RARE'),
  ('10135','RARE'),
  ('10206','NORMAL'),
  ('10240','HIGH RARE'),
  ('10238','NORMAL'),
  ('10230','RARE'),
  ('10227','RARE'),
  ('10387','NORMAL'),
  ('10281','SUPER RARE'),
  ('10472','NORMAL'),
  ('10455','RARE'),
  ('10423','NORMAL'),
  ('10456','NORMAL'),
  ('10457','HIGH RARE'),
  ('10224','RARE'),
  ('10382','NORMAL'),
  ('10393','HIGH RARE'),
  ('10030','NORMAL'),
  ('10391','RARE'),
  ('10392','SUPER RARE'),
  ('10397','RARE'),
  ('10242','RARE'),
  ('10356','NORMAL'),
  ('10274','NORMAL'),
  ('10192','NORMAL'),
  ('10093','NORMAL'),
  ('10312','ULTRA RARE'),
  ('10243','NORMAL'),
  ('10231','HIGH RARE'),
  ('10399','SUPER RARE'),
  ('10050','NORMAL'),
  ('10073','HIGH RARE'),
  ('10229','HIGH RARE'),
  ('10012','NORMAL'),
  ('10219','NORMAL'),
  ('10305','NORMAL'),
  ('10443','NORMAL'),
  ('10024','SUPER RARE'),
  ('10446','NORMAL'),
  ('10427','NORMAL'),
  ('10411','NORMAL'),
  ('10058','ULTRA RARE'),
  ('10395','NORMAL'),
  ('10213','SUPER RARE'),
  ('10175','RARE'),
  ('10007','RARE'),
  ('10257','HIGH RARE'),
  ('10291','ULTRA RARE'),
  ('10288','HIGH RARE'),
  ('10282','NORMAL'),
  ('10405','RARE'),
  ('10452','HIGH RARE'),
  ('10370','RARE'),
  ('10368','RARE'),
  ('10369','SUPER RARE'),
  ('10358','ULTRA RARE'),
  ('10351','NORMAL'),
  ('10449','NORMAL'),
  ('10422','NORMAL'),
  ('10421','NORMAL'),
  ('10396','NORMAL')
on conflict (id) do update set grade = excluded.grade;

-- 2) 유저별 마지막 뽑기 날짜(KST) + 기록
create table if not exists public.story_gacha (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  last_draw  date not null,
  updated_at timestamptz not null default now()
);
alter table public.story_gacha enable row level security;
drop policy if exists "gacha_select_own" on public.story_gacha;
create policy "gacha_select_own" on public.story_gacha for select using (user_id = auth.uid());
-- 쓰기 정책 없음: 아래 SECURITY DEFINER 함수로만 기록

create table if not exists public.story_gacha_log (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references auth.users(id) on delete cascade,
  card_id    text not null,
  grade      text not null,
  created_at timestamptz not null default now()
);
alter table public.story_gacha_log enable row level security;
drop policy if exists "gacha_log_own" on public.story_gacha_log;
create policy "gacha_log_own" on public.story_gacha_log for select using (user_id = auth.uid());

-- 3) 뽑기 함수: 결과 jsonb { ok, card_id, grade, count, day } / 이미 뽑았으면 { ok:false, reason:'already', day }
create or replace function public.story_daily_draw()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid   uuid := auth.uid();
  today date := (now() at time zone 'Asia/Seoul')::date;
  last  date;
  r     double precision;
  g     text;
  cid   text;
  d     jsonb;
  owned jsonb;
  idx   int;
  cnt   int := 1;
begin
  if uid is null then raise exception 'login required'; end if;
  -- 동시 요청 방지: 유저 행 잠금
  insert into story_gacha (user_id, last_draw) values (uid, today - 1) on conflict (user_id) do nothing;
  select last_draw into last from story_gacha where user_id = uid for update;
  if last >= today then return jsonb_build_object('ok', false, 'reason', 'already', 'day', today); end if;

  r := random();
  g := case when r < 0.70 then 'NORMAL' when r < 0.90 then 'RARE' when r < 0.965 then 'HIGH RARE' when r < 0.995 then 'SUPER RARE' else 'ULTRA RARE' end;
  select id into cid from story_card_pool where grade = g order by random() limit 1;
  if cid is null then raise exception 'empty pool for %', g; end if;

  -- 스토리 저장(story_progress.data.owned)에 추가: 있으면 count+1
  insert into story_progress (user_id, data) values (uid, '{}'::jsonb) on conflict (user_id) do nothing;
  select data into d from story_progress where user_id = uid for update;
  owned := coalesce(d->'owned', '[]'::jsonb);
  select i - 1 into idx from jsonb_array_elements(owned) with ordinality as t(e, i) where t.e->>'id' = cid limit 1;
  if idx is null then
    owned := owned || jsonb_build_array(jsonb_build_object('id', cid, 'boost', '{}'::jsonb, 'count', 1));
  else
    cnt := coalesce((owned->idx->>'count')::int, 1) + 1;
    owned := jsonb_set(owned, array[idx::text, 'count'], to_jsonb(cnt));
  end if;
  d := jsonb_set(jsonb_set(jsonb_set(d, '{owned}', owned), '{gachaLast}', to_jsonb(today::text)), '{updatedAt}', to_jsonb((extract(epoch from now()) * 1000)::bigint));
  update story_progress set data = d, updated_at = now() where user_id = uid;
  update story_gacha set last_draw = today, updated_at = now() where user_id = uid;
  insert into story_gacha_log (user_id, card_id, grade) values (uid, cid, g);
  return jsonb_build_object('ok', true, 'card_id', cid, 'grade', g, 'count', cnt, 'day', today);
end $$;
revoke all on function public.story_daily_draw() from public, anon;
grant execute on function public.story_daily_draw() to authenticated;

-- ===== 스토리 진행 서버 확정 (supabase/story_server.sql 과 동일) =====

-- 1) 직접 쓰기 차단 (읽기 정책 story_select_own 은 유지)
drop policy if exists "story_insert_own" on public.story_progress;
drop policy if exists "story_update_own" on public.story_progress;
revoke insert, update, delete on public.story_progress from anon, authenticated;
grant select on public.story_progress to authenticated;

-- 2) 페이즈 설정: 보상은 서버가 결정 (챕터 2부터는 reward_grade 없음 = 스탯 포인트만)
create table if not exists public.story_phase_config (
  chapter      int  not null,
  phase        int  not null,
  type         text not null check (type in ('normal','boss')),
  points       int  not null check (points between 0 and 100),
  reward_grade text check (reward_grade in ('NORMAL','RARE','HIGH RARE','SUPER RARE','ULTRA RARE')),
  primary key (chapter, phase)
);
alter table public.story_phase_config enable row level security;
drop policy if exists "phase_cfg_read" on public.story_phase_config;
create policy "phase_cfg_read" on public.story_phase_config for select using (true);
insert into public.story_phase_config (chapter, phase, type, points, reward_grade) values
  (1,1,'normal',3,'NORMAL'), (1,2,'normal',3,'NORMAL'), (1,3,'normal',3,'NORMAL'), (1,4,'normal',3,'NORMAL'), (1,5,'boss',5,'NORMAL')
on conflict (chapter, phase) do update set type = excluded.type, points = excluded.points, reward_grade = excluded.reward_grade;

-- 스탯 포인트 1당 상승량은 클라이언트(js/story-data.js statPerPoint)에서 적용: ATK+2 / HP+10 / DEF+2
-- 전투 최소 시간 (초): 전투 시작 기록 후 이 시간 이전의 클리어 요청은 거부
create or replace function public._story_min_battle_secs() returns int language sql immutable as $$ select 3 $$;

-- 3) 내부 도우미
-- 첫 클리어로 얻을 수 있는 포인트 총량
create or replace function public._story_earned(d jsonb) returns int language sql stable set search_path = public as $$
  select coalesce(sum(c.points), 0)::int
  from jsonb_each(coalesce(d->'cleared', '{}'::jsonb)) ch(k, v)
  cross join lateral jsonb_array_elements_text(case when jsonb_typeof(ch.v) = 'array' then ch.v else '[]'::jsonb end) p(no)
  join story_phase_config c on c.chapter::text = ch.k and c.phase::text = p.no
$$;
-- 분배한 포인트 합계
create or replace function public._story_used(d jsonb) returns int language sql immutable as $$
  select coalesce(sum(greatest(0, coalesce((o->'boost'->>'ATK')::int,0)) + greatest(0, coalesce((o->'boost'->>'HP')::int,0)) + greatest(0, coalesce((o->'boost'->>'DEF')::int,0))), 0)::int
  from jsonb_array_elements(case when jsonb_typeof(d->'owned') = 'array' then d->'owned' else '[]'::jsonb end) o
$$;
-- 행 잠금 후 data 반환 (없으면 생성)
create or replace function public._story_lock(uid uuid) returns jsonb language plpgsql set search_path = public as $$
declare d jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  insert into story_progress (user_id, data) values (uid, '{}'::jsonb) on conflict (user_id) do nothing;
  select data into d from story_progress where user_id = uid for update;
  return coalesce(d, '{}'::jsonb);
end $$;
create or replace function public._story_save(uid uuid, d jsonb) returns jsonb language plpgsql set search_path = public as $$
begin
  d := jsonb_set(d, '{updatedAt}', to_jsonb((extract(epoch from clock_timestamp()) * 1000)::bigint));
  update story_progress set data = d, updated_at = now() where user_id = uid;
  return d;
end $$;
revoke all on function public._story_earned(jsonb), public._story_used(jsonb), public._story_lock(uuid), public._story_save(uuid, jsonb) from public, anon, authenticated;

-- 4) 공개 RPC (모두 갱신된 data 를 반환)
-- 오프닝·시작 스토리 본 표시
create or replace function public.story_mark_seen(p_key text) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb;
begin
  if p_key not in ('openingSeen', 'startSeen') then raise exception 'invalid key'; end if;
  d := _story_lock(uid);
  return _story_save(uid, jsonb_set(d, array[p_key], 'true'::jsonb));
end $$;

-- 시작 캐릭터 선택 (1회). 기존 보유 카드(뽑기 등)는 유지하고 시작 카드를 맨 앞(리더)으로
create or replace function public.story_choose_starter(p_id text) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb; owned jsonb;
begin
  if p_id not in ('10111', '10265', '10224') then raise exception 'invalid starter'; end if;
  d := _story_lock(uid);
  if coalesce(d->>'starter', '') <> '' then raise exception 'starter already chosen'; end if;
  select coalesce(jsonb_agg(o), '[]'::jsonb) into owned from jsonb_array_elements(case when jsonb_typeof(d->'owned') = 'array' then d->'owned' else '[]'::jsonb end) o where o->>'id' <> p_id;
  owned := jsonb_build_array(jsonb_build_object('id', p_id, 'boost', '{}'::jsonb, 'count', 1)) || owned;
  d := jsonb_set(jsonb_set(d, '{starter}', to_jsonb(p_id)), '{owned}', owned);
  if d->'points' is null then d := jsonb_set(d, '{points}', '0'::jsonb); end if;
  if d->'cleared' is null then d := jsonb_set(d, '{cleared}', '{}'::jsonb); end if;
  return _story_save(uid, d);
end $$;

-- 전투 시작 기록 (열린 페이즈만)
create or replace function public.story_start_phase(p_chapter int, p_phase int) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb;
begin
  if not exists (select 1 from story_phase_config where chapter = p_chapter and phase = p_phase) then raise exception 'invalid phase'; end if;
  d := _story_lock(uid);
  if coalesce(d->>'starter', '') = '' then raise exception 'choose starter first'; end if;
  -- 열림 조건: 같은 챕터의 이전 페이즈 모두 클리어 + 이전 챕터 전체 클리어
  if exists (
    select 1 from story_phase_config c
    where (c.chapter < p_chapter or (c.chapter = p_chapter and c.phase < p_phase))
      and not (coalesce(d->'cleared'->(c.chapter::text), '[]'::jsonb) @> to_jsonb(c.phase))
  ) then raise exception 'phase locked'; end if;
  d := jsonb_set(d, '{battle}', jsonb_build_object('chapter', p_chapter, 'phase', p_phase, 'at', (extract(epoch from clock_timestamp()))::bigint));
  return _story_save(uid, d);
end $$;

-- 페이즈 클리어: 시작 기록·최소 전투 시간 확인. 첫 클리어만 보상(카드+포인트), 재클리어는 아무것도 없음
create or replace function public.story_complete_phase(p_chapter int, p_phase int) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb; cfg story_phase_config; b jsonb; cl jsonb; first boolean; rid text; owned jsonb;
begin
  select * into cfg from story_phase_config where chapter = p_chapter and phase = p_phase;
  if cfg is null then raise exception 'invalid phase'; end if;
  d := _story_lock(uid);
  b := d->'battle';
  if b is null or (b->>'chapter')::int <> p_chapter or (b->>'phase')::int <> p_phase then raise exception 'battle not started'; end if;
  if extract(epoch from clock_timestamp()) - (b->>'at')::bigint < _story_min_battle_secs() then raise exception 'too fast'; end if;
  d := d - 'battle';
  cl := coalesce(d->'cleared'->(p_chapter::text), '[]'::jsonb);
  first := not cl @> to_jsonb(p_phase);
  if first then
    if d->'cleared' is null or jsonb_typeof(d->'cleared') <> 'object' then d := jsonb_set(d, '{cleared}', '{}'::jsonb); end if;
    d := jsonb_set(d, array['cleared', p_chapter::text], cl || to_jsonb(p_phase));
    d := jsonb_set(d, '{points}', to_jsonb(coalesce((d->>'points')::int, 0) + cfg.points));
    if cfg.reward_grade is not null then
      owned := case when jsonb_typeof(d->'owned') = 'array' then d->'owned' else '[]'::jsonb end;
      select p.id into rid from story_card_pool p
        where p.grade = cfg.reward_grade and not exists (select 1 from jsonb_array_elements(owned) o where o->>'id' = p.id)
        order by random() limit 1;
      if rid is not null then d := jsonb_set(d, '{owned}', owned || jsonb_build_array(jsonb_build_object('id', rid, 'boost', '{}'::jsonb, 'count', 1))); end if;
    end if;
  end if;
  d := _story_save(uid, d);
  return jsonb_build_object('data', d, 'first', first, 'points', case when first then cfg.points else 0 end, 'reward_id', rid);
end $$;

-- 스탯 분배: p_alloc = {"카드id": {"ATK":n,"HP":n,"DEF":n}, ...} (추가할 포인트). 보유 카드만, 0 이상 정수, 보유 포인트 이내
create or replace function public.story_allocate(p_alloc jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb; owned jsonb; k text; v jsonb; s text; n int; total int := 0; idx int; pts int;
begin
  if jsonb_typeof(p_alloc) <> 'object' then raise exception 'invalid alloc'; end if;
  d := _story_lock(uid);
  owned := case when jsonb_typeof(d->'owned') = 'array' then d->'owned' else '[]'::jsonb end;
  pts := greatest(0, coalesce((d->>'points')::int, 0));
  for k, v in select * from jsonb_each(p_alloc) loop
    select i - 1 into idx from jsonb_array_elements(owned) with ordinality t(e, i) where t.e->>'id' = k limit 1;
    if idx is null then raise exception 'card not owned'; end if;
    if jsonb_typeof(v) <> 'object' then raise exception 'invalid alloc'; end if;
    for s in select jsonb_object_keys(v) loop
      if s not in ('ATK', 'HP', 'DEF') then raise exception 'invalid stat'; end if;
      if jsonb_typeof(v->s) <> 'number' then raise exception 'invalid amount'; end if;
      n := (v->>s)::int;
      if n < 0 or n::text <> (v->>s) then raise exception 'invalid amount'; end if;
      total := total + n;
      owned := jsonb_set(owned, array[idx::text, 'boost'], coalesce(owned->idx->'boost', '{}'::jsonb) || jsonb_build_object(s, coalesce((owned->idx->'boost'->>s)::int, 0) + n));
    end loop;
  end loop;
  if total > pts then raise exception 'not enough points'; end if;
  d := jsonb_set(jsonb_set(d, '{owned}', owned), '{points}', to_jsonb(pts - total));
  return _story_save(uid, d);
end $$;

revoke all on function public.story_mark_seen(text), public.story_choose_starter(text), public.story_start_phase(int, int), public.story_complete_phase(int, int), public.story_allocate(jsonb) from public, anon;
grant execute on function public.story_mark_seen(text), public.story_choose_starter(text), public.story_start_phase(int, int), public.story_complete_phase(int, int), public.story_allocate(jsonb) to authenticated;

-- 5) 기존 데이터 정리: 잘못된 클리어 기록 제거, 포인트를 (첫 클리어 총량 − 분배량) 이내로
update public.story_progress sp set data = jsonb_set(sp.data, '{cleared}', coalesce((
    select jsonb_object_agg(ch.k, (select coalesce(jsonb_agg(distinct p.no::int), '[]'::jsonb) from jsonb_array_elements_text(ch.v) p(no)
                                   where exists (select 1 from public.story_phase_config c where c.chapter::text = ch.k and c.phase::text = p.no)))
    from jsonb_each(sp.data->'cleared') ch(k, v) where jsonb_typeof(ch.v) = 'array'), '{}'::jsonb))
  where jsonb_typeof(sp.data->'cleared') = 'object';
update public.story_progress sp set data = jsonb_set(sp.data, '{points}', to_jsonb(greatest(0, least(coalesce((sp.data->>'points')::int, 0), public._story_earned(sp.data) - public._story_used(sp.data)))))
  where sp.data ? 'points' or sp.data ? 'cleared';

-- ===== 스토리 카드 레벨 + 폐기 (supabase/story_levels.sql 과 동일) =====

-- 1) 카드 풀에 이름·MR 추가 (뽑기는 gacha=true 인 카드만 · MR 제외 유지)
alter table public.story_card_pool add column if not exists name text;
alter table public.story_card_pool add column if not exists gacha boolean not null default true;
alter table public.story_card_pool drop constraint if exists story_card_pool_grade_check;
alter table public.story_card_pool add constraint story_card_pool_grade_check check (grade in ('NORMAL','RARE','HIGH RARE','SUPER RARE','ULTRA RARE','MYTHIC RARE','LEGENDARY RARE'));
insert into public.story_card_pool (id, grade, name, gacha) values
  ('10118','SUPER RARE','민홍기',true),
  ('10019','RARE','강태준',true),
  ('10018','RARE','강태안',true),
  ('10299','HIGH RARE','이민수',true),
  ('10074','NORMAL','김철민',true),
  ('10080','NORMAL','김홍민',true),
  ('10445','NORMAL','한재',true),
  ('10375','NORMAL','정형준',true),
  ('10051','ULTRA RARE','김기림',true),
  ('10404','NORMAL','최강수',true),
  ('10049','NORMAL','길정재',true),
  ('10048','NORMAL','길윤재',true),
  ('10189','SUPER RARE','선우민철',true),
  ('10060','MYTHIC RARE','김성진',false),
  ('10071','NORMAL','김준하',true),
  ('10086','NORMAL','남경택',true),
  ('10169','NORMAL','사주혁',true),
  ('10137','HIGH RARE','복광준',true),
  ('10138','HIGH RARE','복광훈',true),
  ('10020','RARE','강한길',true),
  ('10463','HIGH RARE','황보재규',true),
  ('10228','RARE','안중산',true),
  ('10453','NORMAL','허재철',true),
  ('10293','RARE','윤태영',true),
  ('10010','NORMAL','강우섭',true),
  ('10380','RARE','조승규',true),
  ('10114','NORMAL','문희찬',true),
  ('10401','NORMAL','채훈기',true),
  ('10315','NORMAL','이찬열',true),
  ('10026','NORMAL','고차연',true),
  ('10191','NORMAL','선인구',true),
  ('10469','NORMAL','황준태',true),
  ('10001','NORMAL','가윤우',true),
  ('10183','SUPER RARE','서태우',true),
  ('10064','NORMAL','김자근',true),
  ('10444','NORMAL','한석열',true),
  ('10279','NORMAL','윤동훈',true),
  ('10225','RARE','안용태',true),
  ('10431','NORMAL','표정재',true),
  ('10332','NORMAL','장동만',true),
  ('10201','NORMAL','소석준',true),
  ('10346','NORMAL','전성국',true),
  ('10275','NORMAL','유형수',true),
  ('10124','RARE','박언석',true),
  ('10134','RARE','배승규',true),
  ('10037','NORMAL','구성원',true),
  ('10031','NORMAL','곽명구',true),
  ('10180','RARE','서영석',true),
  ('10390','NORMAL','주연욱',true),
  ('10027','NORMAL','고한홍',true),
  ('10033','NORMAL','곽재준',true),
  ('10353','NORMAL','전호영',true),
  ('10244','NORMAL','염상휘',true),
  ('10245','NORMAL','염태영',true),
  ('10292','HIGH RARE','윤태민',true),
  ('10076','NORMAL','김철하',true),
  ('10045','SUPER RARE','금어진',true),
  ('10409','NORMAL','최민우',true),
  ('10407','RARE','최대운',true),
  ('10036','HIGH RARE','곽태우',true),
  ('10075','NORMAL','김철중',true),
  ('10173','NORMAL','서규인',true),
  ('10406','HIGH RARE','최국선',true),
  ('10328','NORMAL','임창수',true),
  ('10329','SUPER RARE','임창열',true),
  ('10098','RARE','두윤창',true),
  ('10187','RARE','선영운',true),
  ('10319','RARE','이후남',true),
  ('10081','HIGH RARE','김후',true),
  ('10252','NORMAL','오명준',true),
  ('10298','HIGH RARE','이명진',true),
  ('10125','NORMAL','박오류',true),
  ('10025','SUPER RARE','고정태',true),
  ('10035','HIGH RARE','곽진영',true),
  ('10112','SUPER RARE','문지철',true),
  ('10270','RARE','유진산',true),
  ('10069','NORMAL','김정한',true),
  ('10088','NORMAL','남궁무열',true),
  ('10004','NORMAL','강명준',true),
  ('10420','RARE','최한길',true),
  ('10408','RARE','최두길',true),
  ('10205','HIGH RARE','송동혁',true),
  ('10139','NORMAL','복규철',true),
  ('10347','RARE','전수양',true),
  ('10023','NORMAL','고병헌',true),
  ('10448','NORMAL','허성',true),
  ('10067','SUPER RARE','김재섭',true),
  ('10005','NORMAL','강상',true),
  ('10276','RARE','유혜운',true),
  ('10259','RARE','오한음',true),
  ('10386','RARE','조한얼',true),
  ('10105','RARE','마하랑',true),
  ('10077','HIGH RARE','김한결',true),
  ('10212','NORMAL','신성진',true),
  ('10065','HIGH RARE','김재량',true),
  ('10008','NORMAL','강승헌',true),
  ('10425','HIGH RARE','탁동탁',true),
  ('10107','NORMAL','문동혁',true),
  ('10032','NORMAL','곽민수',true),
  ('10142','NORMAL','봉우람',true),
  ('10089','RARE','남궁형남',true),
  ('10094','NORMAL','노재범',true),
  ('10350','HIGH RARE','전중혁',true),
  ('10366','NORMAL','정지석',true),
  ('10016','RARE','강철하',true),
  ('10385','RARE','조주열',true),
  ('10474','NORMAL','황혁',true),
  ('10287','RARE','윤우람',true),
  ('10182','RARE','서진성',true),
  ('10136','HIGH RARE','백천주',true),
  ('10209','NORMAL','송철순',true),
  ('10170','NORMAL','사진태',true),
  ('10128','NORMAL','박태욱',true),
  ('10433','HIGH RARE','풍건',true),
  ('10374','HIGH RARE','정한서',true),
  ('10218','NORMAL','신재',true),
  ('10441','NORMAL','하혁',true),
  ('10349','RARE','전주일',true),
  ('10314','NORMAL','이진우',true),
  ('10337','NORMAL','장승헌',true),
  ('10038','NORMAL','국태원',true),
  ('10365','NORMAL','정종일',true),
  ('10278','RARE','윤남규',true),
  ('10251','NORMAL','예현승',true),
  ('10109','SUPER RARE','문재',true),
  ('10017','HIGH RARE','강철훈',true),
  ('10015','HIGH RARE','강철진',true),
  ('10028','NORMAL','공윤성',true),
  ('10181','SUPER RARE','서오성',true),
  ('10333','SUPER RARE','장무영',true),
  ('10054','ULTRA RARE','김동욱',true),
  ('10046','RARE','금유진',true),
  ('10066','NORMAL','김재민',true),
  ('10195','RARE','성재수',true),
  ('10283','NORMAL','윤석구',true),
  ('10284','RARE','윤석팔',true),
  ('10321','SUPER RARE','인창수',true),
  ('10320','NORMAL','인창민',true),
  ('10371','HIGH RARE','정태진',true),
  ('10345','RARE','전민진',true),
  ('10021','RARE','경원석',true),
  ('10424','RARE','추정욱',true),
  ('10398','RARE','진수열',true),
  ('10318','NORMAL','이호준',true),
  ('10458','RARE','황기훈',true),
  ('10464','RARE','황보훈',true),
  ('10233','NORMAL','안현',true),
  ('10034','NORMAL','곽제형',true),
  ('10171','NORMAL','서경석',true),
  ('10119','NORMAL','박미르',true),
  ('10226','RARE','안재수',true),
  ('10307','RARE','이영하',true),
  ('10402','NORMAL','천재황',true),
  ('10009','NORMAL','강신',true),
  ('10055','NORMAL','김들',true),
  ('10013','SUPER RARE','강준철',true),
  ('10313','NORMAL','이진규',true),
  ('10106','NORMAL','마형은',true),
  ('10316','NORMAL','이택길',true),
  ('10416','NORMAL','최재홍',true),
  ('10057','NORMAL','김민규',true),
  ('10220','NORMAL','신주호',true),
  ('10340','NORMAL','장제훈',true),
  ('10309','HIGH RARE','이재덕',true),
  ('10070','SUPER RARE','김준기',true),
  ('10113','NORMAL','문철재',true),
  ('10364','NORMAL','정재헌',true),
  ('10410','NORMAL','최봉근',true),
  ('10419','HIGH RARE','최진규',true),
  ('10053','ULTRA RARE','김대욱',true),
  ('10176','ULTRA RARE','서성민',true),
  ('10200','SUPER RARE','소민섭',true),
  ('10234','RARE','안호선',true),
  ('10123','HIGH RARE','박성관',true),
  ('10304','ULTRA RARE','이성호',true),
  ('10435','ULTRA RARE','하승진',true),
  ('10434','NORMAL','풍힘찬',true),
  ('10430','NORMAL','표오성',true),
  ('10379','NORMAL','제갈버들',true),
  ('10325','ULTRA RARE','임유리',true),
  ('10260','NORMAL','오희진',true),
  ('10300','RARE','이민채',true),
  ('10462','RARE','황보예',true),
  ('10072','HIGH RARE','김지수',true),
  ('10256','RARE','오유나',true),
  ('10115','RARE','민유연',true),
  ('10348','NORMAL','전잔디',true),
  ('10339','NORMAL','장은채',true),
  ('10394','HIGH RARE','지세련',true),
  ('10047','HIGH RARE','길선재',true),
  ('10188','HIGH RARE','선우민아',true),
  ('10132','RARE','배나빛',true),
  ('10087','HIGH RARE','남고은',true),
  ('10202','RARE','손란',true),
  ('10184','NORMAL','서하윤',true),
  ('10103','RARE','류하예',true),
  ('10265','RARE','용지혜',true),
  ('10266','RARE','용지효',true),
  ('10465','NORMAL','황예영',true),
  ('10466','RARE','황예은',true),
  ('10002','NORMAL','강나빛',true),
  ('10289','NORMAL','윤정하',true),
  ('10083','NORMAL','김희건',true),
  ('10079','NORMAL','김현진',true),
  ('10338','HIGH RARE','장아유',true),
  ('10336','HIGH RARE','장세유',true),
  ('10418','SUPER RARE','최지연',true),
  ('10323','ULTRA RARE','임나리',true),
  ('10403','NORMAL','천혜원',true),
  ('10185','NORMAL','선나영',true),
  ('10308','HIGH RARE','이윤이',true),
  ('10413','HIGH RARE','최윤아',true),
  ('10415','SUPER RARE','최윤희',true),
  ('10414','HIGH RARE','최윤정',true),
  ('10186','SUPER RARE','선미영',true),
  ('10295','NORMAL','윤희지',true),
  ('10297','RARE','이로하',true),
  ('10317','SUPER RARE','이혜경',true),
  ('10108','SUPER RARE','문유선',true),
  ('10417','RARE','최정인',true),
  ('10172','NORMAL','서규안',true),
  ('10262','NORMAL','온리윤',true),
  ('10261','RARE','온리연',true),
  ('10290','RARE','윤진아',true),
  ('10384','RARE','조윤하',true),
  ('10383','SUPER RARE','조윤이',true),
  ('10110','HIGH RARE','문지아',true),
  ('10442','HIGH RARE','한겨울',true),
  ('10129','RARE','박혜안',true),
  ('10014','NORMAL','강지민',true),
  ('10235','NORMAL','안희숙',true),
  ('10111','RARE','문지예',true),
  ('10357','RARE','정서영',true),
  ('10360','NORMAL','정아영',true),
  ('10306','RARE','이영아',true),
  ('10285','RARE','윤세정',true),
  ('10343','HIGH RARE','전미성',true),
  ('10271','NORMAL','유진아',true),
  ('10003','NORMAL','강리안',true),
  ('10095','RARE','노정아',true),
  ('10096','HIGH RARE','노정은',true),
  ('10342','NORMAL','장혜린',true),
  ('10327','NORMAL','임조은',true),
  ('10286','NORMAL','윤수영',true),
  ('10273','NORMAL','유태이',true),
  ('10253','NORMAL','오빛나',true),
  ('10061','SUPER RARE','김소영',true),
  ('10460','NORMAL','황다영',true),
  ('10459','NORMAL','황다미',true),
  ('10461','RARE','황다윤',true),
  ('10296','RARE','이누리',true),
  ('10246','RARE','예민지',true),
  ('10204','RARE','송다혜',true),
  ('10447','RARE','허동아',true),
  ('10429','RARE','탁희원',true),
  ('10211','NORMAL','신단비',true),
  ('10193','NORMAL','설지원',true),
  ('10120','NORMAL','박보라',true),
  ('10101','NORMAL','류하늘',true),
  ('10099','NORMAL','류장미',true),
  ('10241','RARE','양주영',true),
  ('10044','RARE','권지우',true),
  ('10043','HIGH RARE','권지아',true),
  ('10376','NORMAL','정혜원',true),
  ('10377','NORMAL','정혜진',true),
  ('10322','ULTRA RARE','임규리',true),
  ('10239','HIGH RARE','양유영',true),
  ('10039','NORMAL','권두리',true),
  ('10310','NORMAL','이제원',true),
  ('10247','NORMAL','예유나',true),
  ('10248','NORMAL','예유진',true),
  ('10221','NORMAL','신지아',true),
  ('10011','NORMAL','강유영',true),
  ('10140','NORMAL','복선아',true),
  ('10388','NORMAL','주서형',true),
  ('10121','RARE','박샘',true),
  ('10236','SUPER RARE','양겨울',true),
  ('10102','HIGH RARE','류하늬',true),
  ('10092','RARE','남소연',true),
  ('10194','RARE','설하늘',true),
  ('10361','HIGH RARE','정아윤',true),
  ('10354','SUPER RARE','정다윤',true),
  ('10254','RARE','오샘나',true),
  ('10222','RARE','심버들',true),
  ('10470','RARE','황지수',true),
  ('10059','RARE','김샛별',true),
  ('10428','NORMAL','탁세은',true),
  ('10471','NORMAL','황지은',true),
  ('10450','NORMAL','허유란',true),
  ('10432','RARE','표지아',true),
  ('10359','ULTRA RARE','정아람',true),
  ('10362','HIGH RARE','정연아',true),
  ('10454','RARE','허진서',true),
  ('10363','NORMAL','정영아',true),
  ('10436','NORMAL','하윤하',true),
  ('10412','NORMAL','최유안',true),
  ('10040','NORMAL','권예강',true),
  ('10042','RARE','권예진',true),
  ('10237','RARE','양서진',true),
  ('10207','HIGH RARE','송지아',true),
  ('10208','HIGH RARE','송지은',true),
  ('10303','NORMAL','이믿음',true),
  ('10468','NORMAL','황은채',true),
  ('10467','NORMAL','황은아',true),
  ('10294','NORMAL','윤태희',true),
  ('10258','RARE','오한설',true),
  ('10056','NORMAL','김미윤',true),
  ('10041','HIGH RARE','권예리',true),
  ('10255','SUPER RARE','오설화',true),
  ('10141','RARE','복정아',true),
  ('10133','RARE','배수연',true),
  ('10091','RARE','남다윤',true),
  ('10090','RARE','남다연',true),
  ('10344','NORMAL','전민강',true),
  ('10330','NORMAL','임한빈',true),
  ('10263','NORMAL','온유진',true),
  ('10249','NORMAL','예은아',true),
  ('10063','NORMAL','김예빈',true),
  ('10052','SUPER RARE','김나현',true),
  ('10190','NORMAL','선유린',true),
  ('10174','NORMAL','서미나',true),
  ('10122','NORMAL','박설이',true),
  ('10029','RARE','공주연',true),
  ('10232','NORMAL','안태영',true),
  ('10104','RARE','류햇빛',true),
  ('10378','RARE','제갈민영',true),
  ('10126','HIGH RARE','박인아',true),
  ('10062','MYTHIC RARE','김신현',false),
  ('10203','HIGH RARE','손혜연',true),
  ('10097','RARE','동지선',true),
  ('10280','NORMAL','윤미리내',true),
  ('10352','NORMAL','전하나',true),
  ('10277','NORMAL','유혜윰',true),
  ('10100','NORMAL','류태연',true),
  ('10451','NORMAL','허유리',true),
  ('10389','NORMAL','주슬기',true),
  ('10264','NORMAL','왕유영',true),
  ('10438','NORMAL','하지연',true),
  ('10177','NORMAL','서아란',true),
  ('10178','NORMAL','서아리',true),
  ('10372','RARE','정하나',true),
  ('10373','SUPER RARE','정하루',true),
  ('10130','NORMAL','반지아',true),
  ('10131','HIGH RARE','반지윤',true),
  ('10341','SUPER RARE','장초롱',true),
  ('10272','NORMAL','유진이',true),
  ('10117','SUPER RARE','민지은',true),
  ('10078','HIGH RARE','김한별',true),
  ('10084','NORMAL','나윤아',true),
  ('10085','NORMAL','나윤영',true),
  ('10217','SUPER RARE','신예은',true),
  ('10216','SUPER RARE','신아은',true),
  ('10324','ULTRA RARE','임예리',true),
  ('10006','NORMAL','강서언',true),
  ('10068','SUPER RARE','김재신',true),
  ('10400','HIGH RARE','채예린',true),
  ('10331','ULTRA RARE','임혜리',true),
  ('10250','NORMAL','예햇빛',true),
  ('10022','NORMAL','고명희',true),
  ('10437','RARE','하장미',true),
  ('10426','RARE','탁동혜',true),
  ('10381','NORMAL','조아린',true),
  ('10179','NORMAL','서애정',true),
  ('10215','NORMAL','신아윤',true),
  ('10214','HIGH RARE','신아린',true),
  ('10223','NORMAL','안다미',true),
  ('10269','SUPER RARE','유아리',true),
  ('10268','HIGH RARE','유나리',true),
  ('10473','HIGH RARE','황한결',true),
  ('10135','RARE','백버들',true),
  ('10206','NORMAL','송예빈',true),
  ('10240','HIGH RARE','양제림',true),
  ('10238','NORMAL','양소영',true),
  ('10230','RARE','안지연',true),
  ('10227','RARE','안주연',true),
  ('10387','NORMAL','주서영',true),
  ('10281','SUPER RARE','윤믿음',true),
  ('10472','NORMAL','황진',true),
  ('10455','RARE','홍가영',true),
  ('10423','NORMAL','추나리',true),
  ('10456','NORMAL','홍나영',true),
  ('10457','HIGH RARE','홍다영',true),
  ('10224','RARE','안리',true),
  ('10382','NORMAL','조영애',true),
  ('10393','HIGH RARE','주예서',true),
  ('10030','NORMAL','공태인',true),
  ('10391','RARE','주예나',true),
  ('10392','SUPER RARE','주예린',true),
  ('10311','MYTHIC RARE','이지영',false),
  ('10397','RARE','진교진',true),
  ('10242','RARE','양지림',true),
  ('10356','NORMAL','정새론',true),
  ('10274','NORMAL','유한결',true),
  ('10192','NORMAL','설달',true),
  ('10093','NORMAL','남태은',true),
  ('10312','ULTRA RARE','이진경',true),
  ('10243','NORMAL','연재은',true),
  ('10231','HIGH RARE','안지윤',true),
  ('10399','SUPER RARE','진하린',true),
  ('10050','NORMAL','김가람',true),
  ('10073','HIGH RARE','김지우',true),
  ('10229','HIGH RARE','안지수',true),
  ('10012','NORMAL','강재아',true),
  ('10219','NORMAL','신주원',true),
  ('10305','NORMAL','이소진',true),
  ('10443','NORMAL','한믿음',true),
  ('10024','SUPER RARE','고세린',true),
  ('10446','NORMAL','한하루',true),
  ('10427','NORMAL','탁리',true),
  ('10411','NORMAL','최여진',true),
  ('10058','ULTRA RARE','김백중',true),
  ('10395','NORMAL','지유현',true),
  ('10213','SUPER RARE','신시은',true),
  ('10175','RARE','서민아',true),
  ('10007','RARE','강세연',true),
  ('10257','HIGH RARE','오채원',true),
  ('10291','ULTRA RARE','[각성] 윤진아',true),
  ('10326','MYTHIC RARE','[각성] 임유리',false),
  ('10288','HIGH RARE','윤은별',true),
  ('10282','NORMAL','윤샛별',true),
  ('10405','RARE','최겨울',true),
  ('10452','HIGH RARE','허유희',true),
  ('10370','RARE','정치환',true),
  ('10368','RARE','정치성',true),
  ('10369','SUPER RARE','정치욱',true),
  ('10358','ULTRA RARE','정석윤',true),
  ('10351','NORMAL','전필수',true),
  ('10449','NORMAL','허요한',true),
  ('10422','NORMAL','최훈필',true),
  ('10421','NORMAL','최훈남',true),
  ('10396','NORMAL','지주현',true)
on conflict (id) do update set grade = excluded.grade, name = excluded.name, gacha = excluded.gacha;

-- 2) 페이즈별 적 수 (처치 수 상한 검증용)
alter table public.story_phase_config add column if not exists enemy_count int not null default 1;
update public.story_phase_config set enemy_count = v.n from (values (1,1,1),(1,2,2),(1,3,2),(1,4,3),(1,5,4)) v(c,p,n) where chapter = v.c and phase = v.p;

-- 3) 레벨 규칙
-- 최대 레벨: N 20 / R 30 / HR 40 / SR 50 / UR 60 / MR 70. ex(합성 단계)마다 +10 (EX 합성용 훅)
create or replace function public._story_cap(g text, ex int default 0) returns int language sql immutable as $$
  select (case g when 'NORMAL' then 20 when 'RARE' then 30 when 'HIGH RARE' then 40 when 'SUPER RARE' then 50 when 'ULTRA RARE' then 60 when 'MYTHIC RARE' then 70 else 20 end) + 10 * greatest(0, coalesce(ex, 0))
$$;
-- 폐기 기본 EXP (등급만)
create or replace function public._story_feed_exp(g text) returns int language sql immutable as $$
  select case g when 'NORMAL' then 50 when 'RARE' then 150 when 'HIGH RARE' then 400 when 'SUPER RARE' then 1000 when 'ULTRA RARE' then 3000 when 'MYTHIC RARE' then 6000 else 50 end
$$;
-- 기본값 채우기
create or replace function public._story_norm(e jsonb) returns jsonb language sql immutable as $$
  select e || jsonb_build_object(
    'count', greatest(1, coalesce((e->>'count')::int, 1)), 'boost', coalesce(e->'boost', '{}'::jsonb),
    'level', greatest(1, coalesce((e->>'level')::int, 1)), 'exp', greatest(0, coalesce((e->>'exp')::int, 0)),
    'totalExp', greatest(0, coalesce((e->>'totalExp')::int, 0)), 'cpts', greatest(0, coalesce((e->>'cpts')::int, 0)),
    'spentCard', greatest(0, coalesce((e->>'spentCard')::int, 0)))
$$;
-- EXP 획득: 다음 레벨 필요 EXP = 레벨 × 100, 레벨업마다 그 카드 전용 포인트 +1, 최대 레벨 초과분은 버림
create or replace function public._story_gain(e jsonb, amt int, g text) returns jsonb language plpgsql immutable as $$
declare lv int; ex int; tot int; cap int; got int := 0;
begin
  e := _story_norm(e);
  lv := (e->>'level')::int; ex := (e->>'exp')::int; cap := _story_cap(g, (e->>'ex')::int);
  if lv >= cap then return e || jsonb_build_object('exp', 0); end if;
  ex := ex + greatest(0, amt);
  tot := (e->>'totalExp')::int;
  while lv < cap and ex >= lv * 100 loop ex := ex - lv * 100; lv := lv + 1; got := got + 1; end loop;
  if lv >= cap then tot := tot + greatest(0, amt) - ex; ex := 0; else tot := tot + greatest(0, amt); end if;
  return e || jsonb_build_object('level', lv, 'exp', ex, 'totalExp', tot, 'cpts', (e->>'cpts')::int + got);
end $$;

-- 4) 전역 포인트 사용량 = 강화 합계 − 카드 전용 포인트로 쓴 양
create or replace function public._story_used(d jsonb) returns int language sql immutable as $$
  select coalesce(sum(greatest(0, coalesce((o->'boost'->>'ATK')::int,0)) + greatest(0, coalesce((o->'boost'->>'HP')::int,0)) + greatest(0, coalesce((o->'boost'->>'DEF')::int,0)) - greatest(0, coalesce((o->>'spentCard')::int, 0))), 0)::int
  from jsonb_array_elements(case when jsonb_typeof(d->'owned') = 'array' then d->'owned' else '[]'::jsonb end) o
$$;

-- 5) 페이즈 클리어 + 전투 EXP. p_stats = [{"id":"카드id","kills":n}, ...] (이번 전투에 낸 내 카드)
--    EXP = (60 + 20 × 처치) × (보스 2배). 보유 카드만, 중복 제외, 처치 합계 ≤ 페이즈 적 수. 재클리어도 EXP는 지급(첫 클리어 보상은 없음)
create or replace function public.story_complete_phase(p_chapter int, p_phase int, p_stats jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb; cfg story_phase_config; b jsonb; cl jsonb; first boolean; rid text; owned jsonb;
        st jsonb; idx int; k int; ksum int := 0; gain int; g text; before int; res jsonb := '[]'::jsonb; seen text[] := '{}';
begin
  select * into cfg from story_phase_config where chapter = p_chapter and phase = p_phase;
  if cfg is null then raise exception 'invalid phase'; end if;
  d := _story_lock(uid);
  b := d->'battle';
  if b is null or (b->>'chapter')::int <> p_chapter or (b->>'phase')::int <> p_phase then raise exception 'battle not started'; end if;
  if extract(epoch from clock_timestamp()) - (b->>'at')::bigint < _story_min_battle_secs() then raise exception 'too fast'; end if;
  d := d - 'battle';
  cl := coalesce(d->'cleared'->(p_chapter::text), '[]'::jsonb);
  first := not cl @> to_jsonb(p_phase);
  if first then
    if d->'cleared' is null or jsonb_typeof(d->'cleared') <> 'object' then d := jsonb_set(d, '{cleared}', '{}'::jsonb); end if;
    d := jsonb_set(d, array['cleared', p_chapter::text], cl || to_jsonb(p_phase));
    d := jsonb_set(d, '{points}', to_jsonb(coalesce((d->>'points')::int, 0) + cfg.points));
    if cfg.reward_grade is not null then
      owned := case when jsonb_typeof(d->'owned') = 'array' then d->'owned' else '[]'::jsonb end;
      select p.id into rid from story_card_pool p
        where p.grade = cfg.reward_grade and p.gacha and not exists (select 1 from jsonb_array_elements(owned) o where o->>'id' = p.id)
        order by random() limit 1;
      if rid is not null then d := jsonb_set(d, '{owned}', owned || jsonb_build_array(jsonb_build_object('id', rid, 'boost', '{}'::jsonb, 'count', 1, 'level', 1, 'exp', 0))); end if;
    end if;
  end if;
  -- 전투 EXP
  owned := case when jsonb_typeof(d->'owned') = 'array' then d->'owned' else '[]'::jsonb end;
  if jsonb_typeof(p_stats) = 'array' and jsonb_array_length(p_stats) <= 30 then
    for st in select * from jsonb_array_elements(p_stats) loop
      continue when jsonb_typeof(st) <> 'object' or (st->>'id') is null or (st->>'id') = any(seen) or (st->>'id') = rid;
      select i - 1 into idx from jsonb_array_elements(owned) with ordinality t(e, i) where t.e->>'id' = st->>'id' limit 1;
      continue when idx is null;
      seen := seen || (st->>'id');
      k := least(greatest(0, coalesce((st->>'kills')::int, 0)), greatest(0, cfg.enemy_count - ksum));
      ksum := ksum + k;
      gain := (60 + 20 * k) * (case when cfg.type = 'boss' then 2 else 1 end);
      select grade into g from story_card_pool where id = st->>'id';
      before := coalesce((owned->idx->>'level')::int, 1);
      owned := jsonb_set(owned, array[idx::text], _story_gain(owned->idx, gain, coalesce(g, 'NORMAL')));
      res := res || jsonb_build_object('id', st->>'id', 'kills', k, 'exp', gain, 'from', before, 'level', (owned->idx->>'level')::int);
    end loop;
    d := jsonb_set(d, '{owned}', owned);
  end if;
  d := _story_save(uid, d);
  return jsonb_build_object('data', d, 'first', first, 'points', case when first then cfg.points else 0 end, 'reward_id', rid, 'exp', res);
end $$;
-- 예전 클라이언트용 (EXP 없이)
create or replace function public.story_complete_phase(p_chapter int, p_phase int) returns jsonb language sql security definer set search_path = public as $$
  select public.story_complete_phase(p_chapter, p_phase, '[]'::jsonb)
$$;

-- 6) 스탯 분배: 카드 전용 포인트(cpts) 먼저, 모자라면 전역 포인트에서
create or replace function public.story_allocate(p_alloc jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb; owned jsonb; k text; v jsonb; s text; n int; total int; gtotal int := 0; idx int; pts int; cp int; fromCard int;
begin
  if jsonb_typeof(p_alloc) <> 'object' then raise exception 'invalid alloc'; end if;
  d := _story_lock(uid);
  owned := case when jsonb_typeof(d->'owned') = 'array' then d->'owned' else '[]'::jsonb end;
  pts := greatest(0, coalesce((d->>'points')::int, 0));
  for k, v in select * from jsonb_each(p_alloc) loop
    select i - 1 into idx from jsonb_array_elements(owned) with ordinality t(e, i) where t.e->>'id' = k limit 1;
    if idx is null then raise exception 'card not owned'; end if;
    if jsonb_typeof(v) <> 'object' then raise exception 'invalid alloc'; end if;
    owned := jsonb_set(owned, array[idx::text], _story_norm(owned->idx));
    total := 0;
    for s in select jsonb_object_keys(v) loop
      if s not in ('ATK', 'HP', 'DEF') then raise exception 'invalid stat'; end if;
      if jsonb_typeof(v->s) <> 'number' then raise exception 'invalid amount'; end if;
      n := (v->>s)::int;
      if n < 0 or n::text <> (v->>s) then raise exception 'invalid amount'; end if;
      total := total + n;
      owned := jsonb_set(owned, array[idx::text, 'boost'], coalesce(owned->idx->'boost', '{}'::jsonb) || jsonb_build_object(s, coalesce((owned->idx->'boost'->>s)::int, 0) + n));
    end loop;
    cp := (owned->idx->>'cpts')::int;
    fromCard := least(cp, total);
    gtotal := gtotal + (total - fromCard);
    owned := jsonb_set(owned, array[idx::text], owned->idx || jsonb_build_object('cpts', cp - fromCard, 'spentCard', (owned->idx->>'spentCard')::int + fromCard));
  end loop;
  if gtotal > pts then raise exception 'not enough points'; end if;
  d := jsonb_set(jsonb_set(d, '{owned}', owned), '{points}', to_jsonb(pts - gtotal));
  return _story_save(uid, d);
end $$;

-- 7) 폐기: p_id 카드 1장을 없애고 p_target 카드에 EXP.
--    EXP = 등급 기본값 × (같은 이름이면 1.5) + (그 항목이 통째로 없어질 때) 누적 EXP의 50%
--    중복(count>1)이면 사본 1장만 소모(레벨·강화는 남은 카드에 유지). 마지막 1장이면 항목 제거 + 전역 포인트로 강화한 만큼 돌려줌
--    리더(시작 카드)는 마지막 1장을 폐기할 수 없음. 대상 자신(마지막 1장)도 불가
create or replace function public.story_discard(p_id text, p_target text) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb; owned jsonb; i1 int; i2 int; e1 jsonb; c1 int; g1 text; n1 text; g2 text; n2 text; amt int; whole boolean; refund int := 0; before int; t jsonb;
begin
  d := _story_lock(uid);
  owned := case when jsonb_typeof(d->'owned') = 'array' then d->'owned' else '[]'::jsonb end;
  select i - 1 into i1 from jsonb_array_elements(owned) with ordinality t(e, i) where t.e->>'id' = p_id limit 1;
  select i - 1 into i2 from jsonb_array_elements(owned) with ordinality t(e, i) where t.e->>'id' = p_target limit 1;
  if i1 is null or i2 is null then raise exception 'card not owned'; end if;
  e1 := _story_norm(owned->i1); c1 := (e1->>'count')::int; whole := c1 <= 1;
  if whole and p_id = coalesce(d->>'starter', '') then raise exception 'cannot discard leader'; end if;
  if whole and p_id = p_target then raise exception 'cannot discard target'; end if;
  select grade, name into g1, n1 from story_card_pool where id = p_id;
  select grade, name into g2, n2 from story_card_pool where id = p_target;
  amt := _story_feed_exp(coalesce(g1, 'NORMAL'));
  if n1 is not null and n1 = n2 then amt := floor(amt * 1.5); end if;
  if whole then
    amt := amt + floor((e1->>'totalExp')::int * 0.5);
    refund := greatest(0, coalesce((e1->'boost'->>'ATK')::int,0) + coalesce((e1->'boost'->>'HP')::int,0) + coalesce((e1->'boost'->>'DEF')::int,0) - (e1->>'spentCard')::int);
  end if;
  before := coalesce((owned->i2->>'level')::int, 1);
  t := _story_gain(owned->i2, amt, coalesce(g2, 'NORMAL'));
  owned := jsonb_set(owned, array[i2::text], t);
  if whole then owned := owned - i1;
  else owned := jsonb_set(owned, array[i1::text, 'count'], to_jsonb(c1 - 1)); end if;
  d := jsonb_set(d, '{owned}', owned);
  if refund > 0 then d := jsonb_set(d, '{points}', to_jsonb(coalesce((d->>'points')::int, 0) + refund)); end if;
  d := _story_save(uid, d);
  return jsonb_build_object('data', d, 'exp', amt, 'from', before, 'level', (t->>'level')::int, 'refund', refund);
end $$;

revoke all on function public._story_cap(text, int), public._story_feed_exp(text), public._story_norm(jsonb), public._story_gain(jsonb, int, text), public._story_used(jsonb) from public, anon, authenticated;
revoke all on function public.story_complete_phase(int, int, jsonb), public.story_complete_phase(int, int), public.story_allocate(jsonb), public.story_discard(text, text) from public, anon;
grant execute on function public.story_complete_phase(int, int, jsonb), public.story_complete_phase(int, int), public.story_allocate(jsonb), public.story_discard(text, text) to authenticated;

-- 8) 기존 데이터: 보유 카드에 레벨 기본값 채우기 (기존 강화는 전역 포인트로 쓴 것으로 간주)
update public.story_progress sp set data = jsonb_set(sp.data, '{owned}', (select coalesce(jsonb_agg(public._story_norm(o) order by n), '[]'::jsonb) from jsonb_array_elements(sp.data->'owned') with ordinality x(o, n)))
  where jsonb_typeof(sp.data->'owned') = 'array';

-- ===== 스토리 카드 레벨 스탯 + 일괄 폐기 (supabase/story_level_stats.sql 과 동일) =====

-- 1) EXP 획득: 레벨업 시 cpts 지급 없음
create or replace function public._story_gain(e jsonb, amt int, g text) returns jsonb language plpgsql immutable as $$
declare lv int; ex int; tot int; cap int;
begin
  e := _story_norm(e);
  lv := (e->>'level')::int; ex := (e->>'exp')::int; cap := _story_cap(g, (e->>'ex')::int);
  if lv >= cap then return e || jsonb_build_object('exp', 0); end if;
  ex := ex + greatest(0, amt);
  tot := (e->>'totalExp')::int;
  while lv < cap and ex >= lv * 100 loop ex := ex - lv * 100; lv := lv + 1; end loop;
  if lv >= cap then tot := tot + greatest(0, amt) - ex; ex := 0; else tot := tot + greatest(0, amt); end if;
  return e || jsonb_build_object('level', lv, 'exp', ex, 'totalExp', tot);
end $$;
revoke all on function public._story_gain(jsonb, int, text) from public, anon, authenticated;

-- 2) 일괄 폐기. p_ids 의 같은 id 가 여러 번 있으면 그만큼(사본부터) 폐기.
--    규칙은 story_discard 와 같음: 등급 기본 EXP × (대상과 같은 이름이면 1.5), 마지막 1장이면 누적 EXP 50% 추가 + 공용 포인트로 올린 강화 환급.
--    대상 카드 자신과 리더의 마지막 1장은 폐기 불가. 최대 200장.
create or replace function public.story_discard_many(p_ids text[], p_target text) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb; owned jsonb; pid text; i1 int; i2 int; e1 jsonb; c1 int; g1 text; n1 text; g2 text; n2 text;
        amt int; total int := 0; refund int := 0; n int := 0; before int; t jsonb;
begin
  if p_ids is null or cardinality(p_ids) = 0 then raise exception 'nothing to discard'; end if;
  if cardinality(p_ids) > 200 then raise exception 'too many cards'; end if;
  if p_target = any(p_ids) then raise exception 'cannot discard target'; end if;
  d := _story_lock(uid);
  owned := case when jsonb_typeof(d->'owned') = 'array' then d->'owned' else '[]'::jsonb end;
  if not exists (select 1 from jsonb_array_elements(owned) o where o->>'id' = p_target) then raise exception 'card not owned'; end if;
  select grade, name into g2, n2 from story_card_pool where id = p_target;
  foreach pid in array p_ids loop
    select i - 1 into i1 from jsonb_array_elements(owned) with ordinality x(e, i) where x.e->>'id' = pid limit 1;
    if i1 is null then raise exception 'card not owned'; end if;
    e1 := _story_norm(owned->i1); c1 := (e1->>'count')::int;
    if c1 <= 1 and pid = coalesce(d->>'starter', '') then raise exception 'cannot discard leader'; end if;
    select grade, name into g1, n1 from story_card_pool where id = pid;
    amt := _story_feed_exp(coalesce(g1, 'NORMAL'));
    if n1 is not null and n1 = n2 then amt := floor(amt * 1.5); end if;
    if c1 <= 1 then
      amt := amt + floor((e1->>'totalExp')::int * 0.5);
      refund := refund + greatest(0, coalesce((e1->'boost'->>'ATK')::int,0) + coalesce((e1->'boost'->>'HP')::int,0) + coalesce((e1->'boost'->>'DEF')::int,0) - (e1->>'spentCard')::int);
      owned := owned - i1;
    else
      owned := jsonb_set(owned, array[i1::text, 'count'], to_jsonb(c1 - 1));
    end if;
    total := total + amt; n := n + 1;
  end loop;
  select i - 1 into i2 from jsonb_array_elements(owned) with ordinality x(e, i) where x.e->>'id' = p_target limit 1;
  before := coalesce((owned->i2->>'level')::int, 1);
  t := _story_gain(owned->i2, total, coalesce(g2, 'NORMAL'));
  owned := jsonb_set(owned, array[i2::text], t);
  d := jsonb_set(d, '{owned}', owned);
  if refund > 0 then d := jsonb_set(d, '{points}', to_jsonb(coalesce((d->>'points')::int, 0) + refund)); end if;
  d := _story_save(uid, d);
  return jsonb_build_object('data', d, 'count', n, 'exp', total, 'from', before, 'level', (t->>'level')::int, 'refund', refund);
end $$;
revoke all on function public.story_discard_many(text[], text) from public, anon;
grant execute on function public.story_discard_many(text[], text) to authenticated;

-- ===== 스토리 카드 개별 인스턴스 + EX 합성 (supabase/story_merge.sql 과 동일) =====
-- ----- 도우미 -----
create or replace function public._story_cap(g text, ex int default 0) returns int language sql immutable as $$
  select (case g when 'NORMAL' then 20 when 'RARE' then 30 when 'HIGH RARE' then 40 when 'SUPER RARE' then 50 when 'ULTRA RARE' then 60 when 'MYTHIC RARE' then 70 else 20 end) + 5 * greatest(0, coalesce(ex, 0))
$$;
create or replace function public._story_max_ex(g text) returns int language sql immutable as $$
  select case g when 'NORMAL' then 1 when 'RARE' then 2 when 'HIGH RARE' then 3 when 'SUPER RARE' then 4 when 'ULTRA RARE' then 5 when 'MYTHIC RARE' then 6 else 1 end
$$;
drop function if exists public._story_merge_mat_ratio(jsonb);
-- 새 인스턴스 uid
create or replace function public._story_new_uid() returns text language sql volatile as $$
  select 'c' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 15)
$$;
-- 인스턴스 기본값 (count 없음)
create or replace function public._story_norm(e jsonb) returns jsonb language sql immutable as $$
  select (e - 'count') || jsonb_build_object(
    'boost', coalesce(e->'boost', '{}'::jsonb),
    'level', greatest(1, coalesce((e->>'level')::int, 1)), 'exp', greatest(0, coalesce((e->>'exp')::int, 0)),
    'totalExp', greatest(0, coalesce((e->>'totalExp')::int, 0)), 'cpts', greatest(0, coalesce((e->>'cpts')::int, 0)),
    'spentCard', greatest(0, coalesce((e->>'spentCard')::int, 0)),
    'ex', greatest(0, coalesce((e->>'ex')::int, 0)), 'exb', greatest(0, coalesce((e->>'exb')::numeric, 0)))
$$;
-- 새 카드 1장
create or replace function public._story_new_card(cid text) returns jsonb language sql volatile as $$
  select jsonb_build_object('uid', public._story_new_uid(), 'id', cid, 'boost', '{}'::jsonb, 'level', 1, 'exp', 0, 'totalExp', 0, 'cpts', 0, 'spentCard', 0, 'ex', 0, 'exb', 0)
$$;
-- 예전 형식(count) → 인스턴스. 리더 uid 지정. 여러 번 실행해도 결과 동일
create or replace function public._story_migrate(d jsonb) returns jsonb language plpgsql volatile set search_path = public as $$
declare e jsonb; res jsonb := '[]'::jsonb; c int; k int; lead text;
begin
  if d is null then return d; end if;
  if jsonb_typeof(d->'owned') = 'array' then
    for e in select x from jsonb_array_elements(d->'owned') x loop
      continue when jsonb_typeof(e) <> 'object' or coalesce(e->>'id', '') = '';
      if coalesce(e->>'uid', '') <> '' then res := res || jsonb_build_array(_story_norm(e)); continue; end if;
      c := greatest(1, least(500, coalesce((e->>'count')::int, 1)));
      res := res || jsonb_build_array(_story_norm(e) || jsonb_build_object('uid', _story_new_uid()));
      for k in 2..c loop res := res || jsonb_build_array(_story_new_card(e->>'id')); end loop;
    end loop;
    d := jsonb_set(d, '{owned}', res);
  end if;
  lead := d->>'leader';
  if coalesce(d->>'starter', '') <> '' and (lead is null or not exists (select 1 from jsonb_array_elements(coalesce(d->'owned', '[]'::jsonb)) o where o->>'uid' = lead)) then
    select o->>'uid' into lead from jsonb_array_elements(coalesce(d->'owned', '[]'::jsonb)) o where o->>'id' = d->>'starter' limit 1;
    if lead is not null then d := jsonb_set(d, '{leader}', to_jsonb(lead)); end if;
  end if;
  return d;
end $$;
-- 행 잠금 + 마이그레이션
create or replace function public._story_lock(uid uuid) returns jsonb language plpgsql set search_path = public as $$
declare d jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  insert into story_progress (user_id, data) values (uid, '{}'::jsonb) on conflict (user_id) do nothing;
  select data into d from story_progress where user_id = uid for update;
  return _story_migrate(coalesce(d, '{}'::jsonb));
end $$;
-- 인스턴스 찾기: uid 우선, 없으면 카드 id 의 첫 인스턴스 (예전 클라이언트 호환). 0부터 시작하는 위치, 없으면 null
create or replace function public._story_find(owned jsonb, k text) returns int language sql immutable as $$
  select coalesce(
    (select (n - 1)::int from jsonb_array_elements(owned) with ordinality x(e, n) where x.e->>'uid' = k limit 1),
    (select (n - 1)::int from jsonb_array_elements(owned) with ordinality x(e, n) where x.e->>'id' = k order by n limit 1))
$$;
create or replace function public._story_owned(d jsonb) returns jsonb language sql immutable as $$
  select case when jsonb_typeof(d->'owned') = 'array' then d->'owned' else '[]'::jsonb end
$$;
revoke all on function public._story_cap(text, int), public._story_max_ex(text), public._story_new_uid(), public._story_norm(jsonb), public._story_new_card(text),
  public._story_migrate(jsonb), public._story_lock(uuid), public._story_find(jsonb, text), public._story_owned(jsonb) from public, anon, authenticated;

-- ----- 시작 캐릭터 선택: 새 인스턴스를 맨 앞(리더)으로. 이미 가진 같은 카드(뽑기 등)는 그대로 유지 -----
create or replace function public.story_choose_starter(p_id text) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb; e jsonb;
begin
  if p_id not in ('10111', '10265', '10224') then raise exception 'invalid starter'; end if;
  d := _story_lock(uid);
  if coalesce(d->>'starter', '') <> '' then raise exception 'starter already chosen'; end if;
  e := _story_new_card(p_id);
  d := jsonb_set(jsonb_set(jsonb_set(d, '{starter}', to_jsonb(p_id)), '{leader}', e->'uid'), '{owned}', jsonb_build_array(e) || _story_owned(d));
  if d->'points' is null then d := jsonb_set(d, '{points}', '0'::jsonb); end if;
  if d->'cleared' is null then d := jsonb_set(d, '{cleared}', '{}'::jsonb); end if;
  return _story_save(uid, d);
end $$;

-- ----- 일일 뽑기: 뽑을 때마다 새 인스턴스. count = 그 카드 보유 장수 -----
create or replace function public.story_daily_draw() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); today date := (now() at time zone 'Asia/Seoul')::date; last date; r double precision; g text; cid text; d jsonb; owned jsonb; e jsonb; cnt int;
begin
  if uid is null then raise exception 'login required'; end if;
  insert into story_gacha (user_id, last_draw) values (uid, today - 1) on conflict (user_id) do nothing;
  select last_draw into last from story_gacha where user_id = uid for update;
  if last >= today then return jsonb_build_object('ok', false, 'reason', 'already', 'day', today); end if;
  r := random();
  g := case when r < 0.70 then 'NORMAL' when r < 0.90 then 'RARE' when r < 0.965 then 'HIGH RARE' when r < 0.995 then 'SUPER RARE' else 'ULTRA RARE' end;
  select id into cid from story_card_pool where grade = g and coalesce(gacha, true) order by random() limit 1;
  if cid is null then raise exception 'empty pool for %', g; end if;
  d := _story_lock(uid);
  e := _story_new_card(cid);
  owned := _story_owned(d) || jsonb_build_array(e);
  select count(*) into cnt from jsonb_array_elements(owned) o where o->>'id' = cid;
  d := jsonb_set(jsonb_set(d, '{owned}', owned), '{gachaLast}', to_jsonb(today::text));
  d := _story_save(uid, d);
  update story_gacha set last_draw = today, updated_at = now() where user_id = uid;
  insert into story_gacha_log (user_id, card_id, grade) values (uid, cid, g);
  return jsonb_build_object('ok', true, 'card_id', cid, 'uid', e->>'uid', 'grade', g, 'count', cnt, 'day', today);
end $$;
revoke all on function public.story_daily_draw() from public, anon;
grant execute on function public.story_daily_draw() to authenticated;

-- ----- 페이즈 클리어 + 전투 EXP. p_stats = [{"uid":"인스턴스 uid"(또는 "id":"카드 id"),"kills":n}, ...] -----
create or replace function public.story_complete_phase(p_chapter int, p_phase int, p_stats jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb; cfg story_phase_config; b jsonb; cl jsonb; first boolean; rid text; ruid text; owned jsonb; ne jsonb;
        st jsonb; idx int; k int; ksum int := 0; gain int; g text; before int; res jsonb := '[]'::jsonb; seen int[] := '{}'; key text;
begin
  select * into cfg from story_phase_config where chapter = p_chapter and phase = p_phase;
  if cfg is null then raise exception 'invalid phase'; end if;
  d := _story_lock(uid);
  b := d->'battle';
  if b is null or (b->>'chapter')::int <> p_chapter or (b->>'phase')::int <> p_phase then raise exception 'battle not started'; end if;
  if extract(epoch from clock_timestamp()) - (b->>'at')::bigint < _story_min_battle_secs() then raise exception 'too fast'; end if;
  d := d - 'battle';
  cl := coalesce(d->'cleared'->(p_chapter::text), '[]'::jsonb);
  first := not cl @> to_jsonb(p_phase);
  owned := _story_owned(d);
  if first then
    if d->'cleared' is null or jsonb_typeof(d->'cleared') <> 'object' then d := jsonb_set(d, '{cleared}', '{}'::jsonb); end if;
    d := jsonb_set(d, array['cleared', p_chapter::text], cl || to_jsonb(p_phase));
    d := jsonb_set(d, '{points}', to_jsonb(coalesce((d->>'points')::int, 0) + cfg.points));
    if cfg.reward_grade is not null then
      select p.id into rid from story_card_pool p
        where p.grade = cfg.reward_grade and p.gacha and not exists (select 1 from jsonb_array_elements(owned) o where o->>'id' = p.id)
        order by random() limit 1;
      if rid is not null then ne := _story_new_card(rid); ruid := ne->>'uid'; owned := owned || jsonb_build_array(ne); end if;
    end if;
  end if;
  if jsonb_typeof(p_stats) = 'array' and jsonb_array_length(p_stats) <= 30 then
    for st in select * from jsonb_array_elements(p_stats) loop
      continue when jsonb_typeof(st) <> 'object';
      key := coalesce(st->>'uid', st->>'id');
      continue when key is null or key = rid or key = ruid;
      idx := _story_find(owned, key);
      continue when idx is null or idx = any(seen) or (owned->idx->>'uid') = ruid;
      seen := seen || idx;
      k := least(greatest(0, coalesce((st->>'kills')::int, 0)), greatest(0, cfg.enemy_count - ksum));
      ksum := ksum + k;
      gain := (60 + 20 * k) * (case when cfg.type = 'boss' then 2 else 1 end);
      select grade into g from story_card_pool where id = owned->idx->>'id';
      before := coalesce((owned->idx->>'level')::int, 1);
      owned := jsonb_set(owned, array[idx::text], _story_gain(owned->idx, gain, coalesce(g, 'NORMAL')));
      res := res || jsonb_build_object('uid', owned->idx->>'uid', 'id', owned->idx->>'id', 'kills', k, 'exp', gain, 'from', before, 'level', (owned->idx->>'level')::int);
    end loop;
  end if;
  d := jsonb_set(d, '{owned}', owned);
  d := _story_save(uid, d);
  return jsonb_build_object('data', d, 'first', first, 'points', case when first then cfg.points else 0 end, 'reward_id', rid, 'reward_uid', ruid, 'exp', res);
end $$;

-- ----- 스탯 분배: p_alloc = { "인스턴스 uid"(또는 카드 id): {"ATK":n,...} }. 카드 전용 포인트 먼저 -----
create or replace function public.story_allocate(p_alloc jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb; owned jsonb; k text; v jsonb; s text; n int; total int; gtotal int := 0; idx int; pts int; cp int; fromCard int;
begin
  if jsonb_typeof(p_alloc) <> 'object' then raise exception 'invalid alloc'; end if;
  d := _story_lock(uid);
  owned := _story_owned(d);
  pts := greatest(0, coalesce((d->>'points')::int, 0));
  for k, v in select * from jsonb_each(p_alloc) loop
    idx := _story_find(owned, k);
    if idx is null then raise exception 'card not owned'; end if;
    if jsonb_typeof(v) <> 'object' then raise exception 'invalid alloc'; end if;
    owned := jsonb_set(owned, array[idx::text], _story_norm(owned->idx));
    total := 0;
    for s in select jsonb_object_keys(v) loop
      if s not in ('ATK', 'HP', 'DEF') then raise exception 'invalid stat'; end if;
      if jsonb_typeof(v->s) <> 'number' then raise exception 'invalid amount'; end if;
      n := (v->>s)::int;
      if n < 0 or n::text <> (v->>s) then raise exception 'invalid amount'; end if;
      total := total + n;
      owned := jsonb_set(owned, array[idx::text, 'boost'], coalesce(owned->idx->'boost', '{}'::jsonb) || jsonb_build_object(s, coalesce((owned->idx->'boost'->>s)::int, 0) + n));
    end loop;
    cp := (owned->idx->>'cpts')::int;
    fromCard := least(cp, total);
    gtotal := gtotal + (total - fromCard);
    owned := jsonb_set(owned, array[idx::text], owned->idx || jsonb_build_object('cpts', cp - fromCard, 'spentCard', (owned->idx->>'spentCard')::int + fromCard));
  end loop;
  if gtotal > pts then raise exception 'not enough points'; end if;
  d := jsonb_set(jsonb_set(d, '{owned}', owned), '{points}', to_jsonb(pts - gtotal));
  return _story_save(uid, d);
end $$;

-- ----- 일괄 폐기 (인스턴스 단위): 각 장 EXP = 등급 기본 × (대상과 같은 이름이면 1.5) + 그 장의 누적 EXP 50%, 공용 포인트로 올린 강화 환급 -----
--       대상 자신·리더 인스턴스 불가, 같은 장 중복 지정 불가, 최대 200장. 전부 성공 또는 전부 취소
create or replace function public.story_discard_many(p_ids text[], p_target text) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb; owned jsonb; pid text; i1 int; i2 int; e1 jsonb; g1 text; n1 text; g2 text; n2 text; tuid text; lead text;
        amt int; total int := 0; refund int := 0; n int := 0; before int; t jsonb; gone text[] := '{}'; u1 text;
begin
  if p_ids is null or cardinality(p_ids) = 0 then raise exception 'nothing to discard'; end if;
  if cardinality(p_ids) > 200 then raise exception 'too many cards'; end if;
  d := _story_lock(uid);
  owned := _story_owned(d); lead := d->>'leader';
  i2 := _story_find(owned, p_target);
  if i2 is null then raise exception 'card not owned'; end if;
  tuid := owned->i2->>'uid';
  select grade, name into g2, n2 from story_card_pool where id = owned->i2->>'id';
  foreach pid in array p_ids loop
    -- 예전 클라이언트(카드 id): 아직 고르지 않은 그 카드의 인스턴스 중 대상·리더가 아닌 첫 장
    select x.e->>'uid' into u1 from jsonb_array_elements(owned) with ordinality x(e, k)
      where (x.e->>'uid' = pid or (x.e->>'id' = pid and not exists (select 1 from jsonb_array_elements(owned) y where y->>'uid' = pid)))
        and not (x.e->>'uid' = any(gone)) and (x.e->>'uid' = pid or (x.e->>'uid' <> tuid and x.e->>'uid' is distinct from lead))
      order by k limit 1;
    if u1 is null then raise exception 'card not owned'; end if;
    if u1 = tuid then raise exception 'cannot discard target'; end if;
    if u1 = lead then raise exception 'cannot discard leader'; end if;
    gone := gone || u1;
    select x.e into e1 from jsonb_array_elements(owned) x(e) where x.e->>'uid' = u1;
    e1 := _story_norm(e1);
    select grade, name into g1, n1 from story_card_pool where id = e1->>'id';
    amt := _story_feed_exp(coalesce(g1, 'NORMAL'));
    if n1 is not null and n1 = n2 then amt := floor(amt * 1.5); end if;
    amt := amt + floor((e1->>'totalExp')::int * 0.5);
    refund := refund + greatest(0, coalesce((e1->'boost'->>'ATK')::int,0) + coalesce((e1->'boost'->>'HP')::int,0) + coalesce((e1->'boost'->>'DEF')::int,0) - (e1->>'spentCard')::int);
    total := total + amt; n := n + 1;
  end loop;
  select coalesce(jsonb_agg(x.e order by k), '[]'::jsonb) into owned from jsonb_array_elements(owned) with ordinality x(e, k) where not (x.e->>'uid' = any(gone));
  i2 := _story_find(owned, tuid);
  before := coalesce((owned->i2->>'level')::int, 1);
  t := _story_gain(owned->i2, total, coalesce(g2, 'NORMAL'));
  owned := jsonb_set(owned, array[i2::text], t);
  d := jsonb_set(d, '{owned}', owned);
  if refund > 0 then d := jsonb_set(d, '{points}', to_jsonb(coalesce((d->>'points')::int, 0) + refund)); end if;
  d := _story_save(uid, d);
  return jsonb_build_object('data', d, 'count', n, 'exp', total, 'from', before, 'level', (t->>'level')::int, 'refund', refund);
end $$;
revoke all on function public.story_discard_many(text[], text) from public, anon;
grant execute on function public.story_discard_many(text[], text) to authenticated;

-- ----- 1장 폐기 = 일괄 폐기 1장 (결과 형식은 예전과 같음) -----
create or replace function public.story_discard(p_id text, p_target text) returns jsonb language plpgsql security definer set search_path = public as $$
declare r jsonb;
begin
  r := public.story_discard_many(array[p_id], p_target);
  return r - 'count';
end $$;
revoke all on function public.story_discard(text, text) from public, anon;
grant execute on function public.story_discard(text, text) to authenticated;

-- ----- EX 합성 -----
drop function if exists public.story_merge(text);
create or replace function public.story_merge(p_target text, p_material text) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb; owned jsonb; it int; im int; et jsonb; em jsonb; g text; ex int; lt int; ct int; lm int; cm int; bonus numeric; exb numeric;
begin
  d := _story_lock(uid);
  owned := _story_owned(d);
  select (n - 1)::int into it from jsonb_array_elements(owned) with ordinality x(e, n) where x.e->>'uid' = p_target;
  select (n - 1)::int into im from jsonb_array_elements(owned) with ordinality x(e, n) where x.e->>'uid' = p_material;
  if it is null or im is null then raise exception 'card not owned'; end if;
  if it = im then raise exception 'material is target'; end if;
  et := _story_norm(owned->it); em := _story_norm(owned->im);
  if et->>'id' <> em->>'id' then raise exception 'material must be same card'; end if;
  if em->>'uid' = coalesce(d->>'leader', '') then raise exception 'cannot use leader as material'; end if;
  select grade into g from story_card_pool where id = et->>'id';
  g := coalesce(g, 'NORMAL');
  ex := (et->>'ex')::int;
  if ex >= _story_max_ex(g) then raise exception 'max ex'; end if;
  lt := (et->>'level')::int; ct := _story_cap(g, ex);
  lm := (em->>'level')::int; cm := _story_cap(g, (em->>'ex')::int);
  bonus := round(10 * least(1, lt::numeric / ct) * least(1, lm::numeric / cm), 2);
  exb := round((et->>'exb')::numeric + bonus, 2);
  et := et || jsonb_build_object('ex', ex + 1, 'exb', exb, 'level', 1, 'exp', 0);
  owned := jsonb_set(owned, array[it::text], et);
  owned := owned - im;
  d := _story_save(uid, jsonb_set(d, '{owned}', owned));
  return jsonb_build_object('data', d, 'ex', ex + 1, 'bonus', bonus, 'exb', exb, 'target_level', lt, 'target_cap', ct, 'material_level', lm, 'material_cap', cm, 'cap_to', _story_cap(g, ex + 1));
end $$;
revoke all on function public.story_merge(text, text) from public, anon;
grant execute on function public.story_merge(text, text) to authenticated;

-- ----- 기존 데이터 마이그레이션 (예전 형식 행만 바뀜) -----
update public.story_progress sp set data = public._story_migrate(sp.data), updated_at = now()
  where exists (select 1 from jsonb_array_elements(case when jsonb_typeof(sp.data->'owned') = 'array' then sp.data->'owned' else '[]'::jsonb end) o where coalesce(o->>'uid', '') = '')
     or (coalesce(sp.data->>'starter', '') <> '' and sp.data->'leader' is null);

-- ===== 스토리 챕터 2 (supabase/story_ch2.sql 과 동일) =====
-- 1) 페이즈 설정: 챕터 2는 카드 보상 없이 스탯 포인트만 (일반 3, 보스 5). enemy_count = 그 페이즈 적 수(보스 포함, 챕터 1과 같은 방식)
insert into public.story_phase_config (chapter, phase, type, points, reward_grade, enemy_count) values
  (2,1,'normal',3,null,5), (2,2,'normal',3,null,5), (2,3,'normal',3,null,5), (2,4,'normal',3,null,5), (2,5,'normal',3,null,5),
  (2,6,'normal',3,null,5), (2,7,'normal',3,null,5), (2,8,'normal',3,null,5), (2,9,'normal',3,null,5), (2,10,'boss',5,null,5)
on conflict (chapter, phase) do update set type = excluded.type, points = excluded.points, reward_grade = excluded.reward_grade, enemy_count = excluded.enemy_count;

-- 2) 루트 선택: data.routes = { "2": "카드 id" }. 그 챕터 페이즈를 하나라도 깨면 다른 루트로 바꿀 수 없음
create or replace function public.story_choose_route(p_chapter int, p_route text) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb; cur text;
begin
  if not (p_chapter = 2 and p_route in ('10298', '10081')) then raise exception 'invalid route'; end if;
  d := _story_lock(uid);
  if coalesce(d->>'starter', '') = '' then raise exception 'choose starter first'; end if;
  cur := d->'routes'->>(p_chapter::text);
  if cur is not null and cur <> p_route and jsonb_array_length(coalesce(d->'cleared'->(p_chapter::text), '[]'::jsonb)) > 0 then raise exception 'route locked'; end if;
  if d->'routes' is null or jsonb_typeof(d->'routes') <> 'object' then d := jsonb_set(d, '{routes}', '{}'::jsonb); end if;
  d := jsonb_set(d, array['routes', p_chapter::text], to_jsonb(p_route));
  return _story_save(uid, d);
end $$;
revoke all on function public.story_choose_route(int, text) from public, anon;
grant execute on function public.story_choose_route(int, text) to authenticated;

-- ===== 스토리 스탯 포인트 규칙 변경 (statV 2) — Supabase SQL Editor 에서 한 번 실행 =====
-- 규칙: 포인트 1당 ATK +1 / HP +5 / DEF +1 (상승량 계산은 클라이언트 js/story.js ptGain, 서버는 포인트 개수만 저장)
--       같은 스탯 6번째 포인트부터 절반 (클라이언트 계산) · 한 스탯에는 그 카드 포인트 합계의 절반(올림)까지 (여기서 검사)
-- 예전 분배는 전부 돌려줌: 카드 전용 포인트로 쓴 양(spentCard)은 그 카드 cpts 로, 나머지는 공용 points 로. boost = {}
-- 여러 번 실행해도 안전 (statV 가 2 이상이면 건드리지 않음)

create or replace function public._story_refund_stats(d jsonb) returns jsonb language plpgsql immutable as $$
declare e jsonb; res jsonb := '[]'::jsonb; used int; crd int; pts int; total int := 0;
begin
  if d is null or coalesce((d->>'statV')::int, 1) >= 2 then return d; end if;
  pts := greatest(0, coalesce((d->>'points')::int, 0));
  if jsonb_typeof(d->'owned') = 'array' then
    for e in select x from jsonb_array_elements(d->'owned') x loop
      if jsonb_typeof(e) = 'object' then
        used := greatest(0, coalesce((e->'boost'->>'ATK')::int, 0)) + greatest(0, coalesce((e->'boost'->>'HP')::int, 0)) + greatest(0, coalesce((e->'boost'->>'DEF')::int, 0));
        crd := least(used, greatest(0, coalesce((e->>'spentCard')::int, 0)));
        pts := pts + used - crd; total := total + used;
        e := e || jsonb_build_object('boost', '{}'::jsonb, 'spentCard', 0, 'cpts', greatest(0, coalesce((e->>'cpts')::int, 0)) + crd);
      end if;
      res := res || jsonb_build_array(e);
    end loop;
    d := jsonb_set(d, '{owned}', res);
  end if;
  return d || jsonb_build_object('points', pts, 'statV', 2) || case when total > 0 then jsonb_build_object('statRefunded', true) else '{}'::jsonb end;
end $$;

-- 행 잠금 + 마이그레이션 + (예전 규칙이면) 환급
create or replace function public._story_lock(uid uuid) returns jsonb language plpgsql set search_path = public as $$
declare d jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  insert into story_progress (user_id, data) values (uid, jsonb_build_object('statV', 2)) on conflict (user_id) do nothing;
  select data into d from story_progress where user_id = uid for update;
  return _story_refund_stats(_story_migrate(coalesce(d, '{}'::jsonb)));
end $$;
revoke all on function public._story_refund_stats(jsonb), public._story_lock(uuid) from public, anon, authenticated;

-- ----- 스탯 분배: p_alloc = { "인스턴스 uid"(또는 카드 id): {"ATK":n,...} }. 카드 전용 포인트 먼저 · 한 스탯 ≤ 합계의 절반(올림) -----
create or replace function public.story_allocate(p_alloc jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb; owned jsonb; k text; v jsonb; s text; n int; total int; gtotal int := 0; idx int; pts int; cp int; fromCard int; b jsonb; bsum int;
begin
  if jsonb_typeof(p_alloc) <> 'object' then raise exception 'invalid alloc'; end if;
  d := _story_lock(uid);
  owned := _story_owned(d);
  pts := greatest(0, coalesce((d->>'points')::int, 0));
  for k, v in select * from jsonb_each(p_alloc) loop
    idx := _story_find(owned, k);
    if idx is null then raise exception 'card not owned'; end if;
    if jsonb_typeof(v) <> 'object' then raise exception 'invalid alloc'; end if;
    owned := jsonb_set(owned, array[idx::text], _story_norm(owned->idx));
    total := 0;
    for s in select jsonb_object_keys(v) loop
      if s not in ('ATK', 'HP', 'DEF') then raise exception 'invalid stat'; end if;
      if jsonb_typeof(v->s) <> 'number' then raise exception 'invalid amount'; end if;
      n := (v->>s)::int;
      if n < 0 or n::text <> (v->>s) then raise exception 'invalid amount'; end if;
      total := total + n;
      owned := jsonb_set(owned, array[idx::text, 'boost'], coalesce(owned->idx->'boost', '{}'::jsonb) || jsonb_build_object(s, coalesce((owned->idx->'boost'->>s)::int, 0) + n));
    end loop;
    b := owned->idx->'boost';
    bsum := coalesce((b->>'ATK')::int, 0) + coalesce((b->>'HP')::int, 0) + coalesce((b->>'DEF')::int, 0);
    if greatest(coalesce((b->>'ATK')::int, 0), coalesce((b->>'HP')::int, 0), coalesce((b->>'DEF')::int, 0)) > (bsum + 1) / 2 then raise exception 'stat cap'; end if;
    cp := (owned->idx->>'cpts')::int;
    fromCard := least(cp, total);
    gtotal := gtotal + (total - fromCard);
    owned := jsonb_set(owned, array[idx::text], owned->idx || jsonb_build_object('cpts', cp - fromCard, 'spentCard', (owned->idx->>'spentCard')::int + fromCard));
  end loop;
  if gtotal > pts then raise exception 'not enough points'; end if;
  d := jsonb_set(jsonb_set(d, '{owned}', owned), '{points}', to_jsonb(pts - gtotal));
  return _story_save(uid, d);
end $$;

-- 기존 기록 전부 지금 환급 (다음 접속 때 안내 팝업이 뜸)
update story_progress set data = public._story_refund_stats(public._story_migrate(data)) where coalesce((data->>'statV')::int, 1) < 2;

-- ===== 스토리 특수 뽑기 (소환권) — Supabase SQL Editor 에서 실행. 여러 번 실행해도 안전 =====
-- 소환권: 챕터를 처음 다 깨면 +10 (지금까지 다 깬 챕터도 챕터마다 한 번씩 +10, 다시 주지 않음)
--   보관: story_gacha.tickets / ticket_chapters(이미 소환권을 준 챕터 번호)
--   지급 확인은 story_tickets() / story_ticket_draw() 를 부를 때 서버에서 함 (story_progress.cleared 와 story_phase_config 비교)
-- 특수 뽑기 확률: N 50% · R 30% · HR 16% · SR 3.2% · UR 0.8% · 10회 뽑기는 HR 이상 1장 보장
-- 추첨·차감은 전부 서버에서 (security definer). 클라이언트는 결과만 받음

alter table public.story_gacha add column if not exists tickets int not null default 0 check (tickets >= 0);
alter table public.story_gacha add column if not exists ticket_chapters int[] not null default '{}';
alter table public.story_gacha_log add column if not exists kind text not null default 'daily';

-- 챕터 첫 클리어 소환권 지급 (행 잠금). 반환 { tickets, added, chapters }
create or replace function public._story_ticket_sync(uid uuid) returns jsonb language plpgsql set search_path = public as $$
declare d jsonb; ch int; got int[]; t int; added int := 0; newch int[] := '{}';
begin
  if uid is null then raise exception 'login required'; end if;
  insert into story_gacha (user_id, last_draw) values (uid, (now() at time zone 'Asia/Seoul')::date - 1) on conflict (user_id) do nothing;
  select tickets, ticket_chapters into t, got from story_gacha where user_id = uid for update;
  select data into d from story_progress where user_id = uid;
  for ch in
    select c.chapter from story_phase_config c group by c.chapter
    having bool_and(case when jsonb_typeof(d->'cleared'->(c.chapter::text)) = 'array'
                         then (d->'cleared'->(c.chapter::text)) @> to_jsonb(c.phase) or (d->'cleared'->(c.chapter::text)) @> to_jsonb(c.phase::text) else false end)
    order by c.chapter
  loop
    if not (ch = any(got)) then got := got || ch; newch := newch || ch; added := added + 10; end if;
  end loop;
  if added > 0 then update story_gacha set tickets = tickets + added, ticket_chapters = got, updated_at = now() where user_id = uid; t := t + added; end if;
  return jsonb_build_object('tickets', t, 'added', added, 'chapters', to_jsonb(newch));
end $$;
revoke all on function public._story_ticket_sync(uuid) from public, anon, authenticated;

-- 소환권 개수 (+ 새로 받은 소환권). 반환 { tickets, added, chapters }
create or replace function public.story_tickets() returns jsonb language plpgsql security definer set search_path = public as $$
begin
  return _story_ticket_sync(auth.uid());
end $$;
revoke all on function public.story_tickets() from public, anon;
grant execute on function public.story_tickets() to authenticated;

-- 특수 뽑기: p_count = 1 또는 10. 반환 { ok, cards: [{card_id, uid, grade}], tickets, added } / 소환권 부족 { ok:false, reason:'tickets', tickets }
create or replace function public.story_ticket_draw(p_count int) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); s jsonb; t int; r double precision; g text; cid text; d jsonb; owned jsonb; e jsonb; out jsonb := '[]'::jsonb; i int; hr boolean := false;
begin
  if uid is null then raise exception 'login required'; end if;
  if p_count is null or p_count not in (1, 10) then raise exception 'invalid count'; end if;
  s := _story_ticket_sync(uid);   -- story_gacha 행 잠금 포함
  t := (s->>'tickets')::int;
  if t < p_count then return jsonb_build_object('ok', false, 'reason', 'tickets', 'tickets', t, 'added', (s->>'added')::int); end if;
  d := _story_lock(uid);
  owned := _story_owned(d);
  for i in 1..p_count loop
    r := random();
    if p_count = 10 and i = 10 and not hr then   -- 10회 보장: 앞 9장이 모두 R 이하면 마지막 장은 HR 이상 (HR:SR:UR = 16:3.2:0.8)
      r := 0.80 + random() * 0.20;
    end if;
    g := case when r < 0.50 then 'NORMAL' when r < 0.80 then 'RARE' when r < 0.96 then 'HIGH RARE' when r < 0.992 then 'SUPER RARE' else 'ULTRA RARE' end;
    if g in ('HIGH RARE', 'SUPER RARE', 'ULTRA RARE') then hr := true; end if;
    select id into cid from story_card_pool where grade = g and coalesce(gacha, true) order by random() limit 1;
    if cid is null then raise exception 'empty pool for %', g; end if;
    e := _story_new_card(cid);
    owned := owned || jsonb_build_array(e);
    out := out || jsonb_build_array(jsonb_build_object('card_id', cid, 'uid', e->>'uid', 'grade', g));
    insert into story_gacha_log (user_id, card_id, grade, kind) values (uid, cid, g, 'ticket');
  end loop;
  d := _story_save(uid, jsonb_set(d, '{owned}', owned));
  update story_gacha set tickets = tickets - p_count, updated_at = now() where user_id = uid;
  return jsonb_build_object('ok', true, 'cards', out, 'tickets', t - p_count, 'added', (s->>'added')::int);
end $$;
revoke all on function public.story_ticket_draw(int) from public, anon;
grant execute on function public.story_ticket_draw(int) to authenticated;

-- ===== 스토리 리더 변경 + 분해 잠금 (supabase/story_leader_lock.sql 과 동일) =====
-- SQL Editor 에서 그대로 실행 (여러 번 실행해도 안전). service_role 필요 없음.
-- 저장 형식: data.owned[i].locked = true (잠금), data.leader = 리더 인스턴스 uid (리더는 항상 잠금 취급, 따로 저장 안 함)
-- 리더 스킬 효과와 리더 쓰러짐 패널티는 전투(클라이언트) 계산이라 SQL 없음.

-- 1) 분해 잠금 켜기/끄기: p_uid = 인스턴스 uid, p_on = true(잠금) / false(해제)
create or replace function public.story_set_lock(p_uid text, p_on boolean) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb; owned jsonb; i int; e jsonb;
begin
  d := _story_lock(uid);
  owned := _story_owned(d);
  select (n - 1)::int into i from jsonb_array_elements(owned) with ordinality x(e, n) where x.e->>'uid' = p_uid;
  if i is null then raise exception 'card not owned'; end if;
  e := owned->i;
  e := case when coalesce(p_on, false) then e || jsonb_build_object('locked', true) else e - 'locked' end;
  owned := jsonb_set(owned, array[i::text], e);
  d := _story_save(uid, jsonb_set(d, '{owned}', owned));
  return jsonb_build_object('data', d, 'uid', p_uid, 'locked', coalesce(p_on, false));
end $$;
revoke all on function public.story_set_lock(text, boolean) from public, anon;
grant execute on function public.story_set_lock(text, boolean) to authenticated;

-- 2) 리더 변경: 챕터 1의 모든 페이즈를 클리어해야 가능. 내가 가진 카드(인스턴스 uid)만. 시작 캐릭터(data.starter)·루트는 그대로
create or replace function public.story_set_leader(p_uid text) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb; owned jsonb; tot int; got int; prev text;
begin
  d := _story_lock(uid);
  owned := _story_owned(d);
  if coalesce(p_uid, '') = '' or p_uid like 'guest:%' or not exists (select 1 from jsonb_array_elements(owned) x where x->>'uid' = p_uid) then raise exception 'card not owned'; end if;
  select count(*) into tot from story_phase_config where chapter = 1;
  select count(*) into got from story_phase_config c
    where c.chapter = 1 and coalesce(case when jsonb_typeof(d->'cleared'->'1') = 'array' then d->'cleared'->'1' end, '[]'::jsonb) @> to_jsonb(c.phase);
  if tot = 0 or got < tot then raise exception 'chapter 1 not cleared'; end if;
  prev := d->>'leader';
  d := _story_save(uid, jsonb_set(d, '{leader}', to_jsonb(p_uid)));
  return jsonb_build_object('data', d, 'leader', p_uid, 'prev', prev);
end $$;
revoke all on function public.story_set_leader(text) from public, anon;
grant execute on function public.story_set_leader(text) to authenticated;

-- 3) 일괄 분해: 잠긴 카드·리더·대상은 분해 불가 (나머지는 story_merge.sql 판과 같음)
create or replace function public.story_discard_many(p_ids text[], p_target text) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb; owned jsonb; pid text; i1 int; i2 int; e1 jsonb; g1 text; n1 text; g2 text; n2 text; tuid text; lead text;
        amt int; total int := 0; refund int := 0; n int := 0; before int; t jsonb; gone text[] := '{}'; u1 text;
begin
  if p_ids is null or cardinality(p_ids) = 0 then raise exception 'nothing to discard'; end if;
  if cardinality(p_ids) > 200 then raise exception 'too many cards'; end if;
  d := _story_lock(uid);
  owned := _story_owned(d); lead := d->>'leader';
  i2 := _story_find(owned, p_target);
  if i2 is null then raise exception 'card not owned'; end if;
  tuid := owned->i2->>'uid';
  select grade, name into g2, n2 from story_card_pool where id = owned->i2->>'id';
  foreach pid in array p_ids loop
    -- 예전 클라이언트(카드 id): 아직 고르지 않은 그 카드의 인스턴스 중 대상·리더·잠금이 아닌 첫 장
    select x.e->>'uid' into u1 from jsonb_array_elements(owned) with ordinality x(e, k)
      where (x.e->>'uid' = pid or (x.e->>'id' = pid and not exists (select 1 from jsonb_array_elements(owned) y where y->>'uid' = pid)))
        and not (x.e->>'uid' = any(gone))
        and (x.e->>'uid' = pid or (x.e->>'uid' <> tuid and x.e->>'uid' is distinct from lead and coalesce((x.e->>'locked')::boolean, false) = false))
      order by k limit 1;
    if u1 is null then raise exception 'card not owned'; end if;
    if u1 = tuid then raise exception 'cannot discard target'; end if;
    if u1 = lead then raise exception 'cannot discard leader'; end if;
    select x.e into e1 from jsonb_array_elements(owned) x(e) where x.e->>'uid' = u1;
    if coalesce((e1->>'locked')::boolean, false) then raise exception 'card locked'; end if;
    gone := gone || u1;
    e1 := _story_norm(e1);
    select grade, name into g1, n1 from story_card_pool where id = e1->>'id';
    amt := _story_feed_exp(coalesce(g1, 'NORMAL'));
    if n1 is not null and n1 = n2 then amt := floor(amt * 1.5); end if;
    amt := amt + floor((e1->>'totalExp')::int * 0.5);
    refund := refund + greatest(0, coalesce((e1->'boost'->>'ATK')::int,0) + coalesce((e1->'boost'->>'HP')::int,0) + coalesce((e1->'boost'->>'DEF')::int,0) - (e1->>'spentCard')::int);
    total := total + amt; n := n + 1;
  end loop;
  select coalesce(jsonb_agg(x.e order by k), '[]'::jsonb) into owned from jsonb_array_elements(owned) with ordinality x(e, k) where not (x.e->>'uid' = any(gone));
  i2 := _story_find(owned, tuid);
  before := coalesce((owned->i2->>'level')::int, 1);
  t := _story_gain(owned->i2, total, coalesce(g2, 'NORMAL'));
  owned := jsonb_set(owned, array[i2::text], t);
  d := jsonb_set(d, '{owned}', owned);
  if refund > 0 then d := jsonb_set(d, '{points}', to_jsonb(coalesce((d->>'points')::int, 0) + refund)); end if;
  d := _story_save(uid, d);
  return jsonb_build_object('data', d, 'count', n, 'exp', total, 'from', before, 'level', (t->>'level')::int, 'refund', refund);
end $$;
revoke all on function public.story_discard_many(text[], text) from public, anon;
grant execute on function public.story_discard_many(text[], text) to authenticated;
-- (1장 분해 story_discard 는 story_discard_many 를 부르므로 그대로 잠금 검사가 적용됨)

-- 4) EX 합성: 잠긴 카드·리더는 재료로 못 씀 (나머지는 story_merge.sql 판과 같음)
create or replace function public.story_merge(p_target text, p_material text) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb; owned jsonb; it int; im int; et jsonb; em jsonb; g text; ex int; lt int; ct int; lm int; cm int; bonus numeric; exb numeric;
begin
  d := _story_lock(uid);
  owned := _story_owned(d);
  select (n - 1)::int into it from jsonb_array_elements(owned) with ordinality x(e, n) where x.e->>'uid' = p_target;
  select (n - 1)::int into im from jsonb_array_elements(owned) with ordinality x(e, n) where x.e->>'uid' = p_material;
  if it is null or im is null then raise exception 'card not owned'; end if;
  if it = im then raise exception 'material is target'; end if;
  et := _story_norm(owned->it); em := _story_norm(owned->im);
  if et->>'id' <> em->>'id' then raise exception 'material must be same card'; end if;
  if em->>'uid' = coalesce(d->>'leader', '') then raise exception 'cannot use leader as material'; end if;
  if coalesce((em->>'locked')::boolean, false) then raise exception 'card locked'; end if;
  select grade into g from story_card_pool where id = et->>'id';
  g := coalesce(g, 'NORMAL');
  ex := (et->>'ex')::int;
  if ex >= _story_max_ex(g) then raise exception 'max ex'; end if;
  lt := (et->>'level')::int; ct := _story_cap(g, ex);
  lm := (em->>'level')::int; cm := _story_cap(g, (em->>'ex')::int);
  bonus := round(10 * least(1, lt::numeric / ct) * least(1, lm::numeric / cm), 2);
  exb := round((et->>'exb')::numeric + bonus, 2);
  et := et || jsonb_build_object('ex', ex + 1, 'exb', exb, 'level', 1, 'exp', 0);
  owned := jsonb_set(owned, array[it::text], et);
  owned := owned - im;
  d := _story_save(uid, jsonb_set(d, '{owned}', owned));
  return jsonb_build_object('data', d, 'ex', ex + 1, 'bonus', bonus, 'exb', exb, 'target_level', lt, 'target_cap', ct, 'material_level', lm, 'material_cap', cm, 'cap_to', _story_cap(g, ex + 1));
end $$;
revoke all on function public.story_merge(text, text) from public, anon;
grant execute on function public.story_merge(text, text) to authenticated;
