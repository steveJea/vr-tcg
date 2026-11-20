-- 포트원 다날 본인인증 결과 저장 (CI 해시만, 생년월일·이름·전화·원문 CI 저장 안 함). staging ONLY.
-- 형님이 staging Supabase SQL Editor 에서 실행. 추가만 하는 SQL (idempotent). 플래그를 켜지 않음.
begin;
do $guard$
begin
  if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7703759698107299042' then
    raise exception 'STOP: staging cuyqchmdcnsgzkwyclji only';
  end if;
  if to_regclass('public.profiles') is null then
    raise exception 'STOP: profiles required';
  end if;
end $guard$;

alter table public.profiles add column if not exists age_verified boolean not null default false;
alter table public.profiles add column if not exists age_verified_at timestamptz;
alter table public.profiles add column if not exists age_ci_hash text;
alter table public.profiles add column if not exists age_verification_id text;

do $idx$
begin
  if not exists (select 1 from pg_constraint where conname = 'profiles_age_ci_hash_format') then
    alter table public.profiles add constraint profiles_age_ci_hash_format
      check (age_ci_hash is null or age_ci_hash ~ '^[0-9a-f]{64}$');
  end if;
  if not exists (select 1 from pg_constraint where conname = 'profiles_age_verification_id_format') then
    alter table public.profiles add constraint profiles_age_verification_id_format
      check (age_verification_id is null or age_verification_id ~ '^identity-verification-[0-9a-f-]{36}$');
  end if;
end $idx$;

create unique index if not exists profiles_age_ci_hash_uq
  on public.profiles (age_ci_hash) where age_ci_hash is not null;
create unique index if not exists profiles_age_verification_id_uq
  on public.profiles (age_verification_id) where age_verification_id is not null;

-- service_role 전용. Edge Function 이 포트원 조회·만 19세 확인 뒤에만 호출.
create or replace function public.age_verify_apply(p_uid uuid, p_vid text, p_ci_hash text) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare other uuid; mine public.profiles;
begin
  if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7703759698107299042' then
    raise exception 'age verify unavailable';
  end if;
  if p_uid is null or p_vid is null or p_vid !~ '^identity-verification-[0-9a-f-]{36}$'
     or p_ci_hash is null or p_ci_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'invalid verify';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('age-verify:'||p_ci_hash, 0));
  select * into mine from public.profiles where id = p_uid for update;
  if not found then raise exception 'profile required'; end if;
  if mine.age_verification_id is not distinct from p_vid and mine.age_verified and mine.age_ci_hash is not distinct from p_ci_hash then
    return jsonb_build_object('ok', true, 'verified', true, 'idempotent', true);
  end if;
  select id into other from public.profiles where age_verification_id = p_vid and id is distinct from p_uid;
  if other is not null then raise exception 'identity already used'; end if;
  select id into other from public.profiles where age_ci_hash = p_ci_hash and id is distinct from p_uid;
  if other is not null then raise exception 'identity already used'; end if;
  if mine.age_verified and mine.age_ci_hash is not null and mine.age_ci_hash is distinct from p_ci_hash then
    raise exception 'identity mismatch';
  end if;
  update public.profiles
     set age_verified = true, age_verified_at = clock_timestamp(), age_ci_hash = p_ci_hash, age_verification_id = p_vid
   where id = p_uid;
  return jsonb_build_object('ok', true, 'verified', true, 'idempotent', false);
end $$;

revoke all on function public.age_verify_apply(uuid, text, text) from public, anon, authenticated;
grant execute on function public.age_verify_apply(uuid, text, text) to service_role;

notify pgrst, 'reload schema';
commit;
select 'age_verify staging installed (CI hash only, flag unchanged)' as result;
