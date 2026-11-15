-- 읽기만 함. staging 전용. 김진호·김한철 엔진 해시 설치 후 한 줄 확인.
-- 기대: ok=true
select (
  (select system_identifier::text from pg_catalog.pg_control_system()) = '7703759698107299042'
  and (select engine_hash from public.pvp_policy_v3 where singleton) = '4d2a302eb51172b9db6f0ee380382cae747d9106d0158a7b3e19e1b34ff20d72'
  and (select engine_hash from public.guildbattle_policy_v4 where singleton) = 'd2b099257f69e4ae3bdbd248e0e161c03a788be50b83ddb8affc23856d17ca31'
  and (select engine_hash from public.arcade_policy_v5 where singleton) = '784dbc2ca538f7c597b39156bfc55cbb8dcd478a7c659a4ce999028f07d10226'
  and (select engine_hash from public.battle_replay_policy_v6 where singleton) = '3d99bb32199f214f1e77dd0eaedb8f9dd2b3393352b5619b1726d407c56f2180'
  and (select engine_hash from public.battle_replay_policy_v7 where singleton) = '7f7ee4ee627977cadd1e248b97a1edefe74c702349af776159d3454041439a0d'
) as ok;
