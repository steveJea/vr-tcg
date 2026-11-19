-- 첫 로그인 동의 기록 (user_consents + consent_status/consent_accept/consent_set_marketing): staging cuyqchmdcnsgzkwyclji ONLY.
-- staging 테스트 DB 전용. 형님이 staging Supabase SQL Editor 에서 실행.
-- 추가만 하는 SQL (idempotent): 여러 번 실행해도 같은 결과. 기존 테이블·데이터는 건드리지 않음.
begin;
do $guard$
begin
  if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7703759698107299042' then
    raise exception 'STOP: staging cuyqchmdcnsgzkwyclji only';
  end if;
end $guard$;
-- ===== 첫 로그인 동의 기록 (이용약관·개인정보·만 19세 이상 확인(컬럼명 age14)·마케팅 선택) =====
-- 기록은 쌓기만 함(append-only): 동의·마케팅 변경마다 새 행. 최신 행이 현재 상태. update/delete 없음.
-- 현재 약관 버전 (클라이언트 js/consent.js 의 TERMS_VERSION/PRIVACY_VERSION 과 같아야 함)
create or replace function public._consent_versions() returns jsonb language sql immutable set search_path = pg_catalog, public, pg_temp as $$
  select jsonb_build_object('terms', '2026-11-19plus', 'privacy', '2026-11-19plus')
$$;
create table if not exists public.user_consents (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  terms_version text not null check (char_length(terms_version) between 1 and 40),
  privacy_version text not null check (char_length(privacy_version) between 1 and 40),
  age14 boolean not null check (age14),
  marketing boolean not null default false,
  agreed_at timestamptz not null default now(),
  user_agent text check (user_agent is null or char_length(user_agent) <= 300),
  source text not null default 'first_login' check (source in ('first_login','settings'))
);
create index if not exists user_consents_user_at on public.user_consents(user_id, agreed_at desc, id desc);
alter table public.user_consents enable row level security;
drop policy if exists user_consents_select_own on public.user_consents;
create policy user_consents_select_own on public.user_consents for select to authenticated using (user_id = auth.uid());
drop policy if exists user_consents_insert_own on public.user_consents;
create policy user_consents_insert_own on public.user_consents for insert to authenticated
  with check (user_id = auth.uid() and age14 and terms_version = (public._consent_versions()->>'terms') and privacy_version = (public._consent_versions()->>'privacy'));
revoke all on public.user_consents from public, anon, authenticated;
grant select, insert on public.user_consents to authenticated;
create or replace function public.consent_status() returns jsonb language plpgsql stable security definer set search_path = pg_catalog, public, pg_temp as $$
declare v jsonb := public._consent_versions(); r public.user_consents;
begin
  if auth.uid() is null then raise exception 'login required'; end if;
  select * into r from public.user_consents where user_id = auth.uid() order by agreed_at desc, id desc limit 1;
  return jsonb_build_object('terms_current', v->>'terms', 'privacy_current', v->>'privacy',
    'current', r.id is not null and r.terms_version = v->>'terms' and r.privacy_version = v->>'privacy' and r.age14,
    'record', case when r.id is null then null else jsonb_build_object('terms_version', r.terms_version, 'privacy_version', r.privacy_version,
      'age14', r.age14, 'marketing', r.marketing, 'agreed_at', r.agreed_at) end);
end $$;
create or replace function public.consent_accept(p_terms text, p_privacy text, p_age14 boolean, p_marketing boolean, p_user_agent text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare v jsonb := public._consent_versions();
begin
  if auth.uid() is null then raise exception 'login required'; end if;
  if p_terms is distinct from v->>'terms' or p_privacy is distinct from v->>'privacy' then raise exception 'consent version mismatch'; end if;
  if p_age14 is not true then raise exception 'age14 required'; end if;
  insert into public.user_consents(user_id, terms_version, privacy_version, age14, marketing, user_agent, source)
  values (auth.uid(), p_terms, p_privacy, true, coalesce(p_marketing, false), left(p_user_agent, 300), 'first_login');
  return public.consent_status();
end $$;
create or replace function public.consent_set_marketing(p_marketing boolean) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare v jsonb := public._consent_versions(); r public.user_consents;
begin
  if auth.uid() is null then raise exception 'login required'; end if;
  select * into r from public.user_consents where user_id = auth.uid() order by agreed_at desc, id desc limit 1;
  if r.id is null or r.terms_version is distinct from v->>'terms' or r.privacy_version is distinct from v->>'privacy' then raise exception 'consent required'; end if;
  if r.marketing is distinct from coalesce(p_marketing, false) then
    insert into public.user_consents(user_id, terms_version, privacy_version, age14, marketing, user_agent, source)
    values (auth.uid(), r.terms_version, r.privacy_version, true, coalesce(p_marketing, false), r.user_agent, 'settings');
  end if;
  return public.consent_status();
end $$;
revoke all on function public._consent_versions() from public, anon;
grant execute on function public._consent_versions() to authenticated;
revoke all on function public.consent_status() from public, anon;
revoke all on function public.consent_accept(text, text, boolean, boolean, text) from public, anon;
revoke all on function public.consent_set_marketing(boolean) from public, anon;
grant execute on function public.consent_status() to authenticated;
grant execute on function public.consent_accept(text, text, boolean, boolean, text) to authenticated;
grant execute on function public.consent_set_marketing(boolean) to authenticated;

commit;
notify pgrst, 'reload schema';
