-- 읽기만 함. production 전용. 적용 후 한 줄 확인. 기대: ok=true
select (
  (select system_identifier::text from pg_catalog.pg_control_system()) = '7692130048193495360'
  and to_regprocedure('public.handle_new_user()') is not null
  and to_regprocedure('public.matches_rate_limit()') is not null
  and not has_function_privilege('anon', 'public.handle_new_user()', 'execute')
  and not has_function_privilege('authenticated', 'public.handle_new_user()', 'execute')
  and not has_function_privilege('anon', 'public.matches_rate_limit()', 'execute')
  and not has_function_privilege('authenticated', 'public.matches_rate_limit()', 'execute')
) as ok;
