-- 읽기만 함. staging 전용. 설치 후 한 줄 확인.
-- 기대: is_staging=true, terms_version=2026-11-19plus, age_verified_col=true, flag_required=false, status_fn=true
select
  (select system_identifier::text from pg_catalog.pg_control_system()) = '7703759698107299042' as is_staging,
  (select public._consent_versions()->>'terms') as terms_version,
  exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='profiles' and column_name='age_verified'
  ) as age_verified_col,
  coalesce((select enabled from public.app_flags where key='age_verification_required'), true) as flag_required,
  to_regprocedure('public.age_gate_status()') is not null as status_fn;
