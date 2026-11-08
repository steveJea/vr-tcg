-- READ ONLY. Run in production SQL Editor AFTER 01_install, before main merge.
select * from vr_rollout_private.releases where release_id='20261108'; -- exactly one completed row
select 'pvp' as engine,engine_hash,enabled,engine_hash='5a38b4b72651fcb8632fb1bfe14e1cd18a758d08249dbb18b0cfd223123c7a67' as hash_ok from public.pvp_policy_v3
union all select 'guildbattle',engine_hash,enabled,engine_hash='c570973669776971316dfb650482e1401c5628c5ba73e57d23b879b9320c719a' from public.guildbattle_policy_v4
union all select 'arcade',engine_hash,enabled,engine_hash='e792c491ffafe19d047aa6f58db1920e5767e4059e14816611dd38d473871161' from public.arcade_policy_v5;
-- All values must be true. These do not grant/revoke anything.
select not exists(select 1 from pg_proc p where pronamespace='public'::regnamespace and p.prosecdef and left(proname,1)='_' and pg_get_function_result(oid)<>'trigger' and (has_function_privilege('anon',oid,'execute') or has_function_privilege('authenticated',oid,'execute'))) as internal_functions_closed,
       to_regclass('public.guildbattle_test_clock_v4') is null and to_regclass('public.guildbattle_test_refills_v4') is null as no_staging_fixtures,
       not has_table_privilege('authenticated','public.matches','insert') as raw_arcade_write_closed,
       public._tower_min_level('wind')=25 and public._tower_min_level('light')=40 and public._player_unlock_level('chapter_3')=1 as unlock_levels_ok;
select public._unlock_levels() as menu_levels;
