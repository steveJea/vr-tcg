-- STAGING ONLY (cuyqchmdcnsgzkwyclji). Single atomic DO block for SQL Editor; idempotent (add-only, config row never overwritten).
-- 출석 보상 2종: 7일 간의 행운 (기준 시각 이후 가입 계정 · 7회 · 가입 후 14일) + 30일 접속 선물 (매달 누적 N회째 = N번 칸, 1일 리셋).
-- Requires: gem.sql (_gem_add) · phaseE (_wallet_add) · trade_drink.sql (_drink_grant_bound) · story gacha (story_gacha) · special_summon_staging.sql (special_wallet).
-- launch_at = first install time (now()). Production file is for the later approved release only.
do $install$
begin
 if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7703759698107299042' then
  raise exception 'STOP: staging cuyqchmdcnsgzkwyclji only'; end if;
 if to_regprocedure('public._gem_add(uuid,integer,integer,text,text,jsonb)') is null or to_regprocedure('public._wallet_add(uuid,jsonb,text)') is null
    or to_regprocedure('public._drink_grant_bound(uuid,integer,text,text)') is null or to_regclass('public.story_gacha') is null or to_regclass('public.special_wallet') is null then
  raise exception 'install gem, wallet, trade_drink, story gacha and special_summon first'; end if;
-- ===== ATTENDANCE =====

-- 설정은 한 줄(id=1). 보상 표·가입 기준 시각·7일 기간을 여기서만 바꿈. rerun 해도 덮어쓰지 않음.
create table if not exists public.attend_config (
 id int primary key check(id=1),
 launch_at timestamptz not null,              -- 7일 간의 행운: 이 시각 이후 가입한 계정만
 lucky_window_days int not null check(lucky_window_days between 7 and 60),
 lucky jsonb not null check(jsonb_typeof(lucky)='array' and jsonb_array_length(lucky)=7),
 monthly_cycle jsonb not null check(jsonb_typeof(monthly_cycle)='array' and jsonb_array_length(monthly_cycle)=7),
 monthly_tail jsonb not null check(jsonb_typeof(monthly_tail)='array' and jsonb_array_length(monthly_tail)=3),   -- 29·30·31회째
 updated_at timestamptz not null default now()
);
insert into public.attend_config(id,launch_at,lucky_window_days,lucky,monthly_cycle,monthly_tail)
values(1,now(),14,'[{"gold":10000},{"drink":2},{"tickets":3},{"gem_free":100},{"tickets":10},{"gold":20000,"blood":20000},{"special_tickets":10}]','[{"gold":3000},{"blood":3000},{"gem_free":20},{"drink":1},{"shard":2000},{"gold":3000,"blood":3000},{"tickets":1}]','[{"tickets":5},{"tickets":5},{"tickets":5}]') on conflict(id) do nothing;
create table if not exists public.attend_log (
 id bigint generated always as identity primary key,
 user_id uuid not null references auth.users(id) on delete cascade,
 track text not null check(track in ('lucky','monthly')),
 day date not null,                           -- KST 날짜. 같은 트랙 하루 1번 (unique)
 month date not null,                         -- KST 그 달 1일
 slot int not null check(slot between 1 and 31),
 reward jsonb not null,
 created_at timestamptz not null default now(),
 unique(user_id,track,day)
);
create unique index if not exists attend_log_slot_uq on public.attend_log(user_id,track,month,slot) where track='monthly';
create unique index if not exists attend_log_lucky_uq on public.attend_log(user_id,slot) where track='lucky';
alter table public.attend_config enable row level security;
alter table public.attend_log enable row level security;
revoke all on public.attend_config,public.attend_log from public,anon,authenticated;
if not exists(select 1 from pg_policies where schemaname='public' and tablename='attend_log' and policyname='attend_log_own') then
 create policy attend_log_own on public.attend_log for select to authenticated using(user_id=auth.uid()); end if;
grant select on public.attend_log to authenticated;
execute $ddl$create or replace function public._attend_day() returns date language sql stable set search_path=pg_catalog as $fn$ select (now() at time zone 'Asia/Seoul')::date $fn$;$ddl$;
execute $ddl$create or replace function public._attend_monthly_reward(c public.attend_config, p_slot int) returns jsonb language sql stable set search_path=pg_catalog,public as $fn$
 select case when p_slot>=29 then c.monthly_tail->(p_slot-29) else c.monthly_cycle->((p_slot-1)%7) end $fn$;$ddl$;
