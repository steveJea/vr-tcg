-- 확인용 (읽기 전용): ok = true 면 정리 함수가 설치됨. 이 쿼리는 아무것도 지우지 않습니다.
-- auto_schedule 은 설치 파일에서 항상 false 입니다. 자동 삭제는 별도 승인 파일이 필요합니다.
-- 아직 실행하지 마세요. 형님이 운영 적용을 직접 승인한 뒤에만 실행합니다.
select
  ((select system_identifier::text from pg_catalog.pg_control_system()) = '7692130048193495360')
  and coalesce((j->>'ok')::boolean, false) as ok,
  coalesce((j->>'auto_schedule')::boolean, false) as auto_schedule
from (select public.battle_log_purge_install_ok() as j) s;
