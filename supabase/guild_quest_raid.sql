-- 조직 일일 의뢰 '보스 처치' → '균열 토벌' (레이드 보스). 진행도 = 균열 토벌 전투 1회마다 +1 (guild3.sql raid_finish 가 _guild_event(uid,'raid',1) 호출)
-- 여러 번 돌려도 안전. 오늘 이미 받은 의뢰도 다음 토벌부터 바로 반영 (진행도는 qkey → pool.event 로 셈)
update public.guild_quest_pool set event = 'raid', label = '균열 토벌', icon = '🐉' where key = 'd_boss';
-- 확인: select key, kind, event, label from public.guild_quest_pool where key = 'd_boss';
