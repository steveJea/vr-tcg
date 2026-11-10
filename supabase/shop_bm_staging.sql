-- STAGING ONLY — cuyqchmdcnsgzkwyclji (system_identifier 7703759698107299042).
-- 운영 DB에서 실행하지 마세요. 기존 유저·주문·지갑을 지우지 않습니다. 여러 번 실행해도 됩니다.
-- 이 파일이 2026-11-10 BM 상점의 적용본입니다. 빈 설치본(staging/01~)은 다시 붙이지 마세요.
--
-- 첫 구매 200% = 2배 (3배 아님). 상품마다 한 번.
--   구매자는 표기 수량에 같은 양을 한 번 더 받습니다. 100 → 총 200.
--   gem_500 의 25는 표기 525 안의 기본 보너스(유료 500+무료 25)이고, 첫 구매 때 그것도 같이 2배가 됩니다 (유료 1,000+무료 50).
--   같은 SKU 를 이미 결제한 계정은 첫 구매를 쓴 것으로 봅니다. gem_55000 만 새 상품이라 전원이 첫 구매 대상입니다.
-- 토스 실결제는 기존 심연석 주문(payment_*)만 탑니다. 소환권·레벨업 팩·시즌패스는 결제창을 새로 만들지 않고
--   shop_buy 로 이 테스트 DB에서만 지급합니다 (함수가 식별번호를 다시 확인).
-- 드링크는 KRW 가 아닙니다. drink_buy 가 무료 심연석을 먼저 쓰고 모자라면 유료를 씁니다.
--
-- SQL 편집기에 이 파일 전체를 한 번에 붙여 실행하세요. 임시 테이블은 쓰지 않습니다.
begin;
do $shop_guard$
begin
 if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7703759698107299042' then
  raise exception 'STOP: shop staging cuyqchmdcnsgzkwyclji only';
 end if;
 if to_regprocedure('public._gem_add(uuid,integer,integer,text,text,jsonb)') is null
    or to_regprocedure('public._gem_spend(uuid,integer,text,jsonb)') is null
    or to_regprocedure('public.drink_buy(text)') is null
    or to_regprocedure('public._wallet_add(uuid,jsonb,text)') is null
    or to_regprocedure('public._player_stamina_add(uuid,integer)') is null then
  raise exception 'Install gem, wallet, stamina and drink first';
 end if;
end $shop_guard$;

create or replace function public._shop_guard() returns void language plpgsql security definer set search_path=pg_catalog,public as $$
begin
 if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7703759698107299042' then
  raise exception 'shop unavailable';
 end if;
end $$;

create or replace function public._shop_day() returns date language sql stable as $$
 select (now() at time zone 'Asia/Seoul')::date $$;
create or replace function public._shop_month() returns date language sql stable as $$
 select date_trunc('month', now() at time zone 'Asia/Seoul')::date $$;

