-- ===== 거래 PR2: 체력의 드링크 🥤 =====
-- 선행: gem.sql (player_wallet.gem_free/gem_paid · _gem_add) · phaseE_2.sql (_player_sync · _player_stamina_add). 여러 번 실행해도 안전
-- 유료 심연석으로만 구매 → 거래 가능분(tradable). 이벤트·보상·운영 지급 → 귀속분(bound). 거래에 묶인 분(locked)은 거래 PR 에서 사용
-- 사용: 1개당 행동력 +200, 최대치를 넘어도 쌓이지만 상한(임시 999)을 넘게는 못 씀. 귀속분부터 사용

create table if not exists public.player_items (
  user_id    uuid not null references auth.users(id) on delete cascade,
  item       text not null check (item in ('drink')),
  tradable   int  not null default 0 check (tradable >= 0),
  bound      int  not null default 0 check (bound >= 0),
  locked     int  not null default 0 check (locked >= 0 and locked <= tradable),
  updated_at timestamptz not null default now(),
  primary key (user_id, item)
);
alter table public.player_items enable row level security;
revoke all on public.player_items from public, anon, authenticated;

create table if not exists public.item_log (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references auth.users(id) on delete cascade,
  item       text not null,
  d_tradable int  not null default 0,
  d_bound    int  not null default 0,
  tradable_after int not null,
  bound_after    int not null,
  reason     text not null check (char_length(reason) <= 40),   -- buy:<sku> · use · event · admin · trade(나중)
  ref        text not null default gen_random_uuid()::text,
  meta       jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (user_id, ref)
);
create index if not exists item_log_user_idx on public.item_log (user_id, created_at desc);
alter table public.item_log enable row level security;
revoke all on public.item_log from public, anon, authenticated;

-- 판매 상품 (조정 가능, 임시값). price = 유료 심연석
create table if not exists public.drink_shop (
  sku    text primary key,
  qty    int  not null check (qty > 0),
  price  int  not null check (price > 0),
  ord    int  not null default 0,
  active boolean not null default true
);
insert into public.drink_shop (sku, qty, price, ord) values ('drink1', 1, 100, 1), ('drink10', 10, 950, 2), ('drink30', 30, 2700, 3)
on conflict (sku) do nothing;
alter table public.drink_shop enable row level security;
revoke all on public.drink_shop from public, anon, authenticated;

create table if not exists public.drink_config (key text primary key, val int not null);
insert into public.drink_config values ('stamina_per', 200), ('stamina_cap', 999) on conflict (key) do nothing;
alter table public.drink_config enable row level security;
revoke all on public.drink_config from public, anon, authenticated;
create or replace function public._drink_cfg(k text) returns int language sql stable security definer set search_path = public as $$ select val from drink_config where key = k $$;

-- 내부: 증감 + 기록. p_ref 같으면 한 번만
create or replace function public._item_add(p_uid uuid, p_item text, p_trad int, p_bound int, p_reason text, p_ref text, p_meta jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r player_items;
begin
  if p_uid is null then raise exception 'login required'; end if;
  insert into player_items (user_id, item) values (p_uid, p_item) on conflict do nothing;
  select * into r from player_items where user_id = p_uid and item = p_item for update;
  if p_ref is not null and exists (select 1 from item_log where user_id = p_uid and ref = p_ref) then return null; end if;
  if r.tradable + coalesce(p_trad, 0) < r.locked or r.bound + coalesce(p_bound, 0) < 0 then raise exception 'not enough drink'; end if;
  update player_items set tradable = tradable + coalesce(p_trad, 0), bound = bound + coalesce(p_bound, 0), updated_at = now()
    where user_id = p_uid and item = p_item returning * into r;
  insert into item_log (user_id, item, d_tradable, d_bound, tradable_after, bound_after, reason, ref, meta)
  values (p_uid, p_item, coalesce(p_trad, 0), coalesce(p_bound, 0), r.tradable, r.bound, left(p_reason, 40), coalesce(p_ref, gen_random_uuid()::text), coalesce(p_meta, '{}'::jsonb));
  return jsonb_build_object('tradable', r.tradable, 'bound', r.bound, 'locked', r.locked, 'total', r.tradable + r.bound);
end $$;

-- 이벤트·보상용 지급 (항상 귀속). 다른 서버 함수에서 perform _drink_grant_bound(uid, n, 'event', 'event:<id>')
create or replace function public._drink_grant_bound(p_uid uuid, p_n int, p_reason text, p_ref text) returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if p_n is null or p_n <= 0 then raise exception 'invalid amount'; end if;
  return _item_add(p_uid, 'drink', 0, p_n, p_reason, p_ref, '{}'::jsonb);
end $$;

create or replace function public._drink_json(p_uid uuid) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare r player_items; w player_wallet;
begin
  select * into r from player_items where user_id = p_uid and item = 'drink';
  select * into w from player_wallet where user_id = p_uid;
  return jsonb_build_object('ok', true, 'tradable', coalesce(r.tradable, 0), 'bound', coalesce(r.bound, 0), 'locked', coalesce(r.locked, 0),
    'total', coalesce(r.tradable, 0) + coalesce(r.bound, 0), 'paid_gem', coalesce(w.gem_paid, 0),
    'per', _drink_cfg('stamina_per'), 'cap', _drink_cfg('stamina_cap'),
    'shop', (select coalesce(jsonb_agg(jsonb_build_object('sku', sku, 'qty', qty, 'price', price) order by ord), '[]'::jsonb) from drink_shop where active));
end $$;

create or replace function public.drink_status() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'login required'; end if;
  return _drink_json(auth.uid());
end $$;

-- 구매: 유료 심연석만 차감 (무료분은 안 씀)
create or replace function public.drink_buy(p_sku text) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); s drink_shop; g jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('gem:' || uid::text));
  select * into s from drink_shop where sku = p_sku and active;
  if s.sku is null then raise exception 'invalid item'; end if;
  insert into player_wallet (user_id) values (uid) on conflict (user_id) do nothing;
  if (select gem_paid from player_wallet where user_id = uid) < s.price then raise exception 'not enough paid gem'; end if;
  g := _gem_add(uid, 0, -s.price, 'buy:' || s.sku, null, jsonb_build_object('qty', s.qty, 'price', s.price));
  perform _item_add(uid, 'drink', s.qty, 0, 'buy:' || s.sku, null, jsonb_build_object('paid_gem', s.price));
  return _drink_json(uid) || jsonb_build_object('gem', g, 'bought', s.qty);
