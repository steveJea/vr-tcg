-- STAGING ONLY · 시즌패스 31일 + Toss KRW 테스트 결제 (운영 실행 금지)
-- 선행: payments_staging → payments_refunds_staging → payments_webhook_staging → shop_bm_staging.
-- 선행 SQL 은 이미 설치돼 있으니 다시 돌리지 말고, 이 파일만 통째로 실행. 재실행 안전(멱등). 보상/가격 변경 없음, 기존 패스 기간/수령 기록 보존.
-- 신규 결제부터 31일. 기존 30일 패스는 그대로 (기간 소급 변경/이중 지급 없음). KST 당일만 수령, 놓친 날짜 소급 지급 없음.
-- 첫 구매 2배는 심연석 충전에만 그대로. 패스에 2배 적용 안 함. 패스 환불은 기존 환불 로직에서 자동으로 CS 검토로 빠짐 (자동 회수 없음).
begin;
do $guard$
begin
 if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7703759698107299042' then raise exception 'STOP: season pass staging only'; end if;
 if to_regclass('public.shop_products') is null or to_regprocedure('public._payment_settle_base_v1(uuid,text,text,integer,text,text,integer,text)') is null
    or to_regprocedure('public._payment_external_reconcile_v1(text,text,integer,text,text,integer,jsonb,text)') is null then
   raise exception 'STOP: install payments + refunds + webhook + shop BM first'; end if;
end $guard$;
-- payment tables previously accepted only gem SKUs and positive gem grants. Pass orders contain zero gems, not dummy currency.
alter table public.payment_products drop constraint if exists payment_products_id_check;
alter table public.payment_products add constraint payment_products_id_check check(id ~ '^gem_[0-9]+$' or id in ('pass_1','pass_2','pass_3'));
alter table public.payment_products drop constraint if exists payment_products_paid_gems_check;
alter table public.payment_products add constraint payment_products_paid_gems_check check((id like 'gem_%' and paid_gems between 1 and 100000) or (id in ('pass_1','pass_2','pass_3') and paid_gems=0 and bonus_gems=0));
alter table public.payment_orders drop constraint if exists payment_orders_paid_gems_check;
alter table public.payment_orders add constraint payment_orders_paid_gems_check check((product_id like 'gem_%' and paid_gems>0) or (product_id in ('pass_1','pass_2','pass_3') and paid_gems=0 and bonus_gems=0));
-- Copy original pass prices/rewards; only duration/payment linkage change. No reset of old owned passes.
update public.shop_products set reward=jsonb_set(reward,'{days}','31'::jsonb), payment_sku=sku,
 blurb=replace(blurb,'30일','31일') where sku in ('pass_1','pass_2','pass_3');
insert into public.payment_products(id,name,amount,paid_gems,bonus_gems,sort)
select sku,name,price_krw,0,0,sort from public.shop_products where sku in ('pass_1','pass_2','pass_3')
on conflict(id) do update set name=excluded.name, amount=excluded.amount, paid_gems=0, bonus_gems=0, sort=excluded.sort, active=true;
-- Preserve reviewed existing gem settlement exactly, behind a private fallback. Refuse any unknown implementation.
do $preserve$
begin
 if to_regprocedure('public._payment_settle_gems_season_v1(uuid,text,text,integer,text,text,integer,text)') is null then
  if (select md5(replace(prosrc,chr(13),'')) from pg_proc where oid='public._payment_settle_base_v1(uuid,text,text,integer,text,text,integer,text)'::regprocedure) is distinct from '6ec8b6044d1b4d2f7ce41e84258bc182' then
   raise exception 'STOP: unexpected gem settlement; do not overwrite'; end if;
  alter function public._payment_settle_base_v1(uuid,text,text,integer,text,text,integer,text) rename to _payment_settle_gems_season_v1;
 end if;
