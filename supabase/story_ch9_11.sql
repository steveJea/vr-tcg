-- =====================================================================
-- 스토리 챕터 9 「기도」(18) · 10 「마지막 랠리」(18) · 11 「사라지지 않는 약속」(16) 페이즈 설정
-- 사용법: Supabase SQL Editor 에 붙여넣고 Run. 여러 번 실행해도 안전 (insert … on conflict). 삭제 없음. service_role 키 필요 없음.
-- 필요 조건: story_ch8.sql 까지 적용된 상태
-- 규칙은 챕터 2~8과 같음: 카드 보상 없이 스탯 포인트 (일반 3, 마지막 페이즈 5). 소환권 +10 은 기존 _story_ticket_sync 가 챕터 전체 첫 클리어 때 지급
-- 페이즈 열림: 앞 챕터 전체 클리어 후 (story_start_phase 의 기존 조건)
-- =====================================================================
insert into public.story_phase_config (chapter, phase, type, points, reward_grade, enemy_count) values
  (9,1,'normal',3,null,5), (9,2,'normal',3,null,5), (9,3,'normal',3,null,5), (9,4,'normal',3,null,5), (9,5,'normal',3,null,5), (9,6,'normal',3,null,5), (9,7,'normal',3,null,5), (9,8,'normal',3,null,5), (9,9,'normal',3,null,5), (9,10,'normal',3,null,5), (9,11,'normal',3,null,5), (9,12,'normal',3,null,5), (9,13,'normal',3,null,5), (9,14,'normal',3,null,5), (9,15,'normal',3,null,5), (9,16,'normal',3,null,5), (9,17,'normal',3,null,5), (9,18,'boss',5,null,5),
  (10,1,'normal',3,null,5), (10,2,'normal',3,null,5), (10,3,'normal',3,null,5), (10,4,'normal',3,null,5), (10,5,'normal',3,null,5), (10,6,'normal',3,null,5), (10,7,'normal',3,null,5), (10,8,'normal',3,null,5), (10,9,'normal',3,null,5), (10,10,'normal',3,null,5), (10,11,'normal',3,null,5), (10,12,'normal',3,null,5), (10,13,'normal',3,null,5), (10,14,'normal',3,null,5), (10,15,'normal',3,null,5), (10,16,'normal',3,null,5), (10,17,'normal',3,null,5), (10,18,'boss',5,null,5),
  (11,1,'normal',3,null,5), (11,2,'normal',3,null,5), (11,3,'normal',3,null,5), (11,4,'normal',3,null,5), (11,5,'normal',3,null,5), (11,6,'normal',3,null,5), (11,7,'normal',3,null,5), (11,8,'normal',3,null,5), (11,9,'normal',3,null,5), (11,10,'normal',3,null,5), (11,11,'normal',3,null,5), (11,12,'normal',3,null,5), (11,13,'normal',3,null,5), (11,14,'normal',3,null,5), (11,15,'normal',3,null,5), (11,16,'boss',5,null,5)
on conflict (chapter, phase) do update set type = excluded.type, points = excluded.points, reward_grade = excluded.reward_grade, enemy_count = excluded.enemy_count;

-- 확인: select chapter, count(*) from public.story_phase_config where chapter between 9 and 11 group by chapter order by chapter;  → 9 | 18 · 10 | 18 · 11 | 16
-- 출전 조건·대여(loan)·게스트 레벨·적 스토리 레벨·패시브는 클라이언트(js/story-data-ch9~11.js, js/skills.js, data/skills.json)에만 있음
