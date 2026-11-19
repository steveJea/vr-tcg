-- =====================================================================
-- 2026-11-19 점검/곧 오픈 모드. 한 줄짜리 플래그 + 안내 문구 + 선택 종료 시각
-- + 제목/종류(kind) + 허용 이메일 목록(allow_emails, 기본 빈 목록).
-- 클라이언트는 maintenance_status() 만 읽음 (익명 가능). 새 폴링 없음.
-- SQL이 아직 없으면 클라이언트는 조용히 통과합니다. 이 파일만 실행하면 꺼진 상태입니다.
-- PRODUCTION ONLY (htarwisgkkphutxxnuak). system_identifier 7692130048193495360.
-- 켜기는 maintenance_on_production.sql (클라이언트 배포 후에만). 끄기는 maintenance_off_production.sql.
-- 여러 번 실행해도 안전합니다. 이 파일을 실행해도 유저 데이터는 바꾸지 않습니다.
-- =====================================================================
begin;
do $guard$
begin
  if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7692130048193495360' then
    raise exception 'STOP: maintenance is production htarwisgkkphutxxnuak only; staging/unknown DB refused';
  end if;
end $guard$;

create table if not exists public.maintenance (
  id int primary key check (id = 1),
  is_on boolean not null default false,
  message text not null default '지금은 점검 중이에요. 잠시 후 다시 와 주세요.'
    check (char_length(trim(message)) between 1 and 300),
  ends_at timestamptz,
  updated_at timestamptz not null default clock_timestamp()
);
alter table public.maintenance add column if not exists title text not null default ''
  check (char_length(title) <= 80);
alter table public.maintenance add column if not exists kind text not null default 'maintenance'
  check (kind in ('maintenance', 'coming_soon'));
alter table public.maintenance add column if not exists allow_emails text[] not null default '{}'::text[];

insert into public.maintenance (id, is_on, message, kind, title, allow_emails)
values (1, false, '지금은 점검 중이에요. 잠시 후 다시 와 주세요.', 'maintenance', '', '{}'::text[])
on conflict (id) do nothing;

alter table public.maintenance enable row level security;
revoke all on public.maintenance from public, anon, authenticated;
grant select (id, is_on, message, ends_at, updated_at, title, kind) on public.maintenance to anon, authenticated;
grant all on public.maintenance to service_role;
drop policy if exists maintenance_read on public.maintenance;
create policy maintenance_read on public.maintenance for select to anon, authenticated using (true);

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
      and exists (
        select 1 from information_schema.columns
         where table_schema='public' and table_name='maintenance' and column_name='allow_emails'
      )
      and exists (
        select 1 from information_schema.columns
         where table_schema='public' and table_name='maintenance' and column_name='kind'
      )
      and exists (
        select 1 from information_schema.columns
         where table_schema='public' and table_name='maintenance' and column_name='title'
      ),
    'is_on', coalesce((select is_on and (ends_at is null or ends_at > clock_timestamp()) from public.maintenance where id = 1), false),
    'kind', coalesce((select kind from public.maintenance where id = 1), 'maintenance'),
    'title', coalesce((select title from public.maintenance where id = 1), ''),
    'message', coalesce((select message from public.maintenance where id = 1), ''),
    'allow_count', coalesce((select cardinality(allow_emails) from public.maintenance where id = 1), 0)
  );
$$;

revoke all on function public.maintenance_status(), public.maintenance_install_ok() from public;
grant execute on function public.maintenance_status(), public.maintenance_install_ok() to anon, authenticated;

notify pgrst, 'reload schema';
commit;
select public.maintenance_install_ok() as result;
