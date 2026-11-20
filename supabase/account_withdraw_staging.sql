-- =====================================================================
-- 2026-11-19 회원탈퇴. 탈퇴 신청 후 30일 유예, 그 사이 로그인하면 취소 가능.
-- 실제 삭제 뒤 같은 SNS 신원은 해시만 7일 막아 두었다가 다시 가입 허용.
-- 유료 결제(payment_orders)는 전자상거래법 대비 5년 익명 보관. 게임 데이터·auth 사용자는 삭제.
-- 여러 번 실행해도 안전. STAGING ONLY (cuyqchmdcnsgzkwyclji). system_identifier 7703759698107299042.
-- =====================================================================
begin;
do $guard$
begin
  if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7703759698107299042' then
    raise exception 'STOP: account withdraw is staging cuyqchmdcnsgzkwyclji only; production forbidden';
  end if;
end $guard$;

create table if not exists public.account_withdrawals (
  user_id uuid primary key references auth.users(id) on delete restrict,
  requested_at timestamptz not null default clock_timestamp(),
  purge_at timestamptz not null,
  check (purge_at > requested_at)
);
create index if not exists account_withdrawals_purge_idx on public.account_withdrawals (purge_at);

create table if not exists public.account_withdrawal_hashes (
  user_id uuid not null references public.account_withdrawals(user_id) on delete cascade,
  identity_hash text not null check (identity_hash ~ '^[0-9a-f]{64}$'),
  primary key (user_id, identity_hash)
);

-- 하드 삭제 뒤에만 쌓임. 신원 원문·이메일·user_id 는 보관하지 않음.
create table if not exists public.account_rejoin_blocklist (
  identity_hash text primary key check (identity_hash ~ '^[0-9a-f]{64}$'),
  blocked_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null,
  check (expires_at > blocked_at)
);
create index if not exists account_rejoin_blocklist_exp_idx on public.account_rejoin_blocklist (expires_at);

alter table public.account_withdrawals enable row level security;
alter table public.account_withdrawal_hashes enable row level security;
alter table public.account_rejoin_blocklist enable row level security;
revoke all on public.account_withdrawals, public.account_withdrawal_hashes, public.account_rejoin_blocklist from public, anon, authenticated;
grant select on public.account_withdrawals to authenticated;
drop policy if exists account_withdrawals_own on public.account_withdrawals;
create policy account_withdrawals_own on public.account_withdrawals for select to authenticated using (user_id = auth.uid());
grant all on public.account_withdrawals, public.account_withdrawal_hashes, public.account_rejoin_blocklist to service_role;

-- 결제 기록: 삭제 제한 FK 를 풀고, 사용자만 떼어 5년 익명 보관할 수 있게 함 (테이블이 있을 때만).
do $pay$
declare r record;
begin
  if to_regclass('public.payment_orders') is null then return; end if;
  alter table public.payment_orders add column if not exists user_hash text check (user_hash is null or user_hash ~ '^[0-9a-f]{64}$');
  alter table public.payment_orders add column if not exists retain_until timestamptz;
  for r in
    select con.conname
      from pg_constraint con
     where con.conrelid = 'public.payment_orders'::regclass
       and con.contype = 'f'
       and con.confrelid = 'auth.users'::regclass
  loop
    execute format('alter table public.payment_orders drop constraint %I', r.conname);
  end loop;
  begin
    alter table public.payment_orders alter column user_id drop not null;
  exception when others then null;
  end;
  begin
    alter table public.payment_orders
      add constraint payment_orders_user_id_fkey
      foreign key (user_id) references auth.users(id) on delete set null;
  exception when duplicate_object then null;
  end;
end $pay$;

create or replace function public.account_identity_hash(p_provider text, p_id text)
returns text
language sql
immutable
parallel safe
set search_path = pg_catalog, public, extensions
as $$
  select encode(extensions.digest(convert_to('vr-ag-rejoin-v1|' || coalesce(p_provider, '') || '|' || coalesce(p_id, ''), 'utf8'), 'sha256'), 'hex');
$$;

create or replace function public.account_user_hash(p_uid uuid)
returns text
language sql
immutable
parallel safe
set search_path = pg_catalog, public, extensions
as $$
  select encode(extensions.digest(convert_to('vr-ag-user-v1|' || coalesce(p_uid::text, ''), 'utf8'), 'sha256'), 'hex');
$$;

revoke all on function public.account_identity_hash(text, text), public.account_user_hash(uuid) from public, anon, authenticated;
grant execute on function public.account_identity_hash(text, text), public.account_user_hash(uuid) to service_role;

