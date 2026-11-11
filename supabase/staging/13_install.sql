-- ⚠ 테스트 전용 13/14. 운영 실행 금지. 파일 전체를 번호 순서대로 실행.
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
  if exists (select 1 from vr_staging_install.parts where bundle_hash <> '9c2af48c02c3cc678fec379f67d248fd19aaa81a42036235ff2ae7e2ed605408' or project_ref <> 'cuyqchmdcnsgzkwyclji' or db_id <> '7703759698107299042') then
    raise exception 'STOP: 다른 버전/DB의 설치 기록입니다. 파일을 섞지 마세요.';
  end if;
  if exists (select 1 from vr_staging_install.parts where part_no = 13) then
    if not exists (select 1 from vr_staging_install.parts where part_no = 13 and part_hash = 'd0bf38cbdf1df2c65a7575728b4eac01d0762387c693fcc3714385dd474413b1') then
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
  execute $vr_statement$-- Show held legacy floors so honest players can select and replay them for settlement.
create or replace function public.tower_status() returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare u uuid:=auth.uid(); lv int; out_ jsonb:='{}'; tw text; r public.tower_progress; today_ date:=public._tower_today(); paid_ int; pending_ jsonb;
begin
 if u is null then raise exception 'login required'; end if;
 select level into lv from public.player_state where user_id=u;
 foreach tw in array array['normal','wind','ice','fire','light','dark'] loop
  select * into r from public.tower_progress where user_id=u and tower=tw;
  select coalesce((tower_paid->>tw)::int,0) into paid_ from public.battle_legacy_access_v2 where user_id=u;
  select coalesce(jsonb_agg(f order by f),'[]') into pending_ from generate_series(coalesce(paid_,0)+1,coalesce(r.best_floor,0)) f
   where not exists(select 1 from public.battle_clear_receipts_v2 v where v.user_id=u and v.mode='tower' and v.target=tw||':'||f::text);
  out_:=out_||jsonb_build_object(tw,jsonb_build_object('best_floor',coalesce(r.best_floor,0),'paid_floor',coalesce(r.paid_floor,0),'max_floor',public._tower_max_floor(tw),
   'clears',coalesce(r.clears,0),'rewards',coalesce(r.rewards,'{}'),'unpaid_floors',pending_,'reward_held',not public._clear_enabled_v2('tower'),
   'today',case when r.day=today_ then r.day_floors else 0 end,'daily',public._tower_daily(tw),
   'open_today',public._tower_dow()=any(public._tower_days(tw)),'days',to_jsonb(public._tower_days(tw)),
   'min_level',public._tower_min_level(tw),'unlocked',coalesce(lv,1)>=public._tower_min_level(tw)));
 end loop;
 return jsonb_build_object('ok',true,'level',coalesce(lv,1),'dow',public._tower_dow(),'day',today_,'towers',out_);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.story_sweep(p_chapter int,p_phase int,p_runs int default 1) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare u uuid:=auth.uid(); begin
 if u is null then raise exception 'login required'; end if;
 perform pg_advisory_xact_lock(hashtext('battle-v2:'||u::text)); perform pg_advisory_xact_lock(hashtext('gem:'||u::text));
 if not public._clear_enabled_v2('story') then raise exception 'reward verification pending'; end if;
 if not exists(select 1 from public.battle_clear_receipts_v2 where user_id=u and mode='story' and target=p_chapter::text||':'||p_phase::text) then raise exception 'verified clear required for sweep'; end if;
 return public._phase2_old_story_sweep(p_chapter,p_phase,p_runs);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.story_abort_phase() returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare u uuid:=auth.uid(); s public.battle_sessions_v2; begin
 if u is null then raise exception 'login required'; end if;
 perform pg_advisory_xact_lock(hashtext('battle-v2:'||u::text)); perform pg_advisory_xact_lock(hashtext('gem:'||u::text));
 select * into s from public.battle_sessions_v2 where user_id=u and mode='story' and status='issued' for update;
 if found then perform public._clear_close_v2(s,'aborted'); end if;
 return public._player_json(u);
end $$;$vr_statement$;
  execute $vr_statement$do $acl$
declare f record; t text; c record;
begin
 for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prokind='f' and
 (left(p.proname,1)='_' or p.proname=any(array['story_start_phase','story_complete_phase','story_set_stars','tower_start','tower_complete','tower_sweep_start','tower_sweep_complete','quest_start','quest_complete','quest_sweep_start','quest_sweep_complete','battle_session_start_v2','battle_session_finish_v2','battle_session_status_v2','battle_session_abort_v2','story_star_claim','arcade_tut_claim','story_sweep','daily_claim','weekly_claim','story_abort_phase'])) loop
 execute format('revoke all on function %s from public,anon,authenticated',f.sig); end loop;
 foreach t in array array['battle_policy_v2','battle_legacy_access_v2','battle_session_seeds_v2','battle_sessions_v2','battle_clear_receipts_v2','battle_events_v2','battle_acquisitions_v2','battle_card_meta_v2','battle_story_defs_v2','battle_tutorial_defs_v2','tower_progress','quest_progress','story_phase_config'] loop
 execute format('alter table public.%I enable row level security',t);
 if t in ('tower_progress','quest_progress','story_phase_config') then execute format('revoke insert,update,delete,truncate,references,trigger on public.%I from public,anon,authenticated',t);
 else execute format('revoke all on public.%I from public,anon,authenticated',t); end if;
 for c in select attname from pg_attribute where attrelid=to_regclass('public.'||t) and attnum>0 and not attisdropped loop
 execute format('revoke insert(%I),update(%I),references(%I) on public.%I from public,anon,authenticated',c.attname,c.attname,c.attname,t);
 if t not in ('tower_progress','quest_progress','story_phase_config') then execute format('revoke select(%I) on public.%I from public,anon,authenticated',c.attname,t); end if;
 end loop; end loop;
end $acl$;$vr_statement$;
  execute $vr_statement$grant execute on function public.battle_session_start_v2(text,text,jsonb,uuid),public.battle_session_finish_v2(uuid,jsonb),public.battle_session_status_v2(uuid),public.battle_session_abort_v2(uuid),public.arcade_tut_claim(int),public.story_star_claim(int,text),public.story_sweep(int,int,int),public.daily_claim(text),public.weekly_claim(text),public.story_abort_phase() to authenticated;$vr_statement$;
  execute $vr_statement$notify pgrst,'reload schema';$vr_statement$;
  execute $vr_statement$-- 설치본의 단일 트랜잭션에 포함


-- ===== SOURCE: security_phase3_pvp.sql =====
-- STAGING ONLY. After security_phase1_rewards.sql and security_phase2_clears.sql.
-- No credentials, backfill certification, resets or deletes. Deploy pvp-verify-v3 too.
-- 설치본의 단일 트랜잭션에 포함
-- Standalone phase3 guard: enforced by installer entry guard instead.

create table if not exists public.pvp_policy_v3(
 singleton boolean primary key default true check(singleton), engine_hash text not null check(length(engine_hash)=64), enabled boolean not null default true);$vr_statement$;
  execute $vr_statement$insert into public.pvp_policy_v3(singleton,engine_hash) values(true,'e5d7b4060073b9a35814017aba477fa43f3ef678165970c2755b5f210e9cd0da')
 on conflict(singleton) do update set engine_hash=excluded.engine_hash;$vr_statement$;
  execute $vr_statement$-- A clean, verified ladder. Legacy rows remain intact, NOT copied as proof.
create table if not exists public.pvp_ratings_v3(
 user_id uuid not null references auth.users(id), league text not null, mode text not null, season date not null,
 rating int not null default 1000, wins int not null default 0, losses int not null default 0,
 def_wins int not null default 0, def_losses int not null default 0, streak int not null default 0,
 games_verified int not null default 0, updated_at timestamptz not null default now(),
 primary key(user_id,league,mode,season));$vr_statement$;
  execute $vr_statement$create table if not exists public.pvp_sessions_v3(
 id bigint primary key references public.pvp_attempts(id), user_id uuid not null references auth.users(id),
 request_id uuid not null, control text not null check(control in('auto','actions')), engine_hash text not null,
 issued_at timestamptz not null default clock_timestamp(), expires_at timestamptz not null,
 status text not null default 'issued' check(status in('issued','settled')),
 submission jsonb, result jsonb, verified boolean not null default false,
 unique(user_id,request_id));$vr_statement$;
  execute $vr_statement$create index if not exists pvp_sessions_v3_pending on public.pvp_sessions_v3(user_id,status);$vr_statement$;
  execute $vr_statement$create table if not exists public.pvp_events_v3(
 session_id bigint primary key references public.pvp_sessions_v3(id), user_id uuid not null references auth.users(id),
 day date not null, week date not null, win boolean not null, skills int not null check(skills between 0 and 4800));$vr_statement$;
  execute $vr_statement$create or replace function public._pvp_lock_v3(l text,m text,s date) returns void language sql security definer
set search_path=pg_catalog,public,pg_temp as $$ select pg_advisory_xact_lock(hashtext('pvp3:'||l||':'||m||':'||s::text)) $$;$vr_statement$;
  execute $vr_statement$create or replace function public._pvp_rating_v3(u uuid,l text,m text,s date) returns public.pvp_ratings_v3 language plpgsql security definer
set search_path=pg_catalog,public,pg_temp as $$ declare r public.pvp_ratings_v3; p public.pvp_ratings_v3; begin
 select * into p from public.pvp_ratings_v3 where user_id=u and league=l and mode=m and season<s order by season desc limit 1;
 insert into public.pvp_ratings_v3(user_id,league,mode,season,rating,wins,losses,def_wins,def_losses)
  values(u,l,m,s,coalesce(p.rating,1000),coalesce(p.wins,0),coalesce(p.losses,0),coalesce(p.def_wins,0),coalesce(p.def_losses,0))
  on conflict do nothing;
 select * into r from public.pvp_ratings_v3 where user_id=u and league=l and mode=m and season=s; return r;
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._pvp_session_json_v3(a public.pvp_attempts,s public.pvp_sessions_v3) returns jsonb language sql stable security definer
set search_path=pg_catalog,public,pg_temp as $$ select jsonb_build_object('id',a.id::text,'mode',a.mode,'league',a.league,'season',a.season,
 'seed',a.seed,'me',a.my_snap,'opp',a.opp_snap,'opp_name',a.opp_name,'opp_rating',a.opp_rating,'rating',a.my_rating,
 'dw',a.dw,'dl',a.dl,'bot',a.opp_user is null,'control',s.control,'engine_hash',s.engine_hash,'expires_at',s.expires_at,'status',s.status,'result',s.result) $$;$vr_statement$;
  execute $vr_statement$-- Private ledger grants. Do NOT reopen the old _pvp_grant or global battle feeds.
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
end $$;$vr_statement$;
  execute $vr_statement$-- Restore ONLY verified ranked wins' old guild EXP/loyalty feed (10/win, 100/KST day).
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
end $$;$vr_statement$;
  execute $vr_statement$-- Unsubmitted/replaced sessions are server-defined forfeits, already loss-reserved at start.
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
end $$;$vr_statement$;
  execute $vr_statement$-- Server-owned fresh snapshots, including HR guard checks and cross-deck uniqueness.
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
end $$;$vr_statement$;
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


