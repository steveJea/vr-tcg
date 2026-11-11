-- 보안 5단계: 아케이드. 기존 스테이징 업그레이드 전용, 전체 파일 1회 실행(재실행 안전).
-- 운영 금지. 원본 matches/과거 지급은 보존하되 검증 전 기록은 공식 전적·랭킹·미션에 합산하지 않음.
begin;
do $phase5_staging_guard$
begin
 if (select system_identifier::text from pg_control_system()) <> '7703759698107299042' then
  raise exception 'STOP: phase5 only staging cuyqchmdcnsgzkwyclji';
 end if;
 if to_regclass('public.guildbattle_policy_v4') is null then raise exception 'phase4 required'; end if;
end $phase5_staging_guard$;
create table if not exists public.arcade_policy_v5 (
 singleton boolean primary key default true check(singleton), enabled boolean not null default true, engine_hash text not null check(engine_hash ~ '^[a-f0-9]{64}$'));
insert into public.arcade_policy_v5(singleton,engine_hash) values(true,'7c47d4ccb224c0cd7cf8ff9a11a465e68fd645510588249fabb6c8859a39663a')
on conflict(singleton) do update set engine_hash=excluded.engine_hash;
create table if not exists public.arcade_sessions_v5 (
 id bigint generated always as identity primary key,
 user_id uuid not null references auth.users(id) on delete cascade, request uuid not null,
 seed bigint not null check(seed between 0 and 4294967295), options jsonb not null,
 engine_hash text not null, status text not null default 'active' check(status in('active','settled')),
 created_at timestamptz not null default now(), expires_at timestamptz not null default (now()+interval '2 hours'),
 submission jsonb, result jsonb, unique(user_id,request));
create unique index if not exists arcade_one_active_v5 on public.arcade_sessions_v5(user_id) where status='active';
create index if not exists arcade_session_day_v5 on public.arcade_sessions_v5(user_id,created_at);
create table if not exists public.arcade_records_v5 (
 session_id bigint primary key references public.arcade_sessions_v5(id), user_id uuid not null references auth.users(id) on delete cascade,
 result text not null check(result in('win','lose','draw')), verified boolean not null,
 skills int not null default 0 check(skills between 0 and 20000), turns int not null default 0 check(turns between 0 and 400),
 damage bigint not null default 0 check(damage>=0), mvp_id text, mvp_name text, merc_id text,
 day date not null default public._gem_day(), week date not null default public._weekly_week(), created_at timestamptz not null default now(),
 check(verified or (result='lose' and skills=0 and damage=0)));
create index if not exists arcade_records_user_v5 on public.arcade_records_v5(user_id,day,week);
alter table public.arcade_policy_v5 enable row level security;
alter table public.arcade_sessions_v5 enable row level security;
alter table public.arcade_records_v5 enable row level security;
revoke all on public.arcade_policy_v5,public.arcade_sessions_v5,public.arcade_records_v5 from public,anon,authenticated;
revoke all on sequence public.arcade_sessions_v5_id_seq from public,anon,authenticated;

create or replace function public._arcade_enabled_v5() returns boolean language sql stable security definer set search_path=pg_catalog,public,pg_temp as $$ select coalesce((select enabled from public.arcade_policy_v5 where singleton),false) $$;
create or replace function public._arcade_options_v5(o jsonb) returns jsonb language plpgsql immutable set search_path=pg_catalog,public,pg_temp as $$
begin
 if o is null or jsonb_typeof(o)<>'object' or (select count(*) from jsonb_object_keys(o))<>3 or not(o ?& array['grades','turns','clearFirst'])
 or o->'turns' not in ('0'::jsonb,'10'::jsonb,'40'::jsonb) or jsonb_typeof(o->'clearFirst')<>'boolean' then raise exception 'invalid arcade options'; end if;
 if o->'grades'<>'null'::jsonb then
  if jsonb_typeof(o->'grades')<>'array' then raise exception 'invalid arcade options'; end if;
  if jsonb_array_length(o->'grades') not between 1 and 6
  or exists(select 1 from jsonb_array_elements(o->'grades') g where g not in ('"NORMAL"','"RARE"','"HIGH RARE"','"SUPER RARE"','"ULTRA RARE"','"MYTHIC RARE"'))
  or (select count(distinct g) from jsonb_array_elements(o->'grades') g)<>jsonb_array_length(o->'grades') then raise exception 'invalid arcade options'; end if;
 end if;return o;
