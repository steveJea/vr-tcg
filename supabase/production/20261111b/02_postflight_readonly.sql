-- 운영 후속 20261111b 설치 후 읽기 전용 확인. 모두 true 여야 함.
select exists(select 1 from vr_rollout_private.releases where release_id='20261111b' and bundle_hash='c0898dcb7aa003ccbb9d2f0bdc79a1cac174f3fbe7ea8f7331f247366d2a9c9a') as ledger_ok,
 exists(select 1 from information_schema.columns where table_schema='public' and table_name='story_gacha' and column_name='ur_tickets') as ur_tickets_column_ok,
 exists(select 1 from information_schema.columns where table_schema='public' and table_name='mail_broadcast' and column_name='existing_only') as existing_only_ok,
 public._mail_clean_payload('{"ur_tickets":1}') = '{"ur_tickets":1}'::jsonb as payload_ok,
 to_regprocedure('public.story_ur_ticket_draw()') is not null and to_regprocedure('public.story_ur_tickets()') is not null as rpc_ok,
 not has_function_privilege('anon','public.story_ur_ticket_draw()','execute') as anon_blocked_ok,
 (select count(*) from pg_proc where pronamespace='public'::regnamespace and proname='admin_mail_broadcast')=1 as one_broadcast_fn_ok,
 (select count(*) from public.story_premium_ur w join public.story_card_pool p on p.id=w.id and p.grade='ULTRA RARE')=11 as ur_pool_11_ok;
