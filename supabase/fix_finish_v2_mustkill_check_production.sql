-- 읽기만 함. production 전용. fix_finish_v2_mustkill_production.sql 실행 후 한 줄 확인. 기대: ok=true
select (
  (select system_identifier::text from pg_catalog.pg_control_system()) = '7692130048193495360'
  and exists (select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname in ('battle_session_finish_v2', '_phase7_prev_finish_v2', '_phase6_old_finish_v2')
      and p.prosrc like '%implausible end reason%')
  and not exists (select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname in ('battle_session_finish_v2', '_phase7_prev_finish_v2', '_phase6_old_finish_v2')
      and p.prosrc like '%implausible end reason%' and p.prosrc not like '%(reason_=''mustkill'' and (not win_%')
) as ok;
