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
  select uid, x, 1, (x = p_mvp)::int, now(), now() from unnest(ids) x
  on conflict (user_id, card_id) do update
    set count = g.count + 1, mvp_count = g.mvp_count + excluded.mvp_count, last_at = now()
  returning g.card_id, g.count, g.mvp_count, (g.count = 1);
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
  ('1000100007','SUPER RARE'),
  ('1000100009','RARE'),
  ('1000100010','RARE'),
  ('1000100011','HIGH RARE'),
  ('1000100012','NORMAL'),
  ('1000100013','NORMAL'),
  ('1000100014','NORMAL'),
  ('1000100016','NORMAL'),
  ('1000200018','ULTRA RARE'),
  ('1000200020','NORMAL'),
  ('1000200021','NORMAL'),
  ('1000200022','NORMAL'),
  ('1000200024','SUPER RARE'),
  ('1000200032','NORMAL'),
  ('1000200033','NORMAL'),
  ('1000200034','NORMAL'),
  ('1000200035','HIGH RARE'),
  ('1000200036','HIGH RARE'),
  ('1000200037','RARE'),
  ('1000200038','HIGH RARE'),
  ('1000200039','RARE'),
  ('1000200040','NORMAL'),
  ('1000200041','RARE'),
  ('1000200042','NORMAL'),
  ('1000200043','RARE'),
  ('1000200046','NORMAL'),
  ('1000200047','NORMAL'),
  ('1000200048','NORMAL'),
  ('1000200049','NORMAL'),
  ('1000200050','NORMAL'),
  ('1000200052','NORMAL'),
  ('1000300054','NORMAL'),
  ('1000300056','SUPER RARE'),
  ('1000300057','NORMAL'),
  ('1000300058','NORMAL'),
  ('1000300059','NORMAL'),
  ('1000300060','RARE'),
  ('1000300061','NORMAL'),
  ('1000300062','NORMAL'),
  ('1000300063','NORMAL'),
  ('1000300064','NORMAL'),
  ('1000300065','NORMAL'),
  ('1000300067','RARE'),
  ('1000300070','RARE'),
  ('1000300071','NORMAL'),
  ('1000300072','NORMAL'),
  ('1000300073','RARE'),
  ('1000300074','NORMAL'),
  ('1000300075','NORMAL'),
  ('1000300076','NORMAL'),
  ('1000300077','NORMAL'),
  ('1000300078','NORMAL'),
  ('1000300079','NORMAL'),
  ('1000400090','HIGH RARE'),
  ('1000400091','NORMAL'),
  ('1000400092','SUPER RARE'),
  ('1000400093','NORMAL'),
  ('1000400100','RARE'),
  ('1000400101','HIGH RARE'),
  ('1000400102','NORMAL'),
  ('1000400103','NORMAL'),
  ('1000500107','HIGH RARE'),
  ('1000500108','NORMAL'),
  ('1000500109','SUPER RARE'),
  ('1000500112','RARE'),
  ('1000500113','RARE'),
  ('1000600119','RARE'),
  ('1000600120','HIGH RARE'),
  ('1000600121','NORMAL'),
  ('1000600122','HIGH RARE'),
  ('1000600124','NORMAL'),
  ('1000600125','SUPER RARE'),
  ('1000600127','HIGH RARE'),
  ('1000600130','SUPER RARE'),
  ('2000600131','RARE'),
  ('1000600133','NORMAL'),
  ('1000700137','NORMAL'),
  ('1000800169','NORMAL'),
  ('1000800177','RARE'),
  ('1000800178','RARE'),
  ('1000800180','HIGH RARE'),
  ('1000800182','NORMAL'),
  ('1000800189','RARE'),
  ('1000800192','NORMAL'),
  ('1001000212','NORMAL'),
  ('1001000213','SUPER RARE'),
  ('1001000214','NORMAL'),
  ('1001100218','RARE'),
  ('1001100219','RARE'),
  ('1001100227','RARE'),
  ('1001100228','RARE'),
  ('1001100236','HIGH RARE'),
  ('1001100240','NORMAL'),
  ('1001400245','HIGH RARE'),
  ('1001400250','NORMAL'),
  ('1001400252','HIGH RARE'),
  ('1001400255','NORMAL'),
  ('1001400256','NORMAL'),
  ('1001400258','NORMAL'),
  ('1001400266','RARE'),
  ('1001400268','NORMAL'),
  ('1001400271','HIGH RARE'),
  ('1001400272','NORMAL'),
  ('1001400273','RARE'),
  ('1001400274','RARE'),
  ('1001500280','NORMAL'),
  ('1001500283','RARE'),
  ('1001500285','RARE'),
  ('1001500286','HIGH RARE'),
  ('1001500287','NORMAL'),
  ('1001500288','NORMAL'),
  ('1001500289','NORMAL'),
  ('1001500290','HIGH RARE'),
  ('1001500293','HIGH RARE'),
  ('1001500295','NORMAL'),
  ('1001500296','NORMAL'),
  ('1001500298','RARE'),
  ('1001500299','NORMAL'),
  ('1001500300','NORMAL'),
  ('1001500301','NORMAL'),
  ('1001500302','NORMAL'),
  ('1001500303','RARE'),
  ('1001500304','NORMAL'),
  ('1001500305','SUPER RARE'),
  ('1001500306','HIGH RARE'),
  ('1001500307','HIGH RARE'),
  ('1001500310','NORMAL'),
  ('1001500311','SUPER RARE'),
  ('1001500313','SUPER RARE'),
  ('1001500315','ULTRA RARE'),
  ('1001600318','RARE'),
  ('1001600319','NORMAL'),
  ('1001600320','RARE'),
  ('1001600322','NORMAL'),
  ('1001600323','RARE'),
  ('1001600324','SUPER RARE'),
  ('1001600325','NORMAL'),
  ('1001600326','HIGH RARE'),
  ('1001600327','RARE'),
  ('1001600328','RARE'),
  ('1001600329','RARE'),
  ('1001600330','RARE'),
  ('1001700331','NORMAL'),
  ('1001700332','RARE'),
  ('1001700333','RARE'),
  ('1001700336','NORMAL'),
  ('1001700337','NORMAL'),
  ('1001700338','NORMAL'),
  ('1001700340','NORMAL'),
  ('1001800344','RARE'),
  ('1001900346','RARE'),
  ('1001900348','NORMAL'),
  ('1001900349','NORMAL'),
  ('1001900351','NORMAL'),
  ('1002000355','SUPER RARE'),
  ('1002100356','NORMAL'),
  ('1002100357','NORMAL'),
  ('1002100358','NORMAL'),
  ('1002100359','NORMAL'),
  ('1002100360','NORMAL'),
  ('1002100361','NORMAL'),
  ('1002100363','NORMAL'),
  ('1002100364','HIGH RARE'),
  ('1002100366','SUPER RARE'),
  ('1002100367','NORMAL'),
  ('1002100368','NORMAL'),
  ('1002100369','NORMAL'),
  ('1002100370','HIGH RARE'),
  ('1002100371','ULTRA RARE'),
  ('1002200372','ULTRA RARE'),
  ('1002400375','SUPER RARE'),
  ('1002400376','RARE'),
  ('1002400377','HIGH RARE'),
  ('1002400378','ULTRA RARE'),
  ('1002400380','NORMAL'),
  ('1002400381','NORMAL'),
  ('1002400384','NORMAL'),
  ('2000100001','ULTRA RARE'),
  ('2000100002','NORMAL'),
  ('2000100003','RARE'),
  ('2000100004','RARE'),
  ('2000100005','HIGH RARE'),
  ('2000100006','RARE'),
  ('2000100008','RARE'),
  ('2000100015','NORMAL'),
  ('2000100017','NORMAL'),
  ('2000200019','HIGH RARE'),
  ('2000200023','HIGH RARE'),
  ('2000200025','HIGH RARE'),
  ('2000200026','RARE'),
  ('2000200027','HIGH RARE'),
  ('2000200028','RARE'),
  ('2000200029','NORMAL'),
  ('2000200031','RARE'),
  ('2000200044','RARE'),
  ('2000200045','RARE'),
  ('2000200051','NORMAL'),
  ('2000200053','RARE'),
  ('2000300055','NORMAL'),
  ('2000300066','NORMAL'),
  ('2000300068','NORMAL'),
  ('2000300069','NORMAL'),
  ('2000300080','HIGH RARE'),
  ('2000300081','HIGH RARE'),
  ('2000300082','SUPER RARE'),
  ('2000300083','ULTRA RARE'),
  ('2000400084','NORMAL'),
  ('2000400085','NORMAL'),
  ('2000400086','HIGH RARE'),
  ('2000400087','HIGH RARE'),
  ('2000400088','SUPER RARE'),
  ('2000400089','HIGH RARE'),
  ('2000400094','SUPER RARE'),
  ('2000400095','NORMAL'),
  ('2000400096','RARE'),
  ('2000400097','SUPER RARE'),
  ('2000400098','SUPER RARE'),
  ('2000400099','RARE'),
  ('2000400104','NORMAL'),
  ('2000400105','NORMAL'),
  ('2000400106','RARE'),
  ('2000500110','RARE'),
  ('2000500111','RARE'),
  ('2000500114','SUPER RARE'),
  ('2000600115','HIGH RARE'),
  ('2000600116','HIGH RARE'),
  ('2000600117','RARE'),
  ('2000600118','NORMAL'),
  ('2000600123','NORMAL'),
  ('2000600126','RARE'),
  ('2000600128','RARE'),
  ('2000600129','NORMAL'),
  ('2000600132','RARE'),
  ('2000600134','RARE'),
  ('2000600135','HIGH RARE'),
  ('2000600136','NORMAL'),
  ('2000700138','NORMAL'),
  ('2000700139','RARE'),
  ('2000700140','HIGH RARE'),
  ('2000700141','NORMAL'),
  ('2000700142','NORMAL'),
  ('2000700143','NORMAL'),
  ('2000700144','NORMAL'),
  ('2000700145','NORMAL'),
  ('2000700146','SUPER RARE'),
  ('2000700147','NORMAL'),
  ('2000700148','NORMAL'),
  ('2000700149','RARE'),
  ('2000700150','RARE'),
  ('2000700151','RARE'),
  ('2000700152','RARE'),
  ('2000700153','RARE'),
  ('2000700154','RARE'),
  ('2000700155','NORMAL'),
  ('2000700156','NORMAL'),
  ('2000700157','NORMAL'),
  ('2000700158','NORMAL'),
  ('2000700159','NORMAL'),
  ('2000700160','RARE'),
  ('2000700161','RARE'),
  ('2000700162','HIGH RARE'),
  ('2000700163','NORMAL'),
  ('2000700164','NORMAL'),
  ('2000700165','ULTRA RARE'),
  ('2000700166','HIGH RARE'),
  ('2000800167','NORMAL'),
  ('2000800168','NORMAL'),
  ('2000800170','NORMAL'),
  ('2000800171','NORMAL'),
  ('2000800172','NORMAL'),
  ('2000800173','NORMAL'),
  ('2000800174','NORMAL'),
  ('2000800175','NORMAL'),
  ('2000800176','RARE'),
  ('2000800179','SUPER RARE'),
  ('2000800181','HIGH RARE'),
  ('2000800183','RARE'),
  ('2000800184','RARE'),
  ('2000800185','HIGH RARE'),
  ('2000800186','SUPER RARE'),
  ('2000800187','RARE'),
  ('2000800188','RARE'),
  ('2000800190','RARE'),
  ('2000800191','RARE'),
  ('2000800193','NORMAL'),
  ('2000800194','NORMAL'),
  ('2000800195','NORMAL'),
  ('2000800196','RARE'),
  ('2000800197','ULTRA RARE'),
  ('2000900198','HIGH RARE'),
  ('2000900199','RARE'),
  ('2000900200','NORMAL'),
  ('2000900201','NORMAL'),
  ('2000900202','NORMAL'),
  ('2000900203','NORMAL'),
  ('2000900204','RARE'),
  ('2000900205','RARE'),
  ('2000900206','HIGH RARE'),
  ('2000900207','HIGH RARE'),
  ('2000900208','NORMAL'),
  ('2000900209','NORMAL'),
  ('2000900210','NORMAL'),
  ('2000900211','NORMAL'),
  ('2000900212','RARE'),
  ('2000900213','NORMAL'),
  ('2000900214','HIGH RARE'),
  ('2000900215','SUPER RARE'),
  ('2000900216','RARE'),
  ('2000900217','RARE'),
  ('2000900218','RARE'),
  ('2000900219','RARE'),
  ('2000900220','NORMAL'),
  ('2000900221','NORMAL'),
  ('2000900222','NORMAL'),
  ('2000900223','NORMAL'),
  ('2000900224','NORMAL'),
  ('2000900225','SUPER RARE'),
  ('2000900226','NORMAL'),
  ('2000900227','NORMAL'),
  ('2000900228','NORMAL'),
  ('2000900229','RARE'),
  ('2000900230','NORMAL'),
  ('2000900231','RARE'),
  ('2000900232','RARE'),
  ('2000900233','HIGH RARE'),
  ('2000900235','HIGH RARE'),
  ('2000900236','RARE'),
  ('2001100215','NORMAL'),
  ('2001100216','NORMAL'),
  ('2001100217','NORMAL'),
  ('2001100220','NORMAL'),
  ('2001100221','NORMAL'),
  ('2001100222','NORMAL'),
  ('2001100223','NORMAL'),
  ('2001100224','NORMAL'),
  ('2001100225','NORMAL'),
  ('2001100226','NORMAL'),
  ('2001100229','RARE'),
  ('2001100230','SUPER RARE'),
  ('2001100231','NORMAL'),
  ('2001100232','HIGH RARE'),
  ('2001100233','SUPER RARE'),
  ('2001100234','NORMAL'),
  ('2001100235','SUPER RARE'),
  ('2001100237','HIGH RARE'),
  ('2001100238','NORMAL'),
  ('2001100239','NORMAL'),
  ('2001100241','SUPER RARE'),
  ('2001100242','SUPER RARE'),
  ('2001100243','ULTRA RARE'),
  ('2001200244','NORMAL'),
  ('2001400246','SUPER RARE'),
  ('2001400247','HIGH RARE'),
  ('2001400248','ULTRA RARE'),
  ('2001400249','NORMAL'),
  ('2001400251','NORMAL'),
  ('2001400253','RARE'),
  ('2001400254','RARE'),
  ('2001400257','NORMAL'),
  ('2001400259','NORMAL'),
  ('2001400260','NORMAL'),
  ('2001400261','HIGH RARE'),
  ('2001400262','NORMAL'),
  ('2001400263','SUPER RARE'),
  ('2001400264','HIGH RARE'),
  ('2001400265','HIGH RARE'),
  ('2001400267','RARE'),
  ('2001400269','NORMAL'),
  ('2001400270','HIGH RARE'),
  ('2001400275','NORMAL'),
  ('2001400276','RARE'),
  ('2001400277','RARE'),
  ('2001400278','NORMAL'),
  ('2001400279','SUPER RARE'),
  ('2001500281','NORMAL'),
  ('2001500282','RARE'),
  ('2001500284','NORMAL'),
  ('2001500291','NORMAL'),
  ('2001500292','HIGH RARE'),
  ('2001500294','RARE'),
  ('2001500297','NORMAL'),
  ('2001500308','HIGH RARE'),
  ('2001500309','NORMAL'),
  ('2001500312','RARE'),
  ('2001500314','SUPER RARE'),
  ('2001600317','RARE'),
  ('2001600321','RARE'),
  ('2001700334','NORMAL'),
  ('2001700335','NORMAL'),
  ('2001700339','NORMAL'),
  ('2001700341','NORMAL'),
  ('2001700342','ULTRA RARE'),
  ('2001800343','NORMAL'),
  ('2001800345','HIGH RARE'),
  ('2001900347','SUPER RARE'),
  ('2001900350','NORMAL'),
  ('2002000352','HIGH RARE'),
  ('2002000353','HIGH RARE'),
  ('2002000354','NORMAL'),
  ('2002100362','NORMAL'),
  ('2002100365','NORMAL'),
  ('2002300373','NORMAL'),
  ('2002400374','SUPER RARE'),
  ('2002400379','NORMAL'),
  ('2002400382','NORMAL'),
  ('2002400383','NORMAL'),
  ('2000000001','ULTRA RARE'),
  ('2000000002','NORMAL'),
  ('2000000003','SUPER RARE'),
  ('2000000004','RARE'),
  ('2000000005','RARE'),
  ('2000000006','HIGH RARE'),
  ('2000000007','ULTRA RARE'),
  ('2000000009','HIGH RARE'),
  ('2000000010','NORMAL'),
  ('2000000011','RARE'),
  ('2000000012','HIGH RARE'),
  ('1000000001','RARE'),
  ('1000000002','RARE'),
  ('1000000003','SUPER RARE'),
  ('1000000004','ULTRA RARE'),
  ('1000000005','NORMAL'),
  ('1000000006','NORMAL'),
  ('1000000007','NORMAL'),
  ('1000000008','NORMAL'),
  ('1000000009','NORMAL')
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
