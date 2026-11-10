-- ⚠ 테스트 전용 2/14. 운영 실행 금지. 파일 전체를 번호 순서대로 실행.
-- 대상 프로젝트: cuyqchmdcnsgzkwyclji; 운영 htarwisgkkphutxxnuak 금지.
-- 완료한 파일은 다시 실행해도 건너뜀. 중간 오류는 해당 파일만 되돌아감.
-- 실제 project_ref는 SQL Editor가 보장해서 제공하지 않음: DB 고유번호를 대조.
-- 지정 테스트 DB의 식별번호와 일치할 때만 허용. guard 삭제/SET 우회 금지.
-- docs/STAGING.md 및 supabase/staging/README.md 먼저 확인.

begin;
do $vr_project_guard$
declare
  confirmed_ref text := 'cuyqchmdcnsgzkwyclji';
  expected_db_id text := '7703759698107299042';
  actual_db_id text;
begin
  if confirmed_ref is distinct from 'cuyqchmdcnsgzkwyclji' or confirmed_ref = 'htarwisgkkphutxxnuak' then
    raise exception 'STOP: 지정한 테스트 프로젝트만 허용합니다. 운영 DB 금지.';
  end if;
  if expected_db_id !~ '^[0-9]{16,20}$' then
    raise exception 'STOP: 테스트 DB의 실제 고유번호가 아직 등록되지 않았습니다. 안내 문서를 확인하세요.';
  end if;
  select system_identifier::text into actual_db_id from pg_catalog.pg_control_system();
  if actual_db_id is distinct from expected_db_id then
    raise exception 'STOP: 현재 접속한 DB가 지정된 테스트 DB와 다릅니다. 실행 금지.';
  end if;
exception when insufficient_privilege or undefined_function then
  raise exception 'STOP: DB 식별 조회 권한/기능이 없어 안전하게 중단합니다. guard를 삭제하지 마세요.';
end $vr_project_guard$;

-- 설치 기록은 API에서 접근할 수 없는 별도 스키마에 저장.
select pg_advisory_xact_lock(20261107, 490);
create schema if not exists vr_staging_install;
revoke all on schema vr_staging_install from public, anon, authenticated;
create table if not exists vr_staging_install.parts (
  part_no integer primary key, bundle_hash text not null, part_hash text not null,
  project_ref text not null, db_id text not null, applied_at timestamptz not null default now()
);
alter table vr_staging_install.parts enable row level security;
revoke all on vr_staging_install.parts from public, anon, authenticated;
set local check_function_bodies = off;

do $vr_install_part$
begin
  if exists (select 1 from vr_staging_install.parts where bundle_hash <> '54d6625d06876bdcfb94a46163f92d8c3802d76c35bbddb31221004f89548d48' or project_ref <> 'cuyqchmdcnsgzkwyclji' or db_id <> '7703759698107299042') then
    raise exception 'STOP: 다른 버전/DB의 설치 기록입니다. 파일을 섞지 마세요.';
  end if;
  if exists (select 1 from vr_staging_install.parts where part_no = 2) then
    if not exists (select 1 from vr_staging_install.parts where part_no = 2 and part_hash = 'b2e3e0fc765b0a028e5ce9d64cb1bf5cd0e4ffef54946e0f5f6ed75fea633c6e') then
      raise exception 'STOP: 완료한 파일과 내용이 다릅니다.';
    end if;
    raise notice '02_install.sql: 이미 완료, 변경 없이 건너뜀';
    return;
  end if;
  if (select count(*) from vr_staging_install.parts where part_no < 2) <> 1 then
    raise exception 'STOP: 앞 번호 파일을 먼저 실행하세요 (02_install.sql).';
  end if;
  -- 설치 도중에는 클라이언트가 미완성 게임 스키마에 접근하지 못함. 마지막에만 개방.
  revoke usage on schema public from public, anon, authenticated;
  execute $vr_statement$-- ===== SOURCE: story_cards_1022.sql =====
-- =====================================================================
-- VR: Abyss Gate - 신규 카드 반영 (2026-10-22)
-- 10127~17 신규 5장 (하지혜 = 10440 UR), 황예영(10465) NORMAL → SUPER RARE
-- 10452(허유희)는 건드리지 않음.
-- 사용법: SQL Editor에 붙여넣고 Run. 여러 번 실행해도 안전.
-- =====================================================================
insert into public.story_card_pool (id, grade, name, gacha) values
  ('10127','SUPER RARE','박인영',true),
  ('10439','SUPER RARE','하지은',true),
  ('10355','NORMAL','정미선',true),
  ('10367','RARE','정지선',true),
  ('10440','ULTRA RARE','하지혜',true)
on conflict (id) do update set grade = excluded.grade, name = excluded.name, gacha = excluded.gacha;$vr_statement$;
  execute $vr_statement$update public.story_card_pool set grade = 'SUPER RARE' where id = '10465';$vr_statement$;
  execute $vr_statement$-- 확인용: 6행 (13~17 + 10465 SUPER RARE)
select id, grade, name, gacha from public.story_card_pool
 where id between '10127' and '10440' or id = '10465' order by id;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: admin.sql =====
-- =====================================================================
-- 관리자 페이지 (admin.html) 용 RPC — Supabase SQL Editor 에서 실행. 여러 번 실행해도 안전
-- 관리자: stevejean77@gmail.com 한 명. 판정은 전부 서버에서 (security definer 함수 안에서 매번 확인)
--   1) 호출자 JWT 의 email = 관리자 이메일
--   2) auth.users 에서 auth.uid() 의 email 도 같고, 이메일 인증(email_confirmed_at)이 끝났어야 함
--   둘 중 하나라도 아니면 'forbidden' 예외. anon(비로그인) 에게는 실행 권한 자체가 없음
-- 클라이언트는 anon 키 + 본인 세션만 사용. service_role 키는 쓰지 않음
-- 확인용: select public.admin_check();  → 관리자 { admin:true, email } / 그 외 { admin:false }
-- =====================================================================

-- 관리자 작업 기록 (소환권 지급 등). 클라이언트에서 직접 읽기/쓰기 불가 (정책 없음 + 권한 회수)
create table if not exists public.admin_log (
  id          bigint generated always as identity primary key,
  admin_id    uuid not null,
  admin_email text not null,
  action      text not null check (char_length(action) <= 40),
  target_user uuid references auth.users(id) on delete set null,
  amount      int,
  reason      text check (char_length(reason) <= 200),
  before_val  int,
  after_val   int,
  created_at  timestamptz not null default now()
);$vr_statement$;
  execute $vr_statement$create index if not exists admin_log_created_idx on public.admin_log (created_at desc);$vr_statement$;
  execute $vr_statement$alter table public.admin_log enable row level security;$vr_statement$;
  execute $vr_statement$revoke all on public.admin_log from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$-- 관리자 판정 (내부용, 직접 호출 불가)
create or replace function public._is_admin() returns boolean language sql stable security definer set search_path = public, auth as $$
  select auth.uid() is not null
     and lower(coalesce(auth.jwt()->>'email', '')) = 'stevejean77@gmail.com'
     and exists (select 1 from auth.users u
                  where u.id = auth.uid()
                    and lower(u.email) = 'stevejean77@gmail.com'
                    and u.email_confirmed_at is not null)
$$;$vr_statement$;
  execute $vr_statement$revoke all on function public._is_admin() from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$create or replace function public._admin_guard() returns void language plpgsql security definer set search_path = public, auth as $$
begin
  if not public._is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._admin_guard() from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$-- 0) 확인용 (관리자 아니면 false. 예외 없음) — 새 RPC 확인은 이걸로
create or replace function public.admin_check() returns jsonb language plpgsql security definer set search_path = public, auth as $$
begin
  if public._is_admin() then return jsonb_build_object('admin', true, 'email', auth.jwt()->>'email'); end if;
  return jsonb_build_object('admin', false);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.admin_check() from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.admin_check() to authenticated;$vr_statement$;
  execute $vr_statement$-- 1) 가입 유저 목록 (구글 로그인: 이메일, 이름, 가입/마지막 로그인) + 소환권·카드 수·아케이드 전적
create or replace function public.admin_list_users(p_search text default null, p_limit int default 100, p_offset int default 0)
returns table (id uuid, email text, name text, provider text, created_at timestamptz, last_sign_in_at timestamptz,
               nickname text, tickets int, cards int, wins int, losses int, draws int)
language plpgsql stable security definer set search_path = public, auth as $$
begin
  perform public._admin_guard();
  return query
  select u.id, u.email::text,
         coalesce(u.raw_user_meta_data->>'full_name', u.raw_user_meta_data->>'name')::text,
         coalesce(u.raw_app_meta_data->>'provider', '')::text,
         u.created_at, u.last_sign_in_at,
         p.nickname, coalesce(g.tickets, 0),
         coalesce(jsonb_array_length(case when jsonb_typeof(sp.data->'owned') = 'array' then sp.data->'owned' else '[]'::jsonb end), 0),
         (select count(*)::int from public.matches m where m.user_id = u.id and m.result = 'win'),
         (select count(*)::int from public.matches m where m.user_id = u.id and m.result = 'lose'),
         (select count(*)::int from public.matches m where m.user_id = u.id and m.result = 'draw')
    from auth.users u
    left join public.profiles p on p.id = u.id
    left join public.story_gacha g on g.user_id = u.id
    left join public.story_progress sp on sp.user_id = u.id
   where p_search is null or p_search = ''
      or u.email ilike '%' || p_search || '%'
      or coalesce(u.raw_user_meta_data->>'full_name', u.raw_user_meta_data->>'name', '') ilike '%' || p_search || '%'
      or coalesce(p.nickname, '') ilike '%' || p_search || '%'
   order by u.created_at desc
   limit greatest(1, least(coalesce(p_limit, 100), 500)) offset greatest(0, coalesce(p_offset, 0));
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.admin_list_users(text, int, int) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.admin_list_users(text, int, int) to authenticated;$vr_statement$;
  execute $vr_statement$-- 2) 유저 상세: 보유 카드(스토리 owned) · 리더 · 스토리 진행 · 소환권 · 아케이드 전적 · 최근 판 · 갤러리
create or replace function public.admin_user_detail(p_user uuid) returns jsonb language plpgsql stable security definer set search_path = public, auth as $$
declare u record; d jsonb; r jsonb;
begin
  perform public._admin_guard();
  select id, email, created_at, last_sign_in_at, raw_user_meta_data into u from auth.users where id = p_user;
  if u.id is null then raise exception 'no such user'; end if;
  select data into d from public.story_progress where user_id = p_user;
  d := coalesce(d, '{}'::jsonb);
  r := jsonb_build_object(
    'id', u.id, 'email', u.email, 'name', coalesce(u.raw_user_meta_data->>'full_name', u.raw_user_meta_data->>'name'),
    'created_at', u.created_at, 'last_sign_in_at', u.last_sign_in_at,
    'nickname', (select nickname from public.profiles where id = p_user),
    'owned', coalesce(d->'owned', '[]'::jsonb), 'leader', d->'leader', 'starter', d->'starter',
    'cleared', coalesce(d->'cleared', '{}'::jsonb), 'points', coalesce(d->'points', '0'::jsonb),
    'tickets', coalesce((select tickets from public.story_gacha where user_id = p_user), 0),
    'record', (select jsonb_build_object('wins', count(*) filter (where result = 'win'), 'losses', count(*) filter (where result = 'lose'), 'draws', count(*) filter (where result = 'draw'))
                 from public.matches where user_id = p_user),
    'recent', coalesce((select jsonb_agg(x order by x.created_at desc) from (select result, reason, turns, damage, mvp_name, created_at from public.matches where user_id = p_user order by created_at desc limit 20) x), '[]'::jsonb),
    'gallery', (select jsonb_build_object('cards', count(*), 'mvp', coalesce(sum(mvp_count), 0)) from public.gallery where user_id = p_user)
  );
  return r;
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.admin_user_detail(uuid) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.admin_user_detail(uuid) to authenticated;$vr_statement$;
  execute $vr_statement$-- 3) 소환권 지급 (1~1000장, 사유 필수). admin_log 에 기록. 반환 { ok, tickets, before }
create or replace function public.admin_grant_tickets(p_user uuid, p_amount int, p_reason text) returns jsonb language plpgsql volatile security definer set search_path = public, auth as $$
declare b int; a int;
begin
  perform public._admin_guard();
  if p_amount is null or p_amount < 1 or p_amount > 1000 then raise exception 'amount must be 1..1000'; end if;
  if coalesce(btrim(p_reason), '') = '' then raise exception 'reason required'; end if;
  if not exists (select 1 from auth.users where id = p_user) then raise exception 'no such user'; end if;
  insert into public.story_gacha (user_id, last_draw) values (p_user, (now() at time zone 'Asia/Seoul')::date - 1) on conflict (user_id) do nothing;
  select tickets into b from public.story_gacha where user_id = p_user for update;
  update public.story_gacha set tickets = tickets + p_amount, updated_at = now() where user_id = p_user returning tickets into a;
  insert into public.admin_log (admin_id, admin_email, action, target_user, amount, reason, before_val, after_val)
  values (auth.uid(), auth.jwt()->>'email', 'grant_tickets', p_user, p_amount, left(btrim(p_reason), 200), b, a);
  return jsonb_build_object('ok', true, 'tickets', a, 'before', b);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.admin_grant_tickets(uuid, int, text) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.admin_grant_tickets(uuid, int, text) to authenticated;$vr_statement$;
  execute $vr_statement$-- 4) 유저 뽑기 기록 (매일 뽑기 + 소환권 뽑기)
create or replace function public.admin_gacha_log(p_user uuid, p_limit int default 200)
returns table (id bigint, card_id text, grade text, kind text, created_at timestamptz)
language plpgsql stable security definer set search_path = public, auth as $$
begin
  perform public._admin_guard();
  return query select l.id, l.card_id, l.grade, l.kind, l.created_at from public.story_gacha_log l
    where l.user_id = p_user order by l.created_at desc limit greatest(1, least(coalesce(p_limit, 200), 1000));
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.admin_gacha_log(uuid, int) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.admin_gacha_log(uuid, int) to authenticated;$vr_statement$;
  execute $vr_statement$-- 5) 관리자 작업 기록 보기
create or replace function public.admin_logs(p_limit int default 100)
returns table (id bigint, admin_email text, action text, target_user uuid, target_email text, amount int, reason text, before_val int, after_val int, created_at timestamptz)
language plpgsql stable security definer set search_path = public, auth as $$
begin
  perform public._admin_guard();
  return query select l.id, l.admin_email, l.action, l.target_user, u.email::text, l.amount, l.reason, l.before_val, l.after_val, l.created_at
    from public.admin_log l left join auth.users u on u.id = l.target_user
    order by l.created_at desc limit greatest(1, least(coalesce(p_limit, 100), 1000));
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.admin_logs(int) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.admin_logs(int) to authenticated;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: quest.sql =====
-- ⚠ 다시 돌리지 마세요, 최신 아님 (일부): 이 파일의 admin_user_quest, quest_complete, quest_start, quest_status 는 뒤 파일에서 다시 정의됨. 이 파일을 다시 돌리면 예전 것으로 되돌아가요. supabase/README.md 참고
-- =====================================================================
-- 퀘스트 모드 (시련의 탑) — Supabase SQL Editor 에서 실행. 여러 번 실행해도 안전
-- 필요: story_gacha.sql(소환권), story_server.sql(_story_min_battle_secs), admin.sql(관리자 상세용, 선택)
-- 규칙: 로그인 유저만. 도전 가능 층 = 1 .. (최고 층 + 1). 첫 클리어 보상만 (10층마다 소환권 5, 50층마다 10). 재도전 무제한
-- 클라이언트는 quest_progress 를 읽기만 하고 쓰기는 아래 SECURITY DEFINER 함수로만
-- 확인용: select public.quest_status();  → { best_floor, max_floor, battle }
-- =====================================================================

