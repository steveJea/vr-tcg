-- =====================================================================
-- 스토리 챕터 13 「예전의 너로」(15 페이즈) 페이즈 설정 + 입장 레벨 23
-- 사용법: Supabase SQL Editor 에 붙여넣고 Run. 여러 번 실행해도 안전 (insert … on conflict · create or replace). 삭제 없음. service_role 키 필요 없음.
-- 필요 조건: story_ch12.sql 적용된 상태
-- 스탯 포인트 일반 3, 마지막 페이즈 5. P15 「벌레」 = 일반 전투(1턴 생존)라 type normal. enemy_count = 시트 적 수
-- 보유 마나·별점·출전 조건·대본(P14)은 클라이언트(js/story-data-ch13.js)에만 있음
-- =====================================================================
insert into public.story_phase_config (chapter, phase, type, points, reward_grade, enemy_count) values
  (13,1,'normal',3,null,3), (13,2,'normal',3,null,3), (13,3,'normal',3,null,3), (13,4,'normal',3,null,5), (13,5,'normal',3,null,5), (13,6,'normal',3,null,1), (13,7,'normal',3,null,3), (13,8,'normal',3,null,3), (13,9,'normal',3,null,3), (13,10,'normal',3,null,3), (13,11,'normal',3,null,3), (13,12,'normal',3,null,5), (13,13,'normal',3,null,5), (13,14,'normal',3,null,1), (13,15,'normal',5,null,1)
on conflict (chapter, phase) do update set type = excluded.type, points = excluded.points, reward_grade = excluded.reward_grade, enemy_count = excluded.enemy_count;

create or replace function public._player_unlock_level(p_key text) returns int language sql immutable as $$
  select case p_key when 'sweep' then 5 when 'skill' then 10 when 'equip' then 15 when 'equip_merge' then 20
    when 'chapter_2' then 7 when 'chapter_3' then 9 when 'chapter_4' then 11 when 'chapter_5' then 12 when 'chapter_6' then 14
    when 'chapter_7' then 15 when 'chapter_8' then 16 when 'chapter_9' then 18 when 'chapter_10' then 20 when 'chapter_11' then 21 when 'chapter_12' then 22 when 'chapter_13' then 23 when 'chapter_14' then 24
    else null end $$;

-- 확인: select phase, type, points, enemy_count from public.story_phase_config where chapter = 13 order by phase;  → 15행
