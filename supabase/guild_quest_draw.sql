-- 조직 일일 의뢰 '페이즈 정리 5' → '인재 소환 1회' (보상 그대로: 세력 10 · 골드 800 · 충성 15)
-- 진행도 = 소환 기록(story_gacha_log) 1줄마다 +1 → 무료·소환권·10연 모두 셈 (guild2.sql _guild_trg_draw)
-- 같은 종류 중복 방지: 예전 '소환'(d_draw) 의뢰는 새로 뽑히지 않게 끔 (오늘 이미 받은 d_draw 는 그대로 진행·받기 가능)
-- 여러 번 돌려도 안전. 받은 의뢰·다른 의뢰·3개 완료 보너스는 건드리지 않음
begin;
update public.guild_quest_pool
   set event = 'draw', goal = 1, label = '인재 소환 1회', icon = '🎴',
       reward = '{"loyalty":15,"gold":800,"exp":10}'::jsonb
 where key = 'd_phase';
update public.guild_quest_pool set active = false where key = 'd_draw';
-- 오늘(이후) 아직 안 받은 '페이즈 정리' 의뢰: 목표 5 → 1. 진행도가 1 이상이었으면 바로 받기 가능, 0 이면 다음 소환부터
update public.guild_daily_quests
   set goal = 1, progress = least(1, progress)
 where qkey = 'd_phase' and claimed_at is null and day >= public._guild_day() and goal <> 1;
commit;
-- 확인: select key, event, goal, label, reward, active from public.guild_quest_pool where key in ('d_phase', 'd_draw');
