-- ⚠ 다시 돌리지 마세요, 최신 아님 (일부): 이 파일의 story_discard_many, story_merge, story_set_lock 는 뒤 파일에서 다시 정의됨. 이 파일을 다시 돌리면 예전 것으로 되돌아가요. supabase/README.md 참고
-- ===== 스토리: 리더 변경 + 분해 잠금 (supabase/story_leader_lock.sql) =====
-- SQL Editor 에서 그대로 실행 (여러 번 실행해도 안전). service_role 필요 없음.
-- 저장 형식: data.owned[i].locked = true (잠금), data.leader = 리더 인스턴스 uid (리더는 항상 잠금 취급, 따로 저장 안 함)
-- 리더 스킬 효과와 리더 쓰러짐 패널티는 전투(클라이언트) 계산이라 SQL 없음.

-- 1) 분해 잠금 켜기/끄기: p_uid = 인스턴스 uid, p_on = true(잠금) / false(해제)
create or replace function public.story_set_lock(p_uid text, p_on boolean) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb; owned jsonb; i int; e jsonb;
begin
  d := _story_lock(uid);
  owned := _story_owned(d);
  select (n - 1)::int into i from jsonb_array_elements(owned) with ordinality x(e, n) where x.e->>'uid' = p_uid;
  if i is null then raise exception 'card not owned'; end if;
  e := owned->i;
  e := case when coalesce(p_on, false) then e || jsonb_build_object('locked', true) else e - 'locked' end;
  owned := jsonb_set(owned, array[i::text], e);
  d := _story_save(uid, jsonb_set(d, '{owned}', owned));
  return jsonb_build_object('data', d, 'uid', p_uid, 'locked', coalesce(p_on, false));
end $$;
revoke all on function public.story_set_lock(text, boolean) from public, anon;
grant execute on function public.story_set_lock(text, boolean) to authenticated;

-- 2) 리더 변경: 챕터 1의 모든 페이즈를 클리어해야 가능. 내가 가진 카드(인스턴스 uid)만. 시작 캐릭터(data.starter)·루트는 그대로
create or replace function public.story_set_leader(p_uid text) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb; owned jsonb; tot int; got int; prev text;
begin
  d := _story_lock(uid);
  owned := _story_owned(d);
  if coalesce(p_uid, '') = '' or p_uid like 'guest:%' or not exists (select 1 from jsonb_array_elements(owned) x where x->>'uid' = p_uid) then raise exception 'card not owned'; end if;
  select count(*) into tot from story_phase_config where chapter = 1;
  select count(*) into got from story_phase_config c
    where c.chapter = 1 and coalesce(case when jsonb_typeof(d->'cleared'->'1') = 'array' then d->'cleared'->'1' end, '[]'::jsonb) @> to_jsonb(c.phase);
  if tot = 0 or got < tot then raise exception 'chapter 1 not cleared'; end if;
  prev := d->>'leader';
  d := _story_save(uid, jsonb_set(d, '{leader}', to_jsonb(p_uid)));
  return jsonb_build_object('data', d, 'leader', p_uid, 'prev', prev);
end $$;
revoke all on function public.story_set_leader(text) from public, anon;
grant execute on function public.story_set_leader(text) to authenticated;

-- 3) 일괄 분해: 잠긴 카드·리더·대상은 분해 불가 (나머지는 story_merge.sql 판과 같음)
create or replace function public.story_discard_many(p_ids text[], p_target text) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb; owned jsonb; pid text; i1 int; i2 int; e1 jsonb; g1 text; n1 text; g2 text; n2 text; tuid text; lead text;
        amt int; total int := 0; refund int := 0; n int := 0; before int; t jsonb; gone text[] := '{}'; u1 text;
