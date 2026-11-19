-- 확인용 (읽기 전용): ok = true 면 정상
select (
  (select system_identifier::text from pg_catalog.pg_control_system()) = '7703759698107299042'
  and (select engine_hash from public.pvp_policy_v3 where singleton) = '5e6ec74db1ddae269734a9e26fa794dcc663d720ff9501ff9546f3970807950d'
  and (select engine_hash from public.guildbattle_policy_v4 where singleton) = 'ef3c3c5879627ec0d156608e48d0e1e0e9bed4527879e9190ec39b7b99e6e03a'
  and (select engine_hash from public.arcade_policy_v5 where singleton) = 'd2624efb090ffc55d062b84b9fb7619d205f5a531761cb7a9f991e4cec813f8f'
  and (select engine_hash from public.battle_replay_policy_v6 where singleton) = '6ec3f7fe99fe0c32c2bae9a578d60496609540cb8f9f35d9f65e76c879c54f41'
  and (select engine_hash from public.battle_replay_policy_v7 where singleton) = '69f253990447d4373e37d99c6eda34f01f2f63ee43c7b6649cb901be02528dfb'
) as ok;
