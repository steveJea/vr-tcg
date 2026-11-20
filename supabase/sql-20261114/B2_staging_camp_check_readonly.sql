-- B2. 확인 (스테이징 전용 · 읽기 전용). B1 전/후 아무 때나. 표 1개.
--  installed=true 면 B1 적용됨. 칸별: 훈련 중 인재 · 마지막 정산 뒤 지난 시간(24 이상이면 가득).
--  B1 뒤에 해당 계정으로 아무 화면이나 로그인해 2~3초 기다리면 hours_since_last 가 0 근처로 내려가고 인재 레벨이 오름.
with g as (select system_identifier::text = '7703759698107299042' ok from pg_control_system()),
cs as (select md5(replace(prosrc, chr(13), '')) m from pg_proc where oid = to_regprocedure('public.camp_status()'))
select 'camp_status' as item, null::uuid as user_id, null::int as slot, null::text as card_id, null::int as card_level, null::numeric as hours_since_last,
       case (select m from cs) when 'c4d0ab2c2d27d3f6ff62c0f6f78d7dd4' then 'installed=true' when '135e0269160bd3a2f9a500935bd3fef7' then 'installed=false (원본)' else 'installed=?? md5 ' || (select m from cs) end as note
where (select ok from g)
union all
select 'slot', c.user_id, c.slot, o->>'id', (o->>'level')::int, round((extract(epoch from now() - c.last_at) / 3600)::numeric, 2),
       case when c.last_at < now() - interval '24 hours' then '24시간 가득' else '' end
from public.camp_slots c
left join public.story_progress p on p.user_id = c.user_id
left join lateral (select x o from jsonb_array_elements(case when jsonb_typeof(p.data->'owned') = 'array' then p.data->'owned' else '[]'::jsonb end) x where x->>'uid' = c.card_uid limit 1) t on true
where (select ok from g) and c.card_uid is not null
union all
select 'STOP', null, null, null, null, null, '스테이징 DB 가 아님' where not (select ok from g)
order by 1, 6 desc nulls last;
