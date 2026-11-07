-- ⚠ 테스트 전용 13/13. 운영 실행 금지. 파일 전체를 번호 순서대로 실행.
-- 대상 프로젝트: cuyqchmdcnsgzkwyclji; 운영 htarwisgkkphutxxnuak 금지.
-- 완료한 파일은 다시 실행해도 건너뜀. 중간 오류는 해당 파일만 되돌아감.
-- 실제 project_ref는 SQL Editor가 보장해서 제공하지 않음: DB 고유번호를 대조.
-- 지정 테스트 DB의 식별번호와 일치할 때만 허용. guard 삭제/SET 우회 금지.
-- docs/STAGING.md 및 supabase/staging/README.md 먼저 확인.

begin;
do $vr_project_guard$
declare
  confirmed_ref text := 'cuyqchmdcnsgzkwyclji';
  expected_db_id text := '7703759698107299042';
  actual_db_id text;
begin
  if confirmed_ref is distinct from 'cuyqchmdcnsgzkwyclji' or confirmed_ref = 'htarwisgkkphutxxnuak' then
    raise exception 'STOP: 지정한 테스트 프로젝트만 허용합니다. 운영 DB 금지.';
  end if;
  if expected_db_id !~ '^[0-9]{16,20}$' then
    raise exception 'STOP: 테스트 DB의 실제 고유번호가 아직 등록되지 않았습니다. 안내 문서를 확인하세요.';
  end if;
  select system_identifier::text into actual_db_id from pg_catalog.pg_control_system();
  if actual_db_id is distinct from expected_db_id then
    raise exception 'STOP: 현재 접속한 DB가 지정된 테스트 DB와 다릅니다. 실행 금지.';
  end if;
exception when insufficient_privilege or undefined_function then
  raise exception 'STOP: DB 식별 조회 권한/기능이 없어 안전하게 중단합니다. guard를 삭제하지 마세요.';
end $vr_project_guard$;

-- 설치 기록은 API에서 접근할 수 없는 별도 스키마에 저장.
select pg_advisory_xact_lock(20261107, 490);
create schema if not exists vr_staging_install;
revoke all on schema vr_staging_install from public, anon, authenticated;
create table if not exists vr_staging_install.parts (
  part_no integer primary key, bundle_hash text not null, part_hash text not null,
  project_ref text not null, db_id text not null, applied_at timestamptz not null default now()
);
alter table vr_staging_install.parts enable row level security;
revoke all on vr_staging_install.parts from public, anon, authenticated;
set local check_function_bodies = off;

do $vr_install_part$
begin
  if exists (select 1 from vr_staging_install.parts where bundle_hash <> 'cc55a18ffb6e7f31c29402be300a5e256b333fd450277ae07e425819f76899c9' or project_ref <> 'cuyqchmdcnsgzkwyclji' or db_id <> '7703759698107299042') then
    raise exception 'STOP: 다른 버전/DB의 설치 기록입니다. 파일을 섞지 마세요.';
  end if;
  if exists (select 1 from vr_staging_install.parts where part_no = 13) then
    if not exists (select 1 from vr_staging_install.parts where part_no = 13 and part_hash = '548d48af1cf708bd545adda12f51a0b244ff6d2f45a04b23926d58da1241c37f') then
      raise exception 'STOP: 완료한 파일과 내용이 다릅니다.';
    end if;
    raise notice '13_install.sql: 이미 완료, 변경 없이 건너뜀';
    return;
  end if;
  if (select count(*) from vr_staging_install.parts where part_no < 13) <> 12 then
    raise exception 'STOP: 앞 번호 파일을 먼저 실행하세요 (13_install.sql).';
  end if;
  -- 설치 도중에는 클라이언트가 미완성 게임 스키마에 접근하지 못함. 마지막에만 개방.
  revoke usage on schema public from public, anon, authenticated;
  execute $vr_statement$create or replace function public.pvp_start_v3(p_league text,p_mode text,p_request uuid,p_control text,p_engine_hash text) returns jsonb language plpgsql security definer
set search_path=pg_catalog,public,pg_temp as $$
declare u uuid:=auth.uid(); n int:=public._pvp_ok(p_league,p_mode); season_ date:=public._pvp_season(); me public.pvp_ratings_v3;
 a public.pvp_attempts; s public.pvp_sessions_v3; old_ record; cand record; mine jsonb; osnap jsonb; opp uuid; oname text; orat int; used_ int;
 ex numeric; dw_ int; dl_ int; seed_ bigint;
