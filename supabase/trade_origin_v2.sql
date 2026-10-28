-- ===== 거래 PR1 후속: 스토리 보상만 귀속, 나머지는 모두 거래 가능 =====
-- 선행: trade_origin.sql. 여러 번 실행해도 안전
-- 앞으로: story(챕터 보상·스토리 지급)만 bound=true. recruit·starter·legacy·other 는 거래 가능
create or replace function public._story_new_card(cid text) returns jsonb language plpgsql volatile as $$
declare s text := _story_card_src();
begin
  return jsonb_build_object('uid', public._story_new_uid(), 'id', cid, 'boost', '{}'::jsonb, 'level', 1, 'exp', 0, 'totalExp', 0, 'cpts', 0, 'spentCard', 0, 'ex', 0, 'exb', 0,
    'src', s, 'bound', s = 'story', 'got_at', extract(epoch from now())::bigint);
end $$;
revoke all on function public._story_new_card(text) from public, anon, authenticated;

-- 기존 보유분 재표시
--  1) 소급 때 시작 인재가 story 로 묶였던 것(got_at 없음 = 소급분) 1장 → starter (챕터 보상 목록에 같은 인재가 있으면 그대로 둠)
--  2) story 가 아닌 것은 모두 bound=false
update public.story_progress sp set data = jsonb_set(sp.data, '{owned}', (
  select coalesce(jsonb_agg(case
      when o->>'src' = 'story' and not (o ? 'got_at') and n = (
             select min(m) from jsonb_array_elements(sp.data->'owned') with ordinality y(v, m)
             where v->>'id' = sp.data->>'starter' and v->>'src' = 'story' and not (v ? 'got_at'))
           and not exists (select 1 from public.story_phase_config c where c.reward_card = sp.data->>'starter')
        then o || jsonb_build_object('src', 'starter', 'bound', false)
      when o->>'src' is distinct from 'story' then o || jsonb_build_object('bound', false)
      else o || jsonb_build_object('bound', true) end order by n), '[]'::jsonb)
  from jsonb_array_elements(sp.data->'owned') with ordinality x(o, n)))
where jsonb_typeof(sp.data->'owned') = 'array'
  and exists (select 1 from jsonb_array_elements(sp.data->'owned') z
              where ((z->>'src') is distinct from 'story' and (z->>'bound')::boolean is distinct from false)
                 or (z->>'src' = 'story' and not (z ? 'got_at') and z->>'id' = sp.data->>'starter'));

-- 확인: select o->>'src' src, o->>'bound' bound, count(*) from story_progress, jsonb_array_elements(data->'owned') o group by 1, 2 order by 1;