-- 충전·패키지·패스. 스킨 상품은 만들지 않음. 드링크는 drink_shop.
create table if not exists public.shop_products (
 sku text primary key check (sku ~ '^[a-z][a-z0-9_]{0,40}$'),
 tab text not null check (tab in ('charge','pack','pass')),
 name text not null check (char_length(name) between 1 and 40),
 blurb text not null default '' check (char_length(blurb) <= 200),
 price_krw integer not null check (price_krw between 100 and 1000000),
 month_max integer check (month_max is null or (month_max between 1 and 100)),
 sort integer not null default 0,
 active boolean not null default true,
 reward jsonb not null,
 payment_sku text
);
-- 재실행은 BM 숫자로 되돌립니다. 구매 기록은 지우지 않습니다.
insert into public.shop_products (sku,tab,name,blurb,price_krw,month_max,sort,reward,payment_sku) values
 ('gem_100','charge','심연석 100','첫 구매 2배',1100,null,1,'{"gem_paid":100,"gem_free":0,"first_double":true}','gem_100'),
 ('gem_500','charge','심연석 525','유료 500 + 보너스 25 · 첫 구매 2배',5500,null,2,'{"gem_paid":500,"gem_free":25,"first_double":true}','gem_500'),
 ('gem_1000','charge','심연석 1,050','첫 구매 2배',11000,null,3,'{"gem_paid":1050,"gem_free":0,"first_double":true}','gem_1000'),
 ('gem_3000','charge','심연석 3,200','첫 구매 2배',33000,null,4,'{"gem_paid":3200,"gem_free":0,"first_double":true}','gem_3000'),
 ('gem_55000','charge','심연석 5,500','첫 구매 2배',55000,null,5,'{"gem_paid":5500,"gem_free":0,"first_double":true}','gem_55000'),
 ('ticket_10','pack','스페셜 소환권 10장','월 1회',1100,1,10,'{"tickets":10}',null),
 ('ticket_45','pack','스페셜 소환권 45장','월 1회',5500,1,11,'{"tickets":45}',null),
 ('ticket_160','pack','스페셜 소환권 160장','월 2회',22000,2,12,'{"tickets":160}',null),
 ('ticket_220','pack','스페셜 소환권 220장','구매 제한 없음',33000,null,13,'{"tickets":220}',null),
 ('level_1','pack','레벨업 팩','골드 150,000 · 피 150,000 · 조각 50,000 · 월 2회',22000,2,20,'{"gold":150000,"blood":150000,"shard":50000}',null),
 ('pass_1','pass','시즌패스 1','30일 · 매일 소환권 1, 행동력 100, 골드 5,000',5500,null,30,'{"pass":true,"days":30,"first":{},"daily":{"tickets":1,"stamina":100,"gold":5000}}',null),
 ('pass_2','pass','시즌패스 2','즉시 소환권 10 · 매일 소환권 1, 행동력 150, 골드 10,000, 무료 심연석 50',22000,null,31,'{"pass":true,"days":30,"first":{"tickets":10},"daily":{"tickets":1,"stamina":150,"gold":10000,"gem_free":50}}',null),
 ('pass_3','pass','시즌패스 3','즉시 소환권 30 + 유료 심연석 300 · 매일 소환권 1, 무료 심연석 100, 행동력 200, 골드·피·조각 10,000',44000,null,32,'{"pass":true,"days":30,"first":{"tickets":30,"gem_paid":300},"daily":{"tickets":1,"stamina":200,"gold":10000,"blood":10000,"shard":10000,"gem_free":100}}',null)
on conflict (sku) do update set tab=excluded.tab, name=excluded.name, blurb=excluded.blurb, price_krw=excluded.price_krw,
 month_max=excluded.month_max, sort=excluded.sort, active=true, reward=excluded.reward, payment_sku=excluded.payment_sku;

create table if not exists public.shop_purchases (
 id bigint generated always as identity primary key,
 user_id uuid not null references auth.users(id) on delete cascade,
 sku text not null,
 ym date not null,
 first_bonus boolean not null default false,
 created_at timestamptz not null default clock_timestamp()
);
create index if not exists shop_purchases_user_sku_ym on public.shop_purchases (user_id, sku, ym);
create table if not exists public.shop_passes (
 user_id uuid not null references auth.users(id) on delete cascade,
 sku text not null,
 seq integer not null check (seq > 0),
 starts_on date not null,
 ends_on date not null,
 primary key (user_id, sku, seq),
 check (ends_on >= starts_on)
);
create table if not exists public.shop_pass_claims (
 user_id uuid not null,
 sku text not null,
 seq integer not null,
 day date not null,
 primary key (user_id, sku, seq, day),
 foreign key (user_id, sku, seq) references public.shop_passes (user_id, sku, seq) on delete cascade
);
alter table public.shop_products enable row level security;
alter table public.shop_purchases enable row level security;
alter table public.shop_passes enable row level security;
alter table public.shop_pass_claims enable row level security;
revoke all on public.shop_products, public.shop_purchases, public.shop_passes, public.shop_pass_claims from public, anon, authenticated;

