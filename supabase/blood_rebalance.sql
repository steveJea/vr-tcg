-- =====================================================================
-- 피 리밸런스 (1/2): 카드 레벨업 비용 50% 감소 + LEGENDARY RARE 계수 추가
-- Supabase SQL Editor 에서 실행. 여러 번 실행해도 안전 (함수 재정의만)
-- 선행: phaseE_4.sql (phaseE_3.sql / phaseE_4.sql 은 다시 돌리지 마세요 - 예전 비용으로 돌아감)
--
-- 레벨업 L → L+1:  순수한 피 = ceil(b × L × 0.5),  골드 = ceil(g × L × 10 × 0.5)   (올림이라 최소 1)
--   N b2 g1 · R b3 g1.5 · HR b5 g2 · SR b8 g3 · UR b12 g4 · MR b18 g6 · LR b27 g9 (LR 은 새로 추가, 클라와 맞춤)
--   배율은 _lv_cost_mult() 한 곳. 클라 js/story.js 의 LV_MULT 도 같이 바꿔야 해요
-- 분해 환급(쓴 피 50%)은 카드의 bloodSpent 기준이라 자동으로 새 비용 기준이 됨
-- 기존 유저 차액 환급은 blood_rebalance_refund.sql (따로, 1회)
-- 확인용: select public.card_cost_table();   → version 5, grades.SUPER RARE.lv1 = {"blood":4,"gold":15}
-- =====================================================================

create or replace function public._lv_cost_mult() returns numeric language sql immutable as $$ select 0.5::numeric $$;
create or replace function public._lv_cost_b(p_grade text) returns numeric language sql immutable as $$
  select case p_grade when 'NORMAL' then 2 when 'RARE' then 3 when 'HIGH RARE' then 5 when 'SUPER RARE' then 8 when 'ULTRA RARE' then 12 when 'MYTHIC RARE' then 18 when 'LEGENDARY RARE' then 27 else 2 end::numeric $$;
create or replace function public._lv_cost_g(p_grade text) returns numeric language sql immutable as $$
  select case p_grade when 'NORMAL' then 1 when 'RARE' then 1.5 when 'HIGH RARE' then 2 when 'SUPER RARE' then 3 when 'ULTRA RARE' then 4 when 'MYTHIC RARE' then 6 when 'LEGENDARY RARE' then 9 else 1 end::numeric $$;
create or replace function public._lv_cost(p_grade text, p_level int) returns jsonb language sql immutable as $$
  select jsonb_build_object(
    'blood', greatest(1, ceil(_lv_cost_b(p_grade) * p_level * _lv_cost_mult()))::int,
    'gold',  greatest(1, ceil(_lv_cost_g(p_grade) * p_level * 10 * _lv_cost_mult()))::int) $$;
revoke all on function public._lv_cost_mult() from public, anon, authenticated;

create or replace function public.card_cost_table() returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('ok', true, 'version', 5, 'mult', _lv_cost_mult(),
    'grades', jsonb_object_agg(g, jsonb_build_object('b', _lv_cost_b(g), 'g', _lv_cost_g(g), 'shard', _merge_shard_base(g), 'lv1', _lv_cost(g, 1))))
  from unnest(array['NORMAL','RARE','HIGH RARE','SUPER RARE','ULTRA RARE','MYTHIC RARE','LEGENDARY RARE']) g
$$;
revoke all on function public.card_cost_table() from public, anon;
grant execute on function public.card_cost_table() to authenticated;
