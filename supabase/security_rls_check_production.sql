-- 보안 점검 (읽기 전용, 단일 SELECT). 스키마를 바꾸거나 권한을 고치지 않습니다.
-- no_rls: public 표 중 RLS 가 꺼져 있고, anon/authenticated 에게 권한이 있는 것.
-- anon_writes: RLS 는 켜져 있지만 anon 이 거의 제한 없이 insert/update/delete 할 수 있는 정책.
-- definer_anon: SECURITY DEFINER 함수 중 anon 이 실행할 수 있는 것 (의도된 RPC 도 포함).
-- PRODUCTION ONLY (htarwisgkkphutxxnuak). system_identifier 7692130048193495360.
-- 아직 실행하지 마세요. 형님이 운영 적용을 직접 승인한 뒤에만 실행합니다.
select
  ((select system_identifier::text from pg_catalog.pg_control_system()) = '7692130048193495360') as ok,
  (
    select coalesce(jsonb_agg(x order by x.table_name), '[]'::jsonb)
    from (
      select c.relname as table_name,
             has_table_privilege('anon', c.oid, 'SELECT') as anon_select,
             has_table_privilege('anon', c.oid, 'INSERT') as anon_insert,
             has_table_privilege('anon', c.oid, 'UPDATE') as anon_update,
             has_table_privilege('anon', c.oid, 'DELETE') as anon_delete,
             has_table_privilege('authenticated', c.oid, 'SELECT') as auth_select,
             has_table_privilege('authenticated', c.oid, 'INSERT') as auth_insert,
             has_table_privilege('authenticated', c.oid, 'UPDATE') as auth_update,
             has_table_privilege('authenticated', c.oid, 'DELETE') as auth_delete
        from pg_class c
        join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public'
         and c.relkind = 'r'
         and c.relrowsecurity is not true
         and (
           has_table_privilege('anon', c.oid, 'SELECT')
           or has_table_privilege('anon', c.oid, 'INSERT')
           or has_table_privilege('anon', c.oid, 'UPDATE')
           or has_table_privilege('anon', c.oid, 'DELETE')
           or has_table_privilege('authenticated', c.oid, 'SELECT')
           or has_table_privilege('authenticated', c.oid, 'INSERT')
           or has_table_privilege('authenticated', c.oid, 'UPDATE')
           or has_table_privilege('authenticated', c.oid, 'DELETE')
         )
    ) x
  ) as no_rls,
  (
    select coalesce(jsonb_agg(x order by x.table_name, x.policy), '[]'::jsonb)
    from (
      select c.relname as table_name,
             p.polname as policy,
             case p.polcmd when 'a' then 'INSERT' when 'w' then 'UPDATE' when 'd' then 'DELETE' when '*' then 'ALL' else p.polcmd::text end as cmd,
             pg_get_expr(p.polqual, p.polrelid) as using_expr,
             pg_get_expr(p.polwithcheck, p.polrelid) as check_expr
        from pg_policy p
        join pg_class c on c.oid = p.polrelid
        join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public'
         and p.polpermissive
         and p.polcmd in ('a', 'w', 'd', '*')
         and (
           p.polroles = '{}'::oid[]
           or 0 = any (p.polroles)
           or exists (select 1 from pg_roles r where r.oid = any (p.polroles) and r.rolname = 'anon')
         )
         and (
           coalesce(pg_get_expr(p.polqual, p.polrelid), 'true') in ('true', '(true)')
           or coalesce(pg_get_expr(p.polwithcheck, p.polrelid), 'true') in ('true', '(true)')
         )
    ) x
  ) as anon_writes,
  (
    select coalesce(jsonb_agg(x order by x.function), '[]'::jsonb)
    from (
      select p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' as function
        from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public'
         and p.prosecdef
         and has_function_privilege('anon', p.oid, 'EXECUTE')
    ) x
  ) as definer_anon;
