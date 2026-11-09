-- STAGING ONLY: cuyqchmdcnsgzkwyclji. Run AFTER payments_refunds_staging.sql.
-- Additive/re-runnable. Does not reset orders, receipts, wallet, or ledger.
-- Dashboard/external Toss cancels are reconciled from a service-role call that already
-- re-fetched the payment. This function does not trust a browser or webhook body.
begin;
do $guard$ begin
 if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7703759698107299042' then raise exception 'STOP: webhook staging only'; end if;
 if to_regclass('public.payment_refunds') is null
 or to_regprocedure('public._payment_refund_finish_v1(text,text,integer,text,text,integer,jsonb)') is null
 or to_regprocedure('public._admin_guard()') is null then raise exception 'Install refunds first'; end if;
end $guard$;

alter table public.payment_orders add column if not exists cancel_source text;
alter table public.payment_orders add column if not exists provider_status text;
alter table public.payment_orders add column if not exists provider_mid text;
alter table public.payment_orders drop constraint if exists payment_orders_cancel_source_check;
alter table public.payment_orders add constraint payment_orders_cancel_source_check check (cancel_source is null or cancel_source in ('admin','external'));
alter table public.payment_orders drop constraint if exists payment_orders_provider_status_check;
alter table public.payment_orders add constraint payment_orders_provider_status_check check (provider_status is null or provider_status in ('DONE','CANCELED','PARTIAL_CANCELED'));
alter table public.payment_orders drop constraint if exists payment_orders_provider_mid_check;
alter table public.payment_orders add constraint payment_orders_provider_mid_check check (provider_mid is null or provider_mid ~ '^[A-Za-z0-9_-]{1,64}$');

alter table public.payment_refunds add column if not exists source text;
update public.payment_refunds set source='admin' where source is null;
alter table public.payment_refunds alter column source set default 'admin';
alter table public.payment_refunds alter column source set not null;
alter table public.payment_refunds drop constraint if exists payment_refunds_source_check;
alter table public.payment_refunds add constraint payment_refunds_source_check check (source in ('admin','external'));
alter table public.payment_refunds alter column actor_id drop not null;
alter table public.payment_refunds drop constraint if exists payment_refunds_last_error_check;
alter table public.payment_refunds add constraint payment_refunds_last_error_check check (last_error is null or last_error in ('refund pending','provider mismatch','provider unavailable','external partial','external spent'));

-- Same full-cancel proof as the admin path. Also records who completed it.
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
 update public.payment_orders set cancel_status='refunded',cancel_amount=o.amount,canceled_at=at,cancel_source=coalesce(cancel_source,'admin'),provider_status='CANCELED' where order_id=p_order;
 return out;
end $$;

create or replace function public._payment_provider_key_v1(p_order text) returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare o public.payment_orders;
begin
 perform public._payments_guard_v1();
 select * into o from public.payment_orders where order_id=p_order;
 if not found or o.status<>'paid' or o.payment_key is null then return null; end if;
 return jsonb_build_object('order_id',o.order_id,'payment_key',o.payment_key,'amount',o.amount,'currency',o.currency);
end $$;

-- Service role only. p_* values are the Edge's authenticated Toss GET, never the webhook JSON.
create or replace function public._payment_external_reconcile_v1(p_order text,p_key text,p_amount integer,p_currency text,p_status text,p_balance integer,p_cancels jsonb,p_mid text) returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare o public.payment_orders; r public.payment_refunds; w public.player_wallet; g public.gem_ledger; held jsonb; out jsonb;
 total bigint; at timestamptz; used_free bigint; used_paid bigint; unused boolean:=false; already boolean:=false;
