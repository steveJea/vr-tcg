-- 곧 오픈 켜기. PRODUCTION ONLY (7692130048193495360).
-- 클라이언트(Worker + tcg.mbbs.kr GitHub Pages)가 먼저 배포된 뒤에만 실행하세요.
-- 허용 이메일 목록은 바꾸지 않습니다(빈 목록 유지, 관리자는 _is_admin 으로 통과).
-- 오픈할 때는 관리자 → 점검 탭에서 끄거나, maintenance_off_production.sql 을 실행하세요.
begin;
do $guard$
begin
  if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7692130048193495360' then
    raise exception 'STOP: maintenance on is production htarwisgkkphutxxnuak only; staging/unknown DB refused';
  end if;
  if to_regclass('public.maintenance') is null
     or not exists (select 1 from information_schema.columns where table_schema='public' and table_name='maintenance' and column_name='kind') then
    raise exception 'STOP: 먼저 maintenance_production.sql 을 실행하세요';
  end if;
end $guard$;
update public.maintenance
   set is_on = true,
       kind = 'coming_soon',
       title = '곧 오픈 / COMING SOON',
       message = 'Violence Royale : The Abyss Gate 곧 오픈합니다',
       ends_at = null,
       updated_at = clock_timestamp()
 where id = 1;
commit;
select is_on, kind, title, message, ends_at, cardinality(allow_emails) as allow_count
  from public.maintenance where id = 1;