create table if not exists public.quest_progress (
  user_id     uuid primary key references auth.users(id) on delete cascade default auth.uid(),
  best_floor  int not null default 0 check (best_floor >= 0),
  battle      jsonb,                                   -- 진행 중 전투 { floor, at }
  clears      int not null default 0,                  -- 승리 횟수 (재클리어 포함)
  rewards     jsonb not null default '{}'::jsonb,      -- 받은 보상 합계 { tickets, gold }
  updated_at  timestamptz not null default now()
);$vr_statement$;
  execute $vr_statement$alter table public.quest_progress enable row level security;$vr_statement$;
  execute $vr_statement$drop policy if exists "quest_select_own" on public.quest_progress;$vr_statement$;
  execute $vr_statement$create policy "quest_select_own" on public.quest_progress for select using (user_id = auth.uid());$vr_statement$;
  execute $vr_statement$revoke insert, update, delete on public.quest_progress from anon, authenticated;$vr_statement$;
  execute $vr_statement$grant select on public.quest_progress to authenticated;$vr_statement$;
  execute $vr_statement$-- 층 수 (data/quest.json 과 같게. 층을 늘리면 이 값도 올림)
create or replace function public._quest_max_floor() returns int language sql immutable as $$ select 350 $$;$vr_statement$;
  execute $vr_statement$-- 최소 전투 시간 (초)
create or replace function public._quest_min_secs() returns int language sql immutable as $$ select 5 $$;$vr_statement$;
  execute $vr_statement$-- 첫 클리어 보상 (골드 등은 여기에 추가: 'gold', n). data/quest.json rewards 와 같은 규칙
create or replace function public._quest_reward(p_floor int) returns jsonb language sql immutable as $$
  select case when p_floor % 50 = 0 then jsonb_build_object('tickets', 10)
              when p_floor % 10 = 0 then jsonb_build_object('tickets', 5)
              else '{}'::jsonb end
$$;$vr_statement$;
  execute $vr_statement$revoke all on function public._quest_max_floor() from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$revoke all on function public._quest_min_secs() from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$revoke all on function public._quest_reward(int) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$grant execute on function public._quest_max_floor() to authenticated;$vr_statement$;
  execute $vr_statement$-- 상수라 노출돼도 무해 (quest_status 에서도 반환)

create or replace function public._quest_row(uid uuid) returns public.quest_progress language plpgsql set search_path = public as $$
declare r public.quest_progress;
begin
  if uid is null then raise exception 'login required'; end if;
  insert into quest_progress (user_id) values (uid) on conflict (user_id) do nothing;
  select * into r from quest_progress where user_id = uid for update;
  return r;
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._quest_row(uuid) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$-- 상태 (확인용 RPC)
create or replace function public.quest_status() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); r quest_progress;
begin
  if uid is null then raise exception 'login required'; end if;
  select * into r from quest_progress where user_id = uid;
  return jsonb_build_object('best_floor', coalesce(r.best_floor, 0), 'max_floor', _quest_max_floor(), 'clears', coalesce(r.clears, 0), 'rewards', coalesce(r.rewards, '{}'::jsonb));
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.quest_status() from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.quest_status() to authenticated;$vr_statement$;
  execute $vr_statement$-- 전투 시작: 열린 층(최고 층 + 1 이하)만
create or replace function public.quest_start(p_floor int) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); r quest_progress;
begin
  if p_floor is null or p_floor < 1 or p_floor > _quest_max_floor() then raise exception 'invalid floor'; end if;
  r := _quest_row(uid);
  if p_floor > r.best_floor + 1 then raise exception 'floor locked'; end if;
  update quest_progress set battle = jsonb_build_object('floor', p_floor, 'at', (extract(epoch from clock_timestamp()))::bigint), updated_at = now() where user_id = uid;
  return jsonb_build_object('ok', true, 'floor', p_floor, 'best_floor', r.best_floor);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.quest_start(int) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.quest_start(int) to authenticated;$vr_statement$;
  execute $vr_statement$-- 승리 기록: 시작 기록·최소 시간 확인 → 첫 클리어면 최고 층 갱신 + 보상(소환권은 story_gacha.tickets 에 더함)
-- p_stats: { turns } (참고용, 1..40 이어야 함). 반환 { ok, first, floor, best_floor, reward, tickets }
create or replace function public.quest_complete(p_floor int, p_stats jsonb default '{}'::jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); r quest_progress; b jsonb; first boolean; rw jsonb := '{}'::jsonb; t int; tk int := null; turns int;
begin
  r := _quest_row(uid);
  b := r.battle;
  if b is null or (b->>'floor')::int <> p_floor then raise exception 'battle not started'; end if;
  if extract(epoch from clock_timestamp()) - (b->>'at')::bigint < _quest_min_secs() then raise exception 'too fast'; end if;
  turns := coalesce((p_stats->>'turns')::int, 1);
  if turns < 1 or turns > 40 then raise exception 'invalid stats'; end if;
  first := p_floor = r.best_floor + 1;
  if first then
    rw := _quest_reward(p_floor);
    t := coalesce((rw->>'tickets')::int, 0);
    if t > 0 then
      insert into story_gacha (user_id, last_draw) values (uid, (now() at time zone 'Asia/Seoul')::date - 1) on conflict (user_id) do nothing;
      update story_gacha set tickets = tickets + t, updated_at = now() where user_id = uid returning tickets into tk;
    end if;
  end if;
  update quest_progress set battle = null, clears = clears + 1,
    best_floor = case when first then p_floor else best_floor end,
    rewards = case when first and rw <> '{}'::jsonb then jsonb_build_object('tickets', coalesce((rewards->>'tickets')::int, 0) + coalesce((rw->>'tickets')::int, 0), 'gold', coalesce((rewards->>'gold')::int, 0) + coalesce((rw->>'gold')::int, 0)) else rewards end,
    updated_at = now()
  where user_id = uid;
  return jsonb_build_object('ok', true, 'first', first, 'floor', p_floor, 'best_floor', greatest(r.best_floor, case when first then p_floor else 0 end), 'reward', rw, 'tickets', tk);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.quest_complete(int, jsonb) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.quest_complete(int, jsonb) to authenticated;$vr_statement$;
  execute $vr_statement$-- 관리자: 유저 퀘스트 최고 층 (admin.sql 의 _admin_guard 사용. admin.sql 실행 후)
create or replace function public.admin_user_quest(p_user uuid) returns jsonb language plpgsql stable security definer set search_path = public, auth as $$
declare r quest_progress;
begin
  perform public._admin_guard();
  select * into r from quest_progress where user_id = p_user;
  return jsonb_build_object('best_floor', coalesce(r.best_floor, 0), 'clears', coalesce(r.clears, 0), 'rewards', coalesce(r.rewards, '{}'::jsonb), 'updated_at', r.updated_at);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.admin_user_quest(uuid) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.admin_user_quest(uuid) to authenticated;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: phaseE_1.sql =====
-- ⚠ 다시 돌리지 마세요, 최신 아님 (일부): 이 파일의 wallet_status 는 뒤 파일에서 다시 정의됨. 이 파일을 다시 돌리면 예전 것으로 되돌아가요. supabase/README.md 참고
-- =====================================================================
-- 단계 E-1: 지갑(재화) — Supabase SQL Editor 에서 실행. 여러 번 실행해도 안전
-- 재화: gold(골드) · blood(순수한 피) · shard(이상한 조각) · soul(각성자의 혼)
-- 소환권은 기존 story_gacha.tickets 그대로 (이 파일은 건드리지 않음)
-- 쓰기는 전부 서버 함수(_wallet_add)로만. 클라이언트는 본인 지갑 읽기(wallet_status)만 가능
-- 획득처(스토리·퀘스트 드롭, 분해 수익)와 사용처는 이후 단계(E-2~)에서 _wallet_add 를 호출해 연결
-- 선행: admin.sql (관리자 지급 함수가 _admin_guard / admin_log 사용)
-- 확인용: select public.wallet_status();  → { ok:true, gold, blood, shard, soul }
-- =====================================================================

-- 1) 지갑
create table if not exists public.player_wallet (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  gold       bigint not null default 0 check (gold  >= 0),
  blood      bigint not null default 0 check (blood >= 0),
  shard      bigint not null default 0 check (shard >= 0),
  soul       bigint not null default 0 check (soul  >= 0),
  updated_at timestamptz not null default now()
);$vr_statement$;
  execute $vr_statement$alter table public.player_wallet enable row level security;$vr_statement$;
  execute $vr_statement$revoke all on public.player_wallet from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$grant select on public.player_wallet to authenticated;$vr_statement$;
  execute $vr_statement$drop policy if exists "wallet_read_own" on public.player_wallet;$vr_statement$;
  execute $vr_statement$create policy "wallet_read_own" on public.player_wallet for select using (auth.uid() = user_id);$vr_statement$;
  execute $vr_statement$-- 2) 재화 변동 기록 (획득·사용 추적용, 클라이언트 접근 불가)
create table if not exists public.wallet_log (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references auth.users(id) on delete cascade,
  delta      jsonb not null,           -- {"gold":120,"blood":-30}
  after      jsonb not null,           -- 변동 후 잔액
  reason     text not null check (char_length(reason) <= 60),   -- 'story_clear', 'dismantle', 'card_levelup', 'admin' ...
  created_at timestamptz not null default now()
);$vr_statement$;
  execute $vr_statement$create index if not exists wallet_log_user_idx on public.wallet_log (user_id, created_at desc);$vr_statement$;
  execute $vr_statement$alter table public.wallet_log enable row level security;$vr_statement$;
  execute $vr_statement$revoke all on public.wallet_log from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$-- 3) 내부 도우미: 재화 증감 (음수 = 사용). 잔액 부족이면 'not enough <key>' 예외 → 호출한 RPC 전체가 롤백
--    p_delta 키는 gold/blood/shard/soul 만, 값은 정수. 0 은 무시. 반환: 변동 후 잔액
create or replace function public._wallet_add(p_uid uuid, p_delta jsonb, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare k text; v jsonb; w player_wallet; g bigint; b bigint; s bigint; o bigint; clean jsonb := '{}'::jsonb; res jsonb;
begin
  if p_uid is null then raise exception 'login required'; end if;
  if jsonb_typeof(p_delta) <> 'object' then raise exception 'invalid delta'; end if;
  if coalesce(btrim(p_reason), '') = '' then raise exception 'reason required'; end if;
  for k, v in select * from jsonb_each(p_delta) loop
    if k not in ('gold', 'blood', 'shard', 'soul') then raise exception 'invalid currency: %', k; end if;
    if jsonb_typeof(v) <> 'number' or v::text ~ '[.eE]' then raise exception 'invalid amount'; end if;
    if v::bigint <> 0 then clean := clean || jsonb_build_object(k, v::bigint); end if;
  end loop;
  insert into player_wallet (user_id) values (p_uid) on conflict (user_id) do nothing;
  select * into w from player_wallet where user_id = p_uid for update;
  g := w.gold  + coalesce((clean->>'gold')::bigint, 0);
  b := w.blood + coalesce((clean->>'blood')::bigint, 0);
  s := w.shard + coalesce((clean->>'shard')::bigint, 0);
  o := w.soul  + coalesce((clean->>'soul')::bigint, 0);
  if g < 0 then raise exception 'not enough gold'; end if;
  if b < 0 then raise exception 'not enough blood'; end if;
  if s < 0 then raise exception 'not enough shard'; end if;
  if o < 0 then raise exception 'not enough soul'; end if;
  res := jsonb_build_object('gold', g, 'blood', b, 'shard', s, 'soul', o);
  if clean <> '{}'::jsonb then
    update player_wallet set gold = g, blood = b, shard = s, soul = o, updated_at = now() where user_id = p_uid;
    insert into wallet_log (user_id, delta, after, reason) values (p_uid, clean, res, left(btrim(p_reason), 60));
  end if;
  return res;
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._wallet_add(uuid, jsonb, text) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$-- 4) 공개 RPC: 내 지갑 (행이 없으면 0). 탐침(probe) 겸용
create or replace function public.wallet_status() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); w player_wallet;
begin
  if uid is null then raise exception 'login required'; end if;
  select * into w from player_wallet where user_id = uid;
  return jsonb_build_object('ok', true, 'gold', coalesce(w.gold, 0), 'blood', coalesce(w.blood, 0), 'shard', coalesce(w.shard, 0), 'soul', coalesce(w.soul, 0));
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.wallet_status() from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.wallet_status() to authenticated;$vr_statement$;
  execute $vr_statement$-- 5) 관리자: 유저 지갑 조회 / 재화 지급·회수 (admin_log 에 기록, 관리자 판정은 서버 _admin_guard)
create or replace function public.admin_user_wallet(p_user uuid) returns jsonb language plpgsql stable security definer set search_path = public, auth as $$
declare w player_wallet;
begin
  perform public._admin_guard();
  select * into w from player_wallet where user_id = p_user;
  return jsonb_build_object('gold', coalesce(w.gold, 0), 'blood', coalesce(w.blood, 0), 'shard', coalesce(w.shard, 0), 'soul', coalesce(w.soul, 0),
    'log', coalesce((select jsonb_agg(x order by x.created_at desc) from (select delta, after, reason, created_at from wallet_log where user_id = p_user order by created_at desc limit 50) x), '[]'::jsonb));
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.admin_user_wallet(uuid) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.admin_user_wallet(uuid) to authenticated;$vr_statement$;
  execute $vr_statement$-- p_amount: −1,000,000 ~ 1,000,000 (0 제외, 음수 = 회수). 반환 { ok, key, before, after, wallet }
create or replace function public.admin_grant_currency(p_user uuid, p_key text, p_amount int, p_reason text) returns jsonb language plpgsql volatile security definer set search_path = public, auth as $$
declare bef bigint; res jsonb;
begin
  perform public._admin_guard();
  if p_key not in ('gold', 'blood', 'shard', 'soul') then raise exception 'invalid currency'; end if;
  if p_amount is null or p_amount = 0 or abs(p_amount) > 1000000 then raise exception 'amount must be ±1..1000000'; end if;
  if coalesce(btrim(p_reason), '') = '' then raise exception 'reason required'; end if;
  if not exists (select 1 from auth.users where id = p_user) then raise exception 'no such user'; end if;
  select case p_key when 'gold' then gold when 'blood' then blood when 'shard' then shard else soul end into bef from player_wallet where user_id = p_user;
  bef := coalesce(bef, 0);
  res := public._wallet_add(p_user, jsonb_build_object(p_key, p_amount), 'admin');
  insert into public.admin_log (admin_id, admin_email, action, target_user, amount, reason, before_val, after_val)
  values (auth.uid(), auth.jwt()->>'email', 'grant_' || p_key, p_user, p_amount, left(btrim(p_reason), 200), least(bef, 2147483647)::int, least((res->>p_key)::bigint, 2147483647)::int);
  return jsonb_build_object('ok', true, 'key', p_key, 'before', bef, 'after', (res->>p_key)::bigint, 'wallet', res);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.admin_grant_currency(uuid, text, int, text) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.admin_grant_currency(uuid, text, int, text) to authenticated;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: phaseE_2.sql =====
