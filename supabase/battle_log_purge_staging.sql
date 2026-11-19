-- =====================================================================
-- 2026-11-19 전투 기록 정리 규칙. 함수만 설치하고 아무것도 지우지 않습니다.
-- 자동 삭제 스케줄은 이 파일에 없습니다. battle_log_purge_schedule_staging.sql 은
-- 형님이 승인한 뒤에만 따로 실행하세요.
--
-- 남기는 것 (화면의 도감·업적·랭킹·PvP 전적): battle_clear_receipts_v2,
-- battle_events_v2, battle_acquisitions_v2, arcade_records_v5, pvp_ratings_v3,
-- pvp_events_v3, pvp_attempts 행(승패·레이팅), matches, war 전적, story/tower 진행,
-- 결제·원장·가차 로그, 업적.
-- 정리 대상 (30일 지난 원본 페이로드·만료 세션·오래된 공지): 세션 jsonb,
-- pvp_attempts 스냅샷을 빈 객체로, global_notices 30일 초과 행 삭제,
-- 만료+30일이 지난 미정산 세션(자식 전적 없는 것만) 삭제.
-- STAGING ONLY (cuyqchmdcnsgzkwyclji). system_identifier 7703759698107299042.
-- =====================================================================
begin;
do $guard$
begin
  if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7703759698107299042' then
    raise exception 'STOP: this file is staging cuyqchmdcnsgzkwyclji only; production htarwisgkkphutxxnuak forbidden';
  end if;
end $guard$;

create or replace function public.battle_log_purge_dryrun()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  cut timestamptz := clock_timestamp() - interval '30 days';
  items jsonb := '{}'::jsonb;
  r bigint := 0;
  b bigint := 0;
  total_rows bigint := 0;
  total_bytes bigint := 0;
