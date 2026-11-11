-- STAGING ONLY. After security_phase1_rewards.sql and security_phase2_clears.sql.
-- No credentials, backfill certification, resets or deletes. Deploy pvp-verify-v3 too.
begin;
do $phase3_staging_guard$
begin
 if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7703759698107299042' then
  raise exception 'STOP: phase3 only on staging cuyqchmdcnsgzkwyclji; production htarwisgkkphutxxnuak forbidden';
 end if;
end $phase3_staging_guard$;

create table if not exists public.pvp_policy_v3(
 singleton boolean primary key default true check(singleton), engine_hash text not null check(length(engine_hash)=64), enabled boolean not null default true);
insert into public.pvp_policy_v3(singleton,engine_hash) values(true,'bef887c77a009121ae99301ca91db7d73a7bd9ce30d70e1ec7a18d10742cd16f')
 on conflict(singleton) do update set engine_hash=excluded.engine_hash;
-- A clean, verified ladder. Legacy rows remain intact, NOT copied as proof.
create table if not exists public.pvp_ratings_v3(
 user_id uuid not null references auth.users(id), league text not null, mode text not null, season date not null,
 rating int not null default 1000, wins int not null default 0, losses int not null default 0,
 def_wins int not null default 0, def_losses int not null default 0, streak int not null default 0,
 games_verified int not null default 0, updated_at timestamptz not null default now(),
 primary key(user_id,league,mode,season));
create table if not exists public.pvp_sessions_v3(
 id bigint primary key references public.pvp_attempts(id), user_id uuid not null references auth.users(id),
 request_id uuid not null, control text not null check(control in('auto','actions')), engine_hash text not null,
 issued_at timestamptz not null default clock_timestamp(), expires_at timestamptz not null,
 status text not null default 'issued' check(status in('issued','settled')),
 submission jsonb, result jsonb, verified boolean not null default false,
 unique(user_id,request_id));
create index if not exists pvp_sessions_v3_pending on public.pvp_sessions_v3(user_id,status);
create table if not exists public.pvp_events_v3(
 session_id bigint primary key references public.pvp_sessions_v3(id), user_id uuid not null references auth.users(id),
 day date not null, week date not null, win boolean not null, skills int not null check(skills between 0 and 4800));

create or replace function public._pvp_lock_v3(l text,m text,s date) returns void language sql security definer
set search_path=pg_catalog,public,pg_temp as $$ select pg_advisory_xact_lock(hashtext('pvp3:'||l||':'||m||':'||s::text)) $$;
create or replace function public._pvp_rating_v3(u uuid,l text,m text,s date) returns public.pvp_ratings_v3 language plpgsql security definer
set search_path=pg_catalog,public,pg_temp as $$ declare r public.pvp_ratings_v3; p public.pvp_ratings_v3; begin
 select * into p from public.pvp_ratings_v3 where user_id=u and league=l and mode=m and season<s order by season desc limit 1;
 insert into public.pvp_ratings_v3(user_id,league,mode,season,rating,wins,losses,def_wins,def_losses)
  values(u,l,m,s,coalesce(p.rating,1000),coalesce(p.wins,0),coalesce(p.losses,0),coalesce(p.def_wins,0),coalesce(p.def_losses,0))
  on conflict do nothing;
 select * into r from public.pvp_ratings_v3 where user_id=u and league=l and mode=m and season=s; return r;
end $$;
create or replace function public._pvp_session_json_v3(a public.pvp_attempts,s public.pvp_sessions_v3) returns jsonb language sql stable security definer
set search_path=pg_catalog,public,pg_temp as $$ select jsonb_build_object('id',a.id::text,'mode',a.mode,'league',a.league,'season',a.season,
 'seed',a.seed,'me',a.my_snap,'opp',a.opp_snap,'opp_name',a.opp_name,'opp_rating',a.opp_rating,'rating',a.my_rating,
 'dw',a.dw,'dl',a.dl,'bot',a.opp_user is null,'control',s.control,'engine_hash',s.engine_hash,'expires_at',s.expires_at,'status',s.status,'result',s.result) $$;
