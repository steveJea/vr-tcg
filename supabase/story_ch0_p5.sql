-- 챕터 0 Phase 5 (보스전 튜토리얼 「수비대장이라고?」) — Supabase SQL Editor 에서 실행. 여러 번 실행해도 안전 (추가·갱신만, 삭제 없음)
-- 보스 안지수(10229) + 부하 4명 (주예나·동지선·남태은·류하예) · 첫 클리어 보상 주예린(10392)
-- 서버 순서 규칙(_story_start_phase_e0): P5 는 P1~P4 를 모두 깬 뒤에만 시작 가능 → P4 를 안 깬 사용자는 P4 부터
insert into public.story_phase_config (chapter, phase, type, points, reward_grade, enemy_count) values (0,5,'boss',3,null,5)
on conflict (chapter, phase) do update set type = excluded.type, points = excluded.points, reward_grade = excluded.reward_grade, enemy_count = excluded.enemy_count;
update public.story_phase_config set reward_card = '10392' where chapter = 0 and phase = 5;
-- 확인 (5줄, 마지막 줄 = 5 | boss | 5 | 10392)
select chapter, phase, type, enemy_count, reward_card from public.story_phase_config where chapter = 0 order by phase;
