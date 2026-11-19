-- 곧 오픈/점검 끄기 (오픈할 때). PRODUCTION ONLY (7692130048193495360).
-- 안내 문구·종류·허용 이메일은 그대로 두고 끄기만 합니다. 관리자 점검 탭의 끄기와 같습니다.
begin;
do $guard$
begin
  if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7692130048193495360' then
    raise exception 'STOP: maintenance off is production htarwisgkkphutxxnuak only; staging/unknown DB refused';
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
select is_on, kind, title, message, ends_at, cardinality(allow_emails) as allow_count
  from public.maintenance where id = 1;