-- ===== SOURCE: security_phase4_raid_guildwar.sql =====
-- STAGING ONLY. Existing installs run this entire file ONCE; reruns are safe.
-- Legacy raid/war history is preserved, never copied as verified evidence.
-- 설치본의 단일 트랜잭션에 포함
-- Phase4 cluster guard is enforced by installer outer guard.
set local check_function_bodies=off;$vr_statement$;
  execute $vr_statement$create table if not exists public.guildbattle_policy_v4(singleton boolean primary key default true check(singleton),engine_hash text not null,enabled boolean not null default true);$vr_statement$;
  execute $vr_statement$insert into public.guildbattle_policy_v4(singleton,engine_hash) values(true,'26b881cf87a09a8f220cc3910106a92542677586c21ca9ce7b3cedb93e32684b') on conflict(singleton) do update set engine_hash=excluded.engine_hash;$vr_statement$;
  execute $vr_statement$do $$ begin
 if not exists(select 1 from pvp_policy_v3) then raise exception 'STOP: install phases 1-3 first'; end if;
end $$;$vr_statement$;
  execute $vr_statement$create table if not exists public.guildbattle_test_clock_v4(singleton boolean primary key default true check(singleton),at timestamptz,set_at timestamptz not null default clock_timestamp(),expires_at timestamptz,run int not null default 0,guild_ids bigint[] not null default '{}');$vr_statement$;
  execute $vr_statement$insert into public.guildbattle_test_clock_v4(singleton) values(true) on conflict do nothing;$vr_statement$;
  execute $vr_statement$create or replace function public._guildbattle_now_v4() returns timestamptz language sql stable security definer set search_path=pg_catalog,public,pg_temp as $$ select coalesce((select at+(clock_timestamp()-set_at) from guildbattle_test_clock_v4 where singleton and expires_at>clock_timestamp()),now()) $$;$vr_statement$;
  execute $vr_statement$create or replace function public._raid_day_v4() returns date language sql stable security definer set search_path=pg_catalog,public,pg_temp as $$ select (_guildbattle_now_v4() at time zone 'Asia/Seoul')::date $$;$vr_statement$;
  execute $vr_statement$create or replace function public._raid_week_v4() returns date language sql stable security definer set search_path=pg_catalog,public,pg_temp as $$ select date_trunc('week',_raid_day_v4()::timestamp)::date $$;$vr_statement$;
  execute $vr_statement$create or replace function public._guildbattle_guard_v4() returns void language plpgsql stable security definer set search_path=pg_catalog,public,pg_temp as $$ begin if not exists(select 1 from guildbattle_policy_v4 where singleton and enabled) then raise exception 'reward verification pending'; end if; end $$;$vr_statement$;
  execute $vr_statement$create table if not exists public.guildbattle_sessions_v4(
 id bigint generated always as identity primary key,user_id uuid not null references auth.users(id),kind text not null check(kind in('raid','war')),attempt_id bigint not null,
 request_id uuid not null,control text not null check(control in('auto','actions')),engine_hash text not null,payload jsonb not null,snapshot jsonb not null,
 issued_at timestamptz not null default clock_timestamp(),expires_at timestamptz not null,status text not null default 'issued' check(status in('issued','settled')),
 submission jsonb,result jsonb,verified boolean not null default false,unique(user_id,kind,request_id),unique(kind,attempt_id));$vr_statement$;
  execute $vr_statement$create table if not exists public.guildbattle_events_v4(session_id bigint primary key references public.guildbattle_sessions_v4(id),user_id uuid not null,guild_id bigint not null,kind text not null,day date not null,metrics jsonb not null,at timestamptz not null default clock_timestamp());$vr_statement$;
  execute $vr_statement$create table if not exists public.guildbattle_sweeps_v4(user_id uuid not null,request_id uuid not null,result jsonb not null,guild_id bigint not null,day date not null,primary key(user_id,request_id));$vr_statement$;
  execute $vr_statement$-- Server-owned snapshot refresh; guest/loan cards remain disallowed, as before.
create or replace function public._war_refresh_v4(u uuid,s jsonb) returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,pg_temp as $$ declare ids jsonb; begin
 if s is null or jsonb_array_length(s)=0 then return null; end if;
 select jsonb_agg(c->>'uid' order by ord) into ids from jsonb_array_elements(s) with ordinality x(c,ord);
 return _pvp_snap(u,ids,'open')->'cards'; exception when others then return null; end $$;$vr_statement$;
  execute $vr_statement$-- ISOLATED VERIFIED TABLES: legacy rows remain untouched.
create table if not exists public.guild_raids_v4 (
  guild_id bigint not null references public.guilds(id) on delete cascade, week date not null,
  difficulty text not null default 'normal' check (difficulty in ('normal', 'hard', 'abyss')),
  members int not null, stage int not null default 1, hp_max bigint not null, hp_left bigint not null,
  total_damage bigint not null default 0, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  primary key (guild_id, week));$vr_statement$;
  execute $vr_statement$create table if not exists public.guild_raid_stages_v4 (
  guild_id bigint not null, week date not null, stage int not null, boss_id text, hp bigint not null,
  cleared_at timestamptz, last_hit uuid references auth.users(id) on delete set null,
  primary key (guild_id, week, stage), foreign key (guild_id, week) references public.guild_raids_v4(guild_id, week) on delete cascade);$vr_statement$;
  execute $vr_statement$create table if not exists public.guild_raid_attempts_v4 (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade, guild_id bigint not null, week date not null, day date not null,
  kind text not null check (kind in ('fight', 'sweep')), stage int not null, difficulty text not null,
  seed bigint, snap jsonb, reported bigint, damage bigint not null default 0, flagged boolean not null default false, voided boolean not null default false,
  started_at timestamptz not null default now(), finished_at timestamptz);$vr_statement$;
  execute $vr_statement$create table if not exists public.guild_raid_damage_v4 (
  guild_id bigint not null, week date not null, user_id uuid not null references auth.users(id) on delete cascade,
  damage bigint not null default 0, attempts int not null default 0, updated_at timestamptz not null default now(),
  primary key (guild_id, week, user_id));$vr_statement$;
  execute $vr_statement$create table if not exists public.war_decks_v4 (
  user_id uuid primary key references auth.users(id) on delete cascade,
  def1 jsonb, def2 jsonb, atk1 jsonb, atk2 jsonb, updated_at timestamptz not null default now());$vr_statement$;
  execute $vr_statement$create table if not exists public.war_entries_v4 (
  season date not null, guild_id bigint not null references public.guilds(id) on delete cascade,
  status text not null default 'in' check (status in ('in', 'out')), locked boolean not null default false, scale numeric not null default 1,
  points int not null default 0, wins int not null default 0, draws int not null default 0, losses int not null default 0, boss_kills int not null default 0, score_total int not null default 0,
  entered_at timestamptz not null default now(), primary key (season, guild_id));$vr_statement$;
  execute $vr_statement$create table if not exists public.war_roster_v4 (
  season date not null, guild_id bigint not null, slot int not null check (slot between 1 and 21), user_id uuid references auth.users(id) on delete set null,
  def_snap jsonb, primary key (season, guild_id, slot), foreign key (season, guild_id) references public.war_entries_v4(season, guild_id) on delete cascade);$vr_statement$;
  execute $vr_statement$create table if not exists public.war_matches_v4 (
  id bigint generated always as identity primary key, season date not null, day int not null check (day between 1 and 5),
  guild_a bigint not null, guild_b bigint, score_a int not null default 0, score_b int not null default 0,
  winner bigint, draw boolean not null default false, boss_kill boolean not null default false, ended_at timestamptz, settled boolean not null default false,
  unique (season, day, guild_a));$vr_statement$;
  execute $vr_statement$create table if not exists public.war_ajits_v4 (
  match_id bigint not null references public.war_matches_v4(id) on delete cascade, side int not null check (side in (0, 1)), slot int not null,
  role text not null, user_id uuid, npc boolean not null default false, snaps jsonb not null default '[]'::jsonb,
  deck int not null default 1, state jsonb, destroyed_at timestamptz, destroyed_by uuid, locked_by uuid, locked_until timestamptz,
  primary key (match_id, side, slot));$vr_statement$;
  execute $vr_statement$create table if not exists public.war_atk_state_v4 (
  match_id bigint not null references public.war_matches_v4(id) on delete cascade, user_id uuid not null, deck int not null check (deck in (1, 2)),
  snap jsonb not null, state jsonb, primary key (match_id, user_id, deck));$vr_statement$;
  execute $vr_statement$create table if not exists public.war_attacks_v4 (
  id bigint generated always as identity primary key, match_id bigint not null references public.war_matches_v4(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade, side int not null, target_slot int not null, atk_deck int not null, def_deck int not null,
  seed bigint not null, atk_snap jsonb not null, def_snap jsonb not null, atk_buff jsonb not null, def_buff jsonb not null,
  before jsonb not null, reported jsonb, win boolean, points int not null default 0, flagged boolean not null default false, voided boolean not null default false,
  started_at timestamptz not null default now(), finished_at timestamptz);$vr_statement$;
  execute $vr_statement$alter table guild_raid_attempts_v4 add column if not exists actions jsonb;$vr_statement$;
  execute $vr_statement$alter table war_attacks_v4 add column if not exists actions jsonb;$vr_statement$;
  execute $vr_statement$create unique index if not exists war_roster_user_v4 on war_roster_v4(season,user_id) where user_id is not null;$vr_statement$;
  execute $vr_statement$insert into war_decks_v4 select * from war_decks on conflict do nothing;$vr_statement$;
  execute $vr_statement$create or replace function public._guild_reward_v4(p_uid uuid, p_gid bigint, p_rw jsonb, p_reason text, p_ref text) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare ok boolean; w jsonb;
begin
  perform _guildbattle_guard_v4();
  p_ref := p_ref || ':v4';
  if p_reason not in('raid_attempt','raid_last_hit','raid_stage','raid_rank','war_reward','guild_daily','guild_weekly') then raise exception 'invalid reward reason'; end if;
  insert into reward_claims(user_id,reward_kind,source_or_period,reward,rule_version) values(p_uid,'guild_'||p_reason||'_v4',p_ref,p_rw,4);
  insert into guild_claims (user_id, ref, guild_id, reward) values (p_uid, p_ref, p_gid, p_rw) on conflict do nothing returning true into ok;
  if not coalesce(ok, false) then raise exception 'already claimed'; end if;
  if coalesce((p_rw->>'loyalty')::int, 0) > 0 then perform _loyalty_add(p_uid, (p_rw->>'loyalty')::int, p_reason, null, jsonb_build_object('ref', p_ref)); end if;
  if coalesce((p_rw->>'gold')::int, 0) > 0 then w := _wallet_add(p_uid, jsonb_build_object('gold', (p_rw->>'gold')::int), p_reason); end if;
  if coalesce((p_rw->>'gem')::int, 0) > 0 then perform _gem_add(p_uid, (p_rw->>'gem')::int, 0, p_reason, 'guild:' || p_ref, jsonb_build_object('guild', p_gid)); end if;
  if coalesce((p_rw->>'tickets')::int, 0) > 0 then
    insert into story_gacha (user_id, last_draw) values (p_uid, _raid_day_v4() - 1) on conflict (user_id) do nothing;
    update story_gacha set tickets = tickets + (p_rw->>'tickets')::int, updated_at = now() where user_id = p_uid;
  end if;
  if coalesce((p_rw->>'exp')::int, 0) > 0 and p_gid is not null then perform _guild_exp(p_gid, p_uid, (p_rw->>'exp')::int, p_reason, 'u:' || p_uid || ':' || p_ref); end if;
  update reward_claims set result=jsonb_build_object('reward',p_rw,'wallet',w) where user_id=p_uid and reward_kind='guild_'||p_reason||'_v4' and source_or_period=p_ref;
  return jsonb_build_object('reward', p_rw, 'wallet', w);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._raid_numbers_v4() returns jsonb language sql immutable as $$ select '{
  "attempts_per_day": 3, "sweep_pct": 90, "min_secs": 3, "open_minutes": 20,
  "hp_per_member": {"normal": 500000, "hard": 1250000, "abyss": 3000000}, "hp_min_members": 5, "hp_growth": 1.35,
  "diff_level": {"normal": 1, "hard": 3, "abyss": 5}, "diff_mult": {"normal": 1, "hard": 1.6, "abyss": 2.5},
  "hit_cap": 6000, "hit_cap_growth": 1.1, "attempt_hits": 200,
  "attempt": {"loyalty": 5, "gold_base": 200, "gold_per_damage": 200, "gold_max": 2000, "exp": 5},
  "stage": {"loyalty": 20, "gold": 2000, "gem": 30, "gem_every3": 150, "tickets_every5": 1, "exp_per_stage": 30},
  "last_hit": {"loyalty": 10},
  "rank": [{"from": 1, "to": 1, "reward": {"gem": 1000, "loyalty": 100}}, {"from": 2, "to": 3, "reward": {"gem": 500, "loyalty": 70}}, {"from": 4, "to": 10, "reward": {"gem": 200, "loyalty": 40}}],
  "member": {"gem": 100, "loyalty": 20},
  "join_hours": 24
}'::jsonb $$;$vr_statement$;
  execute $vr_statement$create or replace function public._raid_boss_v4(p_stage int) returns jsonb language sql immutable as $$
  select (array['{"id":"10325","name":"임유리","weak":"CHARGE"}', '{"id":"10326","name":"[각성] 임유리","weak":"DEFENSE"}',
                '{"id":"10062","name":"김신현","weak":"CRUSH"}', '{"id":"10060","name":"김성진","weak":"SUPPORT"}',
                '{"id":"10311","name":"이지영","weak":"DISTURB"}'])[((greatest(p_stage, 1) - 1) % 5) + 1]::jsonb $$;$vr_statement$;
  execute $vr_statement$create or replace function public._raid_now_v4() returns timestamptz language sql stable as $$ select public._guildbattle_now_v4() $$;$vr_statement$;
  execute $vr_statement$create or replace function public._raid_end_v4(p_week date) returns timestamptz language sql stable as $$ select ((p_week + 6)::timestamp + interval '22 hours') at time zone 'Asia/Seoul' $$;$vr_statement$;
  execute $vr_statement$create or replace function public._raid_hp_v4(p_diff text, p_members int, p_stage int) returns bigint language sql immutable as $$
  select round((_raid_numbers_v4()->'hp_per_member'->>p_diff)::numeric * greatest(p_members, (_raid_numbers_v4()->>'hp_min_members')::int)
               * power((_raid_numbers_v4()->>'hp_growth')::numeric, greatest(p_stage, 1) - 1))::bigint $$;$vr_statement$;
  execute $vr_statement$create or replace function public._raid_attempt_cap_v4(p_stage int) returns bigint language sql immutable as $$
  select round((_raid_numbers_v4()->>'hit_cap')::numeric * power((_raid_numbers_v4()->>'hit_cap_growth')::numeric, greatest(p_stage, 1) - 1)) * (_raid_numbers_v4()->>'attempt_hits')::int $$;$vr_statement$;
  execute $vr_statement$create or replace function public._raid_stage_reward_v4(p_diff text, p_stage int) returns jsonb language sql immutable as $$
  with n as (select _raid_numbers_v4() j), x as (select j->'stage' s, (j->'diff_mult'->>p_diff)::numeric m from n)
  select jsonb_strip_nulls(jsonb_build_object('loyalty', round((s->>'loyalty')::int * m)::int, 'gold', round((s->>'gold')::int * m)::int,
    'gem', round(((s->>'gem')::int + case when p_stage % 3 = 0 then (s->>'gem_every3')::int else 0 end) * m)::int,
    'tickets', case when p_stage % 5 = 0 then (s->>'tickets_every5')::int end)) from x $$;$vr_statement$;
  execute $vr_statement$create or replace function public._raid_rank_reward_v4(p_rank int) returns jsonb language sql immutable as $$
  select coalesce((select r->'reward' from jsonb_array_elements(_raid_numbers_v4()->'rank') r where p_rank between (r->>'from')::int and (r->>'to')::int), '{}'::jsonb) $$;$vr_statement$;
  execute $vr_statement$create or replace function public._raid_get_v4(p_gid bigint, p_week date) returns guild_raids_v4 language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare r guild_raids_v4; n int;
