-- =====================================================================
-- 2026-11-20 운영 배포 최종 엔진 해시 (테섭 #664 rename_three_cards 와 동일).
-- 포함하는 엔진 변경: 김진호·김한철, 시트 스탯/스킬, 어린 NPC 나이 숨김,
-- #661 각성 임유리 턴 맞춤, #664 이름 3명(윤수두·김희자·윤부자), 챕터 18/19 카드 데이터.
-- 검증 스위치(enabled)는 건드리지 않음. 여러 번 실행해도 안전.
-- 먼저 Edge Function 5개(pvp-verify-v3, guildbattle-verify-v4, arcade-verify-v5,
-- story-tower-verify-v6, story-direct-verify-v7)를 이 릴리스의 dashboard_single_file.ts 로
-- 재배포한 뒤 실행하세요. PRODUCTION ONLY (htarwisgkkphutxxnuak).
-- =====================================================================
begin;
do $guard$
begin
  if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7692130048193495360' then
    raise exception 'STOP: engine hash is production htarwisgkkphutxxnuak only; staging forbidden';
  end if;
end $guard$;
do $hash$
begin
  update public.pvp_policy_v3
    set engine_hash = '5e6ec74db1ddae269734a9e26fa794dcc663d720ff9501ff9546f3970807950d'
    where singleton
      and engine_hash in (
        'bef887c77a009121ae99301ca91db7d73a7bd9ce30d70e1ec7a18d10742cd16f',
        'de0b20eb9b97eabb27ed2bed2b77aec947eb7823bb5465b01da29f424191437f',
        '4d2a302eb51172b9db6f0ee380382cae747d9106d0158a7b3e19e1b34ff20d72',
        'e9f17af01d6a5798932f9cc068f98cbb7bf76552de1e0ea1dce92a7c292512de',
        'fa0f4fef157422a35f3f5d4fab9d636aa0c8e008f4fd4a1341202d0a19946f41',
        'c5b478a735b1798bd7b9c51902ae85efe5ed861e9ab2936cecf753b4e250a648',
        '96f5145ee300d001d3582762c6e81fb244c8e2428935931f821980601f35df1d',
        '5e6ec74db1ddae269734a9e26fa794dcc663d720ff9501ff9546f3970807950d'
      );

  update public.guildbattle_policy_v4
    set engine_hash = 'ef3c3c5879627ec0d156608e48d0e1e0e9bed4527879e9190ec39b7b99e6e03a'
    where singleton
      and engine_hash in (
        '819b116c1e1ccd7d66ba589e3bc5e4e8d436a43ebf2dfe4543c250cbf5166cd0',
        '11412c0cec381f8a0b268822fbf4815241b374f9553f968ef4303c30f78a6849',
        'd2b099257f69e4ae3bdbd248e0e161c03a788be50b83ddb8affc23856d17ca31',
        '40b95ca320f62733a9c962c26879e2f852620a35e16da88885f5528dc8bf9e63',
        '1e5c20366403b1dd4ce0c687db01d2469fa660d044fbff1b54be5fc4f3ea3060',
        '7fe844f6bd869991d25558341374dbce28308685365d586b4e0cd2281ae16b58',
        '9f6b02bcae08b7a921516060f705ff9a8b579a80fc4807adbb3727ff7d66b267',
        'c87d5a678229e2bbc3bcd92ff3f9f4b8e32291df874a9919c4295b14831d7d07',
        'ef3c3c5879627ec0d156608e48d0e1e0e9bed4527879e9190ec39b7b99e6e03a'
      );

  update public.arcade_policy_v5
    set engine_hash = 'd2624efb090ffc55d062b84b9fb7619d205f5a531761cb7a9f991e4cec813f8f'
    where singleton
      and engine_hash in (
        '7c47d4ccb224c0cd7cf8ff9a11a465e68fd645510588249fabb6c8859a39663a',
        'ff2d9c9fdee9db3f098c9354ae522694864e44cf958543204c914d41234586d6',
        '784dbc2ca538f7c597b39156bfc55cbb8dcd478a7c659a4ce999028f07d10226',
        '671d143bb0b905b82bc2dffe02de890f3e33847787825f719cdec66ef8acc478',
        'a1c0a4262f84e741e06211e15fb5c5d967897adc8e02a3d592cffcf427f0f118',
        'fc7c0deaec9781badc9adc4b6895bbc2bc39ffe42e51dc3ae4deab647790e063',
        '7da716ef3eaf736cda2f07bd87f5a96d399deb4f6b09dc9c1debf123a0133885',
        'd2624efb090ffc55d062b84b9fb7619d205f5a531761cb7a9f991e4cec813f8f'
      );

  update public.battle_replay_policy_v6
    set engine_hash = '6ec3f7fe99fe0c32c2bae9a578d60496609540cb8f9f35d9f65e76c879c54f41'
    where singleton
      and engine_hash in (
        '32f0e5059ddb994d56865b16054d64f3f2c1f389df672be4f113e13c5d4112c2',
        '3287b073666a4551cdb77d6c5e8f0f5ea994edf95852b6a221497c0a6f9966b2',
        '3d99bb32199f214f1e77dd0eaedb8f9dd2b3393352b5619b1726d407c56f2180',
        'a993d56d24f51588f5df75a3a77ccae8c93de8ed9ab2321c87ea85c7188ce3ba',
        'c36ff1eff07d4611014466d4d7dfadc0391974abbddf3fc633a8b803e14ff4d5',
        'ad59546b94862bbb09cbd63692b21709f9729e035ddf54456664ead9eb927d57',
        '68de135b3c27c9f1bf5828605c0aa68b591c8ad18167dcb473e9aa5037748f9f',
        '1d1092662cfa90fd1c118baf7ffb4d83dcb767ef17564e30f9efdecfc3270bd7',
        '6ec3f7fe99fe0c32c2bae9a578d60496609540cb8f9f35d9f65e76c879c54f41'
      );

  update public.battle_replay_policy_v7
    set engine_hash = '69f253990447d4373e37d99c6eda34f01f2f63ee43c7b6649cb901be02528dfb'
    where singleton
      and engine_hash in (
        'c128e31ac46bd40d34f934af334021693f998f48a6d5b47ad8c414a62588688e',
        '0181e4ca3713942fa8e3fb8b5674164765c5bab7598b7d29abd6fa18dd3aa42b',
        '7f7ee4ee627977cadd1e248b97a1edefe74c702349af776159d3454041439a0d',
        '74816d5202bbcb70ef240b866d6ae0a02cfa6440d7f916bf54d9c27ab67b7074',
        '28564a6f121856d8f239945ba533e459f6e0a3dd4600399eda6ebd2bc6409fa1',
        'c326c57e218a5b6fe779d3835931c47a9917b17332740b16bd723cb0d05b3119',
        'ef1b6c31485e4cd767cd833f5c77d85fcec5e8e3e176a4505e60ab7d9570d45e',
        '2fbf41b3446cb61e5a66fd0ea80380d0fa77f644f26a5e1219ea70b91bf39a3a',
        'ca2183b100c223112f64c8d10496f9fdb676d7442bd7522faa2641287eee09b0',
        '69f253990447d4373e37d99c6eda34f01f2f63ee43c7b6649cb901be02528dfb'
      );

  if not exists (select 1 from public.pvp_policy_v3 where singleton and engine_hash = '5e6ec74db1ddae269734a9e26fa794dcc663d720ff9501ff9546f3970807950d')
     or not exists (select 1 from public.guildbattle_policy_v4 where singleton and engine_hash = 'ef3c3c5879627ec0d156608e48d0e1e0e9bed4527879e9190ec39b7b99e6e03a')
     or not exists (select 1 from public.arcade_policy_v5 where singleton and engine_hash = 'd2624efb090ffc55d062b84b9fb7619d205f5a531761cb7a9f991e4cec813f8f')
     or not exists (select 1 from public.battle_replay_policy_v6 where singleton and engine_hash = '6ec3f7fe99fe0c32c2bae9a578d60496609540cb8f9f35d9f65e76c879c54f41')
     or not exists (select 1 from public.battle_replay_policy_v7 where singleton and engine_hash = '69f253990447d4373e37d99c6eda34f01f2f63ee43c7b6649cb901be02528dfb')
  then
    raise exception 'STOP: 엔진 해시가 예상과 다릅니다. 현재 값을 확인하고 딩순이에게 알려 주세요.';
  end if;
end $hash$;
commit;
