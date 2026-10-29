-- ⚠ 다시 돌리지 마세요, 최신 아님 (일부): 이 파일의 _story_lock, _story_new_card, story_allocate, story_complete_phase, story_discard, story_discard_many, story_merge 는 뒤 파일에서 다시 정의됨. 이 파일을 다시 돌리면 예전 것으로 되돌아가요. supabase/README.md 참고
-- =====================================================================
-- VR: Abyss Gate - 스토리 카드 개별 인스턴스 + EX 합성 (스토리 모드 전용, 아케이드와 무관)
-- 사용법: story_level_stats.sql 이후 Supabase SQL Editor 에 이 파일 전체를 붙여넣고 Run. 여러 번 실행해도 안전.
--         ※ 이 SQL 을 먼저 실행한 뒤 클라이언트(PR)를 머지하세요. (예전 클라이언트도 카드 id 로 계속 동작하도록 호환 처리됨)
--
-- 1) 데이터 모델: 보유 카드(owned[])의 각 항목 = 카드 1장(인스턴스)
--    { uid(고유), id(카드 id), level, exp, totalExp, boost{ATK,HP,DEF}, cpts, spentCard, ex(EX 단계), exb(EX 보너스 % 합계) }
--    data.leader = 리더 인스턴스 uid (data.starter 는 시작 카드 id 그대로)
--    마이그레이션: count>1 항목은 개별 인스턴스로 분리. 원래 항목(첫 장)이 레벨·EXP·강화·EX 유지, 나머지 사본은 Lv.1 EXP 0
--    (uid 가 이미 있는 항목은 그대로라서 여러 번 실행해도 결과 동일)
-- 2) 모든 RPC 는 인스턴스 uid 로 동작. 예전 클라이언트 호환: uid 대신 카드 id 를 주면 그 카드의 첫 인스턴스로 처리
-- 3) EX 합성 story_merge(p_target, p_material): 같은 카드 id 의 다른 인스턴스 1장을 재료로 소모
--    보너스(%) = 10 × (대상 Lv / 대상 최대 Lv) × (재료 Lv / 재료 최대 Lv), 소수 둘째 자리 반올림
--    기본 스탯에 합산(복리 아님): 기본 × (1 + exb/100), 레벨 %(N1~MR6)는 그 위에 곱함(클라이언트 계산)
--    합성 후 대상 Lv.1 EXP 0 (누적 EXP 유지), 최대 레벨 = 등급 기본 + 5 × EX, 최대 EX: N1 R2 HR3 SR4 UR5 MR6
--    재료: 대상 자신·리더 인스턴스 불가
-- =====================================================================

-- ----- 도우미 -----
create or replace function public._story_cap(g text, ex int default 0) returns int language sql immutable as $$
  select (case g when 'NORMAL' then 20 when 'RARE' then 30 when 'HIGH RARE' then 40 when 'SUPER RARE' then 50 when 'ULTRA RARE' then 60 when 'MYTHIC RARE' then 70 else 20 end) + 5 * greatest(0, coalesce(ex, 0))
$$;
create or replace function public._story_max_ex(g text) returns int language sql immutable as $$
  select case g when 'NORMAL' then 1 when 'RARE' then 2 when 'HIGH RARE' then 3 when 'SUPER RARE' then 4 when 'ULTRA RARE' then 5 when 'MYTHIC RARE' then 6 else 1 end
$$;
drop function if exists public._story_merge_mat_ratio(jsonb);
-- 새 인스턴스 uid
create or replace function public._story_new_uid() returns text language sql volatile as $$
  select 'c' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 15)
$$;
-- 인스턴스 기본값 (count 없음)
create or replace function public._story_norm(e jsonb) returns jsonb language sql immutable as $$
  select (e - 'count') || jsonb_build_object(
    'boost', coalesce(e->'boost', '{}'::jsonb),
    'level', greatest(1, coalesce((e->>'level')::int, 1)), 'exp', greatest(0, coalesce((e->>'exp')::int, 0)),
    'totalExp', greatest(0, coalesce((e->>'totalExp')::int, 0)), 'cpts', greatest(0, coalesce((e->>'cpts')::int, 0)),
    'spentCard', greatest(0, coalesce((e->>'spentCard')::int, 0)),
    'ex', greatest(0, coalesce((e->>'ex')::int, 0)), 'exb', greatest(0, coalesce((e->>'exb')::numeric, 0)))
$$;
-- 새 카드 1장
create or replace function public._story_new_card(cid text) returns jsonb language sql volatile as $$
  select jsonb_build_object('uid', public._story_new_uid(), 'id', cid, 'boost', '{}'::jsonb, 'level', 1, 'exp', 0, 'totalExp', 0, 'cpts', 0, 'spentCard', 0, 'ex', 0, 'exb', 0)
