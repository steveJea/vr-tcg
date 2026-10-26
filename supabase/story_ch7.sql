-- =====================================================================
-- 스토리 챕터 7 「THE BELL JAR」 (단일 루트: 민유연 · 5페이즈 유가을 단독 · 7페이즈 강태안/강태준/이민수/김철민, 페이즈 10개)
-- 사용법: Supabase SQL Editor 에 붙여넣고 Run. 여러 번 실행해도 안전. service_role 키 필요 없음.
-- 필요 조건: story_ch6.sql 까지 적용된 상태
-- 챕터 2~6과 같은 규칙: 카드 보상 없이 스탯 포인트 (일반 3, 마지막 페이즈 5). 재화 드롭·소탕·소환권·행동력은 기존 함수가 챕터 번호로 처리
-- 페이즈 열림: 챕터 6 전체 클리어 후 (story_start_phase 의 기존 조건)
-- 적 수: 6페이즈 1명(유가을), 7·9페이즈 4명, 나머지 5명
-- =====================================================================
insert into public.story_phase_config (chapter, phase, type, points, reward_grade, enemy_count) values
  (7,1,'normal',3,null,5), (7,2,'normal',3,null,5), (7,3,'normal',3,null,5), (7,4,'normal',3,null,5), (7,5,'normal',3,null,5),
  (7,6,'normal',3,null,1), (7,7,'normal',3,null,4), (7,8,'normal',3,null,5), (7,9,'normal',3,null,4), (7,10,'boss',5,null,5)
on conflict (chapter, phase) do update set type = excluded.type, points = excluded.points, reward_grade = excluded.reward_grade, enemy_count = excluded.enemy_count;

-- 확인: select chapter, count(*) from public.story_phase_config group by chapter order by chapter;  → 7 | 10
-- 출전 조건(남성/여성 금지·최대 장수·추가 편성 금지)·필수 카드 레벨·적 스토리 레벨·NPC 카드는 클라이언트 데이터(js/story-data-ch7.js, data/npc_cards.csv)에만 있음
