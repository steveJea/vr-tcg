-- =====================================================================
-- 2026-11-19 자주 쓰이는 필터용 인덱스. CREATE INDEX IF NOT EXISTS 만 사용.
-- 가드 트랜잭션 안에서는 CREATE INDEX CONCURRENTLY 를 쓸 수 없어 일반 인덱스로 만듭니다.
-- 표가 아주 크면 잠깐 잠길 수 있어요. 그때는 이 파일을 실행하지 말고, 아래 이름을
-- CREATE INDEX CONCURRENTLY IF NOT EXISTS 로 따로 실행하세요 (트랜잭션 밖에서).
-- 표가 없으면 해당 인덱스는 건너뜁니다.
-- STAGING ONLY (cuyqchmdcnsgzkwyclji). system_identifier 7703759698107299042.
-- =====================================================================
begin;
do $guard$
begin
  if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7703759698107299042' then
    raise exception 'STOP: this file is staging cuyqchmdcnsgzkwyclji only; production htarwisgkkphutxxnuak forbidden';
  end if;
end $guard$;

-- 만료된 issued/active 세션을 빠르게 찾기 (발급·정리·시작 RPC).
do $idx$
begin
  if to_regclass('public.battle_sessions_v2') is not null then
    execute 'create index if not exists battle_sessions_v2_expire on public.battle_sessions_v2 (expires_at) where status = ''issued''';
  end if;
  if to_regclass('public.arcade_sessions_v5') is not null then
    execute 'create index if not exists arcade_sessions_v5_expire on public.arcade_sessions_v5 (expires_at) where status = ''active''';
  end if;
  if to_regclass('public.pvp_sessions_v3') is not null then
    execute 'create index if not exists pvp_sessions_v3_expire on public.pvp_sessions_v3 (expires_at) where status = ''issued''';
  end if;
  if to_regclass('public.guildbattle_sessions_v4') is not null then
    execute 'create index if not exists guildbattle_sessions_v4_pending on public.guildbattle_sessions_v4 (user_id, kind, status)';
    execute 'create index if not exists guildbattle_sessions_v4_expire on public.guildbattle_sessions_v4 (expires_at) where status = ''issued''';
  end if;
  -- PvP 시작 시 같은 리그·모드 2초 제한, 최근 시도 조회.
  if to_regclass('public.pvp_attempts') is not null then
    execute 'create index if not exists pvp_attempts_user_recent on public.pvp_attempts (user_id, league, mode, created_at desc)';
  end if;
end $idx$;

create or replace function public.index_hot_filters_install_ok()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select jsonb_build_object(
    'ok',
      (to_regclass('public.battle_sessions_v2') is null or to_regclass('public.battle_sessions_v2_expire') is not null)
      and (to_regclass('public.arcade_sessions_v5') is null or to_regclass('public.arcade_sessions_v5_expire') is not null)
      and (to_regclass('public.pvp_sessions_v3') is null or to_regclass('public.pvp_sessions_v3_expire') is not null)
      and (to_regclass('public.guildbattle_sessions_v4') is null or (
        to_regclass('public.guildbattle_sessions_v4_pending') is not null
        and to_regclass('public.guildbattle_sessions_v4_expire') is not null
      ))
      and (to_regclass('public.pvp_attempts') is null or to_regclass('public.pvp_attempts_user_recent') is not null),
    'indexes', jsonb_build_object(
      'battle_sessions_v2_expire', to_regclass('public.battle_sessions_v2_expire') is not null,
      'arcade_sessions_v5_expire', to_regclass('public.arcade_sessions_v5_expire') is not null,
      'pvp_sessions_v3_expire', to_regclass('public.pvp_sessions_v3_expire') is not null,
      'guildbattle_sessions_v4_pending', to_regclass('public.guildbattle_sessions_v4_pending') is not null,
      'guildbattle_sessions_v4_expire', to_regclass('public.guildbattle_sessions_v4_expire') is not null,
      'pvp_attempts_user_recent', to_regclass('public.pvp_attempts_user_recent') is not null
    )
  );
$$;

revoke all on function public.index_hot_filters_install_ok() from public, anon, authenticated;
grant execute on function public.index_hot_filters_install_ok() to authenticated;

notify pgrst, 'reload schema';
commit;
select public.index_hot_filters_install_ok() as result;