begin
 if u is null then raise exception 'login required'; end if;
 if p_league is null or p_mode is null or p_request is null or p_control is null or p_control not in('auto','actions') then raise exception 'invalid request'; end if;
 if not exists(select 1 from public.pvp_policy_v3 where enabled and engine_hash=p_engine_hash) then raise exception 'PvP verifier unavailable'; end if;
 perform public._pvp_lock_v3(p_league,p_mode,season_);
 select * into s from public.pvp_sessions_v3 where user_id=u and request_id=p_request;
 if found then
  select * into a from public.pvp_attempts where id=s.id;
  if a.league<>p_league or a.mode<>p_mode or s.control<>p_control or s.engine_hash<>p_engine_hash then raise exception 'request conflict'; end if;
  return public._pvp_session_json_v3(a,s);
 end if;
 -- Explicitly starting another battle closes the prior one as a forfeit. One active per mode.
 for old_ in select a0.id from public.pvp_attempts a0 join public.pvp_sessions_v3 s0 using(id)
  where s0.user_id=u and s0.status='issued' and a0.league=p_league and a0.mode=p_mode loop
  select * into a from public.pvp_attempts where id=old_.id;
  -- Old seasons can no longer change ratings: reservation already final, only close the receipt.
  select * into s from public.pvp_sessions_v3 where id=old_.id;
  perform public._pvp_forfeit_v3(a,s);
 end loop;
 select count(*) into used_ from public.pvp_attempts where user_id=u and league=p_league and mode=p_mode and day=public._pvp_day();
 if used_>=10+public._pvp_extra(u,p_league,p_mode) then raise exception 'no attempts left'; end if;
 if exists(select 1 from public.pvp_attempts where user_id=u and league=p_league and mode=p_mode and created_at>clock_timestamp()-interval '2 seconds') then raise exception 'rate limited'; end if;
 mine:=public._pvp_decks_v3(u,p_league,p_mode);
 me:=public._pvp_rating_v3(u,p_league,p_mode,season_);
 for cand in select x.user_id,coalesce(r.rating,1000) rating from (
  select d.user_id from public.pvp_decks d where d.league=p_league and d.mode=p_mode and d.user_id<>u and d.slot>=0 and d.slot<n
  group by d.user_id having count(*)=n) x left join public.pvp_ratings_v3 r on r.user_id=x.user_id and r.league=p_league and r.mode=p_mode and r.season=season_
  order by abs(coalesce(r.rating,1000)-me.rating)+random()*60 limit 30 loop
  begin osnap:=public._pvp_decks_v3(cand.user_id,p_league,p_mode); opp:=cand.user_id; orat:=cand.rating; exit;
  exception when others then osnap:=null; end;
 end loop;
 if opp is null then
  select jsonb_agg((select jsonb_agg(c||jsonb_build_object('level',greatest(1,round(coalesce((c->>'level')::int,1)*0.9)::int),'boost','{}'::jsonb) order by ci)
   from jsonb_array_elements(dk) with ordinality t(c,ci)) order by di) into osnap from jsonb_array_elements(mine) with ordinality t(dk,di);
  oname:='봇'; orat:=me.rating;
 else select coalesce(nickname,'플레이어') into oname from public.profiles where id=opp; oname:=coalesce(oname,'플레이어'); end if;
 ex:=1/(1+power(10,(orat-me.rating)/400.0)); dw_:=greatest(1,round(32*(1-ex))::int); dl_:=greatest(1,round(32*ex)::int);
 if opp is null then dw_:=greatest(1,dw_/2); dl_:=greatest(1,dl_/2); end if;
 seed_:=floor(random()*2147483647)::bigint;
 insert into public.pvp_attempts(user_id,league,mode,season,day,opp_user,opp_name,seed,my_snap,opp_snap,my_rating,opp_rating,dw,dl)
 values(u,p_league,p_mode,season_,public._pvp_day(),opp,oname,seed_,mine,osnap,me.rating,orat,dw_,dl_) returning * into a;
 insert into public.pvp_sessions_v3(id,user_id,request_id,control,engine_hash,expires_at)
 values(a.id,u,p_request,p_control,p_engine_hash,least(clock_timestamp()+interval '1 hour',((season_+7)::timestamp at time zone 'Asia/Seoul'))) returning * into s;
 -- Preserve disconnect/quit penalty. Only verified replay can reverse this reserved loss.
 update public.pvp_ratings_v3 set rating=rating-dl_,losses=losses+1,updated_at=now() where user_id=u and league=p_league and mode=p_mode and season=season_;
 if opp is not null then
  perform public._pvp_rating_v3(opp,p_league,p_mode,season_);
  update public.pvp_ratings_v3 set rating=rating+dl_/2,def_wins=def_wins+1,updated_at=now() where user_id=opp and league=p_league and mode=p_mode and season=season_;
 end if;
 return public._pvp_session_json_v3(a,s)||jsonb_build_object('left',9+public._pvp_extra(u,p_league,p_mode)-used_);
