-- STAGING ONLY — cuyqchmdcnsgzkwyclji. Existing game data is never reset.
-- Placeholder prices; public Toss sample test merchant only. Never run on production.
begin;
do $payments_guard$
begin
 if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7703759698107299042' then raise exception 'STOP: payments staging cuyqchmdcnsgzkwyclji only'; end if;
 if to_regprocedure('public._gem_add(uuid,integer,integer,text,text,jsonb)') is null then raise exception 'Install game wallet first'; end if;
end $payments_guard$;

create table if not exists public.payment_products (
 id text primary key check(id ~ '^gem_[0-9]+$'), name text not null check(length(name) between 1 and 70),
 amount integer not null check(amount between 100 and 1000000), paid_gems integer not null check(paid_gems between 1 and 100000),
 bonus_gems integer not null default 0 check(bonus_gems between 0 and 100000), currency text not null default 'KRW' check(currency='KRW'),
 active boolean not null default true, placeholder boolean not null default true check(placeholder), sort integer not null default 0
);
-- BM 2026-11-10 심연석 충전. 최초 설치에만 넣음. 재실행은 운영자가 바꾼 가격을 덮지 않음 (do nothing).
-- 이미 깔린 테스트 DB의 옛 수량(gem_1000 1,000+100, gem_3000 3,000+450)은 supabase/shop_bm_staging.sql 이 고친다.
-- gem_500 의 25는 표기 수량 525 안의 기본 보너스(유료 500+무료 25)이지, 첫 구매 2배와 별개다.
insert into public.payment_products(id,name,amount,paid_gems,bonus_gems,sort) values
 ('gem_100','심연석 100',1100,100,0,1),('gem_500','심연석 525',5500,500,25,2),
 ('gem_1000','심연석 1,050',11000,1050,0,3),('gem_3000','심연석 3,200',33000,3200,0,4),
 ('gem_55000','심연석 5,500',55000,5500,0,5)
on conflict(id) do nothing;
create table if not exists public.payment_orders (
 order_id text primary key default ('vrs_'||replace(gen_random_uuid()::text,'-','')) check(order_id ~ '^vrs_[a-f0-9]{32}$'),
 user_id uuid not null references auth.users(id) on delete restrict, request_id uuid not null,
 product_id text not null references public.payment_products(id), order_name text not null,
 amount integer not null check(amount between 100 and 1000000), currency text not null check(currency='KRW'),
 paid_gems integer not null check(paid_gems>0), bonus_gems integer not null check(bonus_gems>=0),
 status text not null default 'pending' check(status in ('pending','paid')), payment_key text unique check(length(payment_key) between 1 and 200),
 created_at timestamptz not null default clock_timestamp(), expires_at timestamptz not null default (clock_timestamp()+interval '30 minutes'),
 bound_at timestamptz, paid_at timestamptz, receipt jsonb, unique(user_id,request_id),
 check((status='paid')=(receipt is not null and paid_at is not null)), check(status<>'paid' or payment_key is not null)
);
create index if not exists payment_orders_user_time on public.payment_orders(user_id,created_at desc);
-- 첫 구매 2배(BM 2026-11-10, 3배는 아님)를 정산 때 주문 스냅샷에 반영했는지. 환불은 이 스냅샷과 원장을 맞춘다.
alter table public.payment_orders add column if not exists first_bonus boolean not null default false;
alter table public.payment_products enable row level security;
alter table public.payment_orders enable row level security;
revoke all on public.payment_products,public.payment_orders from public,anon,authenticated;
grant select on public.payment_products,public.payment_orders to authenticated;
grant all on public.payment_products,public.payment_orders to service_role;
drop policy if exists payment_products_read on public.payment_products;
create policy payment_products_read on public.payment_products for select to authenticated using(active);
drop policy if exists payment_orders_own on public.payment_orders;
create policy payment_orders_own on public.payment_orders for select to authenticated using(user_id=auth.uid());

create or replace function public._payments_guard_v1() returns void language plpgsql security definer set search_path=pg_catalog,public as $$
begin
 if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7703759698107299042' then raise exception 'payments unavailable'; end if;
