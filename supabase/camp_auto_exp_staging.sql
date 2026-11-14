-- B1. 스테이징 전용 (디버그 57: 훈련소에 넣어 두면 훈련소를 열지 않아도 레벨이 오름)
-- 스테이징 SQL Editor 에서 이 파일 전체를 한 번에 실행. 여러 번 실행해도 안전 (두 번째부터는 'already installed' 알림만).
-- 바꾸는 것: camp_status() 하나. 받을 EXP 가 있으면 그 자리에서 camp_claim() 을 그대로 불러 정산.
--   · camp_status 는 로그인 2초 뒤 + 열려 있는 모든 화면에서 10분마다 이미 불리고 있음 → 훈련소를 안 열어도 반영
--   · 정산 로직·수치 그대로 (시간당 20 + 플레이어 Lv×1.5, 훈련소 Lv 보너스, 마지막 정산 뒤 최대 24시간, 상한 min(등급 최대, 플레이어 Lv−5))
--   · 테이블·데이터·다른 함수 변경 없음. pg_cron 안 씀 (README 참고: 전원 주기 정산은 24시간 한도를 없애는 밸런스 변경)
-- 지금 camp_status 가 repo(camp.sql) 본문과 다르면 아무것도 안 바꾸고 멈춤 (줄끝 CRLF/LF 차이는 무시: 내용 비교).
do $b1$
declare sid text; cur text;
begin
  select system_identifier::text into sid from pg_control_system();
  if sid is distinct from '7703759698107299042' then raise exception 'STOP: 스테이징 DB 가 아님 (system_identifier %)', sid; end if;
  if to_regprocedure('public.camp_claim()') is null or to_regprocedure('public._camp_json(uuid)') is null or to_regprocedure('public._camp_settle(uuid,integer,integer)') is null then
    raise exception 'STOP: 훈련소 함수(camp.sql·camp2.sql)가 없음'; end if;
  -- 줄끝(CRLF)만 다른 붙여넣기도 같은 본문으로 봄 (스테이징 camp_status 가 CRLF 로 들어가 있음: md5 b82026c8…)
  select md5(replace(prosrc, chr(13), '')) into cur from pg_proc where oid = to_regprocedure('public.camp_status()');
  if cur = 'c4d0ab2c2d27d3f6ff62c0f6f78d7dd4' then raise notice 'camp_status auto-exp already installed'; return; end if;
  if cur is distinct from '135e0269160bd3a2f9a500935bd3fef7' then raise exception 'STOP: camp_status 가 camp.sql 원본과 다름 (md5 %). 덮어쓰지 않음', cur; end if;
  execute $fn$create or replace function public.camp_status() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); j jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('camp:' || uid::text));
  j := _camp_json(uid);
  -- 57: 훈련소를 열지 않아도 쌓인 EXP 반영. 받을 EXP 가 있으면 camp_claim 그대로 실행 (같은 시간당 EXP · 같은 24시간 한도 · 같은 레벨 상한)
  if not exists (select 1 from jsonb_array_elements(coalesce(j->'slots', '[]'::jsonb)) x
                 where x->>'uid' is not null and coalesce((x->>'pending')::int, 0) > 0) then return j; end if;
  return public.camp_claim() || jsonb_build_object('auto', true);
end $$$fn$;
  revoke all on function public.camp_status() from public, anon;
  grant execute on function public.camp_status() to authenticated;
  raise notice 'camp_status auto-exp installed';
end $b1$;
