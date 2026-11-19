-- 읽기만 함. production 전용. age_verify_production.sql 적용 후 한 줄 확인.
-- 기대: ok=true, flag_required=false (게이트는 따로 켜기 전까지 꺼짐)
select (
  (select system_identifier::text from pg_catalog.pg_control_system()) = '7692130048193495360'
  and exists (select 1 from information_schema.columns where table_schema='public' and table_name='profiles' and column_name='age_ci_hash')
  and to_regprocedure('public.age_verify_apply(uuid,text,text)') is not null
  and not has_function_privilege('authenticated', 'public.age_verify_apply(uuid,text,text)', 'execute')
  and not has_function_privilege('anon', 'public.age_verify_apply(uuid,text,text)', 'execute')
  and coalesce((select enabled from public.app_flags where key='age_verification_required'), false) = false
) as ok,
coalesce((select enabled from public.app_flags where key='age_verification_required'), false) as flag_required;
