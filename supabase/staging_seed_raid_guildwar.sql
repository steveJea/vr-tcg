-- STAGING ONLY: edit ONLY user_a/user_b (two disposable, logged-in test accounts).
-- action='start': first run sets up both modes; rerunning only extends the clock.
-- action='refill': SAME live fixture; only refill 3 raid / 5 war attempts, cancel pending reservations.
-- Keeps BOTH sides' HP/decks/score, boss, evidence, balances AND clock unchanged. Repeat as needed.
-- action='reset': NEW future test season/week, fresh 3 raid + 5 war attempts.
-- action='stop': restore real clock. Nothing is deleted; rewards are NOT rolled back.
-- start/reset adds five tagged Lv80 cards and one saved story deck to EACH named test account;
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
 action text := 'start'; -- start / refill / reset / stop
 u uuid; owner_ uuid; users_ uuid[]; gid bigint; gids bigint[]:='{}'; ids jsonb; o jsonb; owned jsonb; data_ jsonb; sn jsonb; cid text; n int; s date; at_ timestamptz; clock_ guildbattle_test_clock_v4; oldclaims text; mt war_matches_v4; k text; base_ bigint;
begin
 perform pg_advisory_xact_lock(hashtext('guildbattle:v4'));
 -- Generated, atomic installer: existing staging needs ONLY this seed file, no Edge redeploy.
 if not exists(select 1 from guildbattle_policy_v4 where singleton and engine_hash='26b881cf87a09a8f220cc3910106a92542677586c21ca9ce7b3cedb93e32684b') then raise exception 'STOP: seed/phase4 engine version mismatch'; end if;
if to_regclass('public.guildbattle_sessions_v4') is null or exists(select 1 from unnest(array['public._raid_status_v4()','public._war_status_v4()','public._raid_start_v4(jsonb)','public._war_start_v4(integer,integer)','public.guildbattle_start_v4(text,jsonb,uuid,text,text)','public.raid_sweep_v4(uuid)']) sig where to_regprocedure(sig) is null) then raise exception 'STOP: install phase4 SQL first'; end if;
 execute $phase4_refill_install$
-- Operator-only fixture budget baselines; never delete or relabel combat/reward evidence.
create table if not exists public.guildbattle_test_refills_v4(
 id bigint generated always as identity primary key,
 user_id uuid not null references auth.users(id) on delete cascade,
 guild_id bigint not null, kind text not null check(kind in('raid','war')),
 day date not null, match_id bigint, run int not null, clock_set_at timestamptz not null,
 used_base bigint not null check(used_base>=0), at timestamptz not null default clock_timestamp(),
 check((kind='raid' and match_id is null) or (kind='war' and match_id is not null))
);
create index if not exists guildbattle_test_refills_scope_v4 on public.guildbattle_test_refills_v4(user_id,kind,day,run,clock_set_at);
alter table public.guildbattle_test_refills_v4 enable row level security;
revoke all on public.guildbattle_test_refills_v4 from public,anon,authenticated;
revoke all on sequence public.guildbattle_test_refills_v4_id_seq from public,anon,authenticated;

-- Same effective count is used by issuance, sweep AND status. Normal users retain 3 / 5 caps.
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
end $budget$;
revoke all on function public._guildbattle_used_v4(uuid,text,bigint) from public,anon,authenticated;
-- Defend against hostile defaults or later column grants when the seed is rerun standalone.
do $refill_acl$ declare cols text; begin
 select string_agg(quote_ident(attname),',') into cols from pg_attribute where attrelid='public.guildbattle_test_refills_v4'::regclass and attnum>0 and not attisdropped;
 execute format('revoke select(%1$s),insert(%1$s),update(%1$s),references(%1$s) on public.guildbattle_test_refills_v4 from public,anon,authenticated',cols);
 if exists(select 1 from pg_roles where rolname='service_role') then
  revoke all on public.guildbattle_test_refills_v4 from service_role;
  revoke all on sequence public.guildbattle_test_refills_v4_id_seq from service_role;
  revoke all on function public._guildbattle_used_v4(uuid,text,bigint) from service_role;
  execute format('revoke select(%1$s),insert(%1$s),update(%1$s),references(%1$s) on public.guildbattle_test_refills_v4 from service_role',cols);
 end if;
end $refill_acl$;

create or replace function public._raid_status_v4() returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
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
end $$;
create or replace function public._war_status_v4() returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
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
end $$;
create or replace function public._raid_start_v4(p_uids jsonb) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
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
end $$;
create or replace function public._war_start_v4(p_slot int, p_deck int) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
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
end $$;
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
end $$;
create or replace function public.raid_sweep_v4(p_request uuid) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare u uuid:=auth.uid(); m guild_members; r guild_raids_v4; a guild_raid_attempts_v4; best bigint; rw jsonb;
begin
 perform _guildbattle_guard_v4(); if u is null or p_request is null then raise exception 'login required'; end if;
 perform pg_advisory_xact_lock(hashtext('guildbattle:v4'));
 select result into rw from guildbattle_sweeps_v4 where user_id=u and request_id=p_request; if found then return rw; end if;
 select * into m from guild_members where user_id=u for update; if not found then raise exception 'not in guild'; end if;
 if _raid_now_v4()>=_raid_end_v4(_raid_week_v4()) then raise exception 'raid ended'; end if;
 if _guildbattle_used_v4(u,'raid')>=3 then raise exception 'no attempts'; end if;
 select max(fight.damage) into best from guild_raid_attempts_v4 fight join guildbattle_sessions_v4 sess on sess.kind='raid' and sess.attempt_id=fight.id and sess.verified and sess.status='settled'
 where fight.user_id=u and fight.guild_id=m.guild_id and fight.week=_raid_week_v4() and fight.day=_raid_day_v4() and fight.kind='fight' and not fight.voided;
 if coalesce(best,0)<=0 then raise exception 'fight first'; end if;
 r:=_raid_get_v4(m.guild_id,_raid_week_v4());
 insert into guild_raid_attempts_v4(user_id,guild_id,week,day,kind,stage,difficulty) values(u,m.guild_id,r.week,_raid_day_v4(),'sweep',r.stage,r.difficulty) returning * into a;
 rw:=jsonb_build_object('result',_raid_close_v4(a,best*90/100));
 insert into guildbattle_sweeps_v4 values(u,p_request,rw,m.guild_id,_guild_day()); return rw;
