-- 읽기만 함. production 전용. fix_16_11_boss_production.sql 적용 후 한 줄 확인. 기대: ok=true
select (
  (select system_identifier::text from pg_catalog.pg_control_system()) = '7692130048193495360'
  and (select type from public.story_phase_config where chapter = 16 and phase = 11) = 'boss'
  and (select definition->>'type' from public.battle_story_defs_v2 where chapter = 16 and phase = 11 and variant = '') = 'boss'
  and (select definition->>'bossId' from public.battle_story_defs_v2 where chapter = 16 and phase = 11 and variant = '') = '10406'
  and (select definition#>'{rules,mustKill}' from public.battle_story_defs_v2 where chapter = 16 and phase = 11 and variant = '') is null
  and (select definition#>>'{rules,revive,0,become}' from public.battle_story_defs_v2 where chapter = 16 and phase = 11 and variant = '') = '10291'
) as ok;