end $$;
create or replace function public._arcade_close_v5(s public.arcade_sessions_v5, sub jsonb, r jsonb) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare receipt jsonb; verified_ boolean:=r is not null;
begin
 if r is null then r:=jsonb_build_object('result','lose','reason','forfeit','skills',0,'turns',0,'damage',0); end if;
 receipt:=r||jsonb_build_object('session_id',s.id::text,'verified',verified_);
 insert into public.arcade_records_v5(session_id,user_id,result,verified,skills,turns,damage,mvp_id,mvp_name,merc_id)
 values(s.id,s.user_id,r->>'result',verified_,(r->>'skills')::int,(r->>'turns')::int,(r->>'damage')::bigint,r->>'mvp_id',r->>'mvp_name',r->>'merc_id');
 update public.arcade_sessions_v5 set status='settled',submission=sub,result=receipt where id=s.id;
 return jsonb_build_object('ok',true,'status','settled','result',receipt);
end $$;
create or replace function public.arcade_start_v5(p_request uuid,p_options jsonb,p_engine_hash text) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare u uuid:=auth.uid(); s public.arcade_sessions_v5; pol public.arcade_policy_v5; seed_ bigint;
begin
 if u is null then raise exception 'login required'; end if;
 perform pg_advisory_xact_lock(hashtext('arcade-v5:'||u::text));
 select * into pol from public.arcade_policy_v5 where singleton for share;
 if pol.enabled is not true or pol.engine_hash is distinct from p_engine_hash then raise exception 'verifier unavailable'; end if;
 perform public._arcade_options_v5(p_options);if p_request is null then raise exception 'request required';end if;
 select * into s from public.arcade_sessions_v5 where user_id=u and request=p_request;
 if found then
  if s.options is distinct from p_options or s.engine_hash is distinct from p_engine_hash then raise exception 'request conflict';end if;
  return jsonb_build_object('ok',true,'id',s.id::text,'seed',s.seed,'options',s.options,'status',s.status,'result',s.result);
 end if;
 for s in select * from public.arcade_sessions_v5 where user_id=u and status='active' for update loop
  if s.expires_at>now() then raise exception 'active session';end if;
  perform public._arcade_close_v5(s,jsonb_build_object('expired',true),null);
 end loop;
 if (select count(*) from public.arcade_sessions_v5 where user_id=u and created_at>=(public._gem_day()::timestamp at time zone 'Asia/Seoul'))>=500
 or exists(select 1 from public.arcade_sessions_v5 where user_id=u and created_at>now()-interval '2 seconds') then raise exception 'rate limited';end if;
 seed_:=(('x'||substr(replace(gen_random_uuid()::text,'-',''),1,8))::bit(32)::bigint);
 insert into public.arcade_sessions_v5(user_id,request,seed,options,engine_hash) values(u,p_request,seed_,p_options,p_engine_hash) returning * into s;
 return jsonb_build_object('ok',true,'id',s.id::text,'seed',s.seed,'options',s.options,'status',s.status,'result',s.result);
end $$;
create or replace function public.arcade_engine_session_v5(p_uid uuid,p_id bigint) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare s public.arcade_sessions_v5;
begin
 select * into s from public.arcade_sessions_v5 where id=p_id and user_id=p_uid;
 if not found then raise exception 'session not found';end if;
 return jsonb_build_object('id',s.id::text,'seed',s.seed,'options',s.options,'engine_hash',s.engine_hash,'status',s.status,'result',s.result);
