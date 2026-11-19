-- 읽기만 함. staging 전용. 미식 스킬 액티브화·주님의 기적 엔진 해시 설치 후 한 줄 확인.
-- PR #619 확인 SQL을 대체한다. 기대: ok=true
select (
  (select system_identifier::text from pg_catalog.pg_control_system()) = '7703759698107299042'
  and (select engine_hash from public.pvp_policy_v3 where singleton) = 'fa0f4fef157422a35f3f5d4fab9d636aa0c8e008f4fd4a1341202d0a19946f41'
  and (select engine_hash from public.guildbattle_policy_v4 where singleton) = '1e5c20366403b1dd4ce0c687db01d2469fa660d044fbff1b54be5fc4f3ea3060'
  and (select engine_hash from public.arcade_policy_v5 where singleton) = 'a1c0a4262f84e741e06211e15fb5c5d967897adc8e02a3d592cffcf427f0f118'
  and (select engine_hash from public.battle_replay_policy_v6 where singleton) = 'c36ff1eff07d4611014466d4d7dfadc0391974abbddf3fc633a8b803e14ff4d5'
  and (select engine_hash from public.battle_replay_policy_v7 where singleton) = '28564a6f121856d8f239945ba533e459f6e0a3dd4600399eda6ebd2bc6409fa1'
) as ok;