begin
  select * into r from guild_raids_v4 where guild_id = p_gid and week = p_week;
  if r.guild_id is not null then return r; end if;
  select count(*) into n from guild_members where guild_id = p_gid;
  insert into guild_raids_v4 (guild_id, week, members, hp_max, hp_left) values (p_gid, p_week, n, _raid_hp_v4('normal', n, 1), _raid_hp_v4('normal', n, 1)) on conflict do nothing;
  insert into guild_raid_stages_v4 (guild_id, week, stage, boss_id, hp) values (p_gid, p_week, 1, _raid_boss_v4(1)->>'id', _raid_hp_v4('normal', n, 1)) on conflict do nothing;
  select * into r from guild_raids_v4 where guild_id = p_gid and week = p_week;
  return r;
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._raid_hit_v4(p_gid bigint, p_week date, p_uid uuid, p_dmg bigint) returns int language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare r guild_raids_v4; d bigint := greatest(p_dmg, 0); k int := 0; nhp bigint;
begin
  select * into r from guild_raids_v4 where guild_id = p_gid and week = p_week for update;
  update guild_raids_v4 set total_damage = total_damage + d, updated_at = now() where guild_id = p_gid and week = p_week;
  while d > 0 and k < 100 loop
    if d < r.hp_left then r.hp_left := r.hp_left - d; d := 0;
    else
      d := d - r.hp_left; k := k + 1;
      update guild_raid_stages_v4 set cleared_at = now(), last_hit = p_uid where guild_id = p_gid and week = p_week and stage = r.stage;
      perform _guild_exp(p_gid, null, r.stage * (_raid_numbers_v4()->'stage'->>'exp_per_stage')::int, 'raid_stage', 'raid:v4:' || p_week || ':' || r.stage);
      perform _guild_reward_v4(p_uid, p_gid, _raid_numbers_v4()->'last_hit', 'raid_last_hit', 'raidlh:' || p_gid || ':' || p_week || ':' || r.stage);
      r.stage := r.stage + 1; nhp := _raid_hp_v4(r.difficulty, r.members, r.stage); r.hp_max := nhp; r.hp_left := nhp;
      insert into guild_raid_stages_v4 (guild_id, week, stage, boss_id, hp) values (p_gid, p_week, r.stage, _raid_boss_v4(r.stage)->>'id', nhp) on conflict do nothing;
    end if;
  end loop;
  update guild_raids_v4 set stage = r.stage, hp_max = r.hp_max, hp_left = r.hp_left where guild_id = p_gid and week = p_week;
  return k;
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._raid_close_v4(a guild_raid_attempts_v4, p_dmg bigint) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare N jsonb := _raid_numbers_v4(); k int; rw jsonb;
begin
  update guild_raid_attempts_v4 set damage = p_dmg, finished_at = now() where id = a.id;
  insert into guild_raid_damage_v4 (guild_id, week, user_id, damage, attempts) values (a.guild_id, a.week, a.user_id, p_dmg, 1)
    on conflict (guild_id, week, user_id) do update set damage = guild_raid_damage_v4.damage + p_dmg, attempts = guild_raid_damage_v4.attempts + 1, updated_at = now();
  k := _raid_hit_v4(a.guild_id, a.week, a.user_id, p_dmg);
  rw := jsonb_build_object('loyalty', (N->'attempt'->>'loyalty')::int,
    'gold', least((N->'attempt'->>'gold_max')::int, (N->'attempt'->>'gold_base')::int + (p_dmg / (N->'attempt'->>'gold_per_damage')::int)::int), 'exp', (N->'attempt'->>'exp')::int);
  perform _guild_reward_v4(a.user_id, a.guild_id, rw, 'raid_attempt', 'raida:' || a.id);
  if to_regprocedure('public._guild_event(uuid,text,integer)') is not null then perform _guild_event(a.user_id, 'raid', 1); end if;
  return jsonb_build_object('damage', p_dmg, 'cleared', k, 'got', rw - 'exp');
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._raid_status_v4() returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare uid uuid := auth.uid(); m guild_members; g guilds; w date := _raid_week_v4(); r guild_raids_v4; N jsonb := _raid_numbers_v4(); used int; best bigint; fought boolean; open_id bigint;
begin
  m := _guild_me(uid);
  if m.user_id is null then raise exception 'not in guild'; end if;
  select * into g from guilds where id = m.guild_id;
  r := _raid_get_v4(m.guild_id, w);
  select count(*), coalesce(max(damage) filter (where kind = 'fight' and finished_at is not null and not voided and guild_id=m.guild_id and week=w), 0), bool_or(kind = 'fight' and finished_at is not null and not voided and guild_id=m.guild_id and week=w)
    into used, best, fought from guild_raid_attempts_v4 where user_id = uid and day = _raid_day_v4();
  return jsonb_build_object('ok', true, 'week', w, 'ends_at', _raid_end_v4(w), 'ended', _raid_now_v4() >= _raid_end_v4(w),
    'difficulty', r.difficulty, 'guild_level', g.level, 'diff_level', N->'diff_level', 'diff_mult', N->'diff_mult',
    'can_set_diff', m.role in ('boss', 'officer') and r.total_damage = 0 and not exists(select 1 from guild_raid_attempts_v4 where guild_id=m.guild_id and week=w),
    'stage', r.stage, 'hp_max', r.hp_max, 'hp_left', r.hp_left, 'total_damage', r.total_damage, 'boss', _raid_boss_v4(r.stage), 'next_boss', _raid_boss_v4(r.stage + 1),
    'attempts_left', greatest(0, (N->>'attempts_per_day')::int - _guildbattle_used_v4(uid,'raid')), 'best_today', best, 'can_sweep', coalesce(fought, false) and best > 0,
    'sweep_damage', best * (N->>'sweep_pct')::int / 100,
    'ranking', (select coalesce(jsonb_agg(jsonb_build_object('user_id', d.user_id, 'name', coalesce(p.nickname, '조직원'), 'damage', d.damage, 'attempts', d.attempts, 'me', d.user_id = uid) order by d.damage desc, d.user_id), '[]'::jsonb)
                from guild_raid_damage_v4 d left join profiles p on p.id = d.user_id where d.guild_id = m.guild_id and d.week = w and d.damage > 0),
    'stages', (select coalesce(jsonb_agg(jsonb_build_object('stage', s.stage, 'boss', _raid_boss_v4(s.stage), 'cleared', s.cleared_at is not null,
                 'reward', _raid_stage_reward_v4(r.difficulty, s.stage), 'claimed', exists (select 1 from guild_claims c where c.user_id = uid and c.ref = 'raidst:' || w || ':' || s.stage || ':v4')) order by s.stage), '[]'::jsonb)
               from guild_raid_stages_v4 s where s.guild_id = m.guild_id and s.week = w),
    'rank_rewards', N->'rank', 'member_reward', N->'member', 'claimable', _raid_claimable_v4());
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._raid_claimable_v4() returns int language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare uid uuid := auth.uid(); m guild_members; w date; n int := 0;
begin
  m := _guild_me(uid);
  if m.user_id is null then return 0; end if;
  foreach w in array array[_raid_week_v4(), _raid_week_v4() - 7] loop
    n := n + (select count(*) from guild_raid_stages_v4 s join guild_raids_v4 r using (guild_id, week) where s.guild_id = m.guild_id and s.week = w and s.cleared_at is not null and m.joined_at <= s.cleared_at
              and not exists (select 1 from guild_claims c where c.user_id = uid and c.ref = 'raidst:' || w || ':' || s.stage || ':v4'));
    if exists(select 1 from guild_raid_damage_v4 where guild_id=m.guild_id and week=w and damage>0) and _raid_now_v4() >= _raid_end_v4(w) and m.joined_at <= _raid_end_v4(w) - make_interval(hours => (_raid_numbers_v4()->>'join_hours')::int)
       and exists (select 1 from guild_raids_v4 where guild_id = m.guild_id and week = w)
       and not exists (select 1 from guild_claims c where c.user_id = uid and c.ref = 'raidrk:' || w || ':v4') then n := n + 1; end if;
  end loop;
  return n;
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._raid_set_difficulty_v4(p_diff text) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare uid uuid := auth.uid(); m guild_members; r guild_raids_v4; lv int; w date := _raid_week_v4(); nhp bigint;
begin
  m := _guild_me(uid);
  if m.user_id is null then raise exception 'not in guild'; end if;
  if m.role not in ('boss', 'officer') then raise exception 'not allowed'; end if;
  if p_diff not in ('normal', 'hard', 'abyss') then raise exception 'bad difficulty'; end if;
  select level into lv from guilds where id = m.guild_id;
  if lv < (_raid_numbers_v4()->'diff_level'->>p_diff)::int then raise exception 'guild level'; end if;
  r := _raid_get_v4(m.guild_id, w);
  select * into r from guild_raids_v4 where guild_id = m.guild_id and week = w for update;
  if exists(select 1 from guild_raid_attempts_v4 where guild_id=m.guild_id and week=w) or r.total_damage > 0 then raise exception 'raid started'; end if;
  nhp := _raid_hp_v4(p_diff, r.members, 1);
  update guild_raids_v4 set difficulty = p_diff, stage = 1, hp_max = nhp, hp_left = nhp, updated_at = now() where guild_id = m.guild_id and week = w;
  update guild_raid_stages_v4 set hp = nhp where guild_id = m.guild_id and week = w and stage = 1;
  return _raid_status_v4();
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._raid_claim_v4() returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare uid uuid := auth.uid(); m guild_members; w date; s record; rr guild_raids_v4; got jsonb := '{}'::jsonb; rw jsonb; k text; rk int;
begin
  m := _guild_me(uid);
  if m.user_id is null then raise exception 'not in guild'; end if;
  foreach w in array array[_raid_week_v4() - 7, _raid_week_v4()] loop
    select * into rr from guild_raids_v4 where guild_id = m.guild_id and week = w;
    if rr.guild_id is null then continue; end if;
    for s in select * from guild_raid_stages_v4 where guild_id = m.guild_id and week = w and cleared_at is not null and m.joined_at <= cleared_at order by stage loop
      if exists (select 1 from guild_claims where user_id = uid and ref = 'raidst:' || w || ':' || s.stage || ':v4') then continue; end if;
      rw := _raid_stage_reward_v4(rr.difficulty, s.stage);
      perform _guild_reward_v4(uid, m.guild_id, rw, 'raid_stage', 'raidst:' || w || ':' || s.stage);
      for k in select jsonb_object_keys(rw) loop got := jsonb_set(got, array[k], to_jsonb(coalesce((got->>k)::int, 0) + (rw->>k)::int)); end loop;
    end loop;
    if exists(select 1 from guild_raid_damage_v4 where guild_id=m.guild_id and week=w and damage>0) and _raid_now_v4() >= _raid_end_v4(w) and m.joined_at <= _raid_end_v4(w) - make_interval(hours => (_raid_numbers_v4()->>'join_hours')::int)
       and not exists (select 1 from guild_claims where user_id = uid and ref = 'raidrk:' || w || ':v4') then
      select x.rk into rk from (select user_id, row_number() over (order by damage desc, user_id) rk from guild_raid_damage_v4 where guild_id = m.guild_id and week = w and damage > 0) x where x.user_id = uid;
      rw := _raid_numbers_v4()->'member';
      if rk is not null then
        for k in select jsonb_object_keys(_raid_rank_reward_v4(rk)) loop rw := jsonb_set(rw, array[k], to_jsonb(coalesce((rw->>k)::int, 0) + (_raid_rank_reward_v4(rk)->>k)::int)); end loop;
      end if;
      perform _guild_reward_v4(uid, m.guild_id, rw || jsonb_build_object('rank', rk), 'raid_rank', 'raidrk:' || w);
      for k in select jsonb_object_keys(rw) loop got := jsonb_set(got, array[k], to_jsonb(coalesce((got->>k)::int, 0) + (rw->>k)::int)); end loop;
      got := got || jsonb_build_object('rank', rk);
    end if;
  end loop;
  if got = '{}'::jsonb then raise exception 'nothing to claim'; end if;
  return _raid_status_v4() || jsonb_build_object('got', got);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._war_numbers_v4() returns jsonb language sql immutable as $$ select '{
  "min_members": 10, "attacks_per_day": 5, "open_hour": 9, "close_hour": 23, "min_secs": 3, "open_minutes": 20, "lock_minutes": 3, "hp_cap": 60000,
  "layout": {"def": [1,2,3,4,5], "atk": [6,7,8,9,10], "mid": [11,12,13], "boss": [14], "etc": [15,16,17,18,19,20,21]},
  "roles": {"def": {"atk": 1, "def": 1.2}, "atk": {"atk": 1.2, "def": 1}, "mid": {"atk": 1.15, "def": 1.15}, "boss": {"atk": 1.25, "def": 1.25}, "etc": {"atk": 1, "def": 1}},
  "points": {"def": 200, "atk": 150, "etc": 150, "mid": 250, "boss": 400},
  "standings": {"win": 3, "draw": 2, "loss": 0, "boss_bonus": 1},
  "npc_level": 10, "npc_scale": 1, "signup_days_before": 3,
  "match_win": {"loyalty": 60, "gold": 5000}, "match_boss_kill": {"loyalty": 20, "gold": 2000}, "match_draw": {"loyalty": 20, "gold": 1500}, "match_loss": {"loyalty": 10}, "match_exp_win": 300,
  "season_rank": [{"from": 1, "to": 1, "reward": {"gem": 1000, "loyalty": 300}}, {"from": 2, "to": 2, "reward": {"gem": 700, "loyalty": 200}}, {"from": 3, "to": 3, "reward": {"gem": 500, "loyalty": 150}},
                  {"from": 4, "to": 10, "reward": {"gem": 300, "loyalty": 100}}, {"from": 11, "to": 30, "reward": {"gem": 150, "loyalty": 50}}],
  "season_member": {"gem": 100, "loyalty": 30}
}'::jsonb $$;$vr_statement$;
  execute $vr_statement$create or replace function public._war_role_v4(p_slot int) returns text language sql immutable as $$
  select case when p_slot <= 5 then 'def' when p_slot <= 10 then 'atk' when p_slot <= 13 then 'mid' when p_slot = 14 then 'boss' else 'etc' end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._war_now_v4() returns timestamptz language sql stable as $$ select public._guildbattle_now_v4() $$;$vr_statement$;
  execute $vr_statement$create or replace function public._war_kst_v4() returns timestamp language sql stable as $$ select _war_now_v4() at time zone 'Asia/Seoul' $$;$vr_statement$;
  execute $vr_statement$create or replace function public._war_third_wed_v4(p_d date) returns date language sql immutable as $$
  select (date_trunc('month', p_d)::date + ((3 - extract(isodow from date_trunc('month', p_d))::int + 7) % 7) + 14) $$;$vr_statement$;
  execute $vr_statement$create or replace function public._war_season_v4() returns date language sql stable as $$
  select case when _war_kst_v4()::date <= _war_third_wed_v4(_war_kst_v4()::date) + 4 then _war_third_wed_v4(_war_kst_v4()::date)
              else _war_third_wed_v4((date_trunc('month', _war_kst_v4()) + interval '1 month')::date) end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._war_at_v4(p_season date, p_day int, p_hour int) returns timestamptz language sql immutable as $$
  select ((p_season + p_day - 1)::timestamp + make_interval(hours => p_hour)) at time zone 'Asia/Seoul' $$;$vr_statement$;
  execute $vr_statement$create or replace function public._war_day_v4(p_season date) returns int language sql stable as $$
  select case when _war_kst_v4()::date between p_season and p_season + 4 then (_war_kst_v4()::date - p_season) + 1 end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._war_phase_v4(p_season date) returns text language sql stable as $$
  select case when _war_now_v4() < _war_at_v4(p_season, 1 - (_war_numbers_v4()->>'signup_days_before')::int, 0) then 'soon'
              when _war_now_v4() < _war_at_v4(p_season, 1, (_war_numbers_v4()->>'open_hour')::int) then 'signup'
              when _war_now_v4() >= _war_at_v4(p_season, 5, (_war_numbers_v4()->>'close_hour')::int) then 'ended'
              when extract(hour from _war_kst_v4()) >= (_war_numbers_v4()->>'open_hour')::int and extract(hour from _war_kst_v4()) < (_war_numbers_v4()->>'close_hour')::int then 'live'
              else 'rest' end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._war_npc_deck_v4(p_seed text, p_scale numeric) returns jsonb language plpgsql stable as $$