-- 드링크 가격 확정 + 무료 심연석 우선 차감. 산 것은 거래 가능, 이벤트/운영 지급은 귀속 그대로.
insert into public.drink_shop (sku, qty, price, ord) values
 ('drink1', 1, 100, 1), ('drink10', 10, 950, 2), ('drink30', 30, 2700, 3)
on conflict (sku) do update set qty=excluded.qty, price=excluded.price, ord=excluded.ord, active=true;
create or replace function public.drink_buy(p_sku text) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); s drink_shop; g jsonb;
begin
 if uid is null then raise exception 'login required'; end if;
 perform pg_advisory_xact_lock(hashtext('gem:' || uid::text));
 select * into s from drink_shop where sku = p_sku and active;
 if s.sku is null then raise exception 'invalid item'; end if;
 insert into player_wallet (user_id) values (uid) on conflict (user_id) do nothing;
 g := _gem_spend(uid, s.price, 'buy:' || s.sku, jsonb_build_object('qty', s.qty, 'price', s.price));
 perform _item_add(uid, 'drink', s.qty, 0, 'buy:' || s.sku, null, jsonb_build_object('price', s.price));
 return _drink_json(uid) || jsonb_build_object('gem', g, 'bought', s.qty);
end $$;
create or replace function public._drink_json(p_uid uuid) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare r player_items; w player_wallet;
begin
 select * into r from player_items where user_id = p_uid and item = 'drink';
 select * into w from player_wallet where user_id = p_uid;
 return jsonb_build_object('ok', true, 'tradable', coalesce(r.tradable, 0), 'bound', coalesce(r.bound, 0), 'locked', coalesce(r.locked, 0),
  'total', coalesce(r.tradable, 0) + coalesce(r.bound, 0), 'paid_gem', coalesce(w.gem_paid, 0), 'free_gem', coalesce(w.gem_free, 0),
  'per', _drink_cfg('stamina_per'), 'cap', _drink_cfg('stamina_cap'),
  'shop', (select coalesce(jsonb_agg(jsonb_build_object('sku', sku, 'qty', qty, 'price', price) order by ord), '[]'::jsonb) from drink_shop where active));
end $$;

