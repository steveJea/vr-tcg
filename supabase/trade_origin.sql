-- ===== 거래 PR1: 인재 출처(src)·귀속(bound) 기록 =====
-- 선행: story_merge.sql(_story_new_card) · gacha.sql(story_gacha_log). 여러 번 실행해도 안전. 화면 거래 기능은 아직 없음
-- 새 인재는 모두 _story_new_card 한 곳에서 만들어짐 → 여기서 호출한 함수(PG_CONTEXT)를 보고 출처를 붙임
--   story_ticket_draw · story_daily_draw → recruit (영입, 거래 가능)
--   story_choose_starter → starter (귀속) · story_complete_phase(챕터 보상) → story (귀속)
--   _story_migrate → legacy (귀속) · 그 밖의 새 경로 → other (귀속: 모르면 막는 쪽이 안전)
-- owned[] 항목에 'src', 'bound', 'got_at' 추가. 기존 함수의 _story_norm 은 다른 키를 그대로 둠

create or replace function public._story_card_src() returns text language plpgsql stable as $$
declare ctx text;
begin
  get diagnostics ctx = pg_context;
  return case when ctx ~ 'story_ticket_draw|story_daily_draw' then 'recruit'
              when ctx ~ 'story_choose_starter' then 'starter'
              when ctx ~ 'story_complete_phase' then 'story'
              when ctx ~ '_story_migrate' then 'legacy'
              else 'other' end;
end $$;

create or replace function public._story_new_card(cid text) returns jsonb language plpgsql volatile as $$
declare s text := _story_card_src();
begin
  return jsonb_build_object('uid', public._story_new_uid(), 'id', cid, 'boost', '{}'::jsonb, 'level', 1, 'exp', 0, 'totalExp', 0, 'cpts', 0, 'spentCard', 0, 'ex', 0, 'exb', 0,
    'src', s, 'bound', s <> 'recruit', 'got_at', extract(epoch from now())::bigint);
end $$;
revoke all on function public._story_card_src(), public._story_new_card(text) from public, anon, authenticated;

-- 기존 보유분 소급 (출처 없는 항목만. 다시 실행해도 이미 정한 것은 그대로)
-- 인재별로: 영입 기록 수(story_gacha_log) − 이미 recruit 로 표시된 수 = 거래 가능으로 돌릴 수 있는 최대치
--          스토리로 받은 것이 확실한 수(클리어한 페이즈 보상 · 시작 인재 · 챕터 0 임유리)는 먼저 귀속으로 뺌
--          남는 것: 영입 기록이 있으면 recruit_backfill(거래 가능), 없으면 unknown(귀속)
create or replace function public._trade_origin_backfill(p_uid uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare d jsonb; o jsonb; res jsonb := '[]'::jsonb; cid text; known jsonb := '{}'::jsonb; avail jsonb := '{}'::jsonb; left_known int; left_rec int;
  n_rec int := 0; n_story int := 0; n_unknown int := 0; total jsonb := '{}'::jsonb; seen jsonb := '{}'::jsonb; i int; arr jsonb;
begin
  select data into d from story_progress where user_id = p_uid for update;
  if d is null or jsonb_typeof(d->'owned') <> 'array' then return null; end if;
  if not exists (select 1 from jsonb_array_elements(d->'owned') x where not (x ? 'src')) then return jsonb_build_object('skipped', true); end if;
  -- 스토리로 받은 것이 확실한 인재 (카드 id → 개수)
  for cid in
    select c.reward_card from story_phase_config c
      where c.reward_card is not null and coalesce(d->'cleared'->(c.chapter::text), '[]'::jsonb) @> to_jsonb(c.phase)
    union all select d->>'starter' where coalesce(d->>'starter', '') <> ''
    union all select '2000100001'
  loop known := jsonb_set(known, array[cid], to_jsonb(coalesce((known->>cid)::int, 0) + 1)); end loop;
  -- 영입 가능분 = 영입 기록 − 이미 recruit 표시
  for cid in select distinct x->>'id' from jsonb_array_elements(d->'owned') x where not (x ? 'src') loop
    avail := jsonb_set(avail, array[cid], to_jsonb(greatest(0,
      (select count(*)::int from story_gacha_log l where l.user_id = p_uid and l.card_id = cid)
      - (select count(*)::int from jsonb_array_elements(d->'owned') y where y->>'id' = cid and y->>'src' in ('recruit', 'recruit_backfill')))));
  end loop;
  -- 출처 없는 항목: 같은 인재 안에서 앞쪽(먼저 받은 것)부터 스토리 몫으로 채우고, 나머지를 영입 몫으로
  for o in select x from jsonb_array_elements(d->'owned') x loop
    if o ? 'src' then res := res || jsonb_build_array(o); continue; end if;
    cid := o->>'id';
    left_known := coalesce((known->>cid)::int, 0);
    left_rec := coalesce((avail->>cid)::int, 0);
    if left_known > 0 then
      o := o || jsonb_build_object('src', 'story', 'bound', true); known := jsonb_set(known, array[cid], to_jsonb(left_known - 1)); n_story := n_story + 1;
    elsif left_rec > 0 then
      o := o || jsonb_build_object('src', 'recruit_backfill', 'bound', false); avail := jsonb_set(avail, array[cid], to_jsonb(left_rec - 1)); n_rec := n_rec + 1;
    else
      o := o || jsonb_build_object('src', 'unknown', 'bound', true); n_unknown := n_unknown + 1;
    end if;
    res := res || jsonb_build_array(o);
  end loop;
  update story_progress set data = jsonb_set(data, '{owned}', res) where user_id = p_uid;
  return jsonb_build_object('story', n_story, 'recruit', n_rec, 'unknown', n_unknown);
end $$;
revoke all on function public._trade_origin_backfill(uuid) from public, anon, authenticated;

do $$ declare u uuid; begin
  for u in select user_id from story_progress loop perform public._trade_origin_backfill(u); end loop;
end $$;

-- 확인: select o->>'src' src, o->>'bound' bound, count(*) from story_progress, jsonb_array_elements(data->'owned') o group by 1, 2 order by 1;
