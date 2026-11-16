-- 읽기만 함. staging 전용. 시트 스탯/강북대장 엔진 해시 설치 후 한 줄 확인.
-- 기대: ok=true
select (
  (select system_identifier::text from pg_catalog.pg_control_system()) = '7703759698107299042'
  and (select engine_hash from public.pvp_policy_v3 where singleton) = 'e9f17af01d6a5798932f9cc068f98cbb7bf76552de1e0ea1dce92a7c292512de'
  and (select engine_hash from public.guildbattle_policy_v4 where singleton) = '40b95ca320f62733a9c962c26879e2f852620a35e16da88885f5528dc8bf9e63'
  and (select engine_hash from public.arcade_policy_v5 where singleton) = '671d143bb0b905b82bc2dffe02de890f3e33847787825f719cdec66ef8acc478'
  and (select engine_hash from public.battle_replay_policy_v6 where singleton) = 'a993d56d24f51588f5df75a3a77ccae8c93de8ed9ab2321c87ea85c7188ce3ba'
  and (select engine_hash from public.battle_replay_policy_v7 where singleton) = '74816d5202bbcb70ef240b866d6ae0a02cfa6440d7f916bf54d9c27ab67b7074'
) as ok;