$$;
-- 예전 형식(count) → 인스턴스. 리더 uid 지정. 여러 번 실행해도 결과 동일
create or replace function public._story_migrate(d jsonb) returns jsonb language plpgsql volatile set search_path = public as $$
declare e jsonb; res jsonb := '[]'::jsonb; c int; k int; lead text;
begin
  if d is null then return d; end if;
  if jsonb_typeof(d->'owned') = 'array' then
    for e in select x from jsonb_array_elements(d->'owned') x loop
      continue when jsonb_typeof(e) <> 'object' or coalesce(e->>'id', '') = '';
      if coalesce(e->>'uid', '') <> '' then res := res || jsonb_build_array(_story_norm(e)); continue; end if;
      c := greatest(1, least(500, coalesce((e->>'count')::int, 1)));
      res := res || jsonb_build_array(_story_norm(e) || jsonb_build_object('uid', _story_new_uid()));
      for k in 2..c loop res := res || jsonb_build_array(_story_new_card(e->>'id')); end loop;
    end loop;
    d := jsonb_set(d, '{owned}', res);
  end if;
  lead := d->>'leader';
  if coalesce(d->>'starter', '') <> '' and (lead is null or not exists (select 1 from jsonb_array_elements(coalesce(d->'owned', '[]'::jsonb)) o where o->>'uid' = lead)) then
    select o->>'uid' into lead from jsonb_array_elements(coalesce(d->'owned', '[]'::jsonb)) o where o->>'id' = d->>'starter' limit 1;
    if lead is not null then d := jsonb_set(d, '{leader}', to_jsonb(lead)); end if;
  end if;
  return d;
end $$;
-- 행 잠금 + 마이그레이션
create or replace function public._story_lock(uid uuid) returns jsonb language plpgsql set search_path = public as $$
declare d jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  insert into story_progress (user_id, data) values (uid, '{}'::jsonb) on conflict (user_id) do nothing;
  select data into d from story_progress where user_id = uid for update;
  return _story_migrate(coalesce(d, '{}'::jsonb));
end $$;
-- 인스턴스 찾기: uid 우선, 없으면 카드 id 의 첫 인스턴스 (예전 클라이언트 호환). 0부터 시작하는 위치, 없으면 null
create or replace function public._story_find(owned jsonb, k text) returns int language sql immutable as $$
  select coalesce(
    (select (n - 1)::int from jsonb_array_elements(owned) with ordinality x(e, n) where x.e->>'uid' = k limit 1),
    (select (n - 1)::int from jsonb_array_elements(owned) with ordinality x(e, n) where x.e->>'id' = k order by n limit 1))
$$;
create or replace function public._story_owned(d jsonb) returns jsonb language sql immutable as $$
  select case when jsonb_typeof(d->'owned') = 'array' then d->'owned' else '[]'::jsonb end
$$;
revoke all on function public._story_cap(text, int), public._story_max_ex(text), public._story_new_uid(), public._story_norm(jsonb), public._story_new_card(text),
  public._story_migrate(jsonb), public._story_lock(uuid), public._story_find(jsonb, text), public._story_owned(jsonb) from public, anon, authenticated;

-- ----- 시작 캐릭터 선택: 새 인스턴스를 맨 앞(리더)으로. 이미 가진 같은 카드(뽑기 등)는 그대로 유지 -----
create or replace function public.story_choose_starter(p_id text) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb; e jsonb;
begin
  if p_id not in ('10111', '10265', '10224') then raise exception 'invalid starter'; end if;
  d := _story_lock(uid);
  if coalesce(d->>'starter', '') <> '' then raise exception 'starter already chosen'; end if;
  e := _story_new_card(p_id);
  d := jsonb_set(jsonb_set(jsonb_set(d, '{starter}', to_jsonb(p_id)), '{leader}', e->'uid'), '{owned}', jsonb_build_array(e) || _story_owned(d));
  if d->'points' is null then d := jsonb_set(d, '{points}', '0'::jsonb); end if;
  if d->'cleared' is null then d := jsonb_set(d, '{cleared}', '{}'::jsonb); end if;
  return _story_save(uid, d);
end $$;

