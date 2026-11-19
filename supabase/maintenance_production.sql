-- =====================================================================
-- 2026-11-19 점검 모드. 한 줄짜리 플래그 + 안내 문구 + 선택 종료 시각.
-- 클라이언트는 maintenance_status() 만 읽음 (익명 가능). 새 폴링 없음.
-- 여러 번 실행해도 안전. 아직 실행하지 마세요. PRODUCTION ONLY (htarwisgkkphutxxnuak). system_identifier 7692130048193495360.
-- 켜고 끄기는 maintenance_on_production.sql / maintenance_off_production.sql. 아직 실행하지 마세요.
-- =====================================================================
begin;
do $guard$
begin
  if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7692130048193495360' then
    raise exception 'STOP: maintenance is production htarwisgkkphutxxnuak only; staging forbidden';
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
insert into public.maintenance (id, is_on, message)
values (1, false, '지금은 점검 중이에요. 잠시 후 다시 와 주세요.')
on conflict (id) do nothing;

alter table public.maintenance enable row level security;
revoke all on public.maintenance from public, anon, authenticated;
grant select on public.maintenance to anon, authenticated;
grant all on public.maintenance to service_role;
drop policy if exists maintenance_read on public.maintenance;
create policy maintenance_read on public.maintenance for select to anon, authenticated using (true);

create or replace function public.maintenance_status()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select jsonb_build_object(
    'on', coalesce(m.is_on, false) and (m.ends_at is null or m.ends_at > clock_timestamp()),
    'message', coalesce(nullif(trim(m.message), ''), '지금은 점검 중이에요. 잠시 후 다시 와 주세요.'),
    'ends_at', m.ends_at
  )
  from (select 1) z
  left join public.maintenance m on m.id = 1;
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
      and exists (select 1 from public.maintenance where id = 1),
    'is_on', coalesce((select is_on and (ends_at is null or ends_at > clock_timestamp()) from public.maintenance where id = 1), false)
  );
$$;

revoke all on function public.maintenance_status(), public.maintenance_install_ok() from public;
grant execute on function public.maintenance_status(), public.maintenance_install_ok() to anon, authenticated;

notify pgrst, 'reload schema';
commit;
select public.maintenance_install_ok() as result;
