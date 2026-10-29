-- =====================================================================
-- LEGENDARY RARE(LR) 서버 등급표를 클라(js/story.js)와 맞춤
-- Supabase SQL Editor 에서 실행. 여러 번 실행해도 안전 (함수 재정의만, LR 줄만 추가 / 다른 등급 숫자는 그대로)
-- 선행: story_merge.sql, story_levels.sql, phaseE_3.sql, phaseE_4.sql, phaseE_6.sql, blood_rebalance.sql
-- ⚠ 이 파일 이후 위 예전 파일들을 다시 돌리면 LR 이 빠져요 (README 표 참고)
--
--   _story_cap        최대 레벨  LR 100 (+5/EX)   ← 기존엔 else 20
--   _story_max_ex     최대 EX    LR 7
--   _story_feed_exp   먹이 EXP   LR 12000
--   _dismantle_yield  분해       LR 골드 5000 · 피 3000 · 혼 200
--   _merge_shard_base EX 조각    LR 60
--   _skill_soul_base  스킬 혼    LR 18
--   (레벨업 피·골드 LR 27·9 는 blood_rebalance.sql 에 이미 있음)
-- 확인용: select public._story_cap('LEGENDARY RARE', 0);  → 100   (SQL Editor 에서)
-- =====================================================================

create or replace function public._story_cap(g text, ex int default 0) returns int language sql immutable as $$
  select (case g when 'NORMAL' then 20 when 'RARE' then 30 when 'HIGH RARE' then 40 when 'SUPER RARE' then 50 when 'ULTRA RARE' then 60 when 'MYTHIC RARE' then 70 when 'LEGENDARY RARE' then 100 else 20 end) + 5 * greatest(0, coalesce(ex, 0))
$$;
create or replace function public._story_max_ex(g text) returns int language sql immutable as $$
  select case g when 'NORMAL' then 1 when 'RARE' then 2 when 'HIGH RARE' then 3 when 'SUPER RARE' then 4 when 'ULTRA RARE' then 5 when 'MYTHIC RARE' then 6 when 'LEGENDARY RARE' then 7 else 1 end
$$;
create or replace function public._story_feed_exp(g text) returns int language sql immutable as $$
  select case g when 'NORMAL' then 50 when 'RARE' then 150 when 'HIGH RARE' then 400 when 'SUPER RARE' then 1000 when 'ULTRA RARE' then 3000 when 'MYTHIC RARE' then 6000 when 'LEGENDARY RARE' then 12000 else 50 end
$$;
create or replace function public._dismantle_yield(p_grade text) returns jsonb language sql immutable as $$
  select case p_grade
    when 'NORMAL'         then '{"gold":20,"blood":10,"soul":0}'
    when 'RARE'           then '{"gold":50,"blood":30,"soul":1}'
    when 'HIGH RARE'      then '{"gold":120,"blood":80,"soul":3}'
    when 'SUPER RARE'     then '{"gold":300,"blood":200,"soul":10}'
    when 'ULTRA RARE'     then '{"gold":800,"blood":500,"soul":30}'
    when 'MYTHIC RARE'    then '{"gold":2000,"blood":1200,"soul":80}'
    when 'LEGENDARY RARE' then '{"gold":5000,"blood":3000,"soul":200}'
    else '{"gold":20,"blood":10,"soul":0}' end::jsonb
$$;
create or replace function public._merge_shard_base(p_grade text) returns int language sql immutable as $$
  select case p_grade when 'NORMAL' then 1 when 'RARE' then 2 when 'HIGH RARE' then 4 when 'SUPER RARE' then 8 when 'ULTRA RARE' then 15 when 'MYTHIC RARE' then 30 when 'LEGENDARY RARE' then 60 else 1 end $$;
create or replace function public._skill_soul_base(p_grade text) returns int language sql immutable as $$
  select case p_grade when 'NORMAL' then 1 when 'RARE' then 2 when 'HIGH RARE' then 3 when 'SUPER RARE' then 5 when 'ULTRA RARE' then 8 when 'MYTHIC RARE' then 12 when 'LEGENDARY RARE' then 18 else 1 end $$;

revoke all on function public._story_cap(text, int), public._story_max_ex(text), public._story_feed_exp(text), public._dismantle_yield(text),
  public._merge_shard_base(text), public._skill_soul_base(text) from public, anon, authenticated;
