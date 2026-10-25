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
--   리셋: 기존 시련의 탑 진행(quest_progress.best_floor)은 0층으로. 이미 받은 보상은 그대로 두고,
--         paid_floor(= 리셋 전 최고 층) 이하 층은 다시 깨도 첫 클리어 보상을 주지 않음 (이중 지급 방지)
-- 새 RPC: tower_status() · tower_start(tower, floor) · tower_complete(tower, floor, stats) · tower_sweep_info(tower) · tower_sweep_start(tower) · tower_sweep_complete(tower, to, stats)
-- 기존 quest_* RPC 는 normal 탑으로 이어지는 래퍼 (예전 클라이언트 호환)
-- =====================================================================

-- 1) 진행 테이블 (탑마다 한 줄)
create table if not exists public.tower_progress (
  user_id     uuid not null references auth.users(id) on delete cascade,
  tower       text not null check (tower in ('normal', 'wind', 'ice', 'fire', 'light', 'dark')),
  best_floor  int not null default 0 check (best_floor >= 0),
  paid_floor  int not null default 0 check (paid_floor >= 0),   -- 첫 클리어 보상을 이미 받은 최고 층 (리셋해도 유지)
  battle      jsonb,
  clears      int not null default 0,
  rewards     jsonb not null default '{}'::jsonb,
  day         date,                                             -- KST 날짜
  day_floors  int not null default 0,                           -- 그날 이긴 층 수 (소탕 포함)
  updated_at  timestamptz not null default now(),
  primary key (user_id, tower)
);
alter table public.tower_progress enable row level security;
drop policy if exists "tower_select_own" on public.tower_progress;
create policy "tower_select_own" on public.tower_progress for select using (user_id = auth.uid());
revoke insert, update, delete on public.tower_progress from anon, authenticated;
grant select on public.tower_progress to authenticated;

-- 2) 기존 진행 이전 + 리셋 (처음 1회: 이미 tower_progress 에 normal 줄이 있으면 건드리지 않음)
insert into public.tower_progress (user_id, tower, best_floor, paid_floor, clears, rewards)
select user_id, 'normal', 0, best_floor, clears, rewards from public.quest_progress
on conflict (user_id, tower) do nothing;

-- 3) 규칙 함수
create or replace function public._tower_ok(p text) returns boolean language sql immutable as $$ select p in ('normal', 'wind', 'ice', 'fire', 'light', 'dark') $$;
create or replace function public._tower_today() returns date language sql stable as $$ select (now() at time zone 'Asia/Seoul')::date $$;
create or replace function public._tower_dow() returns int language sql stable as $$ select extract(isodow from (now() at time zone 'Asia/Seoul'))::int $$;   -- 1 월 … 7 일
create or replace function public._tower_days(p text) returns int[] language sql immutable as $$
  select case p when 'normal' then array[1,2,3,4,5,6,7] when 'wind' then array[1,6,7] when 'ice' then array[2,6,7]
    when 'fire' then array[3,6,7] when 'light' then array[4,6,7] when 'dark' then array[5,6,7] end $$;
create or replace function public._tower_daily(p text) returns int language sql immutable as $$ select case when p = 'normal' then 30 else 10 end $$;
create or replace function public._tower_min_level(p text) returns int language sql immutable as $$ select case p when 'normal' then 5 when 'light' then 50 when 'dark' then 50 else 30 end $$;
create or replace function public._tower_max_floor(p text) returns int language sql immutable as $$ select 350 $$;
create or replace function public._tower_reward(p text, f int) returns jsonb language sql immutable as $$
  select case when p = 'normal' then _quest_reward(f) else '{}'::jsonb end $$;
create or replace function public._tower_currency(p text, f int) returns jsonb language sql immutable as $$
  select case when p = 'normal' then _quest_currency(f) else _quest_currency(f) - 'soul' end $$;
