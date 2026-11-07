-- PHASE 2 PREPARATION ONLY — NOT A REWARD VERIFIER / NOT A RELEASE.
-- DRAFT: offline protocol tests only. Do not ask the owner to apply this yet.
-- Requires phase 1. No existing RPC is replaced; no reward hold is released.
-- A transcript, seed, session token, or elapsed time is NOT proof of a clear.
begin;
select pg_advisory_xact_lock(20261107, 502);
do $preconditions$
begin
  if to_regclass('public.reward_security_policy') is null
     or to_regprocedure('public._pvp_snap(uuid,jsonb,text)') is null
     or to_regclass('public.story_phase_config') is null then
    raise exception 'STOP: install and inspect phase 1 first';
  end if;
end $preconditions$;

-- Shadow protocol: records evidence without changing progress/costs/wallets.
-- There is intentionally NO API (including a service-role RPC) to mark a client
-- submission verified. A future migration must install the actual replay engine.
create table if not exists public.battle_session_seeds_v2 (
  user_id uuid not null references auth.users(id) on delete cascade,
  mode text not null check (mode in ('tutorial','story','tower')),
  target text not null,
  seed integer not null check (seed between 1 and 2147483646),
  rule_version integer not null default 2 check (rule_version = 2),
  primary key(user_id,mode,target,rule_version)
);
create table if not exists public.battle_sessions_v2 (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  request_id uuid not null,
  mode text not null check (mode in ('tutorial','story','tower')),
  target text not null,
  party jsonb not null check (jsonb_typeof(party) = 'array'),
  seed integer not null check (seed between 1 and 2147483646),
  rule_version integer not null default 2 check (rule_version = 2),
  snapshot jsonb not null check (jsonb_typeof(snapshot) = 'object'),
  issued_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null default clock_timestamp() + interval '2 hours',
  status text not null default 'issued' check (status in ('issued','submitted','expired','aborted')),
  actions jsonb,
  submitted_at timestamptz,
  unique(user_id,request_id),
  check (expires_at > issued_at),
  check ((status = 'submitted') = (actions is not null and submitted_at is not null))
);
-- Submissions remain active: changing tabs/starting again cannot replace evidence.
create unique index if not exists battle_sessions_v2_one_active
  on public.battle_sessions_v2(user_id) where status in ('issued','submitted');
create index if not exists battle_sessions_v2_daily
  on public.battle_sessions_v2(user_id,issued_at);

-- Only a future replay + atomic settlement transaction may produce these rows.
-- No legacy JSON/stars/floors/counters are certified during installation.
create table if not exists public.battle_clear_receipts_v2 (
  user_id uuid not null references auth.users(id) on delete cascade,
  mode text not null check (mode in ('tutorial','story','tower')),
  target text not null,
  session_id uuid not null unique references public.battle_sessions_v2(id),
  settled_at timestamptz not null default clock_timestamp(),
  result jsonb not null check (jsonb_typeof(result) = 'object'),
  primary key(user_id,mode,target)
);
create table if not exists public.battle_tutorial_defs_v2 (
  stage integer primary key check (stage between 1 and 3),
  definition jsonb not null check (jsonb_typeof(definition) = 'object')
);
insert into public.battle_tutorial_defs_v2(stage,definition) values
  (1, '{"first":"me","me":["10019","10018","10299","10445","10404","10375","10325","10080","10074","10049"],"aiField":["10348","10339","10184"],"aiDeck":[],"aiHp":3000,"wipe":true,"levels":{"10325":7},"fullMp":["10019","10325"],"haste":["10325"],"bonus":{"3":30}}'::jsonb),
  (2, '{"first":"me","me":["10299","10137","10183","10045","10445","10404","10375","10060","10080","10074","10049"],"aiField":["10270","10462","10132","10202"],"aiDeck":[],"aiHp":3000,"meHpNow":2500,"wipe":true,"levels":{"10060":2},"fullMp":["10060"],"haste":["10060"],"bonus":{"1":30,"2":30,"3":10,"4":70}}'::jsonb),
  (3, '{"first":"me","me":["10036","10049","10118","10445","10404","10375","10080","10074","10311","10083"],"aiField":["10115","10103","10462","10256"],"aiDeck":[],"aiHp":3000,"wipe":true,"levels":{"10311":2},"fullMp":["10311"],"haste":["10311"],"mercs":["10292","10183","10325"],"bonus":{"1":0,"2":20,"3":80,"4":10,"5":50}}'::jsonb)