declare hr text[] := array['10151','10152','10163','10164','10165','10166','10167','10168'];
        r text[] := array['10148','10149','10150','10159','10160','10161','10162'];
        male text[] := array['10148','10149','10150','10151','10152'];   -- 성별은 ID 첫 자리가 아니라 카드 데이터(gender)로 (ID 변경 후에도 맞게)
        a text[]; b text[]; ids text[]; alt text; out jsonb := '[]'::jsonb; i int;
begin
  select array_agg(x order by md5(p_seed || ':h:' || x)) into a from unnest(hr) x;
  select array_agg(x order by md5(p_seed || ':r:' || x)) into b from unnest(r) x;
  ids := a[1:2] || b[1:3];
  if (select count(distinct (x = any(male))) from unnest(ids) x) < 2 then
    select x into alt from unnest(b[4:7]) x where (x = any(male)) <> (ids[1] = any(male)) limit 1;
    ids[5] := alt;
  end if;
  for i in 1..5 loop out := out || jsonb_build_object('uid', 'n' || i, 'id', ids[i], 'level', (_war_numbers_v4()->>'npc_level')::int, 'scale', p_scale); end loop;
  return out;
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._war_scale_v4(p_season date, p_gid bigint) returns numeric language sql stable security definer set search_path=pg_catalog,public,pg_temp as $$
  select coalesce((_war_numbers_v4()->>'npc_scale')::numeric, 1) $$;$vr_statement$;
  execute $vr_statement$create or replace function public._war_lock_v4(p_season date) returns void language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare e record; u record; s int; sc numeric;
