-- 김진호·김한철 스탯/스킬 반영 후 전투 엔진 해시 갱신. staging cuyqchmdcnsgzkwyclji ONLY.
-- 형님이 staging Supabase SQL Editor 에서 실행. 해시만 바꾸고 검증 스위치(enabled)는 건드리지 않음. 재실행 안전.
begin;
do $guard$
begin
  if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7703759698107299042' then
    raise exception 'STOP: staging cuyqchmdcnsgzkwyclji only';
  end if;

  update public.pvp_policy_v3
    set engine_hash = 'de0b20eb9b97eabb27ed2bed2b77aec947eb7823bb5465b01da29f424191437f'
    where singleton
      and engine_hash in (
        'bef887c77a009121ae99301ca91db7d73a7bd9ce30d70e1ec7a18d10742cd16f',
        'de0b20eb9b97eabb27ed2bed2b77aec947eb7823bb5465b01da29f424191437f'
      );

  update public.guildbattle_policy_v4
    set engine_hash = '11412c0cec381f8a0b268822fbf4815241b374f9553f968ef4303c30f78a6849'
    where singleton
      and engine_hash in (
        '819b116c1e1ccd7d66ba589e3bc5e4e8d436a43ebf2dfe4543c250cbf5166cd0',
        '11412c0cec381f8a0b268822fbf4815241b374f9553f968ef4303c30f78a6849'
      );

  update public.arcade_policy_v5
    set engine_hash = 'ff2d9c9fdee9db3f098c9354ae522694864e44cf958543204c914d41234586d6'
    where singleton
      and engine_hash in (
        '7c47d4ccb224c0cd7cf8ff9a11a465e68fd645510588249fabb6c8859a39663a',
        'ff2d9c9fdee9db3f098c9354ae522694864e44cf958543204c914d41234586d6'
      );

  update public.battle_replay_policy_v6
    set engine_hash = '3287b073666a4551cdb77d6c5e8f0f5ea994edf95852b6a221497c0a6f9966b2'
    where singleton
      and engine_hash in (
        '32f0e5059ddb994d56865b16054d64f3f2c1f389df672be4f113e13c5d4112c2',
        '3287b073666a4551cdb77d6c5e8f0f5ea994edf95852b6a221497c0a6f9966b2'
      );

  update public.battle_replay_policy_v7
    set engine_hash = '0181e4ca3713942fa8e3fb8b5674164765c5bab7598b7d29abd6fa18dd3aa42b'
    where singleton
      and engine_hash in (
        'c128e31ac46bd40d34f934af334021693f998f48a6d5b47ad8c414a62588688e',
        '0181e4ca3713942fa8e3fb8b5674164765c5bab7598b7d29abd6fa18dd3aa42b'
      );

  if not exists (select 1 from public.pvp_policy_v3 where singleton and engine_hash = 'de0b20eb9b97eabb27ed2bed2b77aec947eb7823bb5465b01da29f424191437f')
     or not exists (select 1 from public.guildbattle_policy_v4 where singleton and engine_hash = '11412c0cec381f8a0b268822fbf4815241b374f9553f968ef4303c30f78a6849')
     or not exists (select 1 from public.arcade_policy_v5 where singleton and engine_hash = 'ff2d9c9fdee9db3f098c9354ae522694864e44cf958543204c914d41234586d6')
     or not exists (select 1 from public.battle_replay_policy_v6 where singleton and engine_hash = '3287b073666a4551cdb77d6c5e8f0f5ea994edf95852b6a221497c0a6f9966b2')
     or not exists (select 1 from public.battle_replay_policy_v7 where singleton and engine_hash = '0181e4ca3713942fa8e3fb8b5674164765c5bab7598b7d29abd6fa18dd3aa42b')
  then
    raise exception 'STOP: 엔진 해시가 예상과 다릅니다. 현재 값을 확인하고 딩순이에게 알려 주세요.';
  end if;
end $guard$;
commit;
