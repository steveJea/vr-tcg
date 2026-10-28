-- =====================================================================
-- 스토리 챕터 4 「카르밀라」 (단일 루트: 이민채, 페이즈 10개, 페이즈마다 적 5명)
-- 사용법: Supabase SQL Editor 에 붙여넣고 Run. 여러 번 실행해도 안전. service_role 키 필요 없음.
-- 필요 조건: story_ch3.sql 까지 적용된 상태
-- 챕터 2·3과 같은 규칙: 카드 보상 없이 스탯 포인트 (일반 3, 마지막 페이즈 5). 재화 드롭·소탕·소환권·행동력은 기존 함수가 챕터 번호로 처리
-- 페이즈 열림: 챕터 3 전체 클리어 후 (story_start_phase 의 기존 조건)
-- NPC 카드 [각성] 이민채 (10301) 는 스토리 적 전용: 뽑기 풀(story_card_pool)에 절대 넣지 않음
-- =====================================================================
insert into public.story_phase_config (chapter, phase, type, points, reward_grade, enemy_count) values
  (4,1,'normal',3,null,5), (4,2,'normal',3,null,5), (4,3,'normal',3,null,5), (4,4,'normal',3,null,5), (4,5,'normal',3,null,5),
  (4,6,'normal',3,null,5), (4,7,'normal',3,null,5), (4,8,'normal',3,null,5), (4,9,'normal',3,null,5), (4,10,'boss',5,null,5)
on conflict (chapter, phase) do update set type = excluded.type, points = excluded.points, reward_grade = excluded.reward_grade, enemy_count = excluded.enemy_count;

-- NPC 는 뽑기·보상에 나오지 않게 (혹시 들어가 있으면 제거)
delete from public.story_card_pool where id in ('10301');

-- 확인: select chapter, count(*) from public.story_phase_config group by chapter order by chapter;  → 4 | 10
