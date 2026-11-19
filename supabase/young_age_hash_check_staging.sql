-- 확인용 (읽기 전용): ok = true 면 정상
select (
  (select engine_hash from public.pvp_policy_v3 where singleton) = 'c5b478a735b1798bd7b9c51902ae85efe5ed861e9ab2936cecf753b4e250a648'
  and (select engine_hash from public.guildbattle_policy_v4 where singleton) = 'c87d5a678229e2bbc3bcd92ff3f9f4b8e32291df874a9919c4295b14831d7d07'
  and (select engine_hash from public.arcade_policy_v5 where singleton) = 'fc7c0deaec9781badc9adc4b6895bbc2bc39ffe42e51dc3ae4deab647790e063'
  and (select engine_hash from public.battle_replay_policy_v6 where singleton) = '1d1092662cfa90fd1c118baf7ffb4d83dcb767ef17564e30f9efdecfc3270bd7'
  and (select engine_hash from public.battle_replay_policy_v7 where singleton) = '2fbf41b3446cb61e5a66fd0ea80380d0fa77f644f26a5e1219ea70b91bf39a3a'
) as ok;
