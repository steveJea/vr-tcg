-- PRODUCTION ONLY (htarwisgkkphutxxnuak). 하지혜(10440) 스페셜 픽업 종료일 → 2026-11-30 23:59:59 KST.
-- 그 배너 한 줄만 바꿈 (확률·천장·기록 그대로). 다시 돌려도 같음.
do $end$
begin
  if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7692130048193495360' then
    raise exception 'STOP: special summon end is production htarwisgkkphutxxnuak only; staging forbidden';
  end if;
  if to_regclass('public.special_banners') is null then
    raise exception 'STOP: special_banners missing (run special_summon_production.sql first)';
  end if;
  update public.special_banners set ends_at='2026-11-30 23:59:59+09' where id='hajihye-20261113';
  if not found then raise exception 'STOP: banner hajihye-20261113 not found'; end if;
end $end$;
