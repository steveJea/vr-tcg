-- READ-ONLY postflight for production release 20261111. Every check must be true / 0.
select release_id, completed_at from vr_rollout_private.releases where release_id in ('20261108','20261111') order by 1;
select (select engine_hash from public.pvp_policy_v3)='bef887c77a009121ae99301ca91db7d73a7bd9ce30d70e1ec7a18d10742cd16f' pvp_ok,
 (select engine_hash from public.guildbattle_policy_v4)='819b116c1e1ccd7d66ba589e3bc5e4e8d436a43ebf2dfe4543c250cbf5166cd0' guild_ok,
 (select engine_hash from public.arcade_policy_v5)='7c47d4ccb224c0cd7cf8ff9a11a465e68fd645510588249fabb6c8859a39663a' arcade_ok,
 (select engine_hash from public.battle_replay_policy_v6)='32f0e5059ddb994d56865b16054d64f3f2c1f389df672be4f113e13c5d4112c2' sweep_v6_ok,
 (select engine_hash from public.battle_replay_policy_v7)='0178e4a7e0fcdedce4815b75c2a9449782f93b3d7df1277d0943a532ff3659d2' direct_v7_ok,
 (select enabled from public.battle_replay_policy_v6)=false v6_off_ok, (select enabled from public.battle_replay_policy_v7)=false v7_off_ok;
select (select count(*) from public.story_phase_config where chapter=16)=12 ch16_ok, (select count(*) from public.story_phase_config where chapter=17)=15 ch17_ok,
 (select count(*) from public.battle_story_defs_v2 where chapter in (16,17))=27 ch16_17_defs_ok,
 (select count(*) from public.battle_card_meta_v2 where id in ('10511','10512','10513','10520','10521','10522','10523','10524','10525','10526','10527','10528','10529','10530','10531','10532'))=16 new_cards_ok,
 public._player_unlock_level('chapter_16')=1 and public._player_unlock_level('skill')=13 level_policy_kept_ok;
select count(*)=0 as no_public_internal_definer_ok from pg_proc p where p.pronamespace='public'::regnamespace and p.prosecdef and left(p.proname,1)='_' and pg_get_function_result(p.oid)<>'trigger' and (has_function_privilege('anon',p.oid,'execute') or has_function_privilege('authenticated',p.oid,'execute'));
select not has_function_privilege('anon','public.story_complete_scene(integer,integer)','execute') and has_function_privilege('authenticated','public.story_complete_scene(integer,integer)','execute') scene_acl_ok;
with expected(sig,src) as (values
 ('_daily_defs()','fb2540267d9d3c932dcafe90fd118ca6'),
 ('_drink_json(uuid)','070d68fa0b0890eef4d1bfc9eab5a577'),
 ('_dsp_fill(uuid,boolean)','bd17f7198258664605f83805a96dc3ad'),
 ('_pvp_rating_v3(uuid,text,text,date)','c8d73a37f47e02ff4772d4a74ddc61c9'),
 ('_unlock_intros()','46b0691d0652aaff5260b97d52271772'),
 ('_weekly_defs()','2a4f219894d5c4a00832d9e1f7619d79'),
 ('dispatch_start(integer,text[],integer)','ee7fe36509da754977ba6cee83cde36e'),
 ('drink_buy(text)','401f78de49d46dad279db5ee9901a600'),
 ('pvp_rankings(text,text,date)','ab839ce78be269d4e622cedb69a6d895'),
 ('pvp_user_info(text,text,integer)','547b5b63ebb32888760542074add403b')
)
select count(*) filter (where e.src is not distinct from md5(p.prosrc)) as target_match, count(*) filter (where e.src is distinct from md5(p.prosrc)) as mismatch_must_be_0, string_agg(case when e.src is distinct from md5(p.prosrc) then e.sig end, ', ') as mismatch_list
from expected e left join pg_proc p on to_regprocedure(e.sig)=p.oid;
