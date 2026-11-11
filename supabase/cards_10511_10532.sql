-- =====================================================================
-- 2026-11-11 신규 플레이어 카드 16장 (10511~10513, 10520~10532): 카드 풀 · PVP 덱 검증
-- 아직 스킬이 없어서 뽑기(gacha)는 false 로 넣음. 뽑기에 넣기로 정하면 gacha 만 true 로 바꿔 다시 실행.
-- 사용법: SQL Editor에 붙여넣고 Run. 여러 번 실행해도 안전. 삭제 없음.
-- NPC 6장(10514~10519)은 스토리 적 전용이라 여기 없음.
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
on conflict (id) do update set grade = excluded.grade, name = excluded.name, gacha = excluded.gacha;

insert into public.pvp_card_meta (id, grade, cost) values
  ('10511','SUPER RARE',42),
  ('10512','HIGH RARE',26),
  ('10513','ULTRA RARE',52),
  ('10520','RARE',18),
  ('10521','SUPER RARE',44),
  ('10522','ULTRA RARE',53),
  ('10523','SUPER RARE',45),
  ('10524','ULTRA RARE',53),
  ('10525','ULTRA RARE',49),
  ('10526','SUPER RARE',41),
  ('10527','ULTRA RARE',46),
  ('10528','ULTRA RARE',51),
  ('10529','SUPER RARE',43),
  ('10530','SUPER RARE',36),
  ('10531','SUPER RARE',35),
  ('10532','SUPER RARE',35)
on conflict (id) do update set grade = excluded.grade, cost = excluded.cost;

-- 확인용: 32행
select 'pool' k, id, grade, name, gacha::text from public.story_card_pool where id in ('10511','10512','10513','10520','10521','10522','10523','10524','10525','10526','10527','10528','10529','10530','10531','10532')
union all select 'pvp', id, grade, cost::text, null from public.pvp_card_meta where id in ('10511','10512','10513','10520','10521','10522','10523','10524','10525','10526','10527','10528','10529','10530','10531','10532');
