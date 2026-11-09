-- STAGING ONLY: cuyqchmdcnsgzkwyclji. Run AFTER payments_staging.sql.
-- Additive/re-runnable: preserves original receipts, orders, wallet and ledger.
begin;
do $guard$ begin
 if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7703759698107299042' then raise exception 'STOP: refunds staging only'; end if;
 if to_regprocedure('public._payment_settle_v1(uuid,text,text,integer,text,text,integer,text)') is null or to_regprocedure('public._admin_guard()') is null then raise exception 'Install payments and admin first'; end if;
end $guard$;
alter table public.payment_orders add column if not exists checkout_status text not null default 'open' check(checkout_status in ('open','canceled','failed','expired'));
alter table public.payment_orders add column if not exists closed_at timestamptz;
alter table public.payment_orders add column if not exists cancel_status text not null default 'none' check(cancel_status in ('none','processing','refunded','review'));
alter table public.payment_orders add column if not exists cancel_amount integer not null default 0 check(cancel_amount between 0 and amount);
alter table public.payment_orders add column if not exists canceled_at timestamptz;
-- status='paid' / original receipt remain historical proof of the original grant.
-- cancel_status is authoritative for subsequent refund/confirm operations.
create table if not exists public.payment_refunds (
 order_id text primary key references public.payment_orders(order_id) on delete restrict,
 actor_id uuid not null, state text not null default 'held' check(state in ('held','refunded','review')),
 amount integer not null check(amount>0), paid_gems integer not null check(paid_gems>0), bonus_gems integer not null check(bonus_gems>=0),
 idempotency_key text not null unique, created_at timestamptz not null default clock_timestamp(),
 updated_at timestamptz not null default clock_timestamp(), canceled_at timestamptz,
 cancel_amount integer not null default 0 check(cancel_amount between 0 and amount),
 provider_cancels jsonb, last_error text check(last_error in ('refund pending','provider mismatch','provider unavailable')), receipt jsonb
);
alter table public.payment_refunds enable row level security;
revoke all on public.payment_refunds from public,anon,authenticated;
grant all on public.payment_refunds to service_role;

-- Keep the original vetted grant/order logic; guard it under the SAME order row lock.
do $wrap$ begin
 if to_regprocedure('public._payment_create_base_v1(text,uuid)') is null then alter function public.payment_create_v1(text,uuid) rename to _payment_create_base_v1; end if;
 if to_regprocedure('public._payment_bind_base_v1(uuid,text,text,integer)') is null then alter function public._payment_bind_v1(uuid,text,text,integer) rename to _payment_bind_base_v1; end if;
 if to_regprocedure('public._payment_settle_base_v1(uuid,text,text,integer,text,text,integer,text)') is null then alter function public._payment_settle_v1(uuid,text,text,integer,text,text,integer,text) rename to _payment_settle_base_v1; end if;
end $wrap$;
revoke all on function public._payment_create_base_v1(text,uuid),public._payment_bind_base_v1(uuid,text,text,integer),public._payment_settle_base_v1(uuid,text,text,integer,text,text,integer,text) from public,anon,authenticated,service_role;

create or replace function public.payment_create_v1(p_product text,p_request uuid) returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
begin
 perform public._payments_guard_v1();
 if auth.uid() is null then raise exception 'login required'; end if;
 -- Abrupt tab/browser termination has no reliable client callback. Lazy server expiry.
 update public.payment_orders set checkout_status='expired',closed_at=clock_timestamp()
 where user_id=auth.uid() and status='pending' and checkout_status='open' and payment_key is null and expires_at<clock_timestamp();
 return public._payment_create_base_v1(p_product,p_request);
end $$;
create or replace function public._payment_bind_v1(p_uid uuid,p_order text,p_key text,p_amount integer) returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare o public.payment_orders;
begin
 perform public._payments_guard_v1();
 select * into o from public.payment_orders where order_id=p_order and user_id=p_uid for update;
 if not found then raise exception 'order not found'; end if;
 if o.cancel_status<>'none' then raise exception 'payment refunded'; end if;
 if o.checkout_status<>'open' then raise exception 'payment closed'; end if;
 return public._payment_bind_base_v1(p_uid,p_order,p_key,p_amount);
end $$;
create or replace function public._payment_settle_v1(p_uid uuid,p_order text,p_key text,p_amount integer,p_currency text,p_status text,p_balance integer,p_approved text) returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare o public.payment_orders;
begin
 perform public._payments_guard_v1();
 select * into o from public.payment_orders where order_id=p_order and user_id=p_uid for update;
 if not found then raise exception 'order not found'; end if;
 if o.cancel_status<>'none' then raise exception 'payment refunded'; end if;
 if o.checkout_status<>'open' then raise exception 'payment closed'; end if;
 return public._payment_settle_base_v1(p_uid,p_order,p_key,p_amount,p_currency,p_status,p_balance,p_approved);
end $$;