end $$;$vr_statement$;
  execute $vr_statement$-- Only the trusted Edge runtime can read/replay/settle an attempt for a validated Auth UID.
create or replace function public.pvp_engine_session_v3(p_uid uuid,p_id bigint) returns jsonb language plpgsql security definer
set search_path=pg_catalog,public,pg_temp as $$ declare a public.pvp_attempts; s public.pvp_sessions_v3; begin
 select * into s from public.pvp_sessions_v3 where id=p_id and user_id=p_uid; if not found then raise exception 'session not found'; end if;
 select * into a from public.pvp_attempts where id=s.id;
 return public._pvp_session_json_v3(a,s)||jsonb_build_object('submission',s.submission);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.pvp_engine_settle_v3(p_uid uuid,p_id bigint,p_engine_hash text,p_submission jsonb,p_result jsonb) returns jsonb language plpgsql security definer
set search_path=pg_catalog,public,pg_temp as $$
declare a public.pvp_attempts; s public.pvp_sessions_v3; need_ int; w int; l int; skills_ int; r public.pvp_ratings_v3; rw jsonb; res jsonb; pay jsonb; round_ jsonb;
begin
 select * into a from public.pvp_attempts where id=p_id and user_id=p_uid; if not found then raise exception 'session not found'; end if;
 perform public._pvp_lock_v3(a.league,a.mode,a.season);
 select * into s from public.pvp_sessions_v3 where id=p_id and user_id=p_uid for update; if not found then raise exception 'session not found'; end if;
 if s.status='settled' then
  if s.submission is distinct from p_submission then raise exception 'submission conflict'; end if; return s.result;
 end if;
 if p_submission='{"forfeit":true}'::jsonb then return public._pvp_forfeit_v3(a,s); end if;
 if clock_timestamp()>=s.expires_at then
  res:=public._pvp_forfeit_v3(a,s);
  -- Preserve the first submitted body even on expiry, so a lost response is retryable.
  update public.pvp_sessions_v3 set submission=p_submission where id=a.id; return res;
 end if;
 if p_engine_hash is distinct from s.engine_hash or not exists(select 1 from public.pvp_policy_v3 where enabled and engine_hash=p_engine_hash) then raise exception 'PvP verifier unavailable'; end if;
 if s.control='auto' and p_submission is distinct from '{"actions":null}'::jsonb then raise exception 'invalid auto submission'; end if;
 if s.control='actions' and (jsonb_typeof(p_submission->'actions') is distinct from 'array' or octet_length(p_submission::text)>524288) then raise exception 'invalid actions'; end if;
 need_:=case when a.mode='3v3' then 2 else 1 end;
 if p_result is null or jsonb_typeof(p_result)<>'object' or p_result->>'wins' !~ '^[0-3]$' or p_result->>'losses' !~ '^[0-3]$' or p_result->>'skills' !~ '^[0-9]{1,4}$' then raise exception 'invalid trusted result'; end if;
 w:=(p_result->>'wins')::int; l:=(p_result->>'losses')::int; skills_:=(p_result->>'skills')::int;
 if w is null or l is null or skills_ is null or skills_>4800 or not ((w=need_ and l<need_) or (l=need_ and w<need_))
 or p_result->'win' is distinct from to_jsonb(w=need_) or jsonb_typeof(p_result->'rounds') is distinct from 'array' or jsonb_array_length(p_result->'rounds')<>w+l then raise exception 'invalid trusted result'; end if;
 for round_ in select * from jsonb_array_elements(p_result->'rounds') loop
  if round_->>'turns' !~ '^[0-9]{1,2}$' or coalesce((round_->>'turns')::int,0) not between 1 and 40 then raise exception 'invalid turns'; end if;
 end loop;
 if (select count(*) from jsonb_array_elements(p_result->'rounds') x where x->'win'='true'::jsonb)<>w then raise exception 'invalid rounds'; end if;
 if w=need_ then
  update public.pvp_ratings_v3 set rating=rating+a.dl+a.dw,wins=wins+1,losses=losses-1,updated_at=now()
   where user_id=p_uid and league=a.league and mode=a.mode and season=a.season;
  if a.opp_user is not null then update public.pvp_ratings_v3 set rating=rating-a.dl/2-a.dw/2,def_wins=def_wins-1,def_losses=def_losses+1,updated_at=now()
   where user_id=a.opp_user and league=a.league and mode=a.mode and season=a.season; end if;
 end if;
 update public.pvp_ratings_v3 set games_verified=games_verified+1,streak=case when w=need_ then streak+1 else 0 end
  where user_id=p_uid and league=a.league and mode=a.mode and season=a.season returning * into r;
 if w=need_ then select reward into rw from public.pvp_streak_table where n=r.streak; end if;
 if w=need_ then perform public._pvp_guild_feed_v3(p_uid,a.id); end if;
 if rw is not null then pay:=public._pvp_grant_v3(p_uid,rw,'pvp_streak_v3','attempt:'||a.id,a.league,a.mode,a.season); end if;
 insert into public.pvp_events_v3(session_id,user_id,day,week,win,skills) values(a.id,p_uid,public._gem_day(),public._weekly_week(),w=need_,skills_);
 res:=jsonb_build_object('ok',true,'verified',true,'win',w=need_,'wins',w,'losses',l,'rounds',p_result->'rounds','rating',r.rating,
  'delta',case when w=need_ then a.dw else -a.dl end,'streak',r.streak,'streak_reward',rw,'settlement',pay);
 update public.pvp_sessions_v3 set status='settled',submission=p_submission,result=res,verified=true where id=a.id;
 update public.pvp_attempts set reported_at=clock_timestamp(),win=w=need_,wins=w,losses=l,verified=true,actions=p_submission->'actions',streak=r.streak,streak_reward=rw where id=a.id;
 return res;
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.pvp_status(p_league text,p_mode text) returns jsonb language plpgsql security definer
set search_path=pg_catalog,public,pg_temp as $$
declare u uuid:=auth.uid(); n int:=public._pvp_ok(p_league,p_mode); used_ int; r public.pvp_ratings_v3; prev public.pvp_ratings_v3; decks jsonb; pend jsonb; prank jsonb; enabled_ boolean;
begin
 if u is null then raise exception 'login required'; end if;
 perform public._pvp_lock_v3(p_league,p_mode,public._pvp_season());
 r:=public._pvp_rating_v3(u,p_league,p_mode,public._pvp_season());
 select enabled into enabled_ from public.pvp_policy_v3;
 select count(*) into used_ from public.pvp_attempts where user_id=u and league=p_league and mode=p_mode and day=public._pvp_day();
 select coalesce(jsonb_agg(jsonb_build_object('slot',slot,'uids',uids,'cost',cost) order by slot),'[]') into decks from public.pvp_decks where user_id=u and league=p_league and mode=p_mode;
 select * into prev from public.pvp_ratings_v3 where user_id=u and league=p_league and mode=p_mode and season=public._pvp_season()-7;
 if enabled_ and prev.games_verified>=3 and not exists(select 1 from public.pvp_tier_claims where user_id=u and league=p_league and mode=p_mode and season=prev.season) then
  pend:=jsonb_build_object('season',prev.season,'rating',prev.rating,'tier',public._pvp_tier(prev.rating)); end if;
 if enabled_ and prev.games_verified>=1 and not exists(select 1 from public.pvp_reward_claims where user_id=u and league=p_league and mode=p_mode and season=prev.season) then
  prank:=jsonb_build_object('season',prev.season); end if;
 return jsonb_build_object('left',greatest(0,10+public._pvp_extra(u,p_league,p_mode)-used_),'max',10+public._pvp_extra(u,p_league,p_mode),'rating',r.rating,
 'wins',r.wins,'losses',r.losses,'def_wins',r.def_wins,'def_losses',r.def_losses,'streak',r.streak,'games_verified',r.games_verified,'decks',decks,'need',n,
 'season',public._pvp_season(),'season_end',((public._pvp_season()+7)::timestamp at time zone 'Asia/Seoul'),'tier',public._pvp_tier(r.rating),
 'abyss',exists(select 1 from public.pvp_titles where user_id=u and title='abyss'),
 'tiers',(select jsonb_agg(jsonb_build_object('tier',tier,'min',min_rating,'reward',reward) order by ord) from public.pvp_tier_table),
 'streaks',(select jsonb_agg(jsonb_build_object('n',t.n,'reward',reward) order by t.n) from public.pvp_streak_table t),
 'pending',pend,'pending_rank',prank,'reward_held',not enabled_,'ladder','verified-v3',
 'legacy_rating',(select rating from public.pvp_ratings where user_id=u and league=p_league and mode=p_mode and season=public._pvp_season()));
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.pvp_claim_tier(p_league text,p_mode text) returns jsonb language plpgsql security definer
set search_path=pg_catalog,public,pg_temp as $$
declare u uuid:=auth.uid(); s date:=public._pvp_season()-7; r public.pvp_ratings_v3; t text; rw jsonb; pay jsonb;
begin
 if u is null then raise exception 'login required'; end if; perform public._pvp_ok(p_league,p_mode);
 if not exists(select 1 from public.pvp_policy_v3 where enabled) then raise exception 'reward verification pending'; end if;
 perform public._pvp_lock_v3(p_league,p_mode,s);
 select * into r from public.pvp_ratings_v3 where user_id=u and league=p_league and mode=p_mode and season=s;
 if r.user_id is null or r.games_verified<3 then raise exception 'not eligible'; end if;
 if exists(select 1 from public.pvp_tier_claims where user_id=u and league=p_league and mode=p_mode and season=s) then raise exception 'already claimed'; end if;
 t:=public._pvp_tier(r.rating); select reward into rw from public.pvp_tier_table where tier=t;
 if rw is null then raise exception 'no reward'; end if;
 insert into public.pvp_tier_claims(user_id,league,mode,season,tier,rating,reward) values(u,p_league,p_mode,s,t,r.rating,rw);
 pay:=public._pvp_grant_v3(u,rw,'pvp_tier_v3',p_league||':'||p_mode||':'||s,p_league,p_mode,s);
 return jsonb_build_object('ok',true,'season',s,'tier',t,'rating',r.rating,'reward',rw,'settlement',pay);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.pvp_claim_reward(p_league text,p_mode text,p_season date) returns jsonb language plpgsql security definer
