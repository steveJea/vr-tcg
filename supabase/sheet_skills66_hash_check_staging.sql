-- 읽기만 함. staging 전용. 디버그 66번 스킬 시트 반영 엔진 해시 설치 후 한 줄 확인.
-- PR #620 확인 SQL을 대체한다. 기대: ok=true
select (
  (select system_identifier::text from pg_catalog.pg_control_system()) = '7703759698107299042'
  and (select engine_hash from public.pvp_policy_v3 where singleton) = '96f5145ee300d001d3582762c6e81fb244c8e2428935931f821980601f35df1d'
  and (select engine_hash from public.guildbattle_policy_v4 where singleton) = '9f6b02bcae08b7a921516060f705ff9a8b579a80fc4807adbb3727ff7d66b267'
  and (select engine_hash from public.arcade_policy_v5 where singleton) = '7da716ef3eaf736cda2f07bd87f5a96d399deb4f6b09dc9c1debf123a0133885'
  and (select engine_hash from public.battle_replay_policy_v6 where singleton) = '68de135b3c27c9f1bf5828605c0aa68b591c8ad18167dcb473e9aa5037748f9f'
  and (select engine_hash from public.battle_replay_policy_v7 where singleton) = 'ef1b6c31485e4cd767cd833f5c77d85fcec5e8e3e176a4505e60ab7d9570d45e'
) as ok;
