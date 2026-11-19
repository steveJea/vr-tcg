-- =====================================================================
-- 스테이징 보강: 곧 오픈 제목/종류(kind) + 허용 이메일(allow_emails).
-- 오늘 이미 실행한 maintenance_staging.sql / maintenance_admin_staging.sql 위에 이어서 실행합니다.
-- 이 파일만으로는 켜지지 않습니다. STAGING ONLY (cuyqchmdcnsgzkwyclji). system_identifier 7703759698107299042.
-- =====================================================================
begin;
do $guard$
begin
  if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7703759698107299042' then
    raise exception 'STOP: this file is staging cuyqchmdcnsgzkwyclji only; production/unknown DB refused';
  end if;
  if to_regclass('public.maintenance') is null then
    raise exception 'STOP: 먼저 maintenance_staging.sql 을 실행하세요';
  end if;
end $guard$;

alter table public.maintenance add column if not exists title text not null default ''
  check (char_length(title) <= 80);
alter table public.maintenance add column if not exists kind text not null default 'maintenance'
  check (kind in ('maintenance', 'coming_soon'));
alter table public.maintenance add column if not exists allow_emails text[] not null default '{}'::text[];

revoke all on public.maintenance from public, anon, authenticated;
grant select (id, is_on, message, ends_at, updated_at, title, kind) on public.maintenance to anon, authenticated;
grant all on public.maintenance to service_role;

create or replace function public.maintenance_status()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  m public.maintenance;
  v_email text;
  v_allowed boolean := false;
  v_on boolean;
begin
  select * into m from public.maintenance where id = 1;
  if not found then
    return jsonb_build_object('on', false, 'message', '지금은 점검 중이에요. 잠시 후 다시 와 주세요.', 'ends_at', null, 'title', '', 'kind', 'maintenance', 'allowed', false);
  end if;
  v_on := m.is_on and (m.ends_at is null or m.ends_at > clock_timestamp());
  v_email := lower(btrim(coalesce(auth.jwt()->>'email', '')));
  if v_email <> '' then
    if exists (select 1 from unnest(coalesce(m.allow_emails, '{}'::text[])) e where lower(btrim(e)) = v_email) then
      v_allowed := true;
    elsif to_regprocedure('public._is_admin()') is not null and public._is_admin() then
      v_allowed := true;
    end if;
  end if;
  return jsonb_build_object(
    'on', v_on,
    'message', coalesce(nullif(trim(m.message), ''), '지금은 점검 중이에요. 잠시 후 다시 와 주세요.'),
    'ends_at', m.ends_at,
    'title', coalesce(m.title, ''),
    'kind', coalesce(nullif(m.kind, ''), 'maintenance'),
    'allowed', v_allowed
  );
end;
$$;

create or replace function public.maintenance_install_ok()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select jsonb_build_object(
    'ok',
      to_regclass('public.maintenance') is not null
      and to_regprocedure('public.maintenance_status()') is not null
      and exists (select 1 from public.maintenance where id = 1)
      and exists (select 1 from information_schema.columns where table_schema='public' and table_name='maintenance' and column_name='allow_emails')
      and exists (select 1 from information_schema.columns where table_schema='public' and table_name='maintenance' and column_name='kind')
      and exists (select 1 from information_schema.columns where table_schema='public' and table_name='maintenance' and column_name='title'),
    'is_on', coalesce((select is_on and (ends_at is null or ends_at > clock_timestamp()) from public.maintenance where id = 1), false),
    'kind', coalesce((select kind from public.maintenance where id = 1), 'maintenance'),
    'title', coalesce((select title from public.maintenance where id = 1), ''),
    'message', coalesce((select message from public.maintenance where id = 1), ''),
    'allow_count', coalesce((select cardinality(allow_emails) from public.maintenance where id = 1), 0)
  );
$$;

revoke all on function public.maintenance_status(), public.maintenance_install_ok() from public;
grant execute on function public.maintenance_status(), public.maintenance_install_ok() to anon, authenticated;

-- admin RPCs (있으면 시그니처를 새 것으로 교체, 없으면 여기서 만듦)
do $need_admin$
begin
  if to_regprocedure('public._admin_guard()') is null then
    raise exception 'STOP: public._admin_guard() 가 필요합니다. 관리자 점검 탭을 쓰려면 기존 admin SQL 이 있어야 합니다.';
  end if;
end $need_admin$;