on conflict (stage) do nothing;

create or replace function public._battle_session_json_v2(s public.battle_sessions_v2) returns jsonb
language sql stable security definer set search_path = pg_catalog, public, pg_temp as $$
  select jsonb_build_object('ok',true,'session',s.id,'mode',s.mode,'target',s.target,
    'seed',s.seed,'rule_version',s.rule_version,'issued_at',s.issued_at,'expires_at',s.expires_at,
    'status',s.status,'snapshot',s.snapshot,'shadow',true,'reward_held',true,
    'verification','replay_not_installed')
$$;

-- Target syntax is canonical: tutorial '1', story '0:1', tower 'normal:1'.
-- Checking these gates is useful, but is deliberately not called verification.
create or replace function public._battle_session_gate_v2(uid uuid, m text, target_ text) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare ch integer; ph integer; fl integer; tw text; lv integer; need integer; cfg jsonb;
begin
  if m is null or target_ is null or length(target_) > 40 then raise exception 'invalid battle target'; end if;
  if m = 'tutorial' then
    if target_ !~ '^[1-3]$' then raise exception 'invalid tutorial stage'; end if;
    ph := target_::integer;
    if ph > 1 and not exists(select 1 from public.battle_clear_receipts_v2
      where user_id=uid and mode='tutorial' and target=(ph-1)::text) then
      raise exception 'previous tutorial not verified';
    end if;
    select definition into cfg from public.battle_tutorial_defs_v2 where stage=ph;
  elsif m = 'story' then
    if target_ !~ '^(0|[1-9][0-9]?):[1-9][0-9]?$' then raise exception 'invalid story target'; end if;
    ch := split_part(target_,':',1)::integer; ph := split_part(target_,':',2)::integer;
    select to_jsonb(c) into cfg from public.story_phase_config c where chapter=ch and phase=ph;
    if cfg is null then raise exception 'invalid phase'; end if;
    if ch <> 0 and coalesce((select data->>'starter' from public.story_progress where user_id=uid),'') = '' then
      raise exception 'choose starter first';
    end if;
    if exists(select 1 from public.story_phase_config c
      where (c.chapter < ch or (c.chapter = ch and c.phase < ph)) and (c.chapter <> 0 or ch = 0)
      and not exists(select 1 from public.battle_clear_receipts_v2 v
        where v.user_id=uid and v.mode='story' and v.target=c.chapter::text || ':' || c.phase::text)) then
      raise exception 'phase locked: previous clear not verified';
    end if;
    select level into lv from public.player_state where user_id=uid;
    need := public._player_unlock_level('chapter_' || ch);
    if need is not null and coalesce(lv,1) < need and not exists(
      select 1 from public.battle_clear_receipts_v2 where user_id=uid and mode='story'
        and target like ch::text || ':%') then raise exception 'level required: %',need; end if;
  elsif m = 'tower' then
    if target_ !~ '^(normal|wind|ice|fire|light|dark):[1-9][0-9]{0,2}$' then raise exception 'invalid tower target'; end if;
    tw := split_part(target_,':',1); fl := split_part(target_,':',2)::integer;
    if fl > public._tower_max_floor(tw) then raise exception 'invalid floor'; end if;
    if fl > 1 and not exists(select 1 from public.battle_clear_receipts_v2
      where user_id=uid and mode='tower' and target=tw || ':' || (fl-1)::text) then
      raise exception 'floor locked: previous clear not verified';
    end if;
    if not (public._tower_dow() = any(public._tower_days(tw))) then raise exception 'tower closed today'; end if;
    select level into lv from public.player_state where user_id=uid;
    if coalesce(lv,1) < public._tower_min_level(tw) then raise exception 'level too low'; end if;
    if coalesce((select day_floors from public.tower_progress
      where user_id=uid and tower=tw and day=public._tower_today()),0) >= public._tower_daily(tw) then
      raise exception 'daily limit';
    end if;
    cfg := jsonb_build_object('tower',tw,'floor',fl,'daily',public._tower_daily(tw));
  else raise exception 'invalid battle mode';
  end if;
  return cfg;