-- ⚠ 다시 돌리지 마세요, 최신 아님 (일부): 이 파일의 _player_add_xp, _player_xp_need, story_complete_phase 는 뒤 파일에서 다시 정의됨. 이 파일을 다시 돌리면 예전 것으로 되돌아가요. supabase/README.md 참고
-- =====================================================================
-- 단계 E-2: 플레이어 레벨 + 행동력 — Supabase SQL Editor 에서 실행. 여러 번 실행해도 안전
-- 선행: story_*.sql 전부, admin.sql, phaseE_1.sql (레벨업 골드 보상에 지갑 사용)
--
-- 규칙 (확정안)
--   플레이어 레벨 1~100. 경험치는 스토리에서만: 클리어 1회 = 소모 행동력 × 10 (= 60),
--     첫 클리어 보너스 일반 +50 / 보스 +150. 다음 레벨까지 필요량 = 100 + 20 × (L − 1)
--   레벨업 보상: 행동력 +새 최대치 (최대치를 넘어도 보관), 골드 +100 × 새 레벨
--   행동력 최대치 = 40 + 5 × floor(L / 5)  (Lv1 40 · Lv50 90 · Lv100 140)
--   회복: 6분에 1 (서버 시각 기준 계산). 최대치 이상이면 회복 없음
--   비용: 스토리 모든 페이즈 6 (보스 포함). 시련의 탑·아케이드는 0
--   패배·포기: 전부 반환 (story_abort_phase). 전투를 끝내지 않고 새 전투를 시작해도 이전 전투 분은 반환
--   행동력 골드 충전 없음
--   해금 레벨: 소탕 5 · 기술 레벨 10 · 장비 15 · 장비 합성 20 (_player_unlocked 로 이후 단계에서 확인)
--   기존 유저도 모두 Lv1 부터 시작 (클리어 기록 소급 없음)
--
-- 구조: 기존 story_start_phase / story_complete_phase(3인자) 를 _e0 이름으로 보관하고
--       같은 이름의 감싸는 함수(행동력·경험치 처리)를 새로 만듦.
--       ※ 나중에 story_merge.sql 등 스토리 SQL 을 다시 실행했다면 이 파일도 다시 실행해 주세요 (자동으로 다시 감쌈)
-- 확인용: select public.player_status();
-- =====================================================================

-- 1) 플레이어 상태
create table if not exists public.player_state (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  level      int not null default 1 check (level between 1 and 100),
  xp         int not null default 0 check (xp >= 0),          -- 현재 레벨 안에서 모은 경험치
  stamina    int not null default 40 check (stamina >= 0),
  stamina_at timestamptz not null default now(),             -- 회복 기준 시각
  updated_at timestamptz not null default now()
);$vr_statement$;
  execute $vr_statement$alter table public.player_state enable row level security;$vr_statement$;
  execute $vr_statement$revoke all on public.player_state from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$grant select on public.player_state to authenticated;$vr_statement$;
  execute $vr_statement$drop policy if exists "player_read_own" on public.player_state;$vr_statement$;
  execute $vr_statement$create policy "player_read_own" on public.player_state for select using (auth.uid() = user_id);$vr_statement$;
  execute $vr_statement$-- 2) 수치 (한 곳에서 조정)
create or replace function public._player_max_level() returns int language sql immutable as $$ select 100 $$;$vr_statement$;
  execute $vr_statement$create or replace function public._player_xp_need(p_level int) returns int language sql immutable as $$ select 3 * (100 + 20 * (greatest(p_level, 1) - 1)) $$;$vr_statement$;
  execute $vr_statement$-- 2026-10: 3배 (player_xp_x3.sql)
create or replace function public._stamina_max(p_level int) returns int language sql immutable as $$ select 40 + 5 * (greatest(p_level, 1) / 5) $$;$vr_statement$;
  execute $vr_statement$create or replace function public._stamina_regen_secs() returns int language sql immutable as $$ select 360 $$;$vr_statement$;
  execute $vr_statement$create or replace function public._stamina_cost(p_chapter int, p_phase int) returns int language sql immutable as $$ select 6 $$;$vr_statement$;
  execute $vr_statement$create or replace function public._player_xp_per_stamina() returns int language sql immutable as $$ select 10 $$;$vr_statement$;
  execute $vr_statement$create or replace function public._player_first_bonus(p_type text) returns int language sql immutable as $$ select case when p_type = 'boss' then 150 else 50 end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._player_unlock_level(p_key text) returns int language sql immutable as $$
  select case p_key when 'sweep' then 5 when 'skill' then 10 when 'equip' then 15 when 'equip_merge' then 20 else null end $$;$vr_statement$;
  execute $vr_statement$-- 3) 내부 도우미
-- 경험치를 더하고 레벨업 처리. p_reward = true 면 레벨업 보상(행동력·골드) 지급. 반환 { levelups, gold }
create or replace function public._player_add_xp(p_uid uuid, p_xp int, p_reward boolean) returns jsonb language plpgsql security definer set search_path = public as $$
declare ps player_state; n int := 0; gold int := 0; mx int;
begin
  select * into ps from player_state where user_id = p_uid for update;
  if ps.user_id is null or p_xp <= 0 then return jsonb_build_object('levelups', 0, 'gold', 0); end if;
  ps.xp := ps.xp + p_xp;
  while ps.level < _player_max_level() and ps.xp >= _player_xp_need(ps.level) loop
    ps.xp := ps.xp - _player_xp_need(ps.level);
    ps.level := ps.level + 1; n := n + 1;
    if p_reward then
      mx := _stamina_max(ps.level);
      if ps.stamina >= _stamina_max(ps.level - 1) then ps.stamina_at := now(); end if;
      ps.stamina := ps.stamina + mx;
      gold := gold + 100 * ps.level;
    end if;
  end loop;
  if ps.level >= _player_max_level() then ps.xp := 0; end if;
  update player_state set level = ps.level, xp = ps.xp, stamina = ps.stamina, stamina_at = ps.stamina_at, updated_at = now() where user_id = p_uid;
  if gold > 0 and to_regprocedure('public._wallet_add(uuid,jsonb,text)') is not null then
    perform public._wallet_add(p_uid, jsonb_build_object('gold', gold), 'player_levelup');
  end if;
  -- 조직 세력 (guild.sql): 스토리 경험치 60 = 행동력 6 → 세력 1 (하루 상한은 _guild_feed 가 처리)
  if to_regprocedure('public._guild_feed(uuid,text,integer)') is not null then perform public._guild_feed(p_uid, 'story', greatest(1, p_xp / 60)); end if;
  return jsonb_build_object('levelups', n, 'gold', gold);
end $$;$vr_statement$;
  execute $vr_statement$-- 행 잠금 + 회복 반영. 없으면 Lv1 · 행동력 최대치로 생성
create or replace function public._player_sync(p_uid uuid) returns player_state language plpgsql security definer set search_path = public as $$
declare ps player_state; mx int; n int; secs int := _stamina_regen_secs();
begin
  if p_uid is null then raise exception 'login required'; end if;
  insert into player_state (user_id, stamina) values (p_uid, _stamina_max(1)) on conflict (user_id) do nothing;   -- 모두 Lv1 부터 (소급 없음)
  select * into ps from player_state where user_id = p_uid for update;
  mx := _stamina_max(ps.level);
  if ps.stamina >= mx then
    ps.stamina_at := now();
  else
    n := floor(extract(epoch from (now() - ps.stamina_at)) / secs)::int;
    if n > 0 then
      ps.stamina := least(mx, ps.stamina + n);
      ps.stamina_at := case when ps.stamina >= mx then now() else ps.stamina_at + make_interval(secs => n * secs) end;
    end if;
  end if;
  update player_state set stamina = ps.stamina, stamina_at = ps.stamina_at where user_id = p_uid;
  return ps;
end $$;$vr_statement$;
  execute $vr_statement$-- 행동력 증감 (회복 기준 시각 보정 포함). 반환 새 값
create or replace function public._player_stamina_add(p_uid uuid, p_delta int) returns int language plpgsql security definer set search_path = public as $$
declare ps player_state; mx int; nv int;
begin
  ps := _player_sync(p_uid);
  mx := _stamina_max(ps.level); nv := ps.stamina + p_delta;
  if nv < 0 then raise exception 'not enough stamina'; end if;
  -- 최대치 이상 → 미만으로 내려가면 지금부터 회복 시작
  update player_state set stamina = nv, stamina_at = case when ps.stamina >= mx or nv >= mx then now() else stamina_at end, updated_at = now() where user_id = p_uid;
  return nv;
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._player_json(p_uid uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare ps player_state; mx int; secs int := _stamina_regen_secs();
begin
  ps := _player_sync(p_uid); mx := _stamina_max(ps.level);
  return jsonb_build_object('ok', true, 'level', ps.level, 'max_level', _player_max_level(), 'xp', ps.xp,
    'xp_next', case when ps.level >= _player_max_level() then 0 else _player_xp_need(ps.level) end,
    'stamina', ps.stamina, 'stamina_max', mx, 'regen_secs', secs,
    'next_regen_secs', case when ps.stamina >= mx then 0 else greatest(0, secs - floor(extract(epoch from (now() - ps.stamina_at)))::int) end,
    'cost', jsonb_build_object('story', _stamina_cost(0, 0), 'quest', 0, 'arcade', 0),
    'unlocks', jsonb_build_object('sweep', _player_unlock_level('sweep'), 'skill', _player_unlock_level('skill'), 'equip', _player_unlock_level('equip'), 'equip_merge', _player_unlock_level('equip_merge')));
end $$;$vr_statement$;
  execute $vr_statement$-- 이후 단계용: 해금 확인 (서버 RPC 안에서 perform 으로 사용)
create or replace function public._player_unlocked(p_uid uuid, p_key text) returns boolean language plpgsql security definer set search_path = public as $$
declare lv int := (_player_sync(p_uid)).level; need int := _player_unlock_level(p_key);
begin return need is not null and lv >= need; end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._player_add_xp(uuid, int, boolean), public._player_sync(uuid), public._player_stamina_add(uuid, int), public._player_json(uuid), public._player_unlocked(uuid, text) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$-- 4) 기존 스토리 함수 보관 (_e0) — 이미 감싼 상태면 건너뜀, 스토리 SQL 재실행으로 원본이 새로 생겼으면 다시 보관
do $$
declare src text;
begin
  select prosrc into src from pg_proc where oid = to_regprocedure('public.story_start_phase(int,int)');
  if src is not null and src not like '%phaseE_2 wrapper%' then
    drop function if exists public._story_start_phase_e0(int, int);
    alter function public.story_start_phase(int, int) rename to _story_start_phase_e0;
  end if;
  select prosrc into src from pg_proc where oid = to_regprocedure('public.story_complete_phase(int,int,jsonb)');
  if src is not null and src not like '%phaseE_2 wrapper%' then
    drop function if exists public._story_complete_phase_e0(int, int, jsonb);
    alter function public.story_complete_phase(int, int, jsonb) rename to _story_complete_phase_e0;
  end if;
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._story_start_phase_e0(int, int), public._story_complete_phase_e0(int, int, jsonb) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$-- 5) 감싸는 함수
-- 전투 시작: 이전 미완료 전투 행동력 반환 → 6 차감 → 원래 시작 처리 → battle.stamina 기록
create or replace function public.story_start_phase(p_chapter int, p_phase int) returns jsonb language plpgsql security definer set search_path = public as $$
-- phaseE_2 wrapper
declare uid uuid := auth.uid(); b jsonb; d jsonb; cost int := _stamina_cost(p_chapter, p_phase);
begin
  if uid is null then raise exception 'login required'; end if;
  perform _player_sync(uid);
  select data->'battle' into b from story_progress where user_id = uid for update;
  if b is not null and (b->>'stamina') is not null then perform _player_stamina_add(uid, (b->>'stamina')::int); end if;
  perform _player_stamina_add(uid, -cost);   -- 부족하면 'not enough stamina' (전체 롤백)
  d := _story_start_phase_e0(p_chapter, p_phase);
  d := jsonb_set(d, '{battle,stamina}', to_jsonb(cost));
  update story_progress set data = d where user_id = uid;
  return d;
end $$;$vr_statement$;
  execute $vr_statement$-- 전투 완료(승리): 원래 처리 → 플레이어 경험치 (행동력 × 10 + 첫 클리어 보너스). 결과에 player 추가
create or replace function public.story_complete_phase(p_chapter int, p_phase int, p_stats jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
-- phaseE_2 wrapper
declare uid uuid := auth.uid(); b jsonb; spent int; r jsonb; cfg story_phase_config; xp int; up jsonb; drops jsonb := null;
begin
  if uid is null then raise exception 'login required'; end if;
  select data->'battle' into b from story_progress where user_id = uid;
  spent := coalesce((b->>'stamina')::int, 0);
  r := _story_complete_phase_e0(p_chapter, p_phase, p_stats);
  select * into cfg from story_phase_config where chapter = p_chapter and phase = p_phase;
  xp := spent * _player_xp_per_stamina() + case when coalesce((r->>'first')::boolean, false) then _player_first_bonus(cfg.type) else 0 end;
  perform _player_sync(uid);
  up := _player_add_xp(uid, xp, true);
  -- 재화 드롭 (phaseE_3.sql 의 _story_drops 가 있으면)
  if to_regprocedure('public._story_drops(uuid,integer,integer,boolean)') is not null then
    execute 'select public._story_drops($1, $2, $3, $4)' into drops using uid, p_chapter, p_phase, coalesce((r->>'first')::boolean, false);
  end if;
  return r || jsonb_build_object('player', _player_json(uid) || jsonb_build_object('gained_xp', xp, 'levelups', up->'levelups', 'levelup_gold', up->'gold'))
           || case when drops is null then '{}'::jsonb else jsonb_build_object('drops', drops) end;
end $$;$vr_statement$;
  execute $vr_statement$-- 패배·포기: 진행 중 전투 기록 지우고 행동력 전부 반환. 반환 player_status
create or replace function public.story_abort_phase() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb; refund int := 0;
begin
  if uid is null then raise exception 'login required'; end if;
  d := _story_lock(uid);
  if d->'battle' is not null then
    refund := coalesce((d->'battle'->>'stamina')::int, 0);
    perform _story_save(uid, d - 'battle');
    if refund > 0 then perform _player_stamina_add(uid, refund); end if;
  end if;
  return _player_json(uid) || jsonb_build_object('refunded', refund);
end $$;$vr_statement$;
  execute $vr_statement$-- 6) 공개 RPC: 내 레벨·행동력 (탐침 겸용)
create or replace function public.player_status() returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'login required'; end if;
  return _player_json(auth.uid());
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.story_start_phase(int, int), public.story_complete_phase(int, int, jsonb), public.story_abort_phase(), public.player_status() from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.story_start_phase(int, int), public.story_complete_phase(int, int, jsonb), public.story_abort_phase(), public.player_status() to authenticated;$vr_statement$;
  execute $vr_statement$-- 7) 관리자: 유저 레벨·행동력 조회
create or replace function public.admin_user_player(p_user uuid) returns jsonb language plpgsql security definer set search_path = public, auth as $$
begin
  perform public._admin_guard();
  if not exists (select 1 from auth.users where id = p_user) then raise exception 'no such user'; end if;
  return _player_json(p_user);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.admin_user_player(uuid) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.admin_user_player(uuid) to authenticated;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: phaseE_3.sql =====
