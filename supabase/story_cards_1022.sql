-- =====================================================================
-- VR: Abyss Gate - 신규 카드 반영 (2026-10-22)
-- 2000000012: 허유희(HR) → 하지혜(UR) 로 교체, 2000000013~16 신규 4장
-- 사용법: SQL Editor에 붙여넣고 Run. 여러 번 실행해도 안전.
-- =====================================================================
insert into public.story_card_pool (id, grade, name, gacha) values
  ('2000000012','ULTRA RARE','하지혜',true),
  ('2000000013','SUPER RARE','박인영',true),
  ('2000000014','SUPER RARE','하지은',true),
  ('2000000015','NORMAL','정미선',true),
  ('2000000016','RARE','정지선',true)
on conflict (id) do update set grade = excluded.grade, name = excluded.name, gacha = excluded.gacha;

-- 확인용: 5행이 나오면 정상
select id, grade, name, gacha from public.story_card_pool where id between '2000000012' and '2000000016' order by id;
