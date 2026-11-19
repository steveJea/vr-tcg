-- 점검 켜기. 아직 실행하지 마세요. PRODUCTION ONLY (7692130048193495360). 메시지·종료 시각을 고친 뒤 실행.
-- ends_at 를 null 로 두면 종료 시각 없이 계속 켜짐. 지났으면 클라이언트가 자동으로 꺼진 것으로 봄.
begin;
do $guard$
begin
  if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7692130048193495360' then
    raise exception 'STOP: maintenance on is production htarwisgkkphutxxnuak only; staging forbidden';
  end if;
  if to_regclass('public.maintenance') is null then
    raise exception 'STOP: 먼저 maintenance_production.sql 을 실행하세요';
  end if;
end $guard$;
update public.maintenance
   set is_on = true,
       message = '지금은 점검 중이에요. 잠시 후 다시 와 주세요.',
       ends_at = null,
       updated_at = clock_timestamp()
 where id = 1;
commit;
select is_on, message, ends_at from public.maintenance where id = 1;
