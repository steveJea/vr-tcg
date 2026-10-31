-- =====================================================================
-- 📅 일일 미션 + 출석 보상 — Supabase SQL Editor 에서 실행. 여러 번 실행해도 안전
-- 선행: phaseE_1.sql(_wallet_add) · gem.sql(_gem_add, _gem_day) · story_gacha.sql(소환권)
-- 초기화: 한국 시간 00:00 (_gem_day). 보상 지급은 전부 서버 (클라이언트는 미션 키만 보냄)
-- 진행 기록은 클라이언트가 전투 끝에 daily_track 으로 알림 → 서버가 목표치에서 잘라 저장 (1회 호출당 상한)
-- 공개 RPC: daily_status() · daily_track(kind, n) · daily_claim(key) · attend_claim()
-- 확인용: select public.daily_status();
-- =====================================================================

create table if not exists public.daily_progress (
  user_id uuid not null references auth.users(id) on delete cascade,
  day     date not null,
  prog    jsonb not null default '{}'::jsonb,   -- { win: 2, skill: 7, ... }
  claimed jsonb not null default '[]'::jsonb,   -- ["win","all",...]
  primary key (user_id, day)
);
alter table public.daily_progress enable row level security;
revoke all on public.daily_progress from public, anon, authenticated;

create table if not exists public.daily_attend (
  user_id  uuid primary key references auth.users(id) on delete cascade,
  last_day date,
  step     int not null default 0,   -- 이번 주기에서 받은 날 수 (0~7)
  total    int not null default 0
);
alter table public.daily_attend enable row level security;
revoke all on public.daily_attend from public, anon, authenticated;

-- 미션 정의 (한 곳에서 조정). per = daily_track 1회 호출로 올릴 수 있는 최대
create or replace function public._daily_defs() returns jsonb language sql immutable as $$ select '[
  {"key":"arcade","name":"아케이드 1판 플레이","goal":1,"per":1,"reward":{"gold":1000}},
  {"key":"win","name":"전투 3회 승리","goal":3,"per":1,"reward":{"gold":2000}},
  {"key":"story","name":"스토리 스테이지 2회 클리어","goal":2,"per":1,"reward":{"gold":2000,"gem":10}},
  {"key":"tower","name":"시련의 탑 1회 도전","goal":1,"per":1,"reward":{"gold":1500,"gem":10}},
  {"key":"skill","name":"고유기술 10회 사용","goal":10,"per":20,"reward":{"gold":1500}}
]'::jsonb $$;
create or replace function public._daily_all_reward() returns jsonb language sql immutable as $$ select '{"gem":30}'::jsonb $$;
-- 출석 7일 주기 (빠진 날이 있어도 끊기지 않고 다음 칸으로. 7일째 받으면 1일째부터 다시)
create or replace function public._attend_defs() returns jsonb language sql immutable as $$ select '[
  {"gold":3000},{"gem":20},{"gold":5000},{"gem":30},{"tickets":1},{"gold":10000},{"gem":100,"tickets":2}
]'::jsonb $$;