end $$;
create or replace function public.arcade_engine_settle_v5(p_uid uuid,p_id bigint,p_engine_hash text,p_submission jsonb,p_result jsonb) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare s public.arcade_sessions_v5; pol public.arcade_policy_v5;
begin
 perform pg_advisory_xact_lock(hashtext('arcade-v5:'||p_uid::text));
 select * into pol from public.arcade_policy_v5 where singleton for share;
 select * into s from public.arcade_sessions_v5 where id=p_id and user_id=p_uid for update;
 if not found then raise exception 'session not found';end if;
 if s.status='settled' then
  if s.submission is distinct from p_submission and s.submission<>'{"expired":true}'::jsonb then raise exception 'submission conflict';end if;
  return jsonb_build_object('ok',true,'status','settled','result',s.result);
 end if;
 if p_submission is null or jsonb_typeof(p_submission)<>'object' or (select count(*) from jsonb_object_keys(p_submission))<>1 then raise exception 'invalid submission';end if;
 if p_submission<>'{"forfeit":true}'::jsonb and (not(p_submission?'actions') or jsonb_typeof(p_submission->'actions')<>'array' or jsonb_array_length(p_submission->'actions')>20000) then raise exception 'invalid submission';end if;
 if s.expires_at<=now() or p_submission='{"forfeit":true}'::jsonb then return public._arcade_close_v5(s,p_submission,null);end if;
 if pol.enabled is not true or pol.engine_hash is distinct from p_engine_hash or s.engine_hash is distinct from p_engine_hash then raise exception 'verifier unavailable';end if;
 if p_result is null or jsonb_typeof(p_result)<>'object' or p_result->>'result' not in ('win','lose','draw')
 or p_result->>'reason' not in ('ko','hp','cards','draw') or (p_result->>'skills')::int not between 0 and 20000 or (p_result->>'turns')::int not between 1 and 400
 or (p_result->>'damage')::bigint<0 then raise exception 'invalid server verdict';end if;
 return public._arcade_close_v5(s,p_submission,p_result);
end $$;
create or replace function public.arcade_record_v5() returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,pg_temp as $$
begin
 if auth.uid() is null then raise exception 'login required';end if;
 return(select jsonb_build_object('wins',count(*) filter(where result='win'),'losses',count(*) filter(where result='lose'),'draws',count(*) filter(where result='draw')) from public.arcade_records_v5 where user_id=auth.uid());
end $$;
-- The old raw report remains private legacy history, never an authoritative source.
revoke all on public.matches from public,anon,authenticated;
grant select on public.matches to authenticated;
-- Column grants can survive table-level REVOKE in older installations.
do $$declare c record;begin for c in select attname from pg_attribute where attrelid='public.matches'::regclass and attnum>0 and not attisdropped loop execute format('revoke insert(%I),update(%I),references(%I) on public.matches from public,anon,authenticated',c.attname,c.attname,c.attname);end loop;end $$;
drop policy if exists matches_own_insert on public.matches;

create or replace view public.rankings_weekly
with (security_invoker = false) as
select
  row_number() over (order by sum(case m.result when 'win' then 3 when 'draw' then 1 else 0 end) desc,
                              count(*) filter (where m.result = 'win') desc,
                              min(m.created_at)) as rank,
  p.nickname,
  sum(case m.result when 'win' then 3 when 'draw' then 1 else 0 end)::int as score,
  (count(*) filter (where m.result = 'win'))::int as wins,
  (count(*) filter (where m.result = 'draw'))::int as draws,
  (count(*) filter (where m.result not in ('win','draw')))::int as losses,
  (m.user_id = auth.uid()) as is_me