-- This is ONLY abandoning an unapproved checkout, never a player money-refund RPC.
-- A client fail/cancel hint cannot modify an order already bound/paid by confirm.
create or replace function public.payment_abandon_v1(p_order text,p_reason text) returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare o public.payment_orders;
begin
 perform public._payments_guard_v1();
 if auth.uid() is null then raise exception 'login required'; end if;
 if p_reason is null or p_reason not in ('canceled','failed') then raise exception 'invalid request'; end if;
 select * into o from public.payment_orders where order_id=p_order and user_id=auth.uid() for update;
 if not found then raise exception 'order not found'; end if;
 if o.status='paid' or o.payment_key is not null then return jsonb_build_object('ok',true,'state','confirmation_required'); end if;
 if o.checkout_status='open' then
  update public.payment_orders set checkout_status=case when expires_at<clock_timestamp() then 'expired' else p_reason end,closed_at=clock_timestamp() where order_id=o.order_id returning * into o;
 end if;
 return jsonb_build_object('ok',true,'state',o.checkout_status);
end $$;

create or replace function public.admin_payment_orders_v1() returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
begin
 perform public._payments_guard_v1(); perform public._admin_guard();
 update public.payment_orders set checkout_status='expired',closed_at=clock_timestamp()
 where status='pending' and checkout_status='open' and payment_key is null and expires_at<clock_timestamp();
 return jsonb_build_object('ok',true,'orders',(select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at desc),'[]'::jsonb) from
 (select o.order_id,o.order_name,o.amount,o.paid_gems,o.bonus_gems,o.status,o.checkout_status,o.cancel_status,o.cancel_amount,o.created_at,o.paid_at,o.canceled_at,
  coalesce(nullif(btrim(p.nickname),''),o.user_id::text) as buyer
  from public.payment_orders o left join public.profiles p on p.id=o.user_id order by o.created_at desc limit 100) t));
end $$;
create or replace function public.admin_payment_refund_lookup_v1(p_order text) returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare o public.payment_orders; r public.payment_refunds;
begin
 perform public._payments_guard_v1(); perform public._admin_guard();
 select * into o from public.payment_orders where order_id=p_order;
 if not found then raise exception 'order not found'; end if;
 select * into r from public.payment_refunds where order_id=p_order;
 return jsonb_build_object('order',to_jsonb(o),'refund',case when r.order_id is null then null else to_jsonb(r) end);
end $$;
create or replace function public.admin_payment_refund_prepare_v1(p_order text) returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare o public.payment_orders; r public.payment_refunds; w public.player_wallet; g public.gem_ledger; held jsonb; used_free bigint; used_paid bigint;
begin
 perform public._payments_guard_v1(); perform public._admin_guard();
 select * into o from public.payment_orders where order_id=p_order for update;
 if not found then raise exception 'order not found'; end if;
 select * into r from public.payment_refunds where order_id=p_order;
 if found then return jsonb_build_object('order',to_jsonb(o),'refund',to_jsonb(r)); end if;
 if o.status<>'paid' or o.payment_key is null or o.cancel_status<>'none' then raise exception 'refund not eligible'; end if;
 if o.paid_at+interval '7 days'<clock_timestamp() then raise exception 'refund cs review'; end if;
 -- Same wallet row lock as ALL gem spends/grants; no spend/refund TOCTOU.
 select * into w from public.player_wallet where user_id=o.user_id for update;
 if not found then raise exception 'refund cs review'; end if;
 select * into g from public.gem_ledger where user_id=o.user_id and ref='toss:'||o.order_id;
 if not found or g.d_paid<>o.paid_gems or g.d_free<>o.bonus_gems then raise exception 'refund cs review'; end if;
 -- Conservative FIFO eligibility, evaluated from immutable ledger IDs, not clock times.
 -- Later topups/rewards cannot hide consumption of this earlier purchased bundle.
 -- Refund/administrative debits also count conservatively; ambiguous cases go to CS.
 select coalesce(sum(greatest(-d_free,0)),0),coalesce(sum(greatest(-d_paid,0)),0) into used_free,used_paid
 from public.gem_ledger where user_id=o.user_id and id>g.id;
 if w.gem_paid<o.paid_gems or w.gem_free<o.bonus_gems or used_paid>g.paid_after-o.paid_gems
 or (o.bonus_gems>0 and used_free>g.free_after-o.bonus_gems) then raise exception 'refund cs review'; end if;
 held:=public._gem_add(o.user_id,-o.bonus_gems,-o.paid_gems,'refund_hold','toss-refund-hold:'||o.order_id,jsonb_build_object('orderId',o.order_id,'actor',auth.uid()));
 if held is null then raise exception 'refund cs review'; end if;
 insert into public.payment_refunds(order_id,actor_id,amount,paid_gems,bonus_gems,idempotency_key)
 values(o.order_id,auth.uid(),o.amount,o.paid_gems,o.bonus_gems,'vr-refund-'||o.order_id) returning * into r;
 update public.payment_orders set cancel_status='processing' where order_id=o.order_id returning * into o;
 return jsonb_build_object('order',to_jsonb(o),'refund',to_jsonb(r));
