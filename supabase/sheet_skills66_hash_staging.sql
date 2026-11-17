-- 시트 스킬 탭 2~62행 반영 (디버그 66번, 11/17) 후 전투 엔진 해시 갱신.
-- staging cuyqchmdcnsgzkwyclji ONLY. PR #620 해시 SQL을 이미 돌렸든 안 돌렸든, 이 파일을 실행해도 안전하다.
-- 형님이 staging Supabase SQL Editor 에서 실행. 해시만 바꾸고 검증 스위치(enabled)는 건드리지 않음.
-- 이 파일이 PR #620의 sheet_mr_skills_hash_staging.sql 을 대체한다.
begin;
do $guard$
begin
  if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7703759698107299042' then
    raise exception 'STOP: staging cuyqchmdcnsgzkwyclji only';
  end if;

  update public.pvp_policy_v3
    set engine_hash = '96f5145ee300d001d3582762c6e81fb244c8e2428935931f821980601f35df1d'
    where singleton
      and engine_hash in (
        'de0b20eb9b97eabb27ed2bed2b77aec947eb7823bb5465b01da29f424191437f',
        '4d2a302eb51172b9db6f0ee380382cae747d9106d0158a7b3e19e1b34ff20d72',
        'e9f17af01d6a5798932f9cc068f98cbb7bf76552de1e0ea1dce92a7c292512de',
        'fa0f4fef157422a35f3f5d4fab9d636aa0c8e008f4fd4a1341202d0a19946f41',
        '96f5145ee300d001d3582762c6e81fb244c8e2428935931f821980601f35df1d'
      );

  update public.guildbattle_policy_v4
    set engine_hash = '9f6b02bcae08b7a921516060f705ff9a8b579a80fc4807adbb3727ff7d66b267'
    where singleton
      and engine_hash in (
        '11412c0cec381f8a0b268822fbf4815241b374f9553f968ef4303c30f78a6849',
        'd2b099257f69e4ae3bdbd248e0e161c03a788be50b83ddb8affc23856d17ca31',
        '40b95ca320f62733a9c962c26879e2f852620a35e16da88885f5528dc8bf9e63',
        '1e5c20366403b1dd4ce0c687db01d2469fa660d044fbff1b54be5fc4f3ea3060',
        '9f6b02bcae08b7a921516060f705ff9a8b579a80fc4807adbb3727ff7d66b267'
      );

  update public.arcade_policy_v5
    set engine_hash = '7da716ef3eaf736cda2f07bd87f5a96d399deb4f6b09dc9c1debf123a0133885'
    where singleton
      and engine_hash in (
        'ff2d9c9fdee9db3f098c9354ae522694864e44cf958543204c914d41234586d6',
        '784dbc2ca538f7c597b39156bfc55cbb8dcd478a7c659a4ce999028f07d10226',
        '671d143bb0b905b82bc2dffe02de890f3e33847787825f719cdec66ef8acc478',
        'a1c0a4262f84e741e06211e15fb5c5d967897adc8e02a3d592cffcf427f0f118',
        '7da716ef3eaf736cda2f07bd87f5a96d399deb4f6b09dc9c1debf123a0133885'
      );

  update public.battle_replay_policy_v6
    set engine_hash = '68de135b3c27c9f1bf5828605c0aa68b591c8ad18167dcb473e9aa5037748f9f'
    where singleton
      and engine_hash in (
        '3287b073666a4551cdb77d6c5e8f0f5ea994edf95852b6a221497c0a6f9966b2',
        '3d99bb32199f214f1e77dd0eaedb8f9dd2b3393352b5619b1726d407c56f2180',
        'a993d56d24f51588f5df75a3a77ccae8c93de8ed9ab2321c87ea85c7188ce3ba',
        'c36ff1eff07d4611014466d4d7dfadc0391974abbddf3fc633a8b803e14ff4d5',
        '68de135b3c27c9f1bf5828605c0aa68b591c8ad18167dcb473e9aa5037748f9f'
      );

  update public.battle_replay_policy_v7
    set engine_hash = 'ef1b6c31485e4cd767cd833f5c77d85fcec5e8e3e176a4505e60ab7d9570d45e'
    where singleton
      and engine_hash in (
        '0181e4ca3713942fa8e3fb8b5674164765c5bab7598b7d29abd6fa18dd3aa42b',
        '7f7ee4ee627977cadd1e248b97a1edefe74c702349af776159d3454041439a0d',
        '74816d5202bbcb70ef240b866d6ae0a02cfa6440d7f916bf54d9c27ab67b7074',
        '28564a6f121856d8f239945ba533e459f6e0a3dd4600399eda6ebd2bc6409fa1',
        'ef1b6c31485e4cd767cd833f5c77d85fcec5e8e3e176a4505e60ab7d9570d45e'
      );

  if not exists (select 1 from public.pvp_policy_v3 where singleton and engine_hash = '96f5145ee300d001d3582762c6e81fb244c8e2428935931f821980601f35df1d')
     or not exists (select 1 from public.guildbattle_policy_v4 where singleton and engine_hash = '9f6b02bcae08b7a921516060f705ff9a8b579a80fc4807adbb3727ff7d66b267')
     or not exists (select 1 from public.arcade_policy_v5 where singleton and engine_hash = '7da716ef3eaf736cda2f07bd87f5a96d399deb4f6b09dc9c1debf123a0133885')
     or not exists (select 1 from public.battle_replay_policy_v6 where singleton and engine_hash = '68de135b3c27c9f1bf5828605c0aa68b591c8ad18167dcb473e9aa5037748f9f')
     or not exists (select 1 from public.battle_replay_policy_v7 where singleton and engine_hash = 'ef1b6c31485e4cd767cd833f5c77d85fcec5e8e3e176a4505e60ab7d9570d45e')
  then
    raise exception 'STOP: 엔진 해시가 예상과 다릅니다. 현재 값을 확인하고 딩순이에게 알려 주세요.';
  end if;
end $guard$;
commit;
