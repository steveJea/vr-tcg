-- PRODUCTION 확인 (읽기 전용) · premium_pity_plus_pass_production.sql 적용 후 실행. ok = true 면 정상.
select
  (to_regclass('public.story_gacha') is not null
   and exists (select 1 from information_schema.columns where table_schema='public' and table_name='story_gacha' and column_name='pity_misses')
   and position('pity_misses' in coalesce((select prosrc from pg_proc where oid=to_regprocedure('public.story_ticket_draw(integer)')),''))>0
   and position($$'pity', 50$$ in coalesce((select prosrc from pg_proc where oid=to_regprocedure('public.story_tickets()')),''))>0
   and position('m >= 49' in coalesce((select prosrc from pg_proc where oid=to_regprocedure('public.story_ticket_draw(integer)')),''))>0
   and position('pity_misses' in coalesce((select prosrc from pg_proc where oid=to_regprocedure('public.story_daily_draw()')),''))=0
   and (select count(*) from public.story_premium_ur) = 11
   and (to_regclass('public.shop_products') is null or (select name from public.shop_products where sku='pass_2') is not distinct from '플러스 시즌패스')
  ) as ok,
  (select count(*) from public.story_premium_ur) as premium_ur_count,
  (select string_agg(id||' '||name, ', ' order by id) from public.story_premium_ur) as premium_ur_pool,
  (select name from public.shop_products where sku='pass_2') as pass_2_name;
