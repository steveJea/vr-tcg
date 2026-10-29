-- 챕터 0 Phase 4 (마나 소환 전투 튜토리얼) — Supabase SQL Editor 에서 실행. 여러 번 실행해도 안전 (추가·갱신만, 삭제 없음)
-- 적 3명 (문지예·안리·용지혜) · 첫 클리어 보상 송지은(10208)
insert into public.story_phase_config (chapter, phase, type, points, reward_grade, enemy_count) values (0,4,'normal',3,null,3)
on conflict (chapter, phase) do update set type = excluded.type, points = excluded.points, reward_grade = excluded.reward_grade, enemy_count = excluded.enemy_count;
update public.story_phase_config set reward_card = '10208' where chapter = 0 and phase = 4;
select chapter, phase, type, enemy_count, reward_card from public.story_phase_config where chapter = 0 order by phase;