end $$;

-- Trusted Edge only, AFTER authenticated Toss re-fetch validates the entire cancellation.
create or replace function public._payment_refund_finish_v1(p_order text,p_key text,p_amount integer,p_currency text,p_status text,p_balance integer,p_cancels jsonb) returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare o public.payment_orders; r public.payment_refunds; total bigint; at timestamptz; out jsonb;
begin
 perform public._payments_guard_v1();
 select * into o from public.payment_orders where order_id=p_order for update;
 select * into r from public.payment_refunds where order_id=p_order for update;
 if o.order_id is null or r.order_id is null then raise exception 'refund not eligible'; end if;
 if p_key is distinct from o.payment_key or p_amount is distinct from o.amount or p_currency is distinct from o.currency
 or p_status is distinct from 'CANCELED' or p_balance is distinct from 0 or jsonb_typeof(p_cancels) is distinct from 'array' then raise exception 'payment mismatch'; end if;
 if jsonb_array_length(p_cancels) not between 1 and 20 then raise exception 'payment mismatch'; end if;
 if exists(select 1 from jsonb_array_elements(p_cancels) x where x->>'cancelStatus' is distinct from 'DONE' or coalesce((x->>'cancelAmount')::integer,0)<=0 or coalesce(x->>'transactionKey','')='' or coalesce(x->>'canceledAt','')='') then raise exception 'payment mismatch'; end if;
 select sum((x->>'cancelAmount')::integer),max((x->>'canceledAt')::timestamptz) into total,at from jsonb_array_elements(p_cancels) x;
 if total is distinct from o.amount::bigint or (select count(distinct x->>'transactionKey') from jsonb_array_elements(p_cancels) x)<>jsonb_array_length(p_cancels) then raise exception 'payment mismatch'; end if;
 if r.state='refunded' then return r.receipt; end if;
 if not exists(select 1 from public.gem_ledger where user_id=o.user_id and ref='toss-refund-hold:'||o.order_id and d_free=-o.bonus_gems and d_paid=-o.paid_gems) then raise exception 'refund cs review'; end if;
 out:=jsonb_build_object('ok',true,'state','refunded','orderId',o.order_id,'amount',o.amount,'paidGems',o.paid_gems,'bonusGems',o.bonus_gems);
 update public.payment_refunds set state='refunded',cancel_amount=o.amount,canceled_at=at,updated_at=clock_timestamp(),provider_cancels=p_cancels,last_error=null,receipt=out where order_id=p_order;
 update public.payment_orders set cancel_status='refunded',cancel_amount=o.amount,canceled_at=at where order_id=p_order;
 return out;
end $$;
create or replace function public._payment_refund_note_v1(p_order text,p_error text) returns void language plpgsql security definer set search_path=pg_catalog,public as $$
begin
 perform public._payments_guard_v1();
 if p_error is null or p_error not in ('refund pending','provider mismatch','provider unavailable') then raise exception 'invalid request'; end if;
 -- Order-first lock order is shared by prepare/finish/confirm, avoiding lock inversion.
 perform 1 from public.payment_orders where order_id=p_order for update;
 update public.payment_refunds set last_error=p_error,updated_at=clock_timestamp(),state=case when p_error='provider mismatch' then 'review' else state end where order_id=p_order and state<>'refunded';
 update public.payment_orders set cancel_status='review' where order_id=p_order and cancel_status<>'refunded' and p_error='provider mismatch' and exists(select 1 from public.payment_refunds where order_id=p_order);
end $$;

revoke all on function public.payment_create_v1(text,uuid),public._payment_bind_v1(uuid,text,text,integer),public._payment_settle_v1(uuid,text,text,integer,text,text,integer,text),public.payment_abandon_v1(text,text),public.admin_payment_orders_v1(),public.admin_payment_refund_lookup_v1(text),public.admin_payment_refund_prepare_v1(text),public._payment_refund_finish_v1(text,text,integer,text,text,integer,jsonb),public._payment_refund_note_v1(text,text) from public,anon,authenticated;
grant execute on function public.payment_create_v1(text,uuid),public.payment_abandon_v1(text,text),public.admin_payment_orders_v1(),public.admin_payment_refund_lookup_v1(text),public.admin_payment_refund_prepare_v1(text) to authenticated;
grant execute on function public._payment_bind_v1(uuid,text,text,integer),public._payment_settle_v1(uuid,text,text,integer,text,text,integer,text),public._payment_refund_finish_v1(text,text,integer,text,text,integer,jsonb),public._payment_refund_note_v1(text,text) to service_role;
notify pgrst,'reload schema';
commit;
select 'staging refunds installed: admin-only, unused bundle, no negative wallet' as result;
