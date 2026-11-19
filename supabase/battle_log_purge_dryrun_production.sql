-- 미리보기 (읽기 전용, 단일 SELECT). 아무것도 지우지 않습니다.
-- total_rows / total_pretty 가 정리되면 줄어들 건수·용량입니다. 형님 확인용.
-- 실제 정리는 이 결과를 보신 뒤, 형님이 승인한 다음에만 battle_log_purge_run_production.sql 을 실행하세요.
-- 아직 실행하지 마세요. 형님이 운영 적용을 직접 승인한 뒤에만 실행합니다.
select
  ((select system_identifier::text from pg_catalog.pg_control_system()) = '7692130048193495360')
  and coalesce((j->>'ok')::boolean, false) as ok,
  coalesce((j->>'deleted_nothing')::boolean, false) as deleted_nothing,
  (j->>'total_rows')::bigint as total_rows,
  j->>'total_pretty' as total_pretty,
  j as preview
from (select public.battle_log_purge_dryrun() as j) s;
