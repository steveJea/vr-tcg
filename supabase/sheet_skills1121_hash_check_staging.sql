-- 확인용 (읽기 전용): ok = true 면 정상
select (
  (select system_identifier::text from pg_catalog.pg_control_system()) = '7703759698107299042'
  and (select engine_hash from public.pvp_policy_v3 where singleton) = 'abe96a83071bc0113dd991a0c72a6dc839fc22249a542c9d983ee998becf9537'
  and (select engine_hash from public.guildbattle_policy_v4 where singleton) = '2cc3e78c3ed78bc08a3da4c8eb21bfdcebe40e1312916c7eb58f167e9d61914c'
  and (select engine_hash from public.arcade_policy_v5 where singleton) = 'd033151109938fa00c57df14afaf6960eb01a7f7f2e3f4834dad27e00c79f104'
  and (select engine_hash from public.battle_replay_policy_v6 where singleton) = 'db895f9df849a6e72133d5a9e7af23c2a97ef2518243a28390ad7caaacb46ff4'
  and (select engine_hash from public.battle_replay_policy_v7 where singleton) = '648c70496e80bb3382186ac616f2da1f8caee7ccdec7e8b3a15e3abc1a12e275'
  and exists (select 1 from public.story_skill_meta where card_id = '10462' and idx = 1 and unlock = 2)
  and exists (select 1 from public.story_skill_meta where card_id = '10264' and idx = 1 and unlock = 2)
  and exists (select 1 from public.story_skill_meta where card_id = '10389' and idx = 1 and unlock = 2)
  and exists (select 1 from public.story_skill_meta where card_id = '10451' and idx = 1 and unlock = 2)
) as ok;
