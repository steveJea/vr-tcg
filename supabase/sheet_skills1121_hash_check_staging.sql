-- 확인용 (읽기 전용): ok = true 면 정상
select (
  (select system_identifier::text from pg_catalog.pg_control_system()) = '7703759698107299042'
  and (select engine_hash from public.pvp_policy_v3 where singleton) = 'ddd3528a4d2d30e8be7e43c2b4a9ec0248289e54a5bef8ecaf9e8dedd1b21a5c'
  and (select engine_hash from public.guildbattle_policy_v4 where singleton) = 'd5b7e6356faa93ae008fd332844a36311bbe545422ad76eae66d561662b77935'
  and (select engine_hash from public.arcade_policy_v5 where singleton) = '380cd4138c6a119144409d4b6a9e8ec59a46c42548317b87c8af942613a15f04'
  and (select engine_hash from public.battle_replay_policy_v6 where singleton) = '972e2458e4ea4aa38d924238f414b7c7e601acb342232dd6f95d83d6ff495c58'
  and (select engine_hash from public.battle_replay_policy_v7 where singleton) = 'f10146d7143064f5a7411cf37ee10c17f9f2beb6a611c59d1f7f6cdfef346873'
  and exists (select 1 from public.story_skill_meta where card_id = '10462' and idx = 1 and unlock = 2)
  and exists (select 1 from public.story_skill_meta where card_id = '10264' and idx = 1 and unlock = 2)
  and exists (select 1 from public.story_skill_meta where card_id = '10389' and idx = 1 and unlock = 2)
  and exists (select 1 from public.story_skill_meta where card_id = '10451' and idx = 1 and unlock = 2)
) as ok;
