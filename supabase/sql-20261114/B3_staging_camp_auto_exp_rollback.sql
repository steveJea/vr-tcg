-- B3. 되돌리기 (스테이징 전용). camp_status 를 camp.sql 원본으로. 여러 번 실행해도 안전.
do $b3$
declare sid text; cur text;
begin
  select system_identifier::text into sid from pg_control_system();
  if sid is distinct from '7703759698107299042' then raise exception 'STOP: 스테이징 DB 가 아님 (system_identifier %)', sid; end if;
  if to_regprocedure('public.camp_claim()') is null or to_regprocedure('public._camp_json(uuid)') is null or to_regprocedure('public._camp_settle(uuid,integer,integer)') is null then
    raise exception 'STOP: 훈련소 함수(camp.sql·camp2.sql)가 없음'; end if;
  -- 줄끝(CRLF)만 다른 붙여넣기도 같은 본문으로 봄 (스테이징 camp_status 가 CRLF 로 들어가 있음: md5 b82026c8…)
  select md5(replace(prosrc, chr(13), '')) into cur from pg_proc where oid = to_regprocedure('public.camp_status()');
  if cur = '135e0269160bd3a2f9a500935bd3fef7' then raise notice 'camp_status already original'; return; end if;
  if cur is distinct from 'c4d0ab2c2d27d3f6ff62c0f6f78d7dd4' then raise exception 'STOP: camp_status 가 B1 버전도 원본도 아님 (md5 %). 덮어쓰지 않음', cur; end if;
  execute $fn$create or replace function public.camp_status() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('camp:' || uid::text));
  return _camp_json(uid);
end $$$fn$;
  revoke all on function public.camp_status() from public, anon;
  grant execute on function public.camp_status() to authenticated;
  raise notice 'camp_status restored';
end $b3$;
