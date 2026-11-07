-- STAGING ONLY: edit ONLY user_a/user_b (two disposable, logged-in test accounts).
-- action='start': first run sets up both modes; rerunning only extends the clock.
-- action='reset': NEW future test season/week, fresh 3 raid + 5 war attempts.
-- action='stop': restore real clock. Nothing is deleted; rewards are NOT rolled back.
-- Adds five tagged Lv80 cards and one saved story deck to EACH named test account;
-- replaces those test accounts’ war decks (def1/atk1=fixture; def2/atk2 empty),
-- makes two CLOSED Lv3 guilds. Refuses existing unrelated guild memberships.
begin;
do $phase4_seed_guard$ begin
 if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7703759698107299042' then raise exception 'STOP: staging cuyqchmdcnsgzkwyclji only'; end if;
end $phase4_seed_guard$;
do $seed$
declare
 user_a uuid := '00000000-0000-0000-0000-000000000000'; -- EDIT: test account A Auth UUID
 user_b uuid := '00000000-0000-0000-0000-000000000000'; -- EDIT: test account B Auth UUID
 allies_a uuid[] := '{}'; -- OPTIONAL: 2 extra test Auth UUIDs for A => 3 members, full boss-clear test
 allies_b uuid[] := '{}'; -- OPTIONAL: B-side allies
 action text := 'start'; -- start / reset / stop
 u uuid; owner_ uuid; users_ uuid[]; gid bigint; gids bigint[]:='{}'; ids jsonb; o jsonb; owned jsonb; data_ jsonb; sn jsonb; cid text; n int; s date; at_ timestamptz; clock_ guildbattle_test_clock_v4; oldclaims text;
begin
 perform pg_advisory_xact_lock(hashtext('guildbattle:v4'));
 if action='stop' then update guildbattle_test_clock_v4 set at=null,expires_at=null; raise notice '실제 KST 시간으로 복귀. 테스트 자료와 잔액은 유지.'; return; end if;
 if action not in('start','reset') then raise exception 'STOP: bad seed action'; end if;
 if user_a=user_b or not exists(select 1 from auth.users where id=user_a) or not exists(select 1 from auth.users where id=user_b) then raise exception 'STOP: 지정한 테스트 계정 2개로 먼저 로그인하고 Auth UUID를 입력하세요'; end if;
 users_:=array[user_a,user_b]||allies_a||allies_b;
 if (select count(distinct x) from unnest(users_) x)<>cardinality(users_) then raise exception 'STOP: duplicate fixture account'; end if;
 select * into clock_ from guildbattle_test_clock_v4 where singleton for update;
 if clock_.run>0 and exists(select 1 from guilds where id=any(clock_.guild_ids) and boss not in(user_a,user_b)) then raise exception 'STOP: existing fixture belongs to different users'; end if;
 foreach u in array users_ loop
  if not exists(select 1 from auth.users where id=u) then raise exception 'STOP: unknown ally test Auth UUID';end if;
  owner_:=case when u=any(allies_a) then user_a when u=any(allies_b) then user_b else u end;
  if exists(select 1 from guild_members where user_id=u and not(guild_id=any(clock_.guild_ids))) then raise exception 'STOP: 실제 조직원이 아닌 전용 테스트 계정을 사용하세요 (자동 탈퇴하지 않음)'; end if;
  select data into data_ from story_progress where user_id=u for update;
  if not found or data_->>'starter' is null then raise exception 'STOP: 두 계정 모두 스토리 시작 인재를 먼저 선택하세요'; end if;
  select id into gid from guilds where boss=owner_ and name_key='sec4_fixture_'||owner_::text;
  if gid is null then insert into guilds(name,name_key,boss,level,join_mode,notice) values('SEC4_TEST_'||left(owner_::text,8),'sec4_fixture_'||owner_::text,owner_,3,'closed','보안4 테스트 전용 / seed SQL') returning id into gid; end if;
  if not(gid=any(gids)) then gids:=array_append(gids,gid);end if;
  insert into guild_members(user_id,guild_id,role,joined_at) values(u,gid,case when u=owner_ then 'boss' else 'member' end,clock_timestamp()-interval '30 days') on conflict(user_id) do nothing;
  owned:=coalesce(data_->'owned','[]');ids:='[]';n:=0;
  for cid in select id from pvp_card_meta where grade='HIGH RARE' order by cost desc,id limit 5 loop
   n:=n+1;select c into o from jsonb_array_elements(owned) c where c->>'uid'='sec4fixture:'||u||':'||n;
   if o is null then o:=_story_new_card(cid)||jsonb_build_object('uid','sec4fixture:'||u||':'||n,'level',80);owned:=owned||jsonb_build_array(o); end if;
   ids:=ids||jsonb_build_array(o->>'uid');
  end loop;
  if jsonb_array_length(ids)<>5 then raise exception 'STOP: card catalog missing'; end if;
  data_:=jsonb_set(data_,'{owned}',owned);
  if not exists(select 1 from jsonb_array_elements(coalesce(data_->'decks','[]')) d where d->>'name'='SEC4 TEST') then data_:=jsonb_set(data_,'{decks}',coalesce(data_->'decks','[]')||jsonb_build_array(jsonb_build_object('name','SEC4 TEST','uids',ids))); end if;
  update story_progress set data=data_ where user_id=u;
  sn:=_pvp_snap(u,ids,'open')->'cards';
  insert into war_decks_v4(user_id,def1,atk1) values(u,sn,sn) on conflict(user_id) do update set def1=excluded.def1,atk1=excluded.atk1,def2=null,atk2=null;
 end loop;
 n:=greatest(clock_.run,1);if action='reset' then n:=n+1; end if;
 s:=_war_third_wed_v4((date_trunc('month',clock_timestamp() at time zone 'Asia/Seoul')+make_interval(months=>n-1))::date);
 at_:=(s::timestamp+interval '12 hours') at time zone 'Asia/Seoul';
 if action='reset' then
  update guild_raid_attempts_v4 a set voided=true,finished_at=now(),damage=0 where a.user_id=any(users_) and finished_at is null;
  update war_attacks_v4 a set voided=true,finished_at=now(),win=false where a.user_id=any(users_) and finished_at is null;
  update guildbattle_sessions_v4 set status='settled',submission='{"forfeit":true}',result='{"expired":true,"win":false,"damage":0}' where user_id=any(users_) and status='issued';
  update war_ajits_v4 set locked_by=null,locked_until=null where locked_by=any(users_);
 end if;
 update guildbattle_test_clock_v4 set at=case when action='start' and clock_.run>0 then clock_.at else at_ end,set_at=case when action='start' and clock_.run>0 then clock_.set_at else clock_timestamp() end,expires_at=clock_timestamp()+interval '4 hours',run=n,guild_ids=gids where singleton;
 foreach gid in array gids loop perform _raid_get_v4(gid,_raid_week_v4()); end loop;
 perform _war_tick_v4();
 if not exists(select 1 from war_matches_v4 where season=s and day=1 and guild_a=any(gids) and guild_b=any(gids)) then raise exception 'STOP: fixture matchup not created'; end if;
 raise notice '준비 완료: 가상 전투 시작 % KST / 실제 4시간 후 자동 종료. run=% guilds=%',at_ at time zone 'Asia/Seoul',n,gids;
end $seed$;
commit;
select _guildbattle_now_v4() at time zone 'Asia/Seoul' as test_time_kst,expires_at at time zone 'Asia/Seoul' as expires_kst,run,guild_ids from guildbattle_test_clock_v4;
