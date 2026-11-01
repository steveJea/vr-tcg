-- 읽기 전용 조회 (아무것도 바꾸지 않음): 지금 UR 보유 현황. SQL Editor 에서 실행
-- 1) UR 카드별: 가진 사람 수 · 총 장수
with own as (
  select s.user_id, o->>'id' as card_id, greatest(coalesce((o->>'count')::int, 1), 1) as n
  from public.story_progress s, jsonb_array_elements(case when jsonb_typeof(s.data->'owned') = 'array' then s.data->'owned' else '[]'::jsonb end) o),
ur as (select id, coalesce(name, id) as name from public.story_card_pool where grade = 'ULTRA RARE')
select ur.id, ur.name, count(distinct own.user_id) as owners, coalesce(sum(own.n), 0) as copies
from ur left join own on own.card_id = ur.id
group by ur.id, ur.name order by owners desc, ur.id;

-- 2) 사람별: 닉네임 · UR 장수 · UR 목록
with own as (
  select s.user_id, o->>'id' as card_id, greatest(coalesce((o->>'count')::int, 1), 1) as n
  from public.story_progress s, jsonb_array_elements(case when jsonb_typeof(s.data->'owned') = 'array' then s.data->'owned' else '[]'::jsonb end) o),
ur as (select id, coalesce(name, id) as name from public.story_card_pool where grade = 'ULTRA RARE')
select coalesce(p.nickname, '(닉네임 없음)') as nickname, sum(own.n) as ur_copies,
       string_agg(ur.name || case when own.n > 1 then ' x' || own.n else '' end, ', ' order by ur.name) as ur_list
from own join ur on ur.id = own.card_id left join public.profiles p on p.id = own.user_id
group by own.user_id, p.nickname order by ur_copies desc;
