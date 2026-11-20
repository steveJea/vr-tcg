-- =====================================================================
-- ⚠️ 형님이 자동 삭제까지 직접 승인한 뒤에만 실행하세요.
-- 이 파일을 설치 SQL 과 함께 실행하지 마세요. 기본은 꺼 둡니다.
-- 실행 전 아래 APPROVAL 값을 정확히 다음 문장으로 바꾸세요:
--   예, 자동 삭제를 허용합니다
-- 그대로 두면 중단됩니다.
--
-- 승인되면 pg_cron 이 있을 때 매일 06:40 KST(21:40 UTC)에 battle_log_purge('PURGE') 가 돌아갑니다.
-- pg_cron 이 없으면 설치만 거부됩니다. 그때는 필요할 때 battle_log_purge_run_staging.sql 을 수동 실행하세요.
-- STAGING ONLY (cuyqchmdcnsgzkwyclji). system_identifier 7703759698107299042.
-- =====================================================================
begin;
do $guard$
declare
  approval text := '아직 승인하지 않음';
begin
  if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7703759698107299042' then
    raise exception 'STOP: this file is staging cuyqchmdcnsgzkwyclji only; production htarwisgkkphutxxnuak forbidden';
  end if;
  if to_regprocedure('public.battle_log_purge(text)') is null then
    raise exception 'STOP: 먼저 battle_log_purge_staging.sql 을 실행하세요';
  end if;
  if approval is distinct from '예, 자동 삭제를 허용합니다' then
    raise exception 'STOP: 형님 승인 문장을 파일 안의 approval 값에 적기 전에는 자동 삭제를 켜지 않습니다';
  end if;
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise exception 'STOP: pg_cron 이 없습니다. 자동 스케줄을 켤 수 없어요. 필요할 때 battle_log_purge_run_staging.sql 을 수동 실행하세요';
  end if;
  begin
    perform cron.unschedule('battle_log_purge');
  exception when others then null;
  end;
  perform cron.schedule('battle_log_purge', '40 21 * * *', $c$select public.battle_log_purge('PURGE')$c$);
end $guard$;
commit;
select true as scheduled;
