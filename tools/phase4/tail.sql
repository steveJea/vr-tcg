
-- Finish ALL already-frozen past seasons before rankings/claims are evaluated.
-- A lazy tick must not strand Sunday results when Monday advances the season.
create or replace function public._war_tick_v4() returns date language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare s date:=_war_season_v4();old_s date;d int;match_ record;
begin
 perform _guildbattle_guard_v4();perform pg_advisory_xact_lock(hashtext('guildbattle:v4'));
 update war_entries_v4 set status='out' where not locked and season<s;
 for old_s in select distinct season from war_entries_v4 where season<s and locked order by season loop
  for d in 1..5 loop
   perform _war_pair_v4(old_s,d);
   for match_ in select id from war_matches_v4 where season=old_s and day=d and not settled loop perform _war_settle_v4(match_.id);end loop;
  end loop;
 end loop;
 -- No retroactive roster admission after a whole season has ended.
 if _war_now_v4()<_war_at_v4(s,1,9) then perform _war_auto_enter_v4(s);return s;end if;
 if _war_now_v4()>=_war_at_v4(s,5,23) then update war_entries_v4 set status='out' where season=s and not locked;
 else perform _war_auto_enter_v4(s);perform _war_lock_v4(s);end if;
 for d in 1..5 loop
  exit when _war_now_v4()<_war_at_v4(s,d,9);
  perform _war_pair_v4(s,d);
  if _war_now_v4()>=_war_at_v4(s,d,23) then
   for match_ in select id from war_matches_v4 where season=s and day=d and not settled loop perform _war_settle_v4(match_.id);end loop;
  end if;
 end loop;
 return s;
end $$;
-- SERVER ISSUANCE. One global phase4 transaction lock establishes a consistent lock
-- order across raid, war, sweeps and claims. No untrusted outcome enters this RPC.
create or replace function public.guildbattle_start_v4(p_kind text,p_payload jsonb,p_request uuid,p_control text,p_engine_hash text) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare u uuid:=auth.uid(); s guildbattle_sessions_v4; b jsonb; aid bigint; ex timestamptz;
begin
 perform _guildbattle_guard_v4();
 if u is null then raise exception 'login required'; end if;
 if p_request is null or p_kind not in('raid','war') or p_control not in('auto','actions') or p_engine_hash is distinct from (select engine_hash from guildbattle_policy_v4 where singleton) then raise exception 'invalid request'; end if;
 if jsonb_typeof(p_payload) is distinct from 'object' then raise exception 'invalid request'; end if;
 if p_kind='raid' then
  if p_payload-'uids'<>'{}' or jsonb_typeof(p_payload->'uids') is distinct from 'array' or jsonb_array_length(p_payload->'uids') not between 1 and 5 then raise exception 'invalid deck'; end if;
 else
  if p_payload-array['slot','deck']<>'{}' or p_payload->>'slot' is null or p_payload->>'deck' is null or (p_payload->>'slot')!~'^[1-9][0-9]?$' or (p_payload->>'slot')::int>21 or p_payload->>'deck' not in('1','2') then raise exception 'invalid target'; end if;
 end if;
 perform pg_advisory_xact_lock(hashtext('guildbattle:v4'));
 select * into s from guildbattle_sessions_v4 where user_id=u and kind=p_kind and request_id=p_request;
 if found then
  if s.payload is distinct from p_payload or s.control<>p_control or s.engine_hash<>p_engine_hash then raise exception 'request conflict'; end if;
  return s.snapshot||jsonb_build_object('id',s.id::text,'control',s.control,'engine_hash',s.engine_hash,'expires_at',s.expires_at,'status',s.status,'result',s.result);
 end if;
 -- Prior abandoned reservations consume their attempt, never award or feed anything.
 update guildbattle_sessions_v4 set status='settled',submission='{"forfeit":true}',result='{"expired":true,"win":false,"damage":0}' where user_id=u and kind=p_kind and status='issued';
 if p_kind='raid' then
  if (select count(*) from guild_raid_attempts where user_id=u and day=_raid_day_v4())+(select count(*) from guild_raid_attempts_v4 where user_id=u and day=_raid_day_v4())>=3 then raise exception 'no attempts'; end if;
  b:=_raid_start_v4(p_payload->'uids');
 else b:=_war_start_v4((p_payload->>'slot')::int,(p_payload->>'deck')::int);
 end if;
 aid:=(b->>'id')::bigint; ex:=clock_timestamp()+interval '20 minutes';
 b:=(b-'id')||jsonb_build_object('kind',p_kind);
 insert into guildbattle_sessions_v4(user_id,kind,attempt_id,request_id,control,engine_hash,payload,snapshot,expires_at) values(u,p_kind,aid,p_request,p_control,p_engine_hash,p_payload,b,ex) returning * into s;
 return b||jsonb_build_object('id',s.id::text,'control',p_control,'engine_hash',p_engine_hash,'expires_at',ex,'status','issued','result',null);
