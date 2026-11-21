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
  update public.pvp_policy_v3 set engine_hash = 'abe96a83071bc0113dd991a0c72a6dc839fc22249a542c9d983ee998becf9537' where singleton and engine_hash in ('5e6ec74db1ddae269734a9e26fa794dcc663d720ff9501ff9546f3970807950d', 'abe96a83071bc0113dd991a0c72a6dc839fc22249a542c9d983ee998becf9537');
  update public.guildbattle_policy_v4 set engine_hash = '2cc3e78c3ed78bc08a3da4c8eb21bfdcebe40e1312916c7eb58f167e9d61914c' where singleton and engine_hash in ('ef3c3c5879627ec0d156608e48d0e1e0e9bed4527879e9190ec39b7b99e6e03a', '2cc3e78c3ed78bc08a3da4c8eb21bfdcebe40e1312916c7eb58f167e9d61914c');
  update public.arcade_policy_v5 set engine_hash = 'd033151109938fa00c57df14afaf6960eb01a7f7f2e3f4834dad27e00c79f104' where singleton and engine_hash in ('d2624efb090ffc55d062b84b9fb7619d205f5a531761cb7a9f991e4cec813f8f', 'd033151109938fa00c57df14afaf6960eb01a7f7f2e3f4834dad27e00c79f104');
  update public.battle_replay_policy_v6 set engine_hash = 'db895f9df849a6e72133d5a9e7af23c2a97ef2518243a28390ad7caaacb46ff4' where singleton and engine_hash in ('6ec3f7fe99fe0c32c2bae9a578d60496609540cb8f9f35d9f65e76c879c54f41', 'db895f9df849a6e72133d5a9e7af23c2a97ef2518243a28390ad7caaacb46ff4');
  update public.battle_replay_policy_v7 set engine_hash = '648c70496e80bb3382186ac616f2da1f8caee7ccdec7e8b3a15e3abc1a12e275' where singleton and engine_hash in ('69f253990447d4373e37d99c6eda34f01f2f63ee43c7b6649cb901be02528dfb', '648c70496e80bb3382186ac616f2da1f8caee7ccdec7e8b3a15e3abc1a12e275');
  if not exists (select 1 from public.pvp_policy_v3 where singleton and engine_hash = 'abe96a83071bc0113dd991a0c72a6dc839fc22249a542c9d983ee998becf9537')
     or not exists (select 1 from public.guildbattle_policy_v4 where singleton and engine_hash = '2cc3e78c3ed78bc08a3da4c8eb21bfdcebe40e1312916c7eb58f167e9d61914c')
     or not exists (select 1 from public.arcade_policy_v5 where singleton and engine_hash = 'd033151109938fa00c57df14afaf6960eb01a7f7f2e3f4834dad27e00c79f104')
     or not exists (select 1 from public.battle_replay_policy_v6 where singleton and engine_hash = 'db895f9df849a6e72133d5a9e7af23c2a97ef2518243a28390ad7caaacb46ff4')
     or not exists (select 1 from public.battle_replay_policy_v7 where singleton and engine_hash = '648c70496e80bb3382186ac616f2da1f8caee7ccdec7e8b3a15e3abc1a12e275')
  then
    raise exception 'STOP: 엔진 해시가 예상과 다릅니다. rename_three_cards_hash_staging.sql 을 먼저 돌렸는지 확인해 주세요.';
  end if;
end $hash$;
commit;
