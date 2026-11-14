-- STAGING · 시즌패스 우편 설치 확인 (읽기 전용, SELECT 1개). 기대값: ok=true, 나머지 0 / true.
with s as (select public._shop_day() today),
w as (select (select count(*) from pg_proc where oid in (to_regprocedure('public._mail_sync(uuid)'),to_regprocedure('public.mail_msg_claim(bigint)'),to_regprocedure('public._mail_clean_payload(jsonb)'))
        and position('-- pass-mail-wrapper' in replace(prosrc,chr(13),''))>0) wrapped,
      (select count(*) from pg_proc where oid in (to_regprocedure('public._mail_sync_base_pass_v1(uuid)'),to_regprocedure('public._mail_msg_claim_base_pass_v1(bigint)'),to_regprocedure('public._mail_clean_payload_base_pass_v1(jsonb)'))) bases),
days as (select sp.user_id, sp.sku, sp.seq, x::date d from public.shop_passes sp, s,
         generate_series(sp.starts_on, least(sp.ends_on, s.today, coalesce(sp.revoked_on-1, s.today)), interval '1 day') x where sp.starts_on<=s.today
           and not exists (select 1 from public.payment_orders o where o.user_id=sp.user_id and o.product_id=sp.sku and o.receipt->>'seq'=sp.seq::text and o.cancel_status='refunded')),
k as (select d.*, exists(select 1 from public.shop_pass_claims c where (c.user_id,c.sku,c.seq,c.day)=(d.user_id,d.sku,d.seq,d.d)) direct,
        (select count(*) from public.player_mail m where m.user_id=d.user_id and m.pass_key='pass:'||d.sku||':'||d.seq||':'||d.d) mails from days d)
select jsonb_build_object(
 'ok', (select system_identifier::text from pg_catalog.pg_control_system())='7703759698107299042' and w.wrapped=3 and w.bases=3
   and to_regclass('public.player_mail_pass_uniq') is not null and to_regprocedure('public.mail_claim_all()') is not null
   and to_regprocedure('public.admin_shop_pass_revoke(text)') is not null
   and (select count(*) from k where direct and mails>0)=0 and (select count(*) from k where mails>1)=0
   and (select count(*) from public.player_mail where pass_key is not null and expires_at<>'infinity')=0,
 'staging', (select system_identifier::text from pg_catalog.pg_control_system())='7703759698107299042',
 'wrapped_3', w.wrapped, 'base_3', w.bases, 'unique_index', to_regclass('public.player_mail_pass_uniq') is not null,
 'pass_mails', (select count(*) from public.player_mail where pass_key is not null),
 'pass_mails_unclaimed', (select count(*) from public.player_mail where pass_key is not null and claimed_at is null),
 'days_elapsed', (select count(*) from k), 'days_direct_claimed', (select count(*) from k where direct),
 'days_not_mailed_yet_0', (select count(*) from k where not direct and mails=0),
 'double_grant_0', (select count(*) from k where direct and mails>0), 'dup_mail_0', (select count(*) from k where mails>1),
 'expiring_pass_mail_0', (select count(*) from public.player_mail where pass_key is not null and expires_at<>'infinity'),
 'today_kst', (select today from s)) as check_result
from w;