begin
  if to_regclass('public.battle_sessions_v2') is not null then
    select count(*), coalesce(sum(pg_column_size(s.snapshot) + pg_column_size(s.submission) + pg_column_size(s.settlement)), 0)
      into r, b
      from public.battle_sessions_v2 s
     where s.status in ('settled', 'expired', 'aborted')
       and coalesce(s.finished_at, s.issued_at) < cut
       and (s.snapshot is not null or s.submission is not null or s.settlement is not null);
    items := items || jsonb_build_object('battle_sessions_v2_payloads', jsonb_build_object('rows', r, 'bytes', b, 'action', 'null snapshot/submission/settlement'));
    total_rows := total_rows + r; total_bytes := total_bytes + b;
  end if;

  if to_regclass('public.arcade_sessions_v5') is not null then
    select count(*), coalesce(sum(pg_column_size(s.submission)), 0)
      into r, b
      from public.arcade_sessions_v5 s
     where s.status = 'settled' and s.created_at < cut and s.submission is not null;
    items := items || jsonb_build_object('arcade_sessions_v5_payloads', jsonb_build_object('rows', r, 'bytes', b, 'action', 'null submission (result kept)'));
    total_rows := total_rows + r; total_bytes := total_bytes + b;
  end if;

  if to_regclass('public.pvp_sessions_v3') is not null then
    select count(*), coalesce(sum(pg_column_size(s.submission)), 0)
      into r, b
      from public.pvp_sessions_v3 s
     where s.status = 'settled' and s.issued_at < cut and s.submission is not null;
    items := items || jsonb_build_object('pvp_sessions_v3_payloads', jsonb_build_object('rows', r, 'bytes', b, 'action', 'null submission (result kept)'));
    total_rows := total_rows + r; total_bytes := total_bytes + b;
  end if;

  if to_regclass('public.pvp_attempts') is not null then
    select count(*), coalesce(sum(pg_column_size(s.my_snap) + pg_column_size(s.opp_snap)), 0)
      into r, b
      from public.pvp_attempts s
     where s.created_at < cut
       and (coalesce(pg_column_size(s.my_snap), 0) + coalesce(pg_column_size(s.opp_snap), 0)) > 8;
    items := items || jsonb_build_object('pvp_attempts_snaps', jsonb_build_object('rows', r, 'bytes', b, 'action', 'replace my_snap/opp_snap with empty object (PvP history row kept)'));
    total_rows := total_rows + r; total_bytes := total_bytes + b;
  end if;

  if to_regclass('public.guildbattle_sessions_v4') is not null then
    select count(*), coalesce(sum(pg_column_size(s.payload) + pg_column_size(s.snapshot) + pg_column_size(s.submission)), 0)
      into r, b
      from public.guildbattle_sessions_v4 s
     where s.status = 'settled' and s.issued_at < cut
       and (coalesce(pg_column_size(s.payload), 0) + coalesce(pg_column_size(s.snapshot), 0) + coalesce(pg_column_size(s.submission), 0)) > 8;
    items := items || jsonb_build_object('guildbattle_sessions_v4_payloads', jsonb_build_object('rows', r, 'bytes', b, 'action', 'replace payload/snapshot/submission with empty (result kept)'));
    total_rows := total_rows + r; total_bytes := total_bytes + b;
  end if;

  if to_regclass('public.global_notices') is not null then
    select count(*), coalesce(sum(pg_column_size(n)), 0)
      into r, b
      from public.global_notices n
     where n.created_at < cut;
    items := items || jsonb_build_object('global_notices_old', jsonb_build_object('rows', r, 'bytes', b, 'action', 'delete rows older than 30 days (list already hides after 3 days)'));
    total_rows := total_rows + r; total_bytes := total_bytes + b;
  end if;

  if to_regclass('public.battle_sessions_v2') is not null then
    select count(*), coalesce(sum(pg_column_size(s)), 0)
      into r, b
      from public.battle_sessions_v2 s
     where s.status = 'issued' and s.expires_at < cut
       and (to_regclass('public.battle_clear_receipts_v2') is null or not exists (select 1 from public.battle_clear_receipts_v2 x where x.session_id = s.id))
       and (to_regclass('public.battle_events_v2') is null or not exists (select 1 from public.battle_events_v2 x where x.session_id = s.id))
       and (to_regclass('public.battle_acquisitions_v2') is null or not exists (select 1 from public.battle_acquisitions_v2 x where x.session_id = s.id));
    items := items || jsonb_build_object('battle_sessions_v2_expired_issued', jsonb_build_object('rows', r, 'bytes', b, 'action', 'delete abandoned issued sessions'));
    total_rows := total_rows + r; total_bytes := total_bytes + b;
  end if;

  if to_regclass('public.arcade_sessions_v5') is not null then
    select count(*), coalesce(sum(pg_column_size(s)), 0)
      into r, b
      from public.arcade_sessions_v5 s
     where s.status = 'active' and s.expires_at < cut
       and (to_regclass('public.arcade_records_v5') is null or not exists (select 1 from public.arcade_records_v5 x where x.session_id = s.id));
    items := items || jsonb_build_object('arcade_sessions_v5_expired_active', jsonb_build_object('rows', r, 'bytes', b, 'action', 'delete abandoned active sessions'));
    total_rows := total_rows + r; total_bytes := total_bytes + b;
  end if;

  if to_regclass('public.pvp_sessions_v3') is not null then
    select count(*), coalesce(sum(pg_column_size(s)), 0)
      into r, b
      from public.pvp_sessions_v3 s
     where s.status = 'issued' and s.expires_at < cut
       and (to_regclass('public.pvp_events_v3') is null or not exists (select 1 from public.pvp_events_v3 x where x.session_id = s.id));
    items := items || jsonb_build_object('pvp_sessions_v3_expired_issued', jsonb_build_object('rows', r, 'bytes', b, 'action', 'delete abandoned issued sessions'));
    total_rows := total_rows + r; total_bytes := total_bytes + b;
  end if;

  if to_regclass('public.guildbattle_sessions_v4') is not null then
    select count(*), coalesce(sum(pg_column_size(s)), 0)
      into r, b
      from public.guildbattle_sessions_v4 s
     where s.status = 'issued' and s.expires_at < cut
       and (to_regclass('public.guildbattle_events_v4') is null or not exists (select 1 from public.guildbattle_events_v4 x where x.session_id = s.id));
    items := items || jsonb_build_object('guildbattle_sessions_v4_expired_issued', jsonb_build_object('rows', r, 'bytes', b, 'action', 'delete abandoned issued sessions'));
    total_rows := total_rows + r; total_bytes := total_bytes + b;
  end if;

  return jsonb_build_object(
    'ok', true,
    'deleted_nothing', true,
    'keep_days', 30,
    'cut_before', cut,
    'total_rows', total_rows,
    'total_bytes', total_bytes,
    'total_pretty', pg_size_pretty(total_bytes),
    'items', items,
    'kept', jsonb_build_array(
      'battle_clear_receipts_v2',
      'battle_events_v2',
      'battle_acquisitions_v2',
      'arcade_records_v5',
      'pvp_ratings_v3',
      'pvp_events_v3',
      'pvp_attempts rows (snaps cleared only)',
      'matches',
      'story/tower progress',
      'gallery / achievements',
      'payments / ledgers / gacha logs',
      'war / raid standing tables'
    ),
    'note', '이 결과는 미리보기입니다. 아무것도 지우지 않았습니다. 실제 정리는 형님 승인 후 battle_log_purge_run_staging.sql 만 실행하세요.'
  );
end;
$$;

