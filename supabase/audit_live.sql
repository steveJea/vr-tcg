-- =====================================================================
-- 실제 DB 점검 (읽기 전용 · select 만 · 쓰기/DDL 없음) — SQL Editor 에서 Run → 결과 표 전체를 복사해서 딩순이에게
-- 한 결과 표: flag(⚠ = 확인 필요) · kind · name · detail
--   fn    : public 함수마다 서버 권한(definer) 여부 · 본문 md5 앞 10자리 · anon/authenticated 실행 가능 여부
--           ⚠ = 서버 권한 내부(_) 함수를 anon/authenticated 가 실행 가능 · admin_ 함수를 anon 이 실행 가능 · anon 이 서버 권한 함수를 실행 가능
--   table : public 테이블마다 RLS 여부 · anon/authenticated 직접 쓰기(insert/update/delete) 권한 · 쓰기 정책 수
--           ⚠ = 직접 쓰기 권한이 있고 (RLS 꺼짐 또는 쓰기 정책 있음) → 앱에서 바로 쓸 수 있음
-- =====================================================================
with f as (
  select p.oid, p.proname, pg_get_function_identity_arguments(p.oid) args, p.prosecdef def, left(md5(p.prosrc), 10) h,
         has_function_privilege('anon', p.oid, 'execute') ax, has_function_privilege('authenticated', p.oid, 'execute') uxx
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.prokind = 'f'
    and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')   -- 확장 함수 제외
), t as (
  select c.oid, c.relname, c.relrowsecurity rls,
         has_table_privilege('anon', c.oid, 'insert') or has_table_privilege('anon', c.oid, 'update') or has_table_privilege('anon', c.oid, 'delete') aw,
         has_table_privilege('authenticated', c.oid, 'insert') or has_table_privilege('authenticated', c.oid, 'update') or has_table_privilege('authenticated', c.oid, 'delete') uw,
         (select count(*) from pg_policy po where po.polrelid = c.oid and po.polcmd in ('a', 'w', 'd', '*')) wpol
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind in ('r', 'p')
)
select flag, kind, name, detail from (
  select case when f.proname like '\_%' and f.def and (f.ax or f.uxx) then '⚠'      -- 서버 권한 내부 함수를 앱이 직접 부를 수 있음
              when f.proname like 'admin\_%' and f.ax then '⚠'                     -- 관리자 함수를 비로그인이 부를 수 있음
              when f.ax and f.def then '⚠' else '' end flag,                        -- 비로그인이 서버 권한 함수를 부를 수 있음 (의도한 것인지 확인)
         'fn' kind, f.proname || '(' || f.args || ')' name,
         (case when f.def then 'definer' else 'invoker' end) || ' ' || f.h || ' anon:' || (case when f.ax then 'Y' else 'n' end) || ' auth:' || (case when f.uxx then 'Y' else 'n' end) detail
  from f
  union all
  select case when (t.aw or t.uw) and (not t.rls or t.wpol > 0) then '⚠' else '' end, 'table', t.relname,
         'rls:' || (case when t.rls then 'Y' else 'n' end) || ' anon_write:' || (case when t.aw then 'Y' else 'n' end) || ' auth_write:' || (case when t.uw then 'Y' else 'n' end) || ' write_policies:' || t.wpol
  from t
) x
order by flag desc, kind, name;
