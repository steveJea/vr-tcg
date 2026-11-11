-- 보안 1단계: 보상 근거 분리 / 임의 카운터 차단 (2026-11-07 KST)
-- 먼저 docs/SECURITY_PHASE1.md와 security_phase1_preflight.sql 확인.
-- 기존 DB에는 이 파일만 실행. staging/설치본이나 옛 SQL을 재실행하지 마세요.
-- 소유자가 테스트 DB에 먼저 적용/확인, 운영은 별도 승인 후 같은 파일 적용.
-- 기존 잔액/도감/수령/진행 행 삭제·초기화·자동 보상 회수 없음.
-- 중요: 전투 검증기 없는 보상은 정상 플레이에서도 지급 보류됩니다.
begin;
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
  ('10509'),
  ('10511'),
  ('10512'),
  ('10513'),
  ('10520'),
  ('10521'),
  ('10522'),
  ('10523'),
  ('10524'),
  ('10525'),
  ('10526'),
  ('10527'),
  ('10528'),
  ('10529'),
  ('10530'),
  ('10531'),
  ('10532')
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
commit;
