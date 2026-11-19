-- 확인용 (읽기 전용, 아직 실행하지 마세요): ok = true 면 설치 정상. cron_on = true 면 pg_cron 이 매시 20분에 만료 계정을 지움.
-- cron_on = false 여도 기능은 동작함. 매일 SQL Editor 에서 select public.account_withdraw_purge_due(50); 를 실행하면 됨.
select
  ((select system_identifier::text from pg_catalog.pg_control_system()) = '7692130048193495360')
  and coalesce((j->>'ok')::boolean, false) as ok,
  coalesce((j->>'cron_on')::boolean, false) as cron_on
from (select public.account_withdraw_install_ok() as j) s;
