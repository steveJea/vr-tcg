-- STAGING ONLY. Existing installs run this entire file ONCE; reruns are safe.
-- Legacy raid/war history is preserved, never copied as verified evidence.
begin;
do $phase4_staging_guard$ begin
 if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7703759698107299042' then raise exception 'STOP: phase4 only staging cuyqchmdcnsgzkwyclji; production forbidden'; end if;
end $phase4_staging_guard$;
set local check_function_bodies=off;
create table if not exists public.guildbattle_policy_v4(singleton boolean primary key default true check(singleton),engine_hash text not null,enabled boolean not null default true);
insert into public.guildbattle_policy_v4(singleton,engine_hash) values(true,'26b881cf87a09a8f220cc3910106a92542677586c21ca9ce7b3cedb93e32684b') on conflict(singleton) do update set engine_hash=excluded.engine_hash;
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
