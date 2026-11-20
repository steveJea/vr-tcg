-- 읽기만 함. production 전용. story_ch18_19_production.sql 적용 후 한 줄 확인. 기대: ok=true
-- 엔진 해시는 이 파일에서 검사하지 않음 (마지막 engine_hash_check_production.sql).
select (
  (select system_identifier::text from pg_catalog.pg_control_system()) = '7692130048193495360'
  and (select count(*) from public.story_phase_config where chapter = 18) = 16
  and (select count(*) from public.story_phase_config where chapter = 19) = 13
  and (select count(*) from public.story_phase_config where chapter in (18, 19) and enemy_count = 0) = 7
  and (select type from public.story_phase_config where chapter = 18 and phase = 15) = 'boss'
  and (select type from public.story_phase_config where chapter = 19 and phase = 13) = 'boss'
  and (select count(*) from public.battle_story_defs_v2 where chapter in (18, 19) and variant = '') = 29
  and (select definition->'rules'->'revive'->0->>'id' from public.battle_story_defs_v2 where chapter = 19 and phase = 13 and variant = '') = '10534'
  and (select definition->'party'->'forced'->>0 from public.battle_story_defs_v2 where chapter = 16 and phase = 1 and variant = '') = '10536'
  and (select count(*) from public.battle_card_meta_v2 where id between '10533' and '10543') = 11
  and (select gacha from public.story_card_pool where id = '10533') = false
  and exists (select 1 from public.reward_card_catalog where card_id = '10533')
) as ok;
