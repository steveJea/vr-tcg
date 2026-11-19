-- 점검 끄기. 아직 실행하지 마세요. PRODUCTION ONLY (7692130048193495360). 안내 문구는 그대로 두고 끄기만 함.
begin;
do $guard$
begin
  if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7692130048193495360' then
    raise exception 'STOP: maintenance off is production htarwisgkkphutxxnuak only; staging forbidden';
  end if;
  if to_regclass('public.maintenance') is null then
    raise exception 'STOP: 먼저 maintenance_production.sql 을 실행하세요';
  end if;
end $guard$;
update public.maintenance
   set is_on = false,
       updated_at = clock_timestamp()
 where id = 1;
commit;
select is_on, message, ends_at from public.maintenance where id = 1;