end $$;

create or replace function public.battle_session_start_v2(
  p_mode text, p_target text, p_party jsonb, p_request uuid) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare uid uuid := auth.uid(); s public.battle_sessions_v2; cfg jsonb; snap jsonb; seed_ integer;
  day_start timestamptz := ((public._gem_day())::timestamp at time zone 'Asia/Seoul');
begin
  if uid is null then raise exception 'login required'; end if;
  if p_request is null or jsonb_typeof(p_party) is distinct from 'array'
    or jsonb_array_length(p_party) > 10 or octet_length(p_party::text) > 2048
    or exists(select 1 from jsonb_array_elements(p_party) x where jsonb_typeof(x) <> 'string') then
    raise exception 'invalid party or request';
  end if;
  perform pg_advisory_xact_lock(hashtext('battle-v2:' || uid::text));
  select * into s from public.battle_sessions_v2 where user_id=uid and request_id=p_request;
  if found then
    if s.mode is distinct from p_mode or s.target is distinct from p_target or s.party <> p_party then
      raise exception 'request conflict';
    end if;
    -- Preserve submitted evidence even after its expiry; never silently certify it.
    if s.status='issued' and s.expires_at <= clock_timestamp() then
      update public.battle_sessions_v2 set status='expired' where id=s.id returning * into s;
    end if;
    return public._battle_session_json_v2(s);
  end if;
  update public.battle_sessions_v2 set status='expired'
    where user_id=uid and status='issued' and expires_at <= clock_timestamp();
  if exists(select 1 from public.battle_sessions_v2 where user_id=uid and status in ('issued','submitted')) then
    raise exception 'battle session already active';
  end if;
  if (select count(*) from public.battle_sessions_v2 where user_id=uid and issued_at >= day_start) >= 500 then
    raise exception 'session issuance limit';
  end if;
  cfg := public._battle_session_gate_v2(uid,p_mode,p_target);
  if p_mode='tutorial' then
    if p_party <> '[]'::jsonb then raise exception 'tutorial party is fixed'; end if;
    snap := jsonb_build_object('tutorial',cfg);
  else
    -- _pvp_snap reads owned instances, level, skills and equipped gear on the DB.
    -- No client stats, opponent, equipment, star count or win flag is accepted.
    snap := public._pvp_snap(uid,p_party,'open');
    snap := snap || jsonb_build_object('stage',cfg,'starter',
      (select data->'starter' from public.story_progress where user_id=uid),
      'leader',(select data->'leader' from public.story_progress where user_id=uid),
      'player_level',coalesce((select level from public.player_state where user_id=uid),1));
  end if;
  insert into public.battle_session_seeds_v2(user_id,mode,target,seed)
    values(uid,p_mode,p_target,1 + floor(random()*2147483646)::integer) on conflict do nothing;
  select seed into seed_ from public.battle_session_seeds_v2
    where user_id=uid and mode=p_mode and target=p_target and rule_version=2;
  -- Deliberately no stamina reservation here: SHADOW ONLY. Actual battle entry
  -- costs/reservations and fixed/guest party rules must be installed with replay.
  insert into public.battle_sessions_v2(user_id,request_id,mode,target,party,seed,snapshot)
    values(uid,p_request,p_mode,p_target,p_party,seed_,snap) returning * into s;
  return public._battle_session_json_v2(s);
end $$;

