-- =====================================================================
-- 챕터11 「사라지지 않는 약속」 시트 반영 (10/31): 날개 적 배치
--   P13 창밖 = [왼쪽 날개] 1명 → enemy_count 1 · P14 두 언니의 부탁 = [오른쪽 날개] 1명 → enemy_count 1
--   (P10~12 불량배 5명 · 나머지 페이즈는 그대로)
-- 사용법: Supabase SQL Editor 에 붙여넣고 Run. 여러 번 실행해도 안전. 삭제 없음. service_role 키 필요 없음.
-- =====================================================================
update public.story_phase_config set enemy_count = 1 where chapter = 11 and phase in (13, 14) and enemy_count is distinct from 1;

-- 확인: select phase, type, points, enemy_count from public.story_phase_config where chapter = 11 order by phase;  → 16행 · 13·14 만 enemy_count 1