-- ⚠ 다시 돌리지 마세요, 최신 아님 (일부): 이 파일의 quest_complete, story_complete_phase, story_dismantle 는 뒤 파일에서 다시 정의됨. 이 파일을 다시 돌리면 예전 것으로 되돌아가요. supabase/README.md 참고
-- =====================================================================
-- 단계 E-3: 재화 드롭 · 시련의 탑 재화 보상 · 분해 수익(재화) · 남은 카드 EXP → 순수한 피 이전
-- Supabase SQL Editor 에서 실행. 여러 번 실행해도 안전 (이전은 유저마다 1회만)
-- 선행: story_*.sql, quest.sql, admin.sql, phaseE_1.sql, phaseE_2.sql
--
-- 스토리 페이즈 클리어 드롭 (행동력 6 기준, ch = 챕터)
--   골드       6 × 20 × (1 + 0.25 × (ch − 1))   (챕터1 120) · 첫 클리어 ×3 · 보스 ×2 (겹침)
--   순수한 피  6 × 2 = 12                        · 첫 클리어 ×3 · 보스 ×2 (겹침)
--   이상한 조각 보스 3 확정 / 일반 첫 클리어 1 확정 / 일반 반복 30% 확률 1 · 나올 때 챕터 2개마다 +1 (ch1·2 +0, ch3·4 +1 ...)
--   각성자의 혼 챕터 5 이상만: 보스 5 / 일반 첫 클리어 2 / 일반 반복 20% 확률 1
-- 시련의 탑 첫 클리어 (층 f): 골드 50 + 5f · 10층마다 순수한 피 50 × (f/10) · 25층마다 이상한 조각 5 · 100층 이후 50층마다 각성자의 혼 10 (소환권 보상은 그대로)
-- 분해: 대상 카드 없이 재화로 (EXP 지급 없음). 전투 EXP 로 카드 레벨업은 그대로
--   등급별  N / R / HR / SR / UR / MR
--   골드      20 / 50 / 120 / 300 / 800 / 2000
--   순수한 피 10 / 30 /  80 / 200 / 500 / 1200   + 그 카드 누적 EXP 50% 를 피로 (EXP 10 = 피 1)
--   각성자의 혼 0 / 1 / 3 / 10 / 30 / 80
--   공용 포인트 환급은 그대로. 리더·잠금 카드는 분해 불가
-- 이전: 모든 카드의 현재 레벨 안 남은 EXP 를 순수한 피로 (EXP 10 = 피 1, 버림), 레벨은 그대로, 남은 EXP 는 0
-- 확인용: select public.economy_rates();
-- =====================================================================

-- 1) 수치
create or replace function public._exp_per_blood() returns int language sql immutable as $$ select 10 $$;$vr_statement$;
  execute $vr_statement$create or replace function public._dismantle_yield(p_grade text) returns jsonb language sql immutable as $$
  select case p_grade
    when 'NORMAL'      then '{"gold":20,"blood":10,"soul":0}'
    when 'RARE'        then '{"gold":50,"blood":30,"soul":1}'
    when 'HIGH RARE'   then '{"gold":120,"blood":80,"soul":3}'
    when 'SUPER RARE'  then '{"gold":300,"blood":200,"soul":10}'
    when 'ULTRA RARE'  then '{"gold":800,"blood":500,"soul":30}'
    when 'MYTHIC RARE' then '{"gold":2000,"blood":1200,"soul":80}'
    else '{"gold":20,"blood":10,"soul":0}' end::jsonb
$$;$vr_statement$;
  execute $vr_statement$create or replace function public._quest_currency(p_floor int) returns jsonb language sql immutable as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'gold', 50 + 5 * p_floor,
    'blood', case when p_floor % 10 = 0 then 50 * (p_floor / 10) end,
    'shard', case when p_floor % 25 = 0 then 5 end,
    'soul', case when p_floor > 100 and p_floor % 50 = 0 then 10 end))
$$;$vr_statement$;
  execute $vr_statement$-- 드롭 계산 (p_roll1/2: 0~1 난수. 테스트에서 고정값을 넣을 수 있게 분리)
create or replace function public._story_drop_calc(p_chapter int, p_type text, p_first boolean, p_cost int, p_roll1 numeric, p_roll2 numeric) returns jsonb language plpgsql immutable as $$
declare m int := (case when p_first then 3 else 1 end) * (case when p_type = 'boss' then 2 else 1 end); g int; b int; s int := 0; o int := 0;
begin
  g := round(p_cost * 20 * (1 + 0.25 * (greatest(p_chapter, 1) - 1)))::int * m;
  b := p_cost * 2 * m;
  s := case when p_type = 'boss' then 3 when p_first then 1 when p_roll1 < 0.3 then 1 else 0 end;
  if s > 0 then s := s + (greatest(p_chapter, 1) - 1) / 2; end if;
  if p_chapter >= 5 then o := case when p_type = 'boss' then 5 when p_first then 2 when p_roll2 < 0.2 then 1 else 0 end; end if;
  return jsonb_build_object('gold', g, 'blood', b, 'shard', s, 'soul', o);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._story_drop_calc(int, text, boolean, int, numeric, numeric) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$-- 공개: 수치 확인 (탐침 겸용, 클라이언트 미리보기에도 사용)
create or replace function public.economy_rates() returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('ok', true, 'version', 3, 'exp_per_blood', _exp_per_blood(),
    'dismantle', jsonb_build_object('NORMAL', _dismantle_yield('NORMAL'), 'RARE', _dismantle_yield('RARE'), 'HIGH RARE', _dismantle_yield('HIGH RARE'),
                                    'SUPER RARE', _dismantle_yield('SUPER RARE'), 'ULTRA RARE', _dismantle_yield('ULTRA RARE'), 'MYTHIC RARE', _dismantle_yield('MYTHIC RARE')),
    'story_ch1_repeat', _story_drop_calc(1, 'normal', false, 6, 0, 0), 'quest_floor_10', _quest_currency(10))
$$;$vr_statement$;
  execute $vr_statement$revoke all on function public.economy_rates() from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.economy_rates() to authenticated;$vr_statement$;
  execute $vr_statement$-- 2) 스토리 드롭 (phaseE_2 감싸는 함수가 호출)
create or replace function public._story_drops(p_uid uuid, p_chapter int, p_phase int, p_first boolean) returns jsonb language plpgsql security definer set search_path = public as $$
declare cfg story_phase_config; dr jsonb;
begin
  select * into cfg from story_phase_config where chapter = p_chapter and phase = p_phase;
  dr := _story_drop_calc(p_chapter, coalesce(cfg.type, 'normal'), p_first, _stamina_cost(p_chapter, p_phase), random()::numeric, random()::numeric);
  perform _wallet_add(p_uid, dr, case when p_first then 'story_first_clear' else 'story_clear' end);
  return dr;
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._story_drops(uuid, int, int, boolean) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$create or replace function public.story_complete_phase(p_chapter int, p_phase int, p_stats jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
-- phaseE_2 wrapper
declare uid uuid := auth.uid(); b jsonb; spent int; r jsonb; cfg story_phase_config; xp int; up jsonb; drops jsonb := null;
begin
  if uid is null then raise exception 'login required'; end if;
  select data->'battle' into b from story_progress where user_id = uid;
  spent := coalesce((b->>'stamina')::int, 0);
  r := _story_complete_phase_e0(p_chapter, p_phase, p_stats);
  select * into cfg from story_phase_config where chapter = p_chapter and phase = p_phase;
  xp := spent * _player_xp_per_stamina() + case when coalesce((r->>'first')::boolean, false) then _player_first_bonus(cfg.type) else 0 end;
  perform _player_sync(uid);
  up := _player_add_xp(uid, xp, true);
  -- 조직 의뢰 진행 (guild2.sql): 페이즈 클리어 · 행동력 · 보스
  if to_regprocedure('public._guild_event(uuid,text,integer)') is not null then
    perform _guild_event(uid, 'phase', 1); perform _guild_event(uid, 'stamina', spent);
    if cfg.type = 'boss' then perform _guild_event(uid, 'boss', 1); end if;
  end if;
  -- 재화 드롭 (phaseE_3.sql 의 _story_drops 가 있으면)
  if to_regprocedure('public._story_drops(uuid,integer,integer,boolean)') is not null then
    execute 'select public._story_drops($1, $2, $3, $4)' into drops using uid, p_chapter, p_phase, coalesce((r->>'first')::boolean, false);
  end if;
  return r || jsonb_build_object('player', _player_json(uid) || jsonb_build_object('gained_xp', xp, 'levelups', up->'levelups', 'levelup_gold', up->'gold'))
           || case when drops is null then '{}'::jsonb else jsonb_build_object('drops', drops) end;
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.story_complete_phase(int, int, jsonb) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.story_complete_phase(int, int, jsonb) to authenticated;$vr_statement$;
  execute $vr_statement$-- 3) 시련의 탑: 첫 클리어 재화 보상 추가 (나머지는 quest.sql 과 같음)
create or replace function public.quest_complete(p_floor int, p_stats jsonb default '{}'::jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); r quest_progress; b jsonb; first boolean; rw jsonb := '{}'::jsonb; cur jsonb := null; t int; tk int := null; turns int; k text;
begin
  r := _quest_row(uid);
  b := r.battle;
  if b is null or (b->>'floor')::int <> p_floor then raise exception 'battle not started'; end if;
  if extract(epoch from clock_timestamp()) - (b->>'at')::bigint < _quest_min_secs() then raise exception 'too fast'; end if;
  turns := coalesce((p_stats->>'turns')::int, 1);
  if turns < 1 or turns > 40 then raise exception 'invalid stats'; end if;
  first := p_floor = r.best_floor + 1;
  if first then
    rw := _quest_reward(p_floor);
    t := coalesce((rw->>'tickets')::int, 0);
    if t > 0 then
      insert into story_gacha (user_id, last_draw) values (uid, (now() at time zone 'Asia/Seoul')::date - 1) on conflict (user_id) do nothing;
      update story_gacha set tickets = tickets + t, updated_at = now() where user_id = uid returning tickets into tk;
    end if;
    cur := _quest_currency(p_floor);
    perform _wallet_add(uid, cur, 'quest_first_clear');
  end if;
  update quest_progress set battle = null, clears = clears + 1,
    best_floor = case when first then p_floor else best_floor end,
    rewards = case when first then (
      select jsonb_object_agg(x.k, coalesce((rewards->>x.k)::int, 0) + coalesce((rw->>x.k)::int, 0) + coalesce((cur->>x.k)::int, 0))
      from unnest(array['tickets', 'gold', 'blood', 'shard', 'soul']) x(k)) else rewards end,
    updated_at = now()
  where user_id = uid;
  return jsonb_build_object('ok', true, 'first', first, 'floor', p_floor, 'best_floor', greatest(r.best_floor, case when first then p_floor else 0 end), 'reward', rw, 'tickets', tk, 'currency', cur);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.quest_complete(int, jsonb) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.quest_complete(int, jsonb) to authenticated;$vr_statement$;
  execute $vr_statement$-- 4) 분해: 재화로 (대상 카드 없음). p_uids = 카드 인스턴스 uid (최대 200, 전부 성공 또는 전부 취소)
create or replace function public.story_dismantle(p_uids text[]) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb; owned jsonb; u text; e jsonb; g text; y jsonb; lead text; gone text[] := '{}';
        gold int := 0; blood int := 0; soul int := 0; refund int := 0; n int := 0; w jsonb;
begin
  if p_uids is null or cardinality(p_uids) = 0 then raise exception 'nothing to discard'; end if;
  if cardinality(p_uids) > 200 then raise exception 'too many cards'; end if;
  d := _story_lock(uid);
  owned := _story_owned(d); lead := d->>'leader';
  foreach u in array p_uids loop
    if u = any(gone) then raise exception 'duplicate card'; end if;
    select x.e into e from jsonb_array_elements(owned) x(e) where x.e->>'uid' = u;
    if e is null then raise exception 'card not owned'; end if;
    if u = lead then raise exception 'cannot discard leader'; end if;
    if coalesce((e->>'locked')::boolean, false) then raise exception 'card locked'; end if;
    e := _story_norm(e);
    select grade into g from story_card_pool where id = e->>'id';
    y := _dismantle_yield(coalesce(g, 'NORMAL'));
    gold := gold + (y->>'gold')::int;
    blood := blood + (y->>'blood')::int + floor((e->>'totalExp')::int * 0.5 / _exp_per_blood())::int + floor(coalesce((e->>'bloodSpent')::int, 0) * 0.5)::int;
    soul := soul + (y->>'soul')::int;
    refund := refund + greatest(0, coalesce((e->'boost'->>'ATK')::int,0) + coalesce((e->'boost'->>'HP')::int,0) + coalesce((e->'boost'->>'DEF')::int,0) - (e->>'spentCard')::int);
    gone := gone || u; n := n + 1;
  end loop;
  select coalesce(jsonb_agg(x.e order by k), '[]'::jsonb) into owned from jsonb_array_elements(owned) with ordinality x(e, k) where not (x.e->>'uid' = any(gone));
  d := jsonb_set(d, '{owned}', owned);
  if refund > 0 then d := jsonb_set(d, '{points}', to_jsonb(coalesce((d->>'points')::int, 0) + refund)); end if;
  d := _story_save(uid, d);
  w := _wallet_add(uid, jsonb_build_object('gold', gold, 'blood', blood, 'soul', soul), 'dismantle');
  return jsonb_build_object('data', d, 'count', n, 'gold', gold, 'blood', blood, 'soul', soul, 'refund', refund, 'wallet', w);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.story_dismantle(text[]) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.story_dismantle(text[]) to authenticated;$vr_statement$;
  execute $vr_statement$-- 예전 분해 RPC(EXP 지급)는 막고 새 분해로 돌림 (대상 카드는 무시)
create or replace function public.story_discard_many(p_ids text[], p_target text) returns jsonb language plpgsql security definer set search_path = public as $$
begin return public.story_dismantle(p_ids) || jsonb_build_object('exp', 0); end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.story_discard(p_id text, p_target text) returns jsonb language plpgsql security definer set search_path = public as $$
begin return (public.story_dismantle(array[p_id]) - 'count') || jsonb_build_object('exp', 0); end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.story_discard_many(text[], text), public.story_discard(text, text) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.story_discard_many(text[], text), public.story_discard(text, text) to authenticated;$vr_statement$;
  execute $vr_statement$-- 5) 이전: 남은 카드 EXP → 순수한 피 (유저마다 1회, data.econV >= 3 이면 건너뜀)
do $$
declare r record; owned jsonb; e jsonb; k int; left_exp int; tot int; blood int;
begin
  for r in select user_id, data from public.story_progress where coalesce((data->>'econV')::int, 0) < 3 and user_id in (select id from auth.users) loop
    owned := case when jsonb_typeof(r.data->'owned') = 'array' then r.data->'owned' else '[]'::jsonb end;
    tot := 0;
    for k in 0 .. jsonb_array_length(owned) - 1 loop
      e := owned->k;
      left_exp := greatest(0, coalesce((e->>'exp')::int, 0));
      if left_exp > 0 then
        tot := tot + left_exp;
        owned := jsonb_set(owned, array[k::text], e || jsonb_build_object('exp', 0, 'totalExp', greatest(0, coalesce((e->>'totalExp')::int, 0) - left_exp)));
      end if;
    end loop;
    blood := tot / public._exp_per_blood();
    update public.story_progress set data = jsonb_set(jsonb_set(data, '{owned}', owned), '{econV}', '3'), updated_at = now() where user_id = r.user_id;
    if blood > 0 then perform public._wallet_add(r.user_id, jsonb_build_object('blood', blood), 'migrate_exp'); end if;
  end loop;
end $$;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: phaseE_4.sql =====
-- =====================================================================
-- 단계 E-4: 카드 레벨업(골드 + 순수한 피) · EX 합성에 이상한 조각 비용
-- Supabase SQL Editor 에서 실행. 여러 번 실행해도 안전
-- 선행: story_*.sql, phaseE_1.sql (지갑), phaseE_3.sql
--
-- 레벨업 L → L+1 비용 (등급별 b, g):  순수한 피 = b × L,  골드 = g × L × 10
--   N  b2  g1   · R  b3  g1.5 · HR b5 g2 · SR b8 g3 · UR b12 g4 · MR b18 g6
--   EX 로 늘어난 레벨 구간(최대 레벨 +5/EX)도 같은 공식. 전투 EXP 레벨업은 그대로 (둘 다 가능)
--   레벨업해도 현재 레벨 안 EXP 진행도는 유지. 쓴 순수한 피는 bloodSpent 에 누적 (분해 시 50% 환급)
-- EX 합성: 같은 카드 1장 + 이상한 조각 (등급 기본 × 다음 EX 단계)
--   기본  N 1 · R 2 · HR 4 · SR 8 · UR 15 · MR 30   (예: UR 을 EX5 로 = 15 × 5 = 75)
-- 구조: 기존 story_merge 를 _story_merge_e0 로 보관하고 같은 이름으로 감쌈 (스토리 SQL 재실행 후엔 이 파일도 다시 실행)
-- 확인용: select public.card_cost_table();
-- =====================================================================