create or replace function public.battle_session_finish_v2(p_session uuid, p_actions jsonb) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare uid uuid := auth.uid(); s public.battle_sessions_v2; a jsonb; turn_ integer; prev_ integer := 0;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('battle-v2:' || uid::text));
  select * into s from public.battle_sessions_v2 where id=p_session and user_id=uid for update;
  if not found then raise exception 'battle session not found'; end if;
  if s.status='submitted' then
    if s.actions is distinct from p_actions then raise exception 'submission conflict'; end if;
    return public._battle_session_json_v2(s);
  end if;
  if s.status <> 'issued' then raise exception 'battle session closed'; end if;
  if s.expires_at <= clock_timestamp() then
    update public.battle_sessions_v2 set status='expired' where id=s.id returning * into s;
    return public._battle_session_json_v2(s);
  end if;
  if clock_timestamp() - s.issued_at < interval '3 seconds' then raise exception 'too fast'; end if;
  if jsonb_typeof(p_actions) is distinct from 'array' or jsonb_array_length(p_actions) not between 1 and 2000
    or octet_length(p_actions::text) > 262144 then raise exception 'invalid actions'; end if;
  for a in select * from jsonb_array_elements(p_actions) loop
    -- Transport bounds, NOT a combat validator. Legal actions/resource/RNG/target
    -- checking requires the versioned engine. Shape/timing must never pay rewards.
    if jsonb_typeof(a) is distinct from 'object' or a->>'k' is null or a->>'k' not in
      ('attack','skill','summon','recall','buff','equip','guard','swap','reserve','undo','sacrifice','merc','end')
      or jsonb_typeof(a->'turn') is distinct from 'number' or a->>'turn' !~ '^[1-9][0-9]?$' then
      raise exception 'invalid action envelope';
    end if;
    turn_ := (a->>'turn')::integer;
    if turn_ < prev_ or turn_ > 40 then raise exception 'invalid turn sequence'; end if;
    prev_ := turn_;
  end loop;
  update public.battle_sessions_v2 set actions=p_actions,submitted_at=clock_timestamp(),status='submitted'
    where id=s.id returning * into s;
  -- CRITICAL: no winner/stars/kills/EXP/counter/event/receipt is written here.
  -- Releasing rewards before replay would simply recreate the phase-1 exploit.
  return public._battle_session_json_v2(s);
end $$;

create or replace function public.battle_session_status_v2(p_session uuid) returns jsonb
language plpgsql stable security definer set search_path = pg_catalog, public, pg_temp as $$
declare s public.battle_sessions_v2;
begin
  if auth.uid() is null then raise exception 'login required'; end if;
  select * into s from public.battle_sessions_v2 where id=p_session and user_id=auth.uid();
  if not found then raise exception 'battle session not found'; end if;
  return public._battle_session_json_v2(s);
end $$;

create or replace function public.battle_session_abort_v2(p_session uuid) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare uid uuid := auth.uid(); s public.battle_sessions_v2;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('battle-v2:' || uid::text));
  select * into s from public.battle_sessions_v2 where id=p_session and user_id=uid for update;
  if not found then raise exception 'battle session not found'; end if;
  if s.status='submitted' then raise exception 'submitted evidence cannot be discarded'; end if;
  if s.status='issued' then
    update public.battle_sessions_v2 set status='aborted' where id=s.id returning * into s;
  end if;
  -- Shadow sessions charge/refund nothing. Seed is retained across abandon/expiry.
  return public._battle_session_json_v2(s);
end $$;

do $acl$
declare t text; c record; f record;
begin
  foreach t in array array['battle_sessions_v2','battle_session_seeds_v2','battle_clear_receipts_v2','battle_tutorial_defs_v2'] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('revoke all on public.%I from public,anon,authenticated',t);
    for c in select attname from pg_attribute where attrelid=to_regclass('public.' || t) and attnum>0 and not attisdropped loop
      execute format('revoke insert (%I),update (%I),references (%I),select (%I) on public.%I from public,anon,authenticated',
        c.attname,c.attname,c.attname,c.attname,t);
    end loop;
  end loop;
  -- Revoke every overload, not just the expected function signature.
  for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname in ('_battle_session_json_v2','_battle_session_gate_v2',
      'battle_session_start_v2','battle_session_finish_v2','battle_session_status_v2','battle_session_abort_v2') loop
    execute format('revoke all on function %s from public,anon,authenticated',f.sig);
  end loop;
end $acl$;
grant execute on function public.battle_session_start_v2(text,text,jsonb,uuid),
  public.battle_session_finish_v2(uuid,jsonb), public.battle_session_status_v2(uuid),
  public.battle_session_abort_v2(uuid) to authenticated;
notify pgrst, 'reload schema';
commit;
