-- =====================================================================
-- 11/17 어린 최국선(10536) 나이 15 → 9 (캐릭터 시트 수정). 카드 데이터가 엔진에 들어가 있어 엔진 해시 3개 갱신:
--   guildbattle_policy_v4, battle_replay_policy_v6, battle_replay_policy_v7
-- 먼저 story_ch18_19_staging.sql (PR #625) 을 돌린 뒤 실행. 여러 번 실행해도 안전. 삭제 없음. 전투 규칙 변화 없음 (나이는 전투에 안 쓰임).
-- STAGING ONLY (cuyqchmdcnsgzkwyclji). 생성: python3 tools/build_young_age_sql.py (직접 고치지 말 것)
-- =====================================================================
begin;
do $guard$
begin
  if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7703759698107299042' then
    raise exception 'STOP: young age hash staging cuyqchmdcnsgzkwyclji only; production forbidden';
  end if;
end $guard$;
do $hash$
begin
  update public.guildbattle_policy_v4 set engine_hash = 'c87d5a678229e2bbc3bcd92ff3f9f4b8e32291df874a9919c4295b14831d7d07' where singleton and engine_hash in ('7fe844f6bd869991d25558341374dbce28308685365d586b4e0cd2281ae16b58', 'c87d5a678229e2bbc3bcd92ff3f9f4b8e32291df874a9919c4295b14831d7d07');
  update public.battle_replay_policy_v6 set engine_hash = '1d1092662cfa90fd1c118baf7ffb4d83dcb767ef17564e30f9efdecfc3270bd7' where singleton and engine_hash in ('ad59546b94862bbb09cbd63692b21709f9729e035ddf54456664ead9eb927d57', '1d1092662cfa90fd1c118baf7ffb4d83dcb767ef17564e30f9efdecfc3270bd7');
  update public.battle_replay_policy_v7 set engine_hash = '2fbf41b3446cb61e5a66fd0ea80380d0fa77f644f26a5e1219ea70b91bf39a3a' where singleton and engine_hash in ('c326c57e218a5b6fe779d3835931c47a9917b17332740b16bd723cb0d05b3119', '2fbf41b3446cb61e5a66fd0ea80380d0fa77f644f26a5e1219ea70b91bf39a3a');
  if not exists (select 1 from public.pvp_policy_v3 where singleton and engine_hash = 'c5b478a735b1798bd7b9c51902ae85efe5ed861e9ab2936cecf753b4e250a648')
     or not exists (select 1 from public.guildbattle_policy_v4 where singleton and engine_hash = 'c87d5a678229e2bbc3bcd92ff3f9f4b8e32291df874a9919c4295b14831d7d07')
     or not exists (select 1 from public.arcade_policy_v5 where singleton and engine_hash = 'fc7c0deaec9781badc9adc4b6895bbc2bc39ffe42e51dc3ae4deab647790e063')
     or not exists (select 1 from public.battle_replay_policy_v6 where singleton and engine_hash = '1d1092662cfa90fd1c118baf7ffb4d83dcb767ef17564e30f9efdecfc3270bd7')
     or not exists (select 1 from public.battle_replay_policy_v7 where singleton and engine_hash = '2fbf41b3446cb61e5a66fd0ea80380d0fa77f644f26a5e1219ea70b91bf39a3a')
  then
    raise exception 'STOP: 엔진 해시가 예상과 다릅니다. story_ch18_19_staging.sql 을 먼저 돌렸는지 확인해 주세요.';
  end if;
end $hash$;
commit;
