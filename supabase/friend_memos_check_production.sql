-- 확인용 (읽기 전용). 오늘 밤 실섭 업데이트에는 실행하지 마세요.
select
  ((select system_identifier::text from pg_catalog.pg_control_system()) = '7692130048193495360')
  and coalesce((j->>'ok')::boolean, false) as ok,
  coalesce((j->>'flag_on')::boolean, false) as flag_on
from (select public.friend_memos_install_ok() as j) s;
