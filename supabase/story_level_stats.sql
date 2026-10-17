-- =====================================================================
-- VR: Abyss Gate - 스토리 카드 레벨 스탯 + 일괄 폐기 (추가분)
-- 사용법: story_levels.sql 이후 Supabase SQL Editor 에 붙여넣고 Run. 여러 번 실행해도 안전.
-- 1) 레벨업 보상 변경: 레벨업마다 주던 카드 전용 포인트(cpts) +1 지급을 중단.
--    대신 레벨당 기본 스탯 % 상승(N1 R2 HR3 SR4 UR5 MR6 %)은 클라이언트가 레벨로 계산(레벨·EXP는 서버가 확정).
--    이미 받은 cpts(남은 것)·이미 분배한 스탯은 그대로 유지(아무것도 회수하지 않음).
-- 2) story_discard_many(p_ids text[], p_target text): 여러 장을 한 번에 폐기, EXP는 대상 1장에. 전부 성공 또는 전부 취소.
-- =====================================================================

-- 1) EXP 획득: 레벨업 시 cpts 지급 없음
create or replace function public._story_gain(e jsonb, amt int, g text) returns jsonb language plpgsql immutable as $$
declare lv int; ex int; tot int; cap int;
begin
  e := _story_norm(e);
  lv := (e->>'level')::int; ex := (e->>'exp')::int; cap := _story_cap(g, (e->>'ex')::int);
  if lv >= cap then return e || jsonb_build_object('exp', 0); end if;
  ex := ex + greatest(0, amt);
  tot := (e->>'totalExp')::int;
  while lv < cap and ex >= lv * 100 loop ex := ex - lv * 100; lv := lv + 1; end loop;
  if lv >= cap then tot := tot + greatest(0, amt) - ex; ex := 0; else tot := tot + greatest(0, amt); end if;
  return e || jsonb_build_object('level', lv, 'exp', ex, 'totalExp', tot);
end $$;
revoke all on function public._story_gain(jsonb, int, text) from public, anon, authenticated;

-- 2) 일괄 폐기. p_ids 의 같은 id 가 여러 번 있으면 그만큼(사본부터) 폐기.
--    규칙은 story_discard 와 같음: 등급 기본 EXP × (대상과 같은 이름이면 1.5), 마지막 1장이면 누적 EXP 50% 추가 + 공용 포인트로 올린 강화 환급.
--    대상 카드 자신과 리더의 마지막 1장은 폐기 불가. 최대 200장.
create or replace function public.story_discard_many(p_ids text[], p_target text) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb; owned jsonb; pid text; i1 int; i2 int; e1 jsonb; c1 int; g1 text; n1 text; g2 text; n2 text;
        amt int; total int := 0; refund int := 0; n int := 0; before int; t jsonb;
begin
  if p_ids is null or cardinality(p_ids) = 0 then raise exception 'nothing to discard'; end if;
  if cardinality(p_ids) > 200 then raise exception 'too many cards'; end if;
  if p_target = any(p_ids) then raise exception 'cannot discard target'; end if;
  d := _story_lock(uid);
  owned := case when jsonb_typeof(d->'owned') = 'array' then d->'owned' else '[]'::jsonb end;
  if not exists (select 1 from jsonb_array_elements(owned) o where o->>'id' = p_target) then raise exception 'card not owned'; end if;
  select grade, name into g2, n2 from story_card_pool where id = p_target;
  foreach pid in array p_ids loop
    select i - 1 into i1 from jsonb_array_elements(owned) with ordinality x(e, i) where x.e->>'id' = pid limit 1;
    if i1 is null then raise exception 'card not owned'; end if;
    e1 := _story_norm(owned->i1); c1 := (e1->>'count')::int;
    if c1 <= 1 and pid = coalesce(d->>'starter', '') then raise exception 'cannot discard leader'; end if;
    select grade, name into g1, n1 from story_card_pool where id = pid;
    amt := _story_feed_exp(coalesce(g1, 'NORMAL'));
    if n1 is not null and n1 = n2 then amt := floor(amt * 1.5); end if;
    if c1 <= 1 then
      amt := amt + floor((e1->>'totalExp')::int * 0.5);
      refund := refund + greatest(0, coalesce((e1->'boost'->>'ATK')::int,0) + coalesce((e1->'boost'->>'HP')::int,0) + coalesce((e1->'boost'->>'DEF')::int,0) - (e1->>'spentCard')::int);
      owned := owned - i1;
    else
      owned := jsonb_set(owned, array[i1::text, 'count'], to_jsonb(c1 - 1));
    end if;
    total := total + amt; n := n + 1;
  end loop;
  select i - 1 into i2 from jsonb_array_elements(owned) with ordinality x(e, i) where x.e->>'id' = p_target limit 1;
  before := coalesce((owned->i2->>'level')::int, 1);
  t := _story_gain(owned->i2, total, coalesce(g2, 'NORMAL'));
  owned := jsonb_set(owned, array[i2::text], t);
  d := jsonb_set(d, '{owned}', owned);
  if refund > 0 then d := jsonb_set(d, '{points}', to_jsonb(coalesce((d->>'points')::int, 0) + refund)); end if;
  d := _story_save(uid, d);
  return jsonb_build_object('data', d, 'count', n, 'exp', total, 'from', before, 'level', (t->>'level')::int, 'refund', refund);
end $$;
revoke all on function public.story_discard_many(text[], text) from public, anon;
grant execute on function public.story_discard_many(text[], text) to authenticated;