create or replace function public._shop_apply(p_uid uuid, p_grant jsonb, p_reason text, p_ref text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare g jsonb := coalesce(p_grant, '{}'::jsonb);
 n_paid int := coalesce((g->>'gem_paid')::int, 0);
 n_free int := coalesce((g->>'gem_free')::int, 0);
 n_tickets int := coalesce((g->>'tickets')::int, 0);
 n_stamina int := coalesce((g->>'stamina')::int, 0);
 n_gold int := coalesce((g->>'gold')::int, 0);
 n_blood int := coalesce((g->>'blood')::int, 0);
 n_shard int := coalesce((g->>'shard')::int, 0);
 out jsonb := '{}'::jsonb; w jsonb; t int; st int; delta jsonb := '{}'::jsonb;
begin
 if p_uid is null then raise exception 'login required'; end if;
 if n_paid < 0 or n_free < 0 or n_tickets < 0 or n_stamina < 0 or n_gold < 0 or n_blood < 0 or n_shard < 0 then raise exception 'invalid grant'; end if;
 if n_paid > 100000 or n_free > 100000 or n_tickets > 100000 or n_stamina > 100000 then raise exception 'invalid grant'; end if;
 if n_gold > 10000000 or n_blood > 10000000 or n_shard > 10000000 then raise exception 'invalid grant'; end if;
 if n_paid <> 0 or n_free <> 0 then
  w := _gem_add(p_uid, n_free, n_paid, left(p_reason, 40), p_ref, g);
  out := out || jsonb_build_object('gem', w);
 end if;
 if n_gold <> 0 then delta := delta || jsonb_build_object('gold', n_gold); end if;
 if n_blood <> 0 then delta := delta || jsonb_build_object('blood', n_blood); end if;
 if n_shard <> 0 then delta := delta || jsonb_build_object('shard', n_shard); end if;
 if delta <> '{}'::jsonb then
  w := _wallet_add(p_uid, delta, left(p_reason, 60));
  out := out || jsonb_build_object('wallet', w);
 end if;
 if n_tickets <> 0 then
  insert into story_gacha (user_id, last_draw) values (p_uid, (now() at time zone 'Asia/Seoul')::date - 1) on conflict (user_id) do nothing;
  update story_gacha set tickets = story_gacha.tickets + n_tickets, updated_at = now() where user_id = p_uid returning tickets into t;
  out := out || jsonb_build_object('tickets', t);
 end if;
 if n_stamina <> 0 then
  st := _player_stamina_add(p_uid, n_stamina);
  out := out || jsonb_build_object('stamina', st);
 end if;
 return out;
end $$;

create or replace function public.shop_status() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); w player_wallet; today date := public._shop_day(); mon date := public._shop_month();
begin
 perform public._shop_guard();
 if uid is null then raise exception 'login required'; end if;
 select * into w from player_wallet where user_id = uid;
 return jsonb_build_object(
  'ok', true,
  'gem', coalesce(w.gem_free,0)+coalesce(w.gem_paid,0),
  'free', coalesce(w.gem_free,0),
  'paid', coalesce(w.gem_paid,0),
  'month', mon, 'today', today,
  'products', (
    select coalesce(jsonb_agg(jsonb_build_object(
      'sku', p.sku, 'tab', p.tab, 'name', p.name, 'blurb', p.blurb, 'price_krw', p.price_krw,
      'month_max', p.month_max,
      'month_used', (select count(*)::int from shop_purchases s where s.user_id=uid and s.sku=p.sku and s.ym=mon),
      'sort', p.sort, 'grant', p.reward, 'payment_sku', p.payment_sku,
      'first_open', coalesce((p.reward->>'first_double')::boolean, false)
        and not exists (select 1 from shop_purchases s where s.user_id=uid and s.sku=p.sku and s.first_bonus)
        and (p.payment_sku is null or to_regclass('public.payment_orders') is null or not exists (
          select 1 from payment_orders o where o.user_id=uid and o.product_id=p.payment_sku and o.status='paid'))
    ) order by p.sort), '[]'::jsonb)
    from shop_products p where p.active),
  'passes', (
    select coalesce(jsonb_agg(jsonb_build_object(
      'sku', sp.sku, 'seq', sp.seq, 'starts_on', sp.starts_on, 'ends_on', sp.ends_on,
      'state', case when sp.starts_on > today then 'queued' when sp.ends_on < today then 'ended' else 'active' end,
      'claimed_today', exists (select 1 from shop_pass_claims c where c.user_id=sp.user_id and c.sku=sp.sku and c.seq=sp.seq and c.day=today)
    ) order by sp.sku, sp.seq), '[]'::jsonb)
    from shop_passes sp where sp.user_id=uid));
end $$;

-- 테스트 DB에서 KRW 상품을 실제로 지급. 토스 주문은 만들지 않습니다. 식별번호가 다르면 거절.
create or replace function public.shop_buy(p_sku text) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); p shop_products; mon date := public._shop_month(); today date := public._shop_day();
 pid bigint; g jsonb; granted jsonb; doubled boolean := false; open_first boolean;
 days int; seq int; last_end date; start_on date;
