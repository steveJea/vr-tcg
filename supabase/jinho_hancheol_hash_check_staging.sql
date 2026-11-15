-- 읽기만 함. staging 전용. 김진호·김한철 엔진 해시 설치 후 한 줄 확인.
-- 기대: ok=true
select (
  (select system_identifier::text from pg_catalog.pg_control_system()) = '7703759698107299042'
  and (select engine_hash from public.pvp_policy_v3 where singleton) = 'de0b20eb9b97eabb27ed2bed2b77aec947eb7823bb5465b01da29f424191437f'
  and (select engine_hash from public.guildbattle_policy_v4 where singleton) = '11412c0cec381f8a0b268822fbf4815241b374f9553f968ef4303c30f78a6849'
  and (select engine_hash from public.arcade_policy_v5 where singleton) = 'ff2d9c9fdee9db3f098c9354ae522694864e44cf958543204c914d41234586d6'
  and (select engine_hash from public.battle_replay_policy_v6 where singleton) = '3287b073666a4551cdb77d6c5e8f0f5ea994edf95852b6a221497c0a6f9966b2'
  and (select engine_hash from public.battle_replay_policy_v7 where singleton) = '0181e4ca3713942fa8e3fb8b5674164765c5bab7598b7d29abd6fa18dd3aa42b'
) as ok;
