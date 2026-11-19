-- =====================================================================
-- 2026-11-19 캐릭터 이름 변경 3명 (두윤창→윤수두, 김희건→김희자, 한석열→윤부자).
-- 카드 데이터가 엔진에 들어가 있어 엔진 해시 5개 갱신. 전투 수치·규칙 변화 없음. 삭제 없음.
-- 먼저 Edge Function 5개(pvp-verify-v3, guildbattle-verify-v4, arcade-verify-v5,
-- story-tower-verify-v6, story-direct-verify-v7)를 새 dashboard_single_file.ts 로
-- 재배포한 뒤 실행. 여러 번 실행해도 안전. STAGING ONLY (cuyqchmdcnsgzkwyclji).
-- =====================================================================
begin;
do $guard$
begin
  if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7703759698107299042' then
    raise exception 'STOP: rename three cards hash is staging cuyqchmdcnsgzkwyclji only; production forbidden';
  end if;
end $guard$;
do $hash$
begin
  update public.pvp_policy_v3
    set engine_hash = '5e6ec74db1ddae269734a9e26fa794dcc663d720ff9501ff9546f3970807950d'
    where singleton
      and engine_hash in (
        '96f5145ee300d001d3582762c6e81fb244c8e2428935931f821980601f35df1d',
        'c5b478a735b1798bd7b9c51902ae85efe5ed861e9ab2936cecf753b4e250a648',
        '5e6ec74db1ddae269734a9e26fa794dcc663d720ff9501ff9546f3970807950d'
      );

  update public.guildbattle_policy_v4
    set engine_hash = 'ef3c3c5879627ec0d156608e48d0e1e0e9bed4527879e9190ec39b7b99e6e03a'
    where singleton
      and engine_hash in (
        '7fe844f6bd869991d25558341374dbce28308685365d586b4e0cd2281ae16b58',
        'c87d5a678229e2bbc3bcd92ff3f9f4b8e32291df874a9919c4295b14831d7d07',
        'ef3c3c5879627ec0d156608e48d0e1e0e9bed4527879e9190ec39b7b99e6e03a'
      );

  update public.arcade_policy_v5
    set engine_hash = 'd2624efb090ffc55d062b84b9fb7619d205f5a531761cb7a9f991e4cec813f8f'
    where singleton
      and engine_hash in (
        '7da716ef3eaf736cda2f07bd87f5a96d399deb4f6b09dc9c1debf123a0133885',
        'fc7c0deaec9781badc9adc4b6895bbc2bc39ffe42e51dc3ae4deab647790e063',
        'd2624efb090ffc55d062b84b9fb7619d205f5a531761cb7a9f991e4cec813f8f'
      );

  update public.battle_replay_policy_v6
    set engine_hash = '6ec3f7fe99fe0c32c2bae9a578d60496609540cb8f9f35d9f65e76c879c54f41'
    where singleton
      and engine_hash in (
        'ad59546b94862bbb09cbd63692b21709f9729e035ddf54456664ead9eb927d57',
        '1d1092662cfa90fd1c118baf7ffb4d83dcb767ef17564e30f9efdecfc3270bd7',
        '6ec3f7fe99fe0c32c2bae9a578d60496609540cb8f9f35d9f65e76c879c54f41'
      );

  update public.battle_replay_policy_v7
    set engine_hash = '69f253990447d4373e37d99c6eda34f01f2f63ee43c7b6649cb901be02528dfb'
    where singleton
      and engine_hash in (
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