create or replace function public.battle_log_purge(p_confirm text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  cut timestamptz := clock_timestamp() - interval '30 days';
  done jsonb := '{}'::jsonb;
  n int := 0;
begin
  if p_confirm is distinct from 'PURGE' then
    raise exception 'refused: 형님 승인 후 p_confirm := ''PURGE'' 로만 실행하세요. 먼저 battle_log_purge_dryrun() 을 보세요.'
      using errcode = '42501';
  end if;

  if to_regclass('public.battle_sessions_v2') is not null then
    update public.battle_sessions_v2 s
       set snapshot = null, submission = null, settlement = null
     where s.status in ('settled', 'expired', 'aborted')
       and coalesce(s.finished_at, s.issued_at) < cut
       and (s.snapshot is not null or s.submission is not null or s.settlement is not null);
    get diagnostics n = row_count;
    done := done || jsonb_build_object('battle_sessions_v2_payloads', n);
  end if;

  if to_regclass('public.arcade_sessions_v5') is not null then
    update public.arcade_sessions_v5 s
       set submission = null
     where s.status = 'settled' and s.created_at < cut and s.submission is not null;
    get diagnostics n = row_count;
    done := done || jsonb_build_object('arcade_sessions_v5_payloads', n);
  end if;

  if to_regclass('public.pvp_sessions_v3') is not null then
    update public.pvp_sessions_v3 s
       set submission = null
     where s.status = 'settled' and s.issued_at < cut and s.submission is not null;
    get diagnostics n = row_count;
    done := done || jsonb_build_object('pvp_sessions_v3_payloads', n);
  end if;

  if to_regclass('public.pvp_attempts') is not null then
    update public.pvp_attempts s
       set my_snap = '{}'::jsonb, opp_snap = '{}'::jsonb
     where s.created_at < cut
       and (coalesce(pg_column_size(s.my_snap), 0) + coalesce(pg_column_size(s.opp_snap), 0)) > 8;
    get diagnostics n = row_count;
    done := done || jsonb_build_object('pvp_attempts_snaps', n);
  end if;

  if to_regclass('public.guildbattle_sessions_v4') is not null then
    update public.guildbattle_sessions_v4 s
       set payload = '{}'::jsonb, snapshot = '{}'::jsonb, submission = null
     where s.status = 'settled' and s.issued_at < cut
       and (coalesce(pg_column_size(s.payload), 0) + coalesce(pg_column_size(s.snapshot), 0) + coalesce(pg_column_size(s.submission), 0)) > 8;
    get diagnostics n = row_count;
    done := done || jsonb_build_object('guildbattle_sessions_v4_payloads', n);
  end if;

  if to_regclass('public.global_notices') is not null then
    delete from public.global_notices n where n.created_at < cut;
    get diagnostics n = row_count;
    done := done || jsonb_build_object('global_notices_old', n);
  end if;

  if to_regclass('public.battle_sessions_v2') is not null then
    delete from public.battle_sessions_v2 s
     where s.status = 'issued' and s.expires_at < cut
       and (to_regclass('public.battle_clear_receipts_v2') is null or not exists (select 1 from public.battle_clear_receipts_v2 x where x.session_id = s.id))
       and (to_regclass('public.battle_events_v2') is null or not exists (select 1 from public.battle_events_v2 x where x.session_id = s.id))
       and (to_regclass('public.battle_acquisitions_v2') is null or not exists (select 1 from public.battle_acquisitions_v2 x where x.session_id = s.id));
    get diagnostics n = row_count;
    done := done || jsonb_build_object('battle_sessions_v2_expired_issued', n);
  end if;

  if to_regclass('public.arcade_sessions_v5') is not null then
    delete from public.arcade_sessions_v5 s
     where s.status = 'active' and s.expires_at < cut
       and (to_regclass('public.arcade_records_v5') is null or not exists (select 1 from public.arcade_records_v5 x where x.session_id = s.id));
    get diagnostics n = row_count;
    done := done || jsonb_build_object('arcade_sessions_v5_expired_active', n);
  end if;

  if to_regclass('public.pvp_sessions_v3') is not null then
    delete from public.pvp_sessions_v3 s
     where s.status = 'issued' and s.expires_at < cut
       and (to_regclass('public.pvp_events_v3') is null or not exists (select 1 from public.pvp_events_v3 x where x.session_id = s.id));
    get diagnostics n = row_count;
    done := done || jsonb_build_object('pvp_sessions_v3_expired_issued', n);
  end if;

  if to_regclass('public.guildbattle_sessions_v4') is not null then
    delete from public.guildbattle_sessions_v4 s
     where s.status = 'issued' and s.expires_at < cut
       and (to_regclass('public.guildbattle_events_v4') is null or not exists (select 1 from public.guildbattle_events_v4 x where x.session_id = s.id));
    get diagnostics n = row_count;
    done := done || jsonb_build_object('guildbattle_sessions_v4_expired_issued', n);
  end if;

  return jsonb_build_object('ok', true, 'keep_days', 30, 'cut_before', cut, 'done', done);
end;
$$;

create or replace function public.battle_log_purge_install_ok()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select jsonb_build_object(
    'ok',
      to_regprocedure('public.battle_log_purge_dryrun()') is not null
      and to_regprocedure('public.battle_log_purge(text)') is not null,
    'auto_schedule', false
  );
$$;

revoke all on function
  public.battle_log_purge_dryrun(),
  public.battle_log_purge(text),
  public.battle_log_purge_install_ok()
from public, anon, authenticated;

grant execute on function public.battle_log_purge_install_ok() to authenticated;
-- purge / dryrun 은 SQL Editor(역할 postgres)에서만 실행. 클라이언트 권한 없음.

notify pgrst, 'reload schema';
commit;
select public.battle_log_purge_install_ok() as result;
