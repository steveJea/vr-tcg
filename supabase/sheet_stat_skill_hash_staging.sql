-- 시트 반영: 김경섭·천기철 스탯, 김기림 강북대장 액티브화 후 전투 엔진 해시 갱신.
-- staging cuyqchmdcnsgzkwyclji ONLY.
-- 형님이 staging Supabase SQL Editor 에서 실행. 해시만 바꾸고 검증 스위치(enabled)는 건드리지 않음.
-- 이전 해시 SQL을 이미 돌렸든 안 돌렸든, 이 파일을 다시 실행해도 안전하다.
begin;
do $guard$
begin
  if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7703759698107299042' then
    raise exception 'STOP: staging cuyqchmdcnsgzkwyclji only';
  end if;

  update public.pvp_policy_v3
    set engine_hash = 'e9f17af01d6a5798932f9cc068f98cbb7bf76552de1e0ea1dce92a7c292512de'
    where singleton
      and engine_hash in (
        'de0b20eb9b97eabb27ed2bed2b77aec947eb7823bb5465b01da29f424191437f',
        '4d2a302eb51172b9db6f0ee380382cae747d9106d0158a7b3e19e1b34ff20d72',
        'e9f17af01d6a5798932f9cc068f98cbb7bf76552de1e0ea1dce92a7c292512de'
      );

  update public.guildbattle_policy_v4
    set engine_hash = '40b95ca320f62733a9c962c26879e2f852620a35e16da88885f5528dc8bf9e63'
    where singleton
      and engine_hash in (
        '11412c0cec381f8a0b268822fbf4815241b374f9553f968ef4303c30f78a6849',
        'd2b099257f69e4ae3bdbd248e0e161c03a788be50b83ddb8affc23856d17ca31',
        '40b95ca320f62733a9c962c26879e2f852620a35e16da88885f5528dc8bf9e63'
      );

  update public.arcade_policy_v5
    set engine_hash = '671d143bb0b905b82bc2dffe02de890f3e33847787825f719cdec66ef8acc478'
    where singleton
      and engine_hash in (
        'ff2d9c9fdee9db3f098c9354ae522694864e44cf958543204c914d41234586d6',
        '784dbc2ca538f7c597b39156bfc55cbb8dcd478a7c659a4ce999028f07d10226',
        '671d143bb0b905b82bc2dffe02de890f3e33847787825f719cdec66ef8acc478'
      );

  update public.battle_replay_policy_v6
    set engine_hash = 'a993d56d24f51588f5df75a3a77ccae8c93de8ed9ab2321c87ea85c7188ce3ba'
    where singleton
      and engine_hash in (
        '3287b073666a4551cdb77d6c5e8f0f5ea994edf95852b6a221497c0a6f9966b2',
        '3d99bb32199f214f1e77dd0eaedb8f9dd2b3393352b5619b1726d407c56f2180',
        'a993d56d24f51588f5df75a3a77ccae8c93de8ed9ab2321c87ea85c7188ce3ba'
      );

  update public.battle_replay_policy_v7
    set engine_hash = '74816d5202bbcb70ef240b866d6ae0a02cfa6440d7f916bf54d9c27ab67b7074'
    where singleton
      and engine_hash in (
        '0181e4ca3713942fa8e3fb8b5674164765c5bab7598b7d29abd6fa18dd3aa42b',
        '7f7ee4ee627977cadd1e248b97a1edefe74c702349af776159d3454041439a0d',
        '74816d5202bbcb70ef240b866d6ae0a02cfa6440d7f916bf54d9c27ab67b7074'
      );

  if not exists (select 1 from public.pvp_policy_v3 where singleton and engine_hash = 'e9f17af01d6a5798932f9cc068f98cbb7bf76552de1e0ea1dce92a7c292512de')
     or not exists (select 1 from public.guildbattle_policy_v4 where singleton and engine_hash = '40b95ca320f62733a9c962c26879e2f852620a35e16da88885f5528dc8bf9e63')
     or not exists (select 1 from public.arcade_policy_v5 where singleton and engine_hash = '671d143bb0b905b82bc2dffe02de890f3e33847787825f719cdec66ef8acc478')
     or not exists (select 1 from public.battle_replay_policy_v6 where singleton and engine_hash = 'a993d56d24f51588f5df75a3a77ccae8c93de8ed9ab2321c87ea85c7188ce3ba')
     or not exists (select 1 from public.battle_replay_policy_v7 where singleton and engine_hash = '74816d5202bbcb70ef240b866d6ae0a02cfa6440d7f916bf54d9c27ab67b7074')
  then
    raise exception 'STOP: 엔진 해시가 예상과 다릅니다. 현재 값을 확인하고 딩순이에게 알려 주세요.';
  end if;
end $guard$;
commit;