-- 1) 수치
create or replace function public._lv_cost_b(p_grade text) returns numeric language sql immutable as $$
  select case p_grade when 'NORMAL' then 2 when 'RARE' then 3 when 'HIGH RARE' then 5 when 'SUPER RARE' then 8 when 'ULTRA RARE' then 12 when 'MYTHIC RARE' then 18 else 2 end::numeric $$;$vr_statement$;
  execute $vr_statement$create or replace function public._lv_cost_g(p_grade text) returns numeric language sql immutable as $$
  select case p_grade when 'NORMAL' then 1 when 'RARE' then 1.5 when 'HIGH RARE' then 2 when 'SUPER RARE' then 3 when 'ULTRA RARE' then 4 when 'MYTHIC RARE' then 6 else 1 end::numeric $$;$vr_statement$;
  execute $vr_statement$-- 레벨 L 에서 L+1 로 올리는 비용
create or replace function public._lv_cost(p_grade text, p_level int) returns jsonb language sql immutable as $$
  select jsonb_build_object('blood', ceil(_lv_cost_b(p_grade) * p_level)::int, 'gold', ceil(_lv_cost_g(p_grade) * p_level * 10)::int) $$;$vr_statement$;
  execute $vr_statement$create or replace function public._merge_shard_base(p_grade text) returns int language sql immutable as $$
  select case p_grade when 'NORMAL' then 1 when 'RARE' then 2 when 'HIGH RARE' then 4 when 'SUPER RARE' then 8 when 'ULTRA RARE' then 15 when 'MYTHIC RARE' then 30 else 1 end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._merge_shard_cost(p_grade text, p_next_ex int) returns int language sql immutable as $$
  select _merge_shard_base(p_grade) * greatest(1, p_next_ex) $$;$vr_statement$;
  execute $vr_statement$-- 공개: 비용표 (탐침 겸용)
create or replace function public.card_cost_table() returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('ok', true, 'version', 4, 'grades', jsonb_object_agg(g, jsonb_build_object('b', _lv_cost_b(g), 'g', _lv_cost_g(g), 'shard', _merge_shard_base(g), 'lv1', _lv_cost(g, 1))))
  from unnest(array['NORMAL','RARE','HIGH RARE','SUPER RARE','ULTRA RARE','MYTHIC RARE']) g
$$;$vr_statement$;
  execute $vr_statement$revoke all on function public.card_cost_table() from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.card_cost_table() to authenticated;$vr_statement$;
  execute $vr_statement$-- 2) 카드 레벨업: p_uid 카드를 최대 p_levels 단계 (1~100). 최대 레벨·보유 재화가 허락하는 만큼만 올리고 올린 만큼만 차감. 1단계도 못 올리면 'not enough ...'
create or replace function public.story_card_levelup(p_uid text, p_levels int default 1) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb; owned jsonb; i int; e jsonb; g text; lv int; cap int; k int := 0; gold int := 0; blood int := 0; c jsonb; w jsonb; from_lv int; hg bigint := 0; hb bigint := 0;
begin
  if uid is null then raise exception 'login required'; end if;
  if p_levels is null or p_levels < 1 or p_levels > 100 then raise exception 'invalid levels'; end if;
  d := _story_lock(uid);
  owned := _story_owned(d);
  select (n - 1)::int into i from jsonb_array_elements(owned) with ordinality x(e, n) where x.e->>'uid' = p_uid;
  if i is null then raise exception 'card not owned'; end if;
  e := _story_norm(owned->i);
  select grade into g from story_card_pool where id = e->>'id';
  g := coalesce(g, 'NORMAL');
  lv := (e->>'level')::int; from_lv := lv; cap := _story_cap(g, (e->>'ex')::int);
  if lv >= cap then raise exception 'max level'; end if;
  select coalesce(pw.gold, 0), coalesce(pw.blood, 0) into hg, hb from player_wallet pw where pw.user_id = uid;
  hg := coalesce(hg, 0); hb := coalesce(hb, 0);
  while k < p_levels and lv < cap loop
    c := _lv_cost(g, lv);
    if gold + (c->>'gold')::int > hg or blood + (c->>'blood')::int > hb then
      if k = 0 then raise exception 'not enough %', case when gold + (c->>'gold')::int > hg then 'gold' else 'blood' end; end if;
      exit;
    end if;
    gold := gold + (c->>'gold')::int; blood := blood + (c->>'blood')::int;
    lv := lv + 1; k := k + 1;
  end loop;
  w := _wallet_add(uid, jsonb_build_object('gold', -gold, 'blood', -blood), 'card_levelup');
  e := e || jsonb_build_object('level', lv, 'exp', least((e->>'exp')::int, greatest(0, lv * 100 - 1)), 'bloodSpent', coalesce((e->>'bloodSpent')::int, 0) + blood);
  if lv >= cap then e := e || jsonb_build_object('exp', 0); end if;
  owned := jsonb_set(owned, array[i::text], e);
  d := _story_save(uid, jsonb_set(d, '{owned}', owned));
  return jsonb_build_object('data', d, 'from', from_lv, 'level', lv, 'cap', cap, 'requested', p_levels, 'gained', k, 'gold', gold, 'blood', blood, 'wallet', w);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.story_card_levelup(text, int) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.story_card_levelup(text, int) to authenticated;$vr_statement$;
  execute $vr_statement$-- 3) EX 합성 감싸기: 이상한 조각 차감 후 원래 합성
do $$
declare src text;
begin
  select prosrc into src from pg_proc where oid = to_regprocedure('public.story_merge(text,text)');
  if src is not null and src not like '%phaseE_4 wrapper%' then
    drop function if exists public._story_merge_e0(text, text);
    alter function public.story_merge(text, text) rename to _story_merge_e0;
  end if;
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._story_merge_e0(text, text) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$create or replace function public.story_merge(p_target text, p_material text) returns jsonb language plpgsql security definer set search_path = public as $$
-- phaseE_4 wrapper
declare uid uuid := auth.uid(); d jsonb; e jsonb; g text; ex int; cost int; r jsonb; w jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  select data into d from story_progress where user_id = uid for update;
  select x.e into e from jsonb_array_elements(_story_owned(coalesce(d, '{}'::jsonb))) x(e) where x.e->>'uid' = p_target;
  if e is null then raise exception 'card not owned'; end if;
  select grade into g from story_card_pool where id = e->>'id';
  g := coalesce(g, 'NORMAL'); ex := greatest(0, coalesce((e->>'ex')::int, 0));
  if ex >= _story_max_ex(g) then raise exception 'max ex'; end if;
  cost := _merge_shard_cost(g, ex + 1);
  w := _wallet_add(uid, jsonb_build_object('shard', -cost), 'card_merge');   -- 부족하면 'not enough shard'
  r := _story_merge_e0(p_target, p_material);                              -- 실패하면 조각 차감도 롤백
  return r || jsonb_build_object('shard', cost, 'wallet', w);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.story_merge(text, text) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.story_merge(text, text) to authenticated;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: phaseE_5.sql =====
-- ⚠ 다시 돌리지 마세요, 최신 아님 (일부): 이 파일의 story_sweep 는 뒤 파일에서 다시 정의됨. 이 파일을 다시 돌리면 예전 것으로 되돌아가요. supabase/README.md 참고
-- phaseE_5.sql — 소탕 (스토리 반복 클리어 자동 정산)
-- 실행 순서: phaseE_2 → phaseE_3 → (phaseE_4) → phaseE_5. 여러 번 실행해도 안전.
-- 조건: 플레이어 Lv5 이상(_player_unlock_level('sweep')), 이미 클리어한 스토리 페이즈만, 1/5/10회.
-- 1회당 행동력 _stamina_cost (6). 보상 = 반복 클리어와 동일 (골드·순수한 피·이상한 조각/영혼 확률·플레이어 XP).
-- 첫 클리어 보상 없음, 카드 전투 EXP 없음, 퀘스트 소탕 없음.
-- 확인용: select public.sweep_info();

create or replace function public.story_sweep(p_chapter int, p_phase int, p_runs int default 1) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb; cfg story_phase_config; cost int; xp int; up jsonb; dr jsonb;
  tot jsonb := '{"gold":0,"blood":0,"shard":0,"soul":0}'::jsonb; runs jsonb := '[]'::jsonb; k text; w jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  if p_runs is null or p_runs not in (1, 5, 10) then raise exception 'invalid runs'; end if;
  if not _player_unlocked(uid, 'sweep') then raise exception 'sweep locked (player Lv%)', _player_unlock_level('sweep'); end if;
  select * into cfg from story_phase_config where chapter = p_chapter and phase = p_phase;
  if not found then raise exception 'unknown phase'; end if;
  select data into d from story_progress where user_id = uid for update;
  if not (coalesce(d->'cleared'->(p_chapter::text), '[]'::jsonb) @> to_jsonb(p_phase)) then raise exception 'not cleared'; end if;
  cost := _stamina_cost(p_chapter, p_phase);
  perform _player_stamina_add(uid, -cost * p_runs);   -- 부족하면 'not enough stamina' (전체 롤백)
  for i in 1..p_runs loop
    dr := _story_drop_calc(p_chapter, coalesce(cfg.type, 'normal'), false, cost, random()::numeric, random()::numeric);
    runs := runs || dr;
    foreach k in array array['gold','blood','shard','soul'] loop
      tot := jsonb_set(tot, array[k], to_jsonb((tot->>k)::int + coalesce((dr->>k)::int, 0)));
    end loop;
  end loop;
  w := _wallet_add(uid, tot, 'story_sweep');
  xp := cost * p_runs * _player_xp_per_stamina();
  up := _player_add_xp(uid, xp, true);
  -- 조직 의뢰 진행 (guild2.sql): 소탕 1회 = 페이즈 1 · 행동력 · 보스
  if to_regprocedure('public._guild_event(uuid,text,integer)') is not null then
    perform _guild_event(uid, 'phase', p_runs); perform _guild_event(uid, 'stamina', cost * p_runs);
    if cfg.type = 'boss' then perform _guild_event(uid, 'boss', p_runs); end if;
  end if;
  return jsonb_build_object('ok', true, 'chapter', p_chapter, 'phase', p_phase, 'runs', p_runs, 'stamina', cost * p_runs,
    'drops', tot, 'per_run', runs, 'wallet', w,
    'player', _player_json(uid) || jsonb_build_object('gained_xp', xp, 'levelups', up->'levelups', 'levelup_gold', up->'gold'));
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.story_sweep(int, int, int) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.story_sweep(int, int, int) to authenticated;$vr_statement$;
  execute $vr_statement$-- 탐침: 조건·비용·예상 보상
create or replace function public.sweep_info() returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('ok', true, 'version', 5, 'unlock_level', _player_unlock_level('sweep'), 'runs', jsonb_build_array(1, 5, 10),
    'stamina_per_run', _stamina_cost(0, 0), 'xp_per_run', _stamina_cost(0, 0) * _player_xp_per_stamina(),
    'ch1_normal_run', _story_drop_calc(1, 'normal', false, 6, 0.99, 0.99), 'shard_chance', 0.3, 'soul_chance_ch5plus', 0.2)
$$;$vr_statement$;
  execute $vr_statement$revoke all on function public.sweep_info() from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.sweep_info() to authenticated;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: quest_sweep.sql =====
-- ⚠ 다시 돌리지 마세요, 최신 아님 (일부): 이 파일의 quest_sweep_complete, quest_sweep_info, quest_sweep_start 는 뒤 파일에서 다시 정의됨. 이 파일을 다시 돌리면 예전 것으로 되돌아가요. supabase/README.md 참고
-- =====================================================================
-- 시련의 탑 소탕 — quest.sql, phaseE_3.sql 다음에 실행. 여러 번 실행해도 안전
-- 규칙: 다음 층(최고 층 + 1)부터 연속된 일반 층만 자동 클리어. 보스 층(10의 배수)은 직접 싸워야 함. 행동력 없음.
-- 흐름(quest_start / quest_complete 와 같은 방식):
--   quest_sweep_start()           → 시작 층·멈출 보스 층 기록 (battle = { sweep, from, boss, at })
--   (클라이언트가 내 덱으로 전투 엔진을 화면 없이 돌림, 층마다 최소 _quest_sweep_secs() 초)
--   quest_sweep_complete(p_to, p_stats) → 시간·범위 확인 후 from..p_to 층을 첫 클리어 처리 (보상 = quest_complete 첫 클리어와 동일)
-- 확인용: select public.quest_sweep_info();
-- =====================================================================

create or replace function public._quest_sweep_secs() returns numeric language sql immutable as $$ select 1.0 $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._quest_sweep_secs() from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$create or replace function public.quest_sweep_info() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); r quest_progress; f int; boss int;
begin
  if uid is null then raise exception 'login required'; end if;
  select * into r from quest_progress where user_id = uid;
  f := coalesce(r.best_floor, 0) + 1; boss := ((f + 9) / 10) * 10;
  return jsonb_build_object('ok', true, 'from', f, 'boss', least(boss, _quest_max_floor()), 'max_floors', greatest(0, least(boss, _quest_max_floor() + 1) - f),
    'secs_per_floor', _quest_sweep_secs(), 'stamina', 0, 'boss_every', 10);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.quest_sweep_info() from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.quest_sweep_info() to authenticated;$vr_statement$;
  execute $vr_statement$create or replace function public.quest_sweep_start() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); r quest_progress; f int; boss int;
begin
  r := _quest_row(uid);
  f := r.best_floor + 1; boss := ((f + 9) / 10) * 10;
  if f > _quest_max_floor() then raise exception 'tower complete'; end if;
  if f % 10 = 0 then raise exception 'boss floor'; end if;
  update quest_progress set battle = jsonb_build_object('sweep', true, 'from', f, 'boss', boss, 'at', extract(epoch from clock_timestamp())), updated_at = now() where user_id = uid;
  return jsonb_build_object('ok', true, 'from', f, 'boss', boss, 'last', least(boss - 1, _quest_max_floor()), 'secs_per_floor', _quest_sweep_secs());
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.quest_sweep_start() from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.quest_sweep_start() to authenticated;$vr_statement$;
  execute $vr_statement$-- p_to: 마지막으로 이긴 층 (from-1 이면 하나도 못 이김). p_stats: { turns: [층별 턴 수] }
create or replace function public.quest_sweep_complete(p_to int, p_stats jsonb default '{}'::jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); r quest_progress; b jsonb; f int; n int; fl int; rw jsonb; cur jsonb; t int := 0; tk int := null;
  tot jsonb := '{}'::jsonb; floors jsonb := '[]'::jsonb; k text; turns jsonb := coalesce(p_stats->'turns', '[]'::jsonb);