end $$;
create or replace function public.guildbattle_engine_session_v4(p_uid uuid,p_id bigint) returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,pg_temp as $$ declare s guildbattle_sessions_v4; begin
 select * into s from guildbattle_sessions_v4 where id=p_id and user_id=p_uid;
 if not found then raise exception 'session not found'; end if;
 return s.snapshot||jsonb_build_object('id',s.id::text,'control',s.control,'engine_hash',s.engine_hash,'status',s.status,'result',s.result);
end $$;
-- Only the authenticated Edge verifier's service role can call this. Result is
-- canonical replay output, NEVER a player-reported win/damage/HP value.
create or replace function public.guildbattle_engine_settle_v4(p_uid uuid,p_id bigint,p_engine_hash text,p_submission jsonb,p_result jsonb) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare s guildbattle_sessions_v4; a guild_raid_attempts_v4; w war_attacks_v4; mt war_matches_v4; t war_ajits_v4; st war_atk_state_v4; m guild_members; rw jsonb; bad boolean:=false; oldsub text; oldclaims text; dmg bigint;
begin
 perform pg_advisory_xact_lock(hashtext('guildbattle:v4'));
 select * into s from guildbattle_sessions_v4 where id=p_id and user_id=p_uid for update;
 if not found then raise exception 'session not found'; end if;
 if s.status='settled' then
  if s.submission is distinct from p_submission then raise exception 'submission conflict'; end if;
  return jsonb_build_object('ok',true,'status','settled','result',s.result);
 end if;
 if p_submission is null or not (p_submission='{"forfeit":true}' or (jsonb_typeof(p_submission)='object' and p_submission-'actions'='{}' and p_submission?'actions')) then raise exception 'invalid submission'; end if;
 if p_submission<>'{"forfeit":true}' and ((s.control='auto' and p_submission->'actions'<>'null') or (s.control='actions' and jsonb_typeof(p_submission->'actions') is distinct from 'array')) then raise exception 'invalid submission'; end if;
 select * into m from guild_members where user_id=p_uid for update;
 bad:=clock_timestamp()>s.expires_at or p_submission='{"forfeit":true}';
 if s.kind='raid' then
  select * into a from guild_raid_attempts_v4 where id=s.attempt_id for update;
  bad:=bad or a.finished_at is not null or m.guild_id is distinct from a.guild_id or a.week<>_raid_week_v4() or _raid_now_v4()>=_raid_end_v4(a.week)+interval '5 minutes';
 else
  if exists(select 1 from guildbattle_policy_v4 where singleton and enabled) then perform _war_tick_v4(); end if;
  select * into w from war_attacks_v4 where id=s.attempt_id for update;
  select * into mt from war_matches_v4 where id=w.match_id for update;
  select * into t from war_ajits_v4 where match_id=w.match_id and side=1-w.side and slot=w.target_slot for update;
  select * into st from war_atk_state_v4 where match_id=w.match_id and user_id=p_uid and deck=w.atk_deck for update;
  bad:=bad or w.finished_at is not null or mt.settled or mt.ended_at is not null or mt.season<>_war_season_v4() or _war_phase_v4(mt.season)<>'live' or mt.day<>_war_day_v4(mt.season)
   or m.guild_id is distinct from case w.side when 0 then mt.guild_a else mt.guild_b end
   or t.destroyed_at is not null or t.deck<>w.def_deck or t.locked_by is distinct from p_uid or t.locked_until<_war_now_v4()
   or t.state is distinct from w.before->'def_state' and not(t.state is null and w.before->'def_state'='null')
   or st.state is distinct from w.before->'atk_state' and not(st.state is null and w.before->'atk_state'='null');
 end if;
 if bad then
  rw:='{"expired":true,"win":false,"damage":0}';
  if s.kind='raid' then update guild_raid_attempts_v4 set finished_at=now(),damage=0,voided=true where id=s.attempt_id;
  else update war_attacks_v4 set finished_at=now(),win=false,voided=true where id=s.attempt_id;
   update war_ajits_v4 set locked_by=null,locked_until=null where match_id=w.match_id and side=1-w.side and slot=w.target_slot and locked_by=p_uid;
  end if;
 else
  perform _guildbattle_guard_v4();
  if p_engine_hash is distinct from s.engine_hash or p_engine_hash is distinct from (select engine_hash from guildbattle_policy_v4 where singleton) then raise exception 'verifier unavailable'; end if;
  if jsonb_typeof(p_result) is distinct from 'object' then raise exception 'verified result required'; end if;
  if s.kind='raid' then
   if jsonb_typeof(p_result->'damage') is distinct from 'number' or (p_result->>'damage')!~'^[0-9]+$' then raise exception 'invalid result'; end if;
   dmg:=(p_result->>'damage')::bigint;
   update guild_raid_attempts_v4 set actions=p_submission->'actions',reported=dmg where id=a.id;
   rw:=_raid_close_v4(a,dmg);
  else
   if jsonb_typeof(p_result->'win') is distinct from 'boolean' or jsonb_typeof(p_result->'aHp') is distinct from 'object' or jsonb_typeof(p_result->'bHp') is distinct from 'object' then raise exception 'invalid result'; end if;
   update war_attacks_v4 set actions=p_submission->'actions' where id=w.id;
   rw:=_war_finish_v4(p_uid,w.id,(p_result->>'win')::boolean,p_result->'aHp',p_result->'bHp')->'result';
  end if;
  insert into guildbattle_events_v4(session_id,user_id,guild_id,kind,day,metrics) values(s.id,p_uid,m.guild_id,s.kind,_guild_day(),p_result);
 end if;
 update guildbattle_sessions_v4 set status='settled',submission=p_submission,result=rw,verified=not bad where id=s.id;
 return jsonb_build_object('ok',true,'status','settled','result',rw);
