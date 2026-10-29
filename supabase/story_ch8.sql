-- =====================================================================
-- 스토리 챕터 8 「주홍글씨」 (단일 루트: 안지윤 · 안소라 페이즈 1·2·9·11 · 페이즈 15개, 15페이즈 보스)
-- 사용법: Supabase SQL Editor 에 붙여넣고 Run. 여러 번 실행해도 안전. service_role 키 필요 없음.
-- 필요 조건: story_ch7.sql 까지 적용된 상태
-- 챕터 2~7과 같은 규칙: 카드 보상 없이 스탯 포인트 (일반 3, 마지막 페이즈 5). 소환권 +10 은 기존 _story_ticket_sync 가 챕터 전체 첫 클리어 때 지급
-- 페이즈 수는 설정 행 개수로 정해짐 (10개 제한 없음). 페이즈 열림: 챕터 7 전체 클리어 후 (story_start_phase 의 기존 조건)
-- =====================================================================
insert into public.story_phase_config (chapter, phase, type, points, reward_grade, enemy_count) values
  (8,1,'normal',3,null,5), (8,2,'normal',3,null,5), (8,3,'normal',3,null,5), (8,4,'normal',3,null,5), (8,5,'normal',3,null,5), (8,6,'normal',3,null,5), (8,7,'normal',3,null,5), (8,8,'normal',3,null,5), (8,9,'normal',3,null,5), (8,10,'normal',3,null,5), (8,11,'normal',3,null,5), (8,12,'normal',3,null,5), (8,13,'normal',3,null,5), (8,14,'normal',3,null,5), (8,15,'boss',5,null,5)
on conflict (chapter, phase) do update set type = excluded.type, points = excluded.points, reward_grade = excluded.reward_grade, enemy_count = excluded.enemy_count;

-- 확인: select chapter, count(*) from public.story_phase_config group by chapter order by chapter;  → 8 | 15
-- 출전 조건(남성 출전 불가·안지윤 출전 금지·단독 출전)·게스트 레벨·적 스토리 레벨·NPC 카드는 클라이언트 데이터(js/story-data-ch8.js, data/npc_cards.csv)에만 있음
