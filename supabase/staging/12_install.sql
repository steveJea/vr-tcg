-- ⚠ 테스트 전용 12/14. 운영 실행 금지. 파일 전체를 번호 순서대로 실행.
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
  if exists (select 1 from vr_staging_install.parts where bundle_hash <> '1e7a91f656cb089116c27629c13947ec0c769796933ace7bb576f39ba0920d4e' or project_ref <> 'cuyqchmdcnsgzkwyclji' or db_id <> '7703759698107299042') then
    raise exception 'STOP: 다른 버전/DB의 설치 기록입니다. 파일을 섞지 마세요.';
  end if;
  if exists (select 1 from vr_staging_install.parts where part_no = 12) then
    if not exists (select 1 from vr_staging_install.parts where part_no = 12 and part_hash = 'e1a59d08a6876eb4743e8f93627ae2814b77481e40f7127f474ef8fd7c52251b') then
      raise exception 'STOP: 완료한 파일과 내용이 다릅니다.';
    end if;
    raise notice '12_install.sql: 이미 완료, 변경 없이 건너뜀';
    return;
  end if;
  if (select count(*) from vr_staging_install.parts where part_no < 12) <> 11 then
    raise exception 'STOP: 앞 번호 파일을 먼저 실행하세요 (12_install.sql).';
  end if;
  -- 설치 도중에는 클라이언트가 미완성 게임 스키마에 접근하지 못함. 마지막에만 개방.
  revoke usage on schema public from public, anon, authenticated;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10094','{"class":"WIND","gender":"MALE","MOR":21,"cost":7,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10350','{"class":"FIRE","gender":"MALE","MOR":80,"cost":35,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10366','{"class":"WIND","gender":"MALE","MOR":32,"cost":13,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10016','{"class":"WIND","gender":"MALE","MOR":12,"cost":18,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10385','{"class":"ICE","gender":"MALE","MOR":21,"cost":16,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10474','{"class":"WIND","gender":"MALE","MOR":58,"cost":13,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10287','{"class":"FIRE","gender":"MALE","MOR":18,"cost":18,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10182','{"class":"DARK","gender":"MALE","MOR":20,"cost":16,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10136','{"class":"ICE","gender":"MALE","MOR":16,"cost":27,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10209','{"class":"ICE","gender":"MALE","MOR":20,"cost":7,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10170','{"class":"FIRE","gender":"MALE","MOR":21,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10128','{"class":"FIRE","gender":"MALE","MOR":25,"cost":6,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10433','{"class":"WIND","gender":"MALE","MOR":19,"cost":26,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10374','{"class":"WIND","gender":"MALE","MOR":82,"cost":32,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10218','{"class":"FIRE","gender":"MALE","MOR":59,"cost":14,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10441','{"class":"FIRE","gender":"MALE","MOR":37,"cost":6,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10349','{"class":"FIRE","gender":"MALE","MOR":21,"cost":16,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10314','{"class":"WIND","gender":"MALE","MOR":31,"cost":6,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10337','{"class":"ICE","gender":"MALE","MOR":25,"cost":6,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10038','{"class":"WIND","gender":"MALE","MOR":21,"cost":7,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10365','{"class":"WIND","gender":"MALE","MOR":80,"cost":12,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10278','{"class":"WIND","gender":"MALE","MOR":79,"cost":23,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10251','{"class":"FIRE","gender":"MALE","MOR":82,"cost":14,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10109','{"class":"FIRE","gender":"MALE","MOR":60,"cost":42,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10017','{"class":"FIRE","gender":"MALE","MOR":60,"cost":30,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10015','{"class":"ICE","gender":"MALE","MOR":72,"cost":32,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10028','{"class":"WIND","gender":"MALE","MOR":55,"cost":7,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10181','{"class":"WIND","gender":"MALE","MOR":19,"cost":35,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10333','{"class":"FIRE","gender":"MALE","MOR":78,"cost":43,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10054','{"class":"DARK","gender":"MALE","MOR":8,"cost":46,"grade":"ULTRA RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10046','{"class":"WIND","gender":"MALE","MOR":75,"cost":22,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10066','{"class":"WIND","gender":"MALE","MOR":55,"cost":12,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10195','{"class":"ICE","gender":"MALE","MOR":10,"cost":15,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10283','{"class":"FIRE","gender":"MALE","MOR":65,"cost":14,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10284','{"class":"FIRE","gender":"MALE","MOR":40,"cost":20,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10321','{"class":"DARK","gender":"MALE","MOR":12,"cost":38,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10320','{"class":"FIRE","gender":"MALE","MOR":16,"cost":5,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10371','{"class":"FIRE","gender":"MALE","MOR":16,"cost":28,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10345','{"class":"FIRE","gender":"MALE","MOR":14,"cost":19,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10021','{"class":"WIND","gender":"MALE","MOR":20,"cost":20,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10424','{"class":"WIND","gender":"MALE","MOR":12,"cost":21,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10398','{"class":"ICE","gender":"MALE","MOR":24,"cost":16,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10318','{"class":"WIND","gender":"MALE","MOR":42,"cost":13,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10458','{"class":"FIRE","gender":"MALE","MOR":24,"cost":18,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10464','{"class":"FIRE","gender":"MALE","MOR":38,"cost":19,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10233','{"class":"FIRE","gender":"MALE","MOR":19,"cost":9,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10034','{"class":"WIND","gender":"MALE","MOR":35,"cost":14,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10171','{"class":"FIRE","gender":"MALE","MOR":75,"cost":13,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10119','{"class":"ICE","gender":"MALE","MOR":75,"cost":9,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10226','{"class":"WIND","gender":"MALE","MOR":11,"cost":16,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10307','{"class":"ICE","gender":"MALE","MOR":80,"cost":20,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10402','{"class":"WIND","gender":"MALE","MOR":13,"cost":7,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10009','{"class":"WIND","gender":"MALE","MOR":65,"cost":14,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10055','{"class":"WIND","gender":"MALE","MOR":18,"cost":7,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10013','{"class":"FIRE","gender":"MALE","MOR":55,"cost":39,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10313','{"class":"WIND","gender":"MALE","MOR":65,"cost":15,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10106','{"class":"ICE","gender":"MALE","MOR":16,"cost":6,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10316','{"class":"WIND","gender":"MALE","MOR":50,"cost":12,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10416','{"class":"WIND","gender":"MALE","MOR":45,"cost":11,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10057','{"class":"WIND","gender":"MALE","MOR":3,"cost":5,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10220','{"class":"FIRE","gender":"MALE","MOR":60,"cost":13,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10340','{"class":"FIRE","gender":"MALE","MOR":30,"cost":11,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10309','{"class":"FIRE","gender":"MALE","MOR":15,"cost":25,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10070','{"class":"ICE","gender":"MALE","MOR":78,"cost":39,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10113','{"class":"ICE","gender":"MALE","MOR":30,"cost":7,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10364','{"class":"ICE","gender":"MALE","MOR":17,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10410','{"class":"WIND","gender":"MALE","MOR":45,"cost":9,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10419','{"class":"WIND","gender":"MALE","MOR":12,"cost":25,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10053','{"class":"DARK","gender":"MALE","MOR":1,"cost":45,"grade":"ULTRA RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10176','{"class":"LIGHT","gender":"MALE","MOR":90,"cost":49,"grade":"ULTRA RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10200','{"class":"DARK","gender":"MALE","MOR":15,"cost":38,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10234','{"class":"FIRE","gender":"MALE","MOR":20,"cost":16,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10123','{"class":"FIRE","gender":"MALE","MOR":12,"cost":29,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10304','{"class":"DARK","gender":"MALE","MOR":85,"cost":51,"grade":"ULTRA RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10434','{"class":"FIRE","gender":"MALE","MOR":25,"cost":9,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10430','{"class":"WIND","gender":"MALE","MOR":22,"cost":9,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10379','{"class":"WIND","gender":"MALE","MOR":70,"cost":14,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10325','{"class":"DARK","gender":"FEMALE","MOR":1,"cost":46,"grade":"ULTRA RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10260','{"class":"ICE","gender":"FEMALE","MOR":58,"cost":13,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10300','{"class":"DARK","gender":"FEMALE","MOR":72,"cost":20,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10462','{"class":"WIND","gender":"FEMALE","MOR":65,"cost":15,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10072','{"class":"DARK","gender":"FEMALE","MOR":10,"cost":26,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10256','{"class":"DARK","gender":"FEMALE","MOR":55,"cost":21,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10115','{"class":"WIND","gender":"FEMALE","MOR":89,"cost":19,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10348','{"class":"ICE","gender":"FEMALE","MOR":24,"cost":8,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10339','{"class":"ICE","gender":"FEMALE","MOR":28,"cost":8,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10394','{"class":"LIGHT","gender":"FEMALE","MOR":88,"cost":25,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10047','{"class":"WIND","gender":"FEMALE","MOR":82,"cost":27,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10188','{"class":"WIND","gender":"FEMALE","MOR":80,"cost":34,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10132','{"class":"WIND","gender":"FEMALE","MOR":81,"cost":21,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10087','{"class":"ICE","gender":"FEMALE","MOR":21,"cost":29,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10202','{"class":"FIRE","gender":"FEMALE","MOR":45,"cost":19,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10184','{"class":"WIND","gender":"FEMALE","MOR":31,"cost":8,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10103','{"class":"DARK","gender":"FEMALE","MOR":89,"cost":19,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10265','{"class":"WIND","gender":"FEMALE","MOR":79,"cost":25,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10266','{"class":"WIND","gender":"FEMALE","MOR":88,"cost":18,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10465','{"class":"WIND","gender":"FEMALE","MOR":85,"cost":43,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10466','{"class":"WIND","gender":"FEMALE","MOR":88,"cost":22,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10002','{"class":"WIND","gender":"FEMALE","MOR":31,"cost":9,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10289','{"class":"WIND","gender":"FEMALE","MOR":52,"cost":9,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10083','{"class":"WIND","gender":"FEMALE","MOR":11,"cost":5,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10079','{"class":"FIRE","gender":"FEMALE","MOR":13,"cost":11,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10338','{"class":"WIND","gender":"FEMALE","MOR":70,"cost":34,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10336','{"class":"WIND","gender":"FEMALE","MOR":78,"cost":34,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10418','{"class":"ICE","gender":"FEMALE","MOR":74,"cost":40,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10323','{"class":"FIRE","gender":"FEMALE","MOR":72,"cost":49,"grade":"ULTRA RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10403','{"class":"ICE","gender":"FEMALE","MOR":70,"cost":14,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10185','{"class":"FIRE","gender":"FEMALE","MOR":88,"cost":9,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10308','{"class":"ICE","gender":"FEMALE","MOR":55,"cost":28,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10413','{"class":"WIND","gender":"FEMALE","MOR":88,"cost":35,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10415','{"class":"DARK","gender":"FEMALE","MOR":90,"cost":43,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10414','{"class":"ICE","gender":"FEMALE","MOR":85,"cost":35,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10186','{"class":"ICE","gender":"FEMALE","MOR":43,"cost":37,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10295','{"class":"WIND","gender":"FEMALE","MOR":25,"cost":12,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10297','{"class":"WIND","gender":"FEMALE","MOR":92,"cost":23,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10317','{"class":"ICE","gender":"FEMALE","MOR":72,"cost":41,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10108','{"class":"LIGHT","gender":"FEMALE","MOR":90,"cost":41,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10417','{"class":"ICE","gender":"FEMALE","MOR":78,"cost":17,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10172','{"class":"FIRE","gender":"FEMALE","MOR":21,"cost":6,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10262','{"class":"WIND","gender":"FEMALE","MOR":40,"cost":8,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10261','{"class":"WIND","gender":"FEMALE","MOR":58,"cost":20,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10290','{"class":"LIGHT","gender":"FEMALE","MOR":99,"cost":17,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10384','{"class":"WIND","gender":"FEMALE","MOR":55,"cost":16,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10383','{"class":"DARK","gender":"FEMALE","MOR":85,"cost":42,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10110','{"class":"FIRE","gender":"FEMALE","MOR":58,"cost":34,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10442','{"class":"ICE","gender":"FEMALE","MOR":60,"cost":30,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10129','{"class":"WIND","gender":"FEMALE","MOR":78,"cost":15,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10014','{"class":"FIRE","gender":"FEMALE","MOR":21,"cost":7,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10235','{"class":"ICE","gender":"FEMALE","MOR":35,"cost":6,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10111','{"class":"FIRE","gender":"FEMALE","MOR":80,"cost":25,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10357','{"class":"FIRE","gender":"FEMALE","MOR":15,"cost":15,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10360','{"class":"WIND","gender":"FEMALE","MOR":12,"cost":13,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10306','{"class":"WIND","gender":"FEMALE","MOR":90,"cost":17,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10285','{"class":"WIND","gender":"FEMALE","MOR":20,"cost":19,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10343','{"class":"FIRE","gender":"FEMALE","MOR":45,"cost":27,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10271','{"class":"WIND","gender":"FEMALE","MOR":13,"cost":12,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10003','{"class":"FIRE","gender":"FEMALE","MOR":27,"cost":9,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10095','{"class":"FIRE","gender":"FEMALE","MOR":42,"cost":22,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10096','{"class":"ICE","gender":"FEMALE","MOR":43,"cost":28,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10342','{"class":"WIND","gender":"FEMALE","MOR":41,"cost":12,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10327','{"class":"ICE","gender":"FEMALE","MOR":21,"cost":14,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10286','{"class":"WIND","gender":"FEMALE","MOR":65,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10273','{"class":"WIND","gender":"FEMALE","MOR":32,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10253','{"class":"FIRE","gender":"FEMALE","MOR":52,"cost":15,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10061','{"class":"ICE","gender":"FEMALE","MOR":31,"cost":36,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10460','{"class":"WIND","gender":"FEMALE","MOR":51,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10459','{"class":"WIND","gender":"FEMALE","MOR":49,"cost":13,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10461','{"class":"FIRE","gender":"FEMALE","MOR":57,"cost":23,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10296','{"class":"WIND","gender":"FEMALE","MOR":41,"cost":21,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10246','{"class":"WIND","gender":"FEMALE","MOR":51,"cost":20,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10204','{"class":"WIND","gender":"FEMALE","MOR":60,"cost":24,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10447','{"class":"WIND","gender":"FEMALE","MOR":44,"cost":21,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10429','{"class":"WIND","gender":"FEMALE","MOR":50,"cost":23,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10211','{"class":"WIND","gender":"FEMALE","MOR":21,"cost":8,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10193','{"class":"ICE","gender":"FEMALE","MOR":52,"cost":9,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10120','{"class":"FIRE","gender":"FEMALE","MOR":24,"cost":13,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10101','{"class":"WIND","gender":"FEMALE","MOR":33,"cost":14,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10099','{"class":"WIND","gender":"FEMALE","MOR":50,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10241','{"class":"WIND","gender":"FEMALE","MOR":49,"cost":20,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10044','{"class":"WIND","gender":"FEMALE","MOR":42,"cost":21,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10043','{"class":"WIND","gender":"FEMALE","MOR":25,"cost":30,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10376','{"class":"WIND","gender":"FEMALE","MOR":71,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10377','{"class":"WIND","gender":"FEMALE","MOR":81,"cost":8,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10322','{"class":"ICE","gender":"FEMALE","MOR":62,"cost":50,"grade":"ULTRA RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10239','{"class":"WIND","gender":"FEMALE","MOR":31,"cost":31,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10039','{"class":"WIND","gender":"FEMALE","MOR":30,"cost":8,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10310','{"class":"WIND","gender":"FEMALE","MOR":19,"cost":8,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10247','{"class":"ICE","gender":"FEMALE","MOR":72,"cost":14,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10248','{"class":"WIND","gender":"FEMALE","MOR":82,"cost":6,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10221','{"class":"FIRE","gender":"FEMALE","MOR":80,"cost":9,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10011','{"class":"WIND","gender":"FEMALE","MOR":28,"cost":7,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10140','{"class":"WIND","gender":"FEMALE","MOR":32,"cost":11,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10388','{"class":"WIND","gender":"FEMALE","MOR":57,"cost":7,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10121','{"class":"WIND","gender":"FEMALE","MOR":14,"cost":16,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10236','{"class":"FIRE","gender":"FEMALE","MOR":75,"cost":42,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10102','{"class":"WIND","gender":"FEMALE","MOR":9,"cost":26,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10092','{"class":"WIND","gender":"FEMALE","MOR":21,"cost":17,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10194','{"class":"WIND","gender":"FEMALE","MOR":29,"cost":17,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10361','{"class":"WIND","gender":"FEMALE","MOR":6,"cost":27,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10354','{"class":"ICE","gender":"FEMALE","MOR":3,"cost":36,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10254','{"class":"WIND","gender":"FEMALE","MOR":42,"cost":18,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10222','{"class":"WIND","gender":"FEMALE","MOR":24,"cost":17,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10470','{"class":"FIRE","gender":"FEMALE","MOR":57,"cost":23,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10059','{"class":"DARK","gender":"FEMALE","MOR":6,"cost":17,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10428','{"class":"WIND","gender":"FEMALE","MOR":77,"cost":5,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10471','{"class":"FIRE","gender":"FEMALE","MOR":80,"cost":14,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10450','{"class":"ICE","gender":"FEMALE","MOR":54,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10432','{"class":"WIND","gender":"FEMALE","MOR":88,"cost":22,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10359','{"class":"ICE","gender":"FEMALE","MOR":77,"cost":51,"grade":"ULTRA RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10362','{"class":"DARK","gender":"FEMALE","MOR":80,"cost":33,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10454','{"class":"ICE","gender":"FEMALE","MOR":13,"cost":21,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10363','{"class":"WIND","gender":"FEMALE","MOR":78,"cost":9,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10436','{"class":"FIRE","gender":"FEMALE","MOR":21,"cost":12,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10412','{"class":"ICE","gender":"FEMALE","MOR":13,"cost":12,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10040','{"class":"FIRE","gender":"FEMALE","MOR":82,"cost":15,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10042','{"class":"WIND","gender":"FEMALE","MOR":80,"cost":24,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10237','{"class":"ICE","gender":"FEMALE","MOR":75,"cost":25,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10207','{"class":"ICE","gender":"FEMALE","MOR":6,"cost":27,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10208','{"class":"DARK","gender":"FEMALE","MOR":2,"cost":31,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10303','{"class":"WIND","gender":"FEMALE","MOR":19,"cost":9,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10468','{"class":"WIND","gender":"FEMALE","MOR":88,"cost":13,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10467','{"class":"LIGHT","gender":"FEMALE","MOR":90,"cost":15,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10294','{"class":"WIND","gender":"FEMALE","MOR":81,"cost":15,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10258','{"class":"WIND","gender":"FEMALE","MOR":80,"cost":25,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10056','{"class":"WIND","gender":"FEMALE","MOR":73,"cost":14,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10041','{"class":"WIND","gender":"FEMALE","MOR":72,"cost":32,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10255','{"class":"ICE","gender":"FEMALE","MOR":75,"cost":44,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10141','{"class":"WIND","gender":"FEMALE","MOR":43,"cost":22,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10133','{"class":"WIND","gender":"FEMALE","MOR":51,"cost":23,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10091','{"class":"DARK","gender":"FEMALE","MOR":24,"cost":21,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10090','{"class":"ICE","gender":"FEMALE","MOR":35,"cost":20,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10344','{"class":"ICE","gender":"FEMALE","MOR":78,"cost":7,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10330','{"class":"ICE","gender":"FEMALE","MOR":55,"cost":11,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10263','{"class":"FIRE","gender":"FEMALE","MOR":80,"cost":6,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10249','{"class":"FIRE","gender":"FEMALE","MOR":39,"cost":13,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10063','{"class":"ICE","gender":"FEMALE","MOR":49,"cost":14,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10052','{"class":"DARK","gender":"FEMALE","MOR":6,"cost":39,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10190','{"class":"FIRE","gender":"FEMALE","MOR":61,"cost":13,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10174','{"class":"WIND","gender":"FEMALE","MOR":52,"cost":12,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10122','{"class":"ICE","gender":"FEMALE","MOR":68,"cost":14,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10029','{"class":"FIRE","gender":"FEMALE","MOR":75,"cost":23,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10232','{"class":"WIND","gender":"FEMALE","MOR":80,"cost":12,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10104','{"class":"WIND","gender":"FEMALE","MOR":66,"cost":24,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10378','{"class":"ICE","gender":"FEMALE","MOR":42,"cost":23,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10126','{"class":"WIND","gender":"FEMALE","MOR":44,"cost":31,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10062','{"class":"ABYSS","gender":"FEMALE","MOR":1,"cost":58,"grade":"MYTHIC RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10203','{"class":"LIGHT","gender":"FEMALE","MOR":80,"cost":33,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10097','{"class":"WIND","gender":"FEMALE","MOR":82,"cost":22,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10280','{"class":"ICE","gender":"FEMALE","MOR":23,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10352','{"class":"WIND","gender":"FEMALE","MOR":21,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10277','{"class":"WIND","gender":"FEMALE","MOR":39,"cost":7,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10100','{"class":"FIRE","gender":"FEMALE","MOR":39,"cost":9,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10451','{"class":"ICE","gender":"FEMALE","MOR":49,"cost":12,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10389','{"class":"WIND","gender":"FEMALE","MOR":51,"cost":11,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10264','{"class":"ICE","gender":"FEMALE","MOR":61,"cost":11,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10438','{"class":"ICE","gender":"FEMALE","MOR":59,"cost":13,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10177','{"class":"WIND","gender":"FEMALE","MOR":30,"cost":13,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10178','{"class":"ICE","gender":"FEMALE","MOR":29,"cost":12,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10372','{"class":"ICE","gender":"FEMALE","MOR":68,"cost":24,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10373','{"class":"WIND","gender":"FEMALE","MOR":50,"cost":35,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10130','{"class":"WIND","gender":"FEMALE","MOR":81,"cost":7,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10131','{"class":"DARK","gender":"FEMALE","MOR":72,"cost":31,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10341','{"class":"ICE","gender":"FEMALE","MOR":82,"cost":44,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10272','{"class":"WIND","gender":"FEMALE","MOR":69,"cost":6,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10117','{"class":"FIRE","gender":"FEMALE","MOR":82,"cost":44,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10078','{"class":"FIRE","gender":"FEMALE","MOR":13,"cost":30,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10084','{"class":"FIRE","gender":"FEMALE","MOR":56,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10085','{"class":"FIRE","gender":"FEMALE","MOR":59,"cost":11,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10217','{"class":"DARK","gender":"FEMALE","MOR":3,"cost":40,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10216','{"class":"DARK","gender":"FEMALE","MOR":8,"cost":39,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10324','{"class":"DARK","gender":"FEMALE","MOR":90,"cost":53,"grade":"ULTRA RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10006','{"class":"FIRE","gender":"FEMALE","MOR":80,"cost":14,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10068','{"class":"DARK","gender":"FEMALE","MOR":65,"cost":41,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10400','{"class":"ICE","gender":"FEMALE","MOR":35,"cost":26,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10331','{"class":"LIGHT","gender":"FEMALE","MOR":99,"cost":52,"grade":"ULTRA RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10250','{"class":"WIND","gender":"FEMALE","MOR":57,"cost":7,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10022','{"class":"FIRE","gender":"FEMALE","MOR":82,"cost":8,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10437','{"class":"DARK","gender":"FEMALE","MOR":6,"cost":18,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10426','{"class":"FIRE","gender":"FEMALE","MOR":16,"cost":18,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10381','{"class":"FIRE","gender":"FEMALE","MOR":41,"cost":5,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10179','{"class":"WIND","gender":"FEMALE","MOR":65,"cost":8,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10215','{"class":"FIRE","gender":"FEMALE","MOR":72,"cost":13,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10214','{"class":"FIRE","gender":"FEMALE","MOR":72,"cost":31,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10223','{"class":"WIND","gender":"FEMALE","MOR":80,"cost":12,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10269','{"class":"WIND","gender":"FEMALE","MOR":6,"cost":38,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10268','{"class":"WIND","gender":"FEMALE","MOR":11,"cost":29,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10473','{"class":"WIND","gender":"FEMALE","MOR":12,"cost":28,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10135','{"class":"DARK","gender":"FEMALE","MOR":77,"cost":25,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10206','{"class":"ICE","gender":"FEMALE","MOR":80,"cost":11,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10240','{"class":"WIND","gender":"FEMALE","MOR":72,"cost":32,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10238','{"class":"WIND","gender":"FEMALE","MOR":45,"cost":12,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10230','{"class":"WIND","gender":"FEMALE","MOR":78,"cost":22,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10227','{"class":"WIND","gender":"FEMALE","MOR":87,"cost":24,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10387','{"class":"WIND","gender":"FEMALE","MOR":25,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10281','{"class":"WIND","gender":"FEMALE","MOR":80,"cost":41,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10472','{"class":"WIND","gender":"FEMALE","MOR":78,"cost":8,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10455','{"class":"FIRE","gender":"FEMALE","MOR":80,"cost":24,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10423','{"class":"FIRE","gender":"FEMALE","MOR":21,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10456','{"class":"ICE","gender":"FEMALE","MOR":85,"cost":7,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10457','{"class":"WIND","gender":"FEMALE","MOR":83,"cost":33,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10224','{"class":"WIND","gender":"FEMALE","MOR":79,"cost":24,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10382','{"class":"WIND","gender":"FEMALE","MOR":30,"cost":6,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10393','{"class":"ICE","gender":"FEMALE","MOR":89,"cost":33,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10030','{"class":"WIND","gender":"FEMALE","MOR":72,"cost":9,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10391','{"class":"WIND","gender":"FEMALE","MOR":21,"cost":19,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10392','{"class":"WIND","gender":"FEMALE","MOR":88,"cost":42,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10311','{"class":"ABYSS","gender":"FEMALE","MOR":100,"cost":65,"grade":"MYTHIC RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10397','{"class":"ICE","gender":"FEMALE","MOR":88,"cost":21,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10242','{"class":"WIND","gender":"FEMALE","MOR":55,"cost":15,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10356','{"class":"ICE","gender":"FEMALE","MOR":21,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10274','{"class":"WIND","gender":"FEMALE","MOR":21,"cost":6,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10192','{"class":"FIRE","gender":"FEMALE","MOR":78,"cost":15,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10093','{"class":"WIND","gender":"FEMALE","MOR":85,"cost":8,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10312','{"class":"DARK","gender":"FEMALE","MOR":22,"cost":47,"grade":"ULTRA RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10243','{"class":"ICE","gender":"FEMALE","MOR":40,"cost":14,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10231','{"class":"LIGHT","gender":"FEMALE","MOR":88,"cost":35,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10399','{"class":"WIND","gender":"FEMALE","MOR":90,"cost":43,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10050','{"class":"FIRE","gender":"MALE","MOR":28,"cost":9,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10073','{"class":"LIGHT","gender":"FEMALE","MOR":88,"cost":33,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10229','{"class":"FIRE","gender":"FEMALE","MOR":65,"cost":34,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10012','{"class":"WIND","gender":"FEMALE","MOR":45,"cost":12,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10219','{"class":"DARK","gender":"FEMALE","MOR":55,"cost":8,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10305','{"class":"FIRE","gender":"FEMALE","MOR":66,"cost":9,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10443','{"class":"ICE","gender":"FEMALE","MOR":75,"cost":8,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10024','{"class":"ICE","gender":"FEMALE","MOR":88,"cost":41,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10446','{"class":"FIRE","gender":"FEMALE","MOR":10,"cost":13,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10427','{"class":"FIRE","gender":"FEMALE","MOR":80,"cost":14,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10411','{"class":"ICE","gender":"FEMALE","MOR":80,"cost":9,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10058','{"class":"FIRE","gender":"FEMALE","MOR":75,"cost":54,"grade":"ULTRA RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10395','{"class":"WIND","gender":"FEMALE","MOR":87,"cost":15,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10213','{"class":"FIRE","gender":"FEMALE","MOR":52,"cost":44,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10175','{"class":"WIND","gender":"FEMALE","MOR":41,"cost":19,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10007','{"class":"WIND","gender":"FEMALE","MOR":44,"cost":20,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10257','{"class":"ICE","gender":"FEMALE","MOR":31,"cost":31,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10291','{"class":"DARK","gender":"FEMALE","MOR":78,"cost":54,"grade":"ULTRA RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10326','{"class":"DARK","gender":"FEMALE","MOR":1,"cost":55,"grade":"MYTHIC RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10288','{"class":"FIRE","gender":"FEMALE","MOR":6,"cost":30,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10282','{"class":"ICE","gender":"FEMALE","MOR":12,"cost":11,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10405','{"class":"LIGHT","gender":"FEMALE","MOR":89,"cost":18,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10452','{"class":"ICE","gender":"FEMALE","MOR":70,"cost":34,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10370','{"class":"ICE","gender":"MALE","MOR":12,"cost":19,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10368','{"class":"WIND","gender":"MALE","MOR":11,"cost":19,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10369','{"class":"ICE","gender":"MALE","MOR":1,"cost":36,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10358','{"class":"WIND","gender":"MALE","MOR":92,"cost":55,"grade":"ULTRA RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10351','{"class":"WIND","gender":"MALE","MOR":16,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10449','{"class":"WIND","gender":"MALE","MOR":12,"cost":6,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10422','{"class":"WIND","gender":"MALE","MOR":20,"cost":8,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10421','{"class":"WIND","gender":"MALE","MOR":9,"cost":13,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10396','{"class":"ICE","gender":"MALE","MOR":77,"cost":15,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10435','{"class":"FIRE","gender":"MALE","MOR":55,"cost":50,"grade":"ULTRA RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10127','{"class":"LIGHT","gender":"FEMALE","MOR":80,"cost":44,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10439','{"class":"WIND","gender":"FEMALE","MOR":75,"cost":45,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10355','{"class":"ICE","gender":"FEMALE","MOR":78,"cost":14,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10367','{"class":"ICE","gender":"FEMALE","MOR":80,"cost":25,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10440','{"class":"WIND","gender":"FEMALE","MOR":8,"cost":51,"grade":"ULTRA RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10267','{"class":"ICE","gender":"FEMALE","MOR":80,"cost":35,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10509','{"class":"WIND","gender":"FEMALE","MOR":55,"cost":33,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10511','{"class":"FIRE","gender":"FEMALE","MOR":85,"cost":42,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10512','{"class":"WIND","gender":"FEMALE","MOR":80,"cost":27,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10513','{"class":"WIND","gender":"FEMALE","MOR":80,"cost":53,"grade":"ULTRA RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10520','{"class":"FIRE","gender":"MALE","MOR":12,"cost":18,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10521','{"class":"ICE","gender":"FEMALE","MOR":80,"cost":44,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10522','{"class":"WIND","gender":"FEMALE","MOR":75,"cost":54,"grade":"ULTRA RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10523','{"class":"DARK","gender":"FEMALE","MOR":80,"cost":45,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10524','{"class":"ICE","gender":"MALE","MOR":65,"cost":53,"grade":"ULTRA RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10525','{"class":"FIRE","gender":"FEMALE","MOR":55,"cost":49,"grade":"ULTRA RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10526','{"class":"FIRE","gender":"MALE","MOR":76,"cost":41,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10527','{"class":"ICE","gender":"MALE","MOR":78,"cost":46,"grade":"ULTRA RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10528','{"class":"FIRE","gender":"MALE","MOR":65,"cost":53,"grade":"ULTRA RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10529','{"class":"WIND","gender":"FEMALE","MOR":80,"cost":43,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10530','{"class":"WIND","gender":"MALE","MOR":68,"cost":37,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10531','{"class":"WIND","gender":"MALE","MOR":25,"cost":35,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10532','{"class":"ICE","gender":"MALE","MOR":77,"cost":35,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10301','{"class":"DARK","gender":"FEMALE","MOR":75,"cost":45,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10210','{"class":"WIND","gender":"MALE","MOR":55,"cost":30,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10143','{"class":"FIRE","gender":"MALE","MOR":10,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10144','{"class":"WIND","gender":"MALE","MOR":10,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10145','{"class":"ICE","gender":"MALE","MOR":10,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10146','{"class":"FIRE","gender":"MALE","MOR":10,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10147','{"class":"WIND","gender":"MALE","MOR":10,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10148','{"class":"ICE","gender":"MALE","MOR":10,"cost":20,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10149','{"class":"FIRE","gender":"MALE","MOR":10,"cost":20,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10150','{"class":"WIND","gender":"MALE","MOR":10,"cost":20,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10151','{"class":"ICE","gender":"MALE","MOR":10,"cost":30,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10152','{"class":"FIRE","gender":"MALE","MOR":10,"cost":30,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10153','{"class":"WIND","gender":"FEMALE","MOR":10,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10154','{"class":"ICE","gender":"FEMALE","MOR":10,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10155','{"class":"FIRE","gender":"FEMALE","MOR":10,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10156','{"class":"WIND","gender":"FEMALE","MOR":10,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10157','{"class":"ICE","gender":"FEMALE","MOR":10,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10158','{"class":"FIRE","gender":"FEMALE","MOR":10,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10159','{"class":"WIND","gender":"FEMALE","MOR":10,"cost":20,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10160','{"class":"ICE","gender":"FEMALE","MOR":10,"cost":20,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10161','{"class":"FIRE","gender":"FEMALE","MOR":10,"cost":20,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10162','{"class":"WIND","gender":"FEMALE","MOR":10,"cost":20,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10163','{"class":"ICE","gender":"FEMALE","MOR":10,"cost":30,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10164','{"class":"FIRE","gender":"FEMALE","MOR":10,"cost":30,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10165','{"class":"WIND","gender":"FEMALE","MOR":10,"cost":30,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10166','{"class":"DARK","gender":"FEMALE","MOR":10,"cost":30,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10167','{"class":"DARK","gender":"FEMALE","MOR":10,"cost":30,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10168','{"class":"DARK","gender":"FEMALE","MOR":10,"cost":30,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10082','{"class":"WIND","gender":"MALE","MOR":80,"cost":30,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10302','{"class":"WIND","gender":"FEMALE","MOR":10,"cost":20,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10196','{"class":"WIND","gender":"FEMALE","MOR":70,"cost":12,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10197','{"class":"WIND","gender":"FEMALE","MOR":70,"cost":12,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10198','{"class":"WIND","gender":"FEMALE","MOR":70,"cost":12,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10199','{"class":"WIND","gender":"FEMALE","MOR":70,"cost":16,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10116','{"class":"FIRE","gender":"FEMALE","MOR":80,"cost":35,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10335','{"class":"ABYSS","gender":"FEMALE","MOR":99,"cost":100,"grade":"MYTHIC RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10334','{"class":"VOID","gender":"FEMALE","MOR":100,"cost":185,"grade":"LEGENDARY RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10475','{"class":"DARK","gender":"MALE","MOR":10,"cost":45,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10476','{"class":"WIND","gender":"MALE","MOR":55,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10477','{"class":"WIND","gender":"MALE","MOR":55,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10478','{"class":"WIND","gender":"MALE","MOR":55,"cost":20,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10479','{"class":"ICE","gender":"MALE","MOR":55,"cost":20,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10480','{"class":"ICE","gender":"MALE","MOR":12,"cost":30,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10481','{"class":"ICE","gender":"MALE","MOR":12,"cost":30,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10482','{"class":"FIRE","gender":"MALE","MOR":3,"cost":30,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10483','{"class":"FIRE","gender":"MALE","MOR":7,"cost":30,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10484','{"class":"FIRE","gender":"MALE","MOR":4,"cost":30,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10485','{"class":"FIRE","gender":"FEMALE","MOR":24,"cost":20,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10486','{"class":"FIRE","gender":"FEMALE","MOR":54,"cost":20,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10487','{"class":"WIND","gender":"MALE","MOR":70,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10488','{"class":"ICE","gender":"MALE","MOR":3,"cost":45,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10489','{"class":"FIRE","gender":"MALE","MOR":13,"cost":30,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10490','{"class":"WIND","gender":"FEMALE","MOR":80,"cost":45,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10491','{"class":"ICE","gender":"FEMALE","MOR":80,"cost":45,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10492','{"class":"LIGHT","gender":"MALE","MOR":80,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10493','{"class":"LIGHT","gender":"FEMALE","MOR":82,"cost":30,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10494','{"class":"WIND","gender":"MALE","MOR":21,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10495','{"class":"ICE","gender":"MALE","MOR":18,"cost":20,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10496','{"class":"FIRE","gender":"MALE","MOR":6,"cost":30,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10497','{"class":"WIND","gender":"FEMALE","MOR":33,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10498','{"class":"ICE","gender":"FEMALE","MOR":24,"cost":20,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10499','{"class":"FIRE","gender":"FEMALE","MOR":27,"cost":30,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10500','{"class":"DARK","gender":"FEMALE","MOR":0,"cost":20,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10501','{"class":"DARK","gender":"FEMALE","MOR":0,"cost":30,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10502','{"class":"DARK","gender":"FEMALE","MOR":50,"cost":45,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10503','{"class":"DARK","gender":"FEMALE","MOR":99,"cost":55,"grade":"ULTRA RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10504','{"class":"LIGHT","gender":"FEMALE","MOR":99,"cost":55,"grade":"ULTRA RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10505','{"class":"ICE","gender":"FEMALE","MOR":42,"cost":30,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10506','{"class":"ICE","gender":"FEMALE","MOR":23,"cost":30,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10507','{"class":"ICE","gender":"FEMALE","MOR":16,"cost":30,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10508','{"class":"FIRE","gender":"MALE","MOR":76,"cost":45,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10510','{"class":"FIRE","gender":"FEMALE","MOR":34,"cost":30,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10514','{"class":"FIRE","gender":"MALE","MOR":20,"cost":20,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10515','{"class":"FIRE","gender":"FEMALE","MOR":77,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10516','{"class":"ICE","gender":"FEMALE","MOR":80,"cost":30,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10517','{"class":"DARK","gender":"MALE","MOR":3,"cost":55,"grade":"ULTRA RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10518','{"class":"DARK","gender":"MALE","MOR":21,"cost":30,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_card_meta_v2(id,definition) values ('10519','{"class":"WIND","gender":"MALE","MOR":16,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$-- END GENERATED PHASE2 STORY

create or replace function public._clear_enabled_v2(m text) returns boolean language sql stable security definer
set search_path=pg_catalog,public,pg_temp as $$ select coalesce((select enabled from public.battle_policy_v2 where mode=case when m='tower_sweep' then 'tower' else m end),false) $$;$vr_statement$;
  execute $vr_statement$create or replace function public._clear_access_v2(u uuid,m text,t text) returns boolean language sql stable security definer
set search_path=pg_catalog,public,pg_temp as $$
 select exists(select 1 from public.battle_clear_receipts_v2 where user_id=u and mode=m and target=t)
 or case when m='story' then coalesce((select cleared->split_part(t,':',1) @> to_jsonb(split_part(t,':',2)::int) from public.battle_legacy_access_v2 where user_id=u),false)
 when m='tower' then coalesce((select (tower_best->>split_part(t,':',1))::int >= split_part(t,':',2)::int from public.battle_legacy_access_v2 where user_id=u),false)
 else exists(select 1 from public.arcade_tut_claims where user_id=u and stage=t::int) end
$$;$vr_statement$;
  execute $vr_statement$create or replace function public._clear_grant_v2(u uuid,rw jsonb,kind text,ref_ text) returns jsonb language plpgsql security definer
set search_path=pg_catalog,public,pg_temp as $$
declare prior public.reward_claims; res jsonb:='{}'; k text; v jsonb; w jsonb; tk int; g jsonb;
begin
 if kind not in ('tutorial_v2','chapter_v2','star_v2','tower_v2') then raise exception 'invalid grant kind'; end if;
 for k,v in select * from jsonb_each(rw) loop
  if k not in ('gold','blood','shard','soul','gem','tickets') or jsonb_typeof(v)<>'number' or v::text !~ '^[0-9]+$' or v::numeric>2147483647 then raise exception 'invalid reward'; end if;
 end loop;
 perform pg_advisory_xact_lock(hashtext('gem:'||u::text));
 select * into prior from public.reward_claims where user_id=u and reward_kind=kind and source_or_period=ref_;
 if found then return prior.result; end if;
 insert into public.reward_claims(user_id,reward_kind,source_or_period,reward,rule_version) values(u,kind,ref_,rw,3);
 w:=rw-'gem'-'tickets'; if w<>'{}' then res:=res||jsonb_build_object('wallet',public._wallet_add(u,w,kind)); end if;
 if coalesce((rw->>'gem')::int,0)>0 then
  g:=public._gem_add(u,(rw->>'gem')::int,0,kind,'p2:'||ref_,jsonb_build_object('validation','plausibility-v3'));
  res:=res||jsonb_build_object('gem',g->'gem');
 end if;
 if coalesce((rw->>'tickets')::int,0)>0 then
  insert into public.story_gacha(user_id,last_draw) values(u,public._gem_day()-1) on conflict do nothing;
  update public.story_gacha set tickets=tickets+(rw->>'tickets')::int,updated_at=now() where user_id=u returning tickets into tk;
  res:=res||jsonb_build_object('tickets',tk);
 end if;
 res:=res||jsonb_build_object('gave',rw);
 update public.reward_claims set result=res where user_id=u and reward_kind=kind and source_or_period=ref_;
 return res;
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._clear_session_v2(s public.battle_sessions_v2) returns jsonb language sql stable security definer
set search_path=pg_catalog,public,pg_temp as $$
 select jsonb_build_object('ok',true,'session',s.id,'mode',s.mode,'target',s.target,'seed',s.seed,
 'rule_version',3,'validation','plausibility-v3','issued_at',s.issued_at,'expires_at',s.expires_at,
 'status',s.status,'min_seconds',(s.snapshot->>'min_seconds')::numeric,'snapshot',s.snapshot,
 'data',case when s.mode='story' then (select data from public.story_progress where user_id=s.user_id) else null end)
$$;$vr_statement$;
  execute $vr_statement$create or replace function public._clear_close_v2(s public.battle_sessions_v2,st text) returns void language plpgsql security definer
set search_path=pg_catalog,public,pg_temp as $$
declare d jsonb;
begin
 if s.status<>'issued' then return; end if;
 if s.mode='story' then
  d:=public._story_lock(s.user_id);
  if d->'battle'->>'session'=s.id::text then perform public._phase2_old_story_abort_phase(); end if;
 end if;
 update public.battle_sessions_v2 set status=st,finished_at=clock_timestamp() where id=s.id and status='issued';
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.battle_session_start_v2(p_mode text,p_target text,p_party jsonb,p_request uuid) returns jsonb
language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare u uuid:=auth.uid(); s public.battle_sessions_v2; old public.battle_sessions_v2; cfg jsonb; d jsonb; variant_ text;
 ch int; ph int; fl int; tw text; r public.tower_progress; cards jsonb:='[]'; o jsonb; x text; cid text; ids text[]:='{}';
 forced jsonb; allowed jsonb; pp jsonb; v text; snap jsonb; cost int:=0; mana_ int; seed_ int; min_ numeric; lv int; max_ int;
begin
 if u is null then raise exception 'login required'; end if;
 if p_mode is null or not public._clear_enabled_v2(p_mode) then raise exception 'reward verification pending'; end if;
 if p_target is null or length(p_target)>40 or p_request is null or jsonb_typeof(p_party) is distinct from 'array'
 or jsonb_array_length(p_party)>10 or octet_length(p_party::text)>2048
 or exists(select 1 from jsonb_array_elements(p_party) a where jsonb_typeof(a)<>'string') then raise exception 'invalid battle request'; end if;
 perform pg_advisory_xact_lock(hashtext('battle-v2:'||u::text));
 perform pg_advisory_xact_lock(hashtext('gem:'||u::text));
 select * into s from public.battle_sessions_v2 where user_id=u and request_id=p_request for update;
 if found then
  if s.mode<>p_mode or s.target<>p_target or s.party<>p_party then raise exception 'request conflict'; end if;
  if s.status='issued' and s.expires_at<=clock_timestamp() then perform public._clear_close_v2(s,'expired'); select * into s from public.battle_sessions_v2 where id=s.id; end if;
  return public._clear_session_v2(s);
 end if;
 if (select count(*) from public.battle_sessions_v2 where user_id=u and issued_at >= (public._gem_day()::timestamp at time zone 'Asia/Seoul'))>=500 then raise exception 'session issuance limit'; end if;
 insert into public.battle_legacy_access_v2(user_id) values(u) on conflict do nothing;
 -- Starting a different battle replaces/refunds an unfinished story battle exactly
 -- as before; the old token becomes unusable. Reissued stage keeps the same seed.
 for old in select * from public.battle_sessions_v2 where user_id=u and status='issued' for update loop
  perform public._clear_close_v2(old,case when old.expires_at<=clock_timestamp() then 'expired' else 'aborted' end);
 end loop;
 d:=public._story_lock(u); lv:=(public._player_sync(u)).level;
 if p_mode='tutorial' then
  if p_target!~'^[1-3]$' or p_party<>'[]' then raise exception 'invalid tutorial stage or party'; end if;
  ph:=p_target::int;
  if ph>1 and not public._clear_access_v2(u,'tutorial',(ph-1)::text) then raise exception 'previous tutorial first'; end if;
  select definition into cfg from public.battle_tutorial_defs_v2 where stage=ph;
  min_:=3;
 elsif p_mode='story' then
  if p_target!~'^(0|[1-9][0-9]?):[1-9][0-9]?$' then raise exception 'invalid story target'; end if;
  ch:=split_part(p_target,':',1)::int; ph:=split_part(p_target,':',2)::int;
  select definition into cfg from public.battle_story_defs_v2 where chapter=ch and phase=ph and variant='';
  if cfg is null then raise exception 'invalid phase'; end if;
  variant_:=case cfg->>'variantKind' when 'starter' then d->>'starter' when 'route' then d->'routes'->>ch::text else '' end;
  if coalesce(variant_,'')<>'' then select definition into cfg from public.battle_story_defs_v2 where chapter=ch and phase=ph and variant=variant_; end if;
  if cfg is null then raise exception 'invalid story variant'; end if;
  if exists(select 1 from public.story_phase_config c where (c.chapter<ch or(c.chapter=ch and c.phase<ph)) and (c.chapter<>0 or ch=0)
   and not public._clear_access_v2(u,'story',c.chapter::text||':'||c.phase::text)) then raise exception 'phase locked'; end if;
  if cfg->>'variantKind' in ('starter','route') and coalesce(variant_,'')='' then raise exception 'story variant required'; end if;
  pp:=coalesce(cfg->'party','{}'); forced:=coalesce(pp->'forced','[]');
  allowed:=forced||coalesce(pp->'guests','[]')||coalesce(cfg->'loan','[]')||coalesce(cfg->'reserve','[]');
  min_:=public._story_min_battle_secs();
  max_:=case when coalesce((cfg->>'tutorial')::boolean,false) and not coalesce((cfg->>'pool')::boolean,false) then 5 else 10 end;
  if coalesce((pp->>'solo')::boolean,false) then max_:=greatest(1,jsonb_array_length(forced)); end if;
  max_:=least(max_,coalesce((pp->>'max')::int,max_));
  if jsonb_array_length(p_party) not between 1 and max_ then raise exception 'party size'; end if;
 else
  if p_target!~'^(normal|wind|ice|fire|light|dark):[1-9][0-9]{0,2}$' then raise exception 'invalid tower target'; end if;
  tw:=split_part(p_target,':',1); fl:=split_part(p_target,':',2)::int;
  r:=public._tower_row(u,tw); perform public._tower_gate(u,tw,r);
  if fl>public._tower_max_floor(tw) or (fl>1 and not public._clear_access_v2(u,'tower',tw||':'||(fl-1)::text)) then raise exception 'floor locked'; end if;
  if p_mode='tower_sweep' and (fl%10=0 or fl<>r.best_floor+1) then raise exception 'boss floor or stale sweep'; end if;
  if jsonb_array_length(p_party) not between 1 and 5 then raise exception 'party size'; end if;
  cfg:=jsonb_build_object('tower',tw,'floor',fl); min_:=case when p_mode='tower_sweep' then public._quest_sweep_secs() else public._quest_min_secs() end;
 end if;
 if p_mode<>'tutorial' then
  for x in select jsonb_array_elements_text(p_party) loop
   o:=null;
   if x like 'guest:lend:%' then
    select jsonb_build_object('uid',x,'id',card_id,'guest',true,'level',snap->'level','loan',snap) into o from public.guild_loans
     where borrower=u and id::text=substr(x,12) and expires_at>now();
   elsif x like 'guest:%' then
    cid:=substr(x,7);
    if p_mode<>'story' or not allowed @> to_jsonb(cid) then raise exception 'guest not allowed'; end if;
    o:=jsonb_build_object('uid',x,'id',cid,'guest',true,'level',coalesce((pp->'fixedLevel'->>cid)::int,(pp->'levels'->>cid)::int,lv));
   else o:=public._pvp_snap(u,jsonb_build_array(x),'open')->'cards'->0;
   end if;
   if o is null then raise exception 'card not owned or loan expired'; end if;
   cid:=o->>'id';
   if p_mode='story' and not forced @> to_jsonb(cid) and not coalesce(pp->'guests','[]') @> to_jsonb(cid) then
    if coalesce((pp->>'solo')::boolean,false) or coalesce((pp->>'noExtra')::boolean,false) or coalesce(pp->'exclude','[]') @> to_jsonb(cid)
      or (pp ? 'only' and not pp->'only' @> to_jsonb(cid)) then raise exception 'party restriction'; end if;
    select definition into snap from public.battle_card_meta_v2 where id=cid;
    if (coalesce((pp->>'noMale')::boolean,false) and snap->>'gender'='MALE')
      or (coalesce((pp->>'noFemale')::boolean,false) and snap->>'gender'='FEMALE')
      or (pp ? 'maxMor' and (snap->>'MOR')::numeric > (pp->>'maxMor')::numeric)
      or (pp ? 'costBelow' and (snap->>'cost')::numeric >= (pp->>'costBelow')::numeric)
      or (pp ? 'onlyClass' and snap->>'class'<>pp->>'onlyClass')
      or coalesce(pp->'banClass','[]') @> to_jsonb(snap->>'class')
      or (pp ? 'maxGrade' and array_position(array['NORMAL','RARE','HIGH RARE','SUPER RARE','ULTRA RARE','MYTHIC RARE','LEGENDARY RARE'],snap->>'grade') > array_position(array['NORMAL','RARE','HIGH RARE','SUPER RARE','ULTRA RARE','MYTHIC RARE','LEGENDARY RARE'],pp->>'maxGrade'))
      then raise exception 'party restriction'; end if;
   end if;
   if cid=any(ids) then raise exception 'duplicate card'; end if;
   ids:=ids||cid; cards:=cards||jsonb_build_array(o);
   if p_mode like 'tower%' and tw<>'normal' and not exists(select 1 from public.battle_card_meta_v2 where id=cid and definition->>'class'=upper(tw)) then raise exception 'tower element'; end if;
  end loop;
  if p_mode='story' then
   for v in select jsonb_array_elements_text(forced) loop if not v=any(ids) then raise exception 'required card missing'; end if; end loop;
   -- Reserve cards are server-defined participants, never arbitrary XP targets.
   for v in select jsonb_array_elements_text(coalesce(cfg->'reserve','[]')) loop
    select o0 into o from jsonb_array_elements(public._story_owned(d)) o0 where o0->>'id'=v order by (o0->>'uid'=d->>'leader') desc nulls last,coalesce((o0->>'ex')::int,0) desc,coalesce((o0->>'level')::int,1) desc limit 1;
    if o is not null and not v=any(ids) then cards:=cards||jsonb_build_array(public._pvp_snap(u,jsonb_build_array(o->>'uid'),'open')->'cards'->0); end if;
   end loop;
   d:=public._phase2_old_story_start_phase(ch,ph); cost:=coalesce((d->'battle'->>'stamina')::int,0);
   if not coalesce((cfg->>'tutorial')::boolean,false) or coalesce((cfg->>'pool')::boolean,false) then
    mana_:=coalesce((cfg->>'mana')::int,80+15*ch+2*lv+case when cfg->>'type'='boss' then 40 else 0 end+coalesce((cfg->>'manaBonus')::int,0));
   end if;
  end if;
 end if;
 insert into public.battle_session_seeds_v2(user_id,mode,target,seed) values(u,p_mode,p_target,1+floor(random()*2147483646)::int) on conflict do nothing;
 select seed into seed_ from public.battle_session_seeds_v2 where user_id=u and mode=p_mode and target=p_target and rule_version=3;
 snap:=jsonb_build_object('stage',cfg,'cards',cards,'player_level',lv,'starter',d->'starter','leader',d->'leader','cost',cost,'mana',mana_,'min_seconds',min_);
 insert into public.battle_sessions_v2(user_id,request_id,mode,target,party,seed,snapshot) values(u,p_request,p_mode,p_target,p_party,seed_,snap) returning * into s;
 if p_mode='story' then perform public._story_save(u,jsonb_set(d,'{battle,session}',to_jsonb(s.id::text))); end if;
 if p_mode like 'tower%' then insert into public.battle_events_v2(session_id,user_id,mode,win,skills,day,week) values(s.id,u,'tower',false,0,public._gem_day(),public._weekly_week()); end if;
 return public._clear_session_v2(s);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.arcade_tut_status() returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,pg_temp as $$
declare u uuid:=auth.uid(); begin
 if u is null then raise exception 'login required'; end if;
 return jsonb_build_object('ok',true,'reward_held',not public._clear_enabled_v2('tutorial'),
 'claimed',coalesce((select jsonb_agg(stage order by stage) from public.arcade_tut_claims where user_id=u),'[]'),
 'completed',coalesce((select jsonb_agg(target::int order by target::int) from public.battle_clear_receipts_v2 where user_id=u and mode='tutorial'),'[]'),
 'rewards',jsonb_build_object('1',public._arcade_tut_rw(1),'2',public._arcade_tut_rw(2),'3',public._arcade_tut_rw(3)));
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.arcade_tut_claim(p_stage int) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare u uuid:=auth.uid(); rw jsonb:=public._arcade_tut_rw(p_stage); r jsonb; k text; n int;
begin
 if u is null then raise exception 'login required'; end if;
 perform pg_advisory_xact_lock(hashtext('battle-v2:'||u::text)); perform pg_advisory_xact_lock(hashtext('gem:'||u::text));
 if rw is null then raise exception 'invalid tutorial stage'; end if;
 k:=rw->>'kind'; n:=(rw->>'n')::int;
 if exists(select 1 from public.arcade_tut_claims where user_id=u and stage=p_stage) then return jsonb_build_object('ok',true,'already',true,'stage',p_stage,'kind',k); end if;
 if not public._clear_enabled_v2('tutorial') then raise exception 'reward verification pending'; end if;
 if not exists(select 1 from public.battle_clear_receipts_v2 where user_id=u and mode='tutorial' and target=p_stage::text) then raise exception 'verified tutorial session required'; end if;
 r:=public._clear_grant_v2(u,jsonb_build_object(k,n),'tutorial_v2','arcade_tut:'||p_stage);
 insert into public.arcade_tut_claims(user_id,stage,tickets,kind) values(u,p_stage,n,k);
 return r||jsonb_build_object('ok',true,'kind',k,'stage',p_stage,'gave',n);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._story_ticket_sync(uid uuid) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare ch int; got int[]; added int:=0; chapters jsonb:='[]'; rw jsonb; r jsonb; tk int;
begin
 if uid is null then raise exception 'login required'; end if;
 perform pg_advisory_xact_lock(hashtext('gem:'||uid::text));
 insert into public.story_gacha(user_id,last_draw) values(uid,public._gem_day()-1) on conflict do nothing;
 select ticket_chapters into got from public.story_gacha where user_id=uid for update;
 if public._clear_enabled_v2('story') then
 for ch in select chapter from public.story_phase_config c group by chapter having bool_and(exists(
  select 1 from public.battle_clear_receipts_v2 v where v.user_id=uid and v.mode='story' and v.target=c.chapter::text||':'||c.phase::text)) order by chapter loop
  if exists(select 1 from public.reward_claims where user_id=uid and reward_kind='chapter_v2' and source_or_period='chapter:'||ch) then continue; end if;
  rw:=jsonb_build_object('tickets',case when ch=any(got) then 0 else 10 end,'gem',case when exists(
   select 1 from public.gem_ledger where user_id=uid and ref='chapter:'||ch) then 0 else public._gem_chapter_reward() end);
  r:=public._clear_grant_v2(uid,rw,'chapter_v2','chapter:'||ch);
  if not ch=any(got) then got:=got||ch; end if;
  added:=added+(rw->>'tickets')::int; chapters:=chapters||to_jsonb(ch);
 end loop; end if;
 update public.story_gacha set ticket_chapters=got where user_id=uid returning tickets into tk;
 return jsonb_build_object('tickets',tk,'added',added,'chapters',chapters,'reward_held',not public._clear_enabled_v2('story'));
end $$;$vr_statement$;

  insert into vr_staging_install.parts(part_no, bundle_hash, part_hash, project_ref, db_id)
  values (12, '1e7a91f656cb089116c27629c13947ec0c769796933ace7bb576f39ba0920d4e', 'e1a59d08a6876eb4743e8f93627ae2814b77481e40f7127f474ef8fd7c52251b', 'cuyqchmdcnsgzkwyclji', '7703759698107299042');
end $vr_install_part$;
commit;
select '12_install.sql: 완료 또는 이미 완료 (12/14)' as result;