create or replace function public._daily_grant(p_uid uuid, p_rw jsonb, p_reason text, p_ref text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare res jsonb := '{}'::jsonb; t int;
begin
  if coalesce((p_rw->>'gold')::int, 0) > 0 then res := res || jsonb_build_object('wallet', _wallet_add(p_uid, jsonb_build_object('gold', (p_rw->>'gold')::int), p_reason)); end if;
  if coalesce((p_rw->>'gem')::int, 0) > 0 then perform _gem_add(p_uid, (p_rw->>'gem')::int, 0, p_reason, p_ref, jsonb_build_object('ref', p_ref)); end if;
  if coalesce((p_rw->>'tickets')::int, 0) > 0 then
    insert into story_gacha (user_id, last_draw) values (p_uid, _gem_day() - 1) on conflict (user_id) do nothing;
    update story_gacha set tickets = tickets + (p_rw->>'tickets')::int, updated_at = now() where user_id = p_uid returning tickets into t;
    res := res || jsonb_build_object('tickets', t);
  end if;
  return res;
end $$;

create or replace function public._daily_json(p_uid uuid) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare dp daily_progress; a daily_attend; today date := _gem_day(); done int;
begin
  select * into dp from daily_progress where user_id = p_uid and day = today;
  select * into a from daily_attend where user_id = p_uid;
  select count(*) into done from jsonb_array_elements(_daily_defs()) m where coalesce((dp.prog->>(m->>'key'))::int, 0) >= (m->>'goal')::int;
  return jsonb_build_object('ok', true, 'day', today,
    'next_reset', ((today + 1)::timestamp at time zone 'Asia/Seoul'),
    'missions', (select jsonb_agg(m || jsonb_build_object('prog', least((m->>'goal')::int, coalesce((dp.prog->>(m->>'key'))::int, 0)),
                   'claimed', coalesce(dp.claimed, '[]'::jsonb) ? (m->>'key'))) from jsonb_array_elements(_daily_defs()) m),
    'all', jsonb_build_object('reward', _daily_all_reward(), 'done', done, 'goal', jsonb_array_length(_daily_defs()), 'claimed', coalesce(dp.claimed, '[]'::jsonb) ? 'all'),
    'attend', jsonb_build_object('rewards', _attend_defs(), 'step', case when coalesce(a.step, 0) >= 7 and a.last_day < today then 0 else coalesce(a.step, 0) end,
                   'today', a.last_day = today, 'total', coalesce(a.total, 0)));
end $$;
revoke all on function public._daily_grant(uuid, jsonb, text, text), public._daily_json(uuid) from public, anon, authenticated;

create or replace function public.daily_status() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  return _daily_json(uid);
end $$;

create or replace function public.daily_track(p_kind text, p_n int default 1) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); m jsonb; today date := _gem_day(); cur int; nv int;
begin
  if uid is null then raise exception 'login required'; end if;
  select x into m from jsonb_array_elements(_daily_defs()) x where x->>'key' = p_kind;
  if m is null then raise exception 'invalid kind'; end if;
  perform pg_advisory_xact_lock(hashtext('daily:' || uid::text));
  insert into daily_progress (user_id, day) values (uid, today) on conflict do nothing;
  select coalesce((prog->>p_kind)::int, 0) into cur from daily_progress where user_id = uid and day = today;
  nv := least((m->>'goal')::int, cur + greatest(0, least(coalesce(p_n, 1), (m->>'per')::int)));
  if nv <> cur then update daily_progress set prog = prog || jsonb_build_object(p_kind, nv) where user_id = uid and day = today; end if;
  return jsonb_build_object('ok', true, 'kind', p_kind, 'prog', nv, 'goal', (m->>'goal')::int);
end $$;

create or replace function public.daily_claim(p_key text) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); m jsonb; today date := _gem_day(); dp daily_progress; rw jsonb; res jsonb; done int;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('daily:' || uid::text));
  perform pg_advisory_xact_lock(hashtext('gem:' || uid::text));
  insert into daily_progress (user_id, day) values (uid, today) on conflict do nothing;
  select * into dp from daily_progress where user_id = uid and day = today for update;
  if dp.claimed ? p_key then raise exception 'already claimed'; end if;
  if p_key = 'all' then
    select count(*) into done from jsonb_array_elements(_daily_defs()) x where coalesce((dp.prog->>(x->>'key'))::int, 0) >= (x->>'goal')::int;
    if done < jsonb_array_length(_daily_defs()) then raise exception 'not done'; end if;
    rw := _daily_all_reward();
  else
    select x into m from jsonb_array_elements(_daily_defs()) x where x->>'key' = p_key;
    if m is null then raise exception 'invalid key'; end if;
    if coalesce((dp.prog->>p_key)::int, 0) < (m->>'goal')::int then raise exception 'not done'; end if;
    rw := m->'reward';
  end if;
  update daily_progress set claimed = claimed || to_jsonb(p_key) where user_id = uid and day = today;
  res := _daily_grant(uid, rw, 'daily', 'daily:' || today || ':' || p_key);
  return _daily_json(uid) || res || jsonb_build_object('got', rw);
end $$;

create or replace function public.attend_claim() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); today date := _gem_day(); a daily_attend; st int; rw jsonb; res jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('daily:' || uid::text));
  perform pg_advisory_xact_lock(hashtext('gem:' || uid::text));
  insert into daily_attend (user_id) values (uid) on conflict do nothing;
  select * into a from daily_attend where user_id = uid for update;
  if a.last_day = today then raise exception 'already claimed'; end if;
  st := case when a.step >= 7 then 1 else a.step + 1 end;
  rw := _attend_defs()->(st - 1);
  update daily_attend set last_day = today, step = st, total = total + 1 where user_id = uid;
  res := _daily_grant(uid, rw, 'attend', 'attend:' || today);
  return _daily_json(uid) || res || jsonb_build_object('got', rw, 'got_day', st);
end $$;

revoke all on function public.daily_status(), public.daily_track(text, int), public.daily_claim(text), public.attend_claim() from public, anon;
grant execute on function public.daily_status(), public.daily_track(text, int), public.daily_claim(text), public.attend_claim() to authenticated;