begin
  r := _quest_row(uid);
  b := r.battle;
  if b is null or not coalesce((b->>'sweep')::boolean, false) then raise exception 'sweep not started'; end if;
  f := (b->>'from')::int;
  if f <> r.best_floor + 1 then raise exception 'sweep stale'; end if;
  if p_to is null or p_to < f - 1 or p_to >= (b->>'boss')::int or p_to > _quest_max_floor() then raise exception 'invalid range'; end if;
  n := p_to - f + 1;
  if extract(epoch from clock_timestamp()) - (b->>'at')::numeric < n * _quest_sweep_secs() then raise exception 'too fast'; end if;
  if jsonb_typeof(turns) <> 'array' or jsonb_array_length(turns) < n
     or exists (select 1 from jsonb_array_elements(turns) x(v) where jsonb_typeof(x.v) <> 'number' or (x.v)::int < 1 or (x.v)::int > 40) then raise exception 'invalid stats'; end if;
  for fl in f .. p_to loop
    rw := _quest_reward(fl);
    t := t + coalesce((rw->>'tickets')::int, 0);
    cur := case when to_regprocedure('public._quest_currency(integer)') is not null then _quest_currency(fl) else '{}'::jsonb end;
    floors := floors || jsonb_build_object('floor', fl, 'reward', rw, 'currency', cur);
    for k in select jsonb_object_keys(rw || cur) loop
      tot := tot || jsonb_build_object(k, coalesce((tot->>k)::int, 0) + coalesce((rw->>k)::int, 0) + coalesce((cur->>k)::int, 0));
    end loop;
  end loop;
  if t > 0 then
    insert into story_gacha (user_id, last_draw) values (uid, (now() at time zone 'Asia/Seoul')::date - 1) on conflict (user_id) do nothing;
    update story_gacha set tickets = tickets + t, updated_at = now() where user_id = uid returning tickets into tk;
  end if;
  if n > 0 and to_regprocedure('public._wallet_add(uuid,jsonb,text)') is not null then
    perform _wallet_add(uid, tot - 'tickets', 'quest_sweep');
  end if;
  update quest_progress set battle = null, clears = clears + n, best_floor = greatest(best_floor, p_to),
    rewards = (select jsonb_object_agg(x.k, coalesce((rewards->>x.k)::int, 0) + coalesce((tot->>x.k)::int, 0)) from unnest(array['tickets', 'gold', 'blood', 'shard', 'soul']) x(k)),
    updated_at = now()
  where user_id = uid;
  return jsonb_build_object('ok', true, 'from', f, 'to', p_to, 'cleared', n, 'boss', (b->>'boss')::int, 'best_floor', greatest(r.best_floor, p_to),
    'total', tot, 'floors', floors, 'tickets', tk);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.quest_sweep_complete(int, jsonb) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.quest_sweep_complete(int, jsonb) to authenticated;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: gallery_owned.sql =====
-- 갤러리 자동 등록: 스토리·뽑기로 얻은 보유 카드(story_progress.data.owned)를 갤러리에 등록
-- 1) 트리거: story_progress 저장(insert/update) 때 새로 생긴 보유 카드 id 를 gallery 에 추가 (이미 있으면 그대로)
-- 2) 백필: 지금 보유 중인 카드 전부 1회 등록
-- 여러 번 실행해도 안전. 왕관 등급(mvp_count)은 건드리지 않음.
-- 등록 행: count 0 (아케이드 수집 횟수 0 = 보유로만 등록), mvp_count 0, first_at = now(). last_at 은 1분 전으로 둬서 gallery_register 의 15초 도배 방지에 걸리지 않게 함.

create or replace function public._gallery_sync_owned(p_uid uuid, p_data jsonb)
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if p_uid is null or p_data is null or jsonb_typeof(p_data->'owned') <> 'array' then return 0; end if;
  with ids as (
    select distinct o->>'id' as id from jsonb_array_elements(p_data->'owned') o
    where jsonb_typeof(o) = 'object' and char_length(coalesce(o->>'id', '')) between 1 and 40
  ), ins as (
    insert into public.gallery (user_id, card_id, count, mvp_count, first_at, last_at)
    select p_uid, id, 0, 0, now(), now() - interval '1 minute' from ids
    on conflict (user_id, card_id) do nothing
    returning 1
  ) select count(*) into n from ins;
  return n;
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._gallery_sync_owned(uuid, jsonb) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$create or replace function public._gallery_owned_trg()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' and new.data->'owned' is not distinct from old.data->'owned' then return new; end if;
  perform public._gallery_sync_owned(new.user_id, new.data);
  return new;
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._gallery_owned_trg() from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$drop trigger if exists story_progress_gallery on public.story_progress;$vr_statement$;
  execute $vr_statement$create trigger story_progress_gallery after insert or update of data on public.story_progress
  for each row execute function public._gallery_owned_trg();$vr_statement$;
  execute $vr_statement$-- 이전 버전(count 1)으로 자동 등록된 행 보정: 자동 등록 표시(last_at = first_at - 1분)이고 그 뒤 아케이드 수집이 없던 행만 0 으로
update public.gallery set count = 0 where count = 1 and mvp_count = 0 and last_at = first_at - interval '1 minute';$vr_statement$;
  execute $vr_statement$-- 백필 (기존 보유 카드)
select public._gallery_sync_owned(user_id, data) from public.story_progress;$vr_statement$;
  execute $vr_statement$-- 확인용: 내 갤러리 중 보유 카드로 등록된 수
-- select count(*) from public.gallery g where g.user_id = auth.uid();


-- ===== SOURCE: gallery_register_new.sql =====
-- 아케이드 판 종료 'NEW!' 수정: 갤러리 행이 아예 없던 카드만 NEW.
-- 보유(스토리·뽑기) 자동 등록으로 count 0 행이 이미 있는 카드는 아케이드 첫 수집 시 count 1 이 되지만 NEW 아님.
-- 시그니처·권한·15초 도배 방지는 그대로. 여러 번 실행해도 안전 (create or replace).
-- 함께 수정: MVP 없이(p_mvp null) 부른 판은 mvp_count 가 null 이 되어 not-null 오류 → coalesce(…, 0).
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
  returning g.card_id, g.count, g.mvp_count, (g.xmax = 0);   -- 새로 insert 된 행만 NEW (보유 자동 등록 count 0 행은 update → NEW 아님)
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.gallery_register(text[], text) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.gallery_register(text[], text) to authenticated;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: story_ch3.sql =====
-- =====================================================================
-- 스토리 챕터 3 「Just For YOU」 (단일 루트: 조윤하, 페이즈 10개, 페이즈마다 적 5명)
-- 사용법: Supabase SQL Editor 에 붙여넣고 Run. 여러 번 실행해도 안전. service_role 키 필요 없음.
-- 필요 조건: story_ch2.sql 까지 적용된 상태
-- 챕터 2와 같은 규칙: 카드 보상 없이 스탯 포인트 (일반 3, 보스 5). 재화 드롭·소탕·소환권·행동력은 기존 함수가 챕터 번호로 처리
-- 페이즈 열림: 챕터 2 전체 클리어 후 (story_start_phase 의 기존 조건)
-- =====================================================================
insert into public.story_phase_config (chapter, phase, type, points, reward_grade, enemy_count) values
  (3,1,'normal',3,null,5), (3,2,'normal',3,null,5), (3,3,'normal',3,null,5), (3,4,'normal',3,null,5), (3,5,'normal',3,null,5),
  (3,6,'normal',3,null,5), (3,7,'normal',3,null,5), (3,8,'normal',3,null,5), (3,9,'normal',3,null,5), (3,10,'boss',5,null,5)
on conflict (chapter, phase) do update set type = excluded.type, points = excluded.points, reward_grade = excluded.reward_grade, enemy_count = excluded.enemy_count;$vr_statement$;
  execute $vr_statement$-- 확인: select chapter, count(*) from public.story_phase_config group by chapter order by chapter;  → 3 | 10


-- ===== SOURCE: phaseE_6.sql =====
-- =====================================================================
-- 단계 E-6: 스킬 레벨 (각성자의 혼 + 골드)
-- Supabase SQL Editor 에서 실행. 여러 번 실행해도 안전
-- 선행: story_*.sql, phaseE_1.sql (지갑), phaseE_3.sql (분해), phaseE_4.sql (비용 도우미 _lv_cost_g)
--
-- 규칙
--   액티브 스킬만 Lv1~10 (패시브 제외). 저장: story_progress.data.owned[i].skillLv = {"1":3,"2":1} (키 = 카드 스킬 순번 1부터, 없으면 Lv1)
--   효과(클라이언트 js/skills.js): 레벨당 +3% (Lv10 +27%) 스킬 피해·회복·버프/디버프 ATK/DEF 수치 + 확률 레벨당 +0.3%p (Lv10 +2.7%p). 지속·MP 그대로
--   쿨타임: Lv5 −1, Lv10 −1 더 (최소 1)
--   비용 Lv L → L+1: 혼 = 등급 기본 × ceil(L/2),  골드 = 등급 값 × L × 100  (피 없음)
--     혼 기본  N1 · R2 · HR3 · SR5 · UR8 · MR12      골드 값 = 카드 레벨업과 같은 N1 R1.5 HR2 SR3 UR4 MR6
--   해금: 카드 레벨 ≥ 스킬 해금 레벨 (story_skill_meta)
--   합성: 대상 skillLv 유지 (기존 합성이 그대로 둠), 재료의 skillLv 는 사라짐 (환급 없음)
--   분해: 쓴 혼(soulSpent)의 50% 환급 (카드별 내림), 골드 환급 없음
-- 구조: 기존 story_dismantle 을 _story_dismantle_e5 로 보관하고 같은 이름으로 감쌈 (phaseE_3.sql 재실행 후엔 이 파일도 다시 실행)
-- 확인용: select public.skill_cost_table();
-- =====================================================================

-- 1) 스킬 메타 (액티브 스킬 해금 레벨). data/skills.json 에서 생성
create table if not exists public.story_skill_meta (
  card_id text not null,
  idx     int  not null check (idx >= 1),
  unlock  int  not null default 1,
  primary key (card_id, idx)
);$vr_statement$;
  execute $vr_statement$alter table public.story_skill_meta enable row level security;$vr_statement$;
  execute $vr_statement$revoke all on public.story_skill_meta from anon, authenticated;$vr_statement$;
  execute $vr_statement$insert into public.story_skill_meta (card_id, idx, unlock) values
  ('10051',1,2),
  ('10051',2,5),
  ('10060',1,2),
  ('10060',2,5),
  ('10054',1,2),
  ('10054',3,7),
  ('10053',1,2),
  ('10053',2,5),
  ('10053',3,7),
  ('10176',2,5),
  ('10304',1,2),
  ('10304',2,5),
  ('10304',3,7),
  ('10435',1,2),
  ('10435',2,5),
  ('10435',3,7),
  ('10325',1,2),
  ('10325',2,5),
  ('10325',3,7),
  ('10323',1,2),
  ('10323',2,5),
  ('10323',3,7),
  ('10322',1,2),
  ('10322',2,5),
  ('10359',1,2),
  ('10359',2,5),
  ('10062',2,5),
  ('10324',1,2),
  ('10324',2,5),
  ('10331',1,2),
  ('10331',2,5),
  ('10311',1,2),
  ('10311',2,5),
  ('10311',3,7),
  ('10312',1,2),
  ('10312',2,5),
  ('10058',1,2),
  ('10058',2,5),
  ('10058',3,7),
  ('10291',1,2),
  ('10291',2,5),
  ('10291',3,7),
  ('10326',1,2),
  ('10326',2,5),
  ('10326',3,7),
  ('10358',1,2),
  ('10358',2,5),
  ('10358',3,7),
  ('10118',1,3),
  ('10118',2,5),
  ('10019',1,1), ('10018',1,1), ('10299',1,1), ('10074',1,1),
  ('10200',1,3),
  ('10200',2,5),
  ('10418',1,3),
  ('10418',2,5),
  ('10415',1,3),
  ('10415',2,7),
  ('10317',1,3),
  ('10317',2,5),
  ('10052',1,3),
  ('10052',2,5),
  ('10341',1,3),
  ('10341',2,5),
  ('10217',1,5),
  ('10217',2,5),
  ('10216',1,3),
  ('10216',2,5),
  ('10392',1,2),
  ('10392',2,5),
  ('10399',1,2),
  ('10399',2,5),
  ('10383',1,2),
  ('10383',2,7),
  ('10213',1,2),
  ('10070',1,2),
  ('10070',2,5),
  ('10072',1,5),
  ('10413',1,5),
  ('10414',1,5),
  ('10110',1,5),
  ('10207',1,5),
  ('10208',1,5),
  ('10126',1,5),
  ('10393',1,5),
  ('10073',1,5),
  ('10229',1,5),
  ('10257',1,5),
  ('10256',1,3),
  ('10265',1,3),
  ('10108',2,5),
  ('10298',1,2),
  ('10081',1,2),
  ('10224',1,2),
  ('10045',1,2),
  ('10045',2,5),
  ('10189',1,2),
  ('10189',2,5),
  ('10117',1,2),
  ('10117',2,5),
  ('10255',2,5),
  ('10333',1,2),
  ('10333',2,5),
  ('10109',1,2),
  ('10109',2,5),
  ('10236',1,2),
  ('10236',2,5),
  ('10281',1,2),
  ('10281',2,5),
  ('10024',1,2),
  ('10068',1,2),
  ('10013',1,2),
  ('10013',2,5),
  ('10067',1,2),
  ('10067',2,5),
  ('10321',1,2),
  ('10321',2,5),
  ('10186',1,2),
  ('10186',2,5),
  ('10183',1,2),
  ('10025',1,2),
  ('10025',2,5),
  ('10329',1,2),
  ('10329',2,5),
  ('10112',1,2),
  ('10369',1,2),
  ('10369',2,5),
  ('10061',1,2),
  ('10061',2,5),
  ('10354',1,2),
  ('10354',2,5),
  ('10181',1,2),
  ('10181',2,5),
  ('10373',1,2),
  ('10373',2,5),
  ('10465',1,2),
  ('10465',2,5),
  ('10465',3,1),
  ('10440',1,2),
  ('10440',2,5),
  ('10439',2,2),
  ('10127',1,2),
  ('10127',2,5)
on conflict (card_id, idx) do update set unlock = excluded.unlock;$vr_statement$;
  execute $vr_statement$-- 2) 수치
create or replace function public._skill_lv_max() returns int language sql immutable as $$ select 10 $$;$vr_statement$;
  execute $vr_statement$create or replace function public._skill_soul_base(p_grade text) returns int language sql immutable as $$
  select case p_grade when 'NORMAL' then 1 when 'RARE' then 2 when 'HIGH RARE' then 3 when 'SUPER RARE' then 5 when 'ULTRA RARE' then 8 when 'MYTHIC RARE' then 12 else 1 end $$;$vr_statement$;
  execute $vr_statement$-- 레벨 L 에서 L+1 로 올리는 비용
create or replace function public._skill_cost(p_grade text, p_level int) returns jsonb language sql immutable as $$
  select jsonb_build_object('soul', _skill_soul_base(p_grade) * ceil(p_level / 2.0)::int, 'gold', ceil(_lv_cost_g(p_grade) * p_level * 100)::int) $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._skill_lv_max(), public._skill_soul_base(text), public._skill_cost(text, int) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$-- 공개: 비용표 (탐침 겸용)
create or replace function public.skill_cost_table() returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('ok', true, 'version', 6, 'max', _skill_lv_max(), 'step_pct', 3, 'cd_minus_at', jsonb_build_array(5, 10),
    'skills', (select count(*) from story_skill_meta),
    'grades', jsonb_object_agg(g, jsonb_build_object('soul', _skill_soul_base(g), 'g', _lv_cost_g(g), 'lv1', _skill_cost(g, 1),
      'total', (select jsonb_build_object('soul', sum((_skill_cost(g, l)->>'soul')::int), 'gold', sum((_skill_cost(g, l)->>'gold')::int)) from generate_series(1, _skill_lv_max() - 1) l))))
  from unnest(array['NORMAL','RARE','HIGH RARE','SUPER RARE','ULTRA RARE','MYTHIC RARE']) g
$$;$vr_statement$;
  execute $vr_statement$revoke all on function public.skill_cost_table() from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.skill_cost_table() to authenticated;$vr_statement$;
  execute $vr_statement$-- 3) 스킬 레벨업: p_uid 카드의 p_skill 번째(1부터) 액티브 스킬을 최대 p_levels 단계 (1~9). 재화가 허락하는 만큼만, 1단계도 못 올리면 'not enough ...'