begin
  for e in select * from war_entries_v4 where season = p_season and not locked loop
    for u in select gm.user_id from guild_members gm where gm.guild_id = e.guild_id
               and not exists (select 1 from war_roster_v4 r where r.season = p_season and r.user_id = gm.user_id) order by _war_power_v4(gm.user_id) desc, gm.joined_at loop
      select x into s from unnest(array[14,1,2,3,4,5,6,7,8,9,10,11,12,13,15,16,17,18,19,20,21]) with ordinality t(x, o)
        where not exists (select 1 from war_roster_v4 r where r.season = p_season and r.guild_id = e.guild_id and r.slot = x and r.user_id is not null) order by o limit 1;
      exit when s is null;
      insert into war_roster_v4 (season, guild_id, slot, user_id) values (p_season, e.guild_id, s, u.user_id) on conflict (season, guild_id, slot) do update set user_id = excluded.user_id;
    end loop;
    update war_roster_v4 r set user_id = null where r.season = p_season and r.guild_id = e.guild_id and r.user_id is not null
      and not exists (select 1 from guild_members gm where gm.user_id = r.user_id and gm.guild_id = e.guild_id);
    for u in select r.user_id from war_roster_v4 r where r.season = p_season and r.guild_id = e.guild_id and r.user_id is not null loop perform _war_auto_deck_v4(u.user_id); end loop;
    update war_roster_v4 r set def_snap = (select case when _war_refresh_v4(r.user_id,d.def1) is null then null else jsonb_build_array(_war_refresh_v4(r.user_id,d.def1),coalesce(_war_refresh_v4(r.user_id,d.def2),'[]'::jsonb)) end from war_decks_v4 d where d.user_id = r.user_id)
      where r.season = p_season and r.guild_id = e.guild_id and r.user_id is not null;
    sc := _war_scale_v4(p_season, e.guild_id);
    update war_entries_v4 set locked = true, scale = sc, status = 'in' where season = p_season and guild_id = e.guild_id;
  end loop;
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._war_build_side_v4(p_mid bigint, p_side int, p_season date, p_gid bigint, p_scale numeric) returns void language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare i int; r war_roster_v4; sn jsonb;
begin
  for i in 1..21 loop
    r := null;
    if p_gid is not null then select * into r from war_roster_v4 where season = p_season and guild_id = p_gid and slot = i; end if;
    sn := case when r.def_snap is not null and jsonb_array_length(coalesce(r.def_snap->0, '[]'::jsonb)) > 0 then r.def_snap
               else jsonb_build_array(_war_npc_deck_v4(p_mid || ':' || p_side || ':' || i || ':1', p_scale), _war_npc_deck_v4(p_mid || ':' || p_side || ':' || i || ':2', p_scale)) end;
    insert into war_ajits_v4 (match_id, side, slot, role, user_id, npc, snaps) values (p_mid, p_side, i, _war_role_v4(i), r.user_id, r.def_snap is null or jsonb_array_length(coalesce(r.def_snap->0, '[]'::jsonb)) = 0, sn)
      on conflict do nothing;
  end loop;
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._war_pair_v4(p_season date, p_day int) returns void language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare ids bigint[]; used bigint[] := '{}'; a bigint; b bigint; mid bigint; i int; j int; sa numeric; sb numeric;
begin
  if exists (select 1 from war_matches_v4 where season = p_season and day = p_day) then return; end if;
  if p_day = 1 then
    select array_agg(e.guild_id order by g.exp desc, g.level desc, e.guild_id) into ids from war_entries_v4 e join guilds g on g.id = e.guild_id where e.season = p_season and e.status = 'in';
  else
    select array_agg(e.guild_id order by e.points desc, e.score_total desc, e.guild_id) into ids from war_entries_v4 e where e.season = p_season and e.status = 'in';
  end if;
  if ids is null then return; end if;
  for i in 1..array_length(ids, 1) loop
    a := ids[i]; if a = any(used) then continue; end if;
    b := null;
    for j in i + 1..array_length(ids, 1) loop   -- 가장 가까운, 아직 안 붙은 상대
      continue when ids[j] = any(used);
      if not exists (select 1 from war_matches_v4 m where m.season = p_season and ((m.guild_a = a and m.guild_b = ids[j]) or (m.guild_a = ids[j] and m.guild_b = a))) then b := ids[j]; exit; end if;
    end loop;
    if b is null then select x into b from unnest(ids[i + 1:]) x where not x = any(used) limit 1; end if;   -- 다 붙었으면 가장 가까운 조직
    used := used || a || coalesce(b, a);
    insert into war_matches_v4 (season, day, guild_a, guild_b) values (p_season, p_day, a, b) returning id into mid;
    select scale into sa from war_entries_v4 where season = p_season and guild_id = a;
    select scale into sb from war_entries_v4 where season = p_season and guild_id = b;
    perform _war_build_side_v4(mid, 0, p_season, a, sa);
    perform _war_build_side_v4(mid, 1, p_season, b, coalesce(sb, sa));   -- NPC 조직 = 상대 배율
  end loop;
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._war_settle_v4(p_mid bigint) returns void language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare m war_matches_v4; N jsonb := _war_numbers_v4(); win bigint; dr boolean := false; side int;
begin
  select * into m from war_matches_v4 where id = p_mid for update;
  if m.settled then return; end if;
  if m.winner is null then
    if m.score_a > m.score_b then win := m.guild_a; elsif m.score_b > m.score_a then win := coalesce(m.guild_b, -1); else dr := true; end if;
  else win := m.winner; end if;
  update war_matches_v4 set winner = win, draw = dr, settled = true, ended_at = coalesce(ended_at, _war_now_v4()) where id = p_mid;
  for side in 0..1 loop
    continue when (case side when 0 then m.guild_a else m.guild_b end) is null;
    update war_entries_v4 e set
      points = points + case when dr then (N->'standings'->>'draw')::int when win = e.guild_id then (N->'standings'->>'win')::int + case when m.boss_kill then (N->'standings'->>'boss_bonus')::int else 0 end else (N->'standings'->>'loss')::int end,
      wins = wins + (not dr and win = e.guild_id)::int, draws = draws + dr::int, losses = losses + (not dr and win is distinct from e.guild_id)::int,
      boss_kills = boss_kills + (m.boss_kill and win = e.guild_id)::int, score_total = score_total + case side when 0 then m.score_a else m.score_b end
      where season = m.season and guild_id = case side when 0 then m.guild_a else m.guild_b end;
  end loop;
  if win > 0 then perform _guild_exp(win, null, (N->>'match_exp_win')::int, 'war_win', 'war:v4:' || p_mid); end if;
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._war_tick_v4() returns date language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare s date := _war_season_v4(); d int; m record;
begin
  if _war_now_v4() < _war_at_v4(s, 1, (_war_numbers_v4()->>'open_hour')::int) then perform _war_auto_enter_v4(s); return s; end if;
  perform pg_advisory_xact_lock(hashtext('war:' || s));
  perform _war_auto_enter_v4(s);   -- 잠금 직전에 레벨 3 된 조직도 포함 (_war_lock_v4 이 잠금)
  perform _war_lock_v4(s);
  for d in 1..5 loop
    exit when _war_now_v4() < _war_at_v4(s, d, (_war_numbers_v4()->>'open_hour')::int);
    perform _war_pair_v4(s, d);
    if _war_now_v4() >= _war_at_v4(s, d, (_war_numbers_v4()->>'close_hour')::int) then
      for m in select id from war_matches_v4 where season = s and day = d and not settled loop perform _war_settle_v4(m.id); end loop;
    end if;
  end loop;
  return s;
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._war_set_deck_v4(p_kind text, p_uids jsonb) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare uid uuid := auth.uid(); sn jsonb := null; other jsonb; s date;
begin
  if uid is null then raise exception 'login required'; end if;
  if p_kind not in ('def1', 'def2', 'atk1', 'atk2') then raise exception 'bad deck'; end if;
  s := _war_tick_v4();
  if p_kind like 'def%' and _war_phase_v4(s) not in ('soon', 'signup', 'ended') and exists (select 1 from war_roster_v4 where season = s and user_id = uid) then raise exception 'defense locked'; end if;
  if jsonb_array_length(coalesce(p_uids, '[]'::jsonb)) > 0 then sn := _pvp_snap(uid, p_uids, 'open')->'cards'; end if;
  insert into war_decks_v4 (user_id) values (uid) on conflict do nothing;
  select case p_kind when 'def1' then def2 when 'def2' then def1 when 'atk1' then atk2 else atk1 end into other from war_decks_v4 where user_id = uid;
  if sn is not null and other is not null and exists (select 1 from jsonb_array_elements(sn) a, jsonb_array_elements(other) b where a->>'id' = b->>'id') then raise exception 'same card in both decks'; end if;
  execute format('update war_decks_v4 set %I = $1, updated_at = now() where user_id = $2', p_kind) using sn, uid;
  return jsonb_build_object('ok', true, 'decks', (select to_jsonb(d) - 'user_id' from war_decks_v4 d where user_id = uid));
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._war_enter_v4() returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare uid uuid := auth.uid(); m guild_members; s date := _war_tick_v4();
begin
  m := _guild_me(uid);
  if m.user_id is null then raise exception 'not in guild'; end if;
  if m.role not in ('boss', 'officer') then raise exception 'not allowed'; end if;
  if _war_phase_v4(s) <> 'signup' then raise exception 'signup closed'; end if;
  if (select count(*) from guild_members where guild_id = m.guild_id) < (_war_numbers_v4()->>'min_members')::int then raise exception 'need members'; end if;
  insert into war_entries_v4 (season, guild_id) values (s, m.guild_id) on conflict do nothing;
  return _war_status_v4();
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._war_withdraw_v4() returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare uid uuid := auth.uid(); m guild_members; s date := _war_tick_v4();
begin
  m := _guild_me(uid);
  if m.user_id is null or m.role <> 'boss' then raise exception 'not allowed'; end if;
  if _war_phase_v4(s) <> 'signup' then raise exception 'signup closed'; end if;
  delete from war_entries_v4 where season = s and guild_id = m.guild_id;
  return _war_status_v4();
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._war_set_slot_v4(p_slot int, p_user uuid) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare uid uuid := auth.uid(); m guild_members; s date := _war_tick_v4(); e war_entries_v4;
begin
  m := _guild_me(uid);
  if m.user_id is null or m.role <> 'boss' then raise exception 'not allowed'; end if;
  if p_slot not between 1 and 21 then raise exception 'bad slot'; end if;
  select * into e from war_entries_v4 where season = s and guild_id = m.guild_id;
  if e.guild_id is null then raise exception 'not entered'; end if;
  if e.locked then
    if p_slot <> 14 then raise exception 'roster locked'; end if;
    if _war_phase_v4(s) = 'live' then raise exception 'battle hours'; end if;
  end if;
  if p_user is not null and not exists (select 1 from guild_members where user_id = p_user and guild_id = m.guild_id) then raise exception 'not member'; end if;
  if p_user is not null then delete from war_roster_v4 where season = s and guild_id = m.guild_id and user_id = p_user; end if;
  insert into war_roster_v4 (season, guild_id, slot, user_id) values (s, m.guild_id, p_slot, p_user) on conflict (season, guild_id, slot) do update set user_id = excluded.user_id;
  if p_user is not null then perform _war_auto_deck_v4(p_user); end if;
  if e.locked then   -- 잠금 뒤: 방어 덱 스냅 즉시 (다음 경기에 반영)
    update war_roster_v4 r set def_snap = (select case when _war_refresh_v4(r.user_id,d.def1) is null then null else jsonb_build_array(_war_refresh_v4(r.user_id,d.def1),coalesce(_war_refresh_v4(r.user_id,d.def2),'[]'::jsonb)) end from war_decks_v4 d where d.user_id = r.user_id)
      where r.season = s and r.guild_id = m.guild_id and r.slot = 14;
    if p_user is null then update war_roster_v4 set def_snap = null where season = s and guild_id = m.guild_id and slot = 14; end if;
  end if;
  return _war_status_v4();
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._war_side_json_v4(p_mid bigint, p_side int) returns jsonb language sql stable security definer set search_path=pg_catalog,public,pg_temp as $$
  select coalesce(jsonb_agg(jsonb_build_object('slot', a.slot, 'role', a.role, 'npc', a.npc, 'user_id', a.user_id,
      'name', case when a.npc and a.user_id is null then '동네 불량배' else coalesce(p.nickname, '조직원') end, 'deck', a.deck, 'decks', jsonb_array_length(a.snaps) - (case when jsonb_array_length(coalesce(a.snaps->1, '[]'::jsonb)) = 0 then 1 else 0 end),
      'cards', (select coalesce(jsonb_agg(jsonb_build_object('id', c->>'id', 'level', c->'level', 'scale', c->'scale', 'snapshot', jsonb_build_object('id',c->'id','level',c->'level','ex',c->'ex','exb',c->'exb','boost',c->'boost','skillLv',c->'skillLv','gear',c->'gear','sigil',c->'sigil','scale',c->'scale'), 'hp', a.state->(c->>'uid'))), '[]'::jsonb) from jsonb_array_elements(a.snaps->(a.deck - 1)) c),
      'destroyed', a.destroyed_at is not null, 'locked', a.locked_until > _war_now_v4()) order by a.slot), '[]'::jsonb)
  from war_ajits_v4 a left join profiles p on p.id = a.user_id where a.match_id = p_mid and a.side = p_side $$;$vr_statement$;
  execute $vr_statement$create or replace function public._war_status_v4() returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare uid uuid := auth.uid(); m guild_members; s date; e war_entries_v4; mt war_matches_v4; my int; d int; res jsonb; me_slot int; used int := 0;
