-- =====================================================================
-- 스토리 챕터 14 「작은 아씨들」(18 페이즈) 페이즈 설정 + 입장 레벨 24
-- 사용법: Supabase SQL Editor 에 붙여넣고 Run. 여러 번 실행해도 안전 (insert … on conflict · create or replace). 삭제 없음. service_role 키 필요 없음.
-- 필요 조건: story_ch13.sql 적용된 상태
-- 스탯 포인트 일반 3, 마지막 페이즈 5. enemy_count = 시트 적 수 (P13 날개 2)
-- 보유 마나·별점·출전 조건은 클라이언트(js/story-data-ch14.js)에만 있음
-- =====================================================================
insert into public.story_phase_config (chapter, phase, type, points, reward_grade, enemy_count) values
  (14,1,'normal',3,null,5), (14,2,'normal',3,null,5), (14,3,'normal',3,null,5), (14,4,'normal',3,null,5), (14,5,'normal',3,null,5), (14,6,'normal',3,null,5), (14,7,'normal',3,null,5), (14,8,'normal',3,null,5), (14,9,'normal',3,null,5), (14,10,'normal',3,null,5), (14,11,'normal',3,null,5), (14,12,'normal',3,null,5), (14,13,'normal',3,null,2), (14,14,'normal',3,null,5), (14,15,'normal',3,null,5), (14,16,'normal',3,null,5), (14,17,'normal',3,null,5), (14,18,'normal',5,null,5)
on conflict (chapter, phase) do update set type = excluded.type, points = excluded.points, reward_grade = excluded.reward_grade, enemy_count = excluded.enemy_count;

create or replace function public._player_unlock_level(p_key text) returns int language sql immutable as $$
  select case p_key when 'sweep' then 5 when 'skill' then 10 when 'equip' then 15 when 'equip_merge' then 20
    when 'chapter_2' then 7 when 'chapter_3' then 9 when 'chapter_4' then 11 when 'chapter_5' then 12 when 'chapter_6' then 14
    when 'chapter_7' then 15 when 'chapter_8' then 16 when 'chapter_9' then 18 when 'chapter_10' then 20 when 'chapter_11' then 21 when 'chapter_12' then 22 when 'chapter_13' then 23 when 'chapter_14' then 24 when 'chapter_15' then 25
    else null end $$;

-- 확인: select phase, type, points, enemy_count from public.story_phase_config where chapter = 14 order by phase;  → 18행
