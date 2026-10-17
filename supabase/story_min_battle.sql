-- 스토리 전투 최소 시간 15초 → 3초 (적 1명 페이즈는 15초 안에 끝날 수 있어 클리어 저장이 거부되던 문제)
-- Supabase SQL Editor 에 붙여넣고 Run. 여러 번 실행해도 안전.
create or replace function public._story_min_battle_secs() returns int language sql immutable as $$ select 3 $$;
