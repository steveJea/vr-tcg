-- STAGING 확인 (읽기 전용) · shop_v2_staging.sql 적용 후 실행. ok = true 면 정상. missing 에 빠진 항목 이름이 나옴.
with need(name) as (values
 ('public._shop_mail(uuid,jsonb,text,text,text)'),('public._shop_queue_sync(uuid)'),('public._shop_gear_roll(uuid)'),('public._shop_krw_guard()'),
 ('public._shop_paid_before(uuid,text)'),('public._shop_pass_refunded(uuid,text,integer)'),('public._shop_pass_mail_sync(uuid)'),
 ('public._mail_sync_base_pass_v1(uuid)'),('public._mail_msg_claim_base_pass_v1(bigint)'),('public._mail_clean_payload_base_pass_v1(jsonb)'),
 ('public.shop_status()'),('public.shop_buy(text)'),('public.shop_gem_buy(text,integer)'),('public.shop_gear_buy(integer)'),
 ('public.shop_pass_days()'),('public.mail_msg_claim(bigint)'),('public.mail_claim_all()')),
fn as (select name, to_regprocedure(name) oid from need),
missing as (select name from fn where oid is null
 union all select 'wrapper:_mail_sync' where position('shop-v2' in coalesce((select prosrc from pg_proc where oid=to_regprocedure('public._mail_sync(uuid)')),''))=0
 union all select 'wrapper:mail_msg_claim' where position('shop-v2' in coalesce((select prosrc from pg_proc where oid=to_regprocedure('public.mail_msg_claim(bigint)')),''))=0
 union all select 'wrapper:mail_claim_all' where position('shop-v2' in coalesce((select prosrc from pg_proc where oid=to_regprocedure('public.mail_claim_all()')),''))=0
 union all select 'grant:'||name from fn where oid is not null and name ~ '^public\.(shop_|mail_)' and not has_function_privilege('authenticated', oid, 'execute')
 union all select 'private:'||name from fn where oid is not null and name ~ '^public\._' and (has_function_privilege('anon', oid, 'execute') or has_function_privilege('authenticated', oid, 'execute'))
 union all select 'products' where (select count(*) from public.shop_products where active) <> 17
 union all select 'pass:'||sku from public.shop_products where sku in ('pass_1','pass_2','pass_3') and ((reward->>'days')::int <> 30 or payment_sku is not null or not active)
 union all select 'pass_names' where (select string_agg(name, '/' order by sku) from public.shop_products where sku in ('pass_1','pass_2','pass_3')) <> '프리미엄 시즌패스/스페셜 시즌패스/럭셔리 시즌패스'
 union all select 'packs' where (select string_agg(sku||'='||price_krw||':'||month_max||':'||reward::text, ',' order by sku) from public.shop_products where tab='pack' and active)
   <> 'level_1=22000:2:{"gold": 150000, "blood": 150000, "shard": 50000},prem_10=11000:3:{"tickets": 10},prem_25=33000:3:{"tickets": 25},prem_45=66000:2:{"tickets": 45},spec_10=11000:3:{"special_tickets": 10},spec_25=33000:3:{"special_tickets": 25},spec_45=66000:2:{"special_tickets": 45}'
 union all select 'old_packs_active' where exists (select 1 from public.shop_products where sku in ('ticket_10','ticket_45','ticket_160','ticket_220') and active)
 union all select 'popup' where (select count(*) from public.shop_products where tab='popup' and active and acct_max=1 and reward->>'card'='10325') <> 2
 union all select 'gem_items' where (select string_agg(sku||'='||price_gem, ',' order by sku) from public.shop_gem_items where active) <> 'gem_drink=100,gem_prem_ticket=150,gem_spec_ticket=150'
 union all select 'gear_grades' where (select string_agg(grade||'='||tier||':'||price_gem||':'||weight, ',' order by grade) from public.shop_gear_grades) <> 'HR=4:500:950,SR=5:1000:49,UR=6:5000:1'
 union all select 'queue_table' where to_regclass('public.shop_mail_queue') is null
 union all select 'rls' where exists (select 1 from pg_class where oid in (to_regclass('public.shop_mail_queue'),to_regclass('public.shop_gem_items'),to_regclass('public.shop_gem_log'),to_regclass('public.shop_gear_grades'),to_regclass('public.shop_gear_daily')) and not relrowsecurity)
)
select (select count(*) from missing) = 0 as ok, (select count(*) from missing) as missing_count, coalesce((select string_agg(name, ', ') from missing), '') as missing,
 (select count(*) from public.shop_products where active) as active_products;
