-- =====================================================================
-- VR: Abyss Gate - 신규 카드 반영 (2026-10-22)
-- 2000000013~17 신규 5장 (하지혜 = 2000000017 UR), 황예영(2000200051) NORMAL → SUPER RARE
-- 2000000012(허유희)는 건드리지 않음.
-- 사용법: SQL Editor에 붙여넣고 Run. 여러 번 실행해도 안전.
-- =====================================================================
insert into public.story_card_pool (id, grade, name, gacha) values
  ('2000000013','SUPER RARE','박인영',true),
  ('2000000014','SUPER RARE','하지은',true),
  ('2000000015','NORMAL','정미선',true),
  ('2000000016','RARE','정지선',true),
  ('2000000017','ULTRA RARE','하지혜',true)
on conflict (id) do update set grade = excluded.grade, name = excluded.name, gacha = excluded.gacha;

update public.story_card_pool set grade = 'SUPER RARE' where id = '2000200051';

-- 확인용: 6행 (13~17 + 2000200051 SUPER RARE)
select id, grade, name, gacha from public.story_card_pool
 where id between '2000000013' and '2000000017' or id = '2000200051' order by id;
