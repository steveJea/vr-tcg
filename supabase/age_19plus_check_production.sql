-- 읽기만 함. production 전용. age_19plus_production.sql 적용 후 한 줄 확인.
-- 기대: ok=true, flag_required=false (본인인증 게이트는 기본 꺼짐)
select (
  (select system_identifier::text from pg_catalog.pg_control_system()) = '7692130048193495360'
  and (select public._consent_versions()->>'terms') = '2026-11-19plus'
  and exists (select 1 from information_schema.columns where table_schema='public' and table_name='profiles' and column_name='age_verified')
  and to_regprocedure('public.age_gate_status()') is not null
  and coalesce((select enabled from public.app_flags where key='age_verification_required'), true) = false
) as ok,
coalesce((select enabled from public.app_flags where key='age_verification_required'), true) as flag_required;
