-- 확인용 (읽기 전용): ok = true 면 설치 정상. cron_on = true 면 매일 06:30 KST 에 30일 지난 오류를 지움.
-- cron_on = false 여도 수집은 동작함. 가끔 select public.client_errors_purge(5000); 를 실행하면 됨.
select
  ((select system_identifier::text from pg_catalog.pg_control_system()) = '7703759698107299042')
  and coalesce((j->>'ok')::boolean, false) as ok,
  coalesce((j->>'cron_on')::boolean, false) as cron_on
from (select public.client_errors_install_ok() as j) s;
