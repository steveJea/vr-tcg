-- 확인용 (읽기 전용, 단일 SELECT): ok = true 면 곧 오픈이 켜진 상태입니다.
select
  ((select system_identifier::text from pg_catalog.pg_control_system()) = '7692130048193495360')
  and coalesce((j->>'ok')::boolean, false)
  and coalesce((j->>'is_on')::boolean, false)
  and coalesce(j->>'kind', '') = 'coming_soon'
  and coalesce(j->>'message', '') = 'Violence Royale : The Abyss Gate 곧 오픈합니다'
  and coalesce((j->>'allow_count')::int, 0) = 0 as ok,
  coalesce((j->>'is_on')::boolean, false) as is_on,
  j->>'kind' as kind,
  j->>'title' as title,
  j->>'message' as message,
  coalesce((j->>'allow_count')::int, 0) as allow_count
from (select public.maintenance_install_ok() as j) s;