end $$;

-- 사용: 귀속분 먼저, 그다음 거래 가능분(묶인 분 제외). 상한을 넘기면 거부
create or replace function public.drink_use(p_n int default 1) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); r player_items; ps player_state; per int := _drink_cfg('stamina_per'); cap int := _drink_cfg('stamina_cap'); fb int; ft int; st int;
begin
  if uid is null then raise exception 'login required'; end if;
  if p_n is null or p_n < 1 or p_n > 100 then raise exception 'invalid amount'; end if;
  perform pg_advisory_xact_lock(hashtext('gem:' || uid::text));
  select * into r from player_items where user_id = uid and item = 'drink' for update;
  if r.user_id is null or r.bound + r.tradable - r.locked < p_n then raise exception 'not enough drink'; end if;
  ps := _player_sync(uid);
  if ps.stamina + per * p_n > cap then raise exception 'stamina cap'; end if;
  fb := least(r.bound, p_n); ft := p_n - fb;
  perform _item_add(uid, 'drink', -ft, -fb, 'use', null, jsonb_build_object('n', p_n, 'stamina_before', ps.stamina));
  st := _player_stamina_add(uid, per * p_n);
  return _drink_json(uid) || jsonb_build_object('stamina', st, 'used', p_n);
end $$;

-- 운영 지급 (귀속, 음수면 회수: 귀속분에서만)
create or replace function public.admin_grant_drink(p_user uuid, p_n int, p_reason text) returns jsonb language plpgsql volatile security definer set search_path = public, auth as $$
declare res jsonb;
begin
  perform public._admin_guard();
  if p_n is null or p_n = 0 or abs(p_n) > 100000 then raise exception 'amount must be ±1..100000'; end if;
  if coalesce(btrim(p_reason), '') = '' then raise exception 'reason required'; end if;
  if not exists (select 1 from auth.users where id = p_user) then raise exception 'no such user'; end if;
  res := _item_add(p_user, 'drink', 0, p_n, 'admin', null, jsonb_build_object('by', auth.jwt()->>'email', 'memo', left(btrim(p_reason), 200)));
  insert into public.admin_log (admin_id, admin_email, action, target_user, amount, reason, before_val, after_val)
  values (auth.uid(), auth.jwt()->>'email', 'grant_drink', p_user, p_n, left(btrim(p_reason), 200), (res->>'bound')::int - p_n, (res->>'bound')::int);
  return res || jsonb_build_object('ok', true);
end $$;

revoke all on function public._drink_cfg(text), public._item_add(uuid, text, int, int, text, text, jsonb), public._drink_grant_bound(uuid, int, text, text), public._drink_json(uuid) from public, anon, authenticated;
revoke all on function public.drink_status(), public.drink_buy(text), public.drink_use(int), public.admin_grant_drink(uuid, int, text) from public, anon;
grant execute on function public.drink_status(), public.drink_buy(text), public.drink_use(int), public.admin_grant_drink(uuid, int, text) to authenticated;