set search_path=pg_catalog,public,pg_temp as $$ declare u uuid:=auth.uid(); rk int; rw jsonb; pay jsonb; begin
 if u is null then raise exception 'login required'; end if; perform public._pvp_ok(p_league,p_mode);
 if p_season is null or p_season>=public._pvp_season() then raise exception 'season not ended'; end if;
 if not exists(select 1 from public.pvp_policy_v3 where enabled) then raise exception 'reward verification pending'; end if;
 perform public._pvp_lock_v3(p_league,p_mode,p_season);
 select t.rk into rk from (select user_id,rank() over(order by rating desc,wins desc) rk from public.pvp_ratings_v3
  where league=p_league and mode=p_mode and season=p_season and games_verified>0) t where t.user_id=u;
 if rk is null then raise exception 'not ranked'; end if;
 if exists(select 1 from public.pvp_reward_claims where user_id=u and league=p_league and mode=p_mode and season=p_season) then raise exception 'already claimed'; end if;
 select reward into rw from public.pvp_reward_table where league=p_league and mode=p_mode and rk between rank_from and rank_to order by rank_from limit 1;
 if rw is null then raise exception 'no reward'; end if;
 insert into public.pvp_reward_claims(user_id,league,mode,season,rank,reward) values(u,p_league,p_mode,p_season,rk,rw);
 pay:=public._pvp_grant_v3(u,rw,'pvp_rank_v3',p_league||':'||p_mode||':'||p_season,p_league,p_mode,p_season);
 return jsonb_build_object('ok',true,'season',p_season,'rank',rk,'reward',rw,'settlement',pay);
