-- =====================================================================
-- 챕터10 「마지막 랠리」 시트 개정 (10/30): 페이즈 18 → 16
--   시트 P14(거실)는 전투 없음 → P13 전투 후 대사로 합침, 시트 P17 없음 → 시트 15·16·18 = 게임 14·15·16
--   P15(떨리는 손) 적 [염원] 최윤아 3명 → enemy_count 3 · P16 보스 [염원] 최윤아 1명 → enemy_count 1
-- 사용법: Supabase SQL Editor 에 붙여넣고 Run. 여러 번 실행해도 안전. service_role 키 필요 없음.
-- 주의: 챕터10 페이즈 17·18 설정 행 삭제 (없어진 페이즈라 클리어 판정에서 빠져야 챕터 전체 클리어가 됨)
-- =====================================================================
insert into public.story_phase_config (chapter, phase, type, points, reward_grade, enemy_count) values
  (10,1,'normal',3,null,5), (10,2,'normal',3,null,5), (10,3,'normal',3,null,5), (10,4,'normal',3,null,5), (10,5,'normal',3,null,5), (10,6,'normal',3,null,5), (10,7,'normal',3,null,5), (10,8,'normal',3,null,5), (10,9,'normal',3,null,5), (10,10,'normal',3,null,5), (10,11,'normal',3,null,5), (10,12,'normal',3,null,5), (10,13,'normal',3,null,5), (10,14,'normal',3,null,5), (10,15,'normal',3,null,3), (10,16,'boss',5,null,1)
on conflict (chapter, phase) do update set type = excluded.type, points = excluded.points, reward_grade = excluded.reward_grade, enemy_count = excluded.enemy_count;

delete from public.story_phase_config where chapter = 10 and phase > 16;

-- 확인: select phase, type, points, enemy_count from public.story_phase_config where chapter = 10 order by phase;  → 16행 · 15 | normal | 3 | 3 · 16 | boss | 5 | 1
