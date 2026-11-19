-- =====================================================================
-- 2026-11-19 캐릭터 이름 변경 3명 (캐릭터 시트 반영). 수치·등급 변경 없음. 삭제 없음.
--   10098 두윤창 → 윤수두 · 10083 김희건 → 김희자 · 10444 한석열 → 윤부자
-- 여러 번 실행해도 안전. STAGING ONLY (cuyqchmdcnsgzkwyclji). system_identifier 7703759698107299042.
-- =====================================================================
begin;
do $guard$
begin
  if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7703759698107299042' then
    raise exception 'STOP: rename three cards is staging cuyqchmdcnsgzkwyclji only; production forbidden';
  end if;
end $guard$;

update public.story_card_pool p
   set name = v.name
  from (values
    ('10098', '윤수두'),
    ('10083', '김희자'),
    ('10444', '윤부자')
  ) as v(id, name)
 where p.id = v.id
   and p.name is distinct from v.name;

update public.card_id_alias a
   set name = v.name
  from (values
    ('10098', '윤수두'),
    ('10083', '김희자'),
    ('10444', '윤부자')
  ) as v(id, name)
 where a.new_id = v.id
   and a.name is distinct from v.name;

update public.matches m
   set mvp_name = v.name
  from (values
    ('10098', '윤수두'),
    ('10083', '김희자'),
    ('10444', '윤부자')
  ) as v(id, name)
 where m.mvp_id = v.id
   and m.mvp_name is distinct from v.name;

update public.arcade_records_v5 r
   set mvp_name = v.name
  from (values
    ('10098', '윤수두'),
    ('10083', '김희자'),
    ('10444', '윤부자')
  ) as v(id, name)
 where r.mvp_id = v.id
   and r.mvp_name is distinct from v.name;

do $need$
begin
  if (select name from public.story_card_pool where id = '10098') is distinct from '윤수두'
     or (select name from public.story_card_pool where id = '10083') is distinct from '김희자'
     or (select name from public.story_card_pool where id = '10444') is distinct from '윤부자'
  then
    raise exception 'STOP: story_card_pool 이름이 예상과 다릅니다.';
  end if;
end $need$;
commit;