create or replace function public._account_withdraw_snapshot(p_uid uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
begin
  insert into public.account_withdrawal_hashes (user_id, identity_hash)
  select p_uid, public.account_identity_hash(i.provider, i.provider_id)
    from auth.identities i
   where i.user_id = p_uid
     and coalesce(i.provider_id, '') <> ''
  on conflict do nothing;
end;
$$;

create or replace function public._account_withdraw_leave_guild(p_uid uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  gid bigint;
  role text;
  heir uuid;
begin
  if to_regclass('public.guild_members') is null then return; end if;
  select gm.guild_id, gm.role into gid, role from public.guild_members gm where gm.user_id = p_uid;
  if gid is null then return; end if;
  if to_regprocedure('public._guild_lock(bigint)') is not null then
    perform public._guild_lock(gid);
  end if;
  if role = 'boss' then
    if (select count(*) from public.guild_members where guild_id = gid) = 1 then
      delete from public.guilds where id = gid;
      return;
    end if;
    select user_id into heir
      from public.guild_members
     where guild_id = gid and user_id <> p_uid
     order by (role = 'officer') desc,
              case when role = 'officer' then extract(epoch from joined_at) else -coalesce(loyalty_total, 0) end,
              joined_at
     limit 1;
    if heir is null then
      delete from public.guilds where id = gid;
      return;
    end if;
    update public.guild_members set role = 'boss' where user_id = heir;
    update public.guilds set boss = heir where id = gid;
  end if;
  delete from public.guild_members where user_id = p_uid;
end;
$$;

create or replace function public._account_withdraw_anonymize_payments(p_uid uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if to_regclass('public.payment_orders') is null then return; end if;
  -- 결제되지 않은 주문은 법정 보관 대상이 아니므로 지움
  delete from public.payment_orders
   where user_id = p_uid and status is distinct from 'paid';
  update public.payment_orders
     set user_hash = coalesce(user_hash, public.account_user_hash(p_uid)),
         retain_until = coalesce(retain_until, coalesce(paid_at, created_at) + interval '5 years'),
         receipt = case
           when receipt is null then receipt
           else (receipt - 'wallet' - 'user_id' - 'uid' - 'email' - 'nickname')
         end,
         user_id = null
   where user_id = p_uid;
end;
$$;

create or replace function public._account_withdraw_detach(p_uid uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare r record;
begin
  perform public._account_withdraw_leave_guild(p_uid);
  perform public._account_withdraw_anonymize_payments(p_uid);
  for r in
    select n.nspname as sch, c.relname as tbl, a.attname as col, con.confdeltype, a.attnotnull
      from pg_constraint con
      join pg_class c on c.oid = con.conrelid
      join pg_namespace n on n.oid = c.relnamespace
      join unnest(con.conkey) with ordinality as k(attnum, ord) on true
      join pg_attribute a on a.attrelid = c.oid and a.attnum = k.attnum
     where con.contype = 'f'
       and con.confrelid = 'auth.users'::regclass
       and n.nspname = 'public'
       and c.relname not in ('account_withdrawals', 'account_withdrawal_hashes', 'payment_orders')
  loop
    if r.confdeltype in ('c', 'n', 'd') then
      continue;
    elsif not r.attnotnull then
      execute format('update %I.%I set %I = null where %I = $1', r.sch, r.tbl, r.col, r.col) using p_uid;
    else
      execute format('delete from %I.%I where %I = $1', r.sch, r.tbl, r.col) using p_uid;
    end if;
  end loop;
end;
$$;

create or replace function public._account_withdraw_purge_one(p_uid uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
begin
  perform public._account_withdraw_snapshot(p_uid);
  insert into public.account_rejoin_blocklist (identity_hash, expires_at)
  select h.identity_hash, clock_timestamp() + interval '7 days'
    from public.account_withdrawal_hashes h
   where h.user_id = p_uid
  on conflict (identity_hash) do update
    set expires_at = greatest(public.account_rejoin_blocklist.expires_at, excluded.expires_at),
        blocked_at = clock_timestamp();
  perform public._account_withdraw_detach(p_uid);
  delete from public.account_withdrawals where user_id = p_uid;
  delete from auth.users where id = p_uid;
end;
$$;

create or replace function public.account_withdraw_status()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  uid uuid := auth.uid();
  w public.account_withdrawals;
  days numeric;
begin
  if uid is null then raise exception 'login required'; end if;
  select * into w from public.account_withdrawals where user_id = uid;
  if not found then
    return jsonb_build_object('ok', true, 'scheduled', false);
  end if;
  days := ceil(extract(epoch from (w.purge_at - clock_timestamp())) / 86400.0);
  return jsonb_build_object(
    'ok', true,
    'scheduled', true,
    'requested_at', w.requested_at,
    'purge_at', w.purge_at,
    'days_left', greatest(0, days::int)
  );
end;
$$;

create or replace function public.account_withdraw_request(p_confirm text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  uid uuid := auth.uid();
  w public.account_withdrawals;
begin
  if uid is null then raise exception 'login required'; end if;
  if p_confirm is distinct from '탈퇴' then raise exception 'confirm required'; end if;
  perform pg_advisory_xact_lock(hashtextextended('account-withdraw:' || uid::text, 0));
  select * into w from public.account_withdrawals where user_id = uid;
  if found then
    perform public._account_withdraw_snapshot(uid);
    return public.account_withdraw_status();
  end if;
  insert into public.account_withdrawals (user_id, purge_at)
  values (uid, clock_timestamp() + interval '30 days')
  returning * into w;
  perform public._account_withdraw_snapshot(uid);
  return public.account_withdraw_status();
end;
$$;

create or replace function public.account_withdraw_cancel()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtextextended('account-withdraw:' || uid::text, 0));
  delete from public.account_withdrawals where user_id = uid;
  return jsonb_build_object('ok', true, 'scheduled', false);
end;
$$;

create or replace function public.account_withdraw_purge_due(p_limit integer default 50)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  r record;
  n int := 0;
  failed int := 0;
  lim int := coalesce(p_limit, 50);
begin
  if lim < 1 then lim := 1; end if;
  if lim > 200 then lim := 200; end if;
  for r in
    select user_id from public.account_withdrawals
     where purge_at <= clock_timestamp()
     order by purge_at
     limit lim
     for update skip locked
  loop
    begin
      perform public._account_withdraw_purge_one(r.user_id);
      n := n + 1;
    exception when others then
      failed := failed + 1;
      raise warning 'account_withdraw_purge_one % failed: %', r.user_id, sqlerrm;
    end;
  end loop;
  delete from public.account_rejoin_blocklist where expires_at <= clock_timestamp();
  return jsonb_build_object('ok', true, 'purged', n, 'failed', failed);
end;
$$;

create or replace function public.account_rejoin_guard()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if exists (
    select 1 from public.account_rejoin_blocklist b
     where b.identity_hash = public.account_identity_hash(new.provider, new.provider_id)
       and b.expires_at > clock_timestamp()
  ) then
    raise exception 'rejoin_blocked' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists account_rejoin_guard on auth.identities;
create trigger account_rejoin_guard
  before insert or update of provider, provider_id on auth.identities
  for each row execute function public.account_rejoin_guard();

create or replace function public.account_withdraw_install_ok()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare cron_on boolean := false;
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    execute $q$select exists (select 1 from cron.job where jobname = 'account_withdraw_purge')$q$ into cron_on;
  end if;
  return jsonb_build_object(
    'ok',
      to_regclass('public.account_withdrawals') is not null
      and to_regclass('public.account_withdrawal_hashes') is not null
      and to_regclass('public.account_rejoin_blocklist') is not null
      and to_regprocedure('public.account_withdraw_request(text)') is not null
      and to_regprocedure('public.account_withdraw_cancel()') is not null
      and to_regprocedure('public.account_withdraw_status()') is not null
      and to_regprocedure('public.account_withdraw_purge_due(integer)') is not null
      and exists (
        select 1 from pg_trigger t
          join pg_class c on c.oid = t.tgrelid
          join pg_namespace n on n.oid = c.relnamespace
         where n.nspname = 'auth' and c.relname = 'identities' and t.tgname = 'account_rejoin_guard' and not t.tgisinternal
      ),
    'cron_on', cron_on
  );
end;
$$;

revoke all on function
  public._account_withdraw_snapshot(uuid),
  public._account_withdraw_leave_guild(uuid),
  public._account_withdraw_anonymize_payments(uuid),
  public._account_withdraw_detach(uuid),
  public._account_withdraw_purge_one(uuid),
  public.account_withdraw_status(),
  public.account_withdraw_request(text),
  public.account_withdraw_cancel(),
  public.account_withdraw_purge_due(integer),
  public.account_rejoin_guard(),
  public.account_withdraw_install_ok()
from public, anon, authenticated;

grant execute on function
  public.account_withdraw_status(),
  public.account_withdraw_request(text),
  public.account_withdraw_cancel(),
  public.account_withdraw_install_ok()
to authenticated;

grant execute on function public.account_withdraw_purge_due(integer) to service_role;

do $cron$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    begin
      perform cron.unschedule('account_withdraw_purge');
    exception when others then null;
    end;
    perform cron.schedule('account_withdraw_purge', '20 * * * *', 'select public.account_withdraw_purge_due(50)');
  else
    raise notice 'pg_cron 이 없음. 매일 SQL Editor 에서 select public.account_withdraw_purge_due(50); 를 실행하세요.';
  end if;
end $cron$;

notify pgrst, 'reload schema';
commit;
select public.account_withdraw_install_ok() as result;