end $$;
create or replace function public.raid_sweep_v4(p_request uuid) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare u uuid:=auth.uid(); m guild_members; r guild_raids_v4; a guild_raid_attempts_v4; best bigint; rw jsonb;
begin
 perform _guildbattle_guard_v4(); if u is null or p_request is null then raise exception 'login required'; end if;
 perform pg_advisory_xact_lock(hashtext('guildbattle:v4'));
 select result into rw from guildbattle_sweeps_v4 where user_id=u and request_id=p_request; if found then return rw; end if;
 select * into m from guild_members where user_id=u for update; if not found then raise exception 'not in guild'; end if;
 if _raid_now_v4()>=_raid_end_v4(_raid_week_v4()) then raise exception 'raid ended'; end if;
 if (select count(*) from guild_raid_attempts where user_id=u and day=_raid_day_v4())+(select count(*) from guild_raid_attempts_v4 where user_id=u and day=_raid_day_v4())>=3 then raise exception 'no attempts'; end if;
 select max(fight.damage) into best from guild_raid_attempts_v4 fight join guildbattle_sessions_v4 sess on sess.kind='raid' and sess.attempt_id=fight.id and sess.verified and sess.status='settled'
 where fight.user_id=u and fight.guild_id=m.guild_id and fight.week=_raid_week_v4() and fight.day=_raid_day_v4() and fight.kind='fight' and not fight.voided;
 if coalesce(best,0)<=0 then raise exception 'fight first'; end if;
 r:=_raid_get_v4(m.guild_id,_raid_week_v4());
 insert into guild_raid_attempts_v4(user_id,guild_id,week,day,kind,stage,difficulty) values(u,m.guild_id,r.week,_raid_day_v4(),'sweep',r.stage,r.difficulty) returning * into a;
 rw:=jsonb_build_object('result',_raid_close_v4(a,best*90/100));
 insert into guildbattle_sweeps_v4 values(u,p_request,rw,m.guild_id,_guild_day()); return rw;
end $$;
-- Apply the existing random gear trigger ONLY when a new verified fight or
-- server-derived sweep atomically finishes. Failed transactions roll it back.
drop trigger if exists gear_raid_drop_v4 on guild_raid_attempts_v4;
create trigger gear_raid_drop_v4 after update on guild_raid_attempts_v4 for each row execute function public._gear_raid_attempt_trg();

create or replace function public._guildbattle_raid_count_v4(u uuid,g bigint,d date,e date) returns bigint language sql stable security definer set search_path=pg_catalog,public,pg_temp as $$
 select count(*) from (select user_id,guild_id,day from guildbattle_events_v4 where kind='raid' union all select user_id,guild_id,day from guildbattle_sweeps_v4) x where (u is null or user_id=u) and guild_id=g and day between d and e $$;
-- Only raid quests reopen here. Other unverified quest kinds and daily-all bonuses
-- retain phase1's hold. Never use old q.progress or old contribution as evidence.
create or replace function public.guild_quest_claim(p_slot int) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare u uuid:=auth.uid();m guild_members;q guild_daily_quests;p guild_quest_pool;r jsonb;
begin
 perform _guildbattle_guard_v4();perform pg_advisory_xact_lock(hashtext('guildbattle:v4'));
 select * into m from guild_members where user_id=u for update;if not found then raise exception 'not in guild';end if;
 select * into q from guild_daily_quests where user_id=u and day=_guild_day() and slot=p_slot for update;
 select * into p from guild_quest_pool where key=q.qkey;
 if p.event is distinct from 'raid' then raise exception 'reward verification pending';end if;
 if q.claimed_at is not null then raise exception 'already claimed';end if;
 if _guildbattle_raid_count_v4(u,m.guild_id,_guild_day(),_guild_day())<q.goal then raise exception 'not reached';end if;
 r:=_guild_reward_v4(u,m.guild_id,p.reward,'guild_daily','dq:'||_guild_day()||':'||p_slot);
 update guild_daily_quests set claimed_at=now() where user_id=u and day=_guild_day() and slot=p_slot;
 return guild_quests()||jsonb_build_object('got',p.reward,'wallet',r->'wallet');
