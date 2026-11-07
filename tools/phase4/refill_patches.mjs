// Narrow, deterministic replacements of SIX budget consumers, not gameplay/reward rules.
export const refillPatches=[
 ['_raid_status_v4()',"'attempts_left', greatest(0, (N->>'attempts_per_day')::int - used-(select count(*) from guild_raid_attempts where user_id=uid and day=_raid_day_v4()))","'attempts_left', greatest(0, (N->>'attempts_per_day')::int - _guildbattle_used_v4(uid,'raid'))"],
 ['_war_status_v4()',"select count(*) into used from war_attacks_v4 where match_id = mt.id and user_id = uid;","used := _guildbattle_used_v4(uid,'war',mt.id);"],
 ['_raid_start_v4(jsonb)',"(select count(*) from guild_raid_attempts_v4 where user_id = uid and day = _raid_day_v4())","_guildbattle_used_v4(uid,'raid')"],
 ['_war_start_v4(integer,integer)',"(select count(*) from war_attacks_v4 where match_id = mt.id and user_id = uid)+(select count(*) from war_attacks legacy_attempt join war_matches legacy_match on legacy_match.id=legacy_attempt.match_id where legacy_attempt.user_id=uid and legacy_match.season=s and legacy_match.day=d)","_guildbattle_used_v4(uid,'war',mt.id)"],
 ['guildbattle_start_v4(text,jsonb,uuid,text,text)',"(select count(*) from guild_raid_attempts where user_id=u and day=_raid_day_v4())+(select count(*) from guild_raid_attempts_v4 where user_id=u and day=_raid_day_v4())","_guildbattle_used_v4(u,'raid')"],
 ['raid_sweep_v4(uuid)',"(select count(*) from guild_raid_attempts where user_id=u and day=_raid_day_v4())+(select count(*) from guild_raid_attempts_v4 where user_id=u and day=_raid_day_v4())","_guildbattle_used_v4(u,'raid')"],
];