begin
 perform public._payments_guard_v1();
 select * into o from public.payment_orders where order_id=p_order for update;
 if not found or o.status<>'paid' or o.payment_key is null then return jsonb_build_object('ok',true,'state','ignored'); end if;
 if p_key is distinct from o.payment_key or p_amount is distinct from o.amount or p_currency is distinct from o.currency then raise exception 'payment mismatch'; end if;
 if p_mid is null or p_mid !~ '^[A-Za-z0-9_-]{1,64}$' then raise exception 'payment mismatch'; end if;
 if o.provider_mid is null then update public.payment_orders set provider_mid=p_mid where order_id=o.order_id; o.provider_mid:=p_mid;
 elsif o.provider_mid is distinct from p_mid then raise exception 'payment mismatch'; end if;
 select * into r from public.payment_refunds where order_id=o.order_id for update;
 if p_status='DONE' and p_balance is not distinct from o.amount and coalesce(jsonb_array_length(p_cancels),0)=0 then
  return jsonb_build_object('ok',true,'state',case when o.cancel_status='none' then 'open' else o.cancel_status end,'stale',o.cancel_status<>'none');
 end if;
 if p_status not in ('CANCELED','PARTIAL_CANCELED') or jsonb_typeof(p_cancels) is distinct from 'array' or jsonb_array_length(p_cancels) not between 1 and 20 then raise exception 'payment mismatch'; end if;
 if exists(select 1 from jsonb_array_elements(p_cancels) x where x->>'cancelStatus' is distinct from 'DONE' or coalesce((x->>'cancelAmount')::integer,0)<=0 or coalesce(x->>'transactionKey','')='' or coalesce(x->>'canceledAt','')='') then raise exception 'payment mismatch'; end if;
 select sum((x->>'cancelAmount')::integer),max((x->>'canceledAt')::timestamptz) into total,at from jsonb_array_elements(p_cancels) x;
 if (select count(distinct x->>'transactionKey') from jsonb_array_elements(p_cancels) x)<>jsonb_array_length(p_cancels) or total is null or total<=0 or total>o.amount then raise exception 'payment mismatch'; end if;
 if p_status='PARTIAL_CANCELED' then
  if p_balance is null or p_balance<=0 or p_balance>=o.amount or total is distinct from (o.amount-p_balance)::bigint then raise exception 'payment mismatch'; end if;
  -- An in-flight admin hold must keep its retry path. Ask Toss to deliver this notice again.
  if o.cancel_status='processing' or r.state='held' then return jsonb_build_object('ok',true,'state','processing','retry',true); end if;
  if r.state='refunded' or o.cancel_status='refunded' then
   update public.payment_refunds set last_error='external partial',cancel_amount=total::integer,canceled_at=at,updated_at=clock_timestamp(),provider_cancels=p_cancels where order_id=o.order_id;
   update public.payment_orders set provider_status='PARTIAL_CANCELED',cancel_amount=total::integer,canceled_at=coalesce(canceled_at,at),cancel_source=coalesce(cancel_source,'external') where order_id=o.order_id;
   return jsonb_build_object('ok',true,'state','review','reason','external partial','reclaimed',true);
  end if;
  if r.order_id is null then
   insert into public.payment_refunds(order_id,actor_id,state,amount,paid_gems,bonus_gems,idempotency_key,source,cancel_amount,canceled_at,provider_cancels,last_error)
   values(o.order_id,null,'review',o.amount,o.paid_gems,o.bonus_gems,'vr-external-'||o.order_id,'external',total::integer,at,p_cancels,'external partial');
  else
   update public.payment_refunds set state='review',source=case when source='admin' then source else 'external' end,cancel_amount=total::integer,canceled_at=at,updated_at=clock_timestamp(),provider_cancels=p_cancels,last_error='external partial' where order_id=o.order_id and state<>'refunded';
  end if;
  update public.payment_orders set cancel_status='review',cancel_amount=total::integer,canceled_at=at,cancel_source=coalesce(cancel_source,'external'),provider_status='PARTIAL_CANCELED' where order_id=o.order_id;
  return jsonb_build_object('ok',true,'state','review','reason','external partial','reclaimed',false);
 end if;
 if p_status is distinct from 'CANCELED' or p_balance is distinct from 0 or total is distinct from o.amount::bigint then raise exception 'payment mismatch'; end if;
 if r.state='refunded' then
  update public.payment_orders set provider_status='CANCELED',cancel_amount=o.amount,canceled_at=coalesce(canceled_at,at) where order_id=o.order_id;
  return r.receipt;
 end if;
 select exists(select 1 from public.gem_ledger where user_id=o.user_id and ref='toss-refund-hold:'||o.order_id and d_free=-o.bonus_gems and d_paid=-o.paid_gems) into already;
 if r.order_id is not null and already then
  return public._payment_refund_finish_v1(o.order_id,o.payment_key,o.amount,o.currency,'CANCELED',0,p_cancels);
 end if;
 if not already then
  -- Same conservative FIFO as admin prepare. A later top-up does not prove this bundle is unused.
  select * into w from public.player_wallet where user_id=o.user_id for update;
  select * into g from public.gem_ledger where user_id=o.user_id and ref='toss:'||o.order_id;
  if w.user_id is not null and g.id is not null and g.d_paid=o.paid_gems and g.d_free=o.bonus_gems then
   select coalesce(sum(greatest(-d_free,0)),0),coalesce(sum(greatest(-d_paid,0)),0) into used_free,used_paid from public.gem_ledger where user_id=o.user_id and id>g.id;
   unused:=w.gem_paid>=o.paid_gems and w.gem_free>=o.bonus_gems and used_paid<=g.paid_after-o.paid_gems and (o.bonus_gems=0 or used_free<=g.free_after-o.bonus_gems);
  end if;
  if unused then
   begin
    held:=public._gem_add(o.user_id,-o.bonus_gems,-o.paid_gems,'refund_hold','toss-refund-hold:'||o.order_id,jsonb_build_object('orderId',o.order_id,'source','external'));
   exception when others then
    if position('not enough gem' in sqlerrm)=0 then raise; end if;
    held:=null;
   end;
   select exists(select 1 from public.gem_ledger where user_id=o.user_id and ref='toss-refund-hold:'||o.order_id and d_free=-o.bonus_gems and d_paid=-o.paid_gems) into already;
  end if;
 end if;
 if not already then
  if r.order_id is null then
   insert into public.payment_refunds(order_id,actor_id,state,amount,paid_gems,bonus_gems,idempotency_key,source,cancel_amount,canceled_at,provider_cancels,last_error)
   values(o.order_id,null,'review',o.amount,o.paid_gems,o.bonus_gems,'vr-external-'||o.order_id,'external',o.amount,at,p_cancels,'external spent');
  else
   update public.payment_refunds set state='review',source=case when source='admin' then source else 'external' end,cancel_amount=o.amount,canceled_at=at,updated_at=clock_timestamp(),provider_cancels=p_cancels,last_error='external spent' where order_id=o.order_id and state<>'refunded';
  end if;
  update public.payment_orders set cancel_status='review',cancel_amount=o.amount,canceled_at=at,cancel_source=coalesce(cancel_source,'external'),provider_status='CANCELED' where order_id=o.order_id and cancel_status<>'refunded';
  return jsonb_build_object('ok',true,'state','review','reason','external spent','reclaimed',false);
 end if;
 out:=jsonb_build_object('ok',true,'state','refunded','orderId',o.order_id,'amount',o.amount,'paidGems',o.paid_gems,'bonusGems',o.bonus_gems);
 if r.order_id is null then
  insert into public.payment_refunds(order_id,actor_id,state,amount,paid_gems,bonus_gems,idempotency_key,source,cancel_amount,canceled_at,provider_cancels,last_error,receipt)
  values(o.order_id,null,'refunded',o.amount,o.paid_gems,o.bonus_gems,'vr-external-'||o.order_id,'external',o.amount,at,p_cancels,null,out);
 else
  update public.payment_refunds set state='refunded',source=case when source='admin' then source else 'external' end,cancel_amount=o.amount,canceled_at=at,updated_at=clock_timestamp(),provider_cancels=p_cancels,last_error=null,receipt=out where order_id=o.order_id;
 end if;
 update public.payment_orders set cancel_status='refunded',cancel_amount=o.amount,canceled_at=at,cancel_source=coalesce(cancel_source,'external'),provider_status='CANCELED' where order_id=o.order_id;
 return out;
