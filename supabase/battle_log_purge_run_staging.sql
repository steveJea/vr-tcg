-- =====================================================================
-- ⚠️ 형님이 이 정리를 직접 승인한 뒤에만 실행하세요.
-- 먼저 battle_log_purge_dryrun_staging.sql 로 건수·용량을 확인하세요.
-- 도감·업적·랭킹·PvP 전적 요약은 남기고, 30일이 지난 원본 페이로드와 오래된 공지만 정리합니다.
-- 이 파일을 설치 SQL 과 함께 실행하지 마세요.
-- STAGING ONLY (cuyqchmdcnsgzkwyclji). system_identifier 7703759698107299042.
-- =====================================================================
begin;
do $guard$
begin
  if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7703759698107299042' then
    raise exception 'STOP: this file is staging cuyqchmdcnsgzkwyclji only; production htarwisgkkphutxxnuak forbidden';
  end if;
  if to_regprocedure('public.battle_log_purge(text)') is null then
    raise exception 'STOP: 먼저 battle_log_purge_staging.sql 을 실행하세요';
  end if;
end $guard$;
select public.battle_log_purge('PURGE') as result;
commit;
