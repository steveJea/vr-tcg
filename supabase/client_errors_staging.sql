-- =====================================================================
-- 2026-11-19 클라이언트 오류 수집. 외부 서비스 없음.
-- 작은 client_errors 표 + 분당 제한 insert RPC (anon/로그인 가능).
-- 메시지·스택 길이 제한. 30일 지난 행은 client_errors_purge() 로 정리.
-- pg_cron 이 있으면 매일 06:30 KST(21:30 UTC)에 자동 정리. 없어도 함수는 수동 호출 가능.
-- STAGING ONLY (cuyqchmdcnsgzkwyclji). system_identifier 7703759698107299042.
-- =====================================================================
begin;
do $guard$
begin
  if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7703759698107299042' then
    raise exception 'STOP: this file is staging cuyqchmdcnsgzkwyclji only; production htarwisgkkphutxxnuak forbidden';
  end if;
end $guard$;

create table if not exists public.client_errors (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default clock_timestamp(),
  user_id uuid,
  rate_key text not null,
  message text not null check (char_length(message) between 1 and 400),
  stack text check (stack is null or char_length(stack) <= 1200),
  source text check (source is null or char_length(source) <= 80),
  url text check (url is null or char_length(url) <= 200),
  ua text check (ua is null or char_length(ua) <= 160),
  msg_hash text not null check (char_length(msg_hash) = 64)
);
create index if not exists client_errors_created_at on public.client_errors (created_at);
create index if not exists client_errors_rate on public.client_errors (rate_key, created_at);
create index if not exists client_errors_hash on public.client_errors (msg_hash, created_at desc);

alter table public.client_errors enable row level security;
revoke all on public.client_errors from public, anon, authenticated;
revoke all on sequence public.client_errors_id_seq from public, anon, authenticated;
grant all on public.client_errors to service_role;
grant all on sequence public.client_errors_id_seq to service_role;
drop policy if exists client_errors_no_direct on public.client_errors;

create or replace function public._client_error_rate_key()
returns text
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  h jsonb := '{}'::jsonb;
  ip text;
begin
  if auth.uid() is not null then
    return 'u:' || auth.uid()::text;
  end if;
  begin
    h := coalesce(nullif(current_setting('request.headers', true), '')::jsonb, '{}'::jsonb);
  exception when others then
    h := '{}'::jsonb;
  end;
  ip := coalesce(
    nullif(trim(h->>'cf-connecting-ip'), ''),
    nullif(trim(h->>'x-real-ip'), ''),
    nullif(trim(split_part(coalesce(h->>'x-forwarded-for', ''), ',', 1)), ''),
    nullif(host(inet_client_addr()), '')
  );
  if ip is null then
    return 'anon';
  end if;
  return 'h:' || encode(extensions.digest(convert_to('vr-err-v1|' || ip, 'utf8'), 'sha256'), 'hex');
end;
$$;

create or replace function public.client_error_report(
  p_message text,
  p_stack text default null,
  p_source text default null,
  p_url text default null,
  p_ua text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_msg text;
  v_stack text;
  v_source text;
  v_url text;
  v_ua text;
  v_key text;
  v_hash text;
  v_n int;
begin
  v_msg := left(btrim(coalesce(p_message, '')), 400);
  if v_msg = '' then
    return jsonb_build_object('ok', false, 'reason', 'empty');
  end if;
  v_stack := nullif(left(btrim(coalesce(p_stack, '')), 1200), '');
  v_source := nullif(left(btrim(coalesce(p_source, '')), 80), '');
  v_url := nullif(left(btrim(coalesce(p_url, '')), 200), '');
  v_ua := nullif(left(btrim(coalesce(p_ua, '')), 160), '');
  v_key := public._client_error_rate_key();

  select count(*) into v_n
    from public.client_errors
   where rate_key = v_key
     and created_at > clock_timestamp() - interval '1 minute';
  if v_n >= 8 then
    return jsonb_build_object('ok', false, 'limited', true);
  end if;

  select count(*) into v_n
    from public.client_errors
   where created_at > clock_timestamp() - interval '1 minute';
  if v_n >= 200 then
    return jsonb_build_object('ok', false, 'limited', true);
  end if;

  v_hash := encode(extensions.digest(convert_to(coalesce(v_source, '') || '|' || v_msg, 'utf8'), 'sha256'), 'hex');
  insert into public.client_errors (user_id, rate_key, message, stack, source, url, ua, msg_hash)
  values (auth.uid(), v_key, v_msg, v_stack, v_source, v_url, v_ua, v_hash);
  return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.client_errors_purge(p_limit int default 5000)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_lim int := greatest(1, least(coalesce(p_limit, 5000), 20000));
  v_n int := 0;
begin
  delete from public.client_errors
   where id in (
     select e.id
       from public.client_errors e
      where e.created_at < clock_timestamp() - interval '30 days'
      order by e.id
      limit v_lim
   );
  get diagnostics v_n = row_count;
  return jsonb_build_object('ok', true, 'deleted', v_n, 'keep_days', 30);
end;
$$;

create or replace function public.client_errors_install_ok()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  cron_on boolean := false;
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    begin
      execute $q$select exists (select 1 from cron.job where jobname = 'client_errors_purge')$q$ into cron_on;
    exception when others then
      cron_on := false;
    end;
  end if;
  return jsonb_build_object(
    'ok',
      to_regclass('public.client_errors') is not null
      and to_regprocedure('public.client_error_report(text,text,text,text,text)') is not null
      and to_regprocedure('public.client_errors_purge(integer)') is not null,
    'cron_on', cron_on
  );
end;
$$;

revoke all on function
  public._client_error_rate_key(),
  public.client_error_report(text, text, text, text, text),
  public.client_errors_purge(integer),
  public.client_errors_install_ok()
from public, anon, authenticated;

grant execute on function public.client_error_report(text, text, text, text, text) to anon, authenticated;
grant execute on function public.client_errors_purge(integer) to service_role;
grant execute on function public.client_errors_install_ok() to authenticated;

do $cron$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    begin
      perform cron.unschedule('client_errors_purge');
    exception when others then null;
    end;
    perform cron.schedule('client_errors_purge', '30 21 * * *', 'select public.client_errors_purge(5000)');
  else
    raise notice 'pg_cron 이 없음. 가끔 SQL Editor 에서 select public.client_errors_purge(5000); 를 실행하면 30일 지난 오류가 정리됩니다.';
  end if;
end $cron$;

notify pgrst, 'reload schema';
commit;
select public.client_errors_install_ok() as result;
