-- =====================================================================
-- 스토리 챕터 12 「위대한 개츠비」(21 페이즈) 페이즈 설정 + 입장 레벨 22
-- 사용법: Supabase SQL Editor 에 붙여넣고 Run. 여러 번 실행해도 안전 (insert … on conflict · create or replace). 삭제 없음. service_role 키 필요 없음.
-- 필요 조건: story_ch9_11.sql · story_level_gate.sql 적용된 상태
-- 규칙은 챕터 9~11과 같음: 스탯 포인트 일반 3, 마지막 페이즈 5. P21 「첫눈」 = 일반 전투(적 전멸)라 type normal
-- enemy_count: 시트 적 수 (P17 4 · P20 3 · P21 3, 나머지 5)
-- =====================================================================
insert into public.story_phase_config (chapter, phase, type, points, reward_grade, enemy_count) values
  (12,1,'normal',3,null,5), (12,2,'normal',3,null,5), (12,3,'normal',3,null,5), (12,4,'normal',3,null,5), (12,5,'normal',3,null,5), (12,6,'normal',3,null,5), (12,7,'normal',3,null,5), (12,8,'normal',3,null,5), (12,9,'normal',3,null,5), (12,10,'normal',3,null,5), (12,11,'normal',3,null,5), (12,12,'normal',3,null,5), (12,13,'normal',3,null,5), (12,14,'normal',3,null,5), (12,15,'normal',3,null,5), (12,16,'normal',3,null,5), (12,17,'normal',3,null,4), (12,18,'normal',3,null,5), (12,19,'normal',3,null,5), (12,20,'normal',3,null,3), (12,21,'normal',5,null,3)
on conflict (chapter, phase) do update set type = excluded.type, points = excluded.points, reward_grade = excluded.reward_grade, enemy_count = excluded.enemy_count;

-- 입장 레벨: story_level_gate.sql 과 같은 함수에 chapter_12 = 22 만 추가
create or replace function public._player_unlock_level(p_key text) returns int language sql immutable as $$
  select case p_key when 'sweep' then 5 when 'skill' then 10 when 'equip' then 15 when 'equip_merge' then 20
    when 'chapter_2' then 7 when 'chapter_3' then 9 when 'chapter_4' then 11 when 'chapter_5' then 12 when 'chapter_6' then 14
    when 'chapter_7' then 15 when 'chapter_8' then 16 when 'chapter_9' then 18 when 'chapter_10' then 20 when 'chapter_11' then 21 when 'chapter_12' then 22
    else null end $$;

-- 확인: select phase, type, points, enemy_count from public.story_phase_config where chapter = 12 order by phase;  → 21행
