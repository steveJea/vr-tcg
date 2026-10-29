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

create or replace function public._quest_sweep_secs() returns numeric language sql immutable as $$ select 1.0 $$;
revoke all on function public._quest_sweep_secs() from public, anon, authenticated;

create or replace function public.quest_sweep_info() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); r quest_progress; f int; boss int;
begin
  if uid is null then raise exception 'login required'; end if;
  select * into r from quest_progress where user_id = uid;
  f := coalesce(r.best_floor, 0) + 1; boss := ((f + 9) / 10) * 10;
  return jsonb_build_object('ok', true, 'from', f, 'boss', least(boss, _quest_max_floor()), 'max_floors', greatest(0, least(boss, _quest_max_floor() + 1) - f),
    'secs_per_floor', _quest_sweep_secs(), 'stamina', 0, 'boss_every', 10);
end $$;
revoke all on function public.quest_sweep_info() from public, anon;
grant execute on function public.quest_sweep_info() to authenticated;

create or replace function public.quest_sweep_start() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); r quest_progress; f int; boss int;
begin
  r := _quest_row(uid);
  f := r.best_floor + 1; boss := ((f + 9) / 10) * 10;
  if f > _quest_max_floor() then raise exception 'tower complete'; end if;
  if f % 10 = 0 then raise exception 'boss floor'; end if;
  update quest_progress set battle = jsonb_build_object('sweep', true, 'from', f, 'boss', boss, 'at', extract(epoch from clock_timestamp())), updated_at = now() where user_id = uid;
  return jsonb_build_object('ok', true, 'from', f, 'boss', boss, 'last', least(boss - 1, _quest_max_floor()), 'secs_per_floor', _quest_sweep_secs());
end $$;
revoke all on function public.quest_sweep_start() from public, anon;
grant execute on function public.quest_sweep_start() to authenticated;

-- p_to: 마지막으로 이긴 층 (from-1 이면 하나도 못 이김). p_stats: { turns: [층별 턴 수] }
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
end $$;
revoke all on function public.quest_sweep_complete(int, jsonb) from public, anon;
grant execute on function public.quest_sweep_complete(int, jsonb) to authenticated;
