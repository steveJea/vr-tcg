-- =====================================================================
-- 2026-11-11 신규 카드 16장 (10511~10513, 10520~10532): 카드 목록 · 스킬 해금 레벨 · PVP 덱 검증
-- 뽑기 풀에는 넣지 않음 (gacha = false). 뽑기·스토리 무작위 보상 둘 다 gacha 행만 고르므로 획득 경로 없음.
-- 도감(reward_card_catalog)이 story_card_pool을 참조하므로 행은 필요. 뽑기 공개는 gacha만 true로 바꾸면 됨.
-- 여러 번 실행해도 안전. 삭제 없음.
-- =====================================================================
insert into public.story_card_pool (id, grade, name, gacha) values
  ('10511','SUPER RARE','최수아',false),
  ('10512','HIGH RARE','고세연',false),
  ('10513','ULTRA RARE','[각성] 고세연',false),
  ('10520','RARE','황경민',false),
  ('10521','SUPER RARE','이혜림',false),
  ('10522','ULTRA RARE','이수영',false),
  ('10523','SUPER RARE','천혜영',false),
  ('10524','ULTRA RARE','이동주',false),
  ('10525','ULTRA RARE','김수진',false),
  ('10526','SUPER RARE','조태진',false),
  ('10527','ULTRA RARE','김한철',false),
  ('10528','ULTRA RARE','김진호',false),
  ('10529','SUPER RARE','김태희',false),
  ('10530','SUPER RARE','박승규',false),
  ('10531','SUPER RARE','김경섭',false),
  ('10532','SUPER RARE','천기철',false)
on conflict (id) do update set grade = excluded.grade, name = excluded.name;

insert into public.story_skill_meta (card_id, idx, unlock) values
  ('10511',1,2),
  ('10511',2,5),
  ('10512',1,2),
  ('10512',2,5),
  ('10513',1,2),
  ('10513',2,5),
  ('10513',3,7),
  ('10520',1,2),
  ('10521',1,2),
  ('10521',2,5),
  ('10522',1,2),
  ('10522',2,5),
  ('10522',3,7),
  ('10523',1,2),
  ('10523',2,5),
  ('10524',1,2),
  ('10524',2,5),
  ('10524',3,7),
  ('10525',1,2),
  ('10525',2,5),
  ('10525',3,7),
  ('10526',1,2),
  ('10526',2,5),
  ('10527',1,2),
  ('10527',2,5),
  ('10527',3,7),
  ('10528',1,2),
  ('10528',2,5),
  ('10528',3,7),
  ('10529',1,2),
  ('10529',2,5),
  ('10530',1,2),
  ('10530',2,5),
  ('10531',1,2),
  ('10531',2,5),
  ('10532',1,2),
  ('10532',2,5)
on conflict (card_id, idx) do update set unlock = excluded.unlock;

insert into public.pvp_card_meta (id, grade, cost) values
  ('10511','SUPER RARE',42),
  ('10512','HIGH RARE',27),
  ('10513','ULTRA RARE',53),
  ('10520','RARE',18),
  ('10521','SUPER RARE',44),
  ('10522','ULTRA RARE',54),
  ('10523','SUPER RARE',45),
  ('10524','ULTRA RARE',53),
  ('10525','ULTRA RARE',49),
  ('10526','SUPER RARE',41),
  ('10527','ULTRA RARE',46),
  ('10528','ULTRA RARE',53),
  ('10529','SUPER RARE',43),
  ('10530','SUPER RARE',37),
  ('10531','SUPER RARE',35),
  ('10532','SUPER RARE',35)
on conflict (id) do update set grade = excluded.grade, cost = excluded.cost;
