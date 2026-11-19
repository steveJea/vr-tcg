-- 확인용 (읽기 전용, 단일 SELECT): ok = true 면 관리자 RPC 설치 정상.
select
  ((select system_identifier::text from pg_catalog.pg_control_system()) = '7703759698107299042')
  and coalesce((j->>'ok')::boolean, false) as ok,
  coalesce((j->>'is_on')::boolean, false) as is_on
from (select public.maintenance_admin_install_ok() as j) s;