-- Private ledger grants. Do NOT reopen the old _pvp_grant or global battle feeds.
create or replace function public._pvp_grant_v3(u uuid,rw jsonb,kind text,ref_ text,l text,m text,s date) returns jsonb language plpgsql security definer
set search_path=pg_catalog,public,pg_temp as $$
declare prior public.reward_claims; res jsonb:='{}'; k text; v jsonb; tk int; g jsonb;
begin
 if kind not in('pvp_streak_v3','pvp_tier_v3','pvp_rank_v3') then raise exception 'invalid grant kind'; end if;
 for k,v in select * from jsonb_each(rw-'title') loop
  if k not in('gold','blood','shard','soul','gem','tickets') or jsonb_typeof(v)<>'number' or v::text !~ '^[0-9]+$' or v::numeric>2147483647 then raise exception 'invalid reward'; end if;
 end loop;
 if rw ? 'title' and rw->>'title'<>'abyss' then raise exception 'invalid title'; end if;
 perform pg_advisory_xact_lock(hashtext('gem:'||u::text));
 select * into prior from public.reward_claims where user_id=u and reward_kind=kind and source_or_period=ref_;
 if found then return prior.result; end if;
 insert into public.reward_claims(user_id,reward_kind,source_or_period,reward,rule_version) values(u,kind,ref_,rw,4);
 if rw-'gem'-'tickets'-'title'<>'{}' then res:=res||jsonb_build_object('wallet',public._wallet_add(u,rw-'gem'-'tickets'-'title',kind)); end if;
 if coalesce((rw->>'gem')::int,0)>0 then
  g:=public._gem_add(u,(rw->>'gem')::int,0,kind,'p3:'||ref_,jsonb_build_object('validation','server-replay-v3'));
  res:=res||jsonb_build_object('gem',g->'gem');
 end if;
 if coalesce((rw->>'tickets')::int,0)>0 then
  insert into public.story_gacha(user_id,last_draw) values(u,public._gem_day()-1) on conflict do nothing;
  update public.story_gacha set tickets=tickets+(rw->>'tickets')::int,updated_at=now() where user_id=u returning tickets into tk;
  res:=res||jsonb_build_object('tickets',tk);
 end if;
 if rw->>'title'='abyss' then insert into public.pvp_titles(user_id,title,league,mode,season) values(u,'abyss',l,m,s) on conflict do nothing; end if;
 res:=res||jsonb_build_object('gave',rw);
 update public.reward_claims set result=res where user_id=u and reward_kind=kind and source_or_period=ref_;
 return res;
end $$;
-- Restore ONLY verified ranked wins' old guild EXP/loyalty feed (10/win, 100/KST day).
-- Global _guild_feed remains held for other unverified modes. Unique source is the PvP receipt.
create or replace function public._pvp_guild_feed_v3(u uuid,aid bigint) returns int language plpgsql security definer
set search_path=pg_catalog,public,pg_temp as $$ declare m public.guild_members; used_ int; n int; ref_ text:='pvp3:'||aid; begin
 select * into m from public.guild_members where user_id=u; if not found then return 0; end if;
 perform public._guild_lock(m.guild_id);
 if not exists(select 1 from public.guild_members where user_id=u and guild_id=m.guild_id) then return 0; end if;
 if exists(select 1 from public.guild_exp_log where guild_id=m.guild_id and ref=ref_) then return 0; end if;
 perform public._guild_event(u,'pvp_win',1);
 select coalesce(sum(amount),0)::int into used_ from public.guild_exp_log where user_id=u and day=public._guild_day() and src='pvp';
 n:=least(10,greatest(0,100-used_)); if n=0 then return 0; end if;
 perform public._guild_exp(m.guild_id,u,n,'pvp',ref_);
 perform public._loyalty_add(u,n,'feed:pvp',ref_,jsonb_build_object('guild',m.guild_id,'session',aid)); return n;
