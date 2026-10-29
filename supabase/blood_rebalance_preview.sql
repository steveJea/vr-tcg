-- 읽기 전용 미리보기: blood_rebalance_refund.sql 을 돌리면 유저별로 얼마 환급되는지 (맨 위 = 전체 합계)
-- 아무것도 안 바꿈. 몇 번 돌려도 됨. (환급 후 돌리면 줄어든 bloodSpent 기준이라 숫자가 다시 나오지만, 실제 환급은 기록 때문에 다시 안 됨)
with c as (
  select sp.user_id, (e->>'bloodSpent')::int s, coalesce(p.grade, 'NORMAL') g
  from story_progress sp
  cross join lateral jsonb_array_elements(case when jsonb_typeof(sp.data->'owned') = 'array' then sp.data->'owned' else '[]'::jsonb end) e
  left join story_card_pool p on p.id = e->>'id'
  where coalesce((e->>'bloodSpent')::int, 0) >= 2
), r as (
  select user_id, count(*) cards, sum(s / 2)::bigint blood,
         sum(floor((s / 2) * (case g when 'RARE' then 1.5 when 'HIGH RARE' then 2 when 'SUPER RARE' then 3 when 'ULTRA RARE' then 4 when 'MYTHIC RARE' then 6 when 'LEGENDARY RARE' then 9 else 1 end) * 10
                     / (case g when 'RARE' then 3 when 'HIGH RARE' then 5 when 'SUPER RARE' then 8 when 'ULTRA RARE' then 12 when 'MYTHIC RARE' then 18 when 'LEGENDARY RARE' then 27 else 2 end)))::bigint gold
  from c group by user_id
)
select * from (
  select 0 o, '합계 (' || count(*) || '명)' who, sum(cards)::bigint cards, sum(blood)::bigint blood, sum(gold)::bigint gold from r
  union all select 1, user_id::text, cards, blood, gold from r
) x order by o, blood desc;
