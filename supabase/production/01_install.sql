-- GENERATED DELTA ONLY: existing production DB, NEVER staging_install/seed SQL.
-- Target: htarwisgkkphutxxnuak; baseline main f8ed722dbd558a90f091752222bfc7f53d7254e1; staging d0ba664b9d2b1ca65d7f86863292b0dfd0985d08.
-- Production system_identifier 7692130048193495360 explicitly confirmed by the owner and pinned. Run only in the agreed maintenance window after settlement/claims.
-- Do not guess/substitute the current DB ID automatically. See docs/PRODUCTION_ROLLOUT_20261108.md.
-- Atomic + ledger-protected rerun. Existing user rows are not deleted or reset.
begin;
do $production_guard$
declare expected_system_id text := '7692130048193495360'; actual_system_id text;
begin
 select system_identifier::text into actual_system_id from pg_catalog.pg_control_system();
 if expected_system_id !~ '^[1-9][0-9]{15,19}$' or expected_system_id='7703759698107299042' or actual_system_id is distinct from expected_system_id then
  raise exception 'STOP: production system_identifier must be explicitly pinned and match; staging/unknown DB refused';
 end if;
end $production_guard$;
set local lock_timeout='5s';
set local statement_timeout='120s';
select pg_advisory_xact_lock(hashtext('vr:production:20261108'));
create schema if not exists vr_rollout_private;
revoke all on schema vr_rollout_private from public,anon,authenticated,service_role;
create table if not exists vr_rollout_private.releases(release_id text primary key,bundle_hash text not null,db_id text not null,completed_at timestamptz not null default now());
alter table vr_rollout_private.releases enable row level security;
revoke all on vr_rollout_private.releases from public,anon,authenticated,service_role;
do $production_install$
declare h text; f record;
begin
 select bundle_hash into h from vr_rollout_private.releases where release_id='20261108';
 if found then
  if h is distinct from '80124fd4457b5130f0595fc717bf882587c67b11dc62576678b3d490ca783251' then raise exception 'STOP: release content changed after installation; use a reviewed follow-up migration'; end if;
  raise notice 'Production release 20261108 already installed: no data/function/policy changes'; return;
 end if;
 -- Do not rotate an unknown/future live engine silently.
 if to_regclass('public.pvp_policy_v3') is not null then execute 'select engine_hash from public.pvp_policy_v3 where singleton' into h; if h is distinct from '5a38b4b72651fcb8632fb1bfe14e1cd18a758d08249dbb18b0cfd223123c7a67' then raise exception 'STOP: unexpected existing pvp_policy_v3 engine; review upgrade before proceeding'; end if; end if;
 if to_regclass('public.guildbattle_policy_v4') is not null then execute 'select engine_hash from public.guildbattle_policy_v4 where singleton' into h; if h is distinct from 'c570973669776971316dfb650482e1401c5628c5ba73e57d23b879b9320c719a' then raise exception 'STOP: unexpected existing guildbattle_policy_v4 engine; review upgrade before proceeding'; end if; end if;
 if to_regclass('public.arcade_policy_v5') is not null then execute 'select engine_hash from public.arcade_policy_v5 where singleton' into h; if h is distinct from 'e792c491ffafe19d047aa6f58db1920e5767e4059e14816611dd38d473871161' then raise exception 'STOP: unexpected existing arcade_policy_v5 engine; review upgrade before proceeding'; end if; end if;
 -- All users must have left the game; backups and the war/raid boundary must be agreed first.
 perform set_config('check_function_bodies','off',true);
 execute $vr_production_payload$
-- ===== REVIEWED DELTA SOURCE: security_phase1_rewards.sql =====
select pg_advisory_xact_lock(20261107, 501);

do $preconditions$
declare obj text;
begin
  foreach obj in array array['gallery','gallery_claims','daily_progress','weekly_progress',
    'daily_attend','achievement_claims','ach_counters','story_progress','story_gacha',
    'story_gacha_log','story_card_pool','card_id_alias','player_wallet','gem_ledger',
    'arcade_tut_claims','pvp_reward_claims','pvp_tier_claims','guild_claims'] loop
    if to_regclass('public.' || obj) is null then raise exception 'STOP: missing table %; inspect preflight', obj; end if;
  end loop;
  foreach obj in array array['_daily_defs()','_weekly_defs()','_ach_defs()',
    '_daily_grant(uuid,jsonb,text,text)','_gem_add(uuid,integer,integer,text,text,jsonb)',
    '_gem_sync(uuid)','_story_ticket_sync(uuid)','_gallery_sync_owned(uuid,jsonb)',
    'gallery_register(text[],text)','daily_track(text,integer)','weekly_track(text,integer)',
    'ach_track(text,integer)','tower_complete(text,integer,jsonb)',
    'tower_sweep_complete(text,integer,jsonb)','pvp_report(bigint,integer,integer)'] loop
    if to_regprocedure('public.' || obj) is null then raise exception 'STOP: missing function %; inspect preflight', obj; end if;
  end loop;
end $preconditions$;

-- No client-writable flags or generic "verify this result" RPC. Later phases must
-- supply a verifier, not flip an unverified client result into a trusted event.
create table if not exists public.reward_security_policy (
  key text primary key, enabled boolean not null default false,
  installed_at timestamptz not null default now(),
  check (key in ('battle_rewards_v1')), check (not enabled)
);

insert into public.reward_security_policy(key) values ('battle_rewards_v1') on conflict do nothing;

alter table public.reward_security_policy enable row level security;

revoke all on public.reward_security_policy from public, anon, authenticated;

create table if not exists public.verified_game_events (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  source_kind text not null check (source_kind = 'gacha'),
  source_id text not null,
  event_kind text not null check (event_kind = 'card_acquired'),
  card_id text not null references public.story_card_pool(id),
  rule_version integer not null default 1 check (rule_version = 1),
  occurred_at timestamptz not null default now(),
  unique(user_id, source_kind, source_id, event_kind)
);

create index if not exists verified_game_events_user_card on public.verified_game_events(user_id, card_id);

alter table public.verified_game_events enable row level security;

revoke all on public.verified_game_events from public, anon, authenticated;

create table if not exists public.reward_claims (
  user_id uuid not null references auth.users(id) on delete cascade,
  reward_kind text not null,
  source_or_period text not null,
  reward jsonb not null check (jsonb_typeof(reward) = 'object'),
  result jsonb not null default '{}'::jsonb,
  rule_version integer not null default 1,
  claimed_at timestamptz not null default now(),
  primary key(user_id, reward_kind, source_or_period)
);

alter table public.reward_claims enable row level security;

revoke all on public.reward_claims from public, anon, authenticated;

-- Release catalog from data/cards.csv. Hidden pool entries cannot inflate collection %.
create table if not exists public.reward_card_catalog (
  card_id text primary key references public.story_card_pool(id)
);

alter table public.reward_card_catalog enable row level security;

revoke all on public.reward_card_catalog from public,anon,authenticated;

insert into public.reward_card_catalog(card_id) values
  ('10118'),
  ('10019'),
  ('10018'),
  ('10299'),
  ('10074'),
  ('10080'),
  ('10445'),
  ('10375'),
  ('10051'),
  ('10404'),
  ('10049'),
  ('10048'),
  ('10189'),
  ('10060'),
  ('10071'),
  ('10086'),
  ('10169'),
  ('10137'),
  ('10138'),
  ('10020'),
  ('10463'),
  ('10228'),
  ('10453'),
  ('10293'),
  ('10010'),
  ('10380'),
  ('10114'),
  ('10401'),
  ('10315'),
  ('10026'),
  ('10191'),
  ('10469'),
  ('10001'),
  ('10183'),
  ('10064'),
  ('10444'),
  ('10279'),
  ('10225'),
  ('10431'),
  ('10332'),
  ('10201'),
  ('10346'),
  ('10275'),
  ('10124'),
  ('10134'),
  ('10037'),
  ('10031'),
  ('10180'),
  ('10390'),
  ('10027'),
  ('10033'),
  ('10353'),
  ('10244'),
  ('10245'),
  ('10292'),
  ('10076'),
  ('10045'),
  ('10409'),
  ('10407'),
  ('10036'),
  ('10075'),
  ('10173'),
  ('10406'),
  ('10328'),
  ('10329'),
  ('10098'),
  ('10187'),
  ('10319'),
  ('10081'),
  ('10252'),
  ('10298'),
  ('10125'),
  ('10025'),
  ('10035'),
  ('10112'),
  ('10270'),
  ('10069'),
  ('10088'),
  ('10004'),
  ('10420'),
  ('10408'),
  ('10205'),
  ('10139'),
  ('10347'),
  ('10023'),
  ('10448'),
  ('10067'),
  ('10005'),
  ('10276'),
  ('10259'),
  ('10386'),
  ('10105'),
  ('10077'),
  ('10212'),
  ('10065'),
  ('10008'),
  ('10425'),
  ('10107'),
  ('10032'),
  ('10142'),
  ('10089'),
  ('10094'),
  ('10350'),
  ('10366'),
  ('10016'),
  ('10385'),
  ('10474'),
  ('10287'),
  ('10182'),
  ('10136'),
  ('10209'),
  ('10170'),
  ('10128'),
  ('10433'),
  ('10374'),
  ('10218'),
  ('10441'),
  ('10349'),
  ('10314'),
  ('10337'),
  ('10038'),
  ('10365'),
  ('10278'),
  ('10251'),
  ('10109'),
  ('10017'),
  ('10015'),
  ('10028'),
  ('10181'),
  ('10333'),
  ('10054'),
  ('10046'),
  ('10066'),
  ('10195'),
  ('10283'),
  ('10284'),
  ('10321'),
  ('10320'),
  ('10371'),
  ('10345'),
  ('10021'),
  ('10424'),
  ('10398'),
  ('10318'),
  ('10458'),
  ('10464'),
  ('10233'),
  ('10034'),
  ('10171'),
  ('10119'),
  ('10226'),
  ('10307'),
  ('10402'),
  ('10009'),
  ('10055'),
  ('10013'),
  ('10313'),
  ('10106'),
  ('10316'),
  ('10416'),
  ('10057'),
  ('10220'),
  ('10340'),
  ('10309'),
  ('10070'),
  ('10113'),
  ('10364'),
  ('10410'),
  ('10419'),
  ('10053'),
  ('10176'),
  ('10200'),
  ('10234'),
  ('10123'),
  ('10304'),
  ('10434'),
  ('10430'),
  ('10379'),
  ('10325'),
  ('10260'),
  ('10300'),
  ('10462'),
  ('10072'),
  ('10256'),
  ('10115'),
  ('10348'),
  ('10339'),
  ('10394'),
  ('10047'),
  ('10188'),
  ('10132'),
  ('10087'),
  ('10202'),
  ('10184'),
  ('10103'),
  ('10265'),
  ('10266'),
  ('10465'),
  ('10466'),
  ('10002'),
  ('10289'),
  ('10083'),
  ('10079'),
  ('10338'),
  ('10336'),
  ('10418'),
  ('10323'),
  ('10403'),
  ('10185'),
  ('10308'),
  ('10413'),
  ('10415'),
  ('10414'),
  ('10186'),
  ('10295'),
  ('10297'),
  ('10317'),
  ('10108'),
  ('10417'),
  ('10172'),
  ('10262'),
  ('10261'),
  ('10290'),
  ('10384'),
  ('10383'),
  ('10110'),
  ('10442'),
  ('10129'),
  ('10014'),
  ('10235'),
  ('10111'),
  ('10357'),
  ('10360'),
  ('10306'),
  ('10285'),
  ('10343'),
  ('10271'),
  ('10003'),
  ('10095'),
  ('10096'),
  ('10342'),
  ('10327'),
  ('10286'),
  ('10273'),
  ('10253'),
  ('10061'),
  ('10460'),
  ('10459'),
  ('10461'),
  ('10296'),
  ('10246'),
  ('10204'),
  ('10447'),
  ('10429'),
  ('10211'),
  ('10193'),
  ('10120'),
  ('10101'),
  ('10099'),
  ('10241'),
  ('10044'),
  ('10043'),
  ('10376'),
  ('10377'),
  ('10322'),
  ('10239'),
  ('10039'),
  ('10310'),
  ('10247'),
  ('10248'),
  ('10221'),
  ('10011'),
  ('10140'),
  ('10388'),
  ('10121'),
  ('10236'),
  ('10102'),
  ('10092'),
  ('10194'),
  ('10361'),
  ('10354'),
  ('10254'),
  ('10222'),
  ('10470'),
  ('10059'),
  ('10428'),
  ('10471'),
  ('10450'),
  ('10432'),
  ('10359'),
  ('10362'),
  ('10454'),
  ('10363'),
  ('10436'),
  ('10412'),
  ('10040'),
  ('10042'),
  ('10237'),
  ('10207'),
  ('10208'),
  ('10303'),
  ('10468'),
  ('10467'),
  ('10294'),
  ('10258'),
  ('10056'),
  ('10041'),
  ('10255'),
  ('10141'),
  ('10133'),
  ('10091'),
  ('10090'),
  ('10344'),
  ('10330'),
  ('10263'),
  ('10249'),
  ('10063'),
  ('10052'),
  ('10190'),
  ('10174'),
  ('10122'),
  ('10029'),
  ('10232'),
  ('10104'),
  ('10378'),
  ('10126'),
  ('10062'),
  ('10203'),
  ('10097'),
  ('10280'),
  ('10352'),
  ('10277'),
  ('10100'),
  ('10451'),
  ('10389'),
  ('10264'),
  ('10438'),
  ('10177'),
  ('10178'),
  ('10372'),
  ('10373'),
  ('10130'),
  ('10131'),
  ('10341'),
  ('10272'),
  ('10117'),
  ('10078'),
  ('10084'),
  ('10085'),
  ('10217'),
  ('10216'),
  ('10324'),
  ('10006'),
  ('10068'),
  ('10400'),
  ('10331'),
  ('10250'),
  ('10022'),
  ('10437'),
  ('10426'),
  ('10381'),
  ('10179'),
  ('10215'),
  ('10214'),
  ('10223'),
  ('10269'),
  ('10268'),
  ('10473'),
  ('10135'),
  ('10206'),
  ('10240'),
  ('10238'),
  ('10230'),
  ('10227'),
  ('10387'),
  ('10281'),
  ('10472'),
  ('10455'),
  ('10423'),
  ('10456'),
  ('10457'),
  ('10224'),
  ('10382'),
  ('10393'),
  ('10030'),
  ('10391'),
  ('10392'),
  ('10311'),
  ('10397'),
  ('10242'),
  ('10356'),
  ('10274'),
  ('10192'),
  ('10093'),
  ('10312'),
  ('10243'),
  ('10231'),
  ('10399'),
  ('10050'),
  ('10073'),
  ('10229'),
  ('10012'),
  ('10219'),
  ('10305'),
  ('10443'),
  ('10024'),
  ('10446'),
  ('10427'),
  ('10411'),
  ('10058'),
  ('10395'),
  ('10213'),
  ('10175'),
  ('10007'),
  ('10257'),
  ('10291'),
  ('10326'),
  ('10288'),
  ('10282'),
  ('10405'),
  ('10452'),
  ('10370'),
  ('10368'),
  ('10369'),
  ('10358'),
  ('10351'),
  ('10449'),
  ('10422'),
  ('10421'),
  ('10396'),
  ('10435'),
  ('10127'),
  ('10439'),
  ('10355'),
  ('10367'),
  ('10440'),
  ('10267'),
  ('10509')
on conflict do nothing;

create or replace function public._gallery_total() returns int
language sql stable security definer set search_path = pg_catalog, public, pg_temp as $$
  select count(*)::int from public.reward_card_catalog
$$;

-- Actual INSERT into the server-only draw log is the evidence, NOT owned JSON,
-- gallery, matches, a browser event, or an old counter. No legacy backfill.
create or replace function public._reward_gacha_event() returns trigger
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare cid text; eid bigint;
begin
  select p.id into cid from public.story_card_pool p
  where p.id = coalesce((select a.new_id from public.card_id_alias a where a.old_id = new.card_id), new.card_id);
  if cid is null then raise exception 'invalid acquired card'; end if;
  insert into public.verified_game_events(user_id, source_kind, source_id, event_kind, card_id)
  values (new.user_id, 'gacha', new.id::text, 'card_acquired', cid)
  on conflict do nothing returning id into eid;
  if eid is not null then
    insert into public.gallery(user_id, card_id, count, mvp_count, first_at, last_at)
    values (new.user_id, cid, 0, 0, now(), now() - interval '1 minute')
    on conflict (user_id, card_id) do nothing;
  end if;
  return new;
end $$;

revoke all on function public._reward_gacha_event() from public, anon, authenticated;

drop trigger if exists reward_gacha_event on public.story_gacha_log;

create trigger reward_gacha_event after insert on public.story_gacha_log
for each row execute function public._reward_gacha_event();

-- The old JSON trigger is intentionally removed. Do not certify existing owned
-- cards or gallery rows as acquisitions (including a sold/forged legacy card).
drop trigger if exists story_progress_gallery on public.story_progress;

create or replace function public._gallery_sync_owned(p_uid uuid, p_data jsonb)
returns int language sql security definer set search_path = pg_catalog, public, pg_temp as $$ select 0 $$;

create or replace function public._gallery_have(p_uid uuid) returns int
language sql stable security definer set search_path = pg_catalog, public, pg_temp as $$
  select count(distinct e.card_id)::int from public.verified_game_events e
  join public.reward_card_catalog c on c.card_id=e.card_id
  where user_id = p_uid and event_kind = 'card_acquired'
$$;

-- All currencies in a daily/gallery/achievement grant share one receipt. The
-- caller already validates its server catalog and eligibility; this is private.
-- Row/period locks in public claim RPCs precede the gem lock, then wallet/tickets.
create or replace function public._daily_grant(p_uid uuid, p_rw jsonb, p_reason text, p_ref text) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare res jsonb := '{}'::jsonb; prior public.reward_claims; t int; inserted boolean; k text; v jsonb;
begin
  if p_uid is null or p_ref is null or length(p_ref) not between 1 and 200
    or p_reason is null or p_reason not in ('attend','daily','weekly','gallery','ach')
    or jsonb_typeof(p_rw) is distinct from 'object' then raise exception 'invalid reward'; end if;
  for k, v in select * from jsonb_each(p_rw) loop
    if k not in ('gold','gem','tickets') or jsonb_typeof(v) <> 'number'
      or v::text !~ '^[0-9]+$' or v::numeric > 2147483647 then raise exception 'invalid reward'; end if;
  end loop;
  perform pg_advisory_xact_lock(hashtext('gem:' || p_uid::text));
  select * into prior from public.reward_claims where user_id=p_uid and reward_kind=p_reason and source_or_period=p_ref;
  if found then
    if prior.reward <> p_rw then raise exception 'reward conflict'; end if;
    return prior.result;
  end if;
  -- Old gem receipts are NOT permission to replay ticket/gold parts of a grant.
  if exists (select 1 from public.gem_ledger where user_id=p_uid and ref=p_ref) then raise exception 'already claimed'; end if;
  insert into public.reward_claims(user_id, reward_kind, source_or_period, reward)
  values (p_uid,p_reason,p_ref,p_rw) on conflict do nothing returning true into inserted;
  if not coalesce(inserted,false) then raise exception 'already claimed'; end if;
  if coalesce((p_rw->>'gold')::int,0)>0 then
    res := res || jsonb_build_object('wallet',public._wallet_add(p_uid,jsonb_build_object('gold',(p_rw->>'gold')::int),p_reason));
  end if;
  if coalesce((p_rw->>'gem')::int,0)>0 then
    perform public._gem_add(p_uid,(p_rw->>'gem')::int,0,p_reason,p_ref,jsonb_build_object('rule_version',1));
  end if;
  if coalesce((p_rw->>'tickets')::int,0)>0 then
    insert into public.story_gacha(user_id,last_draw) values (p_uid,public._gem_day()-1) on conflict do nothing;
    update public.story_gacha set tickets=tickets+(p_rw->>'tickets')::int, updated_at=now() where user_id=p_uid returning tickets into t;
    res := res || jsonb_build_object('tickets',t);
  end if;
  update public.reward_claims set result=res where user_id=p_uid and reward_kind=p_reason and source_or_period=p_ref;
  return res;
end $$;

-- Legacy mission and battle counters are retained but never used as evidence.
-- No battle event supplier exists in phase 1, so all daily/weekly combat claims
-- are held. Attendance is still server date + auth + account/day lock.
create or replace function public._reward_battle_enabled() returns boolean
language sql stable security definer set search_path = pg_catalog, public, pg_temp as $$
  select coalesce((select enabled from public.reward_security_policy where key='battle_rewards_v1'),false)
$$;

create or replace function public.daily_track(p_kind text, p_n int default 1) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'login required'; end if;
  raise exception 'reward verification pending' using errcode='P0001';
end $$;

create or replace function public.weekly_track(p_kind text, p_n int default 1) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'login required'; end if;
  raise exception 'reward verification pending' using errcode='P0001';
end $$;

create or replace function public.ach_track(p_kind text, p_n int default 1) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'login required'; end if;
  raise exception 'reward verification pending' using errcode='P0001';
end $$;

create or replace function public.daily_claim(p_key text) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'login required'; end if;
  raise exception 'reward verification pending' using errcode='P0001';
end $$;

create or replace function public.weekly_claim(p_key text) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'login required'; end if;
  raise exception 'reward verification pending' using errcode='P0001';
end $$;

create or replace function public.arcade_tut_claim(p_stage int) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'login required'; end if;
  raise exception 'reward verification pending' using errcode='P0001';
end $$;

create or replace function public.story_star_claim(p_chapter int, p_key text) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'login required'; end if;
  raise exception 'reward verification pending' using errcode='P0001';
end $$;

create or replace function public.pvp_claim_tier(p_league text, p_mode text) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'login required'; end if;
  raise exception 'reward verification pending' using errcode='P0001';
end $$;

create or replace function public.pvp_claim_reward(p_league text, p_mode text, p_season date) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'login required'; end if;
  raise exception 'reward verification pending' using errcode='P0001';
end $$;

create or replace function public.raid_claim() returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'login required'; end if;
  raise exception 'reward verification pending' using errcode='P0001';
end $$;

create or replace function public.war_claim() returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'login required'; end if;
  raise exception 'reward verification pending' using errcode='P0001';
end $$;

create or replace function public.gallery_register(p_cards text[], p_mvp text default null)
returns table(card_id text, count int, mvp_count int, is_new boolean)
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'login required'; end if;
  raise exception 'reward verification pending' using errcode='P0001';
end $$;

create or replace function public._daily_json(p_uid uuid) returns jsonb language plpgsql stable security definer set search_path = pg_catalog, public, pg_temp as $$
declare dp daily_progress; a daily_attend; today date := _gem_day(); done int;
begin
  select * into dp from daily_progress where user_id = p_uid and day = today;
  select * into a from daily_attend where user_id = p_uid;
  select count(*) into done from jsonb_array_elements(_daily_defs()) m where 0 >= (m->>'goal')::int;
  return jsonb_build_object('ok', true, 'reward_held', true, 'day', today,
    'next_reset', ((today + 1)::timestamp at time zone 'Asia/Seoul'),
    'missions', (select jsonb_agg(m || jsonb_build_object('prog', least((m->>'goal')::int, 0),
                   'claimed', coalesce(dp.claimed, '[]'::jsonb) ? (m->>'key'))) from jsonb_array_elements(_daily_defs()) m),
    'all', jsonb_build_object('reward', _daily_all_reward(), 'done', done, 'goal', jsonb_array_length(_daily_defs()), 'claimed', coalesce(dp.claimed, '[]'::jsonb) ? 'all'),
    'attend', jsonb_build_object('rewards', _attend_defs(), 'step', case when coalesce(a.step, 0) >= 7 and a.last_day < today then 0 else coalesce(a.step, 0) end,
                   'today', a.last_day = today, 'total', coalesce(a.total, 0)));
end $$;

create or replace function public._weekly_json(p_uid uuid) returns jsonb language plpgsql stable security definer set search_path = pg_catalog, public, pg_temp as $$
declare wp weekly_progress; v_week date := _weekly_week(); done int; next_reset timestamptz;
begin
  select * into wp from weekly_progress where user_id = p_uid and week = v_week;
  select count(*) into done from jsonb_array_elements(_weekly_defs()) m where 0 >= (m->>'goal')::int;
  next_reset := ((v_week + 7)::timestamp at time zone 'Asia/Seoul');
  return jsonb_build_object('ok', true, 'reward_held', true, 'week', v_week, 'next_reset', next_reset,
    'missions', (select jsonb_agg(m || jsonb_build_object('prog', least((m->>'goal')::int, 0),
                   'claimed', coalesce(wp.claimed, '[]'::jsonb) ? (m->>'key'))) from jsonb_array_elements(_weekly_defs()) m),
    'all', jsonb_build_object('reward', _weekly_all_reward(), 'done', done, 'goal', jsonb_array_length(_weekly_defs()),
                   'claimed', coalesce(wp.claimed, '[]'::jsonb) ? 'all'));
end $$;

-- Only independently server-observed actions can unlock an achievement today.
create or replace function public._ach_prog(p_uid uuid,p_id text) returns int
language plpgsql stable security definer set search_path = pg_catalog, public, pg_temp as $$
declare v int := 0;
begin
  case p_id
  when 'camp_lv' then select camp_lv into v from public.camp_state where user_id=p_uid;
  when 'camp_slots' then select count(*)::int into v from public.camp_slots where user_id=p_uid;
  when 'gallery_n' then return public._gallery_have(p_uid);
  when 'gacha_n' then select count(*)::int into v from public.verified_game_events where user_id=p_uid and event_kind='card_acquired';
  when 'gear_p5' then select count(*)::int into v from public.player_gear where user_id=p_uid and plus>=5;
  when 'attend_n' then select total into v from public.daily_attend where user_id=p_uid;
  when 'friends_n' then select count(*)::int into v from public.friendships where user_a=p_uid or user_b=p_uid;
  when 'guild_join' then select exists(select 1 from public.guild_members where user_id=p_uid)::int into v;
  when 'gifts_sent' then select count(*)::int into v from public.friend_gifts where from_user=p_uid;
  else return 0; -- battle/level/star/MVP counters need phase 2-5 verifiers
  end case;
  return coalesce(v,0);
end $$;

create or replace function public._ach_score(p_uid uuid) returns int
language plpgsql stable security definer set search_path = pg_catalog, public, pg_temp as $$
declare a jsonb; t jsonb; n int; i int; g int; s int := 0; k text;
begin
  for a in select x from jsonb_array_elements(_ach_defs()) x loop
    n := jsonb_array_length(a->'tiers');
    for i in 0 .. n - 1 loop
      t := a->'tiers'->i; g := (t->>'goal')::int; k := _ach_key(a->>'id', g);
      if exists (select 1 from public.reward_claims c where c.user_id=p_uid and c.reward_kind='ach' and c.source_or_period='ach:' || k) then
        s := s + case when i = n - 1 then 20 else 10 end;
      end if;
    end loop;
  end loop;
  return s;
end $$;

create or replace function public._ach_json(p_uid uuid) returns jsonb
language plpgsql stable security definer set search_path = pg_catalog, public, pg_temp as $$
declare items jsonb := '[]'::jsonb; a jsonb; t jsonb; i int; n int; prog int; g int; k text; claimed boolean; ready boolean;
  score int; sc jsonb; ready_n int := 0; cat text; cats jsonb := '[]'::jsonb; c jsonb; list jsonb;
begin
  for a in select x from jsonb_array_elements(_ach_defs()) x loop
    prog := _ach_prog(p_uid, a->>'id');
    n := jsonb_array_length(a->'tiers');
    for i in 0 .. n - 1 loop
      t := a->'tiers'->i; g := (t->>'goal')::int; k := _ach_key(a->>'id', g);
      claimed := exists (select 1 from achievement_claims c where c.user_id = p_uid and c.key = k);
      ready := (not claimed) and prog >= g;
      if ready then ready_n := ready_n + 1; end if;
      items := items || jsonb_build_array(jsonb_build_object(
        'id', a->>'id', 'cat', a->>'cat', 'name', a->>'name', 'unit', coalesce(a->>'unit',''),
        'goal', g, 'prog', least(prog, g), 'raw', prog, 'key', k,
        'reward', t->'reward', 'claimed', claimed, 'ready', ready,
        'pts', case when i = n - 1 then 20 else 10 end,
        'tier', i + 1, 'tiers', n, 'held', a->>'id' not in ('camp_lv','camp_slots','gallery_n','gacha_n','gear_p5','attend_n','friends_n','guild_join','gifts_sent'), 'title', _ach_title_name(t->>'title')));
    end loop;
  end loop;
  score := _ach_score(p_uid);
  for sc in select x from jsonb_array_elements(_ach_score_defs()) x loop
    g := (sc->>'goal')::int; k := _ach_score_key(g);
    claimed := exists (select 1 from achievement_claims c where c.user_id = p_uid and c.key = k);
    ready := (not claimed) and score >= g;
    if ready then ready_n := ready_n + 1; end if;
    items := items || jsonb_build_array(jsonb_build_object(
      'id', 'score', 'cat', 'score', 'name', '업적 점수', 'unit', '점',
      'goal', g, 'prog', least(score, g), 'raw', score, 'key', k,
      'reward', sc->'reward', 'claimed', claimed, 'ready', ready,
      'pts', 0, 'tier', 0, 'tiers', 0, 'title', _ach_title_name(sc->>'title')));
  end loop;
  for c in select x from jsonb_array_elements(_ach_cats()) x loop
    cat := c->>'id';
    select coalesce(jsonb_agg(x order by (x->>'id'), (x->>'goal')::int), '[]'::jsonb) into list
      from jsonb_array_elements(items) x where x->>'cat' = cat;
    cats := cats || jsonb_build_array(c || jsonb_build_object('items', list));
  end loop;
  select coalesce(jsonb_agg(x order by (x->>'goal')::int), '[]'::jsonb) into list
    from jsonb_array_elements(items) x where x->>'cat' = 'score';
  return jsonb_build_object('ok', true, 'score', score, 'ready', ready_n,
    'cats', cats, 'score_items', list);
end $$;

create or replace function public.attend_claim() returns jsonb language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare uid uuid := auth.uid(); today date := _gem_day(); a daily_attend; st int; rw jsonb; res jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('daily:' || uid::text));
  perform pg_advisory_xact_lock(hashtext('gem:' || uid::text));
  insert into daily_attend (user_id) values (uid) on conflict do nothing;
  select * into a from daily_attend where user_id = uid for update;
  if a.last_day = today then raise exception 'already claimed'; end if;
  st := case when a.step >= 7 then 1 else a.step + 1 end;
  rw := _attend_defs()->(st - 1);
  update daily_attend set last_day = today, step = st, total = total + 1 where user_id = uid;
  res := _daily_grant(uid, rw, 'attend', 'attend:' || today);
  return _daily_json(uid) || res || jsonb_build_object('got', rw, 'got_day', st);
end $$;

create or replace function public.arcade_tut_status() returns jsonb
language plpgsql stable security definer set search_path = pg_catalog, public, pg_temp as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  return jsonb_build_object('ok', true, 'reward_held', true,
    'claimed', coalesce((select jsonb_agg(stage order by stage) from arcade_tut_claims where user_id = uid), '[]'::jsonb),
    'rewards', jsonb_build_object('1', _arcade_tut_rw(1), '2', _arcade_tut_rw(2), '3', _arcade_tut_rw(3)));
end $$;

create or replace function public._story_ticket_sync(uid uuid) returns jsonb
language plpgsql set search_path = pg_catalog, public, pg_temp as $$
declare t int;
begin
  if uid is null then raise exception 'login required'; end if;
  insert into public.story_gacha(user_id,last_draw) values (uid,public._gem_day()-1) on conflict do nothing;
  select tickets into t from public.story_gacha where user_id=uid for update;
  return jsonb_build_object('tickets',t,'added',0,'chapters','[]'::jsonb,'reward_held',true);
end $$;

create or replace function public._gem_sync(p_uid uuid) returns jsonb language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare d jsonb; ch int; r jsonb; out jsonb := '[]'::jsonb; lg gem_login; today date := _gem_day();
begin
  -- Chapter gems are held until phase 2; daily login remains server dated.
  insert into gem_login (user_id, last_day, streak) values (p_uid, today - 1, 0) on conflict (user_id) do nothing;
  select * into lg from gem_login where user_id = p_uid for update;
  if lg.last_day < today then
    lg.streak := case when lg.last_day = today - 1 then lg.streak + 1 else 1 end;
    update gem_login set last_day = today, streak = lg.streak where user_id = p_uid;
    if lg.streak % 7 = 0 then
      r := _gem_add(p_uid, _gem_login_reward(), 0, 'login_7', 'login:' || today, jsonb_build_object('streak', lg.streak));
      if r is not null then out := out || jsonb_build_array(jsonb_build_object('reason', 'login_7', 'streak', lg.streak, 'gem', _gem_login_reward())); end if;
    end if;
  end if;
  return out;
end $$;

create or replace function public._pvp_grant(p_uid uuid, p_rw jsonb, p_reason text, p_league text, p_mode text, p_season date) returns void
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
begin raise exception 'reward verification pending'; end $$;

create or replace function public._tower_pay(uid uuid, p text, f int) returns jsonb
language plpgsql set search_path = pg_catalog, public, pg_temp as $$
begin raise exception 'reward verification pending'; end $$;

create or replace function public._guild_feed(p_uid uuid, p_src text, p_n int) returns int
language sql security definer set search_path = pg_catalog, public, pg_temp as $$ select 0 $$;

create or replace function public.pvp_report(p_id bigint, p_wins int, p_losses int) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare uid uuid := auth.uid(); a pvp_attempts; n int; need int; v_win boolean; r int; sk int := 0; srw jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  select * into a from pvp_attempts where id = p_id and user_id = uid for update;
  if a.id is null then raise exception 'not found'; end if;
  if a.reported_at is not null then raise exception 'already reported'; end if;
  if now() - a.created_at > interval '1 hour' then raise exception 'expired'; end if;
  n := _pvp_ok(a.league, a.mode); need := case when n = 3 then 2 else 1 end;
  if p_wins is null or p_losses is null or p_wins < 0 or p_losses < 0 or p_wins > need or p_losses > need
     or not (p_wins = need or p_losses = need) or (p_wins = need and p_losses = need) then raise exception 'bad result'; end if;
  v_win := p_wins = need;
  update pvp_attempts set reported_at = now(), wins = p_wins, losses = p_losses, win = v_win where id = p_id;
  if v_win then
    update pvp_ratings set rating = rating + a.dl + a.dw, wins = wins + 1, losses = losses - 1, updated_at = now()
      where user_id = uid and league = a.league and mode = a.mode and season = a.season;
    if a.opp_user is not null then
      update pvp_ratings set rating = rating - a.dl / 2 - a.dw / 2, def_wins = def_wins - 1, def_losses = def_losses + 1, updated_at = now()
        where user_id = a.opp_user and league = a.league and mode = a.mode and season = a.season;
    end if;
    sk := _pvp_streak(uid, a.league, a.mode, a.season, p_id);
    select reward into srw from pvp_streak_table where pvp_streak_table.n = sk;
    -- No verified battle supplier yet. Do not consume a reward or claim it was paid.
    srw := null;
    update pvp_attempts set streak = sk, streak_reward = srw where id = p_id;
    -- 조직 세력 (guild.sql): 승리당 +10 (하루 상한은 _guild_feed 가 처리)
    if to_regprocedure('public._guild_feed(uuid,text,integer)') is not null then perform _guild_feed(uid, 'pvp', 10); end if;
  end if;
  select rating into r from pvp_ratings where user_id = uid and league = a.league and mode = a.mode and season = a.season;
  return jsonb_build_object('ok', true, 'win', v_win, 'rating', r, 'delta', case when v_win then a.dw else -a.dl end,
    'tier', _pvp_tier(r), 'streak', sk, 'streak_reward', srw, 'reward_held', true);
end $$;

create or replace function public.tower_complete(p_tower text, p_floor int, p_stats jsonb default '{}'::jsonb) returns jsonb language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare uid uuid := auth.uid(); r tower_progress; b jsonb; first boolean; paid boolean := false; pay jsonb := '{}'::jsonb; turns int; k text;
begin
  r := _tower_row(uid, p_tower);
  b := r.battle;
  if b is null or b ? 'sweep' or (b->>'floor')::int <> p_floor then raise exception 'battle not started'; end if;
  if extract(epoch from clock_timestamp()) - (b->>'at')::bigint < _quest_min_secs() then raise exception 'too fast'; end if;
  turns := coalesce((p_stats->>'turns')::int, 1);
  if turns < 1 or turns > 40 then raise exception 'invalid stats'; end if;
  if r.day_floors >= _tower_daily(p_tower) then raise exception 'daily limit'; end if;   -- 자정을 넘긴 전투도 새 날 카운트로
  first := p_floor = r.best_floor + 1;
  if public._reward_battle_enabled() and first and p_floor > r.paid_floor then pay := _tower_pay(uid, p_tower, p_floor); paid := true; end if;
  update tower_progress set battle = null, clears = clears + 1, day_floors = day_floors + 1,
    best_floor = case when first then p_floor else best_floor end,
    paid_floor = case when paid then p_floor else paid_floor end,
    rewards = case when paid then (select jsonb_object_agg(x.k, coalesce((rewards->>x.k)::int, 0) + coalesce((pay->'reward'->>x.k)::int, 0) + coalesce((pay->'currency'->>x.k)::int, 0))
                                   from unnest(array['tickets', 'gold', 'blood', 'shard', 'soul']) x(k)) else rewards end,
    updated_at = now()
  where user_id = uid and tower = p_tower;
  return jsonb_build_object('ok', true, 'reward_held', true, 'tower', p_tower, 'first', first, 'paid', paid, 'floor', p_floor, 'best_floor', case when first then p_floor else r.best_floor end,
    'reward', case when paid then pay->'reward' else '{}'::jsonb end, 'currency', pay->'currency', 'tickets', pay->'tickets',
    'today', r.day_floors + 1, 'daily', _tower_daily(p_tower));
end $$;

create or replace function public.tower_sweep_complete(p_tower text, p_to int, p_stats jsonb default '{}'::jsonb) returns jsonb language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare uid uuid := auth.uid(); r tower_progress; b jsonb; f int; n int; fl int; pay jsonb; tk int := null; paidTo int;
  tot jsonb := '{}'::jsonb; floors jsonb := '[]'::jsonb; k text; turns jsonb := coalesce(p_stats->'turns', '[]'::jsonb);
begin
  r := _tower_row(uid, p_tower);
  b := r.battle;
  if b is null or not coalesce((b->>'sweep')::boolean, false) then raise exception 'sweep not started'; end if;
  f := (b->>'from')::int;
  if f <> r.best_floor + 1 then raise exception 'sweep stale'; end if;
  if p_to is null or p_to < f - 1 or p_to > (b->>'last')::int then raise exception 'invalid range'; end if;
  n := p_to - f + 1;
  if r.day_floors + n > _tower_daily(p_tower) then raise exception 'daily limit'; end if;
  if extract(epoch from clock_timestamp()) - (b->>'at')::numeric < n * _quest_sweep_secs() then raise exception 'too fast'; end if;
  if jsonb_typeof(turns) <> 'array' or jsonb_array_length(turns) < n
     or exists (select 1 from jsonb_array_elements(turns) x(v) where jsonb_typeof(x.v) <> 'number' or (x.v)::int < 1 or (x.v)::int > 40) then raise exception 'invalid stats'; end if;
  paidTo := r.paid_floor;
  for fl in f .. p_to loop
    if public._reward_battle_enabled() and fl > paidTo then
      pay := _tower_pay(uid, p_tower, fl); paidTo := fl; tk := coalesce((pay->>'tickets')::int, tk);
      floors := floors || jsonb_build_object('floor', fl, 'reward', pay->'reward', 'currency', pay->'currency');
      for k in select jsonb_object_keys((pay->'reward') || (pay->'currency')) loop
        tot := tot || jsonb_build_object(k, coalesce((tot->>k)::int, 0) + coalesce((pay->'reward'->>k)::int, 0) + coalesce((pay->'currency'->>k)::int, 0));
      end loop;
    else floors := floors || jsonb_build_object('floor', fl, 'reward', '{}'::jsonb, 'currency', '{}'::jsonb, 'paid_before', true);
    end if;
  end loop;
  update tower_progress set battle = null, clears = clears + n, day_floors = day_floors + n, best_floor = greatest(best_floor, p_to), paid_floor = paidTo,
    rewards = (select jsonb_object_agg(x.k, coalesce((rewards->>x.k)::int, 0) + coalesce((tot->>x.k)::int, 0)) from unnest(array['tickets', 'gold', 'blood', 'shard', 'soul']) x(k)),
    updated_at = now()
  where user_id = uid and tower = p_tower;
  return jsonb_build_object('ok', true, 'reward_held', true, 'tower', p_tower, 'from', f, 'to', p_to, 'cleared', n, 'boss', (b->>'boss')::int, 'best_floor', greatest(r.best_floor, p_to),
    'total', tot, 'floors', floors, 'tickets', tk, 'today', r.day_floors + n, 'daily', _tower_daily(p_tower));
end $$;

create or replace function public.quest_complete(p_floor int, p_stats jsonb default '{}'::jsonb) returns jsonb language sql security definer set search_path = pg_catalog, public, pg_temp as $$ select tower_complete('normal', p_floor, p_stats) $$;

create or replace function public.quest_sweep_complete(p_to int, p_stats jsonb default '{}'::jsonb) returns jsonb language sql security definer set search_path = pg_catalog, public, pg_temp as $$ select tower_sweep_complete('normal', p_to, p_stats) $$;

create or replace function public._ach_claim_one(p_uid uuid, p_key text) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare a jsonb; t jsonb; i int; n int; g int; prog int; rw jsonb; ok boolean; score int; sc jsonb;
begin
  -- 점수 마일스톤
  if p_key like 'score:%' then
    g := substr(p_key, 7)::int;
    if p_key <> public._ach_score_key(g) then raise exception 'invalid key'; end if;
    select x into sc from jsonb_array_elements(_ach_score_defs()) x where (x->>'goal')::int = g;
    if sc is null then raise exception 'invalid key'; end if;
    score := _ach_score(p_uid);
    if score < g then raise exception 'not done'; end if;
    insert into achievement_claims (user_id, key) values (p_uid, p_key) on conflict do nothing returning true into ok;
    if not coalesce(ok, false) then raise exception 'already claimed'; end if;
    return sc->'reward';
  end if;
  -- 일반 업적
  for a in select x from jsonb_array_elements(_ach_defs()) x loop
    n := jsonb_array_length(a->'tiers');
    for i in 0 .. n - 1 loop
      t := a->'tiers'->i; g := (t->>'goal')::int;
      if _ach_key(a->>'id', g) = p_key then
        prog := _ach_prog(p_uid, a->>'id');
        if prog < g then raise exception 'not done'; end if;
        insert into achievement_claims (user_id, key) values (p_uid, p_key) on conflict do nothing returning true into ok;
        if not coalesce(ok, false) then raise exception 'already claimed'; end if;
        return t->'reward';
      end if;
    end loop;
  end loop;
  raise exception 'invalid key';
end $$;

create or replace function public._guild_reward(p_uid uuid, p_gid bigint, p_rw jsonb, p_reason text, p_ref text) returns jsonb language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare ok boolean; w jsonb;
begin
  if p_reason in ('raid_attempt','raid_last_hit') then
    return jsonb_build_object('reward','{}'::jsonb,'reward_held',true);
  end if;
  if p_reason not in ('guild_checkin','guild_rally_week','guild_rally_bonus') or p_reason is null then
    raise exception 'reward verification pending';
  end if;
  insert into guild_claims (user_id, ref, guild_id, reward) values (p_uid, p_ref, p_gid, p_rw) on conflict do nothing returning true into ok;
  if not coalesce(ok, false) then raise exception 'already claimed'; end if;
  if coalesce((p_rw->>'loyalty')::int, 0) > 0 then perform _loyalty_add(p_uid, (p_rw->>'loyalty')::int, p_reason, null, jsonb_build_object('ref', p_ref)); end if;
  if coalesce((p_rw->>'gold')::int, 0) > 0 then w := _wallet_add(p_uid, jsonb_build_object('gold', (p_rw->>'gold')::int), p_reason); end if;
  if coalesce((p_rw->>'gem')::int, 0) > 0 then perform _gem_add(p_uid, (p_rw->>'gem')::int, 0, p_reason, 'guild:' || p_ref, jsonb_build_object('guild', p_gid)); end if;
  if coalesce((p_rw->>'tickets')::int, 0) > 0 then
    insert into story_gacha (user_id, last_draw) values (p_uid, _guild_day() - 1) on conflict (user_id) do nothing;
    update story_gacha set tickets = tickets + (p_rw->>'tickets')::int, updated_at = now() where user_id = p_uid;
  end if;
  if coalesce((p_rw->>'exp')::int, 0) > 0 and p_gid is not null then perform _guild_exp(p_gid, p_uid, (p_rw->>'exp')::int, p_reason, 'u:' || p_uid || ':' || p_ref); end if;
  return jsonb_build_object('reward', p_rw, 'wallet', w);
end $$;

create or replace function public._raid_close(a guild_raid_attempts, p_dmg bigint) returns jsonb language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare N jsonb := _raid_numbers(); k int; rw jsonb;
begin
  update guild_raid_attempts set damage = p_dmg, finished_at = now() where id = a.id;
  insert into guild_raid_damage (guild_id, week, user_id, damage, attempts) values (a.guild_id, a.week, a.user_id, p_dmg, 1)
    on conflict (guild_id, week, user_id) do update set damage = guild_raid_damage.damage + p_dmg, attempts = guild_raid_damage.attempts + 1, updated_at = now();
  k := _raid_hit(a.guild_id, a.week, a.user_id, p_dmg);
  rw := jsonb_build_object('loyalty', (N->'attempt'->>'loyalty')::int,
    'gold', least((N->'attempt'->>'gold_max')::int, (N->'attempt'->>'gold_base')::int + (p_dmg / (N->'attempt'->>'gold_per_damage')::int)::int), 'exp', (N->'attempt'->>'exp')::int);
  perform _guild_reward(a.user_id, a.guild_id, rw, 'raid_attempt', 'raida:' || a.id);
  if to_regprocedure('public._guild_event(uuid,text,integer)') is not null then perform _guild_event(a.user_id, 'raid', 1); end if;
  return jsonb_build_object('damage', p_dmg, 'cleared', k, 'got', '{}'::jsonb, 'reward_held', true);
end $$;

-- Cosmetic-only legacy score: already earned cosmetics are not confiscated.
create or replace function public._cosmo_ach_score(p_uid uuid) returns int
language plpgsql stable security definer set search_path = pg_catalog, public, pg_temp as $$
declare a jsonb; t jsonb; n int; i int; g int; s int := 0; k text;
begin
  for a in select x from jsonb_array_elements(_ach_defs()) x loop
    n := jsonb_array_length(a->'tiers');
    for i in 0 .. n - 1 loop
      t := a->'tiers'->i; g := (t->>'goal')::int; k := _ach_key(a->>'id', g);
      if exists (select 1 from achievement_claims c where c.user_id = p_uid and c.key = k) then
        s := s + case when i = n - 1 then 20 else 10 end;
      end if;
    end loop;
  end loop;
  return s;
end $$;

create or replace function public._star_chapter(d jsonb, p_chapter int) returns jsonb language plpgsql stable security definer set search_path = pg_catalog, public, pg_temp as $$
declare mx int; tot int; cl jsonb := coalesce(d->'cleared'->(p_chapter::text), '[]'::jsonb); got jsonb := coalesce(d->'starClaims'->(p_chapter::text), '[]'::jsonb); ms jsonb := '[]'::jsonb; m jsonb; need int;
begin
  select 3 * count(*) into mx from story_phase_config where chapter = p_chapter and (p_chapter >= 1 or phase = 4);
  select coalesce(sum(least(3, greatest(0, (s.value)::int))), 0) into tot
    from jsonb_each_text(case when jsonb_typeof(d->'stars'->(p_chapter::text)) = 'object' then d->'stars'->(p_chapter::text) else '{}'::jsonb end) s
    where s.key ~ '^\d+$' and cl @> to_jsonb(s.key::int)
      and exists (select 1 from story_phase_config c where c.chapter = p_chapter and c.phase = s.key::int and (p_chapter >= 1 or c.phase = 4));
  tot := least(tot, mx);
  for m in select * from jsonb_array_elements(_star_milestones()) loop
    need := coalesce((m->>'need')::int, mx);
    if mx = 0 or need > mx or (m->>'key' <> 'all' and need >= mx) then continue; end if;   -- 최대보다 크거나 '전부'와 같으면 생략
    ms := ms || (m || jsonb_build_object('need', need, 'claimed', got @> to_jsonb(m->>'key'), 'ready', false, 'held', true));
  end loop;
  return jsonb_build_object('chapter', p_chapter, 'total', tot, 'max', mx, 'milestones', ms);
end $$;

-- Explicit API allowlist for affected names: revoke EVERY overload, then grant
-- only the reviewed signatures (including default parameters on those signatures).
do $acl$
declare f record; obj text; col record;
begin
  for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.prokind='f' and
      (left(p.proname,1)='_' or p.proname = any(array[
        'gallery_register','daily_track','weekly_track','ach_track','daily_claim','weekly_claim',
        'daily_status','weekly_status','attend_claim','gallery_rewards','gallery_reward_claim',
        'achievements_status','achievements_claim','achievements_claim_all','arcade_tut_status',
        'arcade_tut_claim','story_star_claim','story_tickets','pvp_claim_tier','pvp_claim_reward',
        'pvp_report','raid_claim','war_claim','tower_complete','tower_sweep_complete',
        'quest_complete','quest_sweep_complete'])) loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
  end loop;
  foreach obj in array array[
    'gallery_register(text[],text)','daily_track(text,integer)','weekly_track(text,integer)','ach_track(text,integer)',
    'daily_claim(text)','weekly_claim(text)','daily_status()','weekly_status()','attend_claim()',
    'gallery_rewards()','gallery_reward_claim(integer)','achievements_status()','achievements_claim(text)',
    'achievements_claim_all()','arcade_tut_status()','arcade_tut_claim(integer)','story_star_claim(integer,text)',
    'story_tickets()','pvp_claim_tier(text,text)','pvp_claim_reward(text,text,date)',
    'pvp_report(bigint,integer,integer)','raid_claim()','war_claim()',
    'tower_complete(text,integer,jsonb)','tower_sweep_complete(text,integer,jsonb)',
    'quest_complete(integer,jsonb)','quest_sweep_complete(integer,jsonb)'] loop
    execute format('grant execute on function public.%s to authenticated',obj);
  end loop;
  -- Strip raw and column-level writes too; retain existing SELECT/RLS contracts.
  foreach obj in array array['gallery','gallery_claims','daily_progress','weekly_progress','daily_attend',
    'achievement_claims','ach_counters','story_progress','story_gacha','story_gacha_log',
    'player_wallet','player_state','player_items','gem_ledger','gem_login','arcade_tut_claims',
    'pvp_reward_claims','pvp_tier_claims','guild_claims','verified_game_events','reward_claims','reward_security_policy',
    'reward_card_catalog','story_card_pool','card_id_alias','gem_shop','pvp_streak_table','pvp_reward_table','pvp_tier_table'] loop
    execute format('alter table public.%I enable row level security',obj);
    execute format('revoke insert,update,delete,truncate,references,trigger on public.%I from public,anon,authenticated',obj);
    for col in select attname from pg_attribute where attrelid=to_regclass('public.'||obj) and attnum>0 and not attisdropped loop
      execute format('revoke insert (%I),update (%I),references (%I) on public.%I from public,anon,authenticated',col.attname,col.attname,col.attname,obj);
    end loop;
  end loop;
end $acl$;

revoke all on sequence public.verified_game_events_id_seq from public,anon,authenticated;

-- Sequence mutation must not let an API role forge a future source/ledger identity.
do $sequences$
declare obj text; seq text;
begin
  foreach obj in array array['story_gacha_log','gem_ledger'] loop
    seq := pg_get_serial_sequence('public.'||obj,'id');
    if seq is not null then execute format('revoke all on sequence %s from public,anon,authenticated',seq); end if;
  end loop;
end $sequences$;

do $verify_phase1$
begin
  if exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and left(p.proname,1)='_' and p.prokind='f'
      and (has_function_privilege('anon',p.oid,'execute') or has_function_privilege('authenticated',p.oid,'execute')))
    then raise exception 'STOP: private reward helper exposed'; end if;
  if has_table_privilege('authenticated','public.verified_game_events','INSERT')
    or has_table_privilege('authenticated','public.reward_claims','INSERT')
    or has_any_column_privilege('authenticated','public.story_gacha','UPDATE')
    or has_any_column_privilege('authenticated','public.daily_progress','INSERT')
    then raise exception 'STOP: raw reward writes exposed'; end if;
end $verify_phase1$;

-- Force PostgREST to see changed overload ACLs; never requires a service key.
notify pgrst, 'reload schema';

-- ===== REVIEWED DELTA SOURCE: security_phase2_clears.sql =====
select pg_advisory_xact_lock(20261107,502);

do $$ begin
  if to_regclass('public.reward_claims') is null or to_regprocedure('public._reward_battle_enabled()') is null then
    raise exception 'STOP: phase 1 required'; end if;
  if to_regclass('public.battle_sessions_v2') is not null and not exists(
    select 1 from pg_attribute where attrelid=to_regclass('public.battle_sessions_v2') and attname='settlement') then
    raise exception 'STOP: offline shadow prototype present; inspect before upgrade'; end if;
end $$;

-- Preserve reviewed economic implementations privately, once, before closing APIs.
do $preserve$
declare n text; sig text; src text; dest text;
begin
  foreach n in array array['story_start_phase','story_complete_phase','story_abort_phase','story_sweep','_ach_prog'] loop
    sig := case n when 'story_start_phase' then '(integer,integer)' when 'story_complete_phase' then '(integer,integer,jsonb)'
      when 'story_abort_phase' then '()' when 'story_sweep' then '(integer,integer,integer)' else '(uuid,text)' end;
    dest := '_phase2_old_' || ltrim(n,'_');
    if to_regprocedure('public.' || dest || sig) is null then
      src := pg_get_functiondef(to_regprocedure('public.' || n || sig));
      if src is null then raise exception 'STOP: missing %',n; end if;
      execute replace(src,'FUNCTION public.' || n || '(', 'FUNCTION public.' || dest || '(');
    end if;
  end loop;
end $preserve$;

create table if not exists public.battle_policy_v2(mode text primary key check(mode in ('tutorial','story','tower')), enabled boolean not null default true);

insert into public.battle_policy_v2(mode) values ('tutorial'),('story'),('tower') on conflict do nothing;

create table if not exists public.battle_legacy_access_v2(
  user_id uuid primary key references auth.users(id) on delete cascade,
  cleared jsonb not null default '{}', tower_best jsonb not null default '{}', tower_paid jsonb not null default '{}');

-- Frozen access-only baseline; never grants stars/rewards/missions for old JSON.
insert into public.battle_legacy_access_v2(user_id,cleared,tower_best,tower_paid)
select u.id,coalesce(s.data->'cleared','{}'),
  coalesce((select jsonb_object_agg(tower,best_floor) from public.tower_progress t where t.user_id=u.id),'{}'),
  coalesce((select jsonb_object_agg(tower,paid_floor) from public.tower_progress t where t.user_id=u.id),'{}')
from auth.users u left join public.story_progress s on s.user_id=u.id on conflict do nothing;

create table if not exists public.battle_session_seeds_v2(
  user_id uuid not null references auth.users(id) on delete cascade, mode text not null, target text not null,
  seed integer not null check(seed between 1 and 2147483646), rule_version integer not null default 3 check(rule_version=3),
  primary key(user_id,mode,target,rule_version));

create table if not exists public.battle_sessions_v2(
  id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
  request_id uuid not null, mode text not null check(mode in ('tutorial','story','tower','tower_sweep')),
  target text not null, party jsonb not null, seed integer not null, rule_version integer not null default 3 check(rule_version=3),
  snapshot jsonb not null, issued_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null default clock_timestamp()+interval '2 hours',
  status text not null default 'issued' check(status in ('issued','settled','expired','aborted')),
  submission jsonb, settlement jsonb, finished_at timestamptz,
  unique(user_id,request_id), check(expires_at>issued_at));

create unique index if not exists battle_sessions_v2_one_active on public.battle_sessions_v2(user_id) where status='issued';

create index if not exists battle_sessions_v2_daily on public.battle_sessions_v2(user_id,issued_at);

create table if not exists public.battle_clear_receipts_v2(
  user_id uuid not null references auth.users(id) on delete cascade, mode text not null, target text not null,
  session_id uuid not null references public.battle_sessions_v2(id), stars integer not null default 0 check(stars between 0 and 3),
  settled_at timestamptz not null default clock_timestamp(), primary key(user_id,mode,target));

create table if not exists public.battle_events_v2(
  session_id uuid primary key references public.battle_sessions_v2(id), user_id uuid not null references auth.users(id) on delete cascade,
  mode text not null, win boolean not null, skills integer not null, day date not null, week date not null);

create index if not exists battle_events_v2_period on public.battle_events_v2(user_id,day,week);

create table if not exists public.battle_acquisitions_v2(
  session_id uuid primary key references public.battle_sessions_v2(id), user_id uuid not null references auth.users(id) on delete cascade,
  card_id text not null references public.story_card_pool(id));

create table if not exists public.battle_card_meta_v2(id text primary key,definition jsonb not null);

create table if not exists public.battle_story_defs_v2(chapter integer not null,phase integer not null,variant text not null,
  definition jsonb not null, primary key(chapter,phase,variant));

create table if not exists public.battle_tutorial_defs_v2(stage integer primary key check(stage between 1 and 3),definition jsonb not null);

insert into public.battle_tutorial_defs_v2(stage,definition) values
  (1, '{"first":"me","me":["10019","10018","10299","10445","10404","10375","10325","10080","10074","10049"],"aiField":["10348","10339","10184"],"aiDeck":[],"aiHp":3000,"wipe":true,"levels":{"10325":7},"fullMp":["10019","10325"],"haste":["10325"],"bonus":{"3":30}}'::jsonb),
  (2, '{"first":"me","me":["10299","10137","10183","10045","10445","10404","10375","10060","10080","10074","10049"],"aiField":["10270","10462","10132","10202"],"aiDeck":[],"aiHp":3000,"meHpNow":2500,"wipe":true,"levels":{"10060":2},"fullMp":["10060"],"haste":["10060"],"bonus":{"1":30,"2":30,"3":10,"4":70}}'::jsonb),
  (3, '{"first":"me","me":["10036","10049","10118","10445","10404","10375","10080","10074","10311","10083"],"aiField":["10115","10103","10462","10256"],"aiDeck":[],"aiHp":3000,"wipe":true,"levels":{"10311":2},"fullMp":["10311"],"haste":["10311"],"mercs":["10292","10183","10325"],"bonus":{"1":0,"2":20,"3":80,"4":10,"5":50}}'::jsonb)
on conflict (stage) do nothing;

-- BEGIN GENERATED PHASE2 STORY
insert into public.battle_story_defs_v2(chapter,phase,variant,definition) values
(0,1,'','{"no":1,"type":"normal","enemies":{"ids":["10256"],"boost":{"10256":{"HP":700}}},"party":{"forced":["10325"],"mustLive":["10325"],"noExtra":true,"auto":true,"battleLevels":{"10325":2}},"fullMp":true,"hero":"10325","tutorial":true,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(0,2,'','{"no":2,"type":"normal","enemies":{"ids":["10154","10153","10153","10153","10153"]},"party":{"forced":["10325"],"mustLive":["10325"],"noExtra":true,"auto":true},"reserve":["10256"],"hero":"10325","tutorial":true,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(0,3,'','{"no":3,"type":"normal","enemies":{"ids":["10323","10168","10168","10168","10168"],"storyLevels":{"10168":30,"10323":30},"levels":{"10168":3,"10323":5}},"party":{"forced":["10325"],"mustLive":[],"fixedLevel":{"10325":1},"only":["10256","10462"],"guests":["10256","10462"]},"awaken":{"pauseOnEntrance":true,"on":"10325","id":"10326","storyLevel":100,"battleLevel":10,"line":"....약해...","image":"img/story/ch0-05.webp"},"hero":"10325","tutorial":true,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(0,4,'','{"no":4,"type":"normal","enemies":{"ids":["10111","10224","10265"],"levels":{"10111":2,"10224":2,"10265":2}},"party":{"forced":["10325","10256","10207","10462"],"mustLive":["10325"],"noExtra":true,"auto":true},"pool":true,"mana":200,"mustSummon":["10207"],"hero":"10325","tutorial":true,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(0,5,'','{"no":5,"type":"boss","enemies":{"ids":["10229","10391","10097","10093","10103"],"levels":{"10093":2,"10097":2,"10103":2,"10229":3,"10391":2}},"party":{"forced":["10325","10256","10207","10462","10208"],"mustLive":["10325"],"noExtra":true,"auto":true},"baseHp":300,"bossId":"10229","pool":true,"mana":200,"hero":"10325","tutorial":true,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(1,1,'','{"no":1,"type":"normal","enemies":{"count":1,"rank":[0,30]},"hero":null,"tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"starter","party":{}}'::jsonb),
(1,2,'','{"no":2,"type":"normal","enemies":{"count":2,"rank":[0,50]},"hero":null,"tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"starter","party":{}}'::jsonb),
(1,3,'','{"no":3,"type":"normal","enemies":{"count":2,"rank":[30,90]},"hero":null,"tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"starter","party":{}}'::jsonb),
(1,4,'','{"no":4,"type":"normal","enemies":{"count":3,"rank":[50,120]},"hero":null,"tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"starter","party":{}}'::jsonb),
(1,5,'','{"no":5,"type":"boss","enemies":{"count":4,"rank":[120,203]},"hero":null,"tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"starter","party":{}}'::jsonb),
(1,1,'10111','{"no":1,"type":"normal","enemies":{"ids":["10210"]},"party":{"forced":["10111","10112"]},"hero":null,"tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"starter"}'::jsonb),
(1,2,'10111','{"no":2,"type":"normal","enemies":{"ids":["10143","10144"]},"party":{"forced":["10111"]},"hero":null,"tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"starter"}'::jsonb),
(1,3,'10111','{"no":3,"type":"normal","enemies":{"ids":["10153","10143","10144"]},"party":{"forced":["10111"]},"hero":null,"tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"starter"}'::jsonb),
(1,4,'10111','{"no":4,"type":"normal","enemies":{"ids":["10154","10153","10143","10144"]},"party":{"forced":["10111"]},"hero":null,"tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"starter"}'::jsonb),
(1,5,'10111','{"no":5,"type":"boss","enemies":{"ids":["10146","10153","10143","10144","10145"]},"party":{"forced":["10111"]},"bossId":"10146","hero":null,"tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"starter"}'::jsonb),
(1,1,'10224','{"no":1,"type":"normal","enemies":{"ids":["10143"]},"party":{"forced":["10224"]},"hero":null,"tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"starter"}'::jsonb),
(1,2,'10224','{"no":2,"type":"normal","enemies":{"ids":["10153","10143"]},"party":{"forced":["10224"]},"hero":null,"tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"starter"}'::jsonb),
(1,3,'10224','{"no":3,"type":"normal","enemies":{"ids":["10145","10144"]},"party":{"forced":["10224"]},"hero":null,"tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"starter"}'::jsonb),
(1,4,'10224','{"no":4,"type":"normal","enemies":{"ids":["10145","10154","10153"]},"party":{"forced":["10224"]},"hero":null,"tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"starter"}'::jsonb),
(1,5,'10224','{"no":5,"type":"boss","enemies":{"ids":["10146","10153","10154","10145"]},"party":{"forced":["10224"]},"bossId":"10146","hero":null,"tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"starter"}'::jsonb),
(1,1,'10265','{"no":1,"type":"normal","enemies":{"ids":["10143"]},"party":{"forced":["10265"]},"hero":null,"tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"starter"}'::jsonb),
(1,2,'10265','{"no":2,"type":"normal","enemies":{"ids":["10153","10154"]},"party":{"forced":["10265"]},"hero":null,"tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"starter"}'::jsonb),
(1,3,'10265','{"no":3,"type":"normal","enemies":{"ids":["10143","10144"]},"party":{"forced":["10265"]},"hero":null,"tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"starter"}'::jsonb),
(1,4,'10265','{"no":4,"type":"normal","enemies":{"ids":["10145","10144","10153"]},"party":{"forced":["10265"]},"hero":null,"tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"starter"}'::jsonb),
(1,5,'10265','{"no":5,"type":"boss","enemies":{"ids":["10146","10144","10145","10153","10154"]},"party":{"forced":["10265"]},"bossId":"10146","hero":null,"tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"starter"}'::jsonb),
(2,1,'','{"no":1,"type":"normal","enemies":{"count":5,"rank":[60,203]},"hero":null,"tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"route","party":{}}'::jsonb),
(2,2,'','{"no":2,"type":"normal","enemies":{"count":5,"rank":[60,203]},"hero":null,"tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"route","party":{}}'::jsonb),
(2,3,'','{"no":3,"type":"normal","enemies":{"count":5,"rank":[60,203]},"hero":null,"tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"route","party":{}}'::jsonb),
(2,4,'','{"no":4,"type":"normal","enemies":{"count":5,"rank":[60,203]},"hero":null,"tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"route","party":{}}'::jsonb),
(2,5,'','{"no":5,"type":"normal","enemies":{"count":5,"rank":[60,203]},"hero":null,"tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"route","party":{}}'::jsonb)
on conflict (chapter,phase,variant) do update set definition=excluded.definition;

insert into public.battle_story_defs_v2(chapter,phase,variant,definition) values
(2,6,'','{"no":6,"type":"normal","enemies":{"count":5,"rank":[60,203]},"hero":null,"tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"route","party":{}}'::jsonb),
(2,7,'','{"no":7,"type":"normal","enemies":{"count":5,"rank":[60,203]},"hero":null,"tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"route","party":{}}'::jsonb),
(2,8,'','{"no":8,"type":"normal","enemies":{"count":5,"rank":[60,203]},"hero":null,"tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"route","party":{}}'::jsonb),
(2,9,'','{"no":9,"type":"normal","enemies":{"ids":["10368","10370","10149","10154","10153"]},"party":{"forced":["10298"],"exclude":["10125","10306"]},"rules":{"mustLive":["10298"]},"hero":null,"tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"route"}'::jsonb),
(2,10,'','{"no":10,"type":"boss","enemies":{"ids":["10369","10368","10370","10149","10146"]},"party":{"forced":["10298"],"exclude":["10125","10306"]},"bossId":"10369","rules":{"mustLive":["10298"]},"hero":null,"tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"route"}'::jsonb),
(2,1,'10081','{"no":1,"type":"normal","enemies":{"ids":["10147","10146","10145","10144","10143"]},"party":{"forced":["10081"]},"hero":"10081","tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"route"}'::jsonb),
(2,2,'10081','{"no":2,"type":"normal","enemies":{"ids":["10147","10146","10145","10144","10143"]},"party":{"forced":["10081"]},"hero":"10081","tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"route"}'::jsonb),
(2,3,'10081','{"no":3,"type":"normal","enemies":{"ids":["10147","10146","10145","10144","10143"]},"party":{"forced":["10081"]},"hero":"10081","tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"route"}'::jsonb),
(2,4,'10081','{"no":4,"type":"normal","enemies":{"ids":["10148","10147","10146","10145","10144"]},"party":{"forced":["10081"]},"hero":"10081","tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"route"}'::jsonb),
(2,5,'10081','{"no":5,"type":"normal","enemies":{"ids":["10149","10148","10147","10146","10145"]},"party":{"forced":["10081"]},"hero":"10081","tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"route"}'::jsonb),
(2,6,'10081','{"no":6,"type":"normal","enemies":{"ids":["10149","10148","10147","10146","10145"]},"party":{"forced":["10081"],"exclude":["10306"]},"hero":"10081","tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"route"}'::jsonb),
(2,7,'10081','{"no":7,"type":"normal","enemies":{"ids":["10082","10082","10082"]},"party":{"forced":["10081"],"exclude":["10252","10306"]},"rules":{"mustLive":["10081"]},"hero":"10081","tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"route"}'::jsonb),
(2,8,'10081','{"no":8,"type":"normal","enemies":{"ids":["10082","10082","10082","10082","10082"]},"party":{"forced":["10081","10062"],"exclude":["10252","10306"]},"rules":{"mustLive":["10081"]},"hero":"10081","tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"route"}'::jsonb),
(2,9,'10081','{"no":9,"type":"normal","enemies":{"ids":["10147","10146","10144","10145","10143"]},"party":{"forced":["10081"],"exclude":["10252","10306"]},"rules":{"mustLive":["10081"]},"hero":"10081","tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"route"}'::jsonb),
(2,10,'10081','{"no":10,"type":"boss","enemies":{"ids":["10369","10368","10370","10149","10148"]},"party":{"forced":["10081"],"exclude":["10252","10306"]},"bossId":"10369","rules":{"mustLive":["10081"]},"hero":"10081","tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"route"}'::jsonb),
(2,1,'10298','{"no":1,"type":"normal","enemies":{"ids":["10146","10143","10144","10145"]},"party":{"forced":["10298"]},"hero":"10298","tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"route"}'::jsonb),
(2,2,'10298','{"no":2,"type":"normal","enemies":{"ids":["10146","10147","10145","10144","10143"]},"party":{"forced":["10298"]},"hero":"10298","tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"route"}'::jsonb),
(2,3,'10298','{"no":3,"type":"normal","enemies":{"ids":["10148","10146","10145","10144","10143"]},"party":{"forced":["10298"]},"hero":"10298","tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"route"}'::jsonb),
(2,4,'10298','{"no":4,"type":"normal","enemies":{"ids":["10149","10146","10145","10144","10143"]},"party":{"forced":["10306","10125"],"exclude":["10298"]},"hero":"10298","tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"route"}'::jsonb),
(2,5,'10298','{"no":5,"type":"normal","enemies":{"ids":["10149","10153","10146","10144","10145"]},"party":{"forced":["10306","10125"],"exclude":["10298"]},"hero":"10298","tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"route"}'::jsonb),
(2,6,'10298','{"no":6,"type":"normal","enemies":{"ids":["10149","10154","10153","10146","10145"]},"party":{"forced":["10306","10125"],"exclude":["10298"]},"hero":"10298","tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"route"}'::jsonb),
(2,7,'10298','{"no":7,"type":"normal","enemies":{"ids":["10149","10154","10153","10146","10145"]},"party":{"forced":["10306","10125"],"exclude":["10298"]},"rules":{"mustLive":["10306"]},"hero":"10298","tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"route"}'::jsonb),
(2,8,'10298','{"no":8,"type":"normal","enemies":{"ids":["10149","10154","10153","10146","10145"]},"party":{"forced":["10298"],"exclude":["10125"]},"rules":{"mustLive":["10298"]},"hero":"10298","tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"route"}'::jsonb),
(2,9,'10298','{"no":9,"type":"normal","enemies":{"ids":["10368","10370","10149","10154","10153"]},"party":{"forced":["10298"],"exclude":["10125","10306"]},"rules":{"mustLive":["10298"]},"hero":"10298","tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"route"}'::jsonb),
(2,10,'10298','{"no":10,"type":"boss","enemies":{"ids":["10369","10368","10370","10149","10146"]},"party":{"forced":["10298"],"exclude":["10125","10306"]},"bossId":"10369","rules":{"mustLive":["10298"]},"hero":"10298","tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"route"}'::jsonb),
(3,1,'','{"no":1,"type":"normal","enemies":{"ids":["10157","10156","10155","10154","10153"]},"party":{"forced":["10384"],"noMale":true},"bossId":"10157","hero":"10384","tutorial":false,"single":true,"loan":["10384","10383"],"loanLevel":{},"variantKind":"none"}'::jsonb),
(3,2,'','{"no":2,"type":"normal","enemies":{"ids":["10097","10297","10290","10103","10432"]},"party":{"forced":["10384"],"maxMor":49},"bossId":"10097","hero":"10384","tutorial":false,"single":true,"loan":["10384","10383"],"loanLevel":{},"variantKind":"none"}'::jsonb),
(3,3,'','{"no":3,"type":"normal","enemies":{"ids":["10280","10160","10159","10158","10157"]},"party":{"forced":["10383"]},"bossId":"10280","hero":"10384","tutorial":false,"single":true,"loan":["10384","10383"],"loanLevel":{},"variantKind":"none"}'::jsonb),
(3,4,'','{"no":4,"type":"normal","enemies":{"ids":["10393","10290","10097","10306","10041"]},"party":{"forced":["10384"],"exclude":["10383"]},"bossId":"10393","hero":"10384","tutorial":false,"single":true,"loan":["10384","10383"],"loanLevel":{},"variantKind":"none"}'::jsonb),
(3,5,'','{"no":5,"type":"normal","enemies":{"ids":["10290","10306","10097","10405","10227"]},"party":{"forced":["10384"],"exclude":["10383"]},"bossId":"10290","hero":"10384","tutorial":false,"single":true,"loan":["10384","10383"],"loanLevel":{},"variantKind":"none"}'::jsonb)
on conflict (chapter,phase,variant) do update set definition=excluded.definition;

insert into public.battle_story_defs_v2(chapter,phase,variant,definition) values
(3,6,'','{"no":6,"type":"normal","enemies":{"ids":["10290","10306","10097","10405","10229"]},"party":{"forced":["10384"],"exclude":["10383"],"maxGrade":"HIGH RARE"},"bossId":"10290","spare":{"10229":["10384"]},"hero":"10384","tutorial":false,"single":true,"loan":["10384","10383"],"loanLevel":{},"variantKind":"none"}'::jsonb),
(3,7,'','{"no":7,"type":"normal","enemies":{"ids":["10229","10040","10097","10466","10290"]},"party":{"forced":["10384","10383"]},"bossId":"10229","enemyFirst":true,"hero":"10384","tutorial":false,"single":true,"loan":["10384","10383"],"loanLevel":{},"variantKind":"none"}'::jsonb),
(3,8,'','{"no":8,"type":"normal","enemies":{"ids":["10123","10161","10160","10159","10158"]},"party":{"forced":["10384"]},"bossId":"10123","enemyFirst":true,"hero":"10384","tutorial":false,"single":true,"loan":["10384","10383"],"loanLevel":{},"variantKind":"none"}'::jsonb),
(3,9,'','{"no":9,"type":"normal","enemies":{"ids":["10123","10183","10161","10160","10159"]},"party":{"forced":["10383"],"maxGrade":"SUPER RARE"},"bossId":"10123","hero":"10384","tutorial":false,"single":true,"loan":["10384","10383"],"loanLevel":{},"variantKind":"none"}'::jsonb),
(3,10,'','{"no":10,"type":"boss","enemies":{"ids":["10200","10161","10160","10123","10025"]},"party":{"forced":["10384"],"exclude":["10383"]},"bossId":"10200","hero":"10384","tutorial":false,"single":true,"loan":["10384","10383"],"loanLevel":{},"variantKind":"none"}'::jsonb),
(4,1,'','{"no":1,"type":"normal","enemies":{"ids":["10153","10154","10155","10156","10157"]},"party":{"forced":["10300"]},"bossId":"10157","hero":"10300","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(4,2,'','{"no":2,"type":"normal","enemies":{"ids":["10153","10154","10156","10157","10158"]},"party":{"forced":["10300"]},"bossId":"10158","hero":"10300","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(4,3,'','{"no":3,"type":"normal","enemies":{"ids":["10160","10161","10162","10163","10159"]},"party":{"forced":["10300"]},"bossId":"10159","hero":"10300","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(4,4,'','{"no":4,"type":"normal","enemies":{"ids":["10156","10165","10166","10159","10164"]},"party":{"forced":["10300","10325"]},"bossId":"10164","rules":{"mustLive":["10300"]},"hero":"10300","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(4,5,'','{"no":5,"type":"normal","enemies":{"ids":["10156","10164","10165","10166","10167"]},"party":{"forced":["10300","10325"]},"bossId":"10167","rules":{"mustLive":["10300"]},"hero":"10300","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(4,6,'','{"no":6,"type":"normal","enemies":{"ids":["10168","10156","10154","10153","10159"]},"party":{"forced":["10300"]},"bossId":"10159","rules":{"mustLive":["10300"]},"hero":"10300","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(4,7,'','{"no":7,"type":"normal","enemies":{"ids":["10156","10154","10153","10159","10072"]},"party":{"forced":["10300"]},"bossId":"10072","rules":{"mustLive":["10300"]},"hero":"10300","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(4,8,'','{"no":8,"type":"normal","enemies":{"ids":["10160","10161","10162","10168","10072"]},"party":{"forced":["10300"]},"bossId":"10072","rules":{"revive":[{"id":"10072","level":1,"delay":2}]},"hero":"10300","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(4,9,'','{"no":9,"type":"normal","enemies":{"ids":["10161","10162","10072","10168","10325"]},"party":{"forced":["10300"]},"bossId":"10325","rules":{"revive":[{"id":"10072","level":"keep","delay":2},{"id":"10256","level":"keep","delay":2}]},"hero":"10300","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(4,10,'','{"no":10,"type":"normal","enemies":{"ids":["10301","10302","10302","10302","10302"],"levels":{"10301":5},"boost":{"10302":{"HP":317,"ATK":62,"DEF":62,"power":13277}}},"party":{"forced":["10325"]},"bossId":"10301","rules":{"invuln":"10301","expire":10,"revive":[{"id":"10302","level":1,"delay":1}]},"hero":"10300","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(5,1,'','{"no":1,"type":"normal","enemies":{"ids":["10153","10154","10155","10156","10157"],"storyLevels":{"10153":25,"10154":25,"10155":25,"10156":25,"10157":30}},"party":{"forced":["10442"]},"bossId":"10157","hero":"10442","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(5,2,'','{"no":2,"type":"normal","enemies":{"ids":["10143","10158","10155","10156","10159"],"storyLevels":{"10143":25,"10155":25,"10156":25,"10158":25,"10159":30}},"party":{"forced":["10442"]},"bossId":"10159","hero":"10442","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(5,3,'','{"no":3,"type":"normal","enemies":{"ids":["10159","10153","10154","10357","10360"],"boost":{"10360":{"HP":150,"ATK":30,"DEF":26,"power":2241}},"storyLevels":{"10153":25,"10154":25,"10159":25,"10357":25}},"party":{"forced":["10442"]},"bossId":"10360","hero":"10442","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(5,4,'','{"no":4,"type":"normal","enemies":{"ids":["10158","10160","10161","10162","10163"],"storyLevels":{"10158":25,"10160":25,"10161":25,"10162":25,"10163":30}},"party":{"forced":["10442"]},"bossId":"10163","hero":"10442","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(5,5,'','{"no":5,"type":"normal","enemies":{"ids":["10153","10154","10156","10164","10165"],"storyLevels":{"10153":25,"10154":25,"10156":25,"10164":25,"10165":30}},"party":{"forced":["10442"]},"bossId":"10165","hero":"10442","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(5,6,'','{"no":6,"type":"normal","enemies":{"ids":["10166","10167","10144","10145","10146"],"storyLevels":{"10144":25,"10145":25,"10146":30,"10166":25,"10167":25}},"party":{"forced":["10442"]},"bossId":"10146","hero":"10442","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(5,7,'','{"no":7,"type":"normal","enemies":{"ids":["10152","10147","10148","10149","10150"],"storyLevels":{"10147":25,"10148":25,"10149":25,"10150":30,"10152":25}},"party":{"forced":["10442"],"banClass":["DARK"]},"bossId":"10150","hero":"10442","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(5,8,'','{"no":8,"type":"normal","enemies":{"ids":["10152","10147","10148","10143","10150"],"storyLevels":{"10143":25,"10147":25,"10148":25,"10150":30,"10152":25}},"party":{"forced":["10442"],"banClass":["LIGHT"]},"bossId":"10150","hero":"10442","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(5,9,'','{"no":9,"type":"normal","enemies":{"ids":["10150","10152","10144","10145","10146"],"storyLevels":{"10144":25,"10145":25,"10146":30,"10150":25,"10152":25}},"party":{"forced":["10442"],"maxGrade":"SUPER RARE"},"bossId":"10146","hero":"10442","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(5,10,'','{"no":10,"type":"boss","enemies":{"ids":["10357","10168","10143","10147","10360"],"boost":{"10357":{"HP":240,"ATK":40,"DEF":30,"power":7800},"10360":{"HP":360,"ATK":62,"DEF":44,"power":4883}},"storyLevels":{"10143":25,"10147":25,"10168":25}},"party":{"forced":["10399"],"maxGrade":"SUPER RARE","exclude":["10442"]},"bossId":"10360","rules":{"undying":["10357"]},"hero":"10442","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(6,1,'','{"no":1,"type":"normal","enemies":{"ids":["10210","10151","10151"]},"party":{"forced":["10112","10111"]},"bossId":"10210","hero":"10110","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(6,2,'','{"no":2,"type":"normal","enemies":{"ids":["10146","10153","10143","10144","10145"]},"party":{"forced":["10111"]},"bossId":"10146","hero":"10110","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(6,3,'','{"no":3,"type":"normal","enemies":{"ids":["10152","10152","10152","10152","10152"]},"party":{"forced":["10111"]},"bossId":"10152","hero":"10110","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(6,4,'','{"no":4,"type":"normal","enemies":{"ids":["10163","10163","10163","10163","10163"]},"party":{"forced":["10111"],"exclude":["10325"]},"bossId":"10163","hero":"10110","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(6,5,'','{"no":5,"type":"normal","enemies":{"ids":["10166","10163","10163","10163","10163"]},"party":{"forced":["10110"],"exclude":["10111"]},"bossId":"10166","hero":"10110","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb)
on conflict (chapter,phase,variant) do update set definition=excluded.definition;

insert into public.battle_story_defs_v2(chapter,phase,variant,definition) values
(6,6,'','{"no":6,"type":"normal","enemies":{"ids":["10166","10166","10166","10166","10166"]},"party":{"forced":["10110"],"exclude":["10325","10111"]},"bossId":"10166","hero":"10110","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(6,7,'','{"no":7,"type":"normal","enemies":{"ids":["10419","10166","10166","10163","10163"]},"party":{"forced":["10110"],"exclude":["10325","10111","10112"]},"bossId":"10419","hero":"10110","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(6,8,'','{"no":8,"type":"normal","enemies":{"ids":["10035","10167","10167","10166","10166"]},"party":{"forced":["10110"],"exclude":["10325","10111","10112"]},"bossId":"10035","hero":"10110","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(6,9,'','{"no":9,"type":"normal","enemies":{"ids":["10321","10168","10168","10167","10167"]},"party":{"forced":["10110"],"exclude":["10325","10111","10112"]},"bossId":"10321","hero":"10110","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(6,10,'','{"no":10,"type":"boss","enemies":{"ids":["10325","10168","10168","10168","10168"]},"party":{"forced":["10110"],"exclude":["10325","10111","10112"]},"bossId":"10325","hero":"10110","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(7,1,'','{"no":1,"type":"normal","enemies":{"ids":["10162","10161","10161","10161","10161"],"boost":{"10161":{"HP":231,"ATK":48,"DEF":41,"storyLv":40,"power":8753},"10162":{"HP":267,"ATK":53,"DEF":46,"storyLv":40,"power":9939}}},"party":{"forced":["10115","10267"],"noMale":true,"mustLive":["10115"],"levels":{"10115":40,"10267":40}},"bossId":"10162","hero":"10115","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(7,2,'','{"no":2,"type":"normal","enemies":{"ids":["10163","10149","10148","10146","10146"],"boost":{"10146":{"HP":97,"ATK":19,"DEF":15,"storyLv":40,"power":1328},"10148":{"HP":160,"ATK":27,"DEF":18,"storyLv":40,"power":5017},"10149":{"HP":196,"ATK":36,"DEF":27,"storyLv":40,"power":6877},"10163":{"HP":391,"ATK":65,"DEF":56,"storyLv":40,"power":21555}}},"party":{"forced":["10115","10267"],"mustLive":["10115"],"levels":{"10115":40,"10267":40}},"bossId":"10163","hero":"10115","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(7,3,'','{"no":3,"type":"normal","enemies":{"ids":["10151","10148","10148","10148","10148"],"boost":{"10148":{"HP":160,"ATK":27,"DEF":18,"storyLv":40,"power":5017},"10151":{"HP":494,"ATK":74,"DEF":74,"storyLv":50,"power":26808}}},"party":{"forced":["10115","10267"],"mustLive":["10115"],"levels":{"10115":40,"10267":40}},"bossId":"10151","hero":"10115","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(7,4,'','{"no":4,"type":"normal","enemies":{"ids":["10165","10164","10164","10164","10164"],"boost":{"10164":{"HP":469,"ATK":74,"DEF":64,"storyLv":50,"power":25336},"10165":{"HP":494,"ATK":74,"DEF":74,"storyLv":50,"power":26808}}},"party":{"forced":["10115","10267"],"noMale":true,"mustLive":["10115"],"levels":{"10115":40,"10267":40}},"bossId":"10165","hero":"10115","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(7,5,'','{"no":5,"type":"normal","enemies":{"ids":["10164","10163","10163","10163","10163"],"boost":{"10163":{"HP":445,"ATK":74,"DEF":64,"storyLv":50,"power":24551},"10164":{"HP":526,"ATK":83,"DEF":72,"storyLv":60,"power":28430}}},"party":{"forced":["10267"],"noMale":true,"exclude":["10115"],"mustLive":["10267"]},"bossId":"10164","hero":"10115","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(7,6,'','{"no":6,"type":"normal","enemies":{"ids":["10267"],"boost":{"10267":{"HP":430,"ATK":65,"DEF":140,"storyLv":30,"power":41589}}},"party":{"forced":["10115"],"exclude":["10267"],"max":3,"maxGrade":"SUPER RARE","mustLive":[]},"bossId":"10267","hero":"10115","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(7,7,'','{"no":7,"type":"normal","enemies":{"ids":["10198","10196","10197","10199"],"boost":{"10196":{"HP":127,"ATK":16,"DEF":16,"storyLv":60,"power":1709},"10197":{"HP":127,"ATK":16,"DEF":16,"storyLv":60,"power":1709},"10198":{"HP":127,"ATK":16,"DEF":16,"storyLv":60,"power":1709},"10199":{"HP":240,"ATK":33,"DEF":33,"storyLv":60,"power":8337}}},"party":{"forced":["10018","10019","10299","10074"],"max":5,"noFemale":true,"maxMor":39,"mustLive":[]},"bossId":"10198","hero":"10115","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(7,8,'','{"no":8,"type":"normal","enemies":{"ids":["10144","10143","10143","10143","10143"],"boost":{"10143":{"HP":80,"ATK":17,"DEF":13,"storyLv":60,"power":1076},"10144":{"HP":80,"ATK":19,"DEF":14,"storyLv":60,"power":1126}}},"party":{"forced":["10115","10018"],"noFemale":true,"exclude":["10118"],"mustLive":["10115"]},"bossId":"10144","hero":"10115","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(7,9,'','{"no":9,"type":"normal","enemies":{"ids":["10299","10019","10018","10074"],"boost":{"10018":{"HP":251,"ATK":46,"DEF":31,"storyLv":60,"power":9153},"10019":{"HP":240,"ATK":44,"DEF":33,"storyLv":60,"power":9100},"10074":{"HP":48,"ATK":8,"DEF":10,"storyLv":60,"power":523},"10299":{"HP":554,"ATK":97,"DEF":69,"storyLv":60,"power":28335}}},"party":{"forced":["10115"],"exclude":["10267","10118"],"mustLive":["10115"]},"bossId":"10299","hero":"10115","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(7,10,'','{"no":10,"type":"boss","enemies":{"ids":["10116","10116","10116","10116","10116"],"boost":{"10116":{"HP":1008,"ATK":50,"DEF":151,"storyLv":60,"power":80121}}},"party":{"forced":["10115"],"exclude":["10118"],"mustLive":["10115"]},"bossId":"10116","hero":"10115","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(8,1,'','{"no":1,"type":"normal","enemies":{"ids":["10494","10495","10495","10495","10495"],"boost":{"10494":{"HP":111,"ATK":17,"DEF":14,"storyLv":40,"power":1433},"10495":{"HP":214,"ATK":27,"DEF":18,"storyLv":40,"power":6130}}},"party":{"forced":["10493"],"mustLive":["10493"],"levels":{"10493":80}},"bossId":"10494","hero":"10231","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(8,2,'','{"no":2,"type":"normal","enemies":{"ids":["10496","10497","10497","10497","10497"],"boost":{"10496":{"HP":386,"ATK":54,"DEF":54,"storyLv":40,"power":19302},"10497":{"HP":97,"ATK":14,"DEF":14,"storyLv":40,"power":1337}}},"party":{"forced":["10493"],"mustLive":["10493"],"levels":{"10493":80}},"bossId":"10496","hero":"10231","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(8,3,'','{"no":3,"type":"normal","enemies":{"ids":["10144","10145","10145","10145","10145"],"boost":{"10144":{"HP":70,"ATK":17,"DEF":13,"storyLv":40,"power":1003},"10145":{"HP":83,"ATK":18,"DEF":14,"storyLv":40,"power":1131}}},"party":{"forced":["10231"],"noMale":true,"mustLive":["10231"],"levels":{"10231":50}},"bossId":"10144","hero":"10231","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(8,4,'','{"no":4,"type":"normal","enemies":{"ids":["10501","10500","10500","10500","10500"],"boost":{"10500":{"HP":217,"ATK":48,"DEF":48,"storyLv":40,"power":9293},"10501":{"HP":458,"ATK":82,"DEF":82,"storyLv":40,"power":28432}}},"party":{"forced":["10231"],"noMale":true,"mustLive":["10231"],"levels":{"10231":50}},"bossId":"10501","hero":"10231","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(8,5,'','{"no":5,"type":"normal","enemies":{"ids":["10154","10144","10145","10153","10155"],"boost":{"10144":{"HP":70,"ATK":17,"DEF":13,"storyLv":42,"power":1003},"10145":{"HP":85,"ATK":18,"DEF":14,"storyLv":42,"power":1145},"10153":{"HP":85,"ATK":14,"DEF":10,"storyLv":42,"power":1066},"10154":{"HP":99,"ATK":16,"DEF":11,"storyLv":42,"power":1226},"10155":{"HP":113,"ATK":17,"DEF":13,"storyLv":42,"power":1383}}},"party":{"forced":["10231"],"noMale":true,"mustLive":["10231"],"levels":{"10231":42}},"bossId":"10154","hero":"10231","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(8,6,'','{"no":6,"type":"normal","enemies":{"ids":["10153","10154","10155","10156","10156"],"boost":{"10153":{"HP":87,"ATK":14,"DEF":10,"storyLv":46,"power":1082},"10154":{"HP":102,"ATK":16,"DEF":12,"storyLv":46,"power":1265},"10155":{"HP":116,"ATK":17,"DEF":13,"storyLv":46,"power":1406},"10156":{"HP":130,"ATK":19,"DEF":14,"storyLv":46,"power":1664}}},"party":{"forced":["10231"],"noMale":true,"mustLive":["10231"],"levels":{"10231":46}},"bossId":"10153","hero":"10231","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(8,7,'','{"no":7,"type":"normal","enemies":{"ids":["10157","10144","10145","10155","10156"],"boost":{"10144":{"HP":74,"ATK":18,"DEF":13,"storyLv":50,"power":1050},"10145":{"HP":89,"ATK":19,"DEF":15,"storyLv":50,"power":1207},"10155":{"HP":119,"ATK":18,"DEF":13,"storyLv":50,"power":1448},"10156":{"HP":134,"ATK":19,"DEF":15,"storyLv":50,"power":1713},"10157":{"HP":149,"ATK":21,"DEF":16,"storyLv":50,"power":1892}}},"party":{"forced":["10231"],"noMale":true,"mustLive":["10231"],"levels":{"10231":50}},"bossId":"10157","hero":"10231","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(8,8,'','{"no":8,"type":"normal","enemies":{"ids":["10500","10501","10501","10501","10501"],"boost":{"10500":{"HP":246,"ATK":55,"DEF":55,"storyLv":52,"power":10591},"10501":{"HP":534,"ATK":96,"DEF":96,"storyLv":52,"power":33210}}},"party":{"forced":["10231"],"noMale":true,"mustLive":["10231"],"levels":{"10231":52}},"bossId":"10500","hero":"10231","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(8,9,'','{"no":9,"type":"normal","enemies":{"ids":["10494","10495","10496","10144","10145"],"boost":{"10144":{"HP":76,"ATK":18,"DEF":14,"storyLv":54,"power":1079},"10145":{"HP":92,"ATK":20,"DEF":15,"storyLv":54,"power":1247},"10494":{"HP":122,"ATK":18,"DEF":15,"storyLv":54,"power":1556},"10495":{"HP":247,"ATK":31,"DEF":21,"storyLv":54,"power":7076},"10496":{"HP":461,"ATK":65,"DEF":65,"storyLv":54,"power":23122}}},"party":{"forced":["10493"],"exclude":["10231"],"mustLive":["10493"],"levels":{"10493":54}},"bossId":"10494","hero":"10231","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(8,10,'','{"no":10,"type":"normal","enemies":{"ids":["10156","10153","10154","10157","10157"],"boost":{"10153":{"HP":93,"ATK":16,"DEF":11,"storyLv":56,"power":1180},"10154":{"HP":108,"ATK":17,"DEF":12,"storyLv":56,"power":1329},"10156":{"HP":140,"ATK":20,"DEF":16,"storyLv":56,"power":1798},"10157":{"HP":155,"ATK":22,"DEF":17,"storyLv":56,"power":1977}}},"party":{"forced":["10231"],"noMale":true,"mustLive":["10231"],"levels":{"10231":56}},"bossId":"10156","hero":"10231","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(8,11,'','{"no":11,"type":"normal","enemies":{"ids":["10494","10495","10496","10497","10498"],"boost":{"10494":{"HP":126,"ATK":19,"DEF":16,"storyLv":58,"power":1623},"10495":{"HP":257,"ATK":32,"DEF":21,"storyLv":58,"power":7318},"10496":{"HP":482,"ATK":68,"DEF":68,"storyLv":58,"power":24180},"10497":{"HP":110,"ATK":16,"DEF":16,"storyLv":58,"power":1521},"10498":{"HP":259,"ATK":39,"DEF":64,"storyLv":58,"power":9524}}},"party":{"forced":["10493"],"exclude":["10231"],"mustLive":["10493"],"levels":{"10493":58}},"bossId":"10494","hero":"10231","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(8,12,'','{"no":12,"type":"normal","enemies":{"ids":["10155","10144","10145","10154","10157"],"boost":{"10144":{"HP":79,"ATK":19,"DEF":14,"storyLv":59,"power":1119},"10145":{"HP":95,"ATK":21,"DEF":16,"storyLv":59,"power":1301},"10154":{"HP":111,"ATK":17,"DEF":13,"storyLv":59,"power":1368},"10155":{"HP":126,"ATK":19,"DEF":14,"storyLv":59,"power":1536},"10157":{"HP":158,"ATK":22,"DEF":17,"storyLv":59,"power":2001}}},"party":{"forced":["10231"],"noMale":true,"mustLive":["10231"],"levels":{"10231":59}},"bossId":"10155","hero":"10231","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(8,13,'','{"no":13,"type":"normal","enemies":{"ids":["10493","10493","10493","10493","10493"],"boost":{"10493":{"HP":554,"ATK":83,"DEF":83,"storyLv":60,"power":41039}}},"party":{"forced":["10231"],"noMale":true,"mustLive":["10231"],"levels":{"10231":60}},"bossId":"10493","hero":"10231","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(8,14,'','{"no":14,"type":"normal","enemies":{"ids":["10494","10495","10496","10153","10156"],"boost":{"10153":{"HP":95,"ATK":16,"DEF":11,"storyLv":60,"power":1195},"10156":{"HP":143,"ATK":21,"DEF":16,"storyLv":60,"power":1843},"10494":{"HP":127,"ATK":19,"DEF":16,"storyLv":60,"power":1631},"10495":{"HP":262,"ATK":33,"DEF":22,"storyLv":60,"power":7501},"10496":{"HP":493,"ATK":69,"DEF":69,"storyLv":60,"power":24657}}},"party":{"forced":["10231"],"noMale":true,"mustLive":["10231"],"levels":{"10231":60}},"bossId":"10494","hero":"10231","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(8,15,'','{"no":15,"type":"boss","enemies":{"ids":["10502"],"boost":{"10502":{"HP":1344,"ATK":151,"DEF":151,"storyLv":60,"power":146456}}},"party":{"forced":["10231"],"noMale":true,"mustLive":["10231"],"levels":{"10231":60}},"bossId":"10502","hero":"10231","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb)
on conflict (chapter,phase,variant) do update set definition=excluded.definition;

insert into public.battle_story_defs_v2(chapter,phase,variant,definition) values
(9,1,'','{"no":1,"type":"normal","enemies":{"ids":["10144","10145","10145","10145","10145"],"boost":{"10144":{"HP":70,"ATK":17,"DEF":13,"storyLv":40,"power":1003},"10145":{"HP":83,"ATK":18,"DEF":14,"storyLv":40,"power":1131}}},"party":{"maxGrade":"HIGH RARE","forced":["10415"],"noMale":true,"mustLive":["10415"],"levels":{"10415":40}},"bossId":"10144","hero":"10415","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(9,2,'','{"no":2,"type":"normal","enemies":{"ids":["10145","10153","10153","10144","10144"],"boost":{"10144":{"HP":70,"ATK":17,"DEF":13,"storyLv":41,"power":1003},"10145":{"HP":84,"ATK":18,"DEF":14,"storyLv":41,"power":1138},"10153":{"HP":84,"ATK":14,"DEF":10,"storyLv":41,"power":1059}}},"party":{"maxGrade":"HIGH RARE","forced":["10415"],"noMale":true,"mustLive":["10415"],"levels":{"10415":41}},"bossId":"10145","hero":"10415","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(9,3,'','{"no":3,"type":"normal","enemies":{"ids":["10153","10154","10154","10145","10145"],"boost":{"10145":{"HP":85,"ATK":18,"DEF":14,"storyLv":43,"power":1145},"10153":{"HP":85,"ATK":14,"DEF":10,"storyLv":43,"power":1066},"10154":{"HP":99,"ATK":16,"DEF":11,"storyLv":43,"power":1226}}},"party":{"maxGrade":"HIGH RARE","forced":["10413"],"exclude":["10415"],"mustLive":["10413"],"levels":{"10413":43}},"bossId":"10153","hero":"10415","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(9,4,'','{"no":4,"type":"normal","enemies":{"ids":["10154","10155","10155","10153","10153"],"boost":{"10153":{"HP":86,"ATK":14,"DEF":10,"storyLv":44,"power":1074},"10154":{"HP":100,"ATK":16,"DEF":11,"storyLv":44,"power":1234},"10155":{"HP":114,"ATK":17,"DEF":13,"storyLv":44,"power":1391}}},"party":{"maxGrade":"HIGH RARE","forced":["10414"],"exclude":["10415"],"mustLive":["10414"],"levels":{"10414":44}},"bossId":"10154","hero":"10415","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(9,5,'','{"no":5,"type":"normal","enemies":{"ids":["10478","10144","10144","10145","10145"],"boost":{"10144":{"HP":72,"ATK":17,"DEF":13,"storyLv":45,"power":1018},"10145":{"HP":86,"ATK":19,"DEF":14,"storyLv":45,"power":1170},"10478":{"HP":209,"ATK":30,"DEF":30,"storyLv":45,"power":7718}}},"party":{"maxGrade":"HIGH RARE","forced":["10415"],"noMale":true,"mustLive":["10415"],"levels":{"10415":45}},"bossId":"10478","hero":"10415","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(9,6,'','{"no":6,"type":"normal","enemies":{"ids":["10478","10479","10145","10153","10153"],"boost":{"10145":{"HP":88,"ATK":19,"DEF":15,"storyLv":47,"power":1200},"10153":{"HP":88,"ATK":15,"DEF":10,"storyLv":47,"power":1108},"10478":{"HP":213,"ATK":31,"DEF":31,"storyLv":47,"power":7908},"10479":{"HP":227,"ATK":48,"DEF":25,"storyLv":47,"power":8876}}},"party":{"maxGrade":"HIGH RARE","forced":["10415"],"noMale":true,"mustLive":["10415"],"levels":{"10415":47}},"bossId":"10478","hero":"10415","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(9,7,'','{"no":7,"type":"normal","enemies":{"ids":["10475","10479","10478","10144","10145"],"boost":{"10144":{"HP":74,"ATK":18,"DEF":13,"storyLv":48,"power":1050},"10145":{"HP":88,"ATK":19,"DEF":15,"storyLv":48,"power":1200},"10475":{"HP":691,"ATK":127,"DEF":109,"storyLv":48,"power":63056},"10478":{"HP":215,"ATK":31,"DEF":31,"storyLv":48,"power":7953},"10479":{"HP":229,"ATK":48,"DEF":25,"storyLv":48,"power":8922}}},"party":{"maxGrade":"HIGH RARE","forced":["10415"],"noMale":true,"mustLive":["10415"],"levels":{"10415":48}},"bossId":"10475","hero":"10415","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(9,8,'','{"no":8,"type":"normal","enemies":{"ids":["10479","10478","10153","10154","10154"],"boost":{"10153":{"HP":89,"ATK":15,"DEF":10,"storyLv":50,"power":1115},"10154":{"HP":104,"ATK":16,"DEF":12,"storyLv":50,"power":1280},"10478":{"HP":220,"ATK":32,"DEF":32,"storyLv":50,"power":8166},"10479":{"HP":234,"ATK":50,"DEF":26,"storyLv":50,"power":9189}}},"party":{"maxGrade":"HIGH RARE","forced":["10415"],"noMale":true,"mustLive":["10415"],"levels":{"10415":50}},"bossId":"10479","hero":"10415","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(9,9,'','{"no":9,"type":"normal","enemies":{"ids":["10479","10478","10478","10155","10155"],"boost":{"10155":{"HP":120,"ATK":18,"DEF":14,"storyLv":51,"power":1471},"10478":{"HP":222,"ATK":32,"DEF":32,"storyLv":51,"power":8211},"10479":{"HP":236,"ATK":50,"DEF":26,"storyLv":51,"power":9234}}},"party":{"maxGrade":"HIGH RARE","forced":["10415"],"noMale":true,"mustLive":["10415"],"levels":{"10415":51}},"bossId":"10479","hero":"10415","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(9,10,'','{"no":10,"type":"normal","enemies":{"ids":["10480","10481","10479","10154","10154"],"boost":{"10154":{"HP":106,"ATK":17,"DEF":12,"storyLv":53,"power":1314},"10479":{"HP":241,"ATK":51,"DEF":27,"storyLv":53,"power":9447},"10480":{"HP":486,"ATK":64,"DEF":115,"storyLv":53,"power":27447},"10481":{"HP":481,"ATK":64,"DEF":64,"storyLv":53,"power":24070}}},"party":{"maxGrade":"HIGH RARE","forced":["10415"],"noMale":true,"mustLive":["10415"],"levels":{"10415":53}},"bossId":"10480","hero":"10415","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(9,11,'','{"no":11,"type":"normal","enemies":{"ids":["10481","10480","10479","10155","10155"],"boost":{"10155":{"HP":122,"ATK":18,"DEF":14,"storyLv":54,"power":1486},"10479":{"HP":243,"ATK":52,"DEF":27,"storyLv":54,"power":9546},"10480":{"HP":492,"ATK":65,"DEF":117,"storyLv":54,"power":27839},"10481":{"HP":487,"ATK":65,"DEF":65,"storyLv":54,"power":24398}}},"party":{"maxGrade":"HIGH RARE","forced":["10415"],"noMale":true,"mustLive":["10415"],"levels":{"10415":54}},"bossId":"10481","hero":"10415","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(9,12,'','{"no":12,"type":"normal","enemies":{"ids":["10475","10480","10481","10156","10156"],"boost":{"10156":{"HP":140,"ATK":20,"DEF":16,"storyLv":56,"power":1798},"10475":{"HP":768,"ATK":141,"DEF":122,"storyLv":56,"power":70152},"10480":{"HP":504,"ATK":66,"DEF":119,"storyLv":56,"power":28420},"10481":{"HP":498,"ATK":66,"DEF":66,"storyLv":56,"power":24884}}},"party":{"maxGrade":"HIGH RARE","forced":["10415"],"noMale":true,"mustLive":["10415"],"levels":{"10415":56}},"bossId":"10475","hero":"10415","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(9,13,'','{"no":13,"type":"normal","enemies":{"ids":["10485","10486","10479","10157","10157"],"boost":{"10157":{"HP":156,"ATK":22,"DEF":17,"storyLv":57,"power":1985},"10479":{"HP":250,"ATK":53,"DEF":28,"storyLv":57,"power":9804},"10485":{"HP":208,"ATK":45,"DEF":34,"storyLv":57,"power":7265},"10486":{"HP":235,"ATK":53,"DEF":38,"storyLv":57,"power":10484}}},"party":{"maxGrade":"HIGH RARE","forced":["10415"],"noMale":true,"mustLive":["10415"],"levels":{"10415":57}},"bossId":"10485","hero":"10415","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(9,14,'','{"no":14,"type":"normal","enemies":{"ids":["10480","10481","10475","10156","10157"],"boost":{"10156":{"HP":142,"ATK":21,"DEF":16,"storyLv":59,"power":1834},"10157":{"HP":158,"ATK":22,"DEF":17,"storyLv":59,"power":2001},"10475":{"HP":797,"ATK":146,"DEF":126,"storyLv":59,"power":72698},"10480":{"HP":521,"ATK":68,"DEF":123,"storyLv":59,"power":29360},"10481":{"HP":515,"ATK":68,"DEF":68,"storyLv":59,"power":25699}}},"party":{"maxGrade":"HIGH RARE","forced":["10414"],"exclude":["10415"],"mustLive":["10414"],"levels":{"10414":59}},"bossId":"10480","hero":"10415","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(9,15,'','{"no":15,"type":"normal","enemies":{"ids":["10482","10483","10484","10157","10157"],"boost":{"10157":{"HP":159,"ATK":22,"DEF":17,"storyLv":60,"power":2009},"10482":{"HP":554,"ATK":133,"DEF":111,"storyLv":60,"power":34119},"10483":{"HP":615,"ATK":125,"DEF":83,"storyLv":60,"power":32803},"10484":{"HP":665,"ATK":138,"DEF":69,"storyLv":60,"power":37416}}},"party":{"maxGrade":"HIGH RARE","forced":["10415"],"noMale":true,"mustLive":["10415"],"levels":{"10415":60}},"bossId":"10482","hero":"10415","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(9,16,'','{"no":16,"type":"normal","enemies":{"ids":["10483","10482","10484","10475","10157"],"boost":{"10157":{"HP":161,"ATK":23,"DEF":18,"storyLv":62,"power":2062},"10475":{"HP":826,"ATK":151,"DEF":131,"storyLv":62,"power":75347},"10482":{"HP":566,"ATK":136,"DEF":113,"storyLv":62,"power":34842},"10483":{"HP":628,"ATK":127,"DEF":85,"storyLv":62,"power":33464},"10484":{"HP":679,"ATK":142,"DEF":71,"storyLv":62,"power":38327}}},"party":{"maxGrade":"HIGH RARE","forced":["10415"],"noMale":true,"mustLive":["10415"],"levels":{"10415":62}},"bossId":"10483","hero":"10415","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(9,17,'','{"no":17,"type":"normal","enemies":{"ids":["10475","10482","10483","10484","10157"],"boost":{"10157":{"HP":162,"ATK":23,"DEF":18,"storyLv":63,"power":2070},"10475":{"HP":835,"ATK":153,"DEF":132,"storyLv":63,"power":76168},"10482":{"HP":572,"ATK":137,"DEF":114,"storyLv":63,"power":35166},"10483":{"HP":635,"ATK":129,"DEF":86,"storyLv":63,"power":33883},"10484":{"HP":686,"ATK":143,"DEF":72,"storyLv":63,"power":38703}}},"party":{"maxGrade":"HIGH RARE","forced":["10415"],"noMale":true,"mustLive":["10415"],"levels":{"10415":63}},"bossId":"10475","hero":"10415","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(9,18,'','{"no":18,"type":"boss","enemies":{"ids":["10475","10482","10483","10484","10480"],"boost":{"10475":{"HP":854,"ATK":157,"DEF":135,"storyLv":65,"power":77966},"10480":{"HP":555,"ATK":73,"DEF":131,"storyLv":65,"power":31317},"10482":{"HP":584,"ATK":140,"DEF":117,"storyLv":65,"power":35951},"10483":{"HP":648,"ATK":131,"DEF":88,"storyLv":65,"power":34545},"10484":{"HP":701,"ATK":146,"DEF":73,"storyLv":65,"power":39501}}},"party":{"maxGrade":"HIGH RARE","forced":["10415"],"noMale":true,"mustLive":["10415"],"levels":{"10415":65}},"bossId":"10475","hero":"10415","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(10,1,'','{"no":1,"type":"normal","enemies":{"ids":["10144","10145","10153","10153","10154"],"boost":{"10144":{"HP":72,"ATK":17,"DEF":13,"storyLv":45,"power":1018},"10145":{"HP":86,"ATK":19,"DEF":14,"storyLv":45,"power":1170},"10153":{"HP":86,"ATK":14,"DEF":10,"storyLv":45,"power":1074},"10154":{"HP":101,"ATK":16,"DEF":12,"storyLv":45,"power":1257}}},"party":{"forced":["10413"],"noMale":true,"mustLive":["10413"],"levels":{"10413":45},"maxGrade":"HIGH RARE"},"bossId":"10144","hero":"10413","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(10,2,'','{"no":2,"type":"normal","enemies":{"ids":["10145","10146","10154","10155","10155"],"boost":{"10145":{"HP":87,"ATK":19,"DEF":14,"storyLv":46,"power":1178},"10146":{"HP":102,"ATK":20,"DEF":16,"storyLv":46,"power":1400},"10154":{"HP":102,"ATK":16,"DEF":12,"storyLv":46,"power":1265},"10155":{"HP":116,"ATK":17,"DEF":13,"storyLv":46,"power":1406}}},"party":{"forced":["10413"],"noMale":true,"mustLive":["10413"],"levels":{"10413":46},"maxGrade":"HIGH RARE"},"bossId":"10145","hero":"10413","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(10,3,'','{"no":3,"type":"normal","enemies":{"ids":["10488","10146","10147","10155","10156"],"boost":{"10146":{"HP":103,"ATK":21,"DEF":16,"storyLv":48,"power":1426},"10147":{"HP":118,"ATK":22,"DEF":18,"storyLv":48,"power":1591},"10155":{"HP":118,"ATK":18,"DEF":13,"storyLv":48,"power":1440},"10156":{"HP":132,"ATK":19,"DEF":15,"storyLv":48,"power":1697},"10488":{"HP":1319,"ATK":196,"DEF":173,"storyLv":48,"power":116171}}},"party":{"forced":["10413"],"noMale":true,"mustLive":["10413"],"levels":{"10413":48},"maxGrade":"HIGH RARE"},"bossId":"10488","hero":"10413","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(10,4,'','{"no":4,"type":"normal","enemies":{"ids":["10147","10148","10156","10156","10157"],"boost":{"10147":{"HP":118,"ATK":22,"DEF":18,"storyLv":49,"power":1591},"10148":{"HP":176,"ATK":29,"DEF":20,"storyLv":49,"power":5495},"10156":{"HP":133,"ATK":19,"DEF":15,"storyLv":49,"power":1705},"10157":{"HP":148,"ATK":21,"DEF":16,"storyLv":49,"power":1884}}},"party":{"forced":["10414"],"exclude":["10413"],"mustLive":["10414"],"levels":{"10414":49},"maxGrade":"SUPER RARE"},"bossId":"10147","hero":"10413","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(10,5,'','{"no":5,"type":"normal","enemies":{"ids":["10480","10481","10148","10149","10157"],"boost":{"10148":{"HP":180,"ATK":30,"DEF":20,"storyLv":51,"power":5618},"10149":{"HP":220,"ATK":40,"DEF":30,"storyLv":51,"power":7686},"10157":{"HP":150,"ATK":21,"DEF":16,"storyLv":51,"power":1900},"10480":{"HP":475,"ATK":62,"DEF":112,"storyLv":51,"power":26759},"10481":{"HP":470,"ATK":62,"DEF":62,"storyLv":51,"power":23445}}},"party":{"forced":["10413"],"noMale":true,"mustLive":["10413"],"levels":{"10413":51},"maxGrade":"HIGH RARE"},"bossId":"10480","hero":"10413","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(10,6,'','{"no":6,"type":"normal","enemies":{"ids":["10481","10480","10149","10158","10158"],"boost":{"10149":{"HP":222,"ATK":40,"DEF":30,"storyLv":52,"power":7727},"10158":{"HP":151,"ATK":23,"DEF":23,"storyLv":52,"power":2062},"10480":{"HP":481,"ATK":63,"DEF":114,"storyLv":52,"power":27151},"10481":{"HP":476,"ATK":63,"DEF":63,"storyLv":52,"power":23773}}},"party":{"forced":["10413"],"noMale":true,"mustLive":["10413"],"levels":{"10413":52},"maxGrade":"HIGH RARE"},"bossId":"10481","hero":"10413","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(10,7,'','{"no":7,"type":"normal","enemies":{"ids":["10475","10158","10159","10149","10150"],"boost":{"10149":{"HP":227,"ATK":41,"DEF":31,"storyLv":54,"power":7919},"10150":{"HP":309,"ATK":62,"DEF":52,"storyLv":54,"power":11484},"10158":{"HP":153,"ATK":23,"DEF":23,"storyLv":54,"power":2078},"10159":{"HP":206,"ATK":41,"DEF":33,"storyLv":54,"power":7126},"10475":{"HP":749,"ATK":137,"DEF":119,"storyLv":54,"power":68355}}},"party":{"forced":["10413"],"noMale":true,"mustLive":["10413"],"levels":{"10413":54},"maxGrade":"HIGH RARE"},"bossId":"10475","hero":"10413","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(10,8,'','{"no":8,"type":"normal","enemies":{"ids":["10482","10150","10151","10159","10159"],"boost":{"10150":{"HP":312,"ATK":62,"DEF":52,"storyLv":55,"power":11546},"10151":{"HP":524,"ATK":79,"DEF":79,"storyLv":55,"power":28509},"10159":{"HP":208,"ATK":42,"DEF":33,"storyLv":55,"power":7211},"10482":{"HP":524,"ATK":126,"DEF":105,"storyLv":55,"power":32287}}},"party":{"forced":["10413"],"noMale":true,"mustLive":["10413"],"levels":{"10413":55},"maxGrade":"HIGH RARE"},"bossId":"10482","hero":"10413","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(10,9,'','{"no":9,"type":"normal","enemies":{"ids":["10480","10481","10151","10160","10160"],"boost":{"10151":{"HP":536,"ATK":80,"DEF":80,"storyLv":57,"power":29045},"10160":{"HP":254,"ATK":53,"DEF":45,"storyLv":57,"power":9066},"10480":{"HP":509,"ATK":67,"DEF":121,"storyLv":57,"power":28779},"10481":{"HP":504,"ATK":67,"DEF":67,"storyLv":57,"power":25213}}},"party":{"forced":["10413"],"noMale":true,"mustLive":["10413"],"levels":{"10413":57},"maxGrade":"HIGH RARE"},"bossId":"10480","hero":"10413","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(10,10,'','{"no":10,"type":"normal","enemies":{"ids":["10475","10160","10161","10152","10152"],"boost":{"10152":{"HP":623,"ATK":122,"DEF":122,"storyLv":58,"power":40167},"10160":{"HP":257,"ATK":53,"DEF":45,"storyLv":58,"power":9123},"10161":{"HP":278,"ATK":58,"DEF":49,"storyLv":58,"power":10532},"10475":{"HP":787,"ATK":144,"DEF":125,"storyLv":58,"power":71825}}},"party":{"forced":["10413"],"noMale":true,"mustLive":["10413"],"levels":{"10413":58},"maxGrade":"HIGH RARE"},"bossId":"10475","hero":"10413","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(10,11,'','{"no":11,"type":"normal","enemies":{"ids":["10152","10161","10162","10162","10163"],"boost":{"10152":{"HP":637,"ATK":125,"DEF":125,"storyLv":60,"power":41109},"10161":{"HP":283,"ATK":59,"DEF":50,"storyLv":60,"power":10724},"10162":{"HP":327,"ATK":65,"DEF":57,"storyLv":60,"power":12204},"10163":{"HP":499,"ATK":83,"DEF":72,"storyLv":60,"power":27547}}},"party":{"forced":["10413"],"noMale":true,"mustLive":["10413"],"levels":{"10413":60},"maxGrade":"HIGH RARE"},"bossId":"10152","hero":"10413","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(10,12,'','{"no":12,"type":"normal","enemies":{"ids":["10482","10483","10484","10143","10144"],"boost":{"10143":{"HP":80,"ATK":18,"DEF":13,"storyLv":61,"power":1094},"10144":{"HP":80,"ATK":19,"DEF":14,"storyLv":61,"power":1126},"10482":{"HP":560,"ATK":134,"DEF":112,"storyLv":61,"power":34443},"10483":{"HP":622,"ATK":126,"DEF":84,"storyLv":61,"power":33149},"10484":{"HP":672,"ATK":140,"DEF":70,"storyLv":61,"power":37871}}},"party":{"forced":["10413"],"noMale":true,"mustLive":["10413"],"levels":{"10413":61},"maxGrade":"HIGH RARE"},"bossId":"10482","hero":"10413","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb)
on conflict (chapter,phase,variant) do update set definition=excluded.definition;

insert into public.battle_story_defs_v2(chapter,phase,variant,definition) values
(10,13,'','{"no":13,"type":"normal","enemies":{"ids":["10501","10500","10500","10500","10500"],"boost":{"10500":{"HP":273,"ATK":60,"DEF":60,"storyLv":63,"power":11654},"10501":{"HP":603,"ATK":109,"DEF":109,"storyLv":63,"power":37593}}},"party":{"forced":["10415"],"noMale":true,"mustLive":["10415"],"levels":{"10415":63},"maxGrade":"HIGH RARE"},"bossId":"10501","hero":"10413","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(10,14,'','{"no":14,"type":"normal","enemies":{"ids":["10149","10149","10149","10149","10149"],"boost":{"10149":{"HP":251,"ATK":46,"DEF":34,"storyLv":65,"power":8778}}},"party":{"forced":["10415"],"noMale":true,"mustLive":["10415"],"levels":{"10415":63},"maxGrade":"HIGH RARE"},"bossId":"10149","hero":"10413","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(10,15,'','{"no":15,"type":"normal","enemies":{"ids":["10145","10146","10153","10153","10154"],"boost":{"10145":{"HP":98,"ATK":21,"DEF":16,"storyLv":65,"power":1323},"10146":{"HP":115,"ATK":23,"DEF":18,"storyLv":65,"power":1586},"10153":{"HP":98,"ATK":16,"DEF":11,"storyLv":65,"power":1219},"10154":{"HP":115,"ATK":18,"DEF":13,"storyLv":65,"power":1417}}},"party":{"forced":["10415"],"noMale":true,"mustLive":["10415"],"levels":{"10415":65},"maxGrade":"HIGH RARE"},"bossId":"10145","hero":"10413","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(10,16,'','{"no":16,"type":"normal","enemies":{"ids":["10490","10490","10490"],"boost":{"10490":{"HP":1440,"ATK":234,"DEF":234,"storyLv":66,"power":168731}}},"party":{"forced":[],"mustLive":[]},"bossId":"10490","hero":"10413","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(10,17,'','{"no":17,"type":"boss","enemies":{"ids":["10490"],"boost":{"10490":{"HP":1664,"ATK":270,"DEF":270,"storyLv":80,"power":194858}}},"party":{"forced":["10413"],"mustLive":["10413"],"levels":{"10413":70},"maxGrade":"SUPER RARE"},"bossId":"10490","bossCdMinus":1,"hero":"10413","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(11,1,'','{"no":1,"type":"normal","enemies":{"ids":["10491","10163","10163","10163","10163"],"boost":{"10163":{"HP":558,"ATK":93,"DEF":81,"storyLv":71,"power":30851},"10491":{"HP":1880,"ATK":263,"DEF":263,"storyLv":70,"power":211427}}},"party":{"forced":["10491"],"noMale":true,"mustLive":["10491"],"levels":{"10491":70}},"bossId":"10491","hero":"10491","tutorial":false,"single":true,"loan":["10491"],"loanLevel":{},"variantKind":"none"}'::jsonb),
(11,2,'','{"no":2,"type":"normal","enemies":{"ids":["10491","10164","10164","10164","10164"],"boost":{"10164":{"HP":589,"ATK":93,"DEF":81,"storyLv":71,"power":31865},"10491":{"HP":1900,"ATK":266,"DEF":266,"storyLv":71,"power":213738}}},"party":{"forced":["10491"],"noMale":true,"mustLive":["10491"],"levels":{"10491":71}},"bossId":"10491","hero":"10491","tutorial":false,"single":true,"loan":["10491"],"loanLevel":{},"variantKind":"none"}'::jsonb),
(11,3,'','{"no":3,"type":"normal","enemies":{"ids":["10491","10164","10164","10165","10165"],"boost":{"10164":{"HP":595,"ATK":94,"DEF":81,"storyLv":72,"power":32139},"10165":{"HP":626,"ATK":94,"DEF":94,"storyLv":72,"power":34004},"10491":{"HP":1920,"ATK":269,"DEF":269,"storyLv":72,"power":216049}}},"party":{"forced":["10491"],"noMale":true,"mustLive":["10491"],"levels":{"10491":72}},"bossId":"10491","hero":"10491","tutorial":false,"single":true,"loan":["10491"],"loanLevel":{},"variantKind":"none"}'::jsonb),
(11,4,'','{"no":4,"type":"normal","enemies":{"ids":["10490","10166","10166","10163","10164"],"boost":{"10163":{"HP":569,"ATK":95,"DEF":82,"storyLv":73,"power":31433},"10164":{"HP":600,"ATK":95,"DEF":82,"storyLv":73,"power":32447},"10166":{"HP":664,"ATK":111,"DEF":111,"storyLv":73,"power":37693},"10490":{"HP":1552,"ATK":252,"DEF":252,"storyLv":73,"power":181795}}},"party":{"forced":["10491","10490"],"noMale":true,"mustLive":["10491"],"levels":{"10490":73,"10491":73}},"bossId":"10490","hero":"10491","tutorial":false,"single":true,"loan":["10491"],"loanLevel":{},"variantKind":"none"}'::jsonb),
(11,5,'','{"no":5,"type":"normal","enemies":{"ids":["10491","10490"],"boost":{"10490":{"HP":1568,"ATK":255,"DEF":255,"storyLv":74,"power":183790},"10491":{"HP":1960,"ATK":274,"DEF":274,"storyLv":74,"power":220365}}},"party":{"forced":["10491","10490"],"noMale":true,"mustLive":["10490"],"levels":{"10490":74,"10491":74}},"bossId":"10491","hero":"10491","tutorial":false,"single":true,"loan":["10491"],"loanLevel":{},"variantKind":"none"}'::jsonb),
(11,6,'','{"no":6,"type":"normal","enemies":{"ids":["10475","10489","10482","10483","10484"],"boost":{"10475":{"HP":950,"ATK":174,"DEF":150,"storyLv":75,"power":86631},"10482":{"HP":644,"ATK":155,"DEF":129,"storyLv":75,"power":39689},"10483":{"HP":715,"ATK":145,"DEF":97,"storyLv":75,"power":38143},"10484":{"HP":773,"ATK":161,"DEF":80,"storyLv":75,"power":43526},"10489":{"HP":679,"ATK":129,"DEF":135,"storyLv":75,"power":44948}}},"party":{"forced":["10491"],"noMale":true,"mustLive":["10491"],"levels":{"10491":75}},"bossId":"10475","hero":"10491","tutorial":false,"single":true,"loan":["10491"],"loanLevel":{},"variantKind":"none"}'::jsonb),
(11,7,'','{"no":7,"type":"normal","enemies":{"ids":["10482","10483","10167","10168","10168"],"boost":{"10167":{"HP":748,"ATK":130,"DEF":130,"storyLv":76,"power":43175},"10168":{"HP":812,"ATK":146,"DEF":146,"storyLv":76,"power":50370},"10482":{"HP":650,"ATK":156,"DEF":130,"storyLv":76,"power":40013},"10483":{"HP":722,"ATK":146,"DEF":98,"storyLv":76,"power":38489}}},"party":{"forced":["10490"],"noMale":true,"mustLive":["10490"],"levels":{"10490":76,"10491":76}},"bossId":"10482","hero":"10491","tutorial":false,"single":true,"loan":["10491"],"loanLevel":{},"variantKind":"none"}'::jsonb),
(11,8,'','{"no":8,"type":"normal","enemies":{"ids":["10168","10166","10167","10163","10164"],"boost":{"10163":{"HP":590,"ATK":98,"DEF":85,"storyLv":77,"power":32552},"10164":{"HP":623,"ATK":98,"DEF":85,"storyLv":77,"power":33631},"10166":{"HP":689,"ATK":115,"DEF":115,"storyLv":77,"power":39087},"10167":{"HP":754,"ATK":131,"DEF":131,"storyLv":77,"power":43516},"10168":{"HP":820,"ATK":148,"DEF":148,"storyLv":77,"power":50952}}},"party":{"forced":["10491"],"noMale":true,"mustLive":["10491"],"levels":{"10491":77}},"bossId":"10168","hero":"10491","tutorial":false,"single":true,"loan":["10491"],"loanLevel":{},"variantKind":"none"}'::jsonb),
(11,9,'','{"no":9,"type":"normal","enemies":{"ids":["10165","10166","10167","10168","10163"],"boost":{"10163":{"HP":596,"ATK":99,"DEF":86,"storyLv":78,"power":32892},"10165":{"HP":662,"ATK":99,"DEF":99,"storyLv":78,"power":35901},"10166":{"HP":695,"ATK":116,"DEF":116,"storyLv":78,"power":39427},"10167":{"HP":761,"ATK":132,"DEF":132,"storyLv":78,"power":43889},"10168":{"HP":828,"ATK":149,"DEF":149,"storyLv":78,"power":51381}}},"party":{"forced":["10491"],"noMale":true,"mustLive":["10491"],"levels":{"10491":78}},"bossId":"10165","hero":"10491","tutorial":false,"single":true,"loan":["10491"],"loanLevel":{},"variantKind":"none"}'::jsonb),
(11,10,'','{"no":10,"type":"normal","enemies":{"ids":["10168","10166","10166","10166","10166"],"boost":{"10166":{"HP":701,"ATK":117,"DEF":117,"storyLv":79,"power":39767},"10168":{"HP":835,"ATK":150,"DEF":150,"storyLv":79,"power":51776}}},"party":{"forced":["10491"],"noMale":true,"mustLive":["10491"],"levels":{"10491":79}},"bossId":"10168","hero":"10491","tutorial":false,"single":true,"loan":["10491"],"loanLevel":{},"variantKind":"none"}'::jsonb),
(11,11,'','{"no":11,"type":"normal","enemies":{"ids":["10168","10166","10166","10166","10166"],"boost":{"10166":{"HP":708,"ATK":118,"DEF":118,"storyLv":80,"power":40140},"10168":{"HP":842,"ATK":152,"DEF":152,"storyLv":80,"power":52323}}},"party":{"forced":["10490"],"noMale":true,"mustLive":["10490"],"levels":{"10490":80,"10491":80}},"bossId":"10168","hero":"10491","tutorial":false,"single":true,"loan":["10491"],"loanLevel":{},"variantKind":"none"}'::jsonb),
(11,12,'','{"no":12,"type":"normal","enemies":{"ids":["10168","10166","10166","10166","10166"],"boost":{"10166":{"HP":714,"ATK":119,"DEF":119,"storyLv":81,"power":40480},"10168":{"HP":850,"ATK":153,"DEF":153,"storyLv":81,"power":52753}}},"party":{"forced":["10491"],"noMale":true,"mustLive":["10491"],"levels":{"10491":81}},"bossId":"10168","hero":"10491","tutorial":false,"single":true,"loan":["10491"],"loanLevel":{},"variantKind":"none"}'::jsonb),
(11,13,'','{"no":13,"type":"normal","enemies":{"ids":["10504"],"boost":{"10504":{"HP":2778,"ATK":278,"DEF":278,"storyLv":82,"power":442353}}},"party":{"forced":["10490"],"noMale":true,"mustLive":["10490"],"levels":{"10490":82,"10491":82}},"bossId":"10504","hero":"10491","tutorial":false,"single":true,"loan":["10491"],"loanLevel":{},"variantKind":"none"}'::jsonb),
(11,14,'','{"no":14,"type":"normal","enemies":{"ids":["10503"],"boost":{"10503":{"HP":2805,"ATK":280,"DEF":280,"storyLv":83,"power":438481}}},"party":{"forced":["10491"],"noMale":true,"mustLive":["10491"],"levels":{"10491":83}},"bossId":"10503","hero":"10491","tutorial":false,"single":true,"loan":["10491"],"loanLevel":{},"variantKind":"none"}'::jsonb),
(11,15,'','{"no":15,"type":"normal","enemies":{"ids":["10475","10489","10482","10483","10484"],"boost":{"10475":{"HP":1046,"ATK":192,"DEF":166,"storyLv":85,"power":95525},"10482":{"HP":704,"ATK":169,"DEF":141,"storyLv":85,"power":43353},"10483":{"HP":781,"ATK":158,"DEF":106,"storyLv":85,"power":41639},"10484":{"HP":845,"ATK":176,"DEF":88,"storyLv":85,"power":47616},"10489":{"HP":743,"ATK":141,"DEF":148,"storyLv":85,"power":49191}}},"party":{"forced":["10415"],"noMale":true,"maxGrade":"RARE","mustLive":["10415"],"levels":{"10415":85,"10491":85}},"bossId":"10475","joinAlly":{"id":"10311","afterTurn":1,"storyLevel":100,"battleLevel":10},"hero":"10491","tutorial":false,"single":true,"loan":["10491"],"loanLevel":{},"variantKind":"none"}'::jsonb),
(11,16,'','{"no":16,"type":"boss","enemies":{"ids":["10475","10489","10482","10483","10484"],"boost":{"10475":{"HP":1056,"ATK":194,"DEF":167,"storyLv":86,"power":96397},"10482":{"HP":710,"ATK":170,"DEF":142,"storyLv":86,"power":43677},"10483":{"HP":788,"ATK":160,"DEF":106,"storyLv":86,"power":41997},"10484":{"HP":852,"ATK":178,"DEF":89,"storyLv":86,"power":48072},"10489":{"HP":749,"ATK":142,"DEF":149,"storyLv":86,"power":49563}}},"party":{"forced":["10311"],"solo":true,"mustLive":["10311"],"levels":{"10311":86,"10491":86}},"bossId":"10475","hero":"10491","tutorial":false,"single":true,"loan":["10491"],"loanLevel":{},"variantKind":"none"}'::jsonb),
(12,1,'','{"no":1,"type":"normal","enemies":{"ids":["10153","10154","10155","10156","10157"],"boost":{"10153":{"HP":102,"ATK":17,"DEF":12,"storyLv":71,"power":1283},"10154":{"HP":119,"ATK":19,"DEF":14,"storyLv":71,"power":1482},"10155":{"HP":136,"ATK":20,"DEF":15,"storyLv":71,"power":1646},"10156":{"HP":153,"ATK":22,"DEF":17,"storyLv":71,"power":1960},"10157":{"HP":170,"ATK":24,"DEF":19,"storyLv":71,"power":2171}}},"party":{"forced":["10072"],"costBelow":35,"mustLive":["10072"],"levels":{"10072":71}},"bossId":"10153","hero":"10072","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(12,2,'','{"no":2,"type":"normal","enemies":{"ids":["10155","10156","10158","10158","10159"],"boost":{"10155":{"HP":137,"ATK":21,"DEF":15,"storyLv":72,"power":1673},"10156":{"HP":154,"ATK":22,"DEF":17,"storyLv":72,"power":1969},"10158":{"HP":171,"ATK":26,"DEF":26,"storyLv":72,"power":2333},"10159":{"HP":242,"ATK":48,"DEF":39,"storyLv":72,"power":8373}}},"party":{"forced":["10072"],"costBelow":35,"mustLive":["10072"],"levels":{"10072":72}},"bossId":"10155","hero":"10072","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(12,3,'','{"no":3,"type":"normal","enemies":{"ids":["10159","10160","10161","10153","10153"],"boost":{"10153":{"HP":103,"ATK":17,"DEF":12,"storyLv":73,"power":1291},"10159":{"HP":244,"ATK":49,"DEF":39,"storyLv":73,"power":8458},"10160":{"HP":293,"ATK":61,"DEF":51,"storyLv":73,"power":10416},"10161":{"HP":317,"ATK":66,"DEF":56,"storyLv":73,"power":12008}}},"party":{"forced":["10072"],"costBelow":35,"mustLive":["10072"],"levels":{"10072":73}},"bossId":"10159","hero":"10072","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(12,4,'','{"no":4,"type":"normal","enemies":{"ids":["10160","10161","10162","10154","10155"],"boost":{"10154":{"HP":121,"ATK":19,"DEF":14,"storyLv":74,"power":1497},"10155":{"HP":138,"ATK":21,"DEF":16,"storyLv":74,"power":1696},"10160":{"HP":295,"ATK":62,"DEF":52,"storyLv":74,"power":10540},"10161":{"HP":320,"ATK":66,"DEF":57,"storyLv":74,"power":12110},"10162":{"HP":369,"ATK":74,"DEF":64,"storyLv":74,"power":13790}}},"party":{"forced":["10072"],"costBelow":35,"mustLive":["10072"],"levels":{"10072":74}},"bossId":"10160","hero":"10072","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(12,5,'','{"no":5,"type":"normal","enemies":{"ids":["10300","10161","10162","10163","10163"],"boost":{"10161":{"HP":322,"ATK":67,"DEF":57,"storyLv":75,"power":12200},"10162":{"HP":372,"ATK":74,"DEF":64,"storyLv":75,"power":13852},"10163":{"HP":580,"ATK":97,"DEF":84,"storyLv":75,"power":32081},"10300":{"HP":310,"ATK":62,"DEF":62,"storyLv":75,"power":12407}}},"party":{"forced":["10072"],"costBelow":40,"mustLive":["10072"],"levels":{"10072":75}},"bossId":"10300","hero":"10072","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(12,6,'','{"no":6,"type":"normal","enemies":{"ids":["10162","10163","10164","10164","10165"],"boost":{"10162":{"HP":375,"ATK":75,"DEF":65,"storyLv":76,"power":14003},"10163":{"HP":585,"ATK":98,"DEF":84,"storyLv":76,"power":32323},"10164":{"HP":618,"ATK":98,"DEF":84,"storyLv":76,"power":33402},"10165":{"HP":650,"ATK":98,"DEF":98,"storyLv":76,"power":35365}}},"party":{"forced":["10072"],"costBelow":45,"mustLive":["10072"],"levels":{"10072":76}},"bossId":"10162","hero":"10072","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(12,7,'','{"no":7,"type":"normal","enemies":{"ids":["10165","10166","10166","10153","10154"],"boost":{"10153":{"HP":106,"ATK":18,"DEF":12,"storyLv":77,"power":1332},"10154":{"HP":123,"ATK":19,"DEF":14,"storyLv":77,"power":1513},"10165":{"HP":656,"ATK":98,"DEF":98,"storyLv":77,"power":35561},"10166":{"HP":689,"ATK":115,"DEF":115,"storyLv":77,"power":39087}}},"party":{"forced":["10505"],"maxGrade":"HIGH RARE","mustLive":["10505"],"levels":{"10505":77}},"bossId":"10165","hero":"10072","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(12,8,'','{"no":8,"type":"normal","enemies":{"ids":["10166","10167","10167","10155","10156"],"boost":{"10155":{"HP":142,"ATK":21,"DEF":16,"storyLv":78,"power":1727},"10156":{"HP":159,"ATK":23,"DEF":18,"storyLv":78,"power":2045},"10166":{"HP":695,"ATK":116,"DEF":116,"storyLv":78,"power":39427},"10167":{"HP":761,"ATK":132,"DEF":132,"storyLv":78,"power":43889}}},"party":{"forced":["10505"],"maxGrade":"HIGH RARE","mustLive":["10505"],"levels":{"10505":78}},"bossId":"10166","hero":"10072","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(12,9,'','{"no":9,"type":"normal","enemies":{"ids":["10167","10168","10168","10157","10158"],"boost":{"10157":{"HP":178,"ATK":25,"DEF":20,"storyLv":79,"power":2273},"10158":{"HP":178,"ATK":27,"DEF":27,"storyLv":79,"power":2427},"10167":{"HP":768,"ATK":134,"DEF":134,"storyLv":79,"power":44405},"10168":{"HP":835,"ATK":150,"DEF":150,"storyLv":79,"power":51776}}},"party":{"forced":["10505"],"costBelow":45,"mustLive":["10505"],"levels":{"10505":79}},"bossId":"10167","hero":"10072","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb)
on conflict (chapter,phase,variant) do update set definition=excluded.definition;

insert into public.battle_story_defs_v2(chapter,phase,variant,definition) values
(12,10,'','{"no":10,"type":"normal","enemies":{"ids":["10505","10168","10168","10153","10154"],"boost":{"10153":{"HP":107,"ATK":18,"DEF":13,"storyLv":80,"power":1356},"10154":{"HP":125,"ATK":20,"DEF":14,"storyLv":80,"power":1546},"10168":{"HP":842,"ATK":152,"DEF":152,"storyLv":80,"power":52323},"10505":{"HP":708,"ATK":135,"DEF":125,"storyLv":80,"power":47151}}},"party":{"forced":["10072"],"costBelow":45,"mustLive":["10072"],"levels":{"10072":80}},"bossId":"10505","hero":"10072","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(12,11,'','{"no":11,"type":"normal","enemies":{"ids":["10153","10155","10156","10157","10158"],"boost":{"10153":{"HP":108,"ATK":18,"DEF":13,"storyLv":81,"power":1363},"10155":{"HP":144,"ATK":22,"DEF":16,"storyLv":81,"power":1760},"10156":{"HP":162,"ATK":23,"DEF":18,"storyLv":81,"power":2070},"10157":{"HP":180,"ATK":25,"DEF":20,"storyLv":81,"power":2289},"10158":{"HP":180,"ATK":27,"DEF":27,"storyLv":81,"power":2443}}},"party":{"forced":["10072"],"costBelow":45,"mustLive":["10072"],"levels":{"10072":81}},"bossId":"10153","hero":"10072","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(12,12,'','{"no":12,"type":"normal","enemies":{"ids":["10506","10507","10159","10160","10161"],"boost":{"10159":{"HP":262,"ATK":52,"DEF":42,"storyLv":82,"power":9058},"10160":{"HP":314,"ATK":66,"DEF":55,"storyLv":82,"power":11205},"10161":{"HP":341,"ATK":71,"DEF":60,"storyLv":82,"power":12907},"10506":{"HP":617,"ATK":113,"DEF":144,"storyLv":82,"power":44487},"10507":{"HP":720,"ATK":144,"DEF":117,"storyLv":82,"power":48414}}},"party":{"forced":["10072"],"maxGrade":"SUPER RARE","mustLive":["10072"],"levels":{"10072":82}},"bossId":"10506","hero":"10072","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(12,13,'','{"no":13,"type":"normal","enemies":{"ids":["10229","10153","10154","10155","10156"],"boost":{"10153":{"HP":109,"ATK":18,"DEF":13,"storyLv":83,"power":1371},"10154":{"HP":127,"ATK":20,"DEF":15,"storyLv":83,"power":1577},"10155":{"HP":146,"ATK":22,"DEF":16,"storyLv":83,"power":1776},"10156":{"HP":164,"ATK":24,"DEF":18,"storyLv":83,"power":2106},"10229":{"HP":761,"ATK":138,"DEF":121,"storyLv":83,"power":60641}}},"party":{"forced":["10072"],"maxGrade":"SUPER RARE","mustLive":["10072"],"levels":{"10072":83}},"bossId":"10229","rules":{"maxTurns":6},"hero":"10072","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(12,14,'','{"no":14,"type":"normal","enemies":{"ids":["10325"],"boost":{"10325":{"HP":2832,"ATK":360,"DEF":360,"storyLv":84,"power":332457}}},"party":{"forced":["10229"],"noMale":true,"maxGrade":"SUPER RARE","mustLive":["10229"],"levels":{"10229":84}},"bossId":"10325","loseClears":true,"hero":"10072","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(12,15,'','{"no":15,"type":"normal","enemies":{"ids":["10508","10506","10507","10256","10462"],"boost":{"10256":{"HP":295,"ATK":54,"DEF":80,"storyLv":85,"power":14426},"10462":{"HP":268,"ATK":40,"DEF":40,"storyLv":85,"power":8085},"10506":{"HP":634,"ATK":116,"DEF":148,"storyLv":85,"power":45705},"10507":{"HP":739,"ATK":148,"DEF":120,"storyLv":85,"power":49703},"10508":{"HP":1526,"ATK":218,"DEF":196,"storyLv":85,"power":169010}}},"party":{"forced":["10072"],"noMale":true,"maxGrade":"SUPER RARE","mustLive":["10072"],"levels":{"10072":85}},"bossId":"10508","hero":"10072","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(12,16,'','{"no":16,"type":"normal","enemies":{"ids":["10163","10164","10165","10143","10144"],"boost":{"10143":{"HP":92,"ATK":20,"DEF":15,"storyLv":86,"power":1247},"10144":{"HP":92,"ATK":22,"DEF":17,"storyLv":86,"power":1311},"10163":{"HP":639,"ATK":106,"DEF":92,"storyLv":86,"power":35240},"10164":{"HP":674,"ATK":106,"DEF":92,"storyLv":86,"power":36385},"10165":{"HP":710,"ATK":106,"DEF":106,"storyLv":86,"power":38478}}},"party":{"forced":["10072"],"noMale":true,"maxGrade":"HIGH RARE","mustLive":["10072"],"levels":{"10072":86}},"bossId":"10163","hero":"10072","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(12,17,'','{"no":17,"type":"normal","enemies":{"ids":["10506","10507","10256","10462"],"boost":{"10256":{"HP":299,"ATK":54,"DEF":82,"storyLv":87,"power":14624},"10462":{"HP":272,"ATK":41,"DEF":41,"storyLv":87,"power":8238},"10506":{"HP":644,"ATK":118,"DEF":150,"storyLv":87,"power":46416},"10507":{"HP":752,"ATK":150,"DEF":122,"storyLv":87,"power":50515}}},"party":{"forced":["10072"],"noMale":true,"maxGrade":"SUPER RARE","mustLive":["10072"],"levels":{"10072":87}},"bossId":"10506","hero":"10072","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(12,18,'','{"no":18,"type":"normal","enemies":{"ids":["10325","10506","10507","10256","10462"],"boost":{"10256":{"HP":301,"ATK":55,"DEF":82,"storyLv":88,"power":14732},"10325":{"HP":2942,"ATK":374,"DEF":374,"storyLv":88,"power":345376},"10462":{"HP":274,"ATK":41,"DEF":41,"storyLv":88,"power":8274},"10506":{"HP":650,"ATK":119,"DEF":152,"storyLv":88,"power":46885},"10507":{"HP":758,"ATK":152,"DEF":123,"storyLv":88,"power":50992}}},"party":{"forced":["10072"],"noMale":true,"maxGrade":"SUPER RARE","mustLive":["10072"],"levels":{"10072":88}},"bossId":"10325","rules":{"survive":5},"hero":"10072","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(12,19,'','{"no":19,"type":"normal","enemies":{"ids":["10325","10506","10507","10256","10462"],"boost":{"10256":{"HP":304,"ATK":55,"DEF":83,"storyLv":89,"power":14856},"10325":{"HP":2970,"ATK":378,"DEF":378,"storyLv":89,"power":348809},"10462":{"HP":276,"ATK":41,"DEF":41,"storyLv":89,"power":8310},"10506":{"HP":655,"ATK":120,"DEF":153,"storyLv":89,"power":47241},"10507":{"HP":764,"ATK":153,"DEF":124,"storyLv":89,"power":51379}}},"party":{"forced":["10072"],"noMale":true,"maxGrade":"SUPER RARE","mustLive":["10072"],"levels":{"10072":89}},"bossId":"10325","rules":{"survive":7},"hero":"10072","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(12,20,'','{"no":20,"type":"normal","enemies":{"ids":["10302"],"boost":{"10302":{"HP":639,"ATK":125,"DEF":125,"storyLv":90,"power":26766}}},"party":{"forced":["10072"],"maxGrade":"SUPER RARE","mustLive":["10072"],"levels":{"10072":90}},"bossId":"10302","rules":{"blind":{"10072":0.4},"survive":10},"hero":"10072","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(12,21,'','{"no":21,"type":"normal","enemies":{"ids":["10300","10256","10462"],"boost":{"10256":{"HP":308,"ATK":56,"DEF":84,"storyLv":91,"power":15063},"10300":{"HP":350,"ATK":70,"DEF":70,"storyLv":91,"power":14008},"10462":{"HP":280,"ATK":42,"DEF":42,"storyLv":91,"power":8463}}},"party":{"forced":["10072"],"mustLive":["10072"],"levels":{"10072":91}},"bossId":"10300","hero":"10072","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(13,1,'','{"no":1,"type":"normal","enemies":{"ids":["10143","10144","10145"],"boost":{"10143":{"HP":86,"ATK":19,"DEF":14,"storyLv":72,"power":1170},"10144":{"HP":86,"ATK":21,"DEF":15,"storyLv":72,"power":1220},"10145":{"HP":103,"ATK":22,"DEF":17,"storyLv":72,"power":1392}}},"party":{"forced":["10229"],"mustLive":["10229"],"levels":{"10229":72}},"bossId":"10143","mana":50,"starTurns":6,"starMana":0.3,"hero":"10229","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(13,2,'','{"no":2,"type":"normal","enemies":{"ids":["10148","10149","10150"],"boost":{"10148":{"HP":220,"ATK":37,"DEF":24,"storyLv":73,"power":6865},"10149":{"HP":268,"ATK":49,"DEF":37,"storyLv":73,"power":9395},"10150":{"HP":366,"ATK":73,"DEF":61,"storyLv":73,"power":13557}}},"party":{"forced":["10229"],"mustLive":["10229"],"levels":{"10229":73}},"bossId":"10148","mana":50,"starTurns":6,"starMana":0.3,"hero":"10229","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(13,3,'','{"no":3,"type":"normal","enemies":{"ids":["10153","10154","10155"],"boost":{"10153":{"HP":104,"ATK":17,"DEF":12,"storyLv":74,"power":1299},"10154":{"HP":121,"ATK":19,"DEF":14,"storyLv":74,"power":1497},"10155":{"HP":138,"ATK":21,"DEF":16,"storyLv":74,"power":1696}}},"party":{"forced":["10229"],"mustLive":["10229"],"levels":{"10229":74}},"bossId":"10153","mana":50,"starTurns":6,"starMana":0.3,"hero":"10229","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(13,4,'','{"no":4,"type":"normal","enemies":{"ids":["10158","10159","10160","10161","10162"],"boost":{"10158":{"HP":174,"ATK":26,"DEF":26,"storyLv":75,"power":2358},"10159":{"HP":248,"ATK":50,"DEF":40,"storyLv":75,"power":8619},"10160":{"HP":298,"ATK":62,"DEF":52,"storyLv":75,"power":10597},"10161":{"HP":322,"ATK":67,"DEF":57,"storyLv":75,"power":12200},"10162":{"HP":372,"ATK":74,"DEF":64,"storyLv":75,"power":13852}}},"party":{"forced":["10229"],"mustLive":["10229"],"levels":{"10229":75}},"bossId":"10158","mana":50,"starTurns":8,"starMana":0.25,"hero":"10229","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(13,5,'','{"no":5,"type":"normal","enemies":{"ids":["10143","10144","10145","10163","10164"],"boost":{"10143":{"HP":88,"ATK":19,"DEF":14,"storyLv":76,"power":1185},"10144":{"HP":88,"ATK":21,"DEF":16,"storyLv":76,"power":1249},"10145":{"HP":105,"ATK":23,"DEF":18,"storyLv":76,"power":1439},"10163":{"HP":585,"ATK":98,"DEF":84,"storyLv":76,"power":32323},"10164":{"HP":618,"ATK":98,"DEF":84,"storyLv":76,"power":33402}}},"party":{"forced":["10229"],"mustLive":["10229"],"levels":{"10229":76}},"bossId":"10143","mana":67,"starTurns":8,"starMana":0.3,"hero":"10229","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(13,6,'','{"no":6,"type":"normal","enemies":{"ids":["10509"],"boost":{"10509":{"HP":689,"ATK":125,"DEF":118,"storyLv":77,"power":55174}}},"party":{"forced":["10229"],"mustLive":["10229"],"levels":{"10229":77}},"bossId":"10509","mana":34,"starTurns":4,"starMana":0,"hero":"10229","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(13,7,'','{"no":7,"type":"normal","enemies":{"ids":["10148","10149","10150"],"boost":{"10148":{"HP":229,"ATK":38,"DEF":25,"storyLv":78,"power":7122},"10149":{"HP":279,"ATK":51,"DEF":38,"storyLv":78,"power":9759},"10150":{"HP":381,"ATK":76,"DEF":64,"storyLv":78,"power":14134}}},"party":{"forced":["10229"],"mustLive":["10229"],"levels":{"10229":78}},"bossId":"10148","mana":50,"starTurns":6,"starMana":0.3,"hero":"10229","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(13,8,'','{"no":8,"type":"normal","enemies":{"ids":["10153","10154","10155"],"boost":{"10153":{"HP":107,"ATK":18,"DEF":12,"storyLv":79,"power":1340},"10154":{"HP":125,"ATK":20,"DEF":14,"storyLv":79,"power":1546},"10155":{"HP":142,"ATK":21,"DEF":16,"storyLv":79,"power":1727}}},"party":{"forced":["10229"],"mustLive":["10229"],"levels":{"10229":79}},"bossId":"10153","mana":50,"starTurns":6,"starMana":0.3,"hero":"10229","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(13,9,'','{"no":9,"type":"normal","enemies":{"ids":["10163","10164","10165"],"boost":{"10163":{"HP":607,"ATK":101,"DEF":88,"storyLv":80,"power":33539},"10164":{"HP":640,"ATK":101,"DEF":88,"storyLv":80,"power":34619},"10165":{"HP":674,"ATK":101,"DEF":101,"storyLv":80,"power":36581}}},"party":{"forced":["10229"],"mustLive":["10229"],"levels":{"10229":80}},"bossId":"10163","mana":50,"starTurns":8,"starMana":0.2,"hero":"10229","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(13,10,'','{"no":10,"type":"normal","enemies":{"ids":["10144","10145","10146"],"boost":{"10144":{"HP":90,"ATK":22,"DEF":16,"storyLv":81,"power":1282},"10145":{"HP":108,"ATK":23,"DEF":18,"storyLv":81,"power":1461},"10146":{"HP":126,"ATK":25,"DEF":20,"storyLv":81,"power":1739}}},"party":{"forced":["10229"],"mustLive":["10229"],"levels":{"10229":81}},"bossId":"10144","mana":50,"starTurns":6,"starMana":0.3,"hero":"10229","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(13,11,'','{"no":11,"type":"normal","enemies":{"ids":["10149","10150","10151"],"boost":{"10149":{"HP":288,"ATK":52,"DEF":39,"storyLv":82,"power":10033},"10150":{"HP":393,"ATK":79,"DEF":66,"storyLv":82,"power":14608},"10151":{"HP":686,"ATK":103,"DEF":103,"storyLv":82,"power":37262}}},"party":{"forced":["10229"],"mustLive":["10229"],"levels":{"10229":82}},"bossId":"10149","mana":50,"starTurns":7,"starMana":0.25,"hero":"10229","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(13,12,'','{"no":12,"type":"normal","enemies":{"ids":["10158","10159","10160","10161","10162"],"boost":{"10158":{"HP":182,"ATK":27,"DEF":27,"storyLv":83,"power":2459},"10159":{"HP":264,"ATK":53,"DEF":42,"storyLv":83,"power":9143},"10160":{"HP":317,"ATK":66,"DEF":55,"storyLv":83,"power":11263},"10161":{"HP":343,"ATK":71,"DEF":61,"storyLv":83,"power":12989},"10162":{"HP":396,"ATK":79,"DEF":69,"storyLv":83,"power":14792}}},"party":{"forced":["10229"],"mustLive":["10229"],"levels":{"10229":83}},"bossId":"10158","mana":80,"starTurns":8,"starMana":0.3,"hero":"10229","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(13,13,'','{"no":13,"type":"normal","enemies":{"ids":["10256","10462","10072","10153","10154"],"boost":{"10072":{"HP":698,"ATK":73,"DEF":154,"storyLv":84,"power":36990},"10153":{"HP":110,"ATK":18,"DEF":13,"storyLv":84,"power":1379},"10154":{"HP":128,"ATK":20,"DEF":15,"storyLv":84,"power":1585},"10256":{"HP":293,"ATK":53,"DEF":80,"storyLv":84,"power":14318},"10462":{"HP":266,"ATK":40,"DEF":40,"storyLv":84,"power":8048}}},"party":{"forced":["10229"],"mustLive":["10229"],"levels":{"10229":84}},"bossId":"10256","mana":80,"starTurns":9,"starMana":0.25,"hero":"10229","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(13,14,'','{"no":14,"type":"normal","enemies":{"ids":["10325"],"boost":{"10325":{"HP":2860,"ATK":364,"DEF":364,"storyLv":85,"power":335890}}},"party":{"forced":["10229"],"mustLive":["10229"],"levels":{"10229":85}},"bossId":"10325","mana":100,"starTurns":3,"starMana":0.3,"rules":{"survive":3,"aiScript":[{"turn":1,"unit":"10325","say":["한 번 때려보세요. 헤헤"],"end":true},{"turn":2,"unit":"10325","say":["너무 느린데.. 정말 격투가 맞나요?"],"end":true},{"turn":3,"unit":"10325","skill":"아름다운 고통의 키스","end":true}]},"hero":"10229","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(13,15,'','{"no":15,"type":"normal","enemies":{"ids":["10325"],"boost":{"10325":{"HP":2860,"ATK":364,"DEF":364,"storyLv":85,"power":335890}}},"party":{"forced":["10229"],"mustLive":["10229"],"levels":{"10229":85}},"bossId":"10325","mana":34,"starTurns":1,"starMana":0,"rules":{"survive":1},"hero":"10229","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(14,1,'','{"no":1,"type":"normal","enemies":{"ids":["10143","10144","10145","10146","10147"],"boost":{"10143":{"HP":86,"ATK":19,"DEF":14,"storyLv":74,"power":1170},"10144":{"HP":86,"ATK":21,"DEF":16,"storyLv":74,"power":1235},"10145":{"HP":104,"ATK":22,"DEF":17,"storyLv":74,"power":1399},"10146":{"HP":121,"ATK":24,"DEF":19,"storyLv":74,"power":1667},"10147":{"HP":138,"ATK":26,"DEF":21,"storyLv":74,"power":1865}}},"party":{"forced":["10317"],"costBelow":41,"mustLive":["10317"],"levels":{"10317":74}},"bossId":"10143","mana":80,"starTurns":6,"starMana":0.3,"hero":"10317","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(14,2,'','{"no":2,"type":"normal","enemies":{"ids":["10148","10149","10153","10154","10155"],"boost":{"10148":{"HP":223,"ATK":37,"DEF":25,"storyLv":75,"power":6961},"10149":{"HP":273,"ATK":50,"DEF":37,"storyLv":75,"power":9546},"10153":{"HP":104,"ATK":17,"DEF":12,"storyLv":75,"power":1299},"10154":{"HP":122,"ATK":19,"DEF":14,"storyLv":75,"power":1505},"10155":{"HP":139,"ATK":21,"DEF":16,"storyLv":75,"power":1703}}},"party":{"forced":["10317"],"costBelow":41,"mustLive":["10317"],"levels":{"10317":75}},"bossId":"10148","mana":80,"starTurns":8,"starMana":0.3,"hero":"10317","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(14,3,'','{"no":3,"type":"normal","enemies":{"ids":["10017","10015","10150","10156","10157"],"boost":{"10015":{"HP":682,"ATK":130,"DEF":75,"storyLv":76,"power":49179},"10017":{"HP":650,"ATK":130,"DEF":81,"storyLv":76,"power":41502},"10150":{"HP":375,"ATK":75,"DEF":62,"storyLv":76,"power":13880},"10156":{"HP":158,"ATK":23,"DEF":18,"storyLv":76,"power":2037},"10157":{"HP":175,"ATK":24,"DEF":19,"storyLv":76,"power":2212}}},"party":{"forced":["10317"],"noFemale":true,"mustLive":["10317"],"levels":{"10317":76}},"bossId":"10017","mana":80,"starTurns":9,"starMana":0.25,"hero":"10317","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb)
on conflict (chapter,phase,variant) do update set definition=excluded.definition;

insert into public.battle_story_defs_v2(chapter,phase,variant,definition) values
(14,4,'','{"no":4,"type":"normal","enemies":{"ids":["10158","10159","10160","10151","10152"],"boost":{"10151":{"HP":656,"ATK":98,"DEF":98,"storyLv":77,"power":35561},"10152":{"HP":754,"ATK":148,"DEF":148,"storyLv":77,"power":48666},"10158":{"HP":176,"ATK":26,"DEF":26,"storyLv":77,"power":2374},"10159":{"HP":252,"ATK":50,"DEF":40,"storyLv":77,"power":8696},"10160":{"HP":302,"ATK":63,"DEF":53,"storyLv":77,"power":10759}}},"party":{"forced":["10317"],"costBelow":35,"mustLive":["10317"],"levels":{"10317":77}},"bossId":"10158","mana":80,"starTurns":9,"starMana":0.25,"hero":"10317","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(14,5,'','{"no":5,"type":"normal","enemies":{"ids":["10181","10423","10287","10136","10161"],"boost":{"10136":{"HP":655,"ATK":126,"DEF":126,"storyLv":78,"power":36978},"10161":{"HP":330,"ATK":69,"DEF":58,"storyLv":78,"power":12503},"10181":{"HP":1142,"ATK":184,"DEF":155,"storyLv":78,"power":105255},"10287":{"HP":282,"ATK":64,"DEF":46,"storyLv":78,"power":11032},"10423":{"HP":124,"ATK":21,"DEF":14,"storyLv":78,"power":1526}}},"party":{"forced":["10317"],"exclude":["10312"],"mustLive":["10317"],"levels":{"10317":78}},"bossId":"10181","mana":80,"starTurns":2,"starMana":0,"rules":{"survive":2},"hero":"10317","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(14,6,'','{"no":6,"type":"normal","enemies":{"ids":["10181","10423","10287","10136","10161"],"boost":{"10136":{"HP":655,"ATK":126,"DEF":126,"storyLv":78,"power":36978},"10161":{"HP":330,"ATK":69,"DEF":58,"storyLv":78,"power":12503},"10181":{"HP":1142,"ATK":184,"DEF":155,"storyLv":78,"power":105255},"10287":{"HP":282,"ATK":64,"DEF":46,"storyLv":78,"power":11032},"10423":{"HP":124,"ATK":21,"DEF":14,"storyLv":78,"power":1526}}},"party":{"forced":["10317"],"maxGrade":"SUPER RARE","mustLive":["10317"],"levels":{"10317":78}},"bossId":"10181","mana":80,"starTurns":10,"starMana":0.2,"hero":"10317","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(14,7,'','{"no":7,"type":"normal","enemies":{"ids":["10182","10136","10162","10163","10164"],"boost":{"10136":{"HP":661,"ATK":127,"DEF":127,"storyLv":79,"power":37296},"10162":{"HP":384,"ATK":77,"DEF":67,"storyLv":79,"power":14367},"10163":{"HP":601,"ATK":100,"DEF":87,"storyLv":79,"power":33199},"10164":{"HP":635,"ATK":100,"DEF":87,"storyLv":79,"power":34311},"10182":{"HP":307,"ATK":41,"DEF":38,"storyLv":79,"power":9366}}},"party":{"forced":["10060"],"solo":true,"mustLive":["10060"],"levels":{"10060":79}},"bossId":"10182","mana":89,"starTurns":4,"starMana":0.3,"hero":"10317","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(14,8,'','{"no":8,"type":"normal","enemies":{"ids":["10153","10154","10155","10167","10168"],"boost":{"10153":{"HP":107,"ATK":18,"DEF":13,"storyLv":80,"power":1356},"10154":{"HP":125,"ATK":20,"DEF":14,"storyLv":80,"power":1546},"10155":{"HP":143,"ATK":21,"DEF":16,"storyLv":80,"power":1734},"10167":{"HP":775,"ATK":135,"DEF":135,"storyLv":80,"power":44778},"10168":{"HP":842,"ATK":152,"DEF":152,"storyLv":80,"power":52323}}},"party":{"forced":["10312"],"solo":true,"mustLive":["10312"],"levels":{"10312":80}},"bossId":"10153","mana":67,"starTurns":7,"starMana":0.3,"hero":"10317","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(14,9,'','{"no":9,"type":"normal","enemies":{"ids":["10433","10156","10157","10158","10159"],"boost":{"10156":{"HP":162,"ATK":23,"DEF":18,"storyLv":81,"power":2070},"10157":{"HP":180,"ATK":25,"DEF":20,"storyLv":81,"power":2289},"10158":{"HP":180,"ATK":27,"DEF":27,"storyLv":81,"power":2443},"10159":{"HP":260,"ATK":52,"DEF":42,"storyLv":81,"power":9020},"10433":{"HP":731,"ATK":129,"DEF":82,"storyLv":81,"power":36255}}},"party":{"forced":["10312"],"solo":true,"mustLive":["10312"],"levels":{"10312":81}},"bossId":"10433","mana":67,"starTurns":9,"starMana":0.3,"hero":"10317","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(14,10,'','{"no":10,"type":"normal","enemies":{"ids":["10143","10144","10145","10161","10162"],"boost":{"10143":{"HP":90,"ATK":20,"DEF":14,"storyLv":82,"power":1217},"10144":{"HP":90,"ATK":22,"DEF":16,"storyLv":82,"power":1282},"10145":{"HP":109,"ATK":24,"DEF":18,"storyLv":82,"power":1486},"10161":{"HP":341,"ATK":71,"DEF":60,"storyLv":82,"power":12907},"10162":{"HP":393,"ATK":79,"DEF":68,"storyLv":82,"power":14690}}},"party":{"forced":["10312"],"solo":true,"mustLive":["10312"],"levels":{"10312":82}},"bossId":"10143","mana":67,"starTurns":9,"starMana":0.3,"hero":"10317","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(14,11,'','{"no":11,"type":"normal","enemies":{"ids":["10163","10164","10165","10166","10167"],"boost":{"10163":{"HP":623,"ATK":104,"DEF":90,"storyLv":83,"power":34429},"10164":{"HP":657,"ATK":104,"DEF":90,"storyLv":83,"power":35541},"10165":{"HP":692,"ATK":104,"DEF":104,"storyLv":83,"power":37602},"10166":{"HP":727,"ATK":121,"DEF":121,"storyLv":83,"power":41193},"10167":{"HP":796,"ATK":138,"DEF":138,"storyLv":83,"power":45897}}},"party":{"forced":["10312"],"solo":true,"mustLive":["10312"],"levels":{"10312":83}},"bossId":"10163","mana":67,"starTurns":7,"starMana":0.3,"hero":"10317","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(14,12,'','{"no":12,"type":"normal","enemies":{"ids":["10146","10147","10148","10163","10164"],"boost":{"10146":{"HP":128,"ATK":26,"DEF":20,"storyLv":84,"power":1773},"10147":{"HP":146,"ATK":27,"DEF":22,"storyLv":84,"power":1961},"10148":{"HP":239,"ATK":40,"DEF":27,"storyLv":84,"power":7484},"10163":{"HP":628,"ATK":105,"DEF":91,"storyLv":84,"power":34737},"10164":{"HP":663,"ATK":105,"DEF":91,"storyLv":84,"power":35881}}},"party":{"forced":["10312"],"solo":true,"mustLive":["10312"],"levels":{"10312":84}},"bossId":"10146","mana":67,"starTurns":8,"starMana":0.3,"hero":"10317","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(14,13,'','{"no":13,"type":"normal","enemies":{"ids":["10504","10503"],"boost":{"10503":{"HP":2860,"ATK":286,"DEF":286,"storyLv":85,"power":447322},"10504":{"HP":2860,"ATK":286,"DEF":286,"storyLv":85,"power":455310}}},"party":{"forced":[],"mustLive":[]},"bossId":"10504","mana":100,"starTurns":8,"starMana":0.3,"hero":"10317","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(14,14,'','{"no":14,"type":"normal","enemies":{"ids":["10423","10287","10153","10154","10148"],"boost":{"10148":{"HP":241,"ATK":40,"DEF":27,"storyLv":85,"power":7523},"10153":{"HP":110,"ATK":18,"DEF":13,"storyLv":85,"power":1379},"10154":{"HP":129,"ATK":20,"DEF":15,"storyLv":85,"power":1593},"10287":{"HP":297,"ATK":67,"DEF":48,"storyLv":85,"power":11579},"10423":{"HP":129,"ATK":22,"DEF":15,"storyLv":85,"power":1597}}},"party":{"forced":["10192"],"costBelow":40,"mustLive":["10192"],"levels":{"10192":85}},"bossId":"10423","mana":150,"starTurns":5,"starMana":0,"rules":{"survive":5},"hero":"10317","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(14,15,'','{"no":15,"type":"normal","enemies":{"ids":["10423","10287","10136","10149","10155"],"boost":{"10136":{"HP":703,"ATK":135,"DEF":135,"storyLv":86,"power":39657},"10149":{"HP":297,"ATK":54,"DEF":40,"storyLv":86,"power":10356},"10155":{"HP":148,"ATK":22,"DEF":17,"storyLv":86,"power":1807},"10287":{"HP":300,"ATK":68,"DEF":49,"storyLv":86,"power":11734},"10423":{"HP":130,"ATK":22,"DEF":15,"storyLv":86,"power":1605}}},"party":{"forced":["10312"],"solo":true,"mustLive":["10312"],"levels":{"10312":86}},"bossId":"10423","mana":67,"starTurns":9,"starMana":0.3,"hero":"10317","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(14,16,'','{"no":16,"type":"normal","enemies":{"ids":["10181","10182","10433","10150","10151"],"boost":{"10150":{"HP":408,"ATK":82,"DEF":68,"storyLv":87,"power":15144},"10151":{"HP":716,"ATK":107,"DEF":107,"storyLv":87,"power":38819},"10181":{"HP":1243,"ATK":200,"DEF":169,"storyLv":87,"power":114560},"10182":{"HP":326,"ATK":44,"DEF":41,"storyLv":87,"power":9992},"10433":{"HP":770,"ATK":136,"DEF":86,"storyLv":87,"power":38176}}},"party":{"forced":["10312"],"solo":true,"mustLive":["10312"],"levels":{"10312":87}},"bossId":"10181","mana":67,"starTurns":8,"starMana":0.3,"hero":"10317","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(14,17,'','{"no":17,"type":"normal","enemies":{"ids":["10109","10017","10015","10150","10151"],"boost":{"10015":{"HP":758,"ATK":144,"DEF":83,"storyLv":88,"power":54578},"10017":{"HP":722,"ATK":144,"DEF":90,"storyLv":88,"power":46066},"10109":{"HP":1882,"ATK":278,"DEF":157,"storyLv":88,"power":193365},"10150":{"HP":411,"ATK":82,"DEF":68,"storyLv":88,"power":15205},"10151":{"HP":722,"ATK":108,"DEF":108,"storyLv":88,"power":39159}}},"party":{"forced":["10312"],"exclude":["10317"],"maxGrade":"SUPER RARE","mustLive":["10312"],"levels":{"10312":88}},"bossId":"10109","mana":90,"starTurns":9,"starMana":0.25,"hero":"10317","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(14,18,'','{"no":18,"type":"normal","enemies":{"ids":["10054","10109","10017","10015","10143"],"boost":{"10015":{"HP":771,"ATK":147,"DEF":84,"storyLv":90,"power":55533},"10017":{"HP":734,"ATK":147,"DEF":92,"storyLv":90,"power":46922},"10054":{"HP":2752,"ATK":409,"DEF":327,"storyLv":90,"power":312724},"10109":{"HP":1915,"ATK":283,"DEF":160,"storyLv":90,"power":196809},"10143":{"HP":94,"ATK":21,"DEF":15,"storyLv":90,"power":1279}}},"party":{"forced":["10312"],"exclude":["10317"],"maxGrade":"SUPER RARE","mustLive":["10312"],"levels":{"10312":90}},"bossId":"10054","mana":90,"starTurns":10,"starMana":0.2,"hero":"10317","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(15,1,'','{"no":1,"type":"normal","enemies":{"ids":["10143","10144","10153","10154","10155"],"boost":{"10143":{"HP":87,"ATK":19,"DEF":14,"storyLv":75,"power":1178},"10144":{"HP":87,"ATK":21,"DEF":16,"storyLv":75,"power":1242},"10153":{"HP":104,"ATK":17,"DEF":12,"storyLv":75,"power":1299},"10154":{"HP":122,"ATK":19,"DEF":14,"storyLv":75,"power":1505},"10155":{"HP":139,"ATK":21,"DEF":16,"storyLv":75,"power":1703}}},"party":{"forced":["10290"],"solo":true,"mustLive":["10290"],"levels":{"10290":75}},"bossId":"10143","mana":25,"starTurns":10,"starMana":0.3,"joinAlly":{"id":"10406","afterTurn":1,"storyLevel":100,"battleLevel":1},"hero":"10290","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(15,2,'','{"no":2,"type":"normal","enemies":{"ids":["10510","10145","10146","10156","10157"],"boost":{"10145":{"HP":105,"ATK":23,"DEF":18,"storyLv":76,"power":1439},"10146":{"HP":122,"ATK":24,"DEF":19,"storyLv":76,"power":1674},"10156":{"HP":158,"ATK":23,"DEF":18,"storyLv":76,"power":2037},"10157":{"HP":175,"ATK":24,"DEF":19,"storyLv":76,"power":2212},"10510":{"HP":650,"ATK":98,"DEF":98,"storyLv":76,"power":37320}}},"party":{"forced":["10290"],"maxGrade":"SUPER RARE","mustLive":["10290"],"levels":{"10290":76}},"bossId":"10510","mana":80,"starTurns":9,"starMana":0.25,"hero":"10290","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(15,3,'','{"no":3,"type":"normal","enemies":{"ids":["10280","10147","10148","10158","10159"],"boost":{"10147":{"HP":141,"ATK":26,"DEF":21,"storyLv":77,"power":1888},"10148":{"HP":227,"ATK":38,"DEF":25,"storyLv":77,"power":7084},"10158":{"HP":176,"ATK":26,"DEF":26,"storyLv":77,"power":2374},"10159":{"HP":252,"ATK":50,"DEF":40,"storyLv":77,"power":8696},"10280":{"HP":123,"ATK":18,"DEF":11,"storyLv":77,"power":1514}}},"party":{"forced":["10097"],"maxGrade":"HIGH RARE","mustLive":["10097"],"levels":{"10097":77}},"bossId":"10280","mana":80,"starTurns":9,"starMana":0.25,"hero":"10290","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(15,4,'','{"no":4,"type":"normal","enemies":{"ids":["10149","10150","10160","10161","10162"],"boost":{"10149":{"HP":279,"ATK":51,"DEF":38,"storyLv":78,"power":9759},"10150":{"HP":381,"ATK":76,"DEF":64,"storyLv":78,"power":14134},"10160":{"HP":305,"ATK":64,"DEF":53,"storyLv":78,"power":10863},"10161":{"HP":330,"ATK":69,"DEF":58,"storyLv":78,"power":12503},"10162":{"HP":381,"ATK":76,"DEF":66,"storyLv":78,"power":14216}}},"party":{"forced":["10383"],"maxGrade":"SUPER RARE","mustLive":["10383"],"levels":{"10383":78}},"bossId":"10149","mana":80,"starTurns":8,"starMana":0.3,"hero":"10290","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(15,5,'','{"no":5,"type":"normal","enemies":{"ids":["10151","10152","10163","10164","10165"],"boost":{"10151":{"HP":668,"ATK":100,"DEF":100,"storyLv":79,"power":36241},"10152":{"HP":768,"ATK":150,"DEF":150,"storyLv":79,"power":49456},"10163":{"HP":601,"ATK":100,"DEF":87,"storyLv":79,"power":33199},"10164":{"HP":635,"ATK":100,"DEF":87,"storyLv":79,"power":34311},"10165":{"HP":668,"ATK":100,"DEF":100,"storyLv":79,"power":36241}}},"party":{"forced":["10290","10024"],"maxGrade":"SUPER RARE","mustLive":["10290"],"levels":{"10024":79,"10290":79}},"bossId":"10151","mana":80,"starTurns":9,"starMana":0.25,"hero":"10290","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(15,6,'','{"no":6,"type":"normal","enemies":{"ids":["10383","10384"],"boost":{"10383":{"HP":1456,"ATK":187,"DEF":208,"storyLv":80,"power":175241},"10384":{"HP":258,"ATK":41,"DEF":34,"storyLv":80,"power":9197}}},"party":{"forced":["10024"],"noMale":true,"exclude":["10383","10384"],"mustLive":["10024"],"levels":{"10024":80}},"bossId":"10383","mana":60,"starTurns":7,"starMana":0.3,"hero":"10290","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(15,7,'','{"no":7,"type":"normal","enemies":{"ids":["10166","10167","10154","10155","10156"],"boost":{"10154":{"HP":125,"ATK":20,"DEF":14,"storyLv":80,"power":1546},"10155":{"HP":143,"ATK":21,"DEF":16,"storyLv":80,"power":1734},"10156":{"HP":161,"ATK":23,"DEF":18,"storyLv":80,"power":2062},"10166":{"HP":708,"ATK":118,"DEF":118,"storyLv":80,"power":40140},"10167":{"HP":775,"ATK":135,"DEF":135,"storyLv":80,"power":44778}}},"party":{"forced":["10024"],"solo":true,"mustLive":["10024"],"levels":{"10024":80}},"bossId":"10166","mana":59,"starTurns":8,"starMana":0.3,"hero":"10290","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(15,8,'','{"no":8,"type":"normal","enemies":{"ids":["10143","10144","10145","10157","10158"],"boost":{"10143":{"HP":90,"ATK":20,"DEF":14,"storyLv":81,"power":1217},"10144":{"HP":90,"ATK":22,"DEF":16,"storyLv":81,"power":1282},"10145":{"HP":108,"ATK":23,"DEF":18,"storyLv":81,"power":1461},"10157":{"HP":180,"ATK":25,"DEF":20,"storyLv":81,"power":2289},"10158":{"HP":180,"ATK":27,"DEF":27,"storyLv":81,"power":2443}}},"party":{"forced":["10290","10200"],"mustLive":[],"levels":{"10200":81,"10290":81}},"bossId":"10143","mana":80,"starTurns":10,"starMana":0.25,"hero":"10290","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(15,9,'','{"no":9,"type":"normal","enemies":{"ids":["10146","10147","10159","10160","10161"],"boost":{"10146":{"HP":127,"ATK":25,"DEF":20,"storyLv":82,"power":1747},"10147":{"HP":145,"ATK":27,"DEF":22,"storyLv":82,"power":1953},"10159":{"HP":262,"ATK":52,"DEF":42,"storyLv":82,"power":9058},"10160":{"HP":314,"ATK":66,"DEF":55,"storyLv":82,"power":11205},"10161":{"HP":341,"ATK":71,"DEF":60,"storyLv":82,"power":12907}}},"party":{"forced":["10097"],"noFemale":true,"mustLive":["10097"],"levels":{"10097":82}},"bossId":"10146","mana":80,"starTurns":9,"starMana":0.25,"hero":"10290","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(15,10,'','{"no":10,"type":"normal","enemies":{"ids":["10025","10148","10149","10162","10163"],"boost":{"10025":{"HP":1498,"ATK":235,"DEF":278,"storyLv":83,"power":132604},"10148":{"HP":238,"ATK":40,"DEF":26,"storyLv":83,"power":7426},"10149":{"HP":290,"ATK":53,"DEF":40,"storyLv":83,"power":10164},"10162":{"HP":396,"ATK":79,"DEF":69,"storyLv":83,"power":14792},"10163":{"HP":623,"ATK":104,"DEF":90,"storyLv":83,"power":34429}}},"party":{"forced":["10290"],"maxGrade":"HIGH RARE","mustLive":["10290"],"levels":{"10290":83}},"bossId":"10025","mana":120,"starTurns":5,"starMana":0,"rules":{"survive":5},"hero":"10290","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(15,11,'','{"no":11,"type":"normal","enemies":{"ids":["10123","10151","10151","10151","10151"],"boost":{"10123":{"HP":768,"ATK":93,"DEF":152,"storyLv":83,"power":41636},"10151":{"HP":692,"ATK":104,"DEF":104,"storyLv":83,"power":37602}}},"party":{"forced":["10290"],"exclude":["10383"],"mustLive":["10290"],"levels":{"10290":83}},"bossId":"10123","mana":80,"starTurns":9,"starMana":0.25,"hero":"10290","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(15,12,'','{"no":12,"type":"normal","enemies":{"ids":["10150","10151","10164","10165","10166"],"boost":{"10150":{"HP":399,"ATK":80,"DEF":66,"storyLv":84,"power":14780},"10151":{"HP":698,"ATK":105,"DEF":105,"storyLv":84,"power":37942},"10164":{"HP":663,"ATK":105,"DEF":91,"storyLv":84,"power":35881},"10165":{"HP":698,"ATK":105,"DEF":105,"storyLv":84,"power":37942},"10166":{"HP":733,"ATK":122,"DEF":122,"storyLv":84,"power":41533}}},"party":{"forced":["10024"],"solo":true,"mustLive":["10024"],"levels":{"10024":84}},"bossId":"10150","mana":59,"starTurns":8,"starMana":0.3,"hero":"10290","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(15,13,'','{"no":13,"type":"normal","enemies":{"ids":["10123","10183","10152","10167","10168"],"boost":{"10123":{"HP":788,"ATK":96,"DEF":156,"storyLv":86,"power":42767},"10152":{"HP":816,"ATK":160,"DEF":160,"storyLv":86,"power":52642},"10167":{"HP":816,"ATK":142,"DEF":142,"storyLv":86,"power":47127},"10168":{"HP":888,"ATK":160,"DEF":160,"storyLv":86,"power":55135},"10183":{"HP":1848,"ATK":264,"DEF":198,"storyLv":86,"power":133936}}},"party":{"forced":["10024"],"exclude":["10290","10383"],"maxGrade":"HIGH RARE","mustLive":["10024"],"levels":{"10024":86}},"bossId":"10123","mana":80,"starTurns":10,"starMana":0.2,"hero":"10290","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(15,14,'','{"no":14,"type":"normal","enemies":{"ids":["10024"],"boost":{"10024":{"HP":1376,"ATK":266,"DEF":222,"storyLv":87,"power":173281}}},"party":{"forced":["10097"],"exclude":["10126"],"maxGrade":"HIGH RARE","noMale":true,"mustLive":["10097"],"levels":{"10097":87}},"bossId":"10024","mana":120,"starTurns":5,"starMana":0,"rules":{"survive":5},"hero":"10290","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(15,15,'','{"no":15,"type":"normal","enemies":{"ids":["10025","10143","10144","10153","10154"],"boost":{"10025":{"HP":1568,"ATK":246,"DEF":291,"storyLv":88,"power":138803},"10143":{"HP":94,"ATK":21,"DEF":15,"storyLv":88,"power":1279},"10144":{"HP":94,"ATK":22,"DEF":17,"storyLv":88,"power":1326},"10153":{"HP":112,"ATK":19,"DEF":13,"storyLv":88,"power":1413},"10154":{"HP":131,"ATK":21,"DEF":15,"storyLv":88,"power":1626}}},"party":{"forced":["10024"],"maxGrade":"HIGH RARE","noMale":true,"mustLive":["10024"],"levels":{"10024":88}},"bossId":"10025","mana":80,"starTurns":8,"starMana":0.3,"hero":"10290","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb)
on conflict (chapter,phase,variant) do update set definition=excluded.definition;

insert into public.battle_story_defs_v2(chapter,phase,variant,definition) values
(15,16,'','{"no":16,"type":"normal","enemies":{"ids":["10200","10143","10143","10143","10143"],"boost":{"10143":{"HP":65,"ATK":14,"DEF":10,"storyLv":31,"power":869},"10200":{"HP":1756,"ATK":319,"DEF":160,"storyLv":90,"power":151890}}},"party":{"forced":["10024"],"maxGrade":"HIGH RARE","noMale":true,"mustLive":["10024"],"levels":{"10024":90}},"bossId":"10200","mana":150,"starTurns":10,"starMana":0,"rules":{"survive":10,"revive":[{"id":"10143","delay":2,"level":"keep"}]},"hero":"10290","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb)
on conflict (chapter,phase,variant) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10118','{"class":"FIRE","gender":"MALE","MOR":72,"cost":43,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10019','{"class":"FIRE","gender":"MALE","MOR":25,"cost":17,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10018','{"class":"WIND","gender":"MALE","MOR":20,"cost":17,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10299','{"class":"ICE","gender":"MALE","MOR":18,"cost":26,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10074','{"class":"WIND","gender":"MALE","MOR":21,"cost":5,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10080','{"class":"WIND","gender":"MALE","MOR":18,"cost":5,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10445','{"class":"WIND","gender":"MALE","MOR":25,"cost":7,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10375','{"class":"FIRE","gender":"MALE","MOR":23,"cost":6,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10051','{"class":"FIRE","gender":"MALE","MOR":60,"cost":48,"grade":"ULTRA RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10404','{"class":"WIND","gender":"MALE","MOR":55,"cost":8,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10049','{"class":"ICE","gender":"MALE","MOR":82,"cost":14,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10048','{"class":"WIND","gender":"MALE","MOR":80,"cost":14,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10189','{"class":"FIRE","gender":"MALE","MOR":77,"cost":45,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10060','{"class":"ABYSS","gender":"MALE","MOR":1,"cost":62,"grade":"MYTHIC RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10071','{"class":"WIND","gender":"MALE","MOR":32,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10086','{"class":"WIND","gender":"MALE","MOR":39,"cost":8,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10169','{"class":"WIND","gender":"MALE","MOR":78,"cost":14,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10137','{"class":"ICE","gender":"MALE","MOR":25,"cost":30,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10138','{"class":"WIND","gender":"MALE","MOR":25,"cost":26,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10020','{"class":"FIRE","gender":"MALE","MOR":23,"cost":23,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10463','{"class":"WIND","gender":"MALE","MOR":13,"cost":30,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10228','{"class":"FIRE","gender":"MALE","MOR":79,"cost":24,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10453','{"class":"WIND","gender":"MALE","MOR":41,"cost":6,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10293','{"class":"FIRE","gender":"MALE","MOR":80,"cost":25,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10010','{"class":"FIRE","gender":"MALE","MOR":41,"cost":13,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10380','{"class":"ICE","gender":"MALE","MOR":80,"cost":24,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10114','{"class":"WIND","gender":"MALE","MOR":21,"cost":7,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10401','{"class":"FIRE","gender":"MALE","MOR":31,"cost":12,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10315','{"class":"FIRE","gender":"MALE","MOR":36,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10026','{"class":"FIRE","gender":"MALE","MOR":40,"cost":11,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10191','{"class":"ICE","gender":"MALE","MOR":26,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10469','{"class":"FIRE","gender":"MALE","MOR":78,"cost":12,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10001','{"class":"WIND","gender":"MALE","MOR":29,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10183','{"class":"ICE","gender":"MALE","MOR":13,"cost":37,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10064','{"class":"WIND","gender":"MALE","MOR":35,"cost":7,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10444','{"class":"FIRE","gender":"MALE","MOR":15,"cost":5,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10279','{"class":"WIND","gender":"MALE","MOR":9,"cost":5,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10225','{"class":"FIRE","gender":"MALE","MOR":42,"cost":23,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10431','{"class":"WIND","gender":"MALE","MOR":28,"cost":8,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10332','{"class":"ICE","gender":"MALE","MOR":19,"cost":13,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10201','{"class":"WIND","gender":"MALE","MOR":47,"cost":6,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10346','{"class":"WIND","gender":"MALE","MOR":12,"cost":11,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10275','{"class":"ICE","gender":"MALE","MOR":12,"cost":11,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10124','{"class":"WIND","gender":"MALE","MOR":24,"cost":21,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10134','{"class":"WIND","gender":"MALE","MOR":12,"cost":20,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10037','{"class":"FIRE","gender":"MALE","MOR":11,"cost":12,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10031','{"class":"ICE","gender":"MALE","MOR":14,"cost":6,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10180','{"class":"ICE","gender":"MALE","MOR":31,"cost":17,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10390','{"class":"WIND","gender":"MALE","MOR":12,"cost":12,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10027','{"class":"ICE","gender":"MALE","MOR":11,"cost":6,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10033','{"class":"FIRE","gender":"MALE","MOR":1,"cost":11,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10353','{"class":"WIND","gender":"MALE","MOR":3,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10244','{"class":"FIRE","gender":"MALE","MOR":5,"cost":12,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10245','{"class":"WIND","gender":"MALE","MOR":11,"cost":11,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10292','{"class":"WIND","gender":"MALE","MOR":55,"cost":28,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10076','{"class":"ICE","gender":"MALE","MOR":35,"cost":7,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10045','{"class":"ICE","gender":"MALE","MOR":78,"cost":45,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10409','{"class":"FIRE","gender":"MALE","MOR":10,"cost":7,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10407','{"class":"ICE","gender":"MALE","MOR":69,"cost":23,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10036','{"class":"WIND","gender":"MALE","MOR":21,"cost":29,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10075','{"class":"WIND","gender":"MALE","MOR":30,"cost":9,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10173','{"class":"WIND","gender":"MALE","MOR":35,"cost":11,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10406','{"class":"ICE","gender":"MALE","MOR":77,"cost":33,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10328','{"class":"FIRE","gender":"MALE","MOR":60,"cost":15,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10329','{"class":"WIND","gender":"MALE","MOR":50,"cost":37,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10098','{"class":"FIRE","gender":"MALE","MOR":18,"cost":18,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10187','{"class":"FIRE","gender":"MALE","MOR":11,"cost":17,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10319','{"class":"FIRE","gender":"MALE","MOR":18,"cost":16,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10081','{"class":"WIND","gender":"MALE","MOR":15,"cost":32,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10252','{"class":"ICE","gender":"MALE","MOR":20,"cost":11,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10298','{"class":"FIRE","gender":"MALE","MOR":88,"cost":31,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10125','{"class":"FIRE","gender":"MALE","MOR":73,"cost":15,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10025','{"class":"FIRE","gender":"MALE","MOR":10,"cost":37,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10035','{"class":"ICE","gender":"MALE","MOR":12,"cost":28,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10112','{"class":"FIRE","gender":"MALE","MOR":55,"cost":36,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10270','{"class":"FIRE","gender":"FEMALE","MOR":19,"cost":16,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10069','{"class":"ICE","gender":"MALE","MOR":42,"cost":13,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10088','{"class":"FIRE","gender":"MALE","MOR":16,"cost":11,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10004','{"class":"WIND","gender":"MALE","MOR":78,"cost":9,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10420','{"class":"WIND","gender":"MALE","MOR":13,"cost":18,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10408','{"class":"WIND","gender":"MALE","MOR":18,"cost":19,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10205','{"class":"ICE","gender":"MALE","MOR":79,"cost":33,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10139','{"class":"WIND","gender":"MALE","MOR":20,"cost":6,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10347','{"class":"ICE","gender":"MALE","MOR":21,"cost":22,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10023','{"class":"WIND","gender":"MALE","MOR":49,"cost":6,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10448','{"class":"FIRE","gender":"MALE","MOR":27,"cost":11,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10067','{"class":"FIRE","gender":"MALE","MOR":16,"cost":38,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10005','{"class":"WIND","gender":"MALE","MOR":58,"cost":8,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10276','{"class":"WIND","gender":"MALE","MOR":39,"cost":20,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10259','{"class":"ICE","gender":"MALE","MOR":19,"cost":21,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10386','{"class":"WIND","gender":"MALE","MOR":30,"cost":24,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10105','{"class":"FIRE","gender":"MALE","MOR":27,"cost":22,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10077','{"class":"ICE","gender":"MALE","MOR":34,"cost":32,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10212','{"class":"WIND","gender":"MALE","MOR":17,"cost":5,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10065','{"class":"ICE","gender":"MALE","MOR":25,"cost":25,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10008','{"class":"WIND","gender":"MALE","MOR":79,"cost":11,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10425','{"class":"WIND","gender":"MALE","MOR":13,"cost":29,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10107','{"class":"WIND","gender":"MALE","MOR":29,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10032','{"class":"WIND","gender":"MALE","MOR":33,"cost":8,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10142','{"class":"ICE","gender":"MALE","MOR":72,"cost":5,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10089','{"class":"WIND","gender":"MALE","MOR":8,"cost":22,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10094','{"class":"WIND","gender":"MALE","MOR":21,"cost":7,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10350','{"class":"FIRE","gender":"MALE","MOR":80,"cost":35,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10366','{"class":"WIND","gender":"MALE","MOR":32,"cost":13,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10016','{"class":"WIND","gender":"MALE","MOR":12,"cost":18,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10385','{"class":"ICE","gender":"MALE","MOR":21,"cost":16,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10474','{"class":"WIND","gender":"MALE","MOR":58,"cost":13,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10287','{"class":"FIRE","gender":"MALE","MOR":18,"cost":18,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10182','{"class":"DARK","gender":"MALE","MOR":20,"cost":16,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10136','{"class":"ICE","gender":"MALE","MOR":16,"cost":27,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10209','{"class":"ICE","gender":"MALE","MOR":20,"cost":7,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10170','{"class":"FIRE","gender":"MALE","MOR":21,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10128','{"class":"FIRE","gender":"MALE","MOR":25,"cost":6,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10433','{"class":"WIND","gender":"MALE","MOR":19,"cost":26,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10374','{"class":"WIND","gender":"MALE","MOR":82,"cost":32,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10218','{"class":"FIRE","gender":"MALE","MOR":59,"cost":14,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10441','{"class":"FIRE","gender":"MALE","MOR":37,"cost":6,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10349','{"class":"FIRE","gender":"MALE","MOR":21,"cost":16,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10314','{"class":"WIND","gender":"MALE","MOR":31,"cost":6,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10337','{"class":"ICE","gender":"MALE","MOR":25,"cost":6,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10038','{"class":"WIND","gender":"MALE","MOR":21,"cost":7,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10365','{"class":"WIND","gender":"MALE","MOR":80,"cost":12,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10278','{"class":"WIND","gender":"MALE","MOR":79,"cost":23,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10251','{"class":"FIRE","gender":"MALE","MOR":82,"cost":14,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10109','{"class":"FIRE","gender":"MALE","MOR":60,"cost":42,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10017','{"class":"FIRE","gender":"MALE","MOR":60,"cost":30,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10015','{"class":"ICE","gender":"MALE","MOR":72,"cost":32,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10028','{"class":"WIND","gender":"MALE","MOR":55,"cost":7,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10181','{"class":"WIND","gender":"MALE","MOR":19,"cost":35,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10333','{"class":"FIRE","gender":"MALE","MOR":78,"cost":43,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10054','{"class":"DARK","gender":"MALE","MOR":8,"cost":46,"grade":"ULTRA RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10046','{"class":"WIND","gender":"MALE","MOR":75,"cost":22,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10066','{"class":"WIND","gender":"MALE","MOR":55,"cost":12,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10195','{"class":"ICE","gender":"MALE","MOR":10,"cost":15,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10283','{"class":"FIRE","gender":"MALE","MOR":65,"cost":14,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10284','{"class":"FIRE","gender":"MALE","MOR":40,"cost":20,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10321','{"class":"DARK","gender":"MALE","MOR":12,"cost":38,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10320','{"class":"FIRE","gender":"MALE","MOR":16,"cost":5,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10371','{"class":"FIRE","gender":"MALE","MOR":16,"cost":28,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10345','{"class":"FIRE","gender":"MALE","MOR":14,"cost":19,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10021','{"class":"WIND","gender":"MALE","MOR":20,"cost":20,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10424','{"class":"WIND","gender":"MALE","MOR":12,"cost":21,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10398','{"class":"ICE","gender":"MALE","MOR":24,"cost":16,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10318','{"class":"WIND","gender":"MALE","MOR":42,"cost":13,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10458','{"class":"FIRE","gender":"MALE","MOR":24,"cost":18,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10464','{"class":"FIRE","gender":"MALE","MOR":38,"cost":19,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10233','{"class":"FIRE","gender":"MALE","MOR":19,"cost":9,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10034','{"class":"WIND","gender":"MALE","MOR":35,"cost":14,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10171','{"class":"FIRE","gender":"MALE","MOR":75,"cost":13,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10119','{"class":"ICE","gender":"MALE","MOR":75,"cost":9,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10226','{"class":"WIND","gender":"MALE","MOR":11,"cost":16,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10307','{"class":"ICE","gender":"MALE","MOR":80,"cost":20,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10402','{"class":"WIND","gender":"MALE","MOR":13,"cost":7,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10009','{"class":"WIND","gender":"MALE","MOR":65,"cost":14,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10055','{"class":"WIND","gender":"MALE","MOR":18,"cost":7,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10013','{"class":"FIRE","gender":"MALE","MOR":55,"cost":39,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10313','{"class":"WIND","gender":"MALE","MOR":65,"cost":15,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10106','{"class":"ICE","gender":"MALE","MOR":16,"cost":6,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10316','{"class":"WIND","gender":"MALE","MOR":50,"cost":12,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10416','{"class":"WIND","gender":"MALE","MOR":45,"cost":11,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10057','{"class":"WIND","gender":"MALE","MOR":3,"cost":5,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10220','{"class":"FIRE","gender":"MALE","MOR":60,"cost":13,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10340','{"class":"FIRE","gender":"MALE","MOR":30,"cost":11,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10309','{"class":"FIRE","gender":"MALE","MOR":15,"cost":25,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10070','{"class":"ICE","gender":"MALE","MOR":78,"cost":39,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10113','{"class":"ICE","gender":"MALE","MOR":30,"cost":7,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10364','{"class":"ICE","gender":"MALE","MOR":17,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10410','{"class":"WIND","gender":"MALE","MOR":45,"cost":9,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10419','{"class":"WIND","gender":"MALE","MOR":12,"cost":25,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10053','{"class":"DARK","gender":"MALE","MOR":1,"cost":45,"grade":"ULTRA RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10176','{"class":"LIGHT","gender":"MALE","MOR":90,"cost":49,"grade":"ULTRA RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10200','{"class":"DARK","gender":"MALE","MOR":15,"cost":38,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10234','{"class":"FIRE","gender":"MALE","MOR":20,"cost":16,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10123','{"class":"FIRE","gender":"MALE","MOR":12,"cost":29,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10304','{"class":"DARK","gender":"MALE","MOR":85,"cost":51,"grade":"ULTRA RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10434','{"class":"FIRE","gender":"MALE","MOR":25,"cost":9,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10430','{"class":"WIND","gender":"MALE","MOR":22,"cost":9,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10379','{"class":"WIND","gender":"MALE","MOR":70,"cost":14,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10325','{"class":"DARK","gender":"FEMALE","MOR":1,"cost":46,"grade":"ULTRA RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10260','{"class":"ICE","gender":"FEMALE","MOR":58,"cost":13,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10300','{"class":"DARK","gender":"FEMALE","MOR":72,"cost":20,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10462','{"class":"WIND","gender":"FEMALE","MOR":65,"cost":15,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10072','{"class":"DARK","gender":"FEMALE","MOR":10,"cost":26,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10256','{"class":"DARK","gender":"FEMALE","MOR":55,"cost":21,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10115','{"class":"WIND","gender":"FEMALE","MOR":89,"cost":19,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10348','{"class":"ICE","gender":"FEMALE","MOR":24,"cost":8,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10339','{"class":"ICE","gender":"FEMALE","MOR":28,"cost":8,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10394','{"class":"LIGHT","gender":"FEMALE","MOR":88,"cost":25,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10047','{"class":"WIND","gender":"FEMALE","MOR":82,"cost":27,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10188','{"class":"WIND","gender":"FEMALE","MOR":80,"cost":34,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10132','{"class":"WIND","gender":"FEMALE","MOR":81,"cost":21,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10087','{"class":"ICE","gender":"FEMALE","MOR":21,"cost":29,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10202','{"class":"FIRE","gender":"FEMALE","MOR":45,"cost":19,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10184','{"class":"WIND","gender":"FEMALE","MOR":31,"cost":8,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10103','{"class":"DARK","gender":"FEMALE","MOR":89,"cost":19,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10265','{"class":"WIND","gender":"FEMALE","MOR":79,"cost":25,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10266','{"class":"WIND","gender":"FEMALE","MOR":88,"cost":18,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10465','{"class":"WIND","gender":"FEMALE","MOR":85,"cost":43,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10466','{"class":"WIND","gender":"FEMALE","MOR":88,"cost":22,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10002','{"class":"WIND","gender":"FEMALE","MOR":31,"cost":9,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10289','{"class":"WIND","gender":"FEMALE","MOR":52,"cost":9,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10083','{"class":"WIND","gender":"FEMALE","MOR":11,"cost":5,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10079','{"class":"FIRE","gender":"FEMALE","MOR":13,"cost":11,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10338','{"class":"WIND","gender":"FEMALE","MOR":70,"cost":34,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10336','{"class":"WIND","gender":"FEMALE","MOR":78,"cost":34,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10418','{"class":"ICE","gender":"FEMALE","MOR":74,"cost":40,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10323','{"class":"FIRE","gender":"FEMALE","MOR":72,"cost":49,"grade":"ULTRA RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10403','{"class":"ICE","gender":"FEMALE","MOR":70,"cost":14,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10185','{"class":"FIRE","gender":"FEMALE","MOR":88,"cost":9,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10308','{"class":"ICE","gender":"FEMALE","MOR":55,"cost":28,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10413','{"class":"WIND","gender":"FEMALE","MOR":88,"cost":35,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10415','{"class":"DARK","gender":"FEMALE","MOR":90,"cost":43,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10414','{"class":"ICE","gender":"FEMALE","MOR":85,"cost":35,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10186','{"class":"ICE","gender":"FEMALE","MOR":43,"cost":37,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10295','{"class":"WIND","gender":"FEMALE","MOR":25,"cost":12,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10297','{"class":"WIND","gender":"FEMALE","MOR":92,"cost":23,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10317','{"class":"ICE","gender":"FEMALE","MOR":72,"cost":41,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10108','{"class":"LIGHT","gender":"FEMALE","MOR":90,"cost":41,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10417','{"class":"ICE","gender":"FEMALE","MOR":78,"cost":17,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10172','{"class":"FIRE","gender":"FEMALE","MOR":21,"cost":6,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10262','{"class":"WIND","gender":"FEMALE","MOR":40,"cost":8,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10261','{"class":"WIND","gender":"FEMALE","MOR":58,"cost":20,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10290','{"class":"LIGHT","gender":"FEMALE","MOR":99,"cost":17,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10384','{"class":"WIND","gender":"FEMALE","MOR":55,"cost":16,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10383','{"class":"DARK","gender":"FEMALE","MOR":85,"cost":42,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10110','{"class":"FIRE","gender":"FEMALE","MOR":58,"cost":34,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10442','{"class":"ICE","gender":"FEMALE","MOR":60,"cost":30,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10129','{"class":"WIND","gender":"FEMALE","MOR":78,"cost":15,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10014','{"class":"FIRE","gender":"FEMALE","MOR":21,"cost":7,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10235','{"class":"ICE","gender":"FEMALE","MOR":35,"cost":6,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10111','{"class":"FIRE","gender":"FEMALE","MOR":80,"cost":25,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10357','{"class":"FIRE","gender":"FEMALE","MOR":15,"cost":15,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10360','{"class":"WIND","gender":"FEMALE","MOR":12,"cost":13,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10306','{"class":"WIND","gender":"FEMALE","MOR":90,"cost":17,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10285','{"class":"WIND","gender":"FEMALE","MOR":20,"cost":19,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10343','{"class":"FIRE","gender":"FEMALE","MOR":45,"cost":27,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10271','{"class":"WIND","gender":"FEMALE","MOR":13,"cost":12,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10003','{"class":"FIRE","gender":"FEMALE","MOR":27,"cost":9,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10095','{"class":"FIRE","gender":"FEMALE","MOR":42,"cost":22,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10096','{"class":"ICE","gender":"FEMALE","MOR":43,"cost":28,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10342','{"class":"WIND","gender":"FEMALE","MOR":41,"cost":12,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10327','{"class":"ICE","gender":"FEMALE","MOR":21,"cost":14,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10286','{"class":"WIND","gender":"FEMALE","MOR":65,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10273','{"class":"WIND","gender":"FEMALE","MOR":32,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10253','{"class":"FIRE","gender":"FEMALE","MOR":52,"cost":15,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10061','{"class":"ICE","gender":"FEMALE","MOR":31,"cost":36,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10460','{"class":"WIND","gender":"FEMALE","MOR":51,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10459','{"class":"WIND","gender":"FEMALE","MOR":49,"cost":13,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10461','{"class":"FIRE","gender":"FEMALE","MOR":57,"cost":23,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10296','{"class":"WIND","gender":"FEMALE","MOR":41,"cost":21,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10246','{"class":"WIND","gender":"FEMALE","MOR":51,"cost":20,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10204','{"class":"WIND","gender":"FEMALE","MOR":60,"cost":24,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10447','{"class":"WIND","gender":"FEMALE","MOR":44,"cost":21,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10429','{"class":"WIND","gender":"FEMALE","MOR":50,"cost":23,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10211','{"class":"WIND","gender":"FEMALE","MOR":21,"cost":8,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10193','{"class":"ICE","gender":"FEMALE","MOR":52,"cost":9,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10120','{"class":"FIRE","gender":"FEMALE","MOR":24,"cost":13,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10101','{"class":"WIND","gender":"FEMALE","MOR":33,"cost":14,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10099','{"class":"WIND","gender":"FEMALE","MOR":50,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10241','{"class":"WIND","gender":"FEMALE","MOR":49,"cost":20,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10044','{"class":"WIND","gender":"FEMALE","MOR":42,"cost":21,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10043','{"class":"WIND","gender":"FEMALE","MOR":25,"cost":30,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10376','{"class":"WIND","gender":"FEMALE","MOR":71,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10377','{"class":"WIND","gender":"FEMALE","MOR":81,"cost":8,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10322','{"class":"ICE","gender":"FEMALE","MOR":62,"cost":50,"grade":"ULTRA RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10239','{"class":"WIND","gender":"FEMALE","MOR":31,"cost":31,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10039','{"class":"WIND","gender":"FEMALE","MOR":30,"cost":8,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10310','{"class":"WIND","gender":"FEMALE","MOR":19,"cost":8,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10247','{"class":"ICE","gender":"FEMALE","MOR":72,"cost":14,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10248','{"class":"WIND","gender":"FEMALE","MOR":82,"cost":6,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10221','{"class":"FIRE","gender":"FEMALE","MOR":80,"cost":9,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10011','{"class":"WIND","gender":"FEMALE","MOR":28,"cost":7,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10140','{"class":"WIND","gender":"FEMALE","MOR":32,"cost":11,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10388','{"class":"WIND","gender":"FEMALE","MOR":57,"cost":7,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10121','{"class":"WIND","gender":"FEMALE","MOR":14,"cost":16,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10236','{"class":"FIRE","gender":"FEMALE","MOR":75,"cost":42,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10102','{"class":"WIND","gender":"FEMALE","MOR":9,"cost":26,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10092','{"class":"WIND","gender":"FEMALE","MOR":21,"cost":17,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10194','{"class":"WIND","gender":"FEMALE","MOR":29,"cost":17,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10361','{"class":"WIND","gender":"FEMALE","MOR":6,"cost":27,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10354','{"class":"ICE","gender":"FEMALE","MOR":3,"cost":36,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10254','{"class":"WIND","gender":"FEMALE","MOR":42,"cost":18,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10222','{"class":"WIND","gender":"FEMALE","MOR":24,"cost":17,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10470','{"class":"FIRE","gender":"FEMALE","MOR":57,"cost":23,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10059','{"class":"DARK","gender":"FEMALE","MOR":6,"cost":17,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10428','{"class":"WIND","gender":"FEMALE","MOR":77,"cost":5,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10471','{"class":"FIRE","gender":"FEMALE","MOR":80,"cost":14,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10450','{"class":"ICE","gender":"FEMALE","MOR":54,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10432','{"class":"WIND","gender":"FEMALE","MOR":88,"cost":22,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10359','{"class":"ICE","gender":"FEMALE","MOR":77,"cost":51,"grade":"ULTRA RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10362','{"class":"DARK","gender":"FEMALE","MOR":80,"cost":33,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10454','{"class":"ICE","gender":"FEMALE","MOR":13,"cost":21,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10363','{"class":"WIND","gender":"FEMALE","MOR":78,"cost":9,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10436','{"class":"FIRE","gender":"FEMALE","MOR":21,"cost":12,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10412','{"class":"ICE","gender":"FEMALE","MOR":13,"cost":12,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10040','{"class":"FIRE","gender":"FEMALE","MOR":82,"cost":15,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10042','{"class":"WIND","gender":"FEMALE","MOR":80,"cost":24,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10237','{"class":"ICE","gender":"FEMALE","MOR":75,"cost":25,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10207','{"class":"ICE","gender":"FEMALE","MOR":6,"cost":27,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10208','{"class":"DARK","gender":"FEMALE","MOR":2,"cost":31,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10303','{"class":"WIND","gender":"FEMALE","MOR":19,"cost":9,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10468','{"class":"WIND","gender":"FEMALE","MOR":88,"cost":13,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10467','{"class":"LIGHT","gender":"FEMALE","MOR":90,"cost":15,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10294','{"class":"WIND","gender":"FEMALE","MOR":81,"cost":15,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10258','{"class":"WIND","gender":"FEMALE","MOR":80,"cost":25,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10056','{"class":"WIND","gender":"FEMALE","MOR":73,"cost":14,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10041','{"class":"WIND","gender":"FEMALE","MOR":72,"cost":32,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10255','{"class":"ICE","gender":"FEMALE","MOR":75,"cost":44,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10141','{"class":"WIND","gender":"FEMALE","MOR":43,"cost":22,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10133','{"class":"WIND","gender":"FEMALE","MOR":51,"cost":23,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10091','{"class":"DARK","gender":"FEMALE","MOR":24,"cost":21,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10090','{"class":"ICE","gender":"FEMALE","MOR":35,"cost":20,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10344','{"class":"ICE","gender":"FEMALE","MOR":78,"cost":7,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10330','{"class":"ICE","gender":"FEMALE","MOR":55,"cost":11,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10263','{"class":"FIRE","gender":"FEMALE","MOR":80,"cost":6,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10249','{"class":"FIRE","gender":"FEMALE","MOR":39,"cost":13,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10063','{"class":"ICE","gender":"FEMALE","MOR":49,"cost":14,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10052','{"class":"DARK","gender":"FEMALE","MOR":6,"cost":39,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10190','{"class":"FIRE","gender":"FEMALE","MOR":61,"cost":13,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10174','{"class":"WIND","gender":"FEMALE","MOR":52,"cost":12,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10122','{"class":"ICE","gender":"FEMALE","MOR":68,"cost":14,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10029','{"class":"FIRE","gender":"FEMALE","MOR":75,"cost":23,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10232','{"class":"WIND","gender":"FEMALE","MOR":80,"cost":12,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10104','{"class":"WIND","gender":"FEMALE","MOR":66,"cost":24,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10378','{"class":"ICE","gender":"FEMALE","MOR":42,"cost":23,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10126','{"class":"WIND","gender":"FEMALE","MOR":44,"cost":31,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10062','{"class":"ABYSS","gender":"FEMALE","MOR":1,"cost":58,"grade":"MYTHIC RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10203','{"class":"LIGHT","gender":"FEMALE","MOR":80,"cost":33,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10097','{"class":"WIND","gender":"FEMALE","MOR":82,"cost":22,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10280','{"class":"ICE","gender":"FEMALE","MOR":23,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10352','{"class":"WIND","gender":"FEMALE","MOR":21,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10277','{"class":"WIND","gender":"FEMALE","MOR":39,"cost":7,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10100','{"class":"FIRE","gender":"FEMALE","MOR":39,"cost":9,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10451','{"class":"ICE","gender":"FEMALE","MOR":49,"cost":12,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10389','{"class":"WIND","gender":"FEMALE","MOR":51,"cost":11,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10264','{"class":"ICE","gender":"FEMALE","MOR":61,"cost":11,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10438','{"class":"ICE","gender":"FEMALE","MOR":59,"cost":13,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10177','{"class":"WIND","gender":"FEMALE","MOR":30,"cost":13,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10178','{"class":"ICE","gender":"FEMALE","MOR":29,"cost":12,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10372','{"class":"ICE","gender":"FEMALE","MOR":68,"cost":24,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10373','{"class":"WIND","gender":"FEMALE","MOR":50,"cost":35,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10130','{"class":"WIND","gender":"FEMALE","MOR":81,"cost":7,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10131','{"class":"DARK","gender":"FEMALE","MOR":72,"cost":31,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10341','{"class":"ICE","gender":"FEMALE","MOR":82,"cost":44,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10272','{"class":"WIND","gender":"FEMALE","MOR":69,"cost":6,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10117','{"class":"FIRE","gender":"FEMALE","MOR":82,"cost":44,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10078','{"class":"FIRE","gender":"FEMALE","MOR":13,"cost":30,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10084','{"class":"FIRE","gender":"FEMALE","MOR":56,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10085','{"class":"FIRE","gender":"FEMALE","MOR":59,"cost":11,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10217','{"class":"DARK","gender":"FEMALE","MOR":3,"cost":40,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10216','{"class":"DARK","gender":"FEMALE","MOR":8,"cost":39,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10324','{"class":"DARK","gender":"FEMALE","MOR":90,"cost":53,"grade":"ULTRA RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10006','{"class":"FIRE","gender":"FEMALE","MOR":80,"cost":14,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10068','{"class":"DARK","gender":"FEMALE","MOR":65,"cost":41,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10400','{"class":"ICE","gender":"FEMALE","MOR":35,"cost":26,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10331','{"class":"LIGHT","gender":"FEMALE","MOR":99,"cost":52,"grade":"ULTRA RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10250','{"class":"WIND","gender":"FEMALE","MOR":57,"cost":7,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10022','{"class":"FIRE","gender":"FEMALE","MOR":82,"cost":8,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10437','{"class":"DARK","gender":"FEMALE","MOR":6,"cost":18,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10426','{"class":"FIRE","gender":"FEMALE","MOR":16,"cost":18,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10381','{"class":"FIRE","gender":"FEMALE","MOR":41,"cost":5,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10179','{"class":"WIND","gender":"FEMALE","MOR":65,"cost":8,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10215','{"class":"FIRE","gender":"FEMALE","MOR":72,"cost":13,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10214','{"class":"FIRE","gender":"FEMALE","MOR":72,"cost":31,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10223','{"class":"WIND","gender":"FEMALE","MOR":80,"cost":12,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10269','{"class":"WIND","gender":"FEMALE","MOR":6,"cost":38,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10268','{"class":"WIND","gender":"FEMALE","MOR":11,"cost":29,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10473','{"class":"WIND","gender":"FEMALE","MOR":12,"cost":28,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10135','{"class":"DARK","gender":"FEMALE","MOR":77,"cost":25,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10206','{"class":"ICE","gender":"FEMALE","MOR":80,"cost":11,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10240','{"class":"WIND","gender":"FEMALE","MOR":72,"cost":32,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10238','{"class":"WIND","gender":"FEMALE","MOR":45,"cost":12,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10230','{"class":"WIND","gender":"FEMALE","MOR":78,"cost":22,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10227','{"class":"WIND","gender":"FEMALE","MOR":87,"cost":24,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10387','{"class":"WIND","gender":"FEMALE","MOR":25,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10281','{"class":"WIND","gender":"FEMALE","MOR":80,"cost":41,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10472','{"class":"WIND","gender":"FEMALE","MOR":78,"cost":8,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10455','{"class":"FIRE","gender":"FEMALE","MOR":80,"cost":24,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10423','{"class":"FIRE","gender":"FEMALE","MOR":21,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10456','{"class":"ICE","gender":"FEMALE","MOR":85,"cost":7,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10457','{"class":"WIND","gender":"FEMALE","MOR":83,"cost":33,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10224','{"class":"WIND","gender":"FEMALE","MOR":79,"cost":24,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10382','{"class":"WIND","gender":"FEMALE","MOR":30,"cost":6,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10393','{"class":"ICE","gender":"FEMALE","MOR":89,"cost":33,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10030','{"class":"WIND","gender":"FEMALE","MOR":72,"cost":9,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10391','{"class":"WIND","gender":"FEMALE","MOR":21,"cost":19,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10392','{"class":"WIND","gender":"FEMALE","MOR":88,"cost":42,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10311','{"class":"ABYSS","gender":"FEMALE","MOR":100,"cost":65,"grade":"MYTHIC RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10397','{"class":"ICE","gender":"FEMALE","MOR":88,"cost":21,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10242','{"class":"WIND","gender":"FEMALE","MOR":55,"cost":15,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10356','{"class":"ICE","gender":"FEMALE","MOR":21,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10274','{"class":"WIND","gender":"FEMALE","MOR":21,"cost":6,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10192','{"class":"FIRE","gender":"FEMALE","MOR":78,"cost":15,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10093','{"class":"WIND","gender":"FEMALE","MOR":85,"cost":8,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10312','{"class":"DARK","gender":"FEMALE","MOR":22,"cost":47,"grade":"ULTRA RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10243','{"class":"ICE","gender":"FEMALE","MOR":40,"cost":14,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10231','{"class":"LIGHT","gender":"FEMALE","MOR":88,"cost":35,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10399','{"class":"WIND","gender":"FEMALE","MOR":90,"cost":43,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10050','{"class":"FIRE","gender":"MALE","MOR":28,"cost":9,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10073','{"class":"LIGHT","gender":"FEMALE","MOR":88,"cost":33,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10229','{"class":"FIRE","gender":"FEMALE","MOR":65,"cost":34,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10012','{"class":"WIND","gender":"FEMALE","MOR":45,"cost":12,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10219','{"class":"DARK","gender":"FEMALE","MOR":55,"cost":8,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10305','{"class":"FIRE","gender":"FEMALE","MOR":66,"cost":9,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10443','{"class":"ICE","gender":"FEMALE","MOR":75,"cost":8,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10024','{"class":"ICE","gender":"FEMALE","MOR":88,"cost":41,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10446','{"class":"FIRE","gender":"FEMALE","MOR":10,"cost":13,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10427','{"class":"FIRE","gender":"FEMALE","MOR":80,"cost":14,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10411','{"class":"ICE","gender":"FEMALE","MOR":80,"cost":9,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10058','{"class":"FIRE","gender":"FEMALE","MOR":75,"cost":54,"grade":"ULTRA RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10395','{"class":"WIND","gender":"FEMALE","MOR":87,"cost":15,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10213','{"class":"FIRE","gender":"FEMALE","MOR":52,"cost":44,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10175','{"class":"WIND","gender":"FEMALE","MOR":41,"cost":19,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10007','{"class":"WIND","gender":"FEMALE","MOR":44,"cost":20,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10257','{"class":"ICE","gender":"FEMALE","MOR":31,"cost":31,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10291','{"class":"DARK","gender":"FEMALE","MOR":78,"cost":54,"grade":"ULTRA RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10326','{"class":"DARK","gender":"FEMALE","MOR":1,"cost":55,"grade":"MYTHIC RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10288','{"class":"FIRE","gender":"FEMALE","MOR":6,"cost":30,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10282','{"class":"ICE","gender":"FEMALE","MOR":12,"cost":11,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10405','{"class":"LIGHT","gender":"FEMALE","MOR":89,"cost":18,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10452','{"class":"ICE","gender":"FEMALE","MOR":70,"cost":34,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10370','{"class":"ICE","gender":"MALE","MOR":12,"cost":19,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10368','{"class":"WIND","gender":"MALE","MOR":11,"cost":19,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10369','{"class":"ICE","gender":"MALE","MOR":1,"cost":36,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10358','{"class":"WIND","gender":"MALE","MOR":92,"cost":55,"grade":"ULTRA RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10351','{"class":"WIND","gender":"MALE","MOR":16,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10449','{"class":"WIND","gender":"MALE","MOR":12,"cost":6,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10422','{"class":"WIND","gender":"MALE","MOR":20,"cost":8,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10421','{"class":"WIND","gender":"MALE","MOR":9,"cost":13,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10396','{"class":"ICE","gender":"MALE","MOR":77,"cost":15,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10435','{"class":"FIRE","gender":"MALE","MOR":55,"cost":50,"grade":"ULTRA RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10127','{"class":"LIGHT","gender":"FEMALE","MOR":80,"cost":44,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10439','{"class":"WIND","gender":"FEMALE","MOR":75,"cost":45,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10355','{"class":"ICE","gender":"FEMALE","MOR":78,"cost":14,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10367','{"class":"ICE","gender":"FEMALE","MOR":80,"cost":25,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10440','{"class":"WIND","gender":"FEMALE","MOR":8,"cost":51,"grade":"ULTRA RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10267','{"class":"ICE","gender":"FEMALE","MOR":80,"cost":35,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10509','{"class":"WIND","gender":"FEMALE","MOR":55,"cost":33,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10301','{"class":"DARK","gender":"FEMALE","MOR":75,"cost":45,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10210','{"class":"WIND","gender":"MALE","MOR":55,"cost":30,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10143','{"class":"FIRE","gender":"MALE","MOR":10,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10144','{"class":"WIND","gender":"MALE","MOR":10,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10145','{"class":"ICE","gender":"MALE","MOR":10,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10146','{"class":"FIRE","gender":"MALE","MOR":10,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10147','{"class":"WIND","gender":"MALE","MOR":10,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10148','{"class":"ICE","gender":"MALE","MOR":10,"cost":20,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10149','{"class":"FIRE","gender":"MALE","MOR":10,"cost":20,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10150','{"class":"WIND","gender":"MALE","MOR":10,"cost":20,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10151','{"class":"ICE","gender":"MALE","MOR":10,"cost":30,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10152','{"class":"FIRE","gender":"MALE","MOR":10,"cost":30,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10153','{"class":"WIND","gender":"FEMALE","MOR":10,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10154','{"class":"ICE","gender":"FEMALE","MOR":10,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10155','{"class":"FIRE","gender":"FEMALE","MOR":10,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10156','{"class":"WIND","gender":"FEMALE","MOR":10,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10157','{"class":"ICE","gender":"FEMALE","MOR":10,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10158','{"class":"FIRE","gender":"FEMALE","MOR":10,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10159','{"class":"WIND","gender":"FEMALE","MOR":10,"cost":20,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10160','{"class":"ICE","gender":"FEMALE","MOR":10,"cost":20,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10161','{"class":"FIRE","gender":"FEMALE","MOR":10,"cost":20,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10162','{"class":"WIND","gender":"FEMALE","MOR":10,"cost":20,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10163','{"class":"ICE","gender":"FEMALE","MOR":10,"cost":30,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10164','{"class":"FIRE","gender":"FEMALE","MOR":10,"cost":30,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10165','{"class":"WIND","gender":"FEMALE","MOR":10,"cost":30,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10166','{"class":"DARK","gender":"FEMALE","MOR":10,"cost":30,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10167','{"class":"DARK","gender":"FEMALE","MOR":10,"cost":30,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10168','{"class":"DARK","gender":"FEMALE","MOR":10,"cost":30,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10082','{"class":"WIND","gender":"MALE","MOR":80,"cost":30,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10302','{"class":"WIND","gender":"FEMALE","MOR":10,"cost":20,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10196','{"class":"WIND","gender":"FEMALE","MOR":70,"cost":12,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10197','{"class":"WIND","gender":"FEMALE","MOR":70,"cost":12,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10198','{"class":"WIND","gender":"FEMALE","MOR":70,"cost":12,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10199','{"class":"WIND","gender":"FEMALE","MOR":70,"cost":16,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10116','{"class":"FIRE","gender":"FEMALE","MOR":80,"cost":35,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10335','{"class":"ABYSS","gender":"FEMALE","MOR":99,"cost":100,"grade":"MYTHIC RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10334','{"class":"VOID","gender":"FEMALE","MOR":100,"cost":185,"grade":"LEGENDARY RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10475','{"class":"DARK","gender":"MALE","MOR":10,"cost":45,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10476','{"class":"WIND","gender":"MALE","MOR":55,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10477','{"class":"WIND","gender":"MALE","MOR":55,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10478','{"class":"WIND","gender":"MALE","MOR":55,"cost":20,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10479','{"class":"ICE","gender":"MALE","MOR":55,"cost":20,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10480','{"class":"ICE","gender":"MALE","MOR":12,"cost":30,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10481','{"class":"ICE","gender":"MALE","MOR":12,"cost":30,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10482','{"class":"FIRE","gender":"MALE","MOR":3,"cost":30,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10483','{"class":"FIRE","gender":"MALE","MOR":7,"cost":30,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10484','{"class":"FIRE","gender":"MALE","MOR":4,"cost":30,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10485','{"class":"FIRE","gender":"FEMALE","MOR":24,"cost":20,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10486','{"class":"FIRE","gender":"FEMALE","MOR":54,"cost":20,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10487','{"class":"WIND","gender":"MALE","MOR":70,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10488','{"class":"ICE","gender":"MALE","MOR":3,"cost":45,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10489','{"class":"FIRE","gender":"MALE","MOR":13,"cost":30,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10490','{"class":"WIND","gender":"FEMALE","MOR":80,"cost":45,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10491','{"class":"ICE","gender":"FEMALE","MOR":80,"cost":45,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10492','{"class":"LIGHT","gender":"MALE","MOR":80,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10493','{"class":"LIGHT","gender":"FEMALE","MOR":82,"cost":30,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10494','{"class":"WIND","gender":"MALE","MOR":21,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10495','{"class":"ICE","gender":"MALE","MOR":18,"cost":20,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10496','{"class":"FIRE","gender":"MALE","MOR":6,"cost":30,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10497','{"class":"WIND","gender":"FEMALE","MOR":33,"cost":10,"grade":"NORMAL"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10498','{"class":"ICE","gender":"FEMALE","MOR":24,"cost":20,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10499','{"class":"FIRE","gender":"FEMALE","MOR":27,"cost":30,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10500','{"class":"DARK","gender":"FEMALE","MOR":0,"cost":20,"grade":"RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10501','{"class":"DARK","gender":"FEMALE","MOR":0,"cost":30,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10502','{"class":"DARK","gender":"FEMALE","MOR":50,"cost":45,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10503','{"class":"DARK","gender":"FEMALE","MOR":99,"cost":55,"grade":"ULTRA RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10504','{"class":"LIGHT","gender":"FEMALE","MOR":99,"cost":55,"grade":"ULTRA RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10505','{"class":"ICE","gender":"FEMALE","MOR":42,"cost":30,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10506','{"class":"ICE","gender":"FEMALE","MOR":23,"cost":30,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10507','{"class":"ICE","gender":"FEMALE","MOR":16,"cost":30,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10508','{"class":"FIRE","gender":"MALE","MOR":76,"cost":45,"grade":"SUPER RARE"}') on conflict(id) do update set definition=excluded.definition;

insert into public.battle_card_meta_v2(id,definition) values ('10510','{"class":"FIRE","gender":"FEMALE","MOR":34,"cost":30,"grade":"HIGH RARE"}') on conflict(id) do update set definition=excluded.definition;

-- END GENERATED PHASE2 STORY

create or replace function public._clear_enabled_v2(m text) returns boolean language sql stable security definer
set search_path=pg_catalog,public,pg_temp as $$ select coalesce((select enabled from public.battle_policy_v2 where mode=case when m='tower_sweep' then 'tower' else m end),false) $$;

create or replace function public._clear_access_v2(u uuid,m text,t text) returns boolean language sql stable security definer
set search_path=pg_catalog,public,pg_temp as $$
 select exists(select 1 from public.battle_clear_receipts_v2 where user_id=u and mode=m and target=t)
 or case when m='story' then coalesce((select cleared->split_part(t,':',1) @> to_jsonb(split_part(t,':',2)::int) from public.battle_legacy_access_v2 where user_id=u),false)
 when m='tower' then coalesce((select (tower_best->>split_part(t,':',1))::int >= split_part(t,':',2)::int from public.battle_legacy_access_v2 where user_id=u),false)
 else exists(select 1 from public.arcade_tut_claims where user_id=u and stage=t::int) end
$$;

create or replace function public._clear_grant_v2(u uuid,rw jsonb,kind text,ref_ text) returns jsonb language plpgsql security definer
set search_path=pg_catalog,public,pg_temp as $$
declare prior public.reward_claims; res jsonb:='{}'; k text; v jsonb; w jsonb; tk int; g jsonb;
begin
 if kind not in ('tutorial_v2','chapter_v2','star_v2','tower_v2') then raise exception 'invalid grant kind'; end if;
 for k,v in select * from jsonb_each(rw) loop
  if k not in ('gold','blood','shard','soul','gem','tickets') or jsonb_typeof(v)<>'number' or v::text !~ '^[0-9]+$' or v::numeric>2147483647 then raise exception 'invalid reward'; end if;
 end loop;
 perform pg_advisory_xact_lock(hashtext('gem:'||u::text));
 select * into prior from public.reward_claims where user_id=u and reward_kind=kind and source_or_period=ref_;
 if found then return prior.result; end if;
 insert into public.reward_claims(user_id,reward_kind,source_or_period,reward,rule_version) values(u,kind,ref_,rw,3);
 w:=rw-'gem'-'tickets'; if w<>'{}' then res:=res||jsonb_build_object('wallet',public._wallet_add(u,w,kind)); end if;
 if coalesce((rw->>'gem')::int,0)>0 then
  g:=public._gem_add(u,(rw->>'gem')::int,0,kind,'p2:'||ref_,jsonb_build_object('validation','plausibility-v3'));
  res:=res||jsonb_build_object('gem',g->'gem');
 end if;
 if coalesce((rw->>'tickets')::int,0)>0 then
  insert into public.story_gacha(user_id,last_draw) values(u,public._gem_day()-1) on conflict do nothing;
  update public.story_gacha set tickets=tickets+(rw->>'tickets')::int,updated_at=now() where user_id=u returning tickets into tk;
  res:=res||jsonb_build_object('tickets',tk);
 end if;
 res:=res||jsonb_build_object('gave',rw);
 update public.reward_claims set result=res where user_id=u and reward_kind=kind and source_or_period=ref_;
 return res;
end $$;

create or replace function public._clear_session_v2(s public.battle_sessions_v2) returns jsonb language sql stable security definer
set search_path=pg_catalog,public,pg_temp as $$
 select jsonb_build_object('ok',true,'session',s.id,'mode',s.mode,'target',s.target,'seed',s.seed,
 'rule_version',3,'validation','plausibility-v3','issued_at',s.issued_at,'expires_at',s.expires_at,
 'status',s.status,'min_seconds',(s.snapshot->>'min_seconds')::numeric,'snapshot',s.snapshot,
 'data',case when s.mode='story' then (select data from public.story_progress where user_id=s.user_id) else null end)
$$;

create or replace function public._clear_close_v2(s public.battle_sessions_v2,st text) returns void language plpgsql security definer
set search_path=pg_catalog,public,pg_temp as $$
declare d jsonb;
begin
 if s.status<>'issued' then return; end if;
 if s.mode='story' then
  d:=public._story_lock(s.user_id);
  if d->'battle'->>'session'=s.id::text then perform public._phase2_old_story_abort_phase(); end if;
 end if;
 update public.battle_sessions_v2 set status=st,finished_at=clock_timestamp() where id=s.id and status='issued';
end $$;

create or replace function public.battle_session_start_v2(p_mode text,p_target text,p_party jsonb,p_request uuid) returns jsonb
language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare u uuid:=auth.uid(); s public.battle_sessions_v2; old public.battle_sessions_v2; cfg jsonb; d jsonb; variant_ text;
 ch int; ph int; fl int; tw text; r public.tower_progress; cards jsonb:='[]'; o jsonb; x text; cid text; ids text[]:='{}';
 forced jsonb; allowed jsonb; pp jsonb; v text; snap jsonb; cost int:=0; mana_ int; seed_ int; min_ numeric; lv int; max_ int;
begin
 if u is null then raise exception 'login required'; end if;
 if p_mode is null or not public._clear_enabled_v2(p_mode) then raise exception 'reward verification pending'; end if;
 if p_target is null or length(p_target)>40 or p_request is null or jsonb_typeof(p_party) is distinct from 'array'
 or jsonb_array_length(p_party)>10 or octet_length(p_party::text)>2048
 or exists(select 1 from jsonb_array_elements(p_party) a where jsonb_typeof(a)<>'string') then raise exception 'invalid battle request'; end if;
 perform pg_advisory_xact_lock(hashtext('battle-v2:'||u::text));
 perform pg_advisory_xact_lock(hashtext('gem:'||u::text));
 select * into s from public.battle_sessions_v2 where user_id=u and request_id=p_request for update;
 if found then
  if s.mode<>p_mode or s.target<>p_target or s.party<>p_party then raise exception 'request conflict'; end if;
  if s.status='issued' and s.expires_at<=clock_timestamp() then perform public._clear_close_v2(s,'expired'); select * into s from public.battle_sessions_v2 where id=s.id; end if;
  return public._clear_session_v2(s);
 end if;
 if (select count(*) from public.battle_sessions_v2 where user_id=u and issued_at >= (public._gem_day()::timestamp at time zone 'Asia/Seoul'))>=500 then raise exception 'session issuance limit'; end if;
 insert into public.battle_legacy_access_v2(user_id) values(u) on conflict do nothing;
 -- Starting a different battle replaces/refunds an unfinished story battle exactly
 -- as before; the old token becomes unusable. Reissued stage keeps the same seed.
 for old in select * from public.battle_sessions_v2 where user_id=u and status='issued' for update loop
  perform public._clear_close_v2(old,case when old.expires_at<=clock_timestamp() then 'expired' else 'aborted' end);
 end loop;
 d:=public._story_lock(u); lv:=(public._player_sync(u)).level;
 if p_mode='tutorial' then
  if p_target!~'^[1-3]$' or p_party<>'[]' then raise exception 'invalid tutorial stage or party'; end if;
  ph:=p_target::int;
  if ph>1 and not public._clear_access_v2(u,'tutorial',(ph-1)::text) then raise exception 'previous tutorial first'; end if;
  select definition into cfg from public.battle_tutorial_defs_v2 where stage=ph;
  min_:=3;
 elsif p_mode='story' then
  if p_target!~'^(0|[1-9][0-9]?):[1-9][0-9]?$' then raise exception 'invalid story target'; end if;
  ch:=split_part(p_target,':',1)::int; ph:=split_part(p_target,':',2)::int;
  select definition into cfg from public.battle_story_defs_v2 where chapter=ch and phase=ph and variant='';
  if cfg is null then raise exception 'invalid phase'; end if;
  variant_:=case cfg->>'variantKind' when 'starter' then d->>'starter' when 'route' then d->'routes'->>ch::text else '' end;
  if coalesce(variant_,'')<>'' then select definition into cfg from public.battle_story_defs_v2 where chapter=ch and phase=ph and variant=variant_; end if;
  if cfg is null then raise exception 'invalid story variant'; end if;
  if exists(select 1 from public.story_phase_config c where (c.chapter<ch or(c.chapter=ch and c.phase<ph)) and (c.chapter<>0 or ch=0)
   and not public._clear_access_v2(u,'story',c.chapter::text||':'||c.phase::text)) then raise exception 'phase locked'; end if;
  if cfg->>'variantKind' in ('starter','route') and coalesce(variant_,'')='' then raise exception 'story variant required'; end if;
  pp:=coalesce(cfg->'party','{}'); forced:=coalesce(pp->'forced','[]');
  allowed:=forced||coalesce(pp->'guests','[]')||coalesce(cfg->'loan','[]')||coalesce(cfg->'reserve','[]');
  min_:=public._story_min_battle_secs();
  max_:=case when coalesce((cfg->>'tutorial')::boolean,false) and not coalesce((cfg->>'pool')::boolean,false) then 5 else 10 end;
  if coalesce((pp->>'solo')::boolean,false) then max_:=greatest(1,jsonb_array_length(forced)); end if;
  max_:=least(max_,coalesce((pp->>'max')::int,max_));
  if jsonb_array_length(p_party) not between 1 and max_ then raise exception 'party size'; end if;
 else
  if p_target!~'^(normal|wind|ice|fire|light|dark):[1-9][0-9]{0,2}$' then raise exception 'invalid tower target'; end if;
  tw:=split_part(p_target,':',1); fl:=split_part(p_target,':',2)::int;
  r:=public._tower_row(u,tw); perform public._tower_gate(u,tw,r);
  if fl>public._tower_max_floor(tw) or (fl>1 and not public._clear_access_v2(u,'tower',tw||':'||(fl-1)::text)) then raise exception 'floor locked'; end if;
  if p_mode='tower_sweep' and (fl%10=0 or fl<>r.best_floor+1) then raise exception 'boss floor or stale sweep'; end if;
  if jsonb_array_length(p_party) not between 1 and 5 then raise exception 'party size'; end if;
  cfg:=jsonb_build_object('tower',tw,'floor',fl); min_:=case when p_mode='tower_sweep' then public._quest_sweep_secs() else public._quest_min_secs() end;
 end if;
 if p_mode<>'tutorial' then
  for x in select jsonb_array_elements_text(p_party) loop
   o:=null;
   if x like 'guest:lend:%' then
    select jsonb_build_object('uid',x,'id',card_id,'guest',true,'level',snap->'level','loan',snap) into o from public.guild_loans
     where borrower=u and id::text=substr(x,12) and expires_at>now();
   elsif x like 'guest:%' then
    cid:=substr(x,7);
    if p_mode<>'story' or not allowed @> to_jsonb(cid) then raise exception 'guest not allowed'; end if;
    o:=jsonb_build_object('uid',x,'id',cid,'guest',true,'level',coalesce((pp->'fixedLevel'->>cid)::int,(pp->'levels'->>cid)::int,lv));
   else o:=public._pvp_snap(u,jsonb_build_array(x),'open')->'cards'->0;
   end if;
   if o is null then raise exception 'card not owned or loan expired'; end if;
   cid:=o->>'id';
   if p_mode='story' and not forced @> to_jsonb(cid) and not coalesce(pp->'guests','[]') @> to_jsonb(cid) then
    if coalesce((pp->>'solo')::boolean,false) or coalesce((pp->>'noExtra')::boolean,false) or coalesce(pp->'exclude','[]') @> to_jsonb(cid)
      or (pp ? 'only' and not pp->'only' @> to_jsonb(cid)) then raise exception 'party restriction'; end if;
    select definition into snap from public.battle_card_meta_v2 where id=cid;
    if (coalesce((pp->>'noMale')::boolean,false) and snap->>'gender'='MALE')
      or (coalesce((pp->>'noFemale')::boolean,false) and snap->>'gender'='FEMALE')
      or (pp ? 'maxMor' and (snap->>'MOR')::numeric > (pp->>'maxMor')::numeric)
      or (pp ? 'costBelow' and (snap->>'cost')::numeric >= (pp->>'costBelow')::numeric)
      or (pp ? 'onlyClass' and snap->>'class'<>pp->>'onlyClass')
      or coalesce(pp->'banClass','[]') @> to_jsonb(snap->>'class')
      or (pp ? 'maxGrade' and array_position(array['NORMAL','RARE','HIGH RARE','SUPER RARE','ULTRA RARE','MYTHIC RARE','LEGENDARY RARE'],snap->>'grade') > array_position(array['NORMAL','RARE','HIGH RARE','SUPER RARE','ULTRA RARE','MYTHIC RARE','LEGENDARY RARE'],pp->>'maxGrade'))
      then raise exception 'party restriction'; end if;
   end if;
   if cid=any(ids) then raise exception 'duplicate card'; end if;
   ids:=ids||cid; cards:=cards||jsonb_build_array(o);
   if p_mode like 'tower%' and tw<>'normal' and not exists(select 1 from public.battle_card_meta_v2 where id=cid and definition->>'class'=upper(tw)) then raise exception 'tower element'; end if;
  end loop;
  if p_mode='story' then
   for v in select jsonb_array_elements_text(forced) loop if not v=any(ids) then raise exception 'required card missing'; end if; end loop;
   -- Reserve cards are server-defined participants, never arbitrary XP targets.
   for v in select jsonb_array_elements_text(coalesce(cfg->'reserve','[]')) loop
    select o0 into o from jsonb_array_elements(public._story_owned(d)) o0 where o0->>'id'=v order by (o0->>'uid'=d->>'leader') desc nulls last,coalesce((o0->>'ex')::int,0) desc,coalesce((o0->>'level')::int,1) desc limit 1;
    if o is not null and not v=any(ids) then cards:=cards||jsonb_build_array(public._pvp_snap(u,jsonb_build_array(o->>'uid'),'open')->'cards'->0); end if;
   end loop;
   d:=public._phase2_old_story_start_phase(ch,ph); cost:=coalesce((d->'battle'->>'stamina')::int,0);
   if not coalesce((cfg->>'tutorial')::boolean,false) or coalesce((cfg->>'pool')::boolean,false) then
    mana_:=coalesce((cfg->>'mana')::int,80+15*ch+2*lv+case when cfg->>'type'='boss' then 40 else 0 end+coalesce((cfg->>'manaBonus')::int,0));
   end if;
  end if;
 end if;
 insert into public.battle_session_seeds_v2(user_id,mode,target,seed) values(u,p_mode,p_target,1+floor(random()*2147483646)::int) on conflict do nothing;
 select seed into seed_ from public.battle_session_seeds_v2 where user_id=u and mode=p_mode and target=p_target and rule_version=3;
 snap:=jsonb_build_object('stage',cfg,'cards',cards,'player_level',lv,'starter',d->'starter','leader',d->'leader','cost',cost,'mana',mana_,'min_seconds',min_);
 insert into public.battle_sessions_v2(user_id,request_id,mode,target,party,seed,snapshot) values(u,p_request,p_mode,p_target,p_party,seed_,snap) returning * into s;
 if p_mode='story' then perform public._story_save(u,jsonb_set(d,'{battle,session}',to_jsonb(s.id::text))); end if;
 if p_mode like 'tower%' then insert into public.battle_events_v2(session_id,user_id,mode,win,skills,day,week) values(s.id,u,'tower',false,0,public._gem_day(),public._weekly_week()); end if;
 return public._clear_session_v2(s);
end $$;

create or replace function public.arcade_tut_status() returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,pg_temp as $$
declare u uuid:=auth.uid(); begin
 if u is null then raise exception 'login required'; end if;
 return jsonb_build_object('ok',true,'reward_held',not public._clear_enabled_v2('tutorial'),
 'claimed',coalesce((select jsonb_agg(stage order by stage) from public.arcade_tut_claims where user_id=u),'[]'),
 'completed',coalesce((select jsonb_agg(target::int order by target::int) from public.battle_clear_receipts_v2 where user_id=u and mode='tutorial'),'[]'),
 'rewards',jsonb_build_object('1',public._arcade_tut_rw(1),'2',public._arcade_tut_rw(2),'3',public._arcade_tut_rw(3)));
end $$;

create or replace function public.arcade_tut_claim(p_stage int) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare u uuid:=auth.uid(); rw jsonb:=public._arcade_tut_rw(p_stage); r jsonb; k text; n int;
begin
 if u is null then raise exception 'login required'; end if;
 perform pg_advisory_xact_lock(hashtext('battle-v2:'||u::text)); perform pg_advisory_xact_lock(hashtext('gem:'||u::text));
 if rw is null then raise exception 'invalid tutorial stage'; end if;
 k:=rw->>'kind'; n:=(rw->>'n')::int;
 if exists(select 1 from public.arcade_tut_claims where user_id=u and stage=p_stage) then return jsonb_build_object('ok',true,'already',true,'stage',p_stage,'kind',k); end if;
 if not public._clear_enabled_v2('tutorial') then raise exception 'reward verification pending'; end if;
 if not exists(select 1 from public.battle_clear_receipts_v2 where user_id=u and mode='tutorial' and target=p_stage::text) then raise exception 'verified tutorial session required'; end if;
 r:=public._clear_grant_v2(u,jsonb_build_object(k,n),'tutorial_v2','arcade_tut:'||p_stage);
 insert into public.arcade_tut_claims(user_id,stage,tickets,kind) values(u,p_stage,n,k);
 return r||jsonb_build_object('ok',true,'kind',k,'stage',p_stage,'gave',n);
end $$;

create or replace function public._story_ticket_sync(uid uuid) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare ch int; got int[]; added int:=0; chapters jsonb:='[]'; rw jsonb; r jsonb; tk int;
begin
 if uid is null then raise exception 'login required'; end if;
 perform pg_advisory_xact_lock(hashtext('gem:'||uid::text));
 insert into public.story_gacha(user_id,last_draw) values(uid,public._gem_day()-1) on conflict do nothing;
 select ticket_chapters into got from public.story_gacha where user_id=uid for update;
 if public._clear_enabled_v2('story') then
 for ch in select chapter from public.story_phase_config c group by chapter having bool_and(exists(
  select 1 from public.battle_clear_receipts_v2 v where v.user_id=uid and v.mode='story' and v.target=c.chapter::text||':'||c.phase::text)) order by chapter loop
  if exists(select 1 from public.reward_claims where user_id=uid and reward_kind='chapter_v2' and source_or_period='chapter:'||ch) then continue; end if;
  rw:=jsonb_build_object('tickets',case when ch=any(got) then 0 else 10 end,'gem',case when exists(
   select 1 from public.gem_ledger where user_id=uid and ref='chapter:'||ch) then 0 else public._gem_chapter_reward() end);
  r:=public._clear_grant_v2(uid,rw,'chapter_v2','chapter:'||ch);
  if not ch=any(got) then got:=got||ch; end if;
  added:=added+(rw->>'tickets')::int; chapters:=chapters||to_jsonb(ch);
 end loop; end if;
 update public.story_gacha set ticket_chapters=got where user_id=uid returning tickets into tk;
 return jsonb_build_object('tickets',tk,'added',added,'chapters',chapters,'reward_held',not public._clear_enabled_v2('story'));
end $$;

create or replace function public.battle_session_finish_v2(p_session uuid,p_report jsonb) returns jsonb language plpgsql security definer
set search_path=pg_catalog,public,pg_temp as $$
declare u uuid:=auth.uid(); s public.battle_sessions_v2; cfg jsonb; d jsonb; res jsonb:='{}'; x jsonb; o jsonb; stats jsonb:='[]';
 tr int; mt int; skills_ int; cap_ int; win_ boolean; clear_ boolean; reason_ text; ch int; ph int; stars_ int:=0; mana_ int; maxmana int;
 kills_ int; blocks_ int; ksum int:=0; bsum int:=0; seen text[]:='{}'; uid_ text; tw text; fl int; tp public.tower_progress;
 first_ boolean; rw jsonb; cur jsonb; pay jsonb:='{}'; baseline int; key_ text; daily_n int;
begin
 if u is null then raise exception 'login required'; end if;
 perform pg_advisory_xact_lock(hashtext('battle-v2:'||u::text)); perform pg_advisory_xact_lock(hashtext('gem:'||u::text));
 select * into s from public.battle_sessions_v2 where id=p_session and user_id=u for update;
 if not found then raise exception 'battle session not found'; end if;
 if s.status='settled' then if s.submission is distinct from p_report then raise exception 'submission conflict'; end if; return s.settlement; end if;
 if s.status<>'issued' then raise exception 'battle session closed'; end if;
 if s.expires_at<=clock_timestamp() then perform public._clear_close_v2(s,'expired'); return jsonb_build_object('ok',false,'session',s.id,'status','expired','reward_held',true); end if;
 if not public._clear_enabled_v2(s.mode) then raise exception 'reward verification pending'; end if;
 if clock_timestamp()-s.issued_at < make_interval(secs=>(s.snapshot->>'min_seconds')::double precision) then raise exception 'too fast'; end if;
 if jsonb_typeof(p_report) is distinct from 'object' or octet_length(p_report::text)>32768 or exists(select 1 from jsonb_object_keys(p_report) k where k not in ('win','reason','turns','my_turns','mana','skills','cards'))
 or jsonb_typeof(p_report->'win') is distinct from 'boolean' then raise exception 'invalid report'; end if;
 foreach key_ in array array['turns','my_turns','skills'] loop
  if jsonb_typeof(p_report->key_) is distinct from 'number' or p_report->>key_ !~ '^[0-9]{1,4}$' then raise exception 'invalid stats'; end if;
 end loop;
 tr:=(p_report->>'turns')::int; mt:=(p_report->>'my_turns')::int; skills_:=(p_report->>'skills')::int;
 cfg:=s.snapshot->'stage'; win_:=(p_report->>'win')::boolean; reason_:=coalesce(p_report->>'reason','');
 cap_:=case when s.mode='tutorial' then 400 else coalesce((cfg->'rules'->>'maxTurns')::int,40) end;
 if (mt=0 and skills_>0) or tr>cap_ or mt>ceil(tr/2.0)::int or mt<greatest(0,floor(tr/2.0)::int-1) or mt>tr or skills_>least(2000,(mt+1)*greatest(1,jsonb_array_length(s.snapshot->'cards'))*5+20)
 or (win_ and reason_='giveup') or length(reason_)>40 then raise exception 'implausible turns or skills'; end if;
 -- Field-entry passives can legitimately win story/manual tower before turn 1.
 if s.mode in ('tower_sweep','tutorial') and win_ and tr<1 then raise exception 'implausible zero-turn win'; end if;
 if reason_ not in ('ko','wipe','survive','timeout','giveup','mustlive','mustsummon','hp','cards','draw')
 or (win_ and reason_ in ('timeout','giveup','mustlive','mustsummon','draw'))
 or (reason_='survive' and (not win_ or cfg->'rules'->>'survive' is null or tr<2*(cfg->'rules'->>'survive')::int)) then raise exception 'implausible end reason'; end if;
 if (select count(*) from public.battle_events_v2 where user_id=u and day=public._gem_day() and session_id<>s.id)>=500 then raise exception 'completion rate limit'; end if;
 clear_:=win_ or (s.mode='story' and coalesce((cfg->>'loseClears')::boolean,false) and reason_ not in ('giveup',''));
 if s.mode='story' then
  ch:=split_part(s.target,':',1)::int; ph:=split_part(s.target,':',2)::int;
  d:=public._story_lock(u);
  if d->'battle'->>'session' is distinct from s.id::text then raise exception 'battle not started'; end if;
  if clear_ then
   if jsonb_typeof(p_report->'cards') is distinct from 'array' or jsonb_array_length(p_report->'cards')>30 then raise exception 'invalid card stats'; end if;
   select enemy_count into cap_ from public.story_phase_config where chapter=ch and phase=ph;
   for x in select * from jsonb_array_elements(p_report->'cards') loop
    uid_:=x->>'uid';
    if uid_ is null or uid_=any(seen) then raise exception 'duplicate or missing participant'; end if;
    seen:=seen||uid_; select c into o from jsonb_array_elements(s.snapshot->'cards') c where c->>'uid'=uid_ and not coalesce((c->>'guest')::boolean,false);
    if o is null then raise exception 'unselected XP participant'; end if;
    if jsonb_typeof(x->'kills') is distinct from 'number' or x->>'kills' !~ '^[0-9]{1,3}$' or jsonb_typeof(x->'blocks') is distinct from 'number' or x->>'blocks' !~ '^[0-9]{1,3}$' then raise exception 'invalid card stats'; end if;
    kills_:=(x->>'kills')::int; blocks_:=(x->>'blocks')::int;
    if kills_>200 or blocks_>200 then raise exception 'implausible card stats'; end if;
    kills_:=least(kills_,greatest(0,cap_-ksum)); ksum:=ksum+kills_;
    blocks_:=least(blocks_,3,greatest(0,cap_*2-bsum)); bsum:=bsum+blocks_;
    stats:=stats||jsonb_build_object('uid',uid_,'kills',kills_,'blocks',blocks_);
   end loop;
   maxmana:=(s.snapshot->>'mana')::int;
   if maxmana is not null then
    if jsonb_typeof(p_report->'mana') is distinct from 'number' or p_report->>'mana' !~ '^[0-9]{1,5}$' then raise exception 'invalid mana'; end if;
    mana_:=(p_report->>'mana')::int; if mana_>maxmana then raise exception 'implausible mana'; end if;
    stars_:=1+case when mt<=coalesce((cfg->>'starTurns')::int,10) then 1 else 0 end+case when mana_>=ceil(maxmana*coalesce((cfg->>'starMana')::numeric,0.3)) then 1 else 0 end;
   end if;
   if coalesce((cfg->>'loseClears')::boolean,false) then stars_:=3; end if;
   res:=public._phase2_old_story_complete_phase(ch,ph,stats);
   insert into public.battle_clear_receipts_v2(user_id,mode,target,session_id,stars) values(u,'story',s.target,s.id,stars_)
    on conflict(user_id,mode,target) do update set stars=greatest(battle_clear_receipts_v2.stars,excluded.stars);
   d:=res->'data';
   if stars_>0 then
    if jsonb_typeof(d->'stars') is distinct from 'object' then d:=jsonb_set(d,'{stars}','{}'); end if;
    if jsonb_typeof(d->'stars'->ch::text) is distinct from 'object' then d:=jsonb_set(d,array['stars',ch::text],'{}'); end if;
    d:=jsonb_set(d,array['stars',ch::text,ph::text],to_jsonb(greatest(stars_,coalesce((d->'stars'->ch::text->>ph::text)::int,0))));
    d:=public._story_save(u,d); res:=res||jsonb_build_object('data',d);
   end if;
   if res->>'reward_id' is not null then
    insert into public.battle_acquisitions_v2(session_id,user_id,card_id) values(s.id,u,res->>'reward_id');
    insert into public.gallery(user_id,card_id,count,mvp_count) values(u,res->>'reward_id',0,0) on conflict do nothing;
   end if;
   res:=res||jsonb_build_object('stars',stars_,'chapter_reward',public._story_ticket_sync(u));
  else
   res:=public._phase2_old_story_abort_phase(); res:=jsonb_build_object('player',res,'win',false);
  end if;
 elsif s.mode='tutorial' then
  if clear_ then
   insert into public.battle_clear_receipts_v2(user_id,mode,target,session_id) values(u,'tutorial',s.target,s.id) on conflict do nothing;
   res:=public.arcade_tut_claim(s.target::int);
  end if;
 else
  tw:=split_part(s.target,':',1); fl:=split_part(s.target,':',2)::int; tp:=public._tower_row(u,tw);
  if clear_ then
   if tp.day_floors>=public._tower_daily(tw) then raise exception 'daily limit'; end if;
   if fl>1 and not public._clear_access_v2(u,'tower',tw||':'||(fl-1)::text) then raise exception 'floor locked'; end if;
   baseline:=coalesce((select (tower_paid->>tw)::int from public.battle_legacy_access_v2 where user_id=u),0);
   first_:=fl>baseline and not exists(select 1 from public.battle_clear_receipts_v2 where user_id=u and mode='tower' and target=s.target);
   rw:=case when first_ then public._tower_reward(tw,fl) else '{}'::jsonb end;
   cur:=case when first_ then public._tower_currency(tw,fl) else '{}'::jsonb end;
   if first_ then pay:=public._clear_grant_v2(u,rw||cur,'tower_v2','tower:'||s.target); end if;
   insert into public.battle_clear_receipts_v2(user_id,mode,target,session_id) values(u,'tower',s.target,s.id) on conflict do nothing;
   update public.tower_progress set battle=null,clears=clears+1,day_floors=day_floors+1,best_floor=greatest(best_floor,fl),
    paid_floor=case when first_ then greatest(paid_floor,fl) else paid_floor end,
    rewards=(select jsonb_object_agg(k,coalesce((rewards->>k)::int,0)+coalesce((rw->>k)::int,0)+coalesce((cur->>k)::int,0)) from unnest(array['tickets','gold','blood','shard','soul']) k),updated_at=now()
    where user_id=u and tower=tw;
   res:=jsonb_build_object('tower',tw,'floor',fl,'best_floor',greatest(tp.best_floor,fl),'first',first_,'paid',first_,'reward',rw,'currency',cur,'tickets',pay->'tickets','today',tp.day_floors+1,'daily',public._tower_daily(tw));
  end if;
 end if;
 if s.mode<>'tutorial' then insert into public.battle_events_v2(session_id,user_id,mode,win,skills,day,week)
  values(s.id,u,case when s.mode='tower_sweep' then 'tower' else s.mode end,win_,skills_,public._gem_day(),public._weekly_week())
 on conflict(session_id) do update set win=excluded.win,skills=excluded.skills; end if;
 res:=res||jsonb_build_object('ok',true,'session',s.id,'status','settled','win',win_,'cleared',clear_,'reward_held',false,'validation','plausibility-v3');
 update public.battle_sessions_v2 set status='settled',submission=p_report,settlement=res,finished_at=clock_timestamp() where id=s.id;
 return res;
end $$;

create or replace function public.battle_session_status_v2(p_session uuid) returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,pg_temp as $$
declare s public.battle_sessions_v2; begin
 if auth.uid() is null then raise exception 'login required'; end if;
 select * into s from public.battle_sessions_v2 where id=p_session and user_id=auth.uid();
 if not found then raise exception 'battle session not found'; end if;
 return public._clear_session_v2(s)||jsonb_build_object('settlement',s.settlement);
end $$;

create or replace function public.battle_session_abort_v2(p_session uuid) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare u uuid:=auth.uid(); s public.battle_sessions_v2; begin
 if u is null then raise exception 'login required'; end if;
 perform pg_advisory_xact_lock(hashtext('battle-v2:'||u::text)); perform pg_advisory_xact_lock(hashtext('gem:'||u::text));
 select * into s from public.battle_sessions_v2 where id=p_session and user_id=u for update;
 if not found then raise exception 'battle session not found'; end if;
 perform public._clear_close_v2(s,'aborted');
 select * into s from public.battle_sessions_v2 where id=p_session;
 return public._clear_session_v2(s)||jsonb_build_object('player',case when s.mode='story' then public._player_json(u) else null end);
end $$;

create or replace function public._clear_mission_prog_v2(u uuid,k text,w boolean) returns int language sql stable security definer set search_path=pg_catalog,public,pg_temp as $$
 select coalesce(case k when 'skill' then sum(skills) else count(*) end,0)::int from public.battle_events_v2
 where user_id=u and (case when w then week=public._weekly_week() else day=public._gem_day() end)
 and case k when 'win' then win when 'story' then mode='story' and win when 'tower' then mode='tower' when 'skill' then true else false end
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
  missions:=missions||jsonb_build_array(m||jsonb_build_object('prog',least(n,(m->>'goal')::int),'held',m->>'key'='arcade','claimed',claimed_ ? (m->>'key')));
 end loop;
 res:=jsonb_build_object('ok',true,'reward_held',false,'missions',missions,'next_reset',((period_+case when w then 7 else 1 end)::timestamp at time zone 'Asia/Seoul'),
 'all',jsonb_build_object('reward',case when w then public._weekly_all_reward() else public._daily_all_reward() end,'done',done_,'goal',jsonb_array_length(defs),'claimed',claimed_ ? 'all','held',true));
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
 if k in ('arcade','all') then raise exception 'reward verification pending'; end if;
 select x into m from jsonb_array_elements(case when w then public._weekly_defs() else public._daily_defs() end) x where x->>'key'=k;
 if m is null then raise exception 'invalid mission'; end if;
 if public._clear_mission_prog_v2(u,k,w)<(m->>'goal')::int then raise exception 'not done'; end if;
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

create or replace function public._star_chapter(d jsonb,p_chapter int) returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,pg_temp as $$
declare mx int; tot int; got jsonb:=coalesce(d->'starClaims'->p_chapter::text,'[]'); ms jsonb:='[]'; m jsonb; need_ int;
begin
 select 3*count(*) into mx from public.story_phase_config where chapter=p_chapter and (p_chapter>=1 or phase=4);
 select coalesce(sum(v.stars),0)::int into tot from public.battle_clear_receipts_v2 v join public.story_phase_config c
  on v.target=c.chapter::text||':'||c.phase::text where v.user_id=auth.uid() and v.mode='story' and c.chapter=p_chapter and (p_chapter>=1 or c.phase=4);
 for m in select * from jsonb_array_elements(public._star_milestones()) loop
  need_:=coalesce((m->>'need')::int,mx);
  if mx=0 or need_>mx or (m->>'key'<>'all' and need_>=mx) then continue; end if;
  ms:=ms||jsonb_build_array(m||jsonb_build_object('need',need_,'claimed',got @> to_jsonb(m->>'key'),'ready',tot>=need_ and public._clear_enabled_v2('story'),'held',not public._clear_enabled_v2('story')));
 end loop;
 return jsonb_build_object('chapter',p_chapter,'total',tot,'max',mx,'milestones',ms);
end $$;

create or replace function public.story_star_claim(p_chapter int,p_key text) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare u uuid:=auth.uid(); d jsonb; m jsonb; st jsonb; res jsonb;
begin
 if u is null then raise exception 'login required'; end if;
 perform pg_advisory_xact_lock(hashtext('battle-v2:'||u::text)); perform pg_advisory_xact_lock(hashtext('gem:'||u::text));
 if not public._clear_enabled_v2('story') then raise exception 'reward verification pending'; end if;
 d:=public._story_lock(u); st:=public._star_chapter(d,p_chapter);
 select x into m from jsonb_array_elements(st->'milestones') x where x->>'key'=p_key;
 if m is null then raise exception 'invalid milestone'; end if;
 if (m->>'claimed')::boolean then raise exception 'already claimed'; end if;
 if not (m->>'ready')::boolean then raise exception 'not enough stars'; end if;
 res:=public._clear_grant_v2(u,jsonb_build_object('tickets',(m->>'tickets')::int,'gold',(m->>'gold')::int),'star_v2','star:'||p_chapter||':'||p_key);
 if jsonb_typeof(d->'starClaims') is distinct from 'object' then d:=jsonb_set(d,'{starClaims}','{}'); end if;
 d:=public._story_save(u,jsonb_set(d,array['starClaims',p_chapter::text],coalesce(d->'starClaims'->p_chapter::text,'[]')||to_jsonb(p_key)));
 return res||jsonb_build_object('ok',true,'status',public._star_chapter(d,p_chapter));
end $$;

create or replace function public._gallery_have(p_uid uuid) returns int language sql stable security definer set search_path=pg_catalog,public,pg_temp as $$
 select count(*)::int from public.reward_card_catalog c where c.card_id in(
 select card_id from public.verified_game_events where user_id=p_uid and event_kind='card_acquired'
 union select card_id from public.battle_acquisitions_v2 where user_id=p_uid)
$$;

create or replace function public._ach_prog(p_uid uuid,p_id text) returns int language plpgsql stable security definer set search_path=pg_catalog,public,pg_temp as $$
declare n int; begin
 case p_id when 'story_ch' then select count(*)::int into n from public.reward_claims where user_id=p_uid and reward_kind='chapter_v2';
 when 'story_stars' then select sum(stars)::int into n from public.battle_clear_receipts_v2 where user_id=p_uid and mode='story';
 when 'skill_uses' then select sum(skills)::int into n from public.battle_events_v2 where user_id=p_uid;
 when 'tower_normal' then select max(split_part(target,':',2)::int) into n from public.battle_clear_receipts_v2 where user_id=p_uid and mode='tower' and target like 'normal:%';
 when 'tower_elem' then select max(split_part(target,':',2)::int) into n from public.battle_clear_receipts_v2 where user_id=p_uid and mode='tower' and split_part(target,':',1) in ('wind','ice','fire');
 when 'tower_light' then select max(split_part(target,':',2)::int) into n from public.battle_clear_receipts_v2 where user_id=p_uid and mode='tower' and split_part(target,':',1) in ('light','dark');
 else return public._phase2_old_ach_prog(p_uid,p_id); end case;
 return coalesce(n,0);
end $$;

do $$ declare src text; begin
 src:=pg_get_functiondef('public._ach_json(uuid)'::regprocedure);
 execute replace(src,'''gifts_sent'')','''gifts_sent'',''story_ch'',''story_stars'',''tower_normal'',''tower_elem'',''tower_light'',''skill_uses'')');
end $$;

-- Show held legacy floors so honest players can select and replay them for settlement.
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
end $$;

create or replace function public.story_sweep(p_chapter int,p_phase int,p_runs int default 1) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare u uuid:=auth.uid(); begin
 if u is null then raise exception 'login required'; end if;
 perform pg_advisory_xact_lock(hashtext('battle-v2:'||u::text)); perform pg_advisory_xact_lock(hashtext('gem:'||u::text));
 if not public._clear_enabled_v2('story') then raise exception 'reward verification pending'; end if;
 if not exists(select 1 from public.battle_clear_receipts_v2 where user_id=u and mode='story' and target=p_chapter::text||':'||p_phase::text) then raise exception 'verified clear required for sweep'; end if;
 return public._phase2_old_story_sweep(p_chapter,p_phase,p_runs);
end $$;

create or replace function public.story_abort_phase() returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare u uuid:=auth.uid(); s public.battle_sessions_v2; begin
 if u is null then raise exception 'login required'; end if;
 perform pg_advisory_xact_lock(hashtext('battle-v2:'||u::text)); perform pg_advisory_xact_lock(hashtext('gem:'||u::text));
 select * into s from public.battle_sessions_v2 where user_id=u and mode='story' and status='issued' for update;
 if found then perform public._clear_close_v2(s,'aborted'); end if;
 return public._player_json(u);
end $$;

do $acl$
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
end $acl$;

grant execute on function public.battle_session_start_v2(text,text,jsonb,uuid),public.battle_session_finish_v2(uuid,jsonb),public.battle_session_status_v2(uuid),public.battle_session_abort_v2(uuid),public.arcade_tut_claim(int),public.story_star_claim(int,text),public.story_sweep(int,int,int),public.daily_claim(text),public.weekly_claim(text),public.story_abort_phase() to authenticated;

notify pgrst,'reload schema';

-- ===== REVIEWED DELTA SOURCE: security_phase3_pvp.sql =====
create table if not exists public.pvp_policy_v3(
 singleton boolean primary key default true check(singleton), engine_hash text not null check(length(engine_hash)=64), enabled boolean not null default true);

insert into public.pvp_policy_v3(singleton,engine_hash) values(true,'5a38b4b72651fcb8632fb1bfe14e1cd18a758d08249dbb18b0cfd223123c7a67')
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
set search_path=pg_catalog,public,pg_temp as $$ declare r public.pvp_ratings_v3; begin
 insert into public.pvp_ratings_v3(user_id,league,mode,season) values(u,l,m,s) on conflict do nothing;
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

-- ===== REVIEWED DELTA SOURCE: security_phase4_raid_guildwar.sql =====
set local check_function_bodies=off;

create table if not exists public.guildbattle_policy_v4(singleton boolean primary key default true check(singleton),engine_hash text not null,enabled boolean not null default true);

insert into public.guildbattle_policy_v4(singleton,engine_hash) values(true,'c570973669776971316dfb650482e1401c5628c5ba73e57d23b879b9320c719a') on conflict(singleton) do update set engine_hash=excluded.engine_hash;

do $$ begin
 if not exists(select 1 from pvp_policy_v3) then raise exception 'STOP: install phases 1-3 first'; end if;
end $$;

create or replace function public._guildbattle_now_v4() returns timestamptz language sql stable security definer set search_path=pg_catalog,public,pg_temp as $$ select now() $$;

create or replace function public._raid_day_v4() returns date language sql stable security definer set search_path=pg_catalog,public,pg_temp as $$ select (_guildbattle_now_v4() at time zone 'Asia/Seoul')::date $$;

create or replace function public._raid_week_v4() returns date language sql stable security definer set search_path=pg_catalog,public,pg_temp as $$ select date_trunc('week',_raid_day_v4()::timestamp)::date $$;

create or replace function public._guildbattle_guard_v4() returns void language plpgsql stable security definer set search_path=pg_catalog,public,pg_temp as $$ begin if not exists(select 1 from guildbattle_policy_v4 where singleton and enabled) then raise exception 'reward verification pending'; end if; end $$;

create table if not exists public.guildbattle_sessions_v4(
 id bigint generated always as identity primary key,user_id uuid not null references auth.users(id),kind text not null check(kind in('raid','war')),attempt_id bigint not null,
 request_id uuid not null,control text not null check(control in('auto','actions')),engine_hash text not null,payload jsonb not null,snapshot jsonb not null,
 issued_at timestamptz not null default clock_timestamp(),expires_at timestamptz not null,status text not null default 'issued' check(status in('issued','settled')),
 submission jsonb,result jsonb,verified boolean not null default false,unique(user_id,kind,request_id),unique(kind,attempt_id));

create table if not exists public.guildbattle_events_v4(session_id bigint primary key references public.guildbattle_sessions_v4(id),user_id uuid not null,guild_id bigint not null,kind text not null,day date not null,metrics jsonb not null,at timestamptz not null default clock_timestamp());

create table if not exists public.guildbattle_sweeps_v4(user_id uuid not null,request_id uuid not null,result jsonb not null,guild_id bigint not null,day date not null,primary key(user_id,request_id));

-- Server-owned snapshot refresh; guest/loan cards remain disallowed, as before.
create or replace function public._war_refresh_v4(u uuid,s jsonb) returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,pg_temp as $$ declare ids jsonb; begin
 if s is null or jsonb_array_length(s)=0 then return null; end if;
 select jsonb_agg(c->>'uid' order by ord) into ids from jsonb_array_elements(s) with ordinality x(c,ord);
 return _pvp_snap(u,ids,'open')->'cards'; exception when others then return null; end $$;

-- ISOLATED VERIFIED TABLES: legacy rows remain untouched.
create table if not exists public.guild_raids_v4 (
  guild_id bigint not null references public.guilds(id) on delete cascade, week date not null,
  difficulty text not null default 'normal' check (difficulty in ('normal', 'hard', 'abyss')),
  members int not null, stage int not null default 1, hp_max bigint not null, hp_left bigint not null,
  total_damage bigint not null default 0, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  primary key (guild_id, week));

create table if not exists public.guild_raid_stages_v4 (
  guild_id bigint not null, week date not null, stage int not null, boss_id text, hp bigint not null,
  cleared_at timestamptz, last_hit uuid references auth.users(id) on delete set null,
  primary key (guild_id, week, stage), foreign key (guild_id, week) references public.guild_raids_v4(guild_id, week) on delete cascade);

create table if not exists public.guild_raid_attempts_v4 (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade, guild_id bigint not null, week date not null, day date not null,
  kind text not null check (kind in ('fight', 'sweep')), stage int not null, difficulty text not null,
  seed bigint, snap jsonb, reported bigint, damage bigint not null default 0, flagged boolean not null default false, voided boolean not null default false,
  started_at timestamptz not null default now(), finished_at timestamptz);

create table if not exists public.guild_raid_damage_v4 (
  guild_id bigint not null, week date not null, user_id uuid not null references auth.users(id) on delete cascade,
  damage bigint not null default 0, attempts int not null default 0, updated_at timestamptz not null default now(),
  primary key (guild_id, week, user_id));

create table if not exists public.war_decks_v4 (
  user_id uuid primary key references auth.users(id) on delete cascade,
  def1 jsonb, def2 jsonb, atk1 jsonb, atk2 jsonb, updated_at timestamptz not null default now());

create table if not exists public.war_entries_v4 (
  season date not null, guild_id bigint not null references public.guilds(id) on delete cascade,
  status text not null default 'in' check (status in ('in', 'out')), locked boolean not null default false, scale numeric not null default 1,
  points int not null default 0, wins int not null default 0, draws int not null default 0, losses int not null default 0, boss_kills int not null default 0, score_total int not null default 0,
  entered_at timestamptz not null default now(), primary key (season, guild_id));

create table if not exists public.war_roster_v4 (
  season date not null, guild_id bigint not null, slot int not null check (slot between 1 and 21), user_id uuid references auth.users(id) on delete set null,
  def_snap jsonb, primary key (season, guild_id, slot), foreign key (season, guild_id) references public.war_entries_v4(season, guild_id) on delete cascade);

create table if not exists public.war_matches_v4 (
  id bigint generated always as identity primary key, season date not null, day int not null check (day between 1 and 5),
  guild_a bigint not null, guild_b bigint, score_a int not null default 0, score_b int not null default 0,
  winner bigint, draw boolean not null default false, boss_kill boolean not null default false, ended_at timestamptz, settled boolean not null default false,
  unique (season, day, guild_a));

create table if not exists public.war_ajits_v4 (
  match_id bigint not null references public.war_matches_v4(id) on delete cascade, side int not null check (side in (0, 1)), slot int not null,
  role text not null, user_id uuid, npc boolean not null default false, snaps jsonb not null default '[]'::jsonb,
  deck int not null default 1, state jsonb, destroyed_at timestamptz, destroyed_by uuid, locked_by uuid, locked_until timestamptz,
  primary key (match_id, side, slot));

create table if not exists public.war_atk_state_v4 (
  match_id bigint not null references public.war_matches_v4(id) on delete cascade, user_id uuid not null, deck int not null check (deck in (1, 2)),
  snap jsonb not null, state jsonb, primary key (match_id, user_id, deck));

create table if not exists public.war_attacks_v4 (
  id bigint generated always as identity primary key, match_id bigint not null references public.war_matches_v4(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade, side int not null, target_slot int not null, atk_deck int not null, def_deck int not null,
  seed bigint not null, atk_snap jsonb not null, def_snap jsonb not null, atk_buff jsonb not null, def_buff jsonb not null,
  before jsonb not null, reported jsonb, win boolean, points int not null default 0, flagged boolean not null default false, voided boolean not null default false,
  started_at timestamptz not null default now(), finished_at timestamptz);

alter table guild_raid_attempts_v4 add column if not exists actions jsonb;

alter table war_attacks_v4 add column if not exists actions jsonb;

create unique index if not exists war_roster_user_v4 on war_roster_v4(season,user_id) where user_id is not null;

insert into war_decks_v4 select * from war_decks on conflict do nothing;

create or replace function public._guild_reward_v4(p_uid uuid, p_gid bigint, p_rw jsonb, p_reason text, p_ref text) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
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
end $$;

create or replace function public._raid_numbers_v4() returns jsonb language sql immutable as $$ select '{
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
}'::jsonb $$;

create or replace function public._raid_boss_v4(p_stage int) returns jsonb language sql immutable as $$
  select (array['{"id":"10325","name":"임유리","weak":"CHARGE"}', '{"id":"10326","name":"[각성] 임유리","weak":"DEFENSE"}',
                '{"id":"10062","name":"김신현","weak":"CRUSH"}', '{"id":"10060","name":"김성진","weak":"SUPPORT"}',
                '{"id":"10311","name":"이지영","weak":"DISTURB"}'])[((greatest(p_stage, 1) - 1) % 5) + 1]::jsonb $$;

create or replace function public._raid_now_v4() returns timestamptz language sql stable as $$ select public._guildbattle_now_v4() $$;

create or replace function public._raid_end_v4(p_week date) returns timestamptz language sql stable as $$ select ((p_week + 6)::timestamp + interval '22 hours') at time zone 'Asia/Seoul' $$;

create or replace function public._raid_hp_v4(p_diff text, p_members int, p_stage int) returns bigint language sql immutable as $$
  select round((_raid_numbers_v4()->'hp_per_member'->>p_diff)::numeric * greatest(p_members, (_raid_numbers_v4()->>'hp_min_members')::int)
               * power((_raid_numbers_v4()->>'hp_growth')::numeric, greatest(p_stage, 1) - 1))::bigint $$;

create or replace function public._raid_attempt_cap_v4(p_stage int) returns bigint language sql immutable as $$
  select round((_raid_numbers_v4()->>'hit_cap')::numeric * power((_raid_numbers_v4()->>'hit_cap_growth')::numeric, greatest(p_stage, 1) - 1)) * (_raid_numbers_v4()->>'attempt_hits')::int $$;

create or replace function public._raid_stage_reward_v4(p_diff text, p_stage int) returns jsonb language sql immutable as $$
  with n as (select _raid_numbers_v4() j), x as (select j->'stage' s, (j->'diff_mult'->>p_diff)::numeric m from n)
  select jsonb_strip_nulls(jsonb_build_object('loyalty', round((s->>'loyalty')::int * m)::int, 'gold', round((s->>'gold')::int * m)::int,
    'gem', round(((s->>'gem')::int + case when p_stage % 3 = 0 then (s->>'gem_every3')::int else 0 end) * m)::int,
    'tickets', case when p_stage % 5 = 0 then (s->>'tickets_every5')::int end)) from x $$;

create or replace function public._raid_rank_reward_v4(p_rank int) returns jsonb language sql immutable as $$
  select coalesce((select r->'reward' from jsonb_array_elements(_raid_numbers_v4()->'rank') r where p_rank between (r->>'from')::int and (r->>'to')::int), '{}'::jsonb) $$;

create or replace function public._raid_get_v4(p_gid bigint, p_week date) returns guild_raids_v4 language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare r guild_raids_v4; n int;
begin
  select * into r from guild_raids_v4 where guild_id = p_gid and week = p_week;
  if r.guild_id is not null then return r; end if;
  select count(*) into n from guild_members where guild_id = p_gid;
  insert into guild_raids_v4 (guild_id, week, members, hp_max, hp_left) values (p_gid, p_week, n, _raid_hp_v4('normal', n, 1), _raid_hp_v4('normal', n, 1)) on conflict do nothing;
  insert into guild_raid_stages_v4 (guild_id, week, stage, boss_id, hp) values (p_gid, p_week, 1, _raid_boss_v4(1)->>'id', _raid_hp_v4('normal', n, 1)) on conflict do nothing;
  select * into r from guild_raids_v4 where guild_id = p_gid and week = p_week;
  return r;
end $$;

create or replace function public._raid_hit_v4(p_gid bigint, p_week date, p_uid uuid, p_dmg bigint) returns int language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
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
end $$;

create or replace function public._raid_close_v4(a guild_raid_attempts_v4, p_dmg bigint) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
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
end $$;

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

create or replace function public._raid_claimable_v4() returns int language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
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
end $$;

create or replace function public._raid_set_difficulty_v4(p_diff text) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
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
end $$;

create or replace function public._raid_claim_v4() returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
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
end $$;

create or replace function public._war_numbers_v4() returns jsonb language sql immutable as $$ select '{
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
}'::jsonb $$;

create or replace function public._war_role_v4(p_slot int) returns text language sql immutable as $$
  select case when p_slot <= 5 then 'def' when p_slot <= 10 then 'atk' when p_slot <= 13 then 'mid' when p_slot = 14 then 'boss' else 'etc' end $$;

create or replace function public._war_now_v4() returns timestamptz language sql stable as $$ select public._guildbattle_now_v4() $$;

create or replace function public._war_kst_v4() returns timestamp language sql stable as $$ select _war_now_v4() at time zone 'Asia/Seoul' $$;

create or replace function public._war_third_wed_v4(p_d date) returns date language sql immutable as $$
  select (date_trunc('month', p_d)::date + ((3 - extract(isodow from date_trunc('month', p_d))::int + 7) % 7) + 14) $$;

create or replace function public._war_season_v4() returns date language sql stable as $$
  select case when _war_kst_v4()::date <= _war_third_wed_v4(_war_kst_v4()::date) + 4 then _war_third_wed_v4(_war_kst_v4()::date)
              else _war_third_wed_v4((date_trunc('month', _war_kst_v4()) + interval '1 month')::date) end $$;

create or replace function public._war_at_v4(p_season date, p_day int, p_hour int) returns timestamptz language sql immutable as $$
  select ((p_season + p_day - 1)::timestamp + make_interval(hours => p_hour)) at time zone 'Asia/Seoul' $$;

create or replace function public._war_day_v4(p_season date) returns int language sql stable as $$
  select case when _war_kst_v4()::date between p_season and p_season + 4 then (_war_kst_v4()::date - p_season) + 1 end $$;

create or replace function public._war_phase_v4(p_season date) returns text language sql stable as $$
  select case when _war_now_v4() < _war_at_v4(p_season, 1 - (_war_numbers_v4()->>'signup_days_before')::int, 0) then 'soon'
              when _war_now_v4() < _war_at_v4(p_season, 1, (_war_numbers_v4()->>'open_hour')::int) then 'signup'
              when _war_now_v4() >= _war_at_v4(p_season, 5, (_war_numbers_v4()->>'close_hour')::int) then 'ended'
              when extract(hour from _war_kst_v4()) >= (_war_numbers_v4()->>'open_hour')::int and extract(hour from _war_kst_v4()) < (_war_numbers_v4()->>'close_hour')::int then 'live'
              else 'rest' end $$;

create or replace function public._war_npc_deck_v4(p_seed text, p_scale numeric) returns jsonb language plpgsql stable as $$
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
end $$;

create or replace function public._war_scale_v4(p_season date, p_gid bigint) returns numeric language sql stable security definer set search_path=pg_catalog,public,pg_temp as $$
  select coalesce((_war_numbers_v4()->>'npc_scale')::numeric, 1) $$;

create or replace function public._war_lock_v4(p_season date) returns void language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
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
end $$;

create or replace function public._war_build_side_v4(p_mid bigint, p_side int, p_season date, p_gid bigint, p_scale numeric) returns void language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
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
end $$;

create or replace function public._war_pair_v4(p_season date, p_day int) returns void language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
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
end $$;

create or replace function public._war_settle_v4(p_mid bigint) returns void language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
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
end $$;

create or replace function public._war_tick_v4() returns date language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
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
end $$;

create or replace function public._war_set_deck_v4(p_kind text, p_uids jsonb) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
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
end $$;

create or replace function public._war_enter_v4() returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare uid uuid := auth.uid(); m guild_members; s date := _war_tick_v4();
begin
  m := _guild_me(uid);
  if m.user_id is null then raise exception 'not in guild'; end if;
  if m.role not in ('boss', 'officer') then raise exception 'not allowed'; end if;
  if _war_phase_v4(s) <> 'signup' then raise exception 'signup closed'; end if;
  if (select count(*) from guild_members where guild_id = m.guild_id) < (_war_numbers_v4()->>'min_members')::int then raise exception 'need members'; end if;
  insert into war_entries_v4 (season, guild_id) values (s, m.guild_id) on conflict do nothing;
  return _war_status_v4();
end $$;

create or replace function public._war_withdraw_v4() returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare uid uuid := auth.uid(); m guild_members; s date := _war_tick_v4();
begin
  m := _guild_me(uid);
  if m.user_id is null or m.role <> 'boss' then raise exception 'not allowed'; end if;
  if _war_phase_v4(s) <> 'signup' then raise exception 'signup closed'; end if;
  delete from war_entries_v4 where season = s and guild_id = m.guild_id;
  return _war_status_v4();
end $$;

create or replace function public._war_set_slot_v4(p_slot int, p_user uuid) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
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
end $$;

create or replace function public._war_side_json_v4(p_mid bigint, p_side int) returns jsonb language sql stable security definer set search_path=pg_catalog,public,pg_temp as $$
  select coalesce(jsonb_agg(jsonb_build_object('slot', a.slot, 'role', a.role, 'npc', a.npc, 'user_id', a.user_id,
      'name', case when a.npc and a.user_id is null then '동네 불량배' else coalesce(p.nickname, '조직원') end, 'deck', a.deck, 'decks', jsonb_array_length(a.snaps) - (case when jsonb_array_length(coalesce(a.snaps->1, '[]'::jsonb)) = 0 then 1 else 0 end),
      'cards', (select coalesce(jsonb_agg(jsonb_build_object('id', c->>'id', 'level', c->'level', 'scale', c->'scale', 'snapshot', jsonb_build_object('id',c->'id','level',c->'level','ex',c->'ex','exb',c->'exb','boost',c->'boost','skillLv',c->'skillLv','gear',c->'gear','sigil',c->'sigil','scale',c->'scale'), 'hp', a.state->(c->>'uid'))), '[]'::jsonb) from jsonb_array_elements(a.snaps->(a.deck - 1)) c),
      'destroyed', a.destroyed_at is not null, 'locked', a.locked_until > _war_now_v4()) order by a.slot), '[]'::jsonb)
  from war_ajits_v4 a left join profiles p on p.id = a.user_id where a.match_id = p_mid and a.side = p_side $$;

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

create or replace function public._war_sum_v4(a jsonb, b jsonb) returns jsonb language sql immutable as $$
  select coalesce(jsonb_object_agg(k, coalesce((a->>k)::int, 0) + coalesce((b->>k)::int, 0)), '{}'::jsonb) from (select jsonb_object_keys(a) k union select jsonb_object_keys(b)) x $$;

create or replace function public._war_pending_v4(p_uid uuid) returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,pg_temp as $$
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
end $$;

create or replace function public._war_claimable_v4() returns int language sql stable security definer set search_path=pg_catalog,public,pg_temp as $$ select jsonb_array_length(_war_pending_v4(auth.uid())) $$;

create or replace function public._war_claim_v4() returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
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
end $$;

create or replace function public._war_leader_card_v4(p_uid uuid) returns text language sql stable security definer set search_path=pg_catalog,public,pg_temp as $$
  select o->>'id' from story_progress sp, jsonb_array_elements(coalesce(sp.data->'owned', '[]'::jsonb)) o where sp.user_id = p_uid and o->>'uid' = sp.data->>'leader' limit 1 $$;

create or replace function public._war_ui_v4() returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
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
end $$;

create or replace function public._war_min_level_v4() returns int language sql immutable as $$ select 3 $$;

create or replace function public._war_card_score_v4(p_id text, p_level int, p_ex int) returns numeric language sql stable security definer set search_path=pg_catalog,public,pg_temp as $$
  select coalesce((select case m.grade when 'LEGENDARY RARE' then 7 when 'MYTHIC RARE' then 6 when 'ULTRA RARE' then 5 when 'SUPER RARE' then 4 when 'HIGH RARE' then 3 when 'RARE' then 2 else 1 end
                   from pvp_card_meta m where m.id = p_id), 0) * 1000 + coalesce(p_level, 1) * 20 + coalesce(p_ex, 0) * 50 $$;

create or replace function public._war_power_v4(p_user uuid) returns numeric language sql stable security definer set search_path=pg_catalog,public,pg_temp as $$
  select coalesce(sum(_war_card_score_v4(x->>'id', (x->>'level')::int, (x->>'ex')::int)), 0) from story_progress sp,
    jsonb_array_elements(case when jsonb_typeof(sp.data->'owned') = 'array' then sp.data->'owned' else '[]'::jsonb end) x
  where sp.user_id = p_user and x->>'uid' in (select jsonb_array_elements_text(_war_top5(p_user))) $$;

create or replace function public._war_auto_deck_v4(p_user uuid) returns void language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
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
end $$;

create or replace function public._war_auto_enter_v4(p_season date) returns void language sql security definer set search_path=pg_catalog,public,pg_temp as $$
  insert into war_entries_v4 (season, guild_id) select p_season, g.id from guilds g where g.level >= _war_min_level_v4() on conflict do nothing $$;

create or replace function public._war_auto_assign_v4() returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
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
end $$;

create or replace function public._war_meta_v4() returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,pg_temp as $$
declare uid uuid := auth.uid(); m guild_members;
begin
  if uid is null then raise exception 'login required'; end if;
  m := _guild_me(uid);
  return jsonb_build_object('ok', true, 'min_level', _war_min_level_v4(),
    'guild_level', (select level from guilds where id = m.guild_id),
    'need_deck', m.user_id is not null and not exists (select 1 from war_decks_v4 d where d.user_id = uid and d.def1 is not null and d.atk1 is not null));
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

create or replace function public._war_finish_v4(p_uid uuid,p_id bigint, p_win boolean, p_atk_hp jsonb, p_def_hp jsonb) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
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
end $$;

create or replace function public._guildbattle_used_v4(p_uid uuid,p_kind text,p_mid bigint default null) returns bigint language plpgsql stable security definer set search_path=pg_catalog,public,pg_temp as $budget$
declare total_ bigint; mt war_matches_v4; d date:=_raid_day_v4();
begin
 if p_kind='raid' then
  select (select count(*) from guild_raid_attempts where user_id=p_uid and day=d)+(select count(*) from guild_raid_attempts_v4 where user_id=p_uid and day=d) into total_;
 elsif p_kind='war' and p_mid is not null then
  select * into mt from war_matches_v4 where id=p_mid;
  if mt.id is null then raise exception 'bad budget match'; end if;
  select (select count(*) from war_attacks_v4 where match_id=p_mid and user_id=p_uid)+(select count(*) from war_attacks a join war_matches m on m.id=a.match_id where a.user_id=p_uid and m.season=mt.season and m.day=mt.day) into total_;
 else raise exception 'bad budget kind'; end if;
 return total_;
end $budget$;

revoke all on function public._guildbattle_used_v4(uuid,text,bigint) from public,anon,authenticated;

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
  if _guildbattle_used_v4(u,'raid')>=3 then raise exception 'no attempts'; end if;
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
 if _guildbattle_used_v4(u,'raid')>=3 then raise exception 'no attempts'; end if;
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

create or replace function public.guild_quests() returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare uid uuid := auth.uid(); m guild_members; d date := _guild_day(); w date := _guild_week();
begin
  m := _guild_me(uid);
  if m.user_id is null then raise exception 'not in guild'; end if;
  perform _guild_roll_daily(uid); perform _guild_roll_weekly(m.guild_id);
  return jsonb_build_object('ok', true, 'day', d, 'week', w, 'week_end', ((w + 7)::timestamp at time zone 'Asia/Seoul'),
    'daily', (select jsonb_agg(jsonb_build_object('slot', q.slot, 'key', q.qkey, 'label', p.label, 'icon', p.icon, 'event', p.event, 'goal', q.goal, 'progress', (case when p.event='raid' then _guildbattle_raid_count_v4(case when p.kind='daily' then uid else null end,m.guild_id,case when p.kind='daily' then d else w end,case when p.kind='daily' then d else w+6 end) else q.progress end),
                'reward', p.reward, 'claimed', q.claimed_at is not null) order by q.slot) from guild_daily_quests q join guild_quest_pool p on p.key = q.qkey where q.user_id = uid and q.day = d),
    'reroll_left', case when exists (select 1 from guild_daily_quests where user_id = uid and day = d and rerolled) then 0 else 1 end,
    'all_reward', _guild_daily_all_reward(), 'all_claimed', exists (select 1 from guild_claims where user_id = uid and ref = 'dqall:' || d),
    'weekly', (select jsonb_agg(jsonb_build_object('slot', q.slot, 'key', q.qkey, 'label', p.label, 'icon', p.icon, 'event', p.event, 'goal', q.goal, 'progress', (case when p.event='raid' then _guildbattle_raid_count_v4(case when p.kind='daily' then uid else null end,m.guild_id,case when p.kind='daily' then d else w end,case when p.kind='daily' then d else w+6 end) else q.progress end),
                'mine', case when p.event='raid' then _guildbattle_raid_count_v4(uid,m.guild_id,w,w+6) else coalesce((select amount from guild_weekly_contrib c where c.guild_id = q.guild_id and c.week = w and c.slot = q.slot and c.user_id = uid),0) end,
                'min', ceil(q.goal * _guild_weekly_min_pct())::int,
                'tiers', (select jsonb_agg(t || jsonb_build_object('reached', (case when p.event='raid' then _guildbattle_raid_count_v4(case when p.kind='daily' then uid else null end,m.guild_id,case when p.kind='daily' then d else w end,case when p.kind='daily' then d else w+6 end) else q.progress end) * 100 >= q.goal * (t->>'tier')::int,
                            'claimed', exists (select 1 from guild_claims where user_id = uid and ref = 'wq:' || w || ':' || q.slot || ':' || (t->>'tier') || case when p.event='raid' then ':v4' else '' end))) from jsonb_array_elements(_guild_weekly_tiers()) t),
                'top', (select coalesce(jsonb_agg(jsonb_build_object('name', coalesce(pr.nickname, '조직원'), 'amount', c.amount) order by c.amount desc), '[]'::jsonb)
                        from (select * from guild_weekly_contrib c2 where c2.guild_id = q.guild_id and c2.week = w and c2.slot = q.slot order by amount desc limit 5) c left join profiles pr on pr.id = c.user_id))
              order by q.slot) from guild_weekly_quests q join guild_quest_pool p on p.key = q.qkey where q.guild_id = m.guild_id and q.week = w));
end $$;

create or replace function public.raid_status() returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$ begin perform _guildbattle_guard_v4(); perform pg_advisory_xact_lock(hashtext('guildbattle:v4')); return _raid_status_v4(); end $$;

revoke all on function public.raid_status() from public,anon;

grant execute on function public.raid_status() to authenticated;

create or replace function public.raid_claimable() returns int language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$ begin perform _guildbattle_guard_v4(); perform pg_advisory_xact_lock(hashtext('guildbattle:v4')); return _raid_claimable_v4(); end $$;

revoke all on function public.raid_claimable() from public,anon;

grant execute on function public.raid_claimable() to authenticated;

create or replace function public.raid_set_difficulty(p_diff text) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$ begin perform _guildbattle_guard_v4(); perform pg_advisory_xact_lock(hashtext('guildbattle:v4')); return _raid_set_difficulty_v4(p_diff); end $$;

revoke all on function public.raid_set_difficulty(text) from public,anon;

grant execute on function public.raid_set_difficulty(text) to authenticated;

create or replace function public.raid_claim() returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$ begin perform _guildbattle_guard_v4(); perform pg_advisory_xact_lock(hashtext('guildbattle:v4')); return _raid_claim_v4(); end $$;

revoke all on function public.raid_claim() from public,anon;

grant execute on function public.raid_claim() to authenticated;

create or replace function public.war_set_deck(p_kind text, p_uids jsonb) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$ begin perform _guildbattle_guard_v4(); perform pg_advisory_xact_lock(hashtext('guildbattle:v4')); return _war_set_deck_v4(p_kind,p_uids); end $$;

revoke all on function public.war_set_deck(text,jsonb) from public,anon;

grant execute on function public.war_set_deck(text,jsonb) to authenticated;

create or replace function public.war_set_slot(p_slot int, p_user uuid) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$ begin perform _guildbattle_guard_v4(); perform pg_advisory_xact_lock(hashtext('guildbattle:v4')); return _war_set_slot_v4(p_slot,p_user); end $$;

revoke all on function public.war_set_slot(int,uuid) from public,anon;

grant execute on function public.war_set_slot(int,uuid) to authenticated;

create or replace function public.war_status() returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$ begin perform _guildbattle_guard_v4(); perform pg_advisory_xact_lock(hashtext('guildbattle:v4')); return _war_status_v4(); end $$;

revoke all on function public.war_status() from public,anon;

grant execute on function public.war_status() to authenticated;

create or replace function public.war_claimable() returns int language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$ begin perform _guildbattle_guard_v4(); perform pg_advisory_xact_lock(hashtext('guildbattle:v4')); return _war_claimable_v4(); end $$;

revoke all on function public.war_claimable() from public,anon;

grant execute on function public.war_claimable() to authenticated;

create or replace function public.war_claim() returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$ begin perform _guildbattle_guard_v4(); perform pg_advisory_xact_lock(hashtext('guildbattle:v4')); return _war_claim_v4(); end $$;

revoke all on function public.war_claim() from public,anon;

grant execute on function public.war_claim() to authenticated;

create or replace function public.war_ui() returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$ begin perform _guildbattle_guard_v4(); perform pg_advisory_xact_lock(hashtext('guildbattle:v4')); return _war_ui_v4(); end $$;

revoke all on function public.war_ui() from public,anon;

grant execute on function public.war_ui() to authenticated;

create or replace function public.war_auto_assign() returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$ begin perform _guildbattle_guard_v4(); perform pg_advisory_xact_lock(hashtext('guildbattle:v4')); return _war_auto_assign_v4(); end $$;

revoke all on function public.war_auto_assign() from public,anon;

grant execute on function public.war_auto_assign() to authenticated;

create or replace function public.war_meta() returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$ begin perform _guildbattle_guard_v4(); perform pg_advisory_xact_lock(hashtext('guildbattle:v4')); return _war_meta_v4(); end $$;

revoke all on function public.war_meta() from public,anon;

grant execute on function public.war_meta() to authenticated;

-- ===== REVIEWED DELTA SOURCE: level_unlocks_staging.sql =====
create or replace function public._unlock_levels() returns jsonb language sql immutable as $$select '{"pvp_hr":3,"gear":3,"dispatch":5,"guild":6,"friends":8,"tower":10,"raid":11,"camp":12,"merge":13,"skill":13,"lend":13,"sigil":14,"pvp_open":15,"trade":15,"pvp_3v3":17,"war":18,"pvp_boss":20,"tower_wind":25,"tower_ice":25,"tower_fire":25,"tower_light":40,"tower_dark":40,"forge":20,"dojo":20}'::jsonb$$;

create or replace function public._unlock_intros() returns jsonb language sql immutable as $$select '[{"key":"ch0","level":1,"title":"프리미엄 소환","text":"챕터 0을 완료했어요. 프리미엄 10회 소환으로 새로운 인재를 만나 보세요.","reward":{},"route":"summon","trigger":"ch0","source_text":"챕터0 클리어- 소환(프리미엄) 10회"},{"key":"leader","level":1,"title":"인재 레벨업","text":"지급된 리더를 레벨업해 보세요. 1레벨씩 또는 10레벨씩 올릴 수 있어요.","reward":{"blood":5000,"gold":5000},"route":"cards","trigger":"1:1","source_text":"ch1 P1클리어- 지급된 리더 레벨업. lv1업, lv10업"},{"key":"deck","level":1,"title":"덱 설정","text":"덱에 출전할 인재를 배치하고 리더를 정해 보세요.","reward":{"gold":5000},"route":"decks","trigger":"1:3","source_text":"ch1 p3클리어- 덱 설정 및 방법 설명"},{"key":"pvp_hr","level":3,"title":"PvP · 장비 가방","text":"HR 이하 1대1 리그가 열렸어요. PvP 덱을 배치하고 장비를 확인해 보세요.","reward":{"gold":5000},"route":"pvp","trigger":"","source_text":"pvp덱배치 및 다른 pvp설명."},{"key":"dispatch","level":5,"title":"파견","text":"인재를 파견하면 시간이 지난 뒤 보상을 받아요. 파견할 인재와 의뢰를 골라 보세요.","reward":{"gold":5000},"route":"dispatch","trigger":"","source_text":"레벨5 되면 파견 설명 및 실행"},{"key":"guild","level":6,"title":"조직","text":"조직에 가입하거나 직접 만들 수 있어요. 가입은 지금 하지 않아도 괜찮아요.","reward":{"gold":5000,"boxes":2},"route":"guild","trigger":"","source_text":"레벨6 되면 조직 가입 또는 창설 설명"},{"key":"friends","level":8,"title":"친구 · 선물","text":"친구를 추가하고 행동력 선물을 주고받을 수 있어요.","reward":{},"route":"friends","trigger":"","source_text":"친구를 추가하고 행동력 선물을 주고받을 수 있어요."},{"key":"tower","level":10,"title":"시련의 탑","text":"덱을 골라 일반 전투 한 판만 도전해 보세요. 소탕은 원할 때 사용할 수 있어요.","reward":{"gold":5000,"boxes":2},"route":"tower","trigger":"","source_text":"시련의탑 설명, 강제 실행(일반+소탕)"},{"key":"raid","level":11,"title":"토벌","text":"조직원들과 보스를 토벌할 수 있어요. 아직 조직이 없어도 안내와 보상은 받을 수 있어요.","reward":{"tickets":10},"route":"raid","trigger":"","source_text":"토벌 방법 및 내용 설명, 시행(길드 가입자 한정)"},{"key":"camp","level":12,"title":"훈련소","text":"인재를 맡기면 훈련 경험치가 쌓여요. 가장 낮은 레벨 인재를 추천하지만 직접 골라도 돼요.","reward":{"gold":5000,"boxes":2},"route":"camp","trigger":"","source_text":"훈련소 설명 및 강제 배정(가장 레벨 낮은 캐릭터)"},{"key":"skill","level":13,"title":"EX 합성 · 스킬 강화 · 대여","text":"인재를 EX 합성하거나 스킬을 강화할 수 있어요. 조직 인재 대여도 열렸어요.","reward":{"soul":1000,"gold":5000},"route":"cards","trigger":"","source_text":"스킬 강화 방법 알려줌"},{"key":"sigil","level":14,"title":"증표","text":"인재 전용 증표를 만들고 강화할 수 있어요. 선택 상자는 우편에서 받을 수 있어요.","reward":{"sigil_boxes":10},"route":"cards","trigger":"","source_text":"증표 설명"},{"key":"trade","level":15,"title":"무제한 1대1 · 거래소","text":"무제한 1대1 리그와 거래소가 열렸어요. 거래소는 계정 생성 후 7일이 지나면 이용할 수 있어요.","reward":{"tickets":10},"route":"trade","trigger":"","source_text":"거래소 설명 및 방법"},{"key":"pvp_3v3","level":17,"title":"3대3 리그","text":"세 덱으로 겨루는 3대3 리그가 열렸어요. 두 리그에서 모두 도전할 수 있어요.","reward":{},"route":"pvp","trigger":"","source_text":"세 덱으로 겨루는 3대3 리그가 열렸어요. 두 리그에서 모두 도전할 수 있어요."},{"key":"war","level":18,"title":"조직전","text":"조직원들과 방어 덱을 배치하고 상대 조직에 도전해 보세요.","reward":{},"route":"war","trigger":"","source_text":"조직원들과 방어 덱을 배치하고 상대 조직에 도전해 보세요."},{"key":"pvp_boss","level":20,"title":"보스 리그","text":"진영 보스를 지키는 보스 리그가 열렸어요. 두 리그에서 모두 도전할 수 있어요.","reward":{},"route":"pvp","trigger":"","source_text":"진영 보스를 지키는 보스 리그가 열렸어요. 두 리그에서 모두 도전할 수 있어요."},{"key":"facilities","level":20,"title":"연마소 · 도장","text":"연마소에서 장비를, 도장에서 스킬을 강화할 수 있어요. 훈련소 건물 레벨과 무관하게 이용하며 기존 재료와 도장 개방 비용은 필요해요.","reward":{"gold":5000},"route":"camp","trigger":"","source_text":"연마소, 도장 설명"},{"key":"attr25","level":25,"title":"바람 · 얼음 · 불의 탑","text":"같은 속성 인재로 도전하는 세 탑이 열렸어요. 각 탑의 개방 요일에 도전해 보세요.","reward":{},"route":"tower","trigger":"","source_text":"같은 속성 인재로 도전하는 세 탑이 열렸어요. 각 탑의 개방 요일에 도전해 보세요."},{"key":"attr40","level":40,"title":"빛의 섬 · 어둠의 늪","text":"빛과 어둠의 인재를 위한 두 탑이 열렸어요. 각 탑의 개방 요일에 도전해 보세요.","reward":{},"route":"tower","trigger":"","source_text":"빛과 어둠의 인재를 위한 두 탑이 열렸어요. 각 탑의 개방 요일에 도전해 보세요."}]'::jsonb$$;

-- Account levels never change here. Existing stamina->account EXP rules are untouched.
create or replace function public._unlock_require(p_key text) returns void language plpgsql security definer
set search_path=pg_catalog,public,pg_temp as $$
declare u uuid:=auth.uid(); n int;
begin
 if u is null then raise exception 'login required'; end if;
 n:=(public._unlock_levels()->>p_key)::int;
 if n is null then raise exception 'invalid unlock key'; end if;
 if coalesce((select level from public.player_state where user_id=u),1)<n then
  raise exception 'Lv%',n;
 end if;
end $$;

create or replace function public._unlock_pvp_key(l text,m text) returns text language plpgsql immutable as $$
begin
 if l not in ('hr','open') or m not in ('1v1','3v3','boss') or l is null or m is null then raise exception 'invalid PvP league/mode'; end if;
 return case m when 'boss' then 'pvp_boss' when '3v3' then 'pvp_3v3' else case l when 'hr' then 'pvp_hr' else 'pvp_open' end end;
end $$;

create or replace function public._player_unlock_level(p_key text) returns int language sql immutable as $$
 select case when p_key ~ '^chapter_[0-9]+$' then 1 else case p_key
 when 'sweep' then 5 when 'skill' then 13 when 'equip' then 3 when 'equip_merge' then 20 else null end end
$$;

create or replace function public._tower_min_level(p text) returns int language sql immutable as $$
 select case p when 'normal' then 10 when 'light' then 40 when 'dark' then 40 else 25 end
$$;

create or replace function public._guild_min_level() returns int language sql immutable as $$select 6$$;

create or replace function public._lend_min_level() returns int language sql immutable as $$select 13$$;

create or replace function public._camp_need_level(s int) returns int language sql immutable as $$
 select case s when 1 then 12 when 2 then 20 when 3 then 35 when 4 then 50 when 5 then 70 end
$$;

insert into public.trade_config(key,val,note) values('min_level',15,'계정 레벨 하한') on conflict(key) do update set val=15;

-- CREATE OR REPLACE preserves the exact OID, defaults, ACL and phase2/3/4 validation.
-- Only this explicit list is patched; revoked legacy endpoints are NEVER re-granted.
do $rpc_gates$
declare rule jsonb; f record; body text; ddl text;
begin
 for rule in select * from jsonb_array_elements('[{"name":"dispatch_refresh","gate":"perform public._unlock_require(''dispatch'');"},{"name":"dispatch_start","gate":"perform public._unlock_require(''dispatch'');"},{"name":"guild_create","gate":"perform public._unlock_require(''guild'');"},{"name":"guild_apply","gate":"perform public._unlock_require(''guild'');"},{"name":"guild_update","gate":"perform public._unlock_require(''guild'');"},{"name":"guild_transfer","gate":"perform public._unlock_require(''guild'');"},{"name":"guild_kick","gate":"perform public._unlock_require(''guild'');"},{"name":"guild_shop_buy","gate":"perform public._unlock_require(''guild'');"},{"name":"guild_rally_claim","gate":"perform public._unlock_require(''guild'');"},{"name":"guild_quest_claim","gate":"perform public._unlock_require(''guild'');"},{"name":"friend_request","gate":"perform public._unlock_require(''friends'');"},{"name":"friend_respond","gate":"perform public._unlock_require(''friends'');"},{"name":"friend_gift_send","gate":"perform public._unlock_require(''friends'');"},{"name":"friend_gift_claim","gate":"perform public._unlock_require(''friends'');"},{"name":"friend_gift_claim_all","gate":"perform public._unlock_require(''friends'');"},{"name":"friend_battle_start","gate":"perform public._unlock_require(''friends'');"},{"name":"gear_expand","gate":"perform public._unlock_require(''gear'');"},{"name":"gear_lock","gate":"perform public._unlock_require(''gear'');"},{"name":"gear_equip","gate":"perform public._unlock_require(''gear'');"},{"name":"gear_unequip","gate":"perform public._unlock_require(''gear'');"},{"name":"gear_box_open","gate":"perform public._unlock_require(''gear'');"},{"name":"gear_enhance","gate":"perform public._unlock_require(''gear'');"},{"name":"gear_reroll","gate":"perform public._unlock_require(''gear'');"},{"name":"camp_put","gate":"perform public._unlock_require(''camp'');"},{"name":"camp_unlock","gate":"perform public._unlock_require(''camp'');"},{"name":"camp_levelup","gate":"perform public._unlock_require(''camp'');"},{"name":"story_merge","gate":"perform public._unlock_require(''merge'');"},{"name":"story_skill_levelup","gate":"perform public._unlock_require(''skill'');"},{"name":"guild_lend_set","gate":"perform public._unlock_require(''lend'');"},{"name":"guild_lend_borrow","gate":"perform public._unlock_require(''lend'');"},{"name":"sigil_craft","gate":"perform public._unlock_require(''sigil'');"},{"name":"sigil_enhance","gate":"perform public._unlock_require(''sigil'');"},{"name":"sigil_exchange","gate":"perform public._unlock_require(''sigil'');"},{"name":"sigil_mail_claim","gate":"perform public._unlock_require(''sigil'');"},{"name":"raid_sweep_v4","gate":"perform public._unlock_require(''raid'');"},{"name":"raid_set_difficulty","gate":"perform public._unlock_require(''raid'');"},{"name":"war_set_deck","gate":"perform public._unlock_require(''war'');"},{"name":"war_set_slot","gate":"perform public._unlock_require(''war'');"},{"name":"war_signup","gate":"perform public._unlock_require(''war'');"},{"name":"war_auto_assign","gate":"perform public._unlock_require(''war'');"},{"name":"pvp_set_deck","gate":"perform public._unlock_require(public._unlock_pvp_key(p_league,p_mode));"},{"name":"pvp_start_v3","gate":"perform public._unlock_require(public._unlock_pvp_key(p_league,p_mode));"},{"name":"guildbattle_start_v4","gate":"perform public._unlock_require(case p_kind when ''raid'' then ''raid'' when ''war'' then ''war'' else null end);"},{"name":"guild_invite","gate":"perform public._unlock_require(''guild'');"},{"name":"guild_respond","gate":"perform public._unlock_require(''guild'');"},{"name":"guild_set_role","gate":"perform public._unlock_require(''guild'');"},{"name":"guild_checkin","gate":"perform public._unlock_require(''guild'');"},{"name":"guild_quest_reroll","gate":"perform public._unlock_require(''guild'');"},{"name":"guild_weekly_claim","gate":"perform public._unlock_require(''guild'');"},{"name":"_guild_add_member","gate":"if coalesce((select level from public.player_state where user_id=p_uid),1)<6 then raise exception ''Lv6''; end if;"}]'::jsonb) loop
  if not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname=rule->>'name') then
   raise exception 'STOP: required unlock RPC missing: %',rule->>'name';
  end if;
  for f in select p.oid,p.prosrc,l.lanname,pg_get_functiondef(p.oid) def from pg_proc p join pg_namespace n on n.oid=p.pronamespace join pg_language l on l.oid=p.prolang
   where n.nspname='public' and p.proname=rule->>'name' loop
   if position('-- unlock-policy-v1' in f.prosrc)>0 then continue; end if;
   if f.lanname<>'plpgsql' or f.prosrc!~* '\mbegin\M' then raise exception 'STOP: unexpected unlock RPC language/body: %',rule->>'name'; end if;
   body:=regexp_replace(f.prosrc,'\mbegin\M',E'begin\n -- unlock-policy-v1\n '||(rule->>'gate')||E'\n','i');
   ddl:=replace(f.def,f.prosrc,body);
   execute ddl;
  end loop;
 end loop;
end $rpc_gates$;

create or replace function public.gear_dismantle(p_ids bigint[]) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
begin perform public._unlock_require('gear'); return public._gear_salvage(p_ids,false); end $$;

create or replace function public.gear_sell(p_ids bigint[]) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
begin perform public._unlock_require('gear'); return public._gear_salvage(p_ids,true); end $$;

-- New users finish CH0 before CH1. Existing CH1+ access is grandfathered, not reset.
-- All later chapters already require every preceding clear in phase2; level walls above are removed.
create or replace function public._unlock_chapter1(p_target text) returns void language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare u uuid:=auth.uid();
begin
 if split_part(p_target,':',1)::int<1 then return; end if;
 if exists(select 1 from public.battle_clear_receipts_v2 where user_id=u and mode='story' and split_part(target,':',1)::int>=1)
 or exists(select 1 from public.battle_legacy_access_v2 b,jsonb_each(b.cleared) c where b.user_id=u and case when c.key ~ '^[0-9]{1,3}$' then c.key::int else 0 end>=1 and jsonb_array_length(case when jsonb_typeof(c.value)='array' then c.value else '[]'::jsonb end)>0) then return; end if;
 if exists(select 1 from public.story_phase_config c where c.chapter=0 and not public._clear_access_v2(u,'story','0:'||c.phase)) then raise exception 'previous chapter required'; end if;
end $$;

do $chapter_gate$
declare f record; body text;
begin
 select p.prosrc,pg_get_functiondef(p.oid) def into f from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='battle_session_start_v2';
 if position('-- unlock-chapter-v1' in f.prosrc)=0 then
  body:=regexp_replace(f.prosrc,'\mbegin\M',E'begin\n -- unlock-chapter-v1\n if p_mode=\'story\' and p_target ~ \'^[0-9]+:[0-9]+$\' then perform public._unlock_chapter1(p_target); end if;\n','i');
  execute replace(f.def,f.prosrc,body);
 end if;
end $chapter_gate$;

create table if not exists public.unlock_intro_receipts (
 user_id uuid not null references auth.users(id) on delete cascade,
 event text not null, reward jsonb not null, claimed_at timestamptz not null default now(),
 primary key(user_id,event)
);

alter table public.unlock_intro_receipts enable row level security;

revoke all on public.unlock_intro_receipts from public,anon,authenticated;

create or replace function public._unlock_intro_eligible(u uuid,e jsonb) returns boolean language plpgsql stable security definer
set search_path=pg_catalog,public,pg_temp as $$
declare t text:=e->>'trigger';
begin
 if coalesce((select level from public.player_state where user_id=u),1)<(e->>'level')::int then return false; end if;
 if coalesce(t,'')='' then return true; end if;
 if t='ch0' then return not exists(select 1 from public.story_phase_config c where c.chapter=0 and not public._clear_access_v2(u,'story','0:'||c.phase)); end if;
 return public._clear_access_v2(u,'story',t);
end $$;

-- Assignment proof survives removing the trainee before returning to the lobby.
create table if not exists public.unlock_tutorial_actions (
 user_id uuid not null references auth.users(id) on delete cascade,
 action text not null check(action='camp'), completed_at timestamptz not null default now(),primary key(user_id,action)
);

alter table public.unlock_tutorial_actions enable row level security;

revoke all on public.unlock_tutorial_actions from public,anon,authenticated;

create or replace function public._unlock_camp_action() returns trigger language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
begin
 if new.card_uid is not null then insert into public.unlock_tutorial_actions(user_id,action) values(new.user_id,'camp') on conflict do nothing; end if;
 return new;
end $$;

drop trigger if exists unlock_camp_action on public.camp_slots;

create trigger unlock_camp_action after insert or update of card_uid on public.camp_slots for each row execute function public._unlock_camp_action();

insert into public.unlock_tutorial_actions(user_id,action) select distinct user_id,'camp' from public.camp_slots where card_uid is not null on conflict do nothing;

create or replace function public._unlock_action_done(u uuid,k text) returns boolean language plpgsql stable security definer set search_path=pg_catalog,public,pg_temp as $$
declare lv int:=coalesce((select level from public.player_state where user_id=u),1);
begin
 if k='tower' then
  return exists(select 1 from public.battle_sessions_v2 where user_id=u and mode='tower' and target like 'normal:%' and status='settled')
   or not exists(select 1 from jsonb_array_elements(public._camp_owned(u)) o);
 elsif k='camp' then
  return exists(select 1 from public.unlock_tutorial_actions where user_id=u and action='camp')
   or not exists(select 1 from jsonb_array_elements(public._camp_owned(u)) o where coalesce((o->>'level')::int,1)<public._camp_cap(public._camp_grade(o->>'id'),coalesce((o->>'ex')::int,0),lv));
 end if;
 return true;
end $$;

create or replace function public.unlock_status() returns jsonb language plpgsql security definer
set search_path=pg_catalog,public,pg_temp as $$
declare u uuid:=auth.uid(); ps public.player_state; es jsonb;
begin
 if u is null then raise exception 'login required'; end if;
 ps:=public._player_sync(u);
 select coalesce(jsonb_agg(e||jsonb_build_object('eligible',public._unlock_intro_eligible(u,e),'action_done',public._unlock_action_done(u,e->>'key'),'claimed',exists(select 1 from public.unlock_intro_receipts r where r.user_id=u and r.event=e->>'key')) order by ord),'[]') into es
 from jsonb_array_elements(public._unlock_intros()) with ordinality a(e,ord);
 return jsonb_build_object('ok',true,'level',ps.level,'levels',public._unlock_levels(),'entries',es);
end $$;

create or replace function public.unlock_intro_claim(p_event text) returns jsonb language plpgsql security definer
set search_path=pg_catalog,public,pg_temp as $$
declare u uuid:=auth.uid(); e jsonb; rw jsonb; wallet jsonb; i int;
begin
 if u is null then raise exception 'login required'; end if;
 perform pg_advisory_xact_lock(hashtext('unlock-intro:'||u::text));
 select x into e from jsonb_array_elements(public._unlock_intros()) x where x->>'key'=p_event;
 if e is null then raise exception 'invalid intro'; end if;
 if exists(select 1 from public.unlock_intro_receipts where user_id=u and event=p_event) then return jsonb_build_object('ok',true,'already',true); end if;
 if not public._unlock_intro_eligible(u,e) then raise exception 'intro locked'; end if;
 if not public._unlock_action_done(u,p_event) then raise exception 'tutorial action required'; end if;
 rw:=e->'reward';
 insert into public.unlock_intro_receipts(user_id,event,reward) values(u,p_event,rw);
 -- Only these fixed server-owned amounts, never client input. No account/card EXP.
 if (rw-'tickets'-'boxes'-'sigil_boxes')<>'{}'::jsonb then
  wallet:=public._wallet_add(u,rw-'tickets'-'boxes'-'sigil_boxes','unlock_intro:'||p_event);
 end if;
 if coalesce((rw->>'tickets')::int,0)>0 then
  insert into public.story_gacha(user_id,last_draw) values(u,public._gem_day()-1) on conflict do nothing;
  update public.story_gacha set tickets=tickets+(rw->>'tickets')::int,updated_at=now() where user_id=u;
 end if;
 for i in 1..coalesce((rw->>'boxes')::int,0) loop
  insert into public.player_mail(user_id,kind,payload,reason,expires_at) values(u,'box','{"tier":4,"up_tier":5,"up_pct":5}','unlock_intro:'||p_event,now()+interval '14 days');
 end loop;
 for i in 1..coalesce((rw->>'sigil_boxes')::int,0) loop
  insert into public.player_mail(user_id,kind,payload,reason,expires_at) values(u,'sigil_frag','{"pick":"raid_select","n":1}','unlock_intro:'||p_event,now()+interval '14 days');
 end loop;
 return jsonb_build_object('ok',true,'gave',rw,'wallet',wallet);
end $$;

-- Facilities are account-Lv20 features, NOT training-building upgrades.
-- Preserve every existing receipt, building level, EXP rate, price, material and job.
do $facility_policy$
declare levels jsonb:=public._unlock_levels(); intros jsonb:=public._unlock_intros(); e jsonb:='{"key":"facilities","level":20,"title":"연마소 · 도장","text":"연마소에서 장비를, 도장에서 스킬을 강화할 수 있어요. 훈련소 건물 레벨과 무관하게 이용하며 기존 재료와 도장 개방 비용은 필요해요.","reward":{"gold":5000},"route":"camp","trigger":"","source_text":"연마소, 도장 설명"}'::jsonb;
begin
 levels:=levels||'{"forge":20,"dojo":20}'::jsonb;
 if not exists(select 1 from jsonb_array_elements(intros) x where x->>'key'=e->>'key') then
  intros:=intros||jsonb_build_array(e);
  select jsonb_agg(x order by (x->>'level')::int,ord) into intros from jsonb_array_elements(intros) with ordinality a(x,ord);
 end if;
 -- CREATE OR REPLACE retains existing function OIDs and ACLs.
 execute format('create or replace function public._unlock_levels() returns jsonb language sql immutable as %L','select '||quote_literal(levels::text)||'::jsonb');
 execute format('create or replace function public._unlock_intros() returns jsonb language sql immutable as %L','select '||quote_literal(intros::text)||'::jsonb');
end $facility_policy$;

do $facility_functions$
declare f record; rule jsonb; body text;
begin
 for rule in select * from jsonb_array_elements($rules$[
  {"name":"camp_forge_start","old":"if (_camp_st(uid)).camp_lv < _camp_forge_lv() then raise exception 'forge locked'; end if;","new":"perform public._unlock_require('forge'); -- facility-account-v1"},
  {"name":"camp_dojo_unlock","old":"if cs.camp_lv < _camp_dojo_lv() then raise exception 'dojo locked'; end if;","new":"perform public._unlock_require('dojo'); -- facility-account-v1"},
  {"name":"camp_dojo_start","old":"begin","new":"begin\n  perform public._unlock_require('dojo'); -- facility-account-v1"},
  {"name":"_camp_json","old":"'forge_lv', _camp_forge_lv(),","new":"'forge_account_level', 20, 'dojo_account_level', 20, 'forge_open', plv >= 20, 'dojo_open', plv >= 20, -- facility-account-v1\n    'forge_lv', _camp_forge_lv(),"}
 ]$rules$::jsonb) loop
  select p.prosrc,pg_get_functiondef(p.oid) def into strict f from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname=rule->>'name';
  if position('facility-account-v1' in f.prosrc)>0 then continue; end if;
  if position(rule->>'old' in f.prosrc)=0 then raise exception 'STOP: unexpected facility function: %',rule->>'name'; end if;
  if rule->>'name'='camp_dojo_start' then body:=regexp_replace(f.prosrc,'\mbegin\M',rule->>'new','i');
  else body:=replace(f.prosrc,rule->>'old',rule->>'new'); end if;
  execute replace(f.def,f.prosrc,body);
 end loop;
end $facility_functions$;

revoke all on function public._unlock_levels(),public._unlock_intros(),public._unlock_require(text),public._unlock_pvp_key(text,text),public._unlock_chapter1(text),public._unlock_intro_eligible(uuid,jsonb),public._unlock_action_done(uuid,text),public._unlock_camp_action() from public,anon,authenticated;

-- CREATE OR REPLACE above does not touch the older helper ACLs; explicitly keep all new helpers private.
revoke all on function public.unlock_status(),public.unlock_intro_claim(text) from public,anon,authenticated;

grant execute on function public.unlock_status(),public.unlock_intro_claim(text) to authenticated;

notify pgrst,'reload schema';

-- ===== REVIEWED DELTA SOURCE: security_phase5_arcade.sql =====
create table if not exists public.arcade_policy_v5 (
 singleton boolean primary key default true check(singleton), enabled boolean not null default true, engine_hash text not null check(engine_hash ~ '^[a-f0-9]{64}$'));

insert into public.arcade_policy_v5(singleton,engine_hash) values(true,'e792c491ffafe19d047aa6f58db1920e5767e4059e14816611dd38d473871161')
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

select 'phase5 arcade verification installed — staging only' as result;
$vr_production_payload$;
 perform set_config('check_function_bodies','on',true);
 -- Compile only release-managed functions after forward dependencies exist.
 for f in select pg_get_functiondef(oid) ddl from pg_proc where pronamespace='public'::regnamespace and prokind='f' and proname=any(array['_ach_claim_one','_ach_json','_ach_prog','_ach_score','_arcade_close_v5','_arcade_enabled_v5','_arcade_options_v5','_camp_need_level','_clear_access_v2','_clear_close_v2','_clear_enabled_v2','_clear_grant_v2','_clear_mission_claim_v2','_clear_mission_prog_v2','_clear_missions_json_v2','_clear_session_v2','_cosmo_ach_score','_cosmo_pvp_ord','_daily_grant','_daily_json','_gallery_have','_gallery_sync_owned','_gallery_total','_gem_sync','_guild_feed','_guild_min_level','_guild_reward','_guild_reward_v4','_guildbattle_guard_v4','_guildbattle_now_v4','_guildbattle_raid_count_v4','_guildbattle_used_v4','_lend_min_level','_player_unlock_level','_pvp_decks_v3','_pvp_forfeit_v3','_pvp_grant','_pvp_grant_v3','_pvp_guild_feed_v3','_pvp_lock_v3','_pvp_rating_v3','_pvp_session_json_v3','_raid_attempt_cap_v4','_raid_boss_v4','_raid_claim_v4','_raid_claimable_v4','_raid_close','_raid_close_v4','_raid_day_v4','_raid_end_v4','_raid_get_v4','_raid_hit_v4','_raid_hp_v4','_raid_now_v4','_raid_numbers_v4','_raid_rank_reward_v4','_raid_set_difficulty_v4','_raid_stage_reward_v4','_raid_start_v4','_raid_status_v4','_raid_week_v4','_reward_battle_enabled','_reward_gacha_event','_star_chapter','_story_ticket_sync','_tower_min_level','_tower_pay','_unlock_action_done','_unlock_camp_action','_unlock_chapter1','_unlock_intro_eligible','_unlock_intros','_unlock_levels','_unlock_pvp_key','_unlock_require','_war_at_v4','_war_auto_assign_v4','_war_auto_deck_v4','_war_auto_enter_v4','_war_build_side_v4','_war_card_score_v4','_war_claim_v4','_war_claimable_v4','_war_day_v4','_war_enter_v4','_war_finish_v4','_war_kst_v4','_war_leader_card_v4','_war_lock_v4','_war_meta_v4','_war_min_level_v4','_war_now_v4','_war_npc_deck_v4','_war_numbers_v4','_war_pair_v4','_war_pending_v4','_war_phase_v4','_war_power_v4','_war_refresh_v4','_war_role_v4','_war_scale_v4','_war_season_v4','_war_set_deck_v4','_war_set_slot_v4','_war_settle_v4','_war_side_json_v4','_war_start_v4','_war_status_v4','_war_sum_v4','_war_third_wed_v4','_war_tick_v4','_war_ui_v4','_war_withdraw_v4','_weekly_json','ach_track','arcade_engine_session_v5','arcade_engine_settle_v5','arcade_record_v5','arcade_start_v5','arcade_tut_claim','arcade_tut_status','attend_claim','battle_session_abort_v2','battle_session_finish_v2','battle_session_start_v2','battle_session_status_v2','daily_claim','daily_track','gallery_register','gear_dismantle','gear_sell','guild_quest_claim','guild_quests','guild_weekly_claim','guildbattle_engine_session_v4','guildbattle_engine_settle_v4','guildbattle_lookup_v4','guildbattle_start_v4','pvp_claim_reward','pvp_claim_tier','pvp_engine_session_v3','pvp_engine_settle_v3','pvp_report','pvp_start','pvp_start_v3','pvp_status','quest_complete','quest_sweep_complete','raid_claim','raid_claimable','raid_set_difficulty','raid_status','raid_sweep_v4','story_abort_phase','story_star_claim','story_sweep','tower_complete','tower_status','tower_sweep_complete','unlock_intro_claim','unlock_status','war_auto_assign','war_claim','war_claimable','war_meta','war_set_deck','war_set_slot','war_status','war_ui','weekly_claim','weekly_track']) loop execute f.ddl; end loop;
 if exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosecdef and left(p.proname,1)='_' and pg_get_function_result(p.oid)<>'trigger' and (has_function_privilege('anon',p.oid,'execute') or has_function_privilege('authenticated',p.oid,'execute'))) then raise exception 'STOP: public-callable internal definer function'; end if;
 insert into vr_rollout_private.releases(release_id,bundle_hash,db_id) values('20261108','80124fd4457b5130f0595fc717bf882587c67b11dc62576678b3d490ca783251',(select system_identifier::text from pg_catalog.pg_control_system()));
end $production_install$;
notify pgrst,'reload schema';
commit;
select 'Production DB delta installed; deploy all THREE production Edge bundles before main merge' as result;
