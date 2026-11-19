-- 확인용 (읽기 전용): ok = true 면 필요한 인덱스가 있거나, 해당 표가 아직 없어 건너뛴 상태입니다.
-- 아직 실행하지 마세요. 형님이 운영 적용을 직접 승인한 뒤에만 실행합니다.
select
  ((select system_identifier::text from pg_catalog.pg_control_system()) = '7692130048193495360')
  and coalesce((j->>'ok')::boolean, false) as ok,
  j->'indexes' as indexes
from (select public.index_hot_filters_install_ok() as j) s;