end $$;
$phase4_refill_install$;

 if action='stop' then update guildbattle_test_clock_v4 set at=null,expires_at=null; raise notice '실제 KST 시간으로 복귀. 테스트 자료와 잔액은 유지.'; return; end if;
 if action not in('start','refill','reset') then raise exception 'STOP: bad seed action'; end if;
 if user_a=user_b or not exists(select 1 from auth.users where id=user_a) or not exists(select 1 from auth.users where id=user_b) then raise exception 'STOP: 지정한 테스트 계정 2개로 먼저 로그인하고 Auth UUID를 입력하세요'; end if;
 users_:=array[user_a,user_b]||allies_a||allies_b;
 if (select count(distinct x) from unnest(users_) x)<>cardinality(users_) then raise exception 'STOP: duplicate fixture account'; end if;
 select * into clock_ from guildbattle_test_clock_v4 where singleton for update;
 if clock_.run>0 and exists(select 1 from guilds where id=any(clock_.guild_ids) and boss not in(user_a,user_b)) then raise exception 'STOP: existing fixture belongs to different users'; end if;
 -- Refill returns BEFORE all provisioning/tick/clock/reset code. Never resurrect a defender.
 if action='refill' then
  if clock_.at is null or clock_.expires_at is null or clock_.expires_at<=clock_timestamp() or clock_.run<1 or cardinality(clock_.guild_ids)<>2 then raise exception 'STOP: active start fixture required; refill never changes/extends the clock'; end if;
  if (select count(*) from guilds where id=any(clock_.guild_ids) and boss in(user_a,user_b) and name_key='sec4_fixture_'||boss::text)<>2 then raise exception 'STOP: fixture guild mismatch'; end if;
  foreach u in array users_ loop
   owner_:=case when u=any(allies_a) then user_a when u=any(allies_b) then user_b else u end;
   select g.id into gid from guild_members gm join guilds g on g.id=gm.guild_id where gm.user_id=u and g.id=any(clock_.guild_ids) and g.boss=owner_ and g.name_key='sec4_fixture_'||owner_::text;
   if gid is null or not exists(select 1 from story_progress sp,jsonb_array_elements(coalesce(sp.data->'owned','[]')) c where sp.user_id=u and c->>'uid' like 'sec4fixture:'||u||':%') then raise exception 'STOP: account is not a provisioned member of this fixture'; end if;
   select * into mt from war_matches_v4 where season=_war_season_v4() and day=_war_day_v4(_war_season_v4()) and (guild_a=gid or guild_b=gid);
   if mt.id is null or mt.ended_at is not null or mt.settled or _war_phase_v4(mt.season)<>'live' then raise exception 'STOP: current fixture match is not live; refill cannot restart it'; end if;
   -- Pending runs become immutable zero-award receipts. Late finish cannot apply damage; status/forfeit recovers this receipt.
   update guild_raid_attempts_v4 a set voided=true,finished_at=now(),damage=0 where a.user_id=u and finished_at is null;
   update war_attacks_v4 a set voided=true,finished_at=now(),win=false where a.user_id=u and finished_at is null;
   update guildbattle_sessions_v4 set status='settled',submission='{"forfeit":true}',result='{"expired":true,"win":false,"damage":0}' where user_id=u and status='issued';
   update war_ajits_v4 set locked_by=null,locked_until=null where locked_by=u;
   foreach k in array array['raid','war'] loop
    -- Add a BASELINE, not extra tickets. Repeating without a fight cannot stack >3 / >5.
    base_:=case when k='raid' then (select count(*) from guild_raid_attempts where user_id=u and day=_raid_day_v4())+(select count(*) from guild_raid_attempts_v4 where user_id=u and day=_raid_day_v4()) else (select count(*) from war_attacks_v4 where user_id=u and match_id=mt.id)+(select count(*) from war_attacks a join war_matches m on m.id=a.match_id where a.user_id=u and m.season=mt.season and m.day=mt.day) end;
    insert into guildbattle_test_refills_v4(user_id,guild_id,kind,day,match_id,run,clock_set_at,used_base) values(u,gid,k,_raid_day_v4(),case when k='war' then mt.id end,clock_.run,clock_.set_at,base_);
   end loop;
  end loop;
  raise notice '횟수만 충전: 토벌 3 / 조직전 5. HP·처치·점수·경기·시계 유지. 소진 시 refill 재실행 (reset 금지).';
  return;
 end if;
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