execute $ddl$create or replace function public._attend_grant(p_uid uuid, p_rw jsonb, p_reason text, p_ref text) returns jsonb
language plpgsql security definer set search_path=pg_catalog,public as $fn$
declare k text; v jsonb; n int; out jsonb:='{}'::jsonb; delta jsonb:='{}'::jsonb; t int;
begin
 if jsonb_typeof(p_rw)<>'object' then raise exception 'invalid reward'; end if;
 for k,v in select * from jsonb_each(p_rw) loop
  if k not in ('gold','blood','shard','gem_free','drink','tickets','special_tickets') then raise exception 'invalid reward key %',k; end if;
  if jsonb_typeof(v)<>'number' or v::text ~ '[.eE-]' then raise exception 'invalid reward'; end if;
  n:=v::text::int; if n<=0 or n>1000000 then raise exception 'invalid reward'; end if;
  if k in ('gold','blood','shard') then delta:=delta||jsonb_build_object(k,n);
  elsif k='gem_free' then out:=out||jsonb_build_object('gem',public._gem_add(p_uid,n,0,p_reason,p_ref||':gem',jsonb_build_object('ref',p_ref)));
  elsif k='drink' then out:=out||jsonb_build_object('drink',public._drink_grant_bound(p_uid,n,p_reason,p_ref||':drink'));   -- 귀속(거래 불가)
  elsif k='tickets' then
   insert into public.story_gacha(user_id,last_draw) values(p_uid,public._attend_day()-1) on conflict(user_id) do nothing;
   update public.story_gacha set tickets=tickets+n,updated_at=now() where user_id=p_uid returning tickets into t;
   out:=out||jsonb_build_object('tickets',t);
  else
   insert into public.special_wallet(user_id) values(p_uid) on conflict do nothing;
   update public.special_wallet set tickets=tickets+n where user_id=p_uid returning tickets into t;
   out:=out||jsonb_build_object('special_tickets',t);
  end if;
 end loop;
 if delta<>'{}'::jsonb then out:=out||jsonb_build_object('wallet',public._wallet_add(p_uid,delta,p_reason)); end if;
 return out;
end $fn$;$ddl$;
execute $ddl$create or replace function public.attend_status() returns jsonb
language plpgsql stable security definer set search_path=pg_catalog,public as $fn$
declare u uuid:=auth.uid(); c public.attend_config; today date:=public._attend_day(); mon date:=date_trunc('month',public._attend_day())::date;
 made timestamptz; lc int; lt boolean; mc int; mt boolean; dim int; ends date; why text;
begin
 if u is null then raise exception 'login required'; end if;
 select * into c from public.attend_config where id=1;
 select created_at into made from auth.users where id=u;
 select count(*), bool_or(day=today) into lc,lt from public.attend_log where user_id=u and track='lucky';
 select count(*), bool_or(day=today) into mc,mt from public.attend_log where user_id=u and track='monthly' and month=mon;
 dim:=extract(day from (mon+interval '1 month'-interval '1 day'))::int;
 ends:=(made at time zone 'Asia/Seoul')::date+c.lucky_window_days-1;
 why:=case when made is null or made<c.launch_at then 'old_account' when lc>=7 then 'done' when today>ends then 'expired' else null end;
 return jsonb_build_object('ok',true,'today',today,
  'lucky',jsonb_build_object('eligible',why is null or coalesce(lt,false),'open',why is null,'reason',why,'claims',lc,'claimed_today',coalesce(lt,false),
    'ends',case when why='old_account' then null else ends end,'window_days',c.lucky_window_days,'rewards',c.lucky),
  'monthly',jsonb_build_object('month',mon,'claims',mc,'claimed_today',coalesce(mt,false),'days',dim,
    'rewards',(select jsonb_agg(public._attend_monthly_reward(c,s) order by s) from generate_series(1,dim) s)));
end $fn$;$ddl$;
execute $ddl$create or replace function public.attend_claim(p_track text) returns jsonb
language plpgsql security definer set search_path=pg_catalog,public as $fn$
declare u uuid:=auth.uid(); c public.attend_config; today date:=public._attend_day(); mon date:=date_trunc('month',public._attend_day())::date;
 made timestamptz; n int; rw jsonb; got jsonb; st jsonb;
begin
 if u is null then raise exception 'login required'; end if;
 if p_track is null or p_track not in ('lucky','monthly') then raise exception 'invalid track'; end if;
 perform pg_advisory_xact_lock(hashtext('attend:'||u::text));
 select * into c from public.attend_config where id=1;
 if exists(select 1 from public.attend_log where user_id=u and track=p_track and day=today) then
  return jsonb_build_object('ok',false,'reason','already') || jsonb_build_object('status',public.attend_status()); end if;
 if p_track='lucky' then
  select created_at into made from auth.users where id=u;
  select count(*) into n from public.attend_log where user_id=u and track='lucky';
  if made is null or made<c.launch_at then return jsonb_build_object('ok',false,'reason','old_account'); end if;
  if n>=7 then return jsonb_build_object('ok',false,'reason','done'); end if;
  if today>(made at time zone 'Asia/Seoul')::date+c.lucky_window_days-1 then return jsonb_build_object('ok',false,'reason','expired'); end if;
  n:=n+1; rw:=c.lucky->(n-1);
 else
  select count(*) into n from public.attend_log where user_id=u and track='monthly' and month=mon;
  n:=n+1; rw:=public._attend_monthly_reward(c,n);
 end if;
 insert into public.attend_log(user_id,track,day,month,slot,reward) values(u,p_track,today,mon,n,rw);
 got:=public._attend_grant(u,rw,'attend:'||p_track,'attend:'||p_track||':'||today||':'||n);
 return jsonb_build_object('ok',true,'track',p_track,'slot',n,'reward',rw,'got',got,'status',public.attend_status());
end $fn$;$ddl$;
revoke all on function public._attend_day(),public._attend_monthly_reward(public.attend_config,int),public._attend_grant(uuid,jsonb,text,text) from public,anon,authenticated;
revoke all on function public.attend_status(),public.attend_claim(text) from public,anon;
grant execute on function public.attend_status(),public.attend_claim(text) to authenticated;
end $install$;
notify pgrst, 'reload schema';
