-- =====================================================================
-- 챕터11 시트 개정 (10/31 오후): P1~P5 적 구성 변경
--   P5 유리 너머 = [염원] 최윤정 · [염원] 최윤아 2명 → enemy_count 2 (P1~P4 는 5명 그대로)
-- 사용법: Supabase SQL Editor 에 붙여넣고 Run. 여러 번 실행해도 안전. 삭제 없음.
-- =====================================================================
update public.story_phase_config set enemy_count = 2 where chapter = 11 and phase = 5 and enemy_count is distinct from 2;
-- 확인: select phase, enemy_count from public.story_phase_config where chapter = 11 order by phase;  → 5 = 2 · 13·14 = 1 · 나머지 5
