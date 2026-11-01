-- CH12 P20: [염원] 이민채 3 → 1 (적 수 = 처치 보상 상한). P18·P19 는 생존 조건만 바뀌어 서버 변경 없음. 여러 번 실행해도 안전
update public.story_phase_config set enemy_count = 1 where chapter = 12 and phase = 20;
-- 확인용: 3행 (18·19 = 5, 20 = 1)
select phase, enemy_count from public.story_phase_config where chapter = 12 and phase in (18, 19, 20) order by phase;
