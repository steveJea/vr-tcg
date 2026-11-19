-- 읽기만 함. production 전용. 적용 후 한 줄 확인. 기대: ok=true
select (
  (select system_identifier::text from pg_catalog.pg_control_system()) = '7692130048193495360'
  and (select pickup_id from public.special_banners where id='hajihye-20261113') = '10440'
  and (select ends_at from public.special_banners where id='hajihye-20261113') = '2026-11-30 23:59:59+09'
) as ok;