end $$;$vr_statement$;
  execute $vr_statement$-- Preserve the existing cosmetic/ranker presentation, change the authoritative source only.
do $$ declare sig text; src text; begin
 foreach sig in array array['public.pvp_rankings(text,text,date)','public.pvp_user_info(text,text,integer)'] loop
  src:=pg_get_functiondef(sig::regprocedure);
  src:=regexp_replace(src,'\mpvp_ratings\M','pvp_ratings_v3','g');
  src:=replace(src,'r.wins + r.losses > 0','r.games_verified > 0'); execute src;
 end loop;
end $$;$vr_statement$;
  execute $vr_statement$-- Cosmetic tier unlocks use the same verified proof; existing equipped profile fields stay untouched.
create or replace function public._cosmo_pvp_ord(p_uid uuid) returns int language sql stable security definer
set search_path=pg_catalog,public,pg_temp as $$ select coalesce(max(t.ord),0) from public.pvp_ratings_v3 r join public.pvp_tier_table t
 on t.tier=public._pvp_tier(r.rating) where r.user_id=p_uid and r.games_verified>0 $$;$vr_statement$;
  execute $vr_statement$-- Add ONLY verified PvP wins/skill uses to already server-derived daily/weekly progress.
do $$ declare sig text; begin
 if to_regprocedure('public._phase3_old_mission_prog(uuid,text,boolean)') is null then
  execute replace(pg_get_functiondef('public._clear_mission_prog_v2(uuid,text,boolean)'::regprocedure),'FUNCTION public._clear_mission_prog_v2(','FUNCTION public._phase3_old_mission_prog(');
 end if;
 if to_regprocedure('public._phase3_old_ach_prog(uuid,text)') is null then
  execute replace(pg_get_functiondef('public._ach_prog(uuid,text)'::regprocedure),'FUNCTION public._ach_prog(','FUNCTION public._phase3_old_ach_prog(');
 end if;
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._clear_mission_prog_v2(u uuid,k text,w boolean) returns int language sql stable security definer
set search_path=pg_catalog,public,pg_temp as $$ select public._phase3_old_mission_prog(u,k,w)+coalesce((select case k when 'skill' then sum(skills) when 'win' then count(*) filter(where win) else 0 end
 from public.pvp_events_v3 where user_id=u and (case when w then week=public._weekly_week() else day=public._gem_day() end)),0)::int $$;$vr_statement$;
  execute $vr_statement$create or replace function public._ach_prog(p_uid uuid,p_id text) returns int language plpgsql stable security definer
