-- 운영 후속 20261111b 읽기 전용 사전 점검. 운영 SQL Editor 에서 실행. 아무것도 바꾸지 않음.
-- 1) 7692130048193495360 이어야 함. 아니면 멈춤.
select system_identifier::text as production_system_identifier, system_identifier::text='7692130048193495360' as pinned_ok from pg_control_system();
-- 2) 배포 기록: 20261111 이 있어야 하고, 20261111b 는 아직 없어야 함.
select release_id, completed_at from vr_rollout_private.releases order by completed_at;
-- 3) 이번에 바꾸는 함수가 mail_v2.sql 원본과 같은지. differs_must_be_0 이 0 이 아니면 누가 운영에서 직접 고친 것 → 실행 전에 목록을 보내 주세요.
with expected(sig,src) as (values
 ('_mail_clean_payload(jsonb)','e012e11a2926c6ff2538c3110a908a7e'),
 ('_mail_sync(uuid)','1e7c35b12855d08008ebe7a15d6b69f4'),
 ('mail_msg_claim(bigint)','3429f085b2f8757fa990367d25f7fbe6'),
 ('admin_mail_broadcast(text,text,jsonb,integer)','62d8597bec375c87839543e818a55927'),
 ('admin_mail_broadcasts(integer)','6d64fed3850203290e87322c6a071a72')
)
select count(*) filter (where e.src is not distinct from md5(replace(p.prosrc, chr(13), ''))) as baseline_match, count(*) filter (where e.src is distinct from md5(replace(p.prosrc, chr(13), ''))) as differs_must_be_0, string_agg(case when e.src is distinct from md5(replace(p.prosrc, chr(13), '')) then e.sig end, ', ') as differs_list
from expected e left join pg_proc p on to_regprocedure(e.sig)=p.oid;
-- 4) UR 확정권 풀: 고급 소환 UR 11명이어야 함 (전부 ULTRA RARE).
select w.id, w.name, p.grade, p.grade='ULTRA RARE' as ur_ok from public.story_premium_ur w left join public.story_card_pool p on p.id=w.id order by w.id;
select count(*) as ur_pool_must_be_11 from public.story_premium_ur w join public.story_card_pool p on p.id=w.id and p.grade='ULTRA RARE';
-- 5) 아직 설치 전인지 (둘 다 false 가 정상. true 면 이미 설치됨)
select exists(select 1 from information_schema.columns where table_schema='public' and table_name='story_gacha' and column_name='ur_tickets') as ur_tickets_column, exists(select 1 from information_schema.columns where table_schema='public' and table_name='mail_broadcast' and column_name='existing_only') as existing_only_column;
select exists(select 1 from information_schema.columns where table_schema='public' and table_name='story_gacha_log' and column_name='kind') as gacha_log_kind_ok;
-- 6) 최근 전체 우편 (오늘 밤 재화 우편 확인용)
select id, title, payload, created_at, expires_at from public.mail_broadcast order by id desc limit 5;
