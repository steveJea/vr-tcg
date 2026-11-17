-- 읽기만 함. staging 전용. fix_start_v2_level_floor_staging.sql 실행 후 한 줄 확인. 기대: ok=true
select (
  (select system_identifier::text from pg_catalog.pg_control_system()) = '7703759698107299042'
  and exists (select 1 from pg_catalog.pg_proc
    where oid = to_regprocedure('public.battle_session_start_v2(text,text,jsonb,uuid)')
      and prosrc like '%story floorLv (js/story.js partyOf)%'
      and prosrc like '%(cfg->''loanLevel''->>cid)::int end,(pp->''levels''->>cid)::int,lv)%'
      and prosecdef)
) as ok;