begin
 perform public._shop_guard();
 if uid is null then raise exception 'login required'; end if;
 if p_sku is null then raise exception 'invalid item'; end if;
 perform pg_advisory_xact_lock(hashtext('gem:' || uid::text));
 perform pg_advisory_xact_lock(hashtextextended('payments:' || uid::text, 0));
 if (select count(*) from shop_purchases where user_id=uid and created_at > clock_timestamp() - interval '1 minute') >= 40
    or (select count(*) from shop_purchases where user_id=uid and created_at > clock_timestamp() - interval '1 day') >= 300 then
  raise exception 'rate limited';
 end if;
 select * into p from shop_products where sku=p_sku and active;
 if p.sku is null then raise exception 'invalid item'; end if;
 if p.month_max is not null and (select count(*) from shop_purchases s where s.user_id=uid and s.sku=p.sku and s.ym=mon) >= p.month_max then
  raise exception 'monthly limit';
 end if;
 insert into shop_purchases (user_id, sku, ym) values (uid, p.sku, mon) returning id into pid;
 if coalesce((p.reward->>'pass')::boolean, false) then
  days := coalesce((p.reward->>'days')::int, 30);
  if days < 1 or days > 90 then raise exception 'invalid grant'; end if;
  select coalesce(max(sp.seq),0)+1, max(sp.ends_on) into seq, last_end from shop_passes sp where sp.user_id=uid and sp.sku=p.sku;
  if last_end is null or last_end < today then start_on := today; else start_on := last_end + 1; end if;
  insert into shop_passes (user_id, sku, seq, starts_on, ends_on) values (uid, p.sku, seq, start_on, start_on + (days - 1));
  granted := public._shop_apply(uid, coalesce(p.reward->'first', '{}'::jsonb), 'shop:'||p.sku, 'shop-first:'||pid);
 else
  g := ((p.reward - 'first_double') - 'pass') - 'days';
  g := (g - 'first') - 'daily';
  if coalesce((p.reward->>'first_double')::boolean, false) then
   open_first := not exists (select 1 from shop_purchases where user_id=uid and sku=p.sku and first_bonus and id<>pid)
    and (p.payment_sku is null or to_regclass('public.payment_orders') is null or not exists (
      select 1 from payment_orders o where o.user_id=uid and o.product_id=p.payment_sku and o.status='paid'));
   if open_first then
    doubled := true;
    g := g || jsonb_build_object('gem_paid', coalesce((g->>'gem_paid')::int,0)*2, 'gem_free', coalesce((g->>'gem_free')::int,0)*2);
    update shop_purchases set first_bonus=true where id=pid;
   end if;
  end if;
  granted := public._shop_apply(uid, g, 'shop:'||p.sku, 'shop:'||pid);
 end if;
 return public.shop_status() || jsonb_build_object('bought', p.sku, 'grant', granted, 'first_bonus', doubled);
end $$;

-- 오늘(KST) 활성 패스의 일일 보상. 놓친 날은 채우지 않습니다. 같은 상품은 기간이 끝난 뒤 이어 붙습니다.
create or replace function public.shop_pass_claim() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); today date := public._shop_day(); r record; n int; one jsonb; got jsonb := '[]'::jsonb;
begin
 perform public._shop_guard();
 if uid is null then raise exception 'login required'; end if;
 perform pg_advisory_xact_lock(hashtext('gem:' || uid::text));
 for r in
  select sp.sku, sp.seq, p.reward
  from shop_passes sp join shop_products p on p.sku=sp.sku
  where sp.user_id=uid and sp.starts_on<=today and sp.ends_on>=today
  order by sp.sku, sp.seq
 loop
  insert into shop_pass_claims (user_id, sku, seq, day) values (uid, r.sku, r.seq, today) on conflict do nothing;
  get diagnostics n = row_count;
  if n = 1 then
   one := public._shop_apply(uid, coalesce(r.reward->'daily', '{}'::jsonb), 'pass:'||r.sku, 'pass-day:'||r.sku||':'||r.seq||':'||today);
   got := got || jsonb_build_array(jsonb_build_object('sku', r.sku, 'seq', r.seq, 'grant', one));
  end if;
 end loop;
 return public.shop_status() || jsonb_build_object('claimed', got);
end $$;

