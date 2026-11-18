-- 확인용 (읽기 전용, staging): ok = true 면 정상
select (select engine_hash from public.battle_replay_policy_v7 where singleton) = 'ca2183b100c223112f64c8d10496f9fdb676d7442bd7522faa2641287eee09b0' as ok;
