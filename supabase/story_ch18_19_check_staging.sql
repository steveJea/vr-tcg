-- 읽기만 함. staging 전용. story_ch18_19_staging.sql 실행 후 한 줄 확인. 기대: ok=true
-- 생성: python3 tools/build_ch18_19_sql.py
select (
  (select system_identifier::text from pg_catalog.pg_control_system()) = '7703759698107299042'
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
  and (select engine_hash from public.pvp_policy_v3 where singleton) = 'c5b478a735b1798bd7b9c51902ae85efe5ed861e9ab2936cecf753b4e250a648'
  and (select engine_hash from public.guildbattle_policy_v4 where singleton) = '7fe844f6bd869991d25558341374dbce28308685365d586b4e0cd2281ae16b58'
  and (select engine_hash from public.arcade_policy_v5 where singleton) = 'fc7c0deaec9781badc9adc4b6895bbc2bc39ffe42e51dc3ae4deab647790e063'
  and (select engine_hash from public.battle_replay_policy_v6 where singleton) = 'ad59546b94862bbb09cbd63692b21709f9729e035ddf54456664ead9eb927d57'
  and (select engine_hash from public.battle_replay_policy_v7 where singleton) = 'c326c57e218a5b6fe779d3835931c47a9917b17332740b16bd723cb0d05b3119'
) as ok;