begin
  if uid is null then raise exception 'login required'; end if;
  s := _war_tick_v4(); d := _war_day_v4(s); m := _guild_me(uid);
  res := jsonb_build_object('ok', true, 'season', s, 'season_end', s + 4, 'phase', _war_phase_v4(s), 'day', d,
    'opens_at', _war_at_v4(s, coalesce(d, 1) + case when d is not null and _war_now_v4() >= _war_at_v4(s, d, (_war_numbers_v4()->>'close_hour')::int) then 1 else 0 end, (_war_numbers_v4()->>'open_hour')::int),
    'closes_at', case when d is not null then _war_at_v4(s, d, (_war_numbers_v4()->>'close_hour')::int) end,
    'numbers', _war_numbers_v4() - 'npc_scale' - 'layout',
    'decks', (select to_jsonb(x) - 'user_id' from war_decks_v4 x where user_id = uid),
    'standings', (select coalesce(jsonb_agg(jsonb_build_object('rank', rk, 'guild_id', guild_id, 'name', name, 'emblem', emblem, 'points', points, 'wins', wins, 'draws', draws, 'losses', losses, 'boss_kills', boss_kills, 'score', score_total, 'me', guild_id = m.guild_id) order by rk), '[]'::jsonb)
                  from (select e2.*, g.name, g.emblem, row_number() over (order by e2.points desc, e2.boss_kills desc, e2.score_total desc, e2.guild_id) rk from war_entries_v4 e2 join guilds g on g.id = e2.guild_id where e2.season = s and e2.status = 'in') t where rk <= 30 or guild_id = m.guild_id),
    'claimable', _war_claimable_v4());
  if m.user_id is null then return res || jsonb_build_object('guild', null); end if;
  select * into e from war_entries_v4 where season = s and guild_id = m.guild_id;
  res := res || jsonb_build_object('guild', jsonb_build_object('id', m.guild_id, 'role', m.role, 'members', (select count(*) from guild_members where guild_id = m.guild_id)),
    'entry', to_jsonb(e) - 'season',
    'roster', (select coalesce(jsonb_agg(jsonb_build_object('slot', x, 'role', _war_role_v4(x), 'user_id', r.user_id, 'name', p.nickname,
                 'ready', (select dd.def1 is not null from war_decks_v4 dd where dd.user_id = r.user_id)) order by x), '[]'::jsonb)
               from generate_series(1, 21) x left join war_roster_v4 r on r.season = s and r.guild_id = m.guild_id and r.slot = x left join profiles p on p.id = r.user_id),
    'members', (select coalesce(jsonb_agg(jsonb_build_object('user_id', gm.user_id, 'name', coalesce(p.nickname, '조직원'), 'role', gm.role,
                  'ready', (select dd.def1 is not null from war_decks_v4 dd where dd.user_id = gm.user_id))), '[]'::jsonb) from guild_members gm left join profiles p on p.id = gm.user_id where gm.guild_id = m.guild_id));
  if d is null then return res; end if;
  select * into mt from war_matches_v4 where season = s and day = d and (guild_a = m.guild_id or guild_b = m.guild_id);
  if mt.id is null then return res; end if;
  my := case when mt.guild_a = m.guild_id then 0 else 1 end;
  select slot into me_slot from war_ajits_v4 where match_id = mt.id and side = my and user_id = uid;
  used := _guildbattle_used_v4(uid,'war',mt.id);
  return res || jsonb_build_object('match', jsonb_build_object('id', mt.id, 'day', mt.day, 'side', my,
    'opponent', case when (case my when 0 then mt.guild_b else mt.guild_a end) is null then jsonb_build_object('name', '동네 불량배파', 'npc', true, 'emblem', 0)
                else (select jsonb_build_object('id', g.id, 'name', g.name, 'emblem', g.emblem, 'level', g.level, 'npc', false) from guilds g where g.id = case my when 0 then mt.guild_b else mt.guild_a end) end,
    'score_me', case my when 0 then mt.score_a else mt.score_b end, 'score_opp', case my when 0 then mt.score_b else mt.score_a end,
    'ended', mt.ended_at is not null or mt.settled, 'winner_me', mt.winner = m.guild_id, 'draw', mt.draw, 'boss_kill', mt.boss_kill,
    'gate_open', not exists (select 1 from war_ajits_v4 where match_id = mt.id and side = 1 - my and role = 'def' and destroyed_at is null),
    'me', jsonb_build_object('slot', me_slot, 'alive', me_slot is not null and exists (select 1 from war_ajits_v4 where match_id = mt.id and side = my and slot = me_slot and destroyed_at is null),
      'attacks_left', greatest(0, (_war_numbers_v4()->>'attacks_per_day')::int - used),
      'atk', (select coalesce(jsonb_object_agg(deck, jsonb_build_object('alive', (select count(*) from jsonb_array_elements(snap) c where coalesce((state->>(c->>'uid'))::int, 1) > 0))), '{}'::jsonb) from war_atk_state_v4 where match_id = mt.id and user_id = uid)),
    'mine', _war_side_json_v4(mt.id, my), 'enemy', _war_side_json_v4(mt.id, 1 - my)));
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._war_sum_v4(a jsonb, b jsonb) returns jsonb language sql immutable as $$
  select coalesce(jsonb_object_agg(k, coalesce((a->>k)::int, 0) + coalesce((b->>k)::int, 0)), '{}'::jsonb) from (select jsonb_object_keys(a) k union select jsonb_object_keys(b)) x $$;$vr_statement$;
  execute $vr_statement$create or replace function public._war_pending_v4(p_uid uuid) returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,pg_temp as $$
declare out jsonb := '[]'::jsonb; r record; N jsonb := _war_numbers_v4(); rk int;
begin
  for r in select mt.*, wr.guild_id gid from war_roster_v4 wr join war_matches_v4 mt on mt.season = wr.season and (mt.guild_a = wr.guild_id or mt.guild_b = wr.guild_id)
            where wr.user_id = p_uid and mt.settled and wr.season >= _war_season_v4() - 62 loop
    continue when exists (select 1 from guild_claims where user_id = p_uid and ref = 'warm:' || r.id || ':v4');
    out := out || jsonb_build_object('ref', 'warm:' || r.id, 'gid', r.gid, 'reward', case when r.draw then N->'match_draw' when r.winner is distinct from r.gid then N->'match_loss' else (N->'match_win') ||
      case when r.boss_kill then _war_sum_v4(N->'match_win', N->'match_boss_kill') else '{}'::jsonb end end);
  end loop;
  for r in select wr.season, wr.guild_id from war_roster_v4 wr join war_entries_v4 e on e.season = wr.season and e.guild_id = wr.guild_id and e.status = 'in' and e.locked and (select count(distinct wm.day) from war_matches_v4 wm where wm.season=wr.season and (wm.guild_a=wr.guild_id or wm.guild_b=wr.guild_id) and wm.settled)=5
            where wr.user_id = p_uid and wr.season >= _war_season_v4() - 62 and _war_now_v4() >= _war_at_v4(wr.season, 5, (N->>'close_hour')::int) loop
    continue when exists (select 1 from guild_claims where user_id = p_uid and ref = 'wars:' || r.season || ':v4');
    select x.rk into rk from (select guild_id, row_number() over (order by points desc, boss_kills desc, score_total desc, guild_id) rk from war_entries_v4 where season = r.season and status = 'in') x where x.guild_id = r.guild_id;
    out := out || jsonb_build_object('ref', 'wars:' || r.season, 'gid', r.guild_id, 'rank', rk, 'reward', _war_sum_v4(N->'season_member',
      coalesce((select q->'reward' from jsonb_array_elements(N->'season_rank') q where rk between (q->>'from')::int and (q->>'to')::int), '{}'::jsonb)));
  end loop;
  return out;
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._war_claimable_v4() returns int language sql stable security definer set search_path=pg_catalog,public,pg_temp as $$ select jsonb_array_length(_war_pending_v4(auth.uid())) $$;$vr_statement$;
  execute $vr_statement$create or replace function public._war_claim_v4() returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare uid uuid := auth.uid(); p jsonb; x jsonb; got jsonb := '{}'::jsonb; k text;
begin
  if uid is null then raise exception 'login required'; end if;
  perform _war_tick_v4();
  p := _war_pending_v4(uid);
  if jsonb_array_length(p) = 0 then raise exception 'nothing to claim'; end if;
  for x in select * from jsonb_array_elements(p) loop
    perform _guild_reward_v4(uid, (x->>'gid')::bigint, x->'reward', 'war_reward', x->>'ref');
    for k in select jsonb_object_keys(x->'reward') loop got := jsonb_set(got, array[k], to_jsonb(coalesce((got->>k)::int, 0) + (x->'reward'->>k)::int)); end loop;
    if x ? 'rank' then got := got || jsonb_build_object('rank', x->'rank'); end if;
  end loop;
  return _war_status_v4() || jsonb_build_object('got', got);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._war_leader_card_v4(p_uid uuid) returns text language sql stable security definer set search_path=pg_catalog,public,pg_temp as $$
  select o->>'id' from story_progress sp, jsonb_array_elements(coalesce(sp.data->'owned', '[]'::jsonb)) o where sp.user_id = p_uid and o->>'uid' = sp.data->>'leader' limit 1 $$;$vr_statement$;
  execute $vr_statement$create or replace function public._war_ui_v4() returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare uid uuid := auth.uid(); m guild_members; s date; d int; mid bigint;
