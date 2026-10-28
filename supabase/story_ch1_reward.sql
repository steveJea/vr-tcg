-- =====================================================================
-- 챕터 1 페이즈별 고정 보상 카드 (모든 루트 동일). 여러 번 실행해도 안전 (idempotent)
-- 1-1 예유진 · 1-2 남태은 · 1-3 선나영 · 1-4 반지아 · 1-5 이윤이
-- 첫 클리어 때만 지급, 이미 보유한 카드면 한 장 더(중복). 소급 지급 없음.
-- 전제: phaseE_2.sql 적용됨 (원래 완료 함수가 _story_complete_phase_e0 로 보관된 상태)
-- 변경: _story_complete_phase_e0 = story_merge.sql 버전 + reward_card 우선 (그 외 동작 동일)
-- =====================================================================
alter table public.story_phase_config add column if not exists reward_card text;

-- (보상 카드 5장 모두 story_card_pool 에 이미 있음: 2026-10-25 확인)
update public.story_phase_config set reward_card = case phase
  when 1 then '10248' when 2 then '10093' when 3 then '10185' when 4 then '10130' when 5 then '10308' end
where chapter = 1 and phase between 1 and 5;

do $$ begin
  if to_regprocedure('public._story_complete_phase_e0(int,int,jsonb)') is null then
    raise exception 'phaseE_2.sql 을 먼저 적용하세요 (_story_complete_phase_e0 없음)';
  end if;
end $$;

create or replace function public._story_complete_phase_e0(p_chapter int, p_phase int, p_stats jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
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
    if cfg.reward_card is not null then
      -- 페이즈 고정 보상 카드: 이미 보유해도 한 장 더 (중복 지급)
      rid := cfg.reward_card; ne := _story_new_card(rid); ruid := ne->>'uid'; owned := owned || jsonb_build_array(ne);
    elsif cfg.reward_grade is not null then
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
      continue when key is null or key = ruid or (key = rid and st->>'uid' is null);
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
revoke all on function public._story_complete_phase_e0(int, int, jsonb) from public, anon, authenticated;

-- 확인용
select chapter, phase, reward_grade, reward_card, (select name from public.story_card_pool p where p.id = c.reward_card) as card_name
from public.story_phase_config c where chapter = 1 order by phase;