-- 이미 깔린 심연석 결제 상품을 BM 수량으로 고치고, 정산 함수에 2배를 넣습니다.
-- 환불 래퍼(_payment_settle_v1)는 건드리지 않습니다. 원본이 _payment_settle_base_v1 로 옮겨져 있으면 그것만 바꿉니다.
do $sync_pay$
begin
 if to_regclass('public.payment_products') is null then return; end if;
 if to_regclass('public.payment_orders') is not null then
  alter table public.payment_orders add column if not exists first_bonus boolean not null default false;
 end if;
 insert into public.payment_products (id,name,amount,paid_gems,bonus_gems,sort) values
  ('gem_100','심연석 100',1100,100,0,1),
  ('gem_500','심연석 525',5500,500,25,2),
  ('gem_1000','심연석 1,050',11000,1050,0,3),
  ('gem_3000','심연석 3,200',33000,3200,0,4),
  ('gem_55000','심연석 5,500',55000,5500,0,5)
 on conflict (id) do update set name=excluded.name, amount=excluded.amount, paid_gems=excluded.paid_gems,
  bonus_gems=excluded.bonus_gems, sort=excluded.sort, active=true;
end $sync_pay$;

do $patch_settle$
declare ddl text := $fn$
create or replace function public.FUNCTION_NAME(p_uid uuid,p_order text,p_key text,p_amount integer,p_currency text,p_status text,p_balance integer,p_approved text) returns jsonb
language plpgsql security definer set search_path=pg_catalog,public as $settle$
declare o public.payment_orders; g jsonb; r jsonb;
begin
 perform public._payments_guard_v1();
 select * into o from public.payment_orders where order_id=p_order and user_id=p_uid for update;
 if not found then raise exception 'order not found'; end if;
 if p_key is null or o.payment_key is distinct from p_key or p_amount is distinct from o.amount or p_currency is distinct from o.currency
  or p_status is distinct from 'DONE' or p_balance is distinct from o.amount or coalesce(p_approved,'')='' then raise exception 'payment mismatch'; end if;
 if o.status='paid' then return o.receipt; end if;
 -- 2× once per SKU (not 3×). Mock shop_buy first_bonus counts as already used. Snapshot is doubled so refunds match the ledger.
 perform pg_advisory_xact_lock(hashtextextended('payments:'||p_uid::text,0));
 if not exists (select 1 from public.payment_orders where user_id=p_uid and product_id=o.product_id and status='paid' and order_id<>o.order_id)
  and not exists (select 1 from public.shop_purchases where user_id=p_uid and sku=o.product_id and first_bonus) then
  update public.payment_orders set paid_gems=paid_gems*2, bonus_gems=bonus_gems*2, first_bonus=true where order_id=o.order_id returning * into o;
 end if;
 g:=public._gem_add(p_uid,o.bonus_gems,o.paid_gems,'iap','toss:'||o.order_id,jsonb_build_object('provider','toss-test','orderId',o.order_id,'amount',o.amount,'product',o.product_id,'firstBonus',o.first_bonus));
 if g is null then raise exception 'ledger conflict'; end if;
 r:=jsonb_build_object('ok',true,'orderId',o.order_id,'paidGems',o.paid_gems,'bonusGems',o.bonus_gems,'firstBonus',o.first_bonus,'wallet',g);
 update public.payment_orders set status='paid',paid_at=clock_timestamp(),receipt=r where order_id=o.order_id;
 return r;
end $settle$;
$fn$;
begin
 if to_regprocedure('public._payments_guard_v1()') is null then return; end if;
 if to_regprocedure('public._payment_settle_base_v1(uuid,text,text,integer,text,text,integer,text)') is not null then
  execute replace(ddl, 'FUNCTION_NAME', '_payment_settle_base_v1');
 elsif to_regprocedure('public._payment_settle_v1(uuid,text,text,integer,text,text,integer,text)') is not null then
  execute replace(ddl, 'FUNCTION_NAME', '_payment_settle_v1');
 end if;
end $patch_settle$;

revoke all on function public._shop_guard(), public._shop_day(), public._shop_month(), public._shop_apply(uuid,jsonb,text,text) from public, anon, authenticated;
revoke all on function public.shop_status(), public.shop_buy(text), public.shop_pass_claim() from public, anon;
grant execute on function public.shop_status(), public.shop_buy(text), public.shop_pass_claim() to authenticated;
notify pgrst, 'reload schema';
commit;
select 'shop bm staging installed (2x first charge, not 3x)' as result;
