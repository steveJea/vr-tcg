-- A1. 운영 전용 · 읽기 전용 진단 (아무것도 바꾸지 않음). 운영 SQL Editor 에서 이 파일 전체를 한 번에 실행.
-- 결과는 표 1개: 운영 DB 가 아니면 'STOP' 한 줄만 나옴.
-- 각 우편 함수(같은 이름의 모든 버전 포함)의 지금 md5(prosrc) · mail_v2.sql 원본과 같은지 · 20261111b 설치 후 모습과 같은지 · 전체 정의(pg_get_functiondef)
-- + 참고 줄: 배포 기록, UR 확정권/기존 가입자만 칸이 이미 있는지
with g as (
  select system_identifier::text = '7692130048193495360' as ok from pg_control_system()
), expected(name, baseline_md5, target_md5) as (values
  ('_mail_clean_payload',   'e012e11a2926c6ff2538c3110a908a7e', 'eea4e559efcb9dc34db983fad49f9566'),
  ('_mail_sync',            '1e7c35b12855d08008ebe7a15d6b69f4', 'c661ffb0e154ba0bab4d7f0e389ee8a7'),
  ('mail_msg_claim',        '3429f085b2f8757fa990367d25f7fbe6', 'ec563b0f7f059c6672cbc625f6fa5da9'),
  ('admin_mail_broadcast',  '62d8597bec375c87839543e818a55927', '7ed9807fabc15786ba06b701bec05eb8'),
  ('admin_mail_broadcasts', '6d64fed3850203290e87322c6a071a72', '154086c754ced350f6a9e2d79a261ebe')
), fns as (
  select 1 as ord, 'function' as kind, e.name,
         coalesce(pg_get_function_identity_arguments(p.oid), '(없음)') as args,
         md5(p.prosrc) as md5_now,
         md5(p.prosrc) = e.baseline_md5 as same_as_mail_v2_baseline,
         md5(p.prosrc) = e.target_md5   as same_as_20261111b_target,
         -- 줄끝 CRLF 만 다른지 (스테이징 camp_status 가 이 경우였음)
         md5(replace(p.prosrc, chr(13), '')) = e.baseline_md5 as same_as_mail_v2_ignoring_crlf,
         md5(replace(p.prosrc, chr(13), '')) = e.target_md5   as same_as_20261111b_ignoring_crlf,
         -- 공백·줄바꿈만 다른지 (붙여넣기 때 줄끝/들여쓰기 변형 여부)
         md5(regexp_replace(p.prosrc, '\s+', '', 'g')) as md5_no_whitespace,
         length(p.prosrc) as src_len,
         pg_get_functiondef(p.oid) as definition
  from expected e left join pg_proc p on p.proname = e.name and p.pronamespace = 'public'::regnamespace
), ctx as (
  select 2, 'context', 'releases', '', null::text, null::boolean, null::boolean, null::boolean, null::boolean, null::text, null::int,
         (select string_agg(release_id || ' @ ' || completed_at::text, E'\n' order by completed_at) from vr_rollout_private.releases)
  union all
  select 3, 'context', 'columns', '', null::text, null::boolean, null::boolean, null::boolean, null::boolean, null::text, null::int,
         'story_gacha.ur_tickets=' || exists(select 1 from information_schema.columns where table_schema='public' and table_name='story_gacha' and column_name='ur_tickets')::text
         || E'\nmail_broadcast.existing_only=' || exists(select 1 from information_schema.columns where table_schema='public' and table_name='mail_broadcast' and column_name='existing_only')::text
         || E'\nfn ur_ticket_draw 있음=' || exists(select 1 from pg_proc where pronamespace='public'::regnamespace and proname like '%ur_ticket%')::text
)
select ord, kind, name, args, md5_now, same_as_mail_v2_baseline, same_as_20261111b_target, same_as_mail_v2_ignoring_crlf, same_as_20261111b_ignoring_crlf, md5_no_whitespace, src_len, definition
from (select * from fns union all select * from ctx) x
where (select ok from g)
union all
select 0, 'STOP', '운영 DB 가 아님 (system_identifier 7692130048193495360 아님)', '', null, null, null, null, null, null, null, null
where not (select ok from g)
order by 1, 3, 4;
