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
);
alter table public.quest_progress enable row level security;
drop policy if exists "quest_select_own" on public.quest_progress;
create policy "quest_select_own" on public.quest_progress for select using (user_id = auth.uid());
revoke insert, update, delete on public.quest_progress from anon, authenticated;
grant select on public.quest_progress to authenticated;

-- 층 수 (data/quest.json 과 같게. 층을 늘리면 이 값도 올림)
create or replace function public._quest_max_floor() returns int language sql immutable as $$ select 350 $$;
-- 최소 전투 시간 (초)
create or replace function public._quest_min_secs() returns int language sql immutable as $$ select 5 $$;
-- 첫 클리어 보상 (골드 등은 여기에 추가: 'gold', n). data/quest.json rewards 와 같은 규칙
create or replace function public._quest_reward(p_floor int) returns jsonb language sql immutable as $$
  select case when p_floor % 50 = 0 then jsonb_build_object('tickets', 10)
              when p_floor % 10 = 0 then jsonb_build_object('tickets', 5)
              else '{}'::jsonb end
$$;
revoke all on function public._quest_max_floor() from public, anon, authenticated;
revoke all on function public._quest_min_secs() from public, anon, authenticated;
revoke all on function public._quest_reward(int) from public, anon, authenticated;
grant execute on function public._quest_max_floor() to authenticated;   -- 상수라 노출돼도 무해 (quest_status 에서도 반환)

create or replace function public._quest_row(uid uuid) returns public.quest_progress language plpgsql set search_path = public as $$
declare r public.quest_progress;
begin
  if uid is null then raise exception 'login required'; end if;
  insert into quest_progress (user_id) values (uid) on conflict (user_id) do nothing;
  select * into r from quest_progress where user_id = uid for update;
  return r;
end $$;
revoke all on function public._quest_row(uuid) from public, anon, authenticated;

-- 상태 (확인용 RPC)
create or replace function public.quest_status() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); r quest_progress;
begin
  if uid is null then raise exception 'login required'; end if;
  select * into r from quest_progress where user_id = uid;
  return jsonb_build_object('best_floor', coalesce(r.best_floor, 0), 'max_floor', _quest_max_floor(), 'clears', coalesce(r.clears, 0), 'rewards', coalesce(r.rewards, '{}'::jsonb));
end $$;
revoke all on function public.quest_status() from public, anon;
grant execute on function public.quest_status() to authenticated;

-- 전투 시작: 열린 층(최고 층 + 1 이하)만
create or replace function public.quest_start(p_floor int) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); r quest_progress;
begin
  if p_floor is null or p_floor < 1 or p_floor > _quest_max_floor() then raise exception 'invalid floor'; end if;
  r := _quest_row(uid);
  if p_floor > r.best_floor + 1 then raise exception 'floor locked'; end if;
  update quest_progress set battle = jsonb_build_object('floor', p_floor, 'at', (extract(epoch from clock_timestamp()))::bigint), updated_at = now() where user_id = uid;
  return jsonb_build_object('ok', true, 'floor', p_floor, 'best_floor', r.best_floor);
end $$;
revoke all on function public.quest_start(int) from public, anon;
grant execute on function public.quest_start(int) to authenticated;

-- 승리 기록: 시작 기록·최소 시간 확인 → 첫 클리어면 최고 층 갱신 + 보상(소환권은 story_gacha.tickets 에 더함)
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
end $$;
revoke all on function public.quest_complete(int, jsonb) from public, anon;
grant execute on function public.quest_complete(int, jsonb) to authenticated;

-- 관리자: 유저 퀘스트 최고 층 (admin.sql 의 _admin_guard 사용. admin.sql 실행 후)
create or replace function public.admin_user_quest(p_user uuid) returns jsonb language plpgsql stable security definer set search_path = public, auth as $$
declare r quest_progress;
begin
  perform public._admin_guard();
  select * into r from quest_progress where user_id = p_user;
  return jsonb_build_object('best_floor', coalesce(r.best_floor, 0), 'clears', coalesce(r.clears, 0), 'rewards', coalesce(r.rewards, '{}'::jsonb), 'updated_at', r.updated_at);
end $$;
revoke all on function public.admin_user_quest(uuid) from public, anon;
grant execute on function public.admin_user_quest(uuid) to authenticated;
