-- =====================================================================
-- VR: Abyss Gate - 신규 카드 반영 (2026-10-22)
-- 10127~17 신규 5장 (하지혜 = 10440 UR), 황예영(10465) NORMAL → SUPER RARE
-- 10452(허유희)는 건드리지 않음.
-- 사용법: SQL Editor에 붙여넣고 Run. 여러 번 실행해도 안전.
-- =====================================================================
insert into public.story_card_pool (id, grade, name, gacha) values
  ('10127','SUPER RARE','박인영',true),
  ('10439','SUPER RARE','하지은',true),
  ('10355','NORMAL','정미선',true),
  ('10367','RARE','정지선',true),
  ('10440','ULTRA RARE','하지혜',true)
on conflict (id) do update set grade = excluded.grade, name = excluded.name, gacha = excluded.gacha;

update public.story_card_pool set grade = 'SUPER RARE' where id = '10465';

-- 확인용: 6행 (13~17 + 10465 SUPER RARE)
select id, grade, name, gacha from public.story_card_pool
 where id between '10127' and '10440' or id = '10465' order by id;
