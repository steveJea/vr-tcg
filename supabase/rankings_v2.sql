-- 랭킹 v2: 시련의 탑 · 스토리 랭킹 (읽기 전용 함수 2개). 여러 번 실행해도 안전.
-- 닉네임·기록만 돌려주고 user_id 는 내보내지 않아요. 아케이드(rankings_weekly/all), PvP(pvp_rankings)는 기존 그대로 사용.

-- 1) 탑 랭킹: 탑별 최고 층 (같으면 먼저 도달한 사람이 위)
create or replace function public.tower_rankings(p_tower text default 'normal') returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); top jsonb; mine jsonb;
begin
  if p_tower not in ('normal', 'wind', 'ice', 'fire', 'light', 'dark') then raise exception 'bad tower'; end if;
  with t as (select g.user_id, g.best_floor, g.clears, rank() over (order by g.best_floor desc) rk, row_number() over (order by g.best_floor desc, g.updated_at) rn
             from tower_progress g where g.tower = p_tower and g.best_floor > 0)
  select coalesce(jsonb_agg(jsonb_build_object('rank', rk, 'name', coalesce(p.nickname, '플레이어'), 'floor', best_floor, 'me', t.user_id = uid) order by rn), '[]'::jsonb)
    into top from (select * from t order by rn limit 50) t left join profiles p on p.id = t.user_id;
  with t as (select g.user_id, g.best_floor, rank() over (order by g.best_floor desc) rk
             from tower_progress g where g.tower = p_tower and g.best_floor > 0)
  select jsonb_build_object('rank', rk, 'floor', best_floor) into mine from t where t.user_id = uid;
  return jsonb_build_object('top', top, 'me', mine);
end $$;

-- 2) 스토리 랭킹: 깬 페이즈 중 가장 먼 곳 (챕터 → 페이즈 순). 화면엔 '9-15' 처럼 표시
create or replace function public.story_rankings() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); top jsonb; mine jsonb;
begin
  with c as (
    select s.user_id, s.updated_at, (k.key)::int ch, max((v.value)::int) ph, count(*) n
      from story_progress s, jsonb_each(case when jsonb_typeof(s.data->'cleared') = 'object' then s.data->'cleared' else '{}'::jsonb end) k,
           jsonb_array_elements_text(case when jsonb_typeof(k.value) = 'array' then k.value else '[]'::jsonb end) v
     where k.key ~ '^[0-9]{1,3}$' and v.value ~ '^[0-9]{1,3}$'
     group by s.user_id, s.updated_at, k.key),
  b as (select distinct on (user_id) user_id, updated_at, ch, ph from c order by user_id, ch desc),
  tot as (select user_id, sum(n)::int total from c group by user_id),
  t as (select b.*, tot.total, rank() over (order by ch desc, ph desc) rk, row_number() over (order by ch desc, ph desc, tot.total desc, b.updated_at) rn
          from b join tot using (user_id))
  select coalesce((select jsonb_agg(jsonb_build_object('rank', rk, 'name', coalesce(p.nickname, '플레이어'), 'ch', ch, 'ph', ph, 'total', total, 'me', t.user_id = uid) order by rn)
                     from (select * from t order by rn limit 50) t left join profiles p on p.id = t.user_id), '[]'::jsonb),
         (select jsonb_build_object('rank', rk, 'ch', ch, 'ph', ph, 'total', total) from t where t.user_id = uid)
    into top, mine;
  return jsonb_build_object('top', top, 'me', mine);
end $$;

revoke all on function public.tower_rankings(text) from public;
revoke all on function public.story_rankings() from public;
grant execute on function public.tower_rankings(text) to anon, authenticated;
grant execute on function public.story_rankings() to anon, authenticated;