end $$;
create or replace function public.payment_create_v1(p_product text,p_request uuid) returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare u uuid:=auth.uid(); p public.payment_products; o public.payment_orders;
begin
 perform public._payments_guard_v1();
 if u is null then raise exception 'login required'; end if;
 if p_request is null or p_product is null then raise exception 'invalid order'; end if;
 perform pg_advisory_xact_lock(hashtextextended('payments:'||u::text,0));
 select * into o from public.payment_orders where user_id=u and request_id=p_request;
 if found then
  if o.product_id<>p_product then raise exception 'request conflict'; end if;
  return to_jsonb(o);
 end if;
 if (select count(*) from public.payment_orders where user_id=u and created_at>clock_timestamp()-interval '1 minute')>=10
 or (select count(*) from public.payment_orders where user_id=u and created_at>clock_timestamp()-interval '1 day')>=100 then raise exception 'rate limited'; end if;
 select * into p from public.payment_products where id=p_product and active for share;
 if not found then raise exception 'product unavailable'; end if;
 insert into public.payment_orders(user_id,request_id,product_id,order_name,amount,currency,paid_gems,bonus_gems)
 values(u,p_request,p.id,p.name,p.amount,p.currency,p.paid_gems,p.bonus_gems) returning * into o;
 return to_jsonb(o);
end $$;
-- Service-role only: binds the opaque provider key BEFORE contacting Toss. Retrying cannot substitute another key.
create or replace function public._payment_bind_v1(p_uid uuid,p_order text,p_key text,p_amount integer) returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare o public.payment_orders;
begin
 perform public._payments_guard_v1();
 select * into o from public.payment_orders where order_id=p_order and user_id=p_uid for update;
 if not found then raise exception 'order not found'; end if;
 if p_amount is null or p_amount<>o.amount or p_key is null or length(p_key) not between 1 and 200 then raise exception 'payment mismatch'; end if;
 if o.payment_key is not null and o.payment_key<>p_key then raise exception 'payment conflict'; end if;
 if o.payment_key is null and o.expires_at<clock_timestamp() then raise exception 'order expired'; end if;
 if o.payment_key is null then update public.payment_orders set payment_key=p_key,bound_at=clock_timestamp() where order_id=o.order_id returning * into o; end if;
 return to_jsonb(o);
end $$;
-- Trusted Edge calls only after authenticated Toss response; never accepts client-reported success.
create or replace function public._payment_settle_v1(p_uid uuid,p_order text,p_key text,p_amount integer,p_currency text,p_status text,p_balance integer,p_approved text) returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare o public.payment_orders; g jsonb; r jsonb;
begin
 perform public._payments_guard_v1();
 select * into o from public.payment_orders where order_id=p_order and user_id=p_uid for update;
 if not found then raise exception 'order not found'; end if;
 if p_key is null or o.payment_key is distinct from p_key or p_amount is distinct from o.amount or p_currency is distinct from o.currency
 or p_status is distinct from 'DONE' or p_balance is distinct from o.amount or coalesce(p_approved,'')='' then raise exception 'payment mismatch'; end if;
 if o.status='paid' then return o.receipt; end if;
 -- 2× first purchase, once per SKU: listed grant PLUS an equal bonus (100 → 200). Not 3×.
 -- Built-in bonus (gem_500 +25 free) is part of the listed grant and is doubled with it.
 -- The order snapshot is doubled before the ledger insert so refunds still match d_paid/d_free.
 perform pg_advisory_xact_lock(hashtextextended('payments:'||p_uid::text,0));
 if not exists (select 1 from public.payment_orders where user_id=p_uid and product_id=o.product_id and status='paid' and order_id<>o.order_id) then
  update public.payment_orders set paid_gems=paid_gems*2, bonus_gems=bonus_gems*2, first_bonus=true where order_id=o.order_id returning * into o;
 end if;
 g:=public._gem_add(p_uid,o.bonus_gems,o.paid_gems,'iap','toss:'||o.order_id,jsonb_build_object('provider','toss-test','orderId',o.order_id,'amount',o.amount,'product',o.product_id,'firstBonus',o.first_bonus));
 if g is null then raise exception 'ledger conflict'; end if;
 r:=jsonb_build_object('ok',true,'orderId',o.order_id,'paidGems',o.paid_gems,'bonusGems',o.bonus_gems,'firstBonus',o.first_bonus,'wallet',g);
 update public.payment_orders set status='paid',paid_at=clock_timestamp(),receipt=r where order_id=o.order_id;
 return r;
end $$;
revoke all on function public._payments_guard_v1(),public.payment_create_v1(text,uuid),public._payment_bind_v1(uuid,text,text,integer),public._payment_settle_v1(uuid,text,text,integer,text,text,integer,text) from public,anon,authenticated;
grant execute on function public.payment_create_v1(text,uuid) to authenticated;
grant execute on function public._payment_bind_v1(uuid,text,text,integer),public._payment_settle_v1(uuid,text,text,integer,text,text,integer,text) to service_role;
notify pgrst,'reload schema';
commit;
select 'payments staging installed (placeholder prices, test only)' as result;
