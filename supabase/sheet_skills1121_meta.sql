-- 2026-11-21 시트: 새/변경 액티브 스킬 4개 해금 레벨 (스킬 레벨업). 패시브는 레벨업 대상 아님.
-- data/skills.json 에서: 황보예(기존 사망 패시브 → 액티브), 왕유영·주슬기·허유리 (각 1개, Lv2).
-- staging installer 에 포함. 운영 DB에는 sheet_skills1121_hash_staging.sql 로 같이 반영 (이 파일만 따로 실행할 필요 없음).
insert into public.story_skill_meta (card_id, idx, unlock) values
  ('10462',1,2),
  ('10264',1,2),
  ('10389',1,2),
  ('10451',1,2)
on conflict (card_id, idx) do update set unlock = excluded.unlock;
