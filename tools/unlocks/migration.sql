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
 for rule in select * from jsonb_array_elements('__RPC_GATES__'::jsonb) loop
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

__FACILITY_SQL__

revoke all on function public._unlock_levels(),public._unlock_intros(),public._unlock_require(text),public._unlock_pvp_key(text,text),public._unlock_chapter1(text),public._unlock_intro_eligible(uuid,jsonb),public._unlock_action_done(uuid,text),public._unlock_camp_action() from public,anon,authenticated;
-- CREATE OR REPLACE above does not touch the older helper ACLs; explicitly keep all new helpers private.
revoke all on function public.unlock_status(),public.unlock_intro_claim(text) from public,anon,authenticated;
grant execute on function public.unlock_status(),public.unlock_intro_claim(text) to authenticated;
commit;
notify pgrst,'reload schema';
