-- ===== 스토리 스탯 포인트 규칙 변경 (statV 2) — Supabase SQL Editor 에서 한 번 실행 =====
-- 규칙: 포인트 1당 ATK +1 / HP +5 / DEF +1 (상승량 계산은 클라이언트 js/story.js ptGain, 서버는 포인트 개수만 저장)
--       같은 스탯 6번째 포인트부터 절반 (클라이언트 계산) · 한 스탯에는 그 카드 포인트 합계의 절반(올림)까지 (여기서 검사)
-- 예전 분배는 전부 돌려줌: 카드 전용 포인트로 쓴 양(spentCard)은 그 카드 cpts 로, 나머지는 공용 points 로. boost = {}
-- 여러 번 실행해도 안전 (statV 가 2 이상이면 건드리지 않음)

create or replace function public._story_refund_stats(d jsonb) returns jsonb language plpgsql immutable as $$
declare e jsonb; res jsonb := '[]'::jsonb; used int; crd int; pts int; total int := 0;
begin
  if d is null or coalesce((d->>'statV')::int, 1) >= 2 then return d; end if;
  pts := greatest(0, coalesce((d->>'points')::int, 0));
  if jsonb_typeof(d->'owned') = 'array' then
    for e in select x from jsonb_array_elements(d->'owned') x loop
      if jsonb_typeof(e) = 'object' then
        used := greatest(0, coalesce((e->'boost'->>'ATK')::int, 0)) + greatest(0, coalesce((e->'boost'->>'HP')::int, 0)) + greatest(0, coalesce((e->'boost'->>'DEF')::int, 0));
        crd := least(used, greatest(0, coalesce((e->>'spentCard')::int, 0)));
        pts := pts + used - crd; total := total + used;
        e := e || jsonb_build_object('boost', '{}'::jsonb, 'spentCard', 0, 'cpts', greatest(0, coalesce((e->>'cpts')::int, 0)) + crd);
      end if;
      res := res || jsonb_build_array(e);
    end loop;
    d := jsonb_set(d, '{owned}', res);
  end if;
  return d || jsonb_build_object('points', pts, 'statV', 2) || case when total > 0 then jsonb_build_object('statRefunded', true) else '{}'::jsonb end;
end $$;

-- 행 잠금 + 마이그레이션 + (예전 규칙이면) 환급
create or replace function public._story_lock(uid uuid) returns jsonb language plpgsql set search_path = public as $$
declare d jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  insert into story_progress (user_id, data) values (uid, jsonb_build_object('statV', 2)) on conflict (user_id) do nothing;
  select data into d from story_progress where user_id = uid for update;
  return _story_refund_stats(_story_migrate(coalesce(d, '{}'::jsonb)));
end $$;
revoke all on function public._story_refund_stats(jsonb), public._story_lock(uuid) from public, anon, authenticated;

-- ----- 스탯 분배: p_alloc = { "인스턴스 uid"(또는 카드 id): {"ATK":n,...} }. 카드 전용 포인트 먼저 · 한 스탯 ≤ 합계의 절반(올림) -----
create or replace function public.story_allocate(p_alloc jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb; owned jsonb; k text; v jsonb; s text; n int; total int; gtotal int := 0; idx int; pts int; cp int; fromCard int; b jsonb; bsum int;
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
    b := owned->idx->'boost';
    bsum := coalesce((b->>'ATK')::int, 0) + coalesce((b->>'HP')::int, 0) + coalesce((b->>'DEF')::int, 0);
    if greatest(coalesce((b->>'ATK')::int, 0), coalesce((b->>'HP')::int, 0), coalesce((b->>'DEF')::int, 0)) > (bsum + 1) / 2 then raise exception 'stat cap'; end if;
    cp := (owned->idx->>'cpts')::int;
    fromCard := least(cp, total);
    gtotal := gtotal + (total - fromCard);
    owned := jsonb_set(owned, array[idx::text], owned->idx || jsonb_build_object('cpts', cp - fromCard, 'spentCard', (owned->idx->>'spentCard')::int + fromCard));
  end loop;
  if gtotal > pts then raise exception 'not enough points'; end if;
  d := jsonb_set(jsonb_set(d, '{owned}', owned), '{points}', to_jsonb(pts - gtotal));
  return _story_save(uid, d);
end $$;

-- 기존 기록 전부 지금 환급 (다음 접속 때 안내 팝업이 뜸)
update story_progress set data = public._story_refund_stats(public._story_migrate(data)) where coalesce((data->>'statV')::int, 1) < 2;
