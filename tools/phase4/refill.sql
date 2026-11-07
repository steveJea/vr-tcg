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