set search_path=pg_catalog,public,pg_temp as $$ declare n int; begin
 if p_id='pvp_wins' then select sum(wins)::int into n from public.pvp_ratings_v3 where user_id=p_uid;
 elsif p_id='pvp_tier' then select max(t.ord) into n from public.pvp_ratings_v3 r join public.pvp_tier_table t on t.tier=public._pvp_tier(r.rating) where r.user_id=p_uid and r.games_verified>0;
 elsif p_id='skill_uses' then select public._phase3_old_ach_prog(p_uid,p_id)+coalesce(sum(skills),0)::int into n from public.pvp_events_v3 where user_id=p_uid;
 else return public._phase3_old_ach_prog(p_uid,p_id); end if; return coalesce(n,0);
end $$;$vr_statement$;
  execute $vr_statement$do $$ declare src text; begin
 src:=pg_get_functiondef('public._ach_json(uuid)'::regprocedure);
 if position('''pvp_wins''' in src)=0 then
  execute replace(src,'''skill_uses'')','''skill_uses'',''pvp_wins'',''pvp_tier'')');
 end if;
end $$;$vr_statement$;
  execute $vr_statement$-- Retired trusted-result inputs remain unusable even through older privileged wrappers.
create or replace function public.pvp_start(p_league text,p_mode text) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$ begin raise exception 'use verified PvP v3'; end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.pvp_report(p_id bigint,p_wins int,p_losses int) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$ begin raise exception 'use verified PvP v3'; end $$;$vr_statement$;
  execute $vr_statement$-- Remove ALL overloads and raw/column writes, including generous Supabase defaults.
