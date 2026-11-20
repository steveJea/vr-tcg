-- 읽기만 함. production 전용. fix_scene_access_production.sql 실행 후 한 줄 확인. 기대: ok=true, stuck=0
select ((select system_identifier::text from pg_catalog.pg_control_system()) = '7692130048193495360'
  and exists (select 1 from pg_catalog.pg_proc where oid = to_regprocedure('public.story_complete_scene(integer,integer)')
    and prosrc like '%insert into public.battle_legacy_access_v2 as a%' and prosecdef)
  and (select count(*) from public.story_progress s join public.story_phase_config c on c.enemy_count = 0
    where jsonb_typeof(s.data->'cleared'->(c.chapter::text)) = 'array' and s.data->'cleared'->(c.chapter::text) @> to_jsonb(c.phase)
      and exists (select 1 from auth.users u where u.id = s.user_id)
      and not public._clear_access_v2(s.user_id, 'story', c.chapter::text || ':' || c.phase::text)
      and (c.phase = 1 or public._clear_access_v2(s.user_id, 'story', c.chapter::text || ':' || (c.phase - 1)::text))) = 0) as ok,
  (select count(*) from public.story_progress s join public.story_phase_config c on c.enemy_count = 0
    where jsonb_typeof(s.data->'cleared'->(c.chapter::text)) = 'array' and s.data->'cleared'->(c.chapter::text) @> to_jsonb(c.phase)
      and exists (select 1 from auth.users u where u.id = s.user_id)
      and not public._clear_access_v2(s.user_id, 'story', c.chapter::text || ':' || c.phase::text)
      and (c.phase = 1 or public._clear_access_v2(s.user_id, 'story', c.chapter::text || ':' || (c.phase - 1)::text))) as stuck;
