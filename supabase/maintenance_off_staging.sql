-- 점검 끄기. STAGING ONLY (7703759698107299042). 안내 문구는 그대로 두고 끄기만 함.
begin;
do $guard$
begin
  if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7703759698107299042' then
    raise exception 'STOP: maintenance off is staging cuyqchmdcnsgzkwyclji only; production forbidden';
  end if;
  if to_regclass('public.maintenance') is null then
    raise exception 'STOP: 먼저 maintenance_staging.sql 을 실행하세요';
  end if;
end $guard$;
update public.maintenance
   set is_on = false,
       updated_at = clock_timestamp()
 where id = 1;
commit;
select is_on, message, ends_at from public.maintenance where id = 1;