do $acl$ declare f record; obj text; col record; sig text; seq text; begin
 for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prokind='f'
 and (left(p.proname,1)='_' or p.proname in('pvp_start','pvp_report','pvp_log','pvp_start_v3','pvp_engine_session_v3','pvp_engine_settle_v3',
 'pvp_status','pvp_rankings','pvp_user_info','pvp_claim_tier','pvp_claim_reward')) loop
  execute format('revoke all on function %s from public,anon,authenticated',f.sig);
  if exists(select 1 from pg_roles where rolname='service_role') then execute format('revoke all on function %s from service_role',f.sig); end if;
 end loop;
 foreach sig in array array['pvp_start_v3(text,text,uuid,text,text)','pvp_status(text,text)','pvp_rankings(text,text,date)','pvp_user_info(text,text,integer)',
 'pvp_claim_tier(text,text)','pvp_claim_reward(text,text,date)'] loop execute format('grant execute on function public.%s to authenticated',sig); end loop;
 grant execute on function public.pvp_rankings(text,text,date) to anon;
 if exists(select 1 from pg_roles where rolname='service_role') then
  grant execute on function public.pvp_engine_session_v3(uuid,bigint),public.pvp_engine_settle_v3(uuid,bigint,text,jsonb,jsonb) to service_role;
 end if;
 foreach obj in array array['pvp_policy_v3','pvp_ratings_v3','pvp_sessions_v3','pvp_events_v3','pvp_decks','pvp_ratings','pvp_attempts','pvp_titles','pvp_bonus_tries','pvp_tier_claims','pvp_reward_claims'] loop
  execute format('alter table public.%I enable row level security',obj);
  execute format('revoke all on public.%I from public,anon,authenticated',obj);
  for col in select attname from pg_attribute where attrelid=to_regclass('public.'||obj) and attnum>0 and not attisdropped loop
   execute format('revoke insert (%I),update (%I),references (%I) on public.%I from public,anon,authenticated',col.attname,col.attname,col.attname,obj);
  end loop;
 end loop;
end $acl$;$vr_statement$;
  execute $vr_statement$revoke all on sequence public.pvp_attempts_id_seq from public,anon,authenticated;$vr_statement$;
  execute $vr_statement$-- 설치본의 단일 트랜잭션에 포함

-- 공개 게임 설정만 명시적으로 조회 허용 (사용자 자료 아님).
grant select on public.story_card_pool, public.story_phase_config, public.story_premium_ur,
  public.pvp_card_meta, public.pvp_reward_table, public.pvp_tier_table, public.pvp_streak_table,
  public.dispatch_card_meta, public.dispatch_zones to anon, authenticated;$vr_statement$;
  execute $vr_statement$-- 설치 완료 (원본 SQL의 사용자 테이블은 처음부터 비어 있어야 함).
set local check_function_bodies = on;$vr_statement$;
  execute $vr_statement$do $staging_verify$
declare f record;
begin
  for f in
    select pg_get_functiondef(p.oid) ddl from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prokind = 'f'
      and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
  loop execute f.ddl; end loop;
  if exists (select 1 from auth.users) then raise exception 'STOP: 설치 중 사용자 자료 발견'; end if;
  if exists (select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relkind='r' and not c.relrowsecurity
      and not exists (select 1 from pg_depend d where d.objid = c.oid and d.deptype = 'e')) then
    raise exception 'STOP: RLS 없는 테이블 발견';
  end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.prosecdef and left(p.proname,1)='_'
      and pg_get_function_result(p.oid) <> 'trigger'
      and (has_function_privilege('anon',p.oid,'execute') or has_function_privilege('authenticated',p.oid,'execute'))) then
    raise exception 'STOP: 외부 호출 가능한 내부 서버 함수 발견';
  end if;
end $staging_verify$;$vr_statement$;

  grant usage on schema public to public, anon, authenticated;
  insert into vr_staging_install.parts(part_no, bundle_hash, part_hash, project_ref, db_id)
  values (13, 'cc55a18ffb6e7f31c29402be300a5e256b333fd450277ae07e425819f76899c9', '548d48af1cf708bd545adda12f51a0b244ff6d2f45a04b23926d58da1241c37f', 'cuyqchmdcnsgzkwyclji', '7703759698107299042');
end $vr_install_part$;
commit;
select '13_install.sql: 완료 또는 이미 완료 (13/13)' as result;
