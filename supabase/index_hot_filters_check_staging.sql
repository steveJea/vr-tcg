-- 확인용 (읽기 전용): ok = true 면 필요한 인덱스가 있거나, 해당 표가 아직 없어 건너뛴 상태입니다.
select
  ((select system_identifier::text from pg_catalog.pg_control_system()) = '7703759698107299042')
  and coalesce((j->>'ok')::boolean, false) as ok,
  j->'indexes' as indexes
from (select public.index_hot_filters_install_ok() as j) s;