do $$ declare fn text; begin
  foreach fn in array array['_tower_ok(text)', '_tower_today()', '_tower_dow()', '_tower_days(text)', '_tower_daily(text)', '_tower_min_level(text)', '_tower_max_floor(text)', '_tower_reward(text,int)', '_tower_currency(text,int)'] loop
    execute format('revoke all on function public.%s from public, anon, authenticated', fn);
  end loop; end $$;

-- 줄 잠금 + 날짜 바뀌면 일일 카운트 0
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
end $$;
revoke all on function public._tower_row(uuid, text) from public, anon, authenticated;

-- 입장 확인 (요일 · 유저 레벨 · 일일 제한)
create or replace function public._tower_gate(uid uuid, p text, r public.tower_progress) returns void language plpgsql stable set search_path = public as $$
declare lv int;
begin
  if not (_tower_dow() = any(_tower_days(p))) then raise exception 'tower closed today'; end if;
  select level into lv from player_state where user_id = uid;
  if coalesce(lv, 1) < _tower_min_level(p) then raise exception 'level too low'; end if;
  if r.day_floors >= _tower_daily(p) then raise exception 'daily limit'; end if;
end $$;
revoke all on function public._tower_gate(uuid, text, public.tower_progress) from public, anon, authenticated;

-- 첫 클리어 보상 지급 (paid_floor 초과 층만). 반환 { reward, currency, tickets }
create or replace function public._tower_pay(uid uuid, p text, f int) returns jsonb language plpgsql set search_path = public as $$
declare rw jsonb := _tower_reward(p, f); cur jsonb := _tower_currency(p, f); t int := coalesce((rw->>'tickets')::int, 0); tk int := null;
begin
  if t > 0 then
    insert into story_gacha (user_id, last_draw) values (uid, (now() at time zone 'Asia/Seoul')::date - 1) on conflict (user_id) do nothing;
    update story_gacha set tickets = tickets + t, updated_at = now() where user_id = uid returning tickets into tk;
  end if;
  if cur <> '{}'::jsonb then perform _wallet_add(uid, cur, 'tower_first_clear:' || p); end if;
  return jsonb_build_object('reward', rw, 'currency', cur, 'tickets', tk);
end $$;
revoke all on function public._tower_pay(uuid, text, int) from public, anon, authenticated;

-- 4) RPC
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
end $$;

create or replace function public.tower_start(p_tower text, p_floor int) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); r tower_progress;
begin
  r := _tower_row(uid, p_tower);
  if p_floor is null or p_floor < 1 or p_floor > _tower_max_floor(p_tower) then raise exception 'invalid floor'; end if;
  if p_floor > r.best_floor + 1 then raise exception 'floor locked'; end if;
  perform _tower_gate(uid, p_tower, r);
  update tower_progress set battle = jsonb_build_object('floor', p_floor, 'at', (extract(epoch from clock_timestamp()))::bigint), updated_at = now() where user_id = uid and tower = p_tower;
  return jsonb_build_object('ok', true, 'tower', p_tower, 'floor', p_floor, 'best_floor', r.best_floor, 'today', r.day_floors, 'daily', _tower_daily(p_tower));
end $$;

create or replace function public.tower_complete(p_tower text, p_floor int, p_stats jsonb default '{}'::jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
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
end $$;

create or replace function public.tower_sweep_info(p_tower text) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); r tower_progress; f int; boss int; left_ int; today date := _tower_today();
begin
  if uid is null then raise exception 'login required'; end if;
  if not _tower_ok(p_tower) then raise exception 'invalid tower'; end if;
  select * into r from tower_progress where user_id = uid and tower = p_tower;
  f := coalesce(r.best_floor, 0) + 1; boss := least(((f + 9) / 10) * 10, _tower_max_floor(p_tower));
  left_ := greatest(0, _tower_daily(p_tower) - case when r.day = today then r.day_floors else 0 end);
  return jsonb_build_object('ok', true, 'tower', p_tower, 'from', f, 'boss', boss, 'max_floors', least(left_, greatest(0, least(boss, _tower_max_floor(p_tower) + 1) - f)),
    'daily_left', left_, 'secs_per_floor', _quest_sweep_secs(), 'stamina', 0, 'boss_every', 10);