end $$;
create or replace function public.guild_weekly_claim(p_slot int,p_tier int) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare u uuid:=auth.uid();m guild_members;q guild_weekly_quests;p guild_quest_pool;t jsonb;w date:=_guild_week();n bigint;r jsonb;
begin
 perform _guildbattle_guard_v4();perform pg_advisory_xact_lock(hashtext('guildbattle:v4'));
 select * into m from guild_members where user_id=u for update;if not found then raise exception 'not in guild';end if;
 select * into q from guild_weekly_quests where guild_id=m.guild_id and week=w and slot=p_slot for update;
 select * into p from guild_quest_pool where key=q.qkey;if p.event is distinct from 'raid' then raise exception 'reward verification pending';end if;
 select x into t from jsonb_array_elements(_guild_weekly_tiers()) x where (x->>'tier')::int=p_tier;if t is null then raise exception 'bad tier';end if;
 if _guildbattle_raid_count_v4(null,m.guild_id,w,w+6)*100<q.goal*p_tier then raise exception 'not reached';end if;
 if _guildbattle_raid_count_v4(u,m.guild_id,w,w+6)<ceil(q.goal*_guild_weekly_min_pct()) then raise exception 'contribution too low';end if;
 r:=_guild_reward_v4(u,m.guild_id,t->'reward','guild_weekly','wq:'||w||':'||p_slot||':'||p_tier);
 perform _guild_exp(m.guild_id,null,(t->>'exp')::int,'weekly_quest','wq:v4:'||w||':'||p_slot||':'||p_tier);
 return guild_quests()||jsonb_build_object('got',t->'reward','wallet',r->'wallet');
end $$;
revoke all on function public.guild_quest_claim(int),public.guild_weekly_claim(int,int) from public,anon;
grant execute on function public.guild_quest_claim(int),public.guild_weekly_claim(int,int) to authenticated;
-- Close every legacy signature and every old/new private helper, including column
-- ACLs and default function EXECUTE inherited from PUBLIC. No client raw writes.
do $phase4_acl$ declare f record; t record; colrec record; begin
 for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and (p.proname~'^_?(raid_|war_)' or p.proname~'^_?guildbattle_' or p.proname='_guild_reward_v4') loop
  execute format('revoke all on function %s from public,anon,authenticated',f.sig);
  if exists(select 1 from pg_roles where rolname='service_role') then execute format('revoke all on function %s from service_role',f.sig); end if;
 end loop;
 for t in select c.oid,c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in('r','p') and (c.relname~'^guildbattle_' or c.relname~'^guild_raid' or c.relname~'^war_') loop
  execute format('alter table public.%I enable row level security',t.relname);
  execute format('revoke all on public.%I from public,anon,authenticated',t.relname);
  for colrec in select attname from pg_attribute where attrelid=t.oid and attnum>0 and not attisdropped loop
   execute format('revoke select(%1$I),insert(%1$I),update(%1$I),references(%1$I) on public.%2$I from public,anon,authenticated',colrec.attname,t.relname);
  end loop;
 end loop;
 for t in select c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='S' and (c.relname~'^guildbattle_' or c.relname~'^guild_raid' or c.relname~'^war_') loop execute format('revoke all on sequence public.%I from public,anon,authenticated',t.relname); end loop;
 if exists(select 1 from pg_roles where rolname='service_role') then
  grant execute on function public.guildbattle_engine_session_v4(uuid,bigint),public.guildbattle_engine_settle_v4(uuid,bigint,text,jsonb,jsonb) to service_role;
 end if;
end $phase4_acl$;
grant execute on function public.guildbattle_start_v4(text,jsonb,uuid,text,text),public.raid_sweep_v4(uuid) to authenticated;
-- PUBLIC_READ_WRAPPERS generated below, with a single transaction lock and gate.

create or replace function public.guildbattle_lookup_v4(p_kind text,p_request uuid) returns jsonb language sql stable security definer set search_path=pg_catalog,public,pg_temp as $$
 select snapshot||jsonb_build_object('id',id::text,'status',status,'result',result) from guildbattle_sessions_v4 where user_id=auth.uid() and kind=p_kind and request_id=p_request $$;
revoke all on function public.guildbattle_lookup_v4(text,uuid) from public,anon;
grant execute on function public.guildbattle_lookup_v4(text,uuid) to authenticated;
