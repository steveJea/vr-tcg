-- 확인용 (읽기 전용): ok = true 면 설치 정상. cron_on = true 면 매일 06:30 KST 에 30일 지난 오류를 지움.
-- cron_on = false 여도 수집은 동작함. 가끔 select public.client_errors_purge(5000); 를 실행하면 됨.
-- 아직 실행하지 마세요. 형님이 운영 적용을 직접 승인한 뒤에만 실행합니다.
select
  ((select system_identifier::text from pg_catalog.pg_control_system()) = '7692130048193495360')
  and coalesce((j->>'ok')::boolean, false) as ok,
  coalesce((j->>'cron_on')::boolean, false) as cron_on
from (select public.client_errors_install_ok() as j) s;
