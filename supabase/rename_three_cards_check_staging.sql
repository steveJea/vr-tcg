-- 확인용 (읽기 전용): ok = true 면 정상
select (
  (select system_identifier::text from pg_catalog.pg_control_system()) = '7703759698107299042'
  and (select name from public.story_card_pool where id = '10098') = '윤수두'
  and (select name from public.story_card_pool where id = '10083') = '김희자'
  and (select name from public.story_card_pool where id = '10444') = '윤부자'
) as ok;
