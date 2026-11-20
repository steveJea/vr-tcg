-- 읽기만 함. production 전용. arcade_mvp_gallery_production.sql 실행 후 한 줄 확인. 기대: ok=true, missing=0
select ((select system_identifier::text from pg_catalog.pg_control_system()) = '7692130048193495360'
  and to_regclass('public.arcade_gallery_v5') is not null
  and position('_arcade_gallery_v5' in pg_get_functiondef(to_regprocedure('public._arcade_close_v5(public.arcade_sessions_v5,jsonb,jsonb)'))) > 0
  and position('arcade_gallery_v5' in pg_get_functiondef(to_regprocedure('public._gallery_have(uuid)'))) > 0
  and not has_function_privilege('authenticated', 'public._arcade_gallery_v5(bigint,uuid,jsonb)', 'execute')
  and not has_table_privilege('authenticated', 'public.arcade_gallery_v5', 'select')
  and (select count(*) from public.arcade_records_v5 r join public.reward_card_catalog c on c.card_id = r.mvp_id
       where r.verified and r.result = 'win' and exists (select 1 from auth.users u where u.id = r.user_id)
         and not exists (select 1 from public.arcade_gallery_v5 a where a.session_id = r.session_id)) = 0) as ok,
  (select count(*) from public.arcade_records_v5 r join public.reward_card_catalog c on c.card_id = r.mvp_id
   where r.verified and r.result = 'win' and exists (select 1 from auth.users u where u.id = r.user_id)
     and not exists (select 1 from public.arcade_gallery_v5 a where a.session_id = r.session_id))::int as missing,
  (select count(*) from public.arcade_gallery_v5)::int as registered;
