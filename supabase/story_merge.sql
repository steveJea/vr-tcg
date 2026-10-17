-- =====================================================================
-- VR: Abyss Gate - 스토리 EX 합성 (스토리 모드 전용, 아케이드와 무관)
-- 사용법: story_level_stats.sql 이후 Supabase SQL Editor 에 붙여넣고 Run. 여러 번 실행해도 안전.
-- 규칙
--  * 대상 카드 + 같은 카드(id) 중복 1장을 소모 → EX 단계 +1 ([EX1] 이름 ...). 리더도 가능
--  * 최대 EX: N1 R2 HR3 SR4 UR5 MR6
--  * 보너스(%) = 10 × (대상 레벨 / 대상 최대 레벨) × (재료 레벨 비율). 소수 둘째 자리 반올림
--    재료 레벨 비율: 중복 사본은 레벨을 따로 갖지 않으므로(개수만 저장) 지금은 1(= 최대 레벨 취급).
--    _story_merge_mat_ratio() 만 바꾸면 규칙 변경 가능
--  * 보너스는 기본 스탯에 더하기(누적 합산, 복리 아님): 기본 × (1 + exb/100). 레벨 % 보너스는 그 위에 곱함 (클라이언트 계산)
--  * 합성 후 대상 레벨 1, EXP 0 (누적 EXP는 유지). 최대 레벨 = 등급 기본 + 5 × EX
-- 보유 카드 항목에 추가되는 값: ex(EX 단계), exb(EX 보너스 % 합계)
-- =====================================================================

-- 최대 레벨: EX 단계마다 +5
create or replace function public._story_cap(g text, ex int default 0) returns int language sql immutable as $$
  select (case g when 'NORMAL' then 20 when 'RARE' then 30 when 'HIGH RARE' then 40 when 'SUPER RARE' then 50 when 'ULTRA RARE' then 60 when 'MYTHIC RARE' then 70 else 20 end) + 5 * greatest(0, coalesce(ex, 0))
$$;
-- 등급별 최대 EX 단계
create or replace function public._story_max_ex(g text) returns int language sql immutable as $$
  select case g when 'NORMAL' then 1 when 'RARE' then 2 when 'HIGH RARE' then 3 when 'SUPER RARE' then 4 when 'ULTRA RARE' then 5 when 'MYTHIC RARE' then 6 else 1 end
$$;
-- 재료(중복 사본) 레벨 비율. 사본은 레벨이 따로 없어서 1
create or replace function public._story_merge_mat_ratio(e jsonb) returns numeric language sql immutable as $$ select 1.0::numeric $$;
revoke all on function public._story_cap(text, int), public._story_max_ex(text), public._story_merge_mat_ratio(jsonb) from public, anon, authenticated;

create or replace function public.story_merge(p_id text) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb; owned jsonb; i int; e jsonb; g text; ex int; lv int; cap int; bonus numeric; exb numeric;
begin
  d := _story_lock(uid);
  owned := case when jsonb_typeof(d->'owned') = 'array' then d->'owned' else '[]'::jsonb end;
  select x.n - 1 into i from jsonb_array_elements(owned) with ordinality x(e, n) where x.e->>'id' = p_id limit 1;
  if i is null then raise exception 'card not owned'; end if;
  e := _story_norm(owned->i);
  if (e->>'count')::int < 2 then raise exception 'no duplicate'; end if;
  select grade into g from story_card_pool where id = p_id;
  g := coalesce(g, 'NORMAL');
  ex := greatest(0, coalesce((e->>'ex')::int, 0));
  if ex >= _story_max_ex(g) then raise exception 'max ex'; end if;
  lv := (e->>'level')::int; cap := _story_cap(g, ex);
  bonus := round(10 * least(1, lv::numeric / cap) * _story_merge_mat_ratio(e), 2);
  exb := round(coalesce((e->>'exb')::numeric, 0) + bonus, 2);
  e := e || jsonb_build_object('count', (e->>'count')::int - 1, 'ex', ex + 1, 'exb', exb, 'level', 1, 'exp', 0);
  owned := jsonb_set(owned, array[i::text], e);
  d := _story_save(uid, jsonb_set(d, '{owned}', owned));
  return jsonb_build_object('data', d, 'ex', ex + 1, 'bonus', bonus, 'exb', exb, 'from_level', lv, 'cap_from', cap, 'cap_to', _story_cap(g, ex + 1));
end $$;
revoke all on function public.story_merge(text) from public, anon;
grant execute on function public.story_merge(text) to authenticated;