begin
  if uid is null then raise exception 'login required'; end if;
  s := _war_season_v4(); d := _war_day_v4(s); m := _guild_me(uid);
  if m.user_id is null then return jsonb_build_object('ok', true, 'signed', '[]'::jsonb, 'me_signed', false, 'cards', '{}'::jsonb); end if;
  select id into mid from war_matches_v4 where season = s and day = d and (guild_a = m.guild_id or guild_b = m.guild_id);
  return jsonb_build_object('ok', true,
    'signed', (select coalesce(jsonb_agg(user_id), '[]'::jsonb) from war_signups where season = s and guild_id = m.guild_id),
    'me_signed', exists (select 1 from war_signups where season = s and user_id = uid),
    'cards', (select coalesce(jsonb_object_agg(u, _war_leader_card_v4(u)) filter (where _war_leader_card_v4(u) is not null), '{}'::jsonb) from (
       select gm.user_id u from guild_members gm where gm.guild_id = m.guild_id
       union select a.user_id from war_ajits_v4 a where a.match_id = mid and a.user_id is not null) x));
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._war_min_level_v4() returns int language sql immutable as $$ select 3 $$;$vr_statement$;
  execute $vr_statement$create or replace function public._war_card_score_v4(p_id text, p_level int, p_ex int) returns numeric language sql stable security definer set search_path=pg_catalog,public,pg_temp as $$
  select coalesce((select case m.grade when 'LEGENDARY RARE' then 7 when 'MYTHIC RARE' then 6 when 'ULTRA RARE' then 5 when 'SUPER RARE' then 4 when 'HIGH RARE' then 3 when 'RARE' then 2 else 1 end
                   from pvp_card_meta m where m.id = p_id), 0) * 1000 + coalesce(p_level, 1) * 20 + coalesce(p_ex, 0) * 50 $$;$vr_statement$;
  execute $vr_statement$create or replace function public._war_power_v4(p_user uuid) returns numeric language sql stable security definer set search_path=pg_catalog,public,pg_temp as $$
  select coalesce(sum(_war_card_score_v4(x->>'id', (x->>'level')::int, (x->>'ex')::int)), 0) from story_progress sp,
    jsonb_array_elements(case when jsonb_typeof(sp.data->'owned') = 'array' then sp.data->'owned' else '[]'::jsonb end) x
  where sp.user_id = p_user and x->>'uid' in (select jsonb_array_elements_text(_war_top5(p_user))) $$;$vr_statement$;
  execute $vr_statement$create or replace function public._war_auto_deck_v4(p_user uuid) returns void language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare t jsonb; sn jsonb;
begin
  if p_user is null then return; end if;
  if exists (select 1 from war_decks_v4 where user_id = p_user and def1 is not null and atk1 is not null) then return; end if;
  t := _war_top5(p_user); if jsonb_array_length(t) = 0 then return; end if;
  begin sn := _pvp_snap(p_user, t, 'open')->'cards'; exception when others then return; end;
  insert into war_decks_v4 (user_id) values (p_user) on conflict do nothing;
  update war_decks_v4 set def1 = coalesce(def1, case when def2 is null or not exists (select 1 from jsonb_array_elements(sn) a, jsonb_array_elements(def2) b where a->>'id' = b->>'id') then sn end),
                       atk1 = coalesce(atk1, case when atk2 is null or not exists (select 1 from jsonb_array_elements(sn) a, jsonb_array_elements(atk2) b where a->>'id' = b->>'id') then sn end),
                       updated_at = now() where user_id = p_user;
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._war_auto_enter_v4(p_season date) returns void language sql security definer set search_path=pg_catalog,public,pg_temp as $$
  insert into war_entries_v4 (season, guild_id) select p_season, g.id from guilds g where g.level >= _war_min_level_v4() and (not exists(select 1 from guildbattle_test_clock_v4 where expires_at>clock_timestamp()) or g.id in(select unnest(guild_ids) from guildbattle_test_clock_v4 where singleton)) on conflict do nothing $$;$vr_statement$;
  execute $vr_statement$create or replace function public._war_auto_assign_v4() returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare uid uuid := auth.uid(); m guild_members; s date := _war_tick_v4(); e war_entries_v4; u record; i int := 0;
        ord int[] := array[14,1,2,3,4,5,6,7,8,9,10,11,12,13,15,16,17,18,19,20,21];
begin
  m := _guild_me(uid);
  if m.user_id is null or m.role <> 'boss' then raise exception 'not allowed'; end if;
  select * into e from war_entries_v4 where season = s and guild_id = m.guild_id;
  if e.guild_id is null then raise exception 'not entered'; end if;
  if e.locked then raise exception 'roster locked'; end if;
  delete from war_roster_v4 where season = s and guild_id = m.guild_id;
  for u in select gm.user_id from guild_members gm where gm.guild_id = m.guild_id order by _war_power_v4(gm.user_id) desc, gm.joined_at loop
    i := i + 1; exit when i > 21;
    insert into war_roster_v4 (season, guild_id, slot, user_id) values (s, m.guild_id, ord[i], u.user_id);
    perform _war_auto_deck_v4(u.user_id);
  end loop;
  return _war_status_v4();
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._war_meta_v4() returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,pg_temp as $$
declare uid uuid := auth.uid(); m guild_members;
begin
  if uid is null then raise exception 'login required'; end if;
  m := _guild_me(uid);
  return jsonb_build_object('ok', true, 'min_level', _war_min_level_v4(),
    'guild_level', (select level from guilds where id = m.guild_id),
    'need_deck', m.user_id is not null and not exists (select 1 from war_decks_v4 d where d.user_id = uid and d.def1 is not null and d.atk1 is not null));
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._raid_start_v4(p_uids jsonb) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare uid uuid := auth.uid(); m guild_members; w date := _raid_week_v4(); r guild_raids_v4; N jsonb := _raid_numbers_v4(); snap jsonb; seed bigint; aid bigint;
begin
  m := _guild_me(uid);
  if m.user_id is null then raise exception 'not in guild'; end if;
  if _raid_now_v4() >= _raid_end_v4(w) then raise exception 'raid ended'; end if;
  perform pg_advisory_xact_lock(hashtext('raid:' || uid));
  -- 끝내지 않은 판은 0 피해로 마감 (횟수는 이미 씀)
  update guild_raid_attempts_v4 set finished_at = now(), damage = 0 where user_id = uid and finished_at is null;
  if _guildbattle_used_v4(uid,'raid') >= (N->>'attempts_per_day')::int then raise exception 'no attempts'; end if;
  r := _raid_get_v4(m.guild_id, w);
  snap := _pvp_snap(uid, p_uids, 'open')->'cards';
  seed := floor(random() * 2147483647)::bigint;
  insert into guild_raid_attempts_v4 (user_id, guild_id, week, day, kind, stage, difficulty, seed, snap)
    values (uid, m.guild_id, w, _raid_day_v4(), 'fight', r.stage, r.difficulty, seed, snap) returning id into aid;
  return jsonb_build_object('ok', true, 'id', aid, 'seed', seed, 'deck', snap, 'stage', r.stage, 'difficulty', r.difficulty, 'boss', _raid_boss_v4(r.stage));
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._war_start_v4(p_slot int, p_deck int) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare uid uuid := auth.uid(); s date; d int; N jsonb := _war_numbers_v4(); m guild_members; mt war_matches_v4; my int; me war_ajits_v4; t war_ajits_v4; st war_atk_state_v4; snap jsonb;
        atk jsonb; def jsonb; seed bigint; aid bigint; ab jsonb; db jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  s := _war_tick_v4(); d := _war_day_v4(s);
  if _war_phase_v4(s) <> 'live' then raise exception 'not battle time'; end if;
  m := _guild_me(uid);
  select * into mt from war_matches_v4 where season = s and day = d and (guild_a = m.guild_id or guild_b = m.guild_id) for update;
  if mt.id is null then raise exception 'no match'; end if;
  if mt.ended_at is not null then raise exception 'match ended'; end if;
  my := case when mt.guild_a = m.guild_id then 0 else 1 end;
  select * into me from war_ajits_v4 where match_id = mt.id and side = my and user_id = uid;
  if me.slot is null then raise exception 'not in roster'; end if;
  if me.destroyed_at is not null then raise exception 'ajit destroyed'; end if;
  perform pg_advisory_xact_lock(hashtext('waratk:' || uid));
  update war_attacks_v4 set finished_at = now(), win = false where user_id = uid and finished_at is null;   -- 끝내지 않은 판 = 패배(변화 없음)
  update war_ajits_v4 set locked_by = null, locked_until = null where locked_by = uid;
  if _guildbattle_used_v4(uid,'war',mt.id) >= (N->>'attacks_per_day')::int then raise exception 'no attacks'; end if;
  select * into t from war_ajits_v4 where match_id = mt.id and side = 1 - my and slot = p_slot for update;
  if t.slot is null then raise exception 'bad target'; end if;
  if t.destroyed_at is not null then raise exception 'already destroyed'; end if;
  if t.locked_until > _war_now_v4() then raise exception 'target busy'; end if;
  if t.role <> 'def' and exists (select 1 from war_ajits_v4 where match_id = mt.id and side = 1 - my and role = 'def' and destroyed_at is null) then raise exception 'defense first'; end if;
  if p_deck not in (1, 2) then raise exception 'bad deck'; end if;
  select * into st from war_atk_state_v4 where match_id = mt.id and user_id = uid and deck = p_deck;
  if st.match_id is null then
    select case p_deck when 1 then atk1 else atk2 end into snap from war_decks_v4 where user_id = uid;
    if snap is null or jsonb_array_length(snap) = 0 then raise exception 'no attack deck'; end if;
    snap := _war_refresh_v4(uid,snap); if snap is null then raise exception 'card not owned'; end if;
    insert into war_atk_state_v4 (match_id, user_id, deck, snap) values (mt.id, uid, p_deck, snap) returning * into st;
  end if;
  select coalesce(jsonb_agg(c || jsonb_build_object('hp', st.state->(c->>'uid'))), '[]'::jsonb) into atk from jsonb_array_elements(st.snap) c where coalesce((st.state->>(c->>'uid'))::int, 1) > 0;
  if jsonb_array_length(atk) = 0 then raise exception 'deck dead'; end if;
  select coalesce(jsonb_agg(c || jsonb_build_object('hp', t.state->(c->>'uid'))), '[]'::jsonb) into def from jsonb_array_elements(t.snaps->(t.deck - 1)) c where coalesce((t.state->>(c->>'uid'))::int, 1) > 0;
  ab := jsonb_build_object('atk', (N->'roles'->me.role->>'atk')::numeric, 'def', case when me.role in ('mid', 'boss') then (N->'roles'->me.role->>'def')::numeric else 1 end);   -- 공격 측
  db := jsonb_build_object('atk', case when t.role in ('mid', 'boss') then (N->'roles'->t.role->>'atk')::numeric else 1 end, 'def', (N->'roles'->t.role->>'def')::numeric);   -- 방어 측
  seed := floor(random() * 2147483647)::bigint;
  update war_ajits_v4 set locked_by = uid, locked_until = _war_now_v4() + make_interval(mins => (N->>'open_minutes')::int) where match_id = mt.id and side = t.side and slot = t.slot;
  insert into war_attacks_v4 (match_id, user_id, side, target_slot, atk_deck, def_deck, seed, atk_snap, def_snap, atk_buff, def_buff, before)
    values (mt.id, uid, my, p_slot, p_deck, t.deck, seed, atk, def, ab, db, jsonb_build_object('atk_state', st.state, 'def_state', t.state, 'def_deck', t.deck))
    returning id into aid;
  return jsonb_build_object('ok', true, 'id', aid, 'seed', seed, 'atk', atk, 'def', def, 'atk_buff', ab, 'def_buff', db, 'target', jsonb_build_object('slot', t.slot, 'role', t.role, 'deck', t.deck, 'npc', t.npc));
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._war_finish_v4(p_uid uuid,p_id bigint, p_win boolean, p_atk_hp jsonb, p_def_hp jsonb) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare uid uuid := p_uid; a war_attacks_v4; N jsonb := _war_numbers_v4(); mt war_matches_v4; t war_ajits_v4; cap int := (_war_numbers_v4()->>'hp_cap')::int;
        ast jsonb := '{}'::jsonb; dst jsonb := '{}'::jsonb; c jsonb; hp int; iswin boolean; pts int := 0; flag boolean := false; next_ok boolean;
