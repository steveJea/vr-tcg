-- 확인용 (읽기 전용): ok = true 면 관리자 점검 RPC 가 설치됨. is_on 은 지금 점검이 켜져 있는지.
-- 아직 실행하지 마세요. 형님이 운영 적용을 직접 승인한 뒤에만 실행합니다.
select
  ((select system_identifier::text from pg_catalog.pg_control_system()) = '7692130048193495360')
  and coalesce((j->>'ok')::boolean, false) as ok,
  coalesce((j->>'is_on')::boolean, false) as is_on
from (select public.maintenance_admin_install_ok() as j) s;
