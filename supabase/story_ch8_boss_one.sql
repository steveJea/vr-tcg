-- 챕8 P15 보스전: [염원] 안지윤 1명만 등장 → enemy_count 5 → 1 (전투 EXP 처치 수 상한). 여러 번 실행해도 안전.
update public.story_phase_config set enemy_count = 1 where chapter = 8 and phase = 15 and enemy_count is distinct from 1;

-- 확인: select chapter, phase, type, enemy_count from public.story_phase_config where chapter = 8 and phase = 15;  → 8 | 15 | boss | 1
