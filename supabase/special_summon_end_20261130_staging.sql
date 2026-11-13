-- STAGING ONLY (cuyqchmdcnsgzkwyclji). 하지혜(10440) 스페셜 픽업 종료일 → 2026-11-30 23:59:59 KST. 그 배너 한 줄만 바꿈 (확률·천장·기록 그대로). 다시 돌려도 같음.
do $end$
begin
 if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7703759698107299042' then
  raise exception 'STOP: staging cuyqchmdcnsgzkwyclji only'; end if;
 if to_regclass('public.special_banners') is null then raise exception 'STOP: special_banners missing (run special_summon_staging.sql first)'; end if;
 update public.special_banners set ends_at='2026-11-30 23:59:59+09' where id='hajihye-20261113';
 if not found then raise exception 'STOP: banner hajihye-20261113 not found'; end if;
end $end$;
select id, pickup_id, starts_at at time zone 'Asia/Seoul' as starts_kst, ends_at at time zone 'Asia/Seoul' as ends_kst, active from public.special_banners where id='hajihye-20261113';
