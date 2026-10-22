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
  select case p_grade when 'NORMAL' then 2 when 'RARE' then 3 when 'HIGH RARE' then 5 when 'SUPER RARE' then 8 when 'ULTRA RARE' then 12 when 'MYTHIC RARE' then 18 else 2 end::numeric $$;
create or replace function public._lv_cost_g(p_grade text) returns numeric language sql immutable as $$
  select case p_grade when 'NORMAL' then 1 when 'RARE' then 1.5 when 'HIGH RARE' then 2 when 'SUPER RARE' then 3 when 'ULTRA RARE' then 4 when 'MYTHIC RARE' then 6 else 1 end::numeric $$;
-- 레벨 L 에서 L+1 로 올리는 비용
create or replace function public._lv_cost(p_grade text, p_level int) returns jsonb language sql immutable as $$
  select jsonb_build_object('blood', ceil(_lv_cost_b(p_grade) * p_level)::int, 'gold', ceil(_lv_cost_g(p_grade) * p_level * 10)::int) $$;
create or replace function public._merge_shard_base(p_grade text) returns int language sql immutable as $$
  select case p_grade when 'NORMAL' then 1 when 'RARE' then 2 when 'HIGH RARE' then 4 when 'SUPER RARE' then 8 when 'ULTRA RARE' then 15 when 'MYTHIC RARE' then 30 else 1 end $$;
create or replace function public._merge_shard_cost(p_grade text, p_next_ex int) returns int language sql immutable as $$
  select _merge_shard_base(p_grade) * greatest(1, p_next_ex) $$;

-- 공개: 비용표 (탐침 겸용)
create or replace function public.card_cost_table() returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('ok', true, 'version', 4, 'grades', jsonb_object_agg(g, jsonb_build_object('b', _lv_cost_b(g), 'g', _lv_cost_g(g), 'shard', _merge_shard_base(g), 'lv1', _lv_cost(g, 1))))
  from unnest(array['NORMAL','RARE','HIGH RARE','SUPER RARE','ULTRA RARE','MYTHIC RARE']) g
$$;
revoke all on function public.card_cost_table() from public, anon;
grant execute on function public.card_cost_table() to authenticated;

-- 2) 카드 레벨업: p_uid 카드를 p_levels 단계 (1~100, 최대 레벨까지만). 전부 성공 또는 전부 취소
create or replace function public.story_card_levelup(p_uid text, p_levels int default 1) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb; owned jsonb; i int; e jsonb; g text; lv int; cap int; k int := 0; gold int := 0; blood int := 0; c jsonb; w jsonb; from_lv int;
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
  while k < p_levels and lv < cap loop
    c := _lv_cost(g, lv);
    gold := gold + (c->>'gold')::int; blood := blood + (c->>'blood')::int;
    lv := lv + 1; k := k + 1;
  end loop;
  w := _wallet_add(uid, jsonb_build_object('gold', -gold, 'blood', -blood), 'card_levelup');   -- 부족하면 'not enough ...' → 전체 롤백
  e := e || jsonb_build_object('level', lv, 'exp', least((e->>'exp')::int, greatest(0, lv * 100 - 1)), 'bloodSpent', coalesce((e->>'bloodSpent')::int, 0) + blood);
  if lv >= cap then e := e || jsonb_build_object('exp', 0); end if;
  owned := jsonb_set(owned, array[i::text], e);
  d := _story_save(uid, jsonb_set(d, '{owned}', owned));
  return jsonb_build_object('data', d, 'from', from_lv, 'level', lv, 'cap', cap, 'gold', gold, 'blood', blood, 'wallet', w);
end $$;
revoke all on function public.story_card_levelup(text, int) from public, anon;
grant execute on function public.story_card_levelup(text, int) to authenticated;

-- 3) EX 합성 감싸기: 이상한 조각 차감 후 원래 합성
do $$
declare src text;
begin
  select prosrc into src from pg_proc where oid = to_regprocedure('public.story_merge(text,text)');
  if src is not null and src not like '%phaseE_4 wrapper%' then
    drop function if exists public._story_merge_e0(text, text);
    alter function public.story_merge(text, text) rename to _story_merge_e0;
  end if;
end $$;
revoke all on function public._story_merge_e0(text, text) from public, anon, authenticated;

create or replace function public.story_merge(p_target text, p_material text) returns jsonb language plpgsql security definer set search_path = public as $$
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
end $$;
revoke all on function public.story_merge(text, text) from public, anon;
grant execute on function public.story_merge(text, text) to authenticated;