end $$;
-- Unsubmitted/replaced sessions are server-defined forfeits, already loss-reserved at start.
-- They NEVER produce verified participation, wins, events, streak money, tier/rank eligibility.
create or replace function public._pvp_forfeit_v3(a public.pvp_attempts,s public.pvp_sessions_v3) returns jsonb language plpgsql security definer
set search_path=pg_catalog,public,pg_temp as $$ declare res jsonb; r int; begin
 if s.status='settled' then return s.result; end if;
 update public.pvp_ratings_v3 set streak=0 where user_id=a.user_id and league=a.league and mode=a.mode and season=a.season returning rating into r;
 res:=jsonb_build_object('ok',true,'verified',false,'forfeit',true,'win',false,'wins',0,'losses',case when a.mode='3v3' then 2 else 1 end,
  'rounds','[]'::jsonb,'rating',r,'delta',-a.dl,'streak',0);
 update public.pvp_sessions_v3 set status='settled',submission='{"forfeit":true}',result=res where id=a.id;
 update public.pvp_attempts set reported_at=clock_timestamp(),win=false,wins=0,losses=case when a.mode='3v3' then 2 else 1 end,verified=false,streak=0 where id=a.id;
 return res;
end $$;
-- Server-owned fresh snapshots, including HR guard checks and cross-deck uniqueness.
create or replace function public._pvp_decks_v3(u uuid,l text,m text) returns jsonb language plpgsql stable security definer
set search_path=pg_catalog,public,pg_temp as $$ declare n int:=public._pvp_ok(l,m); d record; out_ jsonb:='[]'; c jsonb; begin
 for d in select * from public.pvp_decks where user_id=u and league=l and mode=m and slot>=0 and slot<n order by slot loop
  c:=public._pvp_snap_mode(u,d.uids,l,m)->'cards';
  if m='boss' and not exists(select 1 from public.pvp_card_meta where id=c->0->>'id' and grade in('NORMAL','RARE','HIGH RARE')) then raise exception 'guard grade'; end if;
  out_:=out_||jsonb_build_array(c);
 end loop;
 if jsonb_array_length(out_)<>n then raise exception 'deck required'; end if;
 if exists(select x->>'id' from jsonb_array_elements(out_) dk cross join lateral jsonb_array_elements(dk) x group by x->>'id' having count(*)>1) then raise exception 'duplicate card'; end if;
 return out_;
end $$;
create or replace function public.pvp_start_v3(p_league text,p_mode text,p_request uuid,p_control text,p_engine_hash text) returns jsonb language plpgsql security definer
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
end $$;
-- Only the trusted Edge runtime can read/replay/settle an attempt for a validated Auth UID.
create or replace function public.pvp_engine_session_v3(p_uid uuid,p_id bigint) returns jsonb language plpgsql security definer
set search_path=pg_catalog,public,pg_temp as $$ declare a public.pvp_attempts; s public.pvp_sessions_v3; begin
 select * into s from public.pvp_sessions_v3 where id=p_id and user_id=p_uid; if not found then raise exception 'session not found'; end if;
 select * into a from public.pvp_attempts where id=s.id;
 return public._pvp_session_json_v3(a,s)||jsonb_build_object('submission',s.submission);
end $$;
create or replace function public.pvp_engine_settle_v3(p_uid uuid,p_id bigint,p_engine_hash text,p_submission jsonb,p_result jsonb) returns jsonb language plpgsql security definer
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
end $$;

