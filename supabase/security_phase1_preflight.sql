-- 읽기 전용: staging에서 먼저 실행해 결과 확인. 사용자 자료/키/토큰 조회 없음.
-- 적용 전에는 공개 지급 경로 목록, 적용 후에는 helpers ACL·raw writes를 확인.
begin read only;
select current_database() as database_name, now() at time zone 'Asia/Seoul' as checked_at_kst;
select p.oid::regprocedure as signature, p.prosecdef as security_definer,
  p.proconfig as settings,
  has_function_privilege('anon',p.oid,'execute') as anon_execute,
  has_function_privilege('authenticated',p.oid,'execute') as authenticated_execute,
  md5(pg_get_functiondef(p.oid)) as definition_hash
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.prokind='f' and
  (left(p.proname,1)='_' or p.proname ~ '(claim|reward|track|gallery|complete|report|finish|draw|ticket|buy|gem|wallet)')
order by p.proname, p.oid::regprocedure::text;
select t.table_name, t.grantee, t.privilege_type
from information_schema.role_table_grants t
where t.table_schema='public' and t.grantee in ('PUBLIC','anon','authenticated')
  and t.privilege_type <> 'SELECT'
order by t.table_name,t.grantee,t.privilege_type;
select table_name,column_name,grantee,privilege_type from information_schema.column_privileges
where table_schema='public' and grantee in ('PUBLIC','anon','authenticated') and privilege_type <> 'SELECT'
order by table_name,column_name,grantee;
select schemaname,tablename,policyname,roles,cmd,qual,with_check from pg_policies
where schemaname='public' order by tablename,policyname;
select event_object_table,trigger_name,action_statement from information_schema.triggers
where trigger_schema='public' order by event_object_table,trigger_name;
commit;