from public.arcade_records_v5 m
join public.profiles p on p.id = m.user_id
where m.created_at >= (date_trunc('week', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul')
group by m.user_id, p.nickname;

create or replace view public.rankings_all
with (security_invoker = false) as
select
  row_number() over (order by sum(case m.result when 'win' then 3 when 'draw' then 1 else 0 end) desc,
                              count(*) filter (where m.result = 'win') desc,
                              min(m.created_at)) as rank,
  p.nickname,
  sum(case m.result when 'win' then 3 when 'draw' then 1 else 0 end)::int as score,
  (count(*) filter (where m.result = 'win'))::int as wins,
  (count(*) filter (where m.result = 'draw'))::int as draws,
  (count(*) filter (where m.result not in ('win','draw')))::int as losses,
  (m.user_id = auth.uid()) as is_me
from public.arcade_records_v5 m
join public.profiles p on p.id = m.user_id
group by m.user_id, p.nickname;

revoke all on public.rankings_weekly, public.rankings_all from anon, authenticated;
grant select on public.rankings_weekly, public.rankings_all to anon, authenticated;
-- Replace only progress suppliers; existing verified phase2/3 events still count.
do $$begin if to_regprocedure('public._phase5_old_mission_prog(uuid,text,boolean)') is null then alter function public._clear_mission_prog_v2(uuid,text,boolean) rename to _phase5_old_mission_prog;end if;
if to_regprocedure('public._phase5_old_ach_prog(uuid,text)') is null then alter function public._ach_prog(uuid,text) rename to _phase5_old_ach_prog;end if;end $$;
create or replace function public._clear_mission_prog_v2(u uuid,k text,w boolean) returns int language sql stable security definer set search_path=pg_catalog,public,pg_temp as $$
 select public._phase5_old_mission_prog(u,k,w)+coalesce((select case k when 'skill' then sum(skills) else count(*) end from public.arcade_records_v5
 where user_id=u and verified and case when w then week=public._weekly_week() else day=public._gem_day() end
 and case k when 'arcade' then true when 'win' then result='win' when 'skill' then true else false end),0)::int
$$;
create or replace function public._clear_missions_json_v2(u uuid,w boolean) returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,pg_temp as $$
declare defs jsonb:=case when w then public._weekly_defs() else public._daily_defs() end; period_ date:=case when w then public._weekly_week() else public._gem_day() end;
 claimed_ jsonb; missions jsonb:='[]'; m jsonb; n int; done_ int:=0; a public.daily_attend; res jsonb;
begin
 if w then select claimed into claimed_ from public.weekly_progress where user_id=u and week=period_;
 else select claimed into claimed_ from public.daily_progress where user_id=u and day=period_; end if;
 claimed_:=coalesce(claimed_,'[]');
 for m in select * from jsonb_array_elements(defs) loop
  n:=public._clear_mission_prog_v2(u,m->>'key',w); if n>=(m->>'goal')::int then done_:=done_+1; end if;
  missions:=missions||jsonb_build_array(m||jsonb_build_object('prog',least(n,(m->>'goal')::int),'held',m->>'key'='arcade' and not public._arcade_enabled_v5(),'claimed',claimed_ ? (m->>'key')));
 end loop;
 res:=jsonb_build_object('ok',true,'reward_held',false,'missions',missions,'next_reset',((period_+case when w then 7 else 1 end)::timestamp at time zone 'Asia/Seoul'),
 'all',jsonb_build_object('reward',case when w then public._weekly_all_reward() else public._daily_all_reward() end,'done',done_,'goal',jsonb_array_length(defs),'claimed',claimed_ ? 'all','held',not public._arcade_enabled_v5()));
 if w then return res||jsonb_build_object('week',period_); end if;
 select * into a from public.daily_attend where user_id=u;
 return res||jsonb_build_object('day',period_,'attend',jsonb_build_object('rewards',public._attend_defs(),'step',case when coalesce(a.step,0)>=7 and a.last_day<period_ then 0 else coalesce(a.step,0) end,'today',a.last_day=period_,'total',coalesce(a.total,0)));
end $$;
create or replace function public._daily_json(p_uid uuid) returns jsonb language sql stable security definer set search_path=pg_catalog,public,pg_temp as $$ select public._clear_missions_json_v2(p_uid,false) $$;
create or replace function public._weekly_json(p_uid uuid) returns jsonb language sql stable security definer set search_path=pg_catalog,public,pg_temp as $$ select public._clear_missions_json_v2(p_uid,true) $$;
create or replace function public._clear_mission_claim_v2(k text,w boolean) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare u uuid:=auth.uid(); period_ date:=case when w then public._weekly_week() else public._gem_day() end; m jsonb; claimed_ jsonb; res jsonb;
begin
 if u is null then raise exception 'login required'; end if;
 perform pg_advisory_xact_lock(hashtext('battle-v2:'||u::text)); perform pg_advisory_xact_lock(hashtext('gem:'||u::text));
 if k in ('arcade','all') and not public._arcade_enabled_v5() then raise exception 'reward verification pending';end if;
 if k='all' then
  if exists(select 1 from jsonb_array_elements(case when w then public._weekly_defs() else public._daily_defs() end) x where public._clear_mission_prog_v2(u,x->>'key',w)<(x->>'goal')::int) then raise exception 'not done';end if;
  m:=jsonb_build_object('reward',case when w then public._weekly_all_reward() else public._daily_all_reward() end);
 else
 select x into m from jsonb_array_elements(case when w then public._weekly_defs() else public._daily_defs() end) x where x->>'key'=k;
 if m is null then raise exception 'invalid mission'; end if;
 if public._clear_mission_prog_v2(u,k,w)<(m->>'goal')::int then raise exception 'not done'; end if;
 end if;
 if w then
  insert into public.weekly_progress(user_id,week) values(u,period_) on conflict do nothing;
  select claimed into claimed_ from public.weekly_progress where user_id=u and week=period_ for update;
 else
  insert into public.daily_progress(user_id,day) values(u,period_) on conflict do nothing;
  select claimed into claimed_ from public.daily_progress where user_id=u and day=period_ for update;
 end if;
 if claimed_ ? k then raise exception 'already claimed'; end if;
 if w then update public.weekly_progress set claimed=claimed||to_jsonb(k) where user_id=u and week=period_;
 else update public.daily_progress set claimed=claimed||to_jsonb(k) where user_id=u and day=period_; end if;
 res:=public._daily_grant(u,m->'reward',case when w then 'weekly' else 'daily' end,(case when w then 'weekly:' else 'daily:' end)||period_||':'||k);
 return public._clear_missions_json_v2(u,w)||res||jsonb_build_object('got',m->'reward');
end $$;
create or replace function public.daily_claim(p_key text) returns jsonb language sql security definer set search_path=pg_catalog,public,pg_temp as $$ select public._clear_mission_claim_v2(p_key,false) $$;
create or replace function public.weekly_claim(p_key text) returns jsonb language sql security definer set search_path=pg_catalog,public,pg_temp as $$ select public._clear_mission_claim_v2(p_key,true) $$;

create or replace function public._ach_prog(p_uid uuid,p_id text) returns int language plpgsql stable security definer set search_path=pg_catalog,public,pg_temp as $$
begin
 if p_id='arcade_wins' then return(select count(*)::int from public.arcade_records_v5 where user_id=p_uid and verified and result='win');end if;
 if p_id='skill_uses' then return public._phase5_old_ach_prog(p_uid,p_id)+(select coalesce(sum(skills),0)::int from public.arcade_records_v5 where user_id=p_uid and verified);end if;
 return public._phase5_old_ach_prog(p_uid,p_id);
end $$;
do $$declare src text;begin
 src:=pg_get_functiondef('public._ach_json(uuid)'::regprocedure);
 execute replace(src,'''pvp_tier'')','''pvp_tier'',''arcade_wins'')');
end $$;
-- Explicit ACLs even when the project's default privileges are broad.
revoke all on function public._arcade_enabled_v5(),public._arcade_options_v5(jsonb),public._arcade_close_v5(public.arcade_sessions_v5,jsonb,jsonb),public._phase5_old_mission_prog(uuid,text,boolean),public._phase5_old_ach_prog(uuid,text),public._clear_mission_prog_v2(uuid,text,boolean),public._clear_missions_json_v2(uuid,boolean),public._clear_mission_claim_v2(text,boolean),public._ach_prog(uuid,text) from public,anon,authenticated;
revoke all on function public.arcade_start_v5(uuid,jsonb,text),public.arcade_record_v5(),public.arcade_engine_session_v5(uuid,bigint),public.arcade_engine_settle_v5(uuid,bigint,text,jsonb,jsonb) from public,anon,authenticated;
grant execute on function public.arcade_start_v5(uuid,jsonb,text),public.arcade_record_v5() to authenticated;
do $$declare f record;begin if exists(select 1 from pg_roles where rolname='service_role') then
 revoke all on public.arcade_policy_v5,public.arcade_sessions_v5,public.arcade_records_v5 from service_role;
 revoke all on sequence public.arcade_sessions_v5_id_seq from service_role;
 for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and (p.proname like '%arcade%v5' or p.proname like '_phase5_%') loop execute format('revoke all on function %s from service_role',f.sig);end loop;
 grant execute on function public.arcade_engine_session_v5(uuid,bigint),public.arcade_engine_settle_v5(uuid,bigint,text,jsonb,jsonb) to service_role;
 end if;end $$;
commit;
select 'phase5 arcade verification installed — staging only' as result;