create or replace function public.pvp_status(p_league text,p_mode text) returns jsonb language plpgsql security definer
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
end $$;
create or replace function public.pvp_claim_tier(p_league text,p_mode text) returns jsonb language plpgsql security definer
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
end $$;
create or replace function public.pvp_claim_reward(p_league text,p_mode text,p_season date) returns jsonb language plpgsql security definer
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
end $$;
-- Preserve the existing cosmetic/ranker presentation, change the authoritative source only.
do $$ declare sig text; src text; begin
 foreach sig in array array['public.pvp_rankings(text,text,date)','public.pvp_user_info(text,text,integer)'] loop
  src:=pg_get_functiondef(sig::regprocedure);
  src:=regexp_replace(src,'\mpvp_ratings\M','pvp_ratings_v3','g');
  src:=replace(src,'r.wins + r.losses > 0','r.games_verified > 0'); execute src;
 end loop;
end $$;
-- Cosmetic tier unlocks use the same verified proof; existing equipped profile fields stay untouched.
create or replace function public._cosmo_pvp_ord(p_uid uuid) returns int language sql stable security definer
set search_path=pg_catalog,public,pg_temp as $$ select coalesce(max(t.ord),0) from public.pvp_ratings_v3 r join public.pvp_tier_table t
 on t.tier=public._pvp_tier(r.rating) where r.user_id=p_uid and r.games_verified>0 $$;
-- Add ONLY verified PvP wins/skill uses to already server-derived daily/weekly progress.
do $$ declare sig text; begin
 if to_regprocedure('public._phase3_old_mission_prog(uuid,text,boolean)') is null then
  execute replace(pg_get_functiondef('public._clear_mission_prog_v2(uuid,text,boolean)'::regprocedure),'FUNCTION public._clear_mission_prog_v2(','FUNCTION public._phase3_old_mission_prog(');
 end if;
 if to_regprocedure('public._phase3_old_ach_prog(uuid,text)') is null then
  execute replace(pg_get_functiondef('public._ach_prog(uuid,text)'::regprocedure),'FUNCTION public._ach_prog(','FUNCTION public._phase3_old_ach_prog(');
 end if;
end $$;
create or replace function public._clear_mission_prog_v2(u uuid,k text,w boolean) returns int language sql stable security definer
set search_path=pg_catalog,public,pg_temp as $$ select public._phase3_old_mission_prog(u,k,w)+coalesce((select case k when 'skill' then sum(skills) when 'win' then count(*) filter(where win) else 0 end
 from public.pvp_events_v3 where user_id=u and (case when w then week=public._weekly_week() else day=public._gem_day() end)),0)::int $$;
create or replace function public._ach_prog(p_uid uuid,p_id text) returns int language plpgsql stable security definer
set search_path=pg_catalog,public,pg_temp as $$ declare n int; begin
 if p_id='pvp_wins' then select sum(wins)::int into n from public.pvp_ratings_v3 where user_id=p_uid;
 elsif p_id='pvp_tier' then select max(t.ord) into n from public.pvp_ratings_v3 r join public.pvp_tier_table t on t.tier=public._pvp_tier(r.rating) where r.user_id=p_uid and r.games_verified>0;
 elsif p_id='skill_uses' then select public._phase3_old_ach_prog(p_uid,p_id)+coalesce(sum(skills),0)::int into n from public.pvp_events_v3 where user_id=p_uid;
 else return public._phase3_old_ach_prog(p_uid,p_id); end if; return coalesce(n,0);
end $$;
do $$ declare src text; begin
 src:=pg_get_functiondef('public._ach_json(uuid)'::regprocedure);
 if position('''pvp_wins''' in src)=0 then
  execute replace(src,'''skill_uses'')','''skill_uses'',''pvp_wins'',''pvp_tier'')');
 end if;
end $$;
-- Retired trusted-result inputs remain unusable even through older privileged wrappers.
create or replace function public.pvp_start(p_league text,p_mode text) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$ begin raise exception 'use verified PvP v3'; end $$;
create or replace function public.pvp_report(p_id bigint,p_wins int,p_losses int) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$ begin raise exception 'use verified PvP v3'; end $$;
-- Remove ALL overloads and raw/column writes, including generous Supabase defaults.
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
end $acl$;
revoke all on sequence public.pvp_attempts_id_seq from public,anon,authenticated;
commit;
