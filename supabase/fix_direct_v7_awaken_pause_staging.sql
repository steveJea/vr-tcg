-- =====================================================================
-- 11/18 챕터0 P3 [각성] 임유리 난입 후 저장 실패("전투 기록이 맞지 않아요") 수정.
-- 서버 재계산 엔진(story-direct-verify-v7)이 화면 전투처럼 각성 난입 시 적 턴을 멈추고
-- 같은 내 턴으로 바로 넘겨 주도록 맞춤 → 엔진 해시 변경. 전투 수치 변화 없음. 삭제 없음.
-- 먼저 Edge Function story-direct-verify-v7 을 새 dashboard_single_file.ts 로 재배포한 뒤 실행.
-- 여러 번 실행해도 안전. STAGING ONLY (cuyqchmdcnsgzkwyclji).
-- =====================================================================
begin;
do $guard$
begin
  if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7703759698107299042' then
    raise exception 'STOP: awaken pause hash is staging cuyqchmdcnsgzkwyclji only; production forbidden';
  end if;
end $guard$;
do $hash$
begin
  update public.battle_replay_policy_v7 set engine_hash = 'ca2183b100c223112f64c8d10496f9fdb676d7442bd7522faa2641287eee09b0'
    where singleton and engine_hash in ('2fbf41b3446cb61e5a66fd0ea80380d0fa77f644f26a5e1219ea70b91bf39a3a', 'ca2183b100c223112f64c8d10496f9fdb676d7442bd7522faa2641287eee09b0');
  if not exists (select 1 from public.battle_replay_policy_v7 where singleton and engine_hash = 'ca2183b100c223112f64c8d10496f9fdb676d7442bd7522faa2641287eee09b0') then
    raise exception 'STOP: battle_replay_policy_v7 엔진 해시가 예상(2fbf41b3…)과 다릅니다.';
  end if;
end $hash$;
commit;