create or replace function public.maintenance_admin_get()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  m public.maintenance;
begin
  perform public._admin_guard();
  select * into m from public.maintenance where id = 1;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'missing');
  end if;
  return jsonb_build_object(
    'ok', true,
    'is_on', m.is_on,
    'on', m.is_on and (m.ends_at is null or m.ends_at > clock_timestamp()),
    'message', m.message,
    'ends_at', m.ends_at,
    'updated_at', m.updated_at,
    'title', coalesce(m.title, ''),
    'kind', coalesce(m.kind, 'maintenance'),
    'allow_emails', coalesce(m.allow_emails, '{}'::text[])
  );
end;
$$;

drop function if exists public.maintenance_admin_set(boolean, text, timestamptz);

create or replace function public.maintenance_admin_set(
  p_is_on boolean,
  p_message text,
  p_ends_at timestamptz default null,
  p_title text default null,
  p_kind text default null,
  p_allow_emails text[] default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  v_msg text;
  v_title text;
  v_kind text;
  v_emails text[];
  v_before boolean;
  v_email text;
begin
  perform public._admin_guard();
  if p_is_on is null then
    raise exception 'invalid is_on';
  end if;
  v_msg := nullif(btrim(coalesce(p_message, '')), '');
  if v_msg is null or char_length(v_msg) > 300 then
    raise exception 'invalid message';
  end if;
  v_title := btrim(coalesce(p_title, ''));
  if char_length(v_title) > 80 then
    raise exception 'invalid title';
  end if;
  v_kind := lower(btrim(coalesce(nullif(p_kind, ''), 'maintenance')));
  if v_kind not in ('maintenance', 'coming_soon') then
    raise exception 'invalid kind';
  end if;
  if p_allow_emails is null then
    select allow_emails into v_emails from public.maintenance where id = 1;
    v_emails := coalesce(v_emails, '{}'::text[]);
  else
    v_emails := '{}'::text[];
    if cardinality(p_allow_emails) > 30 then
      raise exception 'invalid allow_emails';
    end if;
    foreach v_email in array coalesce(p_allow_emails, '{}'::text[]) loop
      v_email := lower(btrim(coalesce(v_email, '')));
      if v_email = '' then
        continue;
      end if;
      if char_length(v_email) > 200 or v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or v_email = any(v_emails) then
        raise exception 'invalid allow_emails';
      end if;
      v_emails := array_append(v_emails, v_email);
    end loop;
  end if;
  select is_on into v_before from public.maintenance where id = 1;
  update public.maintenance
     set is_on = p_is_on,
         message = v_msg,
         ends_at = p_ends_at,
         title = v_title,
         kind = v_kind,
         allow_emails = v_emails,
         updated_at = clock_timestamp()
   where id = 1;
  begin
    insert into public.admin_log (admin_id, admin_email, action, amount, reason, before_val, after_val)
    values (
      auth.uid(),
      auth.jwt()->>'email',
      'maintenance_set',
      case when p_is_on then 1 else 0 end,
      left(v_kind || ': ' || v_msg, 200),
      case when v_before then 1 else 0 end,
      case when p_is_on then 1 else 0 end
    );
  exception when others then
    null;
  end;
  return public.maintenance_admin_get();
end;
$$;

create or replace function public.maintenance_admin_install_ok()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select jsonb_build_object(
    'ok',
      to_regclass('public.maintenance') is not null
      and to_regprocedure('public.maintenance_admin_get()') is not null
      and to_regprocedure('public.maintenance_admin_set(boolean,text,timestamptz,text,text,text[])') is not null
      and has_function_privilege('authenticated', 'public.maintenance_admin_get()', 'EXECUTE')
      and has_function_privilege('authenticated', 'public.maintenance_admin_set(boolean,text,timestamptz,text,text,text[])', 'EXECUTE')
      and not has_function_privilege('anon', 'public.maintenance_admin_get()', 'EXECUTE')
      and not has_function_privilege('anon', 'public.maintenance_admin_set(boolean,text,timestamptz,text,text,text[])', 'EXECUTE'),
    'is_on', coalesce((select is_on and (ends_at is null or ends_at > clock_timestamp()) from public.maintenance where id = 1), false)
  );
$$;

revoke all on function
  public.maintenance_admin_get(),
  public.maintenance_admin_set(boolean, text, timestamptz, text, text, text[]),
  public.maintenance_admin_install_ok()
from public, anon, authenticated;

grant execute on function
  public.maintenance_admin_get(),
  public.maintenance_admin_set(boolean, text, timestamptz, text, text, text[])
to authenticated;

grant execute on function public.maintenance_admin_install_ok() to authenticated;

notify pgrst, 'reload schema';
commit;
select public.maintenance_install_ok() as status, public.maintenance_admin_install_ok() as admin;