create or replace function public.story_skill_levelup(p_uid text, p_skill int, p_levels int default 1) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb; owned jsonb; i int; e jsonb; g text; ul int; lv int; from_lv int; k int := 0; gold int := 0; soul int := 0; c jsonb; w jsonb; hg bigint := 0; hs bigint := 0; sl jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  if p_levels is null or p_levels < 1 or p_levels > 9 then raise exception 'invalid levels'; end if;
  if p_skill is null or p_skill < 1 then raise exception 'invalid skill'; end if;
  d := _story_lock(uid);
  owned := _story_owned(d);
  select (n - 1)::int into i from jsonb_array_elements(owned) with ordinality x(e, n) where x.e->>'uid' = p_uid;
  if i is null then raise exception 'card not owned'; end if;
  e := _story_norm(owned->i);
  select m.unlock into ul from story_skill_meta m where m.card_id = e->>'id' and m.idx = p_skill;
  if ul is null then raise exception 'invalid skill'; end if;            -- 없는 스킬·패시브
  if (e->>'level')::int < ul then raise exception 'skill locked'; end if;
  select grade into g from story_card_pool where id = e->>'id';
  g := coalesce(g, 'NORMAL');
  sl := case when jsonb_typeof(e->'skillLv') = 'object' then e->'skillLv' else '{}'::jsonb end;
  lv := greatest(1, least(_skill_lv_max(), coalesce((sl->>p_skill::text)::int, 1))); from_lv := lv;
  if lv >= _skill_lv_max() then raise exception 'max skill level'; end if;
  select coalesce(pw.gold, 0), coalesce(pw.soul, 0) into hg, hs from player_wallet pw where pw.user_id = uid;
  hg := coalesce(hg, 0); hs := coalesce(hs, 0);
  while k < p_levels and lv < _skill_lv_max() loop
    c := _skill_cost(g, lv);
    if gold + (c->>'gold')::int > hg or soul + (c->>'soul')::int > hs then
      if k = 0 then raise exception 'not enough %', case when soul + (c->>'soul')::int > hs then 'soul' else 'gold' end; end if;
      exit;
    end if;
    gold := gold + (c->>'gold')::int; soul := soul + (c->>'soul')::int;
    lv := lv + 1; k := k + 1;
  end loop;
  w := _wallet_add(uid, jsonb_build_object('gold', -gold, 'soul', -soul), 'skill_levelup');
  e := e || jsonb_build_object('skillLv', sl || jsonb_build_object(p_skill::text, lv), 'soulSpent', coalesce((e->>'soulSpent')::int, 0) + soul);
  owned := jsonb_set(owned, array[i::text], e);
  d := _story_save(uid, jsonb_set(d, '{owned}', owned));
  return jsonb_build_object('data', d, 'skill', p_skill, 'from', from_lv, 'level', lv, 'gained', k, 'gold', gold, 'soul', soul, 'wallet', w);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.story_skill_levelup(text, int, int) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.story_skill_levelup(text, int, int) to authenticated;$vr_statement$;
  execute $vr_statement$-- 4) 분해 감싸기: 원래 분해 후 쓴 혼 50% 환급
do $$
declare src text;
begin
  select prosrc into src from pg_proc where oid = to_regprocedure('public.story_dismantle(text[])');
  if src is not null and src not like '%phaseE_6 wrapper%' then
    drop function if exists public._story_dismantle_e5(text[]);
    alter function public.story_dismantle(text[]) rename to _story_dismantle_e5;
  end if;
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._story_dismantle_e5(text[]) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$create or replace function public.story_dismantle(p_uids text[]) returns jsonb language plpgsql security definer set search_path = public as $$
-- phaseE_6 wrapper
declare uid uuid := auth.uid(); d jsonb; back int := 0; r jsonb; w jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  select data into d from story_progress where user_id = uid for update;
  select coalesce(sum(floor(greatest(0, coalesce((x.e->>'soulSpent')::int, 0)) * 0.5)), 0)::int into back
    from jsonb_array_elements(_story_owned(coalesce(d, '{}'::jsonb))) x(e) where x.e->>'uid' = any(p_uids);
  r := _story_dismantle_e5(p_uids);                                         -- 검증 실패하면 전부 롤백
  if back > 0 then
    w := _wallet_add(uid, jsonb_build_object('soul', back), 'dismantle_skill');
    r := r || jsonb_build_object('soul', coalesce((r->>'soul')::int, 0) + back, 'skill_soul', back, 'wallet', w);
  end if;
  return r;
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.story_dismantle(text[]) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.story_dismantle(text[]) to authenticated;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: story_ch4.sql =====
-- =====================================================================
-- 스토리 챕터 4 「카르밀라」 (단일 루트: 이민채, 페이즈 10개, 페이즈마다 적 5명)
-- 사용법: Supabase SQL Editor 에 붙여넣고 Run. 여러 번 실행해도 안전. service_role 키 필요 없음.
-- 필요 조건: story_ch3.sql 까지 적용된 상태
-- 챕터 2·3과 같은 규칙: 카드 보상 없이 스탯 포인트 (일반 3, 마지막 페이즈 5). 재화 드롭·소탕·소환권·행동력은 기존 함수가 챕터 번호로 처리
-- 페이즈 열림: 챕터 3 전체 클리어 후 (story_start_phase 의 기존 조건)
-- NPC 카드 [각성] 이민채 (10301) 는 스토리 적 전용: 뽑기 풀(story_card_pool)에 절대 넣지 않음
-- =====================================================================
insert into public.story_phase_config (chapter, phase, type, points, reward_grade, enemy_count) values
  (4,1,'normal',3,null,5), (4,2,'normal',3,null,5), (4,3,'normal',3,null,5), (4,4,'normal',3,null,5), (4,5,'normal',3,null,5),
  (4,6,'normal',3,null,5), (4,7,'normal',3,null,5), (4,8,'normal',3,null,5), (4,9,'normal',3,null,5), (4,10,'boss',5,null,5)
on conflict (chapter, phase) do update set type = excluded.type, points = excluded.points, reward_grade = excluded.reward_grade, enemy_count = excluded.enemy_count;$vr_statement$;
  execute $vr_statement$-- NPC 는 뽑기·보상에 나오지 않게 (혹시 들어가 있으면 제거)
delete from public.story_card_pool where id in ('10301');$vr_statement$;
  execute $vr_statement$-- 확인: select chapter, count(*) from public.story_phase_config group by chapter order by chapter;  → 4 | 10


-- ===== SOURCE: story_ch5.sql =====
-- =====================================================================
-- 스토리 챕터 5 「영원히 멈추지 않는 비」 (단일 루트: 한겨울 · 10페이즈 진하린, 페이즈 10개, 페이즈마다 적 5명)
-- 사용법: Supabase SQL Editor 에 붙여넣고 Run. 여러 번 실행해도 안전. service_role 키 필요 없음.
-- 필요 조건: story_ch4.sql 까지 적용된 상태
-- 챕터 2~4와 같은 규칙: 카드 보상 없이 스탯 포인트 (일반 3, 마지막 페이즈 5). 재화 드롭·소탕·소환권·행동력은 기존 함수가 챕터 번호로 처리
-- 페이즈 열림: 챕터 4 전체 클리어 후 (story_start_phase 의 기존 조건)
-- =====================================================================
insert into public.story_phase_config (chapter, phase, type, points, reward_grade, enemy_count) values
  (5,1,'normal',3,null,5), (5,2,'normal',3,null,5), (5,3,'normal',3,null,5), (5,4,'normal',3,null,5), (5,5,'normal',3,null,5),
  (5,6,'normal',3,null,5), (5,7,'normal',3,null,5), (5,8,'normal',3,null,5), (5,9,'normal',3,null,5), (5,10,'boss',5,null,5)
on conflict (chapter, phase) do update set type = excluded.type, points = excluded.points, reward_grade = excluded.reward_grade, enemy_count = excluded.enemy_count;$vr_statement$;
  execute $vr_statement$-- 확인: select chapter, count(*) from public.story_phase_config group by chapter order by chapter;  → 5 | 10
-- 정아영(N) 3·10페이즈 리더 능력치·10페이즈 보스전 규칙은 클라이언트 데이터(js/story-data-ch5.js)에만 있음: 서버 SQL 변경 없음


-- ===== SOURCE: player_xp_x3.sql =====
-- 플레이어(유저) 레벨 필요 경험치 3배 (2026-10-23)
-- 레벨업마다 행동력이 최대치만큼 채워져 행동력이 계속 넘쳐서, 레벨업 속도를 1/3로.
-- 기존: Lv n → n+1 필요 = 100 + 20(n-1).  변경: 3 × (100 + 20(n-1)).
-- 기존 유저: player_state 의 level 은 그대로, xp(현재 레벨 안에서 모은 양)도 그대로. 다음 레벨까지 필요량만 늘어남 → 레벨이 내려가는 사람 없음.
-- 여러 번 실행해도 안전 (함수 교체만).
create or replace function public._player_xp_need(p_level int) returns int language sql immutable as $$ select 3 * (100 + 20 * (greatest(p_level, 1) - 1)) $$;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: story_ch6.sql =====
-- =====================================================================
-- 스토리 챕터 6 「마지막 대답」 (단일 루트: 문지아 · 1~4페이즈 문지예/문지철, 페이즈 10개. 1페이즈 적 3명, 나머지 5명)
-- 사용법: Supabase SQL Editor 에 붙여넣고 Run. 여러 번 실행해도 안전. service_role 키 필요 없음.
-- 필요 조건: story_ch5.sql 까지 적용된 상태
-- 챕터 2~5와 같은 규칙: 카드 보상 없이 스탯 포인트 (일반 3, 마지막 페이즈 5). 재화 드롭·소탕·소환권·행동력은 기존 함수가 챕터 번호로 처리
-- 페이즈 열림: 챕터 5 전체 클리어 후 (story_start_phase 의 기존 조건)
-- =====================================================================
insert into public.story_phase_config (chapter, phase, type, points, reward_grade, enemy_count) values
  (6,1,'normal',3,null,3), (6,2,'normal',3,null,5), (6,3,'normal',3,null,5), (6,4,'normal',3,null,5), (6,5,'normal',3,null,5),
  (6,6,'normal',3,null,5), (6,7,'normal',3,null,5), (6,8,'normal',3,null,5), (6,9,'normal',3,null,5), (6,10,'boss',5,null,5)
on conflict (chapter, phase) do update set type = excluded.type, points = excluded.points, reward_grade = excluded.reward_grade, enemy_count = excluded.enemy_count;$vr_statement$;
  execute $vr_statement$-- 확인: select chapter, count(*) from public.story_phase_config group by chapter order by chapter;  → 6 | 10
-- 같은 NPC 적 여러 명·출전 금지·필수 출전 패배 규칙·경고 카드는 클라이언트 데이터(js/story-data-ch6.js)에만 있음


-- ===== SOURCE: tower_v2.sql =====
-- =====================================================================
-- 시련의 탑 v2: 탑 6종 (normal 시련의 탑 · wind 바람의 계곡 · ice 얼음의 숲 · fire 불의 절벽 · light 빛의 섬 · dark 어둠의 늪)
-- 사용법: Supabase SQL Editor 에 붙여넣고 Run. 여러 번 실행해도 안전 (진행 리셋은 처음 1회만). service_role 키 필요 없음.
-- 선행: quest.sql, quest_sweep.sql, phaseE_1~3.sql (지갑·재화)
--
-- 규칙 (모두 서버에서 확인)
--   층: 탑마다 1~350, 10층마다 보스(소탕 불가)
--   하루 제한 (KST 자정 기준, 소탕 포함, 이긴 층 수): normal 30 · 속성 탑 10
--   요일 (KST): normal 매일 · wind 월토일 · ice 화토일 · fire 수토일 · light 목토일 · dark 금토일
--   입장 유저 레벨 (player_state.level): normal 5 · wind/ice/fire 30 · light/dark 50
--   첫 클리어 보상: normal = 기존과 같음 (소환권 10층 5 / 50층 10 + 골드·피·조각·혼) · 속성 탑 = 골드·피·조각만
--   리셋: 기존 시련의 탑 진행(quest_progress.best_floor)은 0층으로 (처음 1회). 이미 받은 보상은 그대로 두고, 1층부터 첫 클리어 보상을 다시 줌
--         paid_floor = 첫 클리어 보상을 받은 최고 층. 층마다 한 번만 지급 (재실행해도 리셋·재지급 없음)
-- 새 RPC: tower_status() · tower_start(tower, floor) · tower_complete(tower, floor, stats) · tower_sweep_info(tower) · tower_sweep_start(tower) · tower_sweep_complete(tower, to, stats)
-- 기존 quest_* RPC 는 normal 탑으로 이어지는 래퍼 (예전 클라이언트 호환)
-- =====================================================================

-- 1) 진행 테이블 (탑마다 한 줄)
create table if not exists public.tower_progress (
  user_id     uuid not null references auth.users(id) on delete cascade,
  tower       text not null check (tower in ('normal', 'wind', 'ice', 'fire', 'light', 'dark')),
  best_floor  int not null default 0 check (best_floor >= 0),
  paid_floor  int not null default 0 check (paid_floor >= 0),   -- 첫 클리어 보상을 받은 최고 층 (층마다 한 번만)
  battle      jsonb,
  clears      int not null default 0,
  rewards     jsonb not null default '{}'::jsonb,
  day         date,                                             -- KST 날짜
  day_floors  int not null default 0,                           -- 그날 이긴 층 수 (소탕 포함)
  updated_at  timestamptz not null default now(),
  primary key (user_id, tower)
);$vr_statement$;
  execute $vr_statement$alter table public.tower_progress enable row level security;$vr_statement$;
  execute $vr_statement$drop policy if exists "tower_select_own" on public.tower_progress;$vr_statement$;
  execute $vr_statement$create policy "tower_select_own" on public.tower_progress for select using (user_id = auth.uid());$vr_statement$;
  execute $vr_statement$revoke insert, update, delete on public.tower_progress from anon, authenticated;$vr_statement$;
  execute $vr_statement$grant select on public.tower_progress to authenticated;$vr_statement$;
  execute $vr_statement$-- 2) 기존 진행 이전 + 리셋 (처음 1회: 이미 tower_progress 에 normal 줄이 있으면 건드리지 않음). 보상은 1층부터 다시
insert into public.tower_progress (user_id, tower, best_floor, paid_floor, clears, rewards)
select user_id, 'normal', 0, 0, clears, rewards from public.quest_progress
on conflict (user_id, tower) do nothing;$vr_statement$;
  execute $vr_statement$-- 3) 규칙 함수
create or replace function public._tower_ok(p text) returns boolean language sql immutable as $$ select p in ('normal', 'wind', 'ice', 'fire', 'light', 'dark') $$;$vr_statement$;
  execute $vr_statement$create or replace function public._tower_today() returns date language sql stable as $$ select (now() at time zone 'Asia/Seoul')::date $$;$vr_statement$;
  execute $vr_statement$create or replace function public._tower_dow() returns int language sql stable as $$ select extract(isodow from (now() at time zone 'Asia/Seoul'))::int $$;$vr_statement$;
  execute $vr_statement$-- 1 월 … 7 일
create or replace function public._tower_days(p text) returns int[] language sql immutable as $$
  select case p when 'normal' then array[1,2,3,4,5,6,7] when 'wind' then array[1,6,7] when 'ice' then array[2,6,7]
    when 'fire' then array[3,6,7] when 'light' then array[4,6,7] when 'dark' then array[5,6,7] end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._tower_daily(p text) returns int language sql immutable as $$ select case when p = 'normal' then 30 else 10 end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._tower_min_level(p text) returns int language sql immutable as $$ select case p when 'normal' then 5 when 'light' then 50 when 'dark' then 50 else 30 end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._tower_max_floor(p text) returns int language sql immutable as $$ select 350 $$;$vr_statement$;
  execute $vr_statement$create or replace function public._tower_reward(p text, f int) returns jsonb language sql immutable as $$
  select case when p = 'normal' then _quest_reward(f) else '{}'::jsonb end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._tower_currency(p text, f int) returns jsonb language sql immutable as $$
  select case when p = 'normal' then _quest_currency(f) else _quest_currency(f) - 'soul' end $$;$vr_statement$;
  execute $vr_statement$do $$ declare fn text; begin
  foreach fn in array array['_tower_ok(text)', '_tower_today()', '_tower_dow()', '_tower_days(text)', '_tower_daily(text)', '_tower_min_level(text)', '_tower_max_floor(text)', '_tower_reward(text,int)', '_tower_currency(text,int)'] loop
    execute format('revoke all on function public.%s from public, anon, authenticated', fn);
  end loop; end $$;$vr_statement$;
  execute $vr_statement$-- 줄 잠금 + 날짜 바뀌면 일일 카운트 0