end $$;

create or replace function public.tower_sweep_start(p_tower text) returns jsonb language plpgsql security definer set search_path = public as $$
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
end $$;

create or replace function public.tower_sweep_complete(p_tower text, p_to int, p_stats jsonb default '{}'::jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
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
end $$;

do $$ declare fn text; begin
  foreach fn in array array['tower_status()', 'tower_start(text,int)', 'tower_complete(text,int,jsonb)', 'tower_sweep_info(text)', 'tower_sweep_start(text)', 'tower_sweep_complete(text,int,jsonb)'] loop
    execute format('revoke all on function public.%s from public, anon', fn);
    execute format('grant execute on function public.%s to authenticated', fn);
  end loop; end $$;

-- 5) 예전 RPC → normal 탑 (예전 클라이언트 호환. 반환 모양 유지)
create or replace function public.quest_status() returns jsonb language plpgsql security definer set search_path = public as $$
declare s jsonb := tower_status()->'towers'->'normal';
begin
  return jsonb_build_object('best_floor', (s->>'best_floor')::int, 'max_floor', (s->>'max_floor')::int, 'clears', (s->>'clears')::int, 'rewards', s->'rewards', 'today', (s->>'today')::int, 'daily', (s->>'daily')::int);
end $$;
create or replace function public.quest_start(p_floor int) returns jsonb language sql security definer set search_path = public as $$ select tower_start('normal', p_floor) $$;
create or replace function public.quest_complete(p_floor int, p_stats jsonb default '{}'::jsonb) returns jsonb language sql security definer set search_path = public as $$ select tower_complete('normal', p_floor, p_stats) $$;
create or replace function public.quest_sweep_info() returns jsonb language sql security definer set search_path = public as $$ select tower_sweep_info('normal') $$;
create or replace function public.quest_sweep_start() returns jsonb language sql security definer set search_path = public as $$ select tower_sweep_start('normal') $$;
create or replace function public.quest_sweep_complete(p_to int, p_stats jsonb default '{}'::jsonb) returns jsonb language sql security definer set search_path = public as $$ select tower_sweep_complete('normal', p_to, p_stats) $$;
do $$ declare fn text; begin
  foreach fn in array array['quest_status()', 'quest_start(int)', 'quest_complete(int,jsonb)', 'quest_sweep_info()', 'quest_sweep_start()', 'quest_sweep_complete(int,jsonb)'] loop
    execute format('revoke all on function public.%s from public, anon', fn);
    execute format('grant execute on function public.%s to authenticated', fn);
  end loop; end $$;

-- 관리자: 탑별 진행
create or replace function public.admin_user_quest(p_user uuid) returns jsonb language plpgsql stable security definer set search_path = public, auth as $$
declare r tower_progress; out jsonb := '{}'::jsonb;
begin
  perform public._admin_guard();
  for r in select * from tower_progress where user_id = p_user loop
    out := out || jsonb_build_object(r.tower, jsonb_build_object('best_floor', r.best_floor, 'paid_floor', r.paid_floor, 'clears', r.clears, 'rewards', r.rewards, 'updated_at', r.updated_at));
  end loop;
  return jsonb_build_object('best_floor', coalesce((out->'normal'->>'best_floor')::int, 0), 'clears', coalesce((out->'normal'->>'clears')::int, 0), 'rewards', coalesce(out->'normal'->'rewards', '{}'::jsonb),
    'updated_at', out->'normal'->>'updated_at', 'towers', out);
end $$;
revoke all on function public.admin_user_quest(uuid) from public, anon;
grant execute on function public.admin_user_quest(uuid) to authenticated;

-- 확인: select tower, count(*), max(paid_floor) from public.tower_progress group by tower;
