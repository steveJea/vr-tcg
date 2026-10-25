-- =====================================================================
-- VR: Abyss Gate - 신규 카드 반영 (2026-10-25)
-- 유가을(2000000040, HIGH RARE) 뽑기 풀 추가 · 민홍기(1000100007) 2번 스킬 「용서는 없다」 액티브 전환 → 스킬 레벨 메타(해금 Lv5)
-- 사용법: SQL Editor에 붙여넣고 Run. 여러 번 실행해도 안전.
-- =====================================================================
insert into public.story_card_pool (id, grade, name, gacha) values
  ('2000000040','HIGH RARE','유가을',true)
on conflict (id) do update set grade = excluded.grade, name = excluded.name, gacha = excluded.gacha;

insert into public.story_skill_meta (card_id, idx, unlock) values
  ('1000100007',2,5)
on conflict (card_id, idx) do update set unlock = excluded.unlock;

-- 확인용: 2행
select 'pool' k, id, grade, name, gacha::text from public.story_card_pool where id = '2000000040'
union all
select 'skill', card_id, idx::text, unlock::text, null from public.story_skill_meta where card_id = '1000100007' and idx = 2;
