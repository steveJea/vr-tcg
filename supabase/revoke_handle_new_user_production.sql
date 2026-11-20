-- PRODUCTION ONLY (htarwisgkkphutxxnuak).
-- handle_new_user() · matches_rate_limit() 는 트리거 전용 함수라 클라이언트 EXECUTE 가 필요 없습니다.
-- REVOKE 해도 트리거는 그대로 동작합니다. 여러 번 실행해도 안전. 삭제 없음.
begin;
do $guard$
begin
  if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7692130048193495360' then
    raise exception 'STOP: revoke is production htarwisgkkphutxxnuak only; staging forbidden';
  end if;
  if to_regprocedure('public.handle_new_user()') is null or to_regprocedure('public.matches_rate_limit()') is null then
    raise exception 'STOP: handle_new_user() 또는 matches_rate_limit() 가 없습니다';
  end if;
end $guard$;
revoke execute on function public.handle_new_user() from public, anon, authenticated;
revoke execute on function public.matches_rate_limit() from public, anon, authenticated;
commit;