-- ----- 일일 뽑기: 뽑을 때마다 새 인스턴스. count = 그 카드 보유 장수 -----
create or replace function public.story_daily_draw() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); today date := (now() at time zone 'Asia/Seoul')::date; last date; r double precision; g text; cid text; d jsonb; owned jsonb; e jsonb; cnt int;
begin
  if uid is null then raise exception 'login required'; end if;
  insert into story_gacha (user_id, last_draw) values (uid, today - 1) on conflict (user_id) do nothing;
  select last_draw into last from story_gacha where user_id = uid for update;
  if last >= today then return jsonb_build_object('ok', false, 'reason', 'already', 'day', today); end if;
  r := random();
  g := case when r < 0.70 then 'NORMAL' when r < 0.90 then 'RARE' when r < 0.965 then 'HIGH RARE' when r < 0.995 then 'SUPER RARE' else 'ULTRA RARE' end;
  select id into cid from story_card_pool where grade = g and coalesce(gacha, true) order by random() limit 1;
  if cid is null then raise exception 'empty pool for %', g; end if;
  d := _story_lock(uid);
  e := _story_new_card(cid);
  owned := _story_owned(d) || jsonb_build_array(e);
  select count(*) into cnt from jsonb_array_elements(owned) o where o->>'id' = cid;
  d := jsonb_set(jsonb_set(d, '{owned}', owned), '{gachaLast}', to_jsonb(today::text));
  d := _story_save(uid, d);
  update story_gacha set last_draw = today, updated_at = now() where user_id = uid;
  insert into story_gacha_log (user_id, card_id, grade) values (uid, cid, g);
  return jsonb_build_object('ok', true, 'card_id', cid, 'uid', e->>'uid', 'grade', g, 'count', cnt, 'day', today);
end $$;
revoke all on function public.story_daily_draw() from public, anon;
grant execute on function public.story_daily_draw() to authenticated;

