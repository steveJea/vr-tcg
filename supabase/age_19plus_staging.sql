-- 만 19세 미만 이용 불가: 동의 버전 갱신 + 본인인증 게이트 자리(기본 OFF). staging cuyqchmdcnsgzkwyclji ONLY.
-- 형님이 staging Supabase SQL Editor 에서 실행. 추가만 하는 SQL (idempotent). 플래그를 켜지 않음.
-- 클라이언트 js/consent.js 의 TERMS_VERSION/PRIVACY_VERSION 과 같아야 함 (2026-11-19plus).
begin;
do $guard$
begin
  if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7703759698107299042' then
    raise exception 'STOP: staging cuyqchmdcnsgzkwyclji only';
  end if;
end $guard$;

-- 약관·개인정보 문구가 만 19세로 바뀌었으므로, 기존 동의(2026-11-draft)는 다시 받음.
create or replace function public._consent_versions() returns jsonb language sql immutable set search_path = pg_catalog, public, pg_temp as $$
  select jsonb_build_object('terms', '2026-11-19plus', 'privacy', '2026-11-19plus')
$$;

alter table public.profiles add column if not exists age_verified boolean not null default false;
alter table public.profiles add column if not exists age_verified_at timestamptz;

create table if not exists public.app_flags (
  key text primary key check (char_length(key) between 1 and 40),
  enabled boolean not null default false,
  updated_at timestamptz not null default now()
);
alter table public.app_flags enable row level security;
revoke all on public.app_flags from public, anon, authenticated;
-- 클라이언트는 age_gate_status RPC 만 씀. 플래그 테이블은 직접 읽기/쓰기 없음.
insert into public.app_flags(key, enabled) values ('age_verification_required', false)
on conflict (key) do nothing;

create or replace function public._age_gate_ok(p_uid uuid) returns boolean
language plpgsql stable security definer set search_path = pg_catalog, public, pg_temp as $$
begin
  if p_uid is null then return false; end if;
  if not coalesce((select enabled from public.app_flags where key = 'age_verification_required'), false) then
    return true;
  end if;
  return coalesce((select age_verified from public.profiles where id = p_uid), false);
end $$;

create or replace function public.age_gate_status() returns jsonb
language plpgsql stable security definer set search_path = pg_catalog, public, pg_temp as $$
declare req boolean; ver boolean; uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  req := coalesce((select enabled from public.app_flags where key = 'age_verification_required'), false);
  ver := coalesce((select age_verified from public.profiles where id = uid), false);
  return jsonb_build_object('required', req, 'verified', ver, 'ok', (not req) or ver);
end $$;

create or replace function public._age_gate_before_payment() returns trigger
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
begin
  if not public._age_gate_ok(new.user_id) then
    raise exception 'age verification required';
  end if;
  return new;
end $$;

-- 결제 테이블이 있는 테섭에만 트리거를 붙임. 함수를 통째로 바꾸지 않음.
do $pay$
begin
  if to_regclass('public.payment_orders') is null then
    return;
  end if;
  drop trigger if exists payment_orders_age_gate on public.payment_orders;
  create trigger payment_orders_age_gate
    before insert on public.payment_orders
    for each row execute function public._age_gate_before_payment();
end $pay$;

revoke all on function public._consent_versions() from public, anon;
grant execute on function public._consent_versions() to authenticated;
revoke all on function public._age_gate_ok(uuid) from public, anon, authenticated;
revoke all on function public.age_gate_status() from public, anon;
grant execute on function public.age_gate_status() to authenticated;
revoke all on function public._age_gate_before_payment() from public, anon, authenticated;

notify pgrst, 'reload schema';
commit;
select 'age_19plus staging installed (consent 2026-11-19plus, age gate flag OFF)' as result;
