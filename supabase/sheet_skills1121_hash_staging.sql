-- =====================================================================
-- 2026-11-21 스킬 시트 반영: 황보예 스킬 변경 (사망 패시브 → 액티브 '나 갈거거든?'),
-- 왕유영·하지연·주슬기·허유리·류태연 스킬 추가. 스킬 데이터가 엔진에 들어가 있어 엔진 해시 5개 갱신
-- + 스킬 레벨업 해금 메타 (새 액티브 4개, Lv2).
-- 먼저 Edge Function 5개(pvp-verify-v3, guildbattle-verify-v4, arcade-verify-v5,
-- story-tower-verify-v6, story-direct-verify-v7)를 새 dashboard_single_file.ts 로 재배포한 뒤 실행.
-- 이전 값은 rename_three_cards_hash_staging.sql (11/19) 실행 후 값. 여러 번 실행해도 안전. 삭제 없음.
-- STAGING ONLY (cuyqchmdcnsgzkwyclji). 생성: python3 tools/build_sheet1121_sql.py (직접 고치지 말 것)
-- =====================================================================
begin;
do $guard$
begin
  if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7703759698107299042' then
    raise exception 'STOP: sheet skills 1121 hash is staging cuyqchmdcnsgzkwyclji only; production forbidden';
  end if;
end $guard$;
insert into public.story_skill_meta (card_id, idx, unlock) values
  ('10462',1,2),
  ('10264',1,2),
  ('10389',1,2),
  ('10451',1,2)
on conflict (card_id, idx) do update set unlock = excluded.unlock;
do $hash$
begin
  update public.pvp_policy_v3 set engine_hash = 'ddd3528a4d2d30e8be7e43c2b4a9ec0248289e54a5bef8ecaf9e8dedd1b21a5c' where singleton and engine_hash in ('5e6ec74db1ddae269734a9e26fa794dcc663d720ff9501ff9546f3970807950d', 'ddd3528a4d2d30e8be7e43c2b4a9ec0248289e54a5bef8ecaf9e8dedd1b21a5c');
  update public.guildbattle_policy_v4 set engine_hash = 'd5b7e6356faa93ae008fd332844a36311bbe545422ad76eae66d561662b77935' where singleton and engine_hash in ('ef3c3c5879627ec0d156608e48d0e1e0e9bed4527879e9190ec39b7b99e6e03a', 'd5b7e6356faa93ae008fd332844a36311bbe545422ad76eae66d561662b77935');
  update public.arcade_policy_v5 set engine_hash = '380cd4138c6a119144409d4b6a9e8ec59a46c42548317b87c8af942613a15f04' where singleton and engine_hash in ('d2624efb090ffc55d062b84b9fb7619d205f5a531761cb7a9f991e4cec813f8f', '380cd4138c6a119144409d4b6a9e8ec59a46c42548317b87c8af942613a15f04');
  update public.battle_replay_policy_v6 set engine_hash = '972e2458e4ea4aa38d924238f414b7c7e601acb342232dd6f95d83d6ff495c58' where singleton and engine_hash in ('6ec3f7fe99fe0c32c2bae9a578d60496609540cb8f9f35d9f65e76c879c54f41', '972e2458e4ea4aa38d924238f414b7c7e601acb342232dd6f95d83d6ff495c58');
  update public.battle_replay_policy_v7 set engine_hash = 'f10146d7143064f5a7411cf37ee10c17f9f2beb6a611c59d1f7f6cdfef346873' where singleton and engine_hash in ('69f253990447d4373e37d99c6eda34f01f2f63ee43c7b6649cb901be02528dfb', 'f10146d7143064f5a7411cf37ee10c17f9f2beb6a611c59d1f7f6cdfef346873');
  if not exists (select 1 from public.pvp_policy_v3 where singleton and engine_hash = 'ddd3528a4d2d30e8be7e43c2b4a9ec0248289e54a5bef8ecaf9e8dedd1b21a5c')
     or not exists (select 1 from public.guildbattle_policy_v4 where singleton and engine_hash = 'd5b7e6356faa93ae008fd332844a36311bbe545422ad76eae66d561662b77935')
     or not exists (select 1 from public.arcade_policy_v5 where singleton and engine_hash = '380cd4138c6a119144409d4b6a9e8ec59a46c42548317b87c8af942613a15f04')
     or not exists (select 1 from public.battle_replay_policy_v6 where singleton and engine_hash = '972e2458e4ea4aa38d924238f414b7c7e601acb342232dd6f95d83d6ff495c58')
     or not exists (select 1 from public.battle_replay_policy_v7 where singleton and engine_hash = 'f10146d7143064f5a7411cf37ee10c17f9f2beb6a611c59d1f7f6cdfef346873')
  then
    raise exception 'STOP: 엔진 해시가 예상과 다릅니다. rename_three_cards_hash_staging.sql 을 먼저 돌렸는지 확인해 주세요.';
  end if;
end $hash$;
commit;