create or replace function public._tower_row(uid uuid, p text) returns public.tower_progress language plpgsql set search_path = public as $$
declare r tower_progress;
begin
  if uid is null then raise exception 'login required'; end if;
  if not _tower_ok(p) then raise exception 'invalid tower'; end if;
  insert into tower_progress (user_id, tower) values (uid, p) on conflict (user_id, tower) do nothing;
  select * into r from tower_progress where user_id = uid and tower = p for update;
  if r.day is distinct from _tower_today() then
    update tower_progress set day = _tower_today(), day_floors = 0 where user_id = uid and tower = p returning * into r;
  end if;
  return r;
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._tower_row(uuid, text) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$-- 입장 확인 (요일 · 유저 레벨 · 일일 제한)
create or replace function public._tower_gate(uid uuid, p text, r public.tower_progress) returns void language plpgsql stable set search_path = public as $$
declare lv int;
begin
  if not (_tower_dow() = any(_tower_days(p))) then raise exception 'tower closed today'; end if;
  select level into lv from player_state where user_id = uid;
  if coalesce(lv, 1) < _tower_min_level(p) then raise exception 'level too low'; end if;
  if r.day_floors >= _tower_daily(p) then raise exception 'daily limit'; end if;
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._tower_gate(uuid, text, public.tower_progress) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$-- 첫 클리어 보상 지급 (paid_floor 초과 층만). 반환 { reward, currency, tickets }
create or replace function public._tower_pay(uid uuid, p text, f int) returns jsonb language plpgsql set search_path = public as $$
declare rw jsonb := _tower_reward(p, f); cur jsonb := _tower_currency(p, f); t int := coalesce((rw->>'tickets')::int, 0); tk int := null;
begin
  if t > 0 then
    insert into story_gacha (user_id, last_draw) values (uid, (now() at time zone 'Asia/Seoul')::date - 1) on conflict (user_id) do nothing;
    update story_gacha set tickets = tickets + t, updated_at = now() where user_id = uid returning tickets into tk;
  end if;
  if cur <> '{}'::jsonb then perform _wallet_add(uid, cur, 'tower_first_clear:' || p); end if;
  return jsonb_build_object('reward', rw, 'currency', cur, 'tickets', tk);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._tower_pay(uuid, text, int) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$-- 4) RPC
create or replace function public.tower_status() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); lv int; out jsonb := '{}'::jsonb; p text; r tower_progress; today date := _tower_today();
begin
  if uid is null then raise exception 'login required'; end if;
  select level into lv from player_state where user_id = uid;
  foreach p in array array['normal', 'wind', 'ice', 'fire', 'light', 'dark'] loop
    select * into r from tower_progress where user_id = uid and tower = p;
    out := out || jsonb_build_object(p, jsonb_build_object('best_floor', coalesce(r.best_floor, 0), 'paid_floor', coalesce(r.paid_floor, 0), 'max_floor', _tower_max_floor(p),
      'clears', coalesce(r.clears, 0), 'rewards', coalesce(r.rewards, '{}'::jsonb),
      'today', case when r.day = today then r.day_floors else 0 end, 'daily', _tower_daily(p),
      'open_today', _tower_dow() = any(_tower_days(p)), 'days', to_jsonb(_tower_days(p)), 'min_level', _tower_min_level(p), 'unlocked', coalesce(lv, 1) >= _tower_min_level(p)));
  end loop;
  return jsonb_build_object('ok', true, 'level', coalesce(lv, 1), 'dow', _tower_dow(), 'day', today, 'towers', out);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.tower_start(p_tower text, p_floor int) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); r tower_progress;
begin
  r := _tower_row(uid, p_tower);
  if p_floor is null or p_floor < 1 or p_floor > _tower_max_floor(p_tower) then raise exception 'invalid floor'; end if;
  if p_floor > r.best_floor + 1 then raise exception 'floor locked'; end if;
  perform _tower_gate(uid, p_tower, r);
  update tower_progress set battle = jsonb_build_object('floor', p_floor, 'at', (extract(epoch from clock_timestamp()))::bigint), updated_at = now() where user_id = uid and tower = p_tower;
  return jsonb_build_object('ok', true, 'tower', p_tower, 'floor', p_floor, 'best_floor', r.best_floor, 'today', r.day_floors, 'daily', _tower_daily(p_tower));
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.tower_complete(p_tower text, p_floor int, p_stats jsonb default '{}'::jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); r tower_progress; b jsonb; first boolean; paid boolean := false; pay jsonb := '{}'::jsonb; turns int; k text;
begin
  r := _tower_row(uid, p_tower);
  b := r.battle;
  if b is null or b ? 'sweep' or (b->>'floor')::int <> p_floor then raise exception 'battle not started'; end if;
  if extract(epoch from clock_timestamp()) - (b->>'at')::bigint < _quest_min_secs() then raise exception 'too fast'; end if;
  turns := coalesce((p_stats->>'turns')::int, 1);
  if turns < 1 or turns > 40 then raise exception 'invalid stats'; end if;
  if r.day_floors >= _tower_daily(p_tower) then raise exception 'daily limit'; end if;   -- 자정을 넘긴 전투도 새 날 카운트로
  first := p_floor = r.best_floor + 1;
  if first and p_floor > r.paid_floor then pay := _tower_pay(uid, p_tower, p_floor); paid := true; end if;
  update tower_progress set battle = null, clears = clears + 1, day_floors = day_floors + 1,
    best_floor = case when first then p_floor else best_floor end,
    paid_floor = case when paid then p_floor else paid_floor end,
    rewards = case when paid then (select jsonb_object_agg(x.k, coalesce((rewards->>x.k)::int, 0) + coalesce((pay->'reward'->>x.k)::int, 0) + coalesce((pay->'currency'->>x.k)::int, 0))
                                   from unnest(array['tickets', 'gold', 'blood', 'shard', 'soul']) x(k)) else rewards end,
    updated_at = now()
  where user_id = uid and tower = p_tower;
  return jsonb_build_object('ok', true, 'tower', p_tower, 'first', first, 'paid', paid, 'floor', p_floor, 'best_floor', case when first then p_floor else r.best_floor end,
    'reward', case when paid then pay->'reward' else '{}'::jsonb end, 'currency', pay->'currency', 'tickets', pay->'tickets',
    'today', r.day_floors + 1, 'daily', _tower_daily(p_tower));
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.tower_sweep_info(p_tower text) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); r tower_progress; f int; boss int; left_ int; today date := _tower_today();
begin
  if uid is null then raise exception 'login required'; end if;
  if not _tower_ok(p_tower) then raise exception 'invalid tower'; end if;
  select * into r from tower_progress where user_id = uid and tower = p_tower;
  f := coalesce(r.best_floor, 0) + 1; boss := least(((f + 9) / 10) * 10, _tower_max_floor(p_tower));
  left_ := greatest(0, _tower_daily(p_tower) - case when r.day = today then r.day_floors else 0 end);
  return jsonb_build_object('ok', true, 'tower', p_tower, 'from', f, 'boss', boss, 'max_floors', least(left_, greatest(0, least(boss, _tower_max_floor(p_tower) + 1) - f)),
    'daily_left', left_, 'secs_per_floor', _quest_sweep_secs(), 'stamina', 0, 'boss_every', 10);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.tower_sweep_start(p_tower text) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); r tower_progress; f int; boss int; last_ int;
begin
  r := _tower_row(uid, p_tower);
  f := r.best_floor + 1; boss := ((f + 9) / 10) * 10;
  if f > _tower_max_floor(p_tower) then raise exception 'tower complete'; end if;
  if f % 10 = 0 then raise exception 'boss floor'; end if;
  perform _tower_gate(uid, p_tower, r);
  last_ := least(boss - 1, _tower_max_floor(p_tower), f - 1 + (_tower_daily(p_tower) - r.day_floors));
  update tower_progress set battle = jsonb_build_object('sweep', true, 'from', f, 'boss', boss, 'last', last_, 'at', extract(epoch from clock_timestamp())), updated_at = now() where user_id = uid and tower = p_tower;
  return jsonb_build_object('ok', true, 'tower', p_tower, 'from', f, 'boss', boss, 'last', last_, 'secs_per_floor', _quest_sweep_secs(), 'daily_left', _tower_daily(p_tower) - r.day_floors);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.tower_sweep_complete(p_tower text, p_to int, p_stats jsonb default '{}'::jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); r tower_progress; b jsonb; f int; n int; fl int; pay jsonb; tk int := null; paidTo int;
  tot jsonb := '{}'::jsonb; floors jsonb := '[]'::jsonb; k text; turns jsonb := coalesce(p_stats->'turns', '[]'::jsonb);
begin
  r := _tower_row(uid, p_tower);
  b := r.battle;
  if b is null or not coalesce((b->>'sweep')::boolean, false) then raise exception 'sweep not started'; end if;
  f := (b->>'from')::int;
  if f <> r.best_floor + 1 then raise exception 'sweep stale'; end if;
  if p_to is null or p_to < f - 1 or p_to > (b->>'last')::int then raise exception 'invalid range'; end if;
  n := p_to - f + 1;
  if r.day_floors + n > _tower_daily(p_tower) then raise exception 'daily limit'; end if;
  if extract(epoch from clock_timestamp()) - (b->>'at')::numeric < n * _quest_sweep_secs() then raise exception 'too fast'; end if;
  if jsonb_typeof(turns) <> 'array' or jsonb_array_length(turns) < n
     or exists (select 1 from jsonb_array_elements(turns) x(v) where jsonb_typeof(x.v) <> 'number' or (x.v)::int < 1 or (x.v)::int > 40) then raise exception 'invalid stats'; end if;
  paidTo := r.paid_floor;
  for fl in f .. p_to loop
    if fl > paidTo then
      pay := _tower_pay(uid, p_tower, fl); paidTo := fl; tk := coalesce((pay->>'tickets')::int, tk);
      floors := floors || jsonb_build_object('floor', fl, 'reward', pay->'reward', 'currency', pay->'currency');
      for k in select jsonb_object_keys((pay->'reward') || (pay->'currency')) loop
        tot := tot || jsonb_build_object(k, coalesce((tot->>k)::int, 0) + coalesce((pay->'reward'->>k)::int, 0) + coalesce((pay->'currency'->>k)::int, 0));
      end loop;
    else floors := floors || jsonb_build_object('floor', fl, 'reward', '{}'::jsonb, 'currency', '{}'::jsonb, 'paid_before', true);
    end if;
  end loop;
  update tower_progress set battle = null, clears = clears + n, day_floors = day_floors + n, best_floor = greatest(best_floor, p_to), paid_floor = paidTo,
    rewards = (select jsonb_object_agg(x.k, coalesce((rewards->>x.k)::int, 0) + coalesce((tot->>x.k)::int, 0)) from unnest(array['tickets', 'gold', 'blood', 'shard', 'soul']) x(k)),
    updated_at = now()
  where user_id = uid and tower = p_tower;
  return jsonb_build_object('ok', true, 'tower', p_tower, 'from', f, 'to', p_to, 'cleared', n, 'boss', (b->>'boss')::int, 'best_floor', greatest(r.best_floor, p_to),
    'total', tot, 'floors', floors, 'tickets', tk, 'today', r.day_floors + n, 'daily', _tower_daily(p_tower));
end $$;$vr_statement$;
  execute $vr_statement$do $$ declare fn text; begin
  foreach fn in array array['tower_status()', 'tower_start(text,int)', 'tower_complete(text,int,jsonb)', 'tower_sweep_info(text)', 'tower_sweep_start(text)', 'tower_sweep_complete(text,int,jsonb)'] loop
    execute format('revoke all on function public.%s from public, anon', fn);
    execute format('grant execute on function public.%s to authenticated', fn);
  end loop; end $$;$vr_statement$;
  execute $vr_statement$-- 5) 예전 RPC → normal 탑 (예전 클라이언트 호환. 반환 모양 유지)
create or replace function public.quest_status() returns jsonb language plpgsql security definer set search_path = public as $$
declare s jsonb := tower_status()->'towers'->'normal';
begin
  return jsonb_build_object('best_floor', (s->>'best_floor')::int, 'max_floor', (s->>'max_floor')::int, 'clears', (s->>'clears')::int, 'rewards', s->'rewards', 'today', (s->>'today')::int, 'daily', (s->>'daily')::int);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.quest_start(p_floor int) returns jsonb language sql security definer set search_path = public as $$ select tower_start('normal', p_floor) $$;$vr_statement$;
  execute $vr_statement$create or replace function public.quest_complete(p_floor int, p_stats jsonb default '{}'::jsonb) returns jsonb language sql security definer set search_path = public as $$ select tower_complete('normal', p_floor, p_stats) $$;$vr_statement$;
  execute $vr_statement$create or replace function public.quest_sweep_info() returns jsonb language sql security definer set search_path = public as $$ select tower_sweep_info('normal') $$;$vr_statement$;
  execute $vr_statement$create or replace function public.quest_sweep_start() returns jsonb language sql security definer set search_path = public as $$ select tower_sweep_start('normal') $$;$vr_statement$;
  execute $vr_statement$create or replace function public.quest_sweep_complete(p_to int, p_stats jsonb default '{}'::jsonb) returns jsonb language sql security definer set search_path = public as $$ select tower_sweep_complete('normal', p_to, p_stats) $$;$vr_statement$;
  execute $vr_statement$do $$ declare fn text; begin
  foreach fn in array array['quest_status()', 'quest_start(int)', 'quest_complete(int,jsonb)', 'quest_sweep_info()', 'quest_sweep_start()', 'quest_sweep_complete(int,jsonb)'] loop
    execute format('revoke all on function public.%s from public, anon', fn);
    execute format('grant execute on function public.%s to authenticated', fn);
  end loop; end $$;$vr_statement$;
  execute $vr_statement$-- 관리자: 탑별 진행
create or replace function public.admin_user_quest(p_user uuid) returns jsonb language plpgsql stable security definer set search_path = public, auth as $$
declare r tower_progress; out jsonb := '{}'::jsonb;
begin
  perform public._admin_guard();
  for r in select * from tower_progress where user_id = p_user loop
    out := out || jsonb_build_object(r.tower, jsonb_build_object('best_floor', r.best_floor, 'paid_floor', r.paid_floor, 'clears', r.clears, 'rewards', r.rewards, 'updated_at', r.updated_at));
  end loop;
  return jsonb_build_object('best_floor', coalesce((out->'normal'->>'best_floor')::int, 0), 'clears', coalesce((out->'normal'->>'clears')::int, 0), 'rewards', coalesce(out->'normal'->'rewards', '{}'::jsonb),
    'updated_at', out->'normal'->>'updated_at', 'towers', out);
end $$;$vr_statement$;

  insert into vr_staging_install.parts(part_no, bundle_hash, part_hash, project_ref, db_id)
  values (2, '54d6625d06876bdcfb94a46163f92d8c3802d76c35bbddb31221004f89548d48', 'b2e3e0fc765b0a028e5ce9d64cb1bf5cd0e4ffef54946e0f5f6ed75fea633c6e', 'cuyqchmdcnsgzkwyclji', '7703759698107299042');
end $vr_install_part$;
commit;
select '02_install.sql: 완료 또는 이미 완료 (2/14)' as result;
