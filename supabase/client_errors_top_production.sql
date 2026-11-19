-- 최근 24시간 오류 상위 (읽기 전용, 단일 SELECT). 먼저 client_errors_production.sql 을 실행하세요.
-- 관리자 확인용. 이 쿼리는 아무것도 지우지 않습니다.
-- 아직 실행하지 마세요. 형님이 운영 적용을 직접 승인한 뒤에만 실행합니다.
select
  ((select system_identifier::text from pg_catalog.pg_control_system()) = '7692130048193495360')
  and to_regclass('public.client_errors') is not null as ok,
  (select count(*) from public.client_errors where created_at > clock_timestamp() - interval '24 hours') as rows_24h,
  (
    select coalesce(jsonb_agg(x), '[]'::jsonb)
    from (
      select e.msg_hash,
             max(e.message) as message,
             max(e.source) as source,
             count(*)::int as n,
             max(e.created_at) as last_at
        from public.client_errors e
       where e.created_at > clock_timestamp() - interval '24 hours'
       group by e.msg_hash
       order by count(*) desc, max(e.created_at) desc
       limit 30
    ) x
  ) as top;