-- ----- 페이즈 클리어 + 전투 EXP. p_stats = [{"uid":"인스턴스 uid"(또는 "id":"카드 id"),"kills":n}, ...] -----
create or replace function public.story_complete_phase(p_chapter int, p_phase int, p_stats jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb; cfg story_phase_config; b jsonb; cl jsonb; first boolean; rid text; ruid text; owned jsonb; ne jsonb;
        st jsonb; idx int; k int; ksum int := 0; gain int; g text; before int; res jsonb := '[]'::jsonb; seen int[] := '{}'; key text;
begin
  select * into cfg from story_phase_config where chapter = p_chapter and phase = p_phase;
  if cfg is null then raise exception 'invalid phase'; end if;
  d := _story_lock(uid);
  b := d->'battle';
  if b is null or (b->>'chapter')::int <> p_chapter or (b->>'phase')::int <> p_phase then raise exception 'battle not started'; end if;
  if extract(epoch from clock_timestamp()) - (b->>'at')::bigint < _story_min_battle_secs() then raise exception 'too fast'; end if;
  d := d - 'battle';
  cl := coalesce(d->'cleared'->(p_chapter::text), '[]'::jsonb);
  first := not cl @> to_jsonb(p_phase);
  owned := _story_owned(d);
  if first then
    if d->'cleared' is null or jsonb_typeof(d->'cleared') <> 'object' then d := jsonb_set(d, '{cleared}', '{}'::jsonb); end if;
    d := jsonb_set(d, array['cleared', p_chapter::text], cl || to_jsonb(p_phase));
    d := jsonb_set(d, '{points}', to_jsonb(coalesce((d->>'points')::int, 0) + cfg.points));
    if cfg.reward_grade is not null then
      select p.id into rid from story_card_pool p
        where p.grade = cfg.reward_grade and p.gacha and not exists (select 1 from jsonb_array_elements(owned) o where o->>'id' = p.id)
        order by random() limit 1;
      if rid is not null then ne := _story_new_card(rid); ruid := ne->>'uid'; owned := owned || jsonb_build_array(ne); end if;
    end if;
  end if;
  if jsonb_typeof(p_stats) = 'array' and jsonb_array_length(p_stats) <= 30 then
    for st in select * from jsonb_array_elements(p_stats) loop
      continue when jsonb_typeof(st) <> 'object';
      key := coalesce(st->>'uid', st->>'id');
      continue when key is null or key = rid or key = ruid;
      idx := _story_find(owned, key);
      continue when idx is null or idx = any(seen) or (owned->idx->>'uid') = ruid;
      seen := seen || idx;
      k := least(greatest(0, coalesce((st->>'kills')::int, 0)), greatest(0, cfg.enemy_count - ksum));
      ksum := ksum + k;
      gain := (60 + 20 * k) * (case when cfg.type = 'boss' then 2 else 1 end);
      select grade into g from story_card_pool where id = owned->idx->>'id';
      before := coalesce((owned->idx->>'level')::int, 1);
      owned := jsonb_set(owned, array[idx::text], _story_gain(owned->idx, gain, coalesce(g, 'NORMAL')));
      res := res || jsonb_build_object('uid', owned->idx->>'uid', 'id', owned->idx->>'id', 'kills', k, 'exp', gain, 'from', before, 'level', (owned->idx->>'level')::int);
    end loop;
  end if;
  d := jsonb_set(d, '{owned}', owned);
  d := _story_save(uid, d);
  return jsonb_build_object('data', d, 'first', first, 'points', case when first then cfg.points else 0 end, 'reward_id', rid, 'reward_uid', ruid, 'exp', res);
end $$;

-- ----- 스탯 분배: p_alloc = { "인스턴스 uid"(또는 카드 id): {"ATK":n,...} }. 카드 전용 포인트 먼저 -----
create or replace function public.story_allocate(p_alloc jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb; owned jsonb; k text; v jsonb; s text; n int; total int; gtotal int := 0; idx int; pts int; cp int; fromCard int;
begin
  if jsonb_typeof(p_alloc) <> 'object' then raise exception 'invalid alloc'; end if;
  d := _story_lock(uid);
  owned := _story_owned(d);
  pts := greatest(0, coalesce((d->>'points')::int, 0));
  for k, v in select * from jsonb_each(p_alloc) loop
    idx := _story_find(owned, k);
    if idx is null then raise exception 'card not owned'; end if;
    if jsonb_typeof(v) <> 'object' then raise exception 'invalid alloc'; end if;
    owned := jsonb_set(owned, array[idx::text], _story_norm(owned->idx));
    total := 0;
    for s in select jsonb_object_keys(v) loop
      if s not in ('ATK', 'HP', 'DEF') then raise exception 'invalid stat'; end if;
      if jsonb_typeof(v->s) <> 'number' then raise exception 'invalid amount'; end if;
      n := (v->>s)::int;
      if n < 0 or n::text <> (v->>s) then raise exception 'invalid amount'; end if;
      total := total + n;
      owned := jsonb_set(owned, array[idx::text, 'boost'], coalesce(owned->idx->'boost', '{}'::jsonb) || jsonb_build_object(s, coalesce((owned->idx->'boost'->>s)::int, 0) + n));
    end loop;
    cp := (owned->idx->>'cpts')::int;
    fromCard := least(cp, total);
    gtotal := gtotal + (total - fromCard);
    owned := jsonb_set(owned, array[idx::text], owned->idx || jsonb_build_object('cpts', cp - fromCard, 'spentCard', (owned->idx->>'spentCard')::int + fromCard));
  end loop;
  if gtotal > pts then raise exception 'not enough points'; end if;
  d := jsonb_set(jsonb_set(d, '{owned}', owned), '{points}', to_jsonb(pts - gtotal));
  return _story_save(uid, d);
end $$;

-- ----- 일괄 폐기 (인스턴스 단위): 각 장 EXP = 등급 기본 × (대상과 같은 이름이면 1.5) + 그 장의 누적 EXP 50%, 공용 포인트로 올린 강화 환급 -----
--       대상 자신·리더 인스턴스 불가, 같은 장 중복 지정 불가, 최대 200장. 전부 성공 또는 전부 취소
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
    -- 예전 클라이언트(카드 id): 아직 고르지 않은 그 카드의 인스턴스 중 대상·리더가 아닌 첫 장
    select x.e->>'uid' into u1 from jsonb_array_elements(owned) with ordinality x(e, k)
      where (x.e->>'uid' = pid or (x.e->>'id' = pid and not exists (select 1 from jsonb_array_elements(owned) y where y->>'uid' = pid)))
        and not (x.e->>'uid' = any(gone)) and (x.e->>'uid' = pid or (x.e->>'uid' <> tuid and x.e->>'uid' is distinct from lead))
      order by k limit 1;
    if u1 is null then raise exception 'card not owned'; end if;
    if u1 = tuid then raise exception 'cannot discard target'; end if;
    if u1 = lead then raise exception 'cannot discard leader'; end if;
    gone := gone || u1;
    select x.e into e1 from jsonb_array_elements(owned) x(e) where x.e->>'uid' = u1;
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

-- ----- 1장 폐기 = 일괄 폐기 1장 (결과 형식은 예전과 같음) -----
create or replace function public.story_discard(p_id text, p_target text) returns jsonb language plpgsql security definer set search_path = public as $$
declare r jsonb;
begin
  r := public.story_discard_many(array[p_id], p_target);
  return r - 'count';
end $$;
revoke all on function public.story_discard(text, text) from public, anon;
grant execute on function public.story_discard(text, text) to authenticated;

-- ----- EX 합성 -----
drop function if exists public.story_merge(text);
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

-- ----- 기존 데이터 마이그레이션 (예전 형식 행만 바뀜) -----
update public.story_progress sp set data = public._story_migrate(sp.data), updated_at = now()
  where exists (select 1 from jsonb_array_elements(case when jsonb_typeof(sp.data->'owned') = 'array' then sp.data->'owned' else '[]'::jsonb end) o where coalesce(o->>'uid', '') = '')
     or (coalesce(sp.data->>'starter', '') <> '' and sp.data->'leader' is null);