end $$;

create or replace function public.admin_payment_orders_v1() returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
begin
 perform public._payments_guard_v1(); perform public._admin_guard();
 update public.payment_orders set checkout_status='expired',closed_at=clock_timestamp()
 where status='pending' and checkout_status='open' and payment_key is null and expires_at<clock_timestamp();
 return jsonb_build_object('ok',true,'orders',(select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at desc),'[]'::jsonb) from
 (select o.order_id,o.order_name,o.amount,o.paid_gems,o.bonus_gems,o.status,o.checkout_status,o.cancel_status,o.cancel_amount,o.created_at,o.paid_at,o.canceled_at,o.cancel_source,o.provider_status,
  coalesce(nullif(btrim(p.nickname),''),o.user_id::text) as buyer
  from public.payment_orders o left join public.profiles p on p.id=o.user_id order by o.created_at desc limit 100) t));
end $$;

revoke all on function public._payment_refund_finish_v1(text,text,integer,text,text,integer,jsonb),public._payment_provider_key_v1(text),public._payment_external_reconcile_v1(text,text,integer,text,text,integer,jsonb,text),public.admin_payment_orders_v1() from public,anon,authenticated;
grant execute on function public._payment_refund_finish_v1(text,text,integer,text,text,integer,jsonb),public._payment_provider_key_v1(text),public._payment_external_reconcile_v1(text,text,integer,text,text,integer,jsonb,text) to service_role;
grant execute on function public.admin_payment_orders_v1() to authenticated;
notify pgrst,'reload schema';
commit;
select 'staging external cancel reconciliation installed' as result;