begin
  select * into a from war_attacks_v4 where id = p_id and user_id = uid for update;
  if a.id is null then raise exception 'no battle'; end if;
  if a.finished_at is not null then raise exception 'already finished'; end if;
  select * into mt from war_matches_v4 where id = a.match_id for update;
  select * into t from war_ajits_v4 where match_id = a.match_id and side = 1 - a.side and slot = a.target_slot for update;
  if now() - a.started_at > make_interval(mins => (N->>'open_minutes')::int) or t.destroyed_at is not null or t.deck <> a.def_deck or mt.settled then
    update war_attacks_v4 set finished_at = now(), win = false where id = a.id;
    update war_ajits_v4 set locked_by = null, locked_until = null where match_id = t.match_id and side = t.side and slot = t.slot and locked_by = uid;
    return jsonb_build_object('result', jsonb_build_object('win', false, 'expired', true));
  end if;
  -- 남은 HP (이전보다 클 수 없음, 없으면 쓰러짐)
  for c in select * from jsonb_array_elements(a.atk_snap) loop
    hp := greatest(0, least(coalesce((p_atk_hp->>(c->>'uid'))::int, 0), coalesce((c->>'hp')::int, cap)));
    if coalesce((p_atk_hp->>(c->>'uid'))::int, 0) > coalesce((c->>'hp')::int, cap) then flag := true; end if;
    ast := ast || jsonb_build_object(c->>'uid', hp);
  end loop;
  for c in select * from jsonb_array_elements(a.def_snap) loop
    hp := case when p_win then 0 else greatest(0, least(coalesce((p_def_hp->>(c->>'uid'))::int, 0), coalesce((c->>'hp')::int, cap))) end;
    dst := dst || jsonb_build_object(c->>'uid', hp);
  end loop;
  iswin := p_win or not exists (select 1 from jsonb_each_text(dst) x where x.value::int > 0);
  if not exists (select 1 from jsonb_each_text(ast) x where x.value::int > 0) and iswin then flag := true; end if;   -- 둘 다 전멸 = 의심
  update war_atk_state_v4 set state = coalesce(state, '{}'::jsonb) || ast where match_id = a.match_id and user_id = uid and deck = a.atk_deck;
  if iswin then
    next_ok := t.deck = 1 and jsonb_array_length(coalesce(t.snaps->1, '[]'::jsonb)) > 0;
    if next_ok then
      update war_ajits_v4 set deck = 2, state = null where match_id = t.match_id and side = t.side and slot = t.slot;   -- 2번 덱 등장
    else
      pts := (N->'points'->>t.role)::int;
      update war_ajits_v4 set destroyed_at = now(), destroyed_by = uid, state = dst where match_id = t.match_id and side = t.side and slot = t.slot;
      update war_matches_v4 set score_a = score_a + case a.side when 0 then pts else 0 end, score_b = score_b + case a.side when 1 then pts else 0 end where id = mt.id;
      if t.role = 'boss' then
        update war_matches_v4 set boss_kill = true, winner = coalesce(case a.side when 0 then mt.guild_a else mt.guild_b end, -1), ended_at = now() where id = mt.id;
      end if;
    end if;
  else
    update war_ajits_v4 set state = coalesce(state, '{}'::jsonb) || dst where match_id = t.match_id and side = t.side and slot = t.slot;
  end if;
  update war_ajits_v4 set locked_by = null, locked_until = null where match_id = t.match_id and side = t.side and slot = t.slot;
  update war_attacks_v4 set finished_at = now(), win = iswin, points = pts, flagged = flag, reported = jsonb_build_object('win', p_win, 'atk', p_atk_hp, 'def', p_def_hp) where id = a.id;
  return jsonb_build_object('result', jsonb_build_object('win', iswin, 'points', pts, 'next_deck', iswin and next_ok, 'destroyed', iswin and not next_ok, 'boss_kill', t.role = 'boss' and iswin and not next_ok));
end $$;$vr_statement$;
  execute $vr_statement$-- Operator-only fixture budget baselines; never delete or relabel combat/reward evidence.
create table if not exists public.guildbattle_test_refills_v4(
 id bigint generated always as identity primary key,
 user_id uuid not null references auth.users(id) on delete cascade,
 guild_id bigint not null, kind text not null check(kind in('raid','war')),
 day date not null, match_id bigint, run int not null, clock_set_at timestamptz not null,
 used_base bigint not null check(used_base>=0), at timestamptz not null default clock_timestamp(),
 check((kind='raid' and match_id is null) or (kind='war' and match_id is not null))
);$vr_statement$;
  execute $vr_statement$create index if not exists guildbattle_test_refills_scope_v4 on public.guildbattle_test_refills_v4(user_id,kind,day,run,clock_set_at);$vr_statement$;
  execute $vr_statement$alter table public.guildbattle_test_refills_v4 enable row level security;$vr_statement$;
  execute $vr_statement$revoke all on public.guildbattle_test_refills_v4 from public,anon,authenticated;$vr_statement$;
  execute $vr_statement$revoke all on sequence public.guildbattle_test_refills_v4_id_seq from public,anon,authenticated;$vr_statement$;
  execute $vr_statement$-- Same effective count is used by issuance, sweep AND status. Normal users retain 3 / 5 caps.
-- Allowance is valid ONLY inside this staging DB's still-active, identical fixture clock/run,
-- day/match and guild membership. Closing/resetting the clock disables old baselines.
create or replace function public._guildbattle_used_v4(p_uid uuid,p_kind text,p_mid bigint default null) returns bigint language plpgsql stable security definer set search_path=pg_catalog,public,pg_temp as $budget$
declare total_ bigint; base_ bigint; gid bigint; c guildbattle_test_clock_v4; mt war_matches_v4; d date:=_raid_day_v4();
begin
 if p_kind='raid' then
  select (select count(*) from guild_raid_attempts where user_id=p_uid and day=d)+(select count(*) from guild_raid_attempts_v4 where user_id=p_uid and day=d) into total_;
 elsif p_kind='war' and p_mid is not null then
  select * into mt from war_matches_v4 where id=p_mid;
  if mt.id is null then raise exception 'bad budget match'; end if;
  select (select count(*) from war_attacks_v4 where match_id=p_mid and user_id=p_uid)+(select count(*) from war_attacks a join war_matches m on m.id=a.match_id where a.user_id=p_uid and m.season=mt.season and m.day=mt.day) into total_;
 else raise exception 'bad budget kind'; end if;
 select * into c from guildbattle_test_clock_v4 where singleton;
 if c.at is null or c.expires_at is null or c.expires_at<=clock_timestamp() or c.run<1 or (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7703759698107299042' then return total_; end if;
 select g.id into gid from guild_members gm join guilds g on g.id=gm.guild_id where gm.user_id=p_uid and g.id=any(c.guild_ids) and g.name_key='sec4_fixture_'||g.boss::text;
 if gid is null or not exists(select 1 from story_progress sp,jsonb_array_elements(coalesce(sp.data->'owned','[]')) o where sp.user_id=p_uid and o->>'uid' like 'sec4fixture:'||p_uid||':%') then return total_; end if;
 if p_kind='war' and (mt.season<>_war_season_v4() or mt.day is distinct from _war_day_v4(mt.season) or (gid is distinct from mt.guild_a and gid is distinct from mt.guild_b)) then return total_; end if;
 select coalesce(max(used_base),0) into base_ from guildbattle_test_refills_v4 where user_id=p_uid and guild_id=gid and kind=p_kind and day=d and match_id is not distinct from p_mid and run=c.run and clock_set_at=c.set_at;
 return greatest(0,total_-least(total_,base_));
end $budget$;$vr_statement$;
  execute $vr_statement$revoke all on function public._guildbattle_used_v4(uuid,text,bigint) from public,anon,authenticated;$vr_statement$;
  execute $vr_statement$-- Defend against hostile defaults or later column grants when the seed is rerun standalone.
do $refill_acl$ declare cols text; begin
 select string_agg(quote_ident(attname),',') into cols from pg_attribute where attrelid='public.guildbattle_test_refills_v4'::regclass and attnum>0 and not attisdropped;
 execute format('revoke select(%1$s),insert(%1$s),update(%1$s),references(%1$s) on public.guildbattle_test_refills_v4 from public,anon,authenticated',cols);
 if exists(select 1 from pg_roles where rolname='service_role') then
  revoke all on public.guildbattle_test_refills_v4 from service_role;
  revoke all on sequence public.guildbattle_test_refills_v4_id_seq from service_role;
  revoke all on function public._guildbattle_used_v4(uuid,text,bigint) from service_role;
  execute format('revoke select(%1$s),insert(%1$s),update(%1$s),references(%1$s) on public.guildbattle_test_refills_v4 from service_role',cols);
 end if;
end $refill_acl$;$vr_statement$;
  execute $vr_statement$-- Finish ALL already-frozen past seasons before rankings/claims are evaluated.
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
end $$;$vr_statement$;
  execute $vr_statement$-- SERVER ISSUANCE. One global phase4 transaction lock establishes a consistent lock
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
  if _guildbattle_used_v4(u,'raid')>=3 then raise exception 'no attempts'; end if;
  b:=_raid_start_v4(p_payload->'uids');
 else b:=_war_start_v4((p_payload->>'slot')::int,(p_payload->>'deck')::int);
 end if;
 aid:=(b->>'id')::bigint; ex:=clock_timestamp()+interval '20 minutes';
 b:=(b-'id')||jsonb_build_object('kind',p_kind);
 insert into guildbattle_sessions_v4(user_id,kind,attempt_id,request_id,control,engine_hash,payload,snapshot,expires_at) values(u,p_kind,aid,p_request,p_control,p_engine_hash,p_payload,b,ex) returning * into s;
 return b||jsonb_build_object('id',s.id::text,'control',p_control,'engine_hash',p_engine_hash,'expires_at',ex,'status','issued','result',null);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.guildbattle_engine_session_v4(p_uid uuid,p_id bigint) returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,pg_temp as $$ declare s guildbattle_sessions_v4; begin
 select * into s from guildbattle_sessions_v4 where id=p_id and user_id=p_uid;
 if not found then raise exception 'session not found'; end if;
 return s.snapshot||jsonb_build_object('id',s.id::text,'control',s.control,'engine_hash',s.engine_hash,'status',s.status,'result',s.result);
end $$;$vr_statement$;
  execute $vr_statement$-- Only the authenticated Edge verifier's service role can call this. Result is
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
end $$;$vr_statement$;

  insert into vr_staging_install.parts(part_no, bundle_hash, part_hash, project_ref, db_id)
  values (13, '9c2af48c02c3cc678fec379f67d248fd19aaa81a42036235ff2ae7e2ed605408', 'd0bf38cbdf1df2c65a7575728b4eac01d0762387c693fcc3714385dd474413b1', 'cuyqchmdcnsgzkwyclji', '7703759698107299042');
end $vr_install_part$;
commit;
select '13_install.sql: 완료 또는 이미 완료 (13/14)' as result;
