-- CH12 P14 「하얀 핸드랩」 시트 개정 (11/02): 안지수(필수) vs 임유리 1명 → enemy_count 5 → 1 (처치 EXP 상한)
-- 페이즈 수(21)·포인트·타입은 그대로. '져도 클리어(별 3개)' 는 게임 코드(js/story.js loseClears)라 서버 변경 없음
-- 사용법: Supabase SQL Editor 에 붙여넣고 Run. 여러 번 실행해도 안전.
update public.story_phase_config set enemy_count = 1 where chapter = 12 and phase = 14;
-- 확인: 1행 · 14 | normal | 3 | 1
select phase, type, points, enemy_count from public.story_phase_config where chapter = 12 and phase = 14;
