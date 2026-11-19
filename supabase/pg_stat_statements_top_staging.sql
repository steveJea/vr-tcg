-- 느린 쿼리 상위 (읽기 전용, 단일 SELECT). 스키마를 바꾸지 않습니다.
-- pg_stat_statements 확장이 있어야 합니다. 없으면 ext_ok = false 이고 목록은 비어 있습니다.
-- query 텍스트에 값이 남아 있을 수 있으니, 결과를 외부에 붙여 넣지 마세요.
-- STAGING ONLY (cuyqchmdcnsgzkwyclji). system_identifier 7703759698107299042.
select
  ((select system_identifier::text from pg_catalog.pg_control_system()) = '7703759698107299042') as ok,
  exists (select 1 from pg_extension where extname = 'pg_stat_statements') as ext_ok,
  case
    when not exists (select 1 from pg_extension where extname = 'pg_stat_statements') then '[]'::jsonb
    else (
      select coalesce(jsonb_agg(x), '[]'::jsonb)
      from (
        select
          left(s.query, 400) as query,
          s.calls,
          round(s.total_exec_time::numeric, 1) as total_ms,
          round(s.mean_exec_time::numeric, 1) as mean_ms,
          s.rows
        from pg_stat_statements s
        order by s.total_exec_time desc
        limit 20
      ) x
    )
  end as top;
