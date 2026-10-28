-- =====================================================================
-- 스토리 챕터 2 (이명진 / 김후 루트, 페이즈 10개, 페이즈마다 적 5명)
-- 사용법: Supabase SQL Editor 에 붙여넣고 Run. 여러 번 실행해도 안전함. service_role 키 필요 없음.
-- 필요 조건: story_server.sql · story_levels.sql · story_merge.sql 적용 후
-- =====================================================================

-- 1) 페이즈 설정: 챕터 2는 카드 보상 없이 스탯 포인트만 (일반 3, 보스 5). enemy_count = 그 페이즈 적 수(보스 포함, 챕터 1과 같은 방식)
insert into public.story_phase_config (chapter, phase, type, points, reward_grade, enemy_count) values
  (2,1,'normal',3,null,5), (2,2,'normal',3,null,5), (2,3,'normal',3,null,5), (2,4,'normal',3,null,5), (2,5,'normal',3,null,5),
  (2,6,'normal',3,null,5), (2,7,'normal',3,null,5), (2,8,'normal',3,null,5), (2,9,'normal',3,null,5), (2,10,'boss',5,null,5)
on conflict (chapter, phase) do update set type = excluded.type, points = excluded.points, reward_grade = excluded.reward_grade, enemy_count = excluded.enemy_count;

-- 2) 루트 선택: data.routes = { "2": "카드 id" }. 그 챕터 페이즈를 하나라도 깨면 다른 루트로 바꿀 수 없음
create or replace function public.story_choose_route(p_chapter int, p_route text) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb; cur text;
begin
  if not (p_chapter = 2 and p_route in ('10298', '10081')) then raise exception 'invalid route'; end if;
  d := _story_lock(uid);
  if coalesce(d->>'starter', '') = '' then raise exception 'choose starter first'; end if;
  cur := d->'routes'->>(p_chapter::text);
  if cur is not null and cur <> p_route and jsonb_array_length(coalesce(d->'cleared'->(p_chapter::text), '[]'::jsonb)) > 0 then raise exception 'route locked'; end if;
  if d->'routes' is null or jsonb_typeof(d->'routes') <> 'object' then d := jsonb_set(d, '{routes}', '{}'::jsonb); end if;
  d := jsonb_set(d, array['routes', p_chapter::text], to_jsonb(p_route));
  return _story_save(uid, d);
end $$;
revoke all on function public.story_choose_route(int, text) from public, anon;
grant execute on function public.story_choose_route(int, text) to authenticated;
