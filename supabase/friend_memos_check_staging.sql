-- 확인용 (읽기 전용): ok = true 면 설치 정상. flag_on = true 면 일반 유저에게 쪽지가 열린 상태 (기본은 false).
-- 관리자(stevejean77@gmail.com)는 flag_on 이 false 여도 테스트할 수 있습니다.
select
  ((select system_identifier::text from pg_catalog.pg_control_system()) = '7703759698107299042')
  and coalesce((j->>'ok')::boolean, false) as ok,
  coalesce((j->>'flag_on')::boolean, false) as flag_on
from (select public.friend_memos_install_ok() as j) s;
