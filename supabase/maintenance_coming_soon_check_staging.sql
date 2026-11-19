-- 확인용 (읽기 전용, 단일 SELECT): ok = true 면 제목/종류/허용 이메일 보강이 된 상태입니다. is_on 은 바꾸지 않습니다.
select
  ((select system_identifier::text from pg_catalog.pg_control_system()) = '7703759698107299042')
  and coalesce((s->>'ok')::boolean, false)
  and coalesce((a->>'ok')::boolean, false) as ok,
  coalesce((s->>'is_on')::boolean, false) as is_on,
  s->>'kind' as kind,
  coalesce((s->>'allow_count')::int, 0) as allow_count
from (select public.maintenance_install_ok() as s, public.maintenance_admin_install_ok() as a) q;
