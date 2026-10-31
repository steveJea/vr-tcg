-- =====================================================================
-- 2026-10-31 신규 카드 강보람(10509, HIGH RARE, 코스트 33): 뽑기 풀 · 스킬 해금 레벨 · PVP 덱 검증
-- 사용법: SQL Editor에 붙여넣고 Run. 여러 번 실행해도 안전. 삭제 없음. service_role 키 필요 없음.
-- =====================================================================
insert into public.story_card_pool (id, grade, name, gacha) values
  ('10509','HIGH RARE','강보람',true)
on conflict (id) do update set grade = excluded.grade, name = excluded.name, gacha = excluded.gacha;

insert into public.story_skill_meta (card_id, idx, unlock) values
  ('10509',1,2),
  ('10509',2,5)
on conflict (card_id, idx) do update set unlock = excluded.unlock;

insert into public.pvp_card_meta (id, grade, cost) values
  ('10509','HIGH RARE',33)
on conflict (id) do update set grade = excluded.grade, cost = excluded.cost;

-- 확인용: 4행
select 'pool' k, id, grade, name, gacha::text from public.story_card_pool where id = '10509'
union all select 'skill', card_id, idx::text, unlock::text, null from public.story_skill_meta where card_id = '10509'
union all select 'pvp', id, grade, cost::text, null from public.pvp_card_meta where id = '10509';
