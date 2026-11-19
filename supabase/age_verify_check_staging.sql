-- 읽기만 함. staging 전용. 설치 후 한 줄 확인.
-- 기대: is_staging=true, ci_hash_col=true, apply_fn=true, flag_required=false
select
  (select system_identifier::text from pg_catalog.pg_control_system()) = '7703759698107299042' as is_staging,
  exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='profiles' and column_name='age_ci_hash'
  ) as ci_hash_col,
  to_regprocedure('public.age_verify_apply(uuid,text,text)') is not null as apply_fn,
  coalesce((select enabled from public.app_flags where key='age_verification_required'), false) as flag_required;
