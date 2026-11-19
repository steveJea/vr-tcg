-- =====================================================================
-- 2026-11-19 관리자 점검/곧 오픈 켜기·끄기 RPC. 기존 maintenance 표를 쓰며,
-- admin_check / _admin_guard (stevejean77@gmail.com) 로만 변경할 수 있습니다.
-- 일반 유저·익명은 실행할 수 없음. 허용 이메일은 관리자가 나중에 추가할 수 있습니다(지금은 빈 목록).
-- 먼저 maintenance_production.sql 이 있어야 합니다.
-- PRODUCTION ONLY (htarwisgkkphutxxnuak). system_identifier 7692130048193495360.
-- 클라이언트 배포 후에 실행하세요. 이 파일만으로는 켜지지 않습니다.
-- =====================================================================
begin;
do $guard$
begin
  if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7692130048193495360' then
    raise exception 'STOP: this file is production htarwisgkkphutxxnuak only; staging/unknown DB refused';
  end if;
  if to_regclass('public.maintenance') is null
     or not exists (select 1 from information_schema.columns where table_schema='public' and table_name='maintenance' and column_name='allow_emails') then
    raise exception 'STOP: 먼저 maintenance_production.sql 을 실행하세요';
  end if;
  if to_regprocedure('public._admin_guard()') is null or to_regprocedure('public._is_admin()') is null then
    raise exception 'STOP: public._admin_guard() / _is_admin() 가 필요합니다 (supabase/admin.sql)';
  end if;
end $guard$;

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
select public.maintenance_admin_install_ok() as result;