end $preserve$;
revoke all on function public._payment_settle_gems_season_v1(uuid,text,text,integer,text,text,integer,text) from public,anon,authenticated,service_role;
create or replace function public._payment_settle_base_v1(p_uid uuid,p_order text,p_key text,p_amount integer,p_currency text,p_status text,p_balance integer,p_approved text) returns jsonb
language plpgsql security definer set search_path=pg_catalog,public as $$
declare o public.payment_orders; p public.shop_products; r jsonb; s int; last_end date; start_on date; g jsonb;
begin
 perform public._payments_guard_v1();
 -- The public settle wrapper already holds this order row. Pass grants then take gem → payments locks (same order as shop_buy).
 select * into o from public.payment_orders where order_id=p_order and user_id=p_uid for update;
 if not found then raise exception 'order not found'; end if;
 if o.product_id not in ('pass_1','pass_2','pass_3') then return public._payment_settle_gems_season_v1(p_uid,p_order,p_key,p_amount,p_currency,p_status,p_balance,p_approved); end if;
 if p_key is null or o.payment_key is distinct from p_key or p_amount is distinct from o.amount or p_currency is distinct from o.currency
  or p_status is distinct from 'DONE' or p_balance is distinct from o.amount or coalesce(p_approved,'')='' then raise exception 'payment mismatch'; end if;
 if o.status='paid' then return o.receipt; end if;
 select * into p from public.shop_products where sku=o.product_id and tab='pass' and payment_sku=o.product_id and price_krw=o.amount;
 if not found or (p.reward->>'days')::int<>31 or not coalesce((p.reward->>'pass')::boolean,false) then raise exception 'payment mismatch'; end if;
 perform pg_advisory_xact_lock(hashtext('gem:'||p_uid::text));
 perform pg_advisory_xact_lock(hashtextextended('payments:'||p_uid::text,0));
 select coalesce(max(seq),0)+1,max(ends_on) into s,last_end from public.shop_passes where user_id=p_uid and sku=o.product_id;
 start_on:=greatest(public._shop_day(),coalesce(last_end+1,public._shop_day()));
 insert into public.shop_passes(user_id,sku,seq,starts_on,ends_on) values(p_uid,o.product_id,s,start_on,start_on+30);
 g:=public._shop_apply(p_uid,coalesce(p.reward->'first','{}'::jsonb),'shop:'||o.product_id,'pass-order:'||o.order_id);
 insert into public.shop_purchases(user_id,sku,ym) values(p_uid,o.product_id,public._shop_month());
 r:=jsonb_build_object('ok',true,'orderId',o.order_id,'kind','pass','sku',o.product_id,'name',p.name,'paidGems',0,'bonusGems',0,'firstBonus',false,'seq',s,'starts_on',start_on,'ends_on',start_on+30,'grant',g);
 update public.payment_orders set status='paid',paid_at=clock_timestamp(),receipt=r where order_id=o.order_id;
 return r;
end $$;
-- Pass refunds: the existing refund prepare / external reconcile find no 'toss:' gem ledger row and route to CS review (no auto clawback).
-- Calendar data for the shop. Read-only; claiming stays shop_pass_claim() (today only, KST).
create or replace function public.shop_pass_days() returns jsonb
language plpgsql stable security definer set search_path=pg_catalog,public as $$
declare u uuid:=auth.uid();
begin
 perform public._shop_guard();
 if u is null then raise exception 'login required'; end if;
 return jsonb_build_object('today',public._shop_day(),'passes',coalesce((select jsonb_agg(jsonb_build_object('sku',sp.sku,'seq',sp.seq,'name',p.name,
   'starts_on',sp.starts_on,'ends_on',sp.ends_on,'days',sp.ends_on-sp.starts_on+1,'daily',p.reward->'daily',
   'state',case when public._shop_day()<sp.starts_on then 'queued' when public._shop_day()>sp.ends_on then 'ended' else 'active' end,
   'claimed',coalesce((select jsonb_agg(c.day order by c.day) from public.shop_pass_claims c where c.user_id=u and c.sku=sp.sku and c.seq=sp.seq),'[]'::jsonb))
   order by p.sort,sp.seq) from public.shop_passes sp join public.shop_products p on p.sku=sp.sku
   where sp.user_id=u and sp.ends_on>=public._shop_day()-31),'[]'::jsonb));
end $$;
revoke all on function public._payment_settle_base_v1(uuid,text,text,integer,text,text,integer,text) from public,anon,authenticated,service_role;
revoke all on function public.shop_pass_days() from public,anon;
grant execute on function public.shop_pass_days() to authenticated;
notify pgrst,'reload schema';
commit;
select 'season pass 31 days installed (new purchases only, Toss staging)' as result;
