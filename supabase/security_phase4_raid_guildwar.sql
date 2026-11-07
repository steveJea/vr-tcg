-- STAGING ONLY. Existing installs run this entire file ONCE; reruns are safe.
-- Legacy raid/war history is preserved, never copied as verified evidence.
begin;
do $phase4_staging_guard$ begin
 if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7703759698107299042' then raise exception 'STOP: phase4 only staging cuyqchmdcnsgzkwyclji; production forbidden'; end if;
end $phase4_staging_guard$;
set local check_function_bodies=off;
create table if not exists public.guildbattle_policy_v4(singleton boolean primary key default true check(singleton),engine_hash text not null,enabled boolean not null default true);
insert into public.guildbattle_policy_v4(singleton,engine_hash) values(true,'a00f5c9824515cfce4fcbd6d579deb5e971335035b264454d427fdb93669819e') on conflict(singleton) do update set engine_hash=excluded.engine_hash;
do $$ begin
 if not exists(select 1 from pvp_policy_v3) then raise exception 'STOP: install phases 1-3 first'; end if;
end $$;
create table if not exists public.guildbattle_test_clock_v4(singleton boolean primary key default true check(singleton),at timestamptz,set_at timestamptz not null default clock_timestamp(),expires_at timestamptz,run int not null default 0,guild_ids bigint[] not null default '{}');
insert into public.guildbattle_test_clock_v4(singleton) values(true) on conflict do nothing;
create or replace function public._guildbattle_now_v4() returns timestamptz language sql stable security definer set search_path=pg_catalog,public,pg_temp as $$ select coalesce((select at+(clock_timestamp()-set_at) from guildbattle_test_clock_v4 where singleton and expires_at>clock_timestamp()),now()) $$;
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
  insert into war_entries_v4 (season, guild_id) select p_season, g.id from guilds g where g.level >= _war_min_level_v4() and (not exists(select 1 from guildbattle_test_clock_v4 where expires_at>clock_timestamp()) or g.id in(select unnest(guild_ids) from guildbattle_test_clock_v4 where singleton)) on conflict do nothing $$;

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

commit;