begin
  if p_ids is null or cardinality(p_ids) = 0 then raise exception 'nothing to discard'; end if;
  if cardinality(p_ids) > 200 then raise exception 'too many cards'; end if;
  d := _story_lock(uid);
  owned := _story_owned(d); lead := d->>'leader';
  i2 := _story_find(owned, p_target);
  if i2 is null then raise exception 'card not owned'; end if;
  tuid := owned->i2->>'uid';
  select grade, name into g2, n2 from story_card_pool where id = owned->i2->>'id';
  foreach pid in array p_ids loop
    -- 예전 클라이언트(카드 id): 아직 고르지 않은 그 카드의 인스턴스 중 대상·리더·잠금이 아닌 첫 장
    select x.e->>'uid' into u1 from jsonb_array_elements(owned) with ordinality x(e, k)
      where (x.e->>'uid' = pid or (x.e->>'id' = pid and not exists (select 1 from jsonb_array_elements(owned) y where y->>'uid' = pid)))
        and not (x.e->>'uid' = any(gone))
        and (x.e->>'uid' = pid or (x.e->>'uid' <> tuid and x.e->>'uid' is distinct from lead and coalesce((x.e->>'locked')::boolean, false) = false))
      order by k limit 1;
    if u1 is null then raise exception 'card not owned'; end if;
    if u1 = tuid then raise exception 'cannot discard target'; end if;
    if u1 = lead then raise exception 'cannot discard leader'; end if;
    select x.e into e1 from jsonb_array_elements(owned) x(e) where x.e->>'uid' = u1;
    if coalesce((e1->>'locked')::boolean, false) then raise exception 'card locked'; end if;
    gone := gone || u1;
    e1 := _story_norm(e1);
    select grade, name into g1, n1 from story_card_pool where id = e1->>'id';
    amt := _story_feed_exp(coalesce(g1, 'NORMAL'));
    if n1 is not null and n1 = n2 then amt := floor(amt * 1.5); end if;
    amt := amt + floor((e1->>'totalExp')::int * 0.5);
    refund := refund + greatest(0, coalesce((e1->'boost'->>'ATK')::int,0) + coalesce((e1->'boost'->>'HP')::int,0) + coalesce((e1->'boost'->>'DEF')::int,0) - (e1->>'spentCard')::int);
    total := total + amt; n := n + 1;
  end loop;
  select coalesce(jsonb_agg(x.e order by k), '[]'::jsonb) into owned from jsonb_array_elements(owned) with ordinality x(e, k) where not (x.e->>'uid' = any(gone));
  i2 := _story_find(owned, tuid);
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
-- (1장 분해 story_discard 는 story_discard_many 를 부르므로 그대로 잠금 검사가 적용됨)

-- 4) EX 합성: 잠긴 카드·리더는 재료로 못 씀 (나머지는 story_merge.sql 판과 같음)
create or replace function public.story_merge(p_target text, p_material text) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb; owned jsonb; it int; im int; et jsonb; em jsonb; g text; ex int; lt int; ct int; lm int; cm int; bonus numeric; exb numeric;
begin
  d := _story_lock(uid);
  owned := _story_owned(d);
  select (n - 1)::int into it from jsonb_array_elements(owned) with ordinality x(e, n) where x.e->>'uid' = p_target;
  select (n - 1)::int into im from jsonb_array_elements(owned) with ordinality x(e, n) where x.e->>'uid' = p_material;
  if it is null or im is null then raise exception 'card not owned'; end if;
  if it = im then raise exception 'material is target'; end if;
  et := _story_norm(owned->it); em := _story_norm(owned->im);
  if et->>'id' <> em->>'id' then raise exception 'material must be same card'; end if;
  if em->>'uid' = coalesce(d->>'leader', '') then raise exception 'cannot use leader as material'; end if;
  if coalesce((em->>'locked')::boolean, false) then raise exception 'card locked'; end if;
  select grade into g from story_card_pool where id = et->>'id';
  g := coalesce(g, 'NORMAL');
  ex := (et->>'ex')::int;
  if ex >= _story_max_ex(g) then raise exception 'max ex'; end if;
  lt := (et->>'level')::int; ct := _story_cap(g, ex);
  lm := (em->>'level')::int; cm := _story_cap(g, (em->>'ex')::int);
  bonus := round(10 * least(1, lt::numeric / ct) * least(1, lm::numeric / cm), 2);
  exb := round((et->>'exb')::numeric + bonus, 2);
  et := et || jsonb_build_object('ex', ex + 1, 'exb', exb, 'level', 1, 'exp', 0);
  owned := jsonb_set(owned, array[it::text], et);
  owned := owned - im;
  d := _story_save(uid, jsonb_set(d, '{owned}', owned));
  return jsonb_build_object('data', d, 'ex', ex + 1, 'bonus', bonus, 'exb', exb, 'target_level', lt, 'target_cap', ct, 'material_level', lm, 'material_cap', cm, 'cap_to', _story_cap(g, ex + 1));
end $$;
revoke all on function public.story_merge(text, text) from public, anon;
grant execute on function public.story_merge(text, text) to authenticated;
