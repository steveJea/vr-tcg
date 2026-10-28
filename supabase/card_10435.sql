-- =====================================================================
-- 2026-10-27 카드 정리: 이름 변경 3명 + 신규 카드 하승진(10435). 여러 번 실행해도 안전.
--   10053 최창원 → 김대욱 · 10054 최창민 → 김동욱 · 10051 지세강 → 김기림
--   (서성민 SUPPORT 변경은 클라이언트 데이터만 — DB 변경 없음)
-- =====================================================================

-- 1) 카드 풀 이름 + 신규 카드 (뽑기 대상)
insert into public.story_card_pool (id, grade, name, gacha) values
  ('10051','ULTRA RARE','김기림',true),
  ('10054','ULTRA RARE','김동욱',true),
  ('10053','ULTRA RARE','김대욱',true),
  ('10435','ULTRA RARE','하승진',true)
on conflict (id) do update set grade = excluded.grade, name = excluded.name, gacha = excluded.gacha;

-- 2) 스킬 해금 레벨 (스킬 레벨업 서버 검증용)
insert into public.story_skill_meta (card_id, idx, unlock) values
  ('10435',1,2),
  ('10435',2,5),
  ('10435',3,7)
on conflict (card_id, idx) do update set unlock = excluded.unlock;

-- 3) PVP 덱 검증용 등급·코스트
insert into public.pvp_card_meta (id, grade, cost) values
  ('10435','ULTRA RARE',50)
on conflict (id) do update set grade = excluded.grade, cost = excluded.cost;
