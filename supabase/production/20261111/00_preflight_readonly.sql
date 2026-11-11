-- READ-ONLY preflight for production release 20261111. Run in the production SQL Editor; changes nothing.
-- 1) Must be 7692130048193495360. If not: STOP.
select system_identifier::text as production_system_identifier, system_identifier::text='7692130048193495360' as pinned_ok from pg_control_system();
-- 2) Release ledger: 20261108 must exist; 20261111 must NOT exist yet.
select release_id, completed_at from vr_rollout_private.releases order by completed_at;
-- 3) Live engine hashes must equal release 20261108 values (all true).
select 'pvp_policy_v3' as policy, engine_hash='5a38b4b72651fcb8632fb1bfe14e1cd18a758d08249dbb18b0cfd223123c7a67' as ok, enabled from public.pvp_policy_v3;
select 'guildbattle_policy_v4' as policy, engine_hash='c570973669776971316dfb650482e1401c5628c5ba73e57d23b879b9320c719a' as ok, enabled from public.guildbattle_policy_v4;
select 'arcade_policy_v5' as policy, engine_hash='e792c491ffafe19d047aa6f58db1920e5767e4059e14816611dd38d473871161' as ok, enabled from public.arcade_policy_v5;
select to_regclass('public.battle_replay_policy_v6') is null and to_regclass('public.battle_replay_policy_v7') is null as phase67_not_installed_ok;
-- 4) Story CH15 already in production? Expect 16 phases. 0 means story_ch15.sql was never applied: STOP and tell the agent.
select count(*) as ch15_phases from public.story_phase_config where chapter=15;
select count(*) as ch16_17_phases_must_be_0 from public.story_phase_config where chapter in (16,17);
-- 5) Open battles (should be 0 or near 0 inside the maintenance window).
select mode, count(*) as open_sessions from public.battle_sessions_v2 where status='issued' and expires_at>now() group by 1;
-- 6) Drift: functions this release replaces vs the main baseline. differs_from_main_baseline should be 0;
--    otherwise someone hot-fixed production by hand: send the list before running 01_install.sql.
with expected(sig,src) as (values
 ('_daily_defs()','09d0b827131ac08fa986c8483af0227f'),
 ('_drink_json(uuid)','9fc21c2654a9637d0dede6008e71a5d7'),
 ('_dsp_fill(uuid,boolean)','b59d8c4cdaea12a9b6201b3f03a3847b'),
 ('_pvp_rating_v3(uuid,text,text,date)','d773e7bcb39d2aadeebfbd0119c10e0b'),
 ('_unlock_intros()','2be4f2bf11cc40cfd7ac75786f83d623'),
 ('_weekly_defs()','b476c2b85a51d82265a644d253aada85'),
 ('dispatch_start(integer,text[],integer)','c0599825f5a5da3d3720d01efa67f709'),
 ('drink_buy(text)','0dd4d939e82822b4ce587e9db6b30613'),
 ('pvp_rankings(text,text,date)','a38f26785cc0523b98fafa8820afcfb1'),
 ('pvp_user_info(text,text,integer)','db87a1436cb372b2b57d8974fc7c6020')
)
select count(*) filter (where e.src is not distinct from md5(p.prosrc)) as baseline_match, count(*) filter (where e.src is distinct from md5(p.prosrc)) as differs_from_main_baseline, string_agg(case when e.src is distinct from md5(p.prosrc) then e.sig end, ', ') as differs_list
from expected e left join pg_proc p on to_regprocedure(e.sig)=p.oid;
