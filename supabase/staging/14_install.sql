-- ⚠ 테스트 전용 14/14. 운영 실행 금지. 파일 전체를 번호 순서대로 실행.
-- 대상 프로젝트: cuyqchmdcnsgzkwyclji; 운영 htarwisgkkphutxxnuak 금지.
-- 완료한 파일은 다시 실행해도 건너뜀. 중간 오류는 해당 파일만 되돌아감.
-- 실제 project_ref는 SQL Editor가 보장해서 제공하지 않음: DB 고유번호를 대조.
-- 지정 테스트 DB의 식별번호와 일치할 때만 허용. guard 삭제/SET 우회 금지.
-- docs/STAGING.md 및 supabase/staging/README.md 먼저 확인.

begin;
do $vr_project_guard$
declare
  confirmed_ref text := 'cuyqchmdcnsgzkwyclji';
  expected_db_id text := '7703759698107299042';
  actual_db_id text;
begin
  if confirmed_ref is distinct from 'cuyqchmdcnsgzkwyclji' or confirmed_ref = 'htarwisgkkphutxxnuak' then
    raise exception 'STOP: 지정한 테스트 프로젝트만 허용합니다. 운영 DB 금지.';
  end if;
  if expected_db_id !~ '^[0-9]{16,20}$' then
    raise exception 'STOP: 테스트 DB의 실제 고유번호가 아직 등록되지 않았습니다. 안내 문서를 확인하세요.';
  end if;
  select system_identifier::text into actual_db_id from pg_catalog.pg_control_system();
  if actual_db_id is distinct from expected_db_id then
    raise exception 'STOP: 현재 접속한 DB가 지정된 테스트 DB와 다릅니다. 실행 금지.';
  end if;
exception when insufficient_privilege or undefined_function then
  raise exception 'STOP: DB 식별 조회 권한/기능이 없어 안전하게 중단합니다. guard를 삭제하지 마세요.';
end $vr_project_guard$;

-- 설치 기록은 API에서 접근할 수 없는 별도 스키마에 저장.
select pg_advisory_xact_lock(20261107, 490);
create schema if not exists vr_staging_install;
revoke all on schema vr_staging_install from public, anon, authenticated;
create table if not exists vr_staging_install.parts (
  part_no integer primary key, bundle_hash text not null, part_hash text not null,
  project_ref text not null, db_id text not null, applied_at timestamptz not null default now()
);
alter table vr_staging_install.parts enable row level security;
revoke all on vr_staging_install.parts from public, anon, authenticated;
set local check_function_bodies = off;

do $vr_install_part$
begin
  if exists (select 1 from vr_staging_install.parts where bundle_hash <> '8ff473e973d5bc52e71f798115e03bf5931c2ad74f766c08f6dd0f2d69dd56f5' or project_ref <> 'cuyqchmdcnsgzkwyclji' or db_id <> '7703759698107299042') then
    raise exception 'STOP: 다른 버전/DB의 설치 기록입니다. 파일을 섞지 마세요.';
  end if;
  if exists (select 1 from vr_staging_install.parts where part_no = 14) then
    if not exists (select 1 from vr_staging_install.parts where part_no = 14 and part_hash = '723c3d5ab0678fe6fa94104ae457627d713931175f6cc120570d1164ced163c2') then
      raise exception 'STOP: 완료한 파일과 내용이 다릅니다.';
    end if;
    raise notice '14_install.sql: 이미 완료, 변경 없이 건너뜀';
    return;
  end if;
  if (select count(*) from vr_staging_install.parts where part_no < 14) <> 13 then
    raise exception 'STOP: 앞 번호 파일을 먼저 실행하세요 (14_install.sql).';
  end if;
  -- 설치 도중에는 클라이언트가 미완성 게임 스키마에 접근하지 못함. 마지막에만 개방.
  revoke usage on schema public from public, anon, authenticated;
  execute $vr_statement$grant execute on function public.war_ui() to authenticated;$vr_statement$;
  execute $vr_statement$create or replace function public.war_auto_assign() returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$ begin perform _guildbattle_guard_v4(); perform pg_advisory_xact_lock(hashtext('guildbattle:v4')); return _war_auto_assign_v4(); end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.war_auto_assign() from public,anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.war_auto_assign() to authenticated;$vr_statement$;
  execute $vr_statement$create or replace function public.war_meta() returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$ begin perform _guildbattle_guard_v4(); perform pg_advisory_xact_lock(hashtext('guildbattle:v4')); return _war_meta_v4(); end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.war_meta() from public,anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.war_meta() to authenticated;$vr_statement$;
  execute $vr_statement$-- 설치본의 단일 트랜잭션에 포함

-- 공개 게임 설정만 명시적으로 조회 허용 (사용자 자료 아님).
grant select on public.story_card_pool, public.story_phase_config, public.story_premium_ur,
  public.pvp_card_meta, public.pvp_reward_table, public.pvp_tier_table, public.pvp_streak_table,
  public.dispatch_card_meta, public.dispatch_zones to anon, authenticated;$vr_statement$;
  execute $vr_statement$-- 설치 완료 (원본 SQL의 사용자 테이블은 처음부터 비어 있어야 함).
set local check_function_bodies = on;$vr_statement$;
  execute $vr_statement$do $staging_verify$
declare f record;
begin
  for f in
    select pg_get_functiondef(p.oid) ddl from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prokind = 'f'
      and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
  loop execute f.ddl; end loop;
  if exists (select 1 from auth.users) then raise exception 'STOP: 설치 중 사용자 자료 발견'; end if;
  if exists (select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relkind='r' and not c.relrowsecurity
      and not exists (select 1 from pg_depend d where d.objid = c.oid and d.deptype = 'e')) then
    raise exception 'STOP: RLS 없는 테이블 발견';
  end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.prosecdef and left(p.proname,1)='_'
      and pg_get_function_result(p.oid) <> 'trigger'
      and (has_function_privilege('anon',p.oid,'execute') or has_function_privilege('authenticated',p.oid,'execute'))) then
    raise exception 'STOP: 외부 호출 가능한 내부 서버 함수 발견';
  end if;
end $staging_verify$;$vr_statement$;

  grant usage on schema public to public, anon, authenticated;
  insert into vr_staging_install.parts(part_no, bundle_hash, part_hash, project_ref, db_id)
  values (14, '8ff473e973d5bc52e71f798115e03bf5931c2ad74f766c08f6dd0f2d69dd56f5', '723c3d5ab0678fe6fa94104ae457627d713931175f6cc120570d1164ced163c2', 'cuyqchmdcnsgzkwyclji', '7703759698107299042');
end $vr_install_part$;
commit;
select '14_install.sql: 완료 또는 이미 완료 (14/14)' as result;
