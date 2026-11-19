-- 확인용 (읽기 전용, 단일 SELECT): ok = true 면 설치 정상. is_on 은 아직 끄기여야 합니다(켜기는 마지막 파일).
select
  ((select system_identifier::text from pg_catalog.pg_control_system()) = '7692130048193495360')
  and coalesce((j->>'ok')::boolean, false) as ok,
  coalesce((j->>'is_on')::boolean, false) as is_on,
  j->>'kind' as kind,
  coalesce((j->>'allow_count')::int, 0) as allow_count
from (select public.maintenance_install_ok() as j) s;
