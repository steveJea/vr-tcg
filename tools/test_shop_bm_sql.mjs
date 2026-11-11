// BM 상점 (supabase/shop_bm_staging.sql): 카탈로그 숫자, SKU별 첫 구매 2배, 월 제한, 패스 즉시·일일, 드링크 무료 우선.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {PGlite} from '@electric-sql/pglite';
import {buildSql,INSTALL_ACK} from './build_staging_sql.mjs';
const read=p=>readFile(new URL('../'+p,import.meta.url),'utf8');
const swap=s=>s.replaceAll('pg_catalog.pg_control_system()','public.test_payment_control()');
const db=new PGlite();
const q=async(s,p=[])=>(await db.query(s,p)).rows;
const v=async(s,p=[])=>(await q(s,p))[0]?.v;
const role=async(who,uid,fn)=>{
 await db.exec('reset role');
 await q("select set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claims',$2,false)",[uid||'',JSON.stringify(uid?{sub:uid}:{})]);
 await db.exec('set role '+who);
 try{return await fn();}finally{await db.exec('reset role');}
};
const call=(who,uid,expr,args=[])=>role(who,uid,()=>v('select '+expr+' v',args));
const buy=(uid,sku)=>call('authenticated',uid,'shop_buy($1)',[sku]);
const wallet=uid=>q('select coalesce(gold,0)::int gold, coalesce(blood,0)::int blood, coalesce(shard,0)::int shard, coalesce(gem_paid,0)::int paid, coalesce(gem_free,0)::int free from player_wallet where user_id=$1',[uid]).then(r=>r[0]);
const tickets=async uid=> (await v('select coalesce(tickets,0)::int v from story_gacha where user_id=$1',[uid]))??0;
const product=async(uid,sku)=>{const s=await call('authenticated',uid,'shop_status()');return s.products.find(p=>p.sku===sku);};
try{
 await db.exec(`create role anon;create role authenticated;create role service_role bypassrls;create schema auth;
 create table auth.users(id uuid primary key,email text,raw_user_meta_data jsonb default '{}',raw_app_meta_data jsonb default '{}',created_at timestamptz default now(),last_sign_in_at timestamptz,email_confirmed_at timestamptz);
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
 grant usage on schema auth,public to anon,authenticated,service_role;
 alter default privileges in schema public grant all on tables to anon,authenticated;
 alter default privileges in schema public grant execute on functions to anon,authenticated;`);
 await db.exec((await buildSql()).replace(`confirmed_ref text := '${INSTALL_ACK}'`,"confirmed_ref text := 'abcdefghijklmnopqrst'"));
 await db.exec(`create function public.test_payment_control() returns table(system_identifier text) language sql as $$select current_setting('test.payment_db',true)$$;select set_config('test.payment_db','7703759698107299042',false);`);
 await db.exec(swap(await read('supabase/payments_staging.sql')));
 await db.exec(swap(await read('supabase/payments_refunds_staging.sql')));
 const shop=swap(await read('supabase/shop_bm_staging.sql'));
 await db.exec("select set_config('test.payment_db','7692130048193495360',false)");
 await assert.rejects(db.exec(shop),/STOP: shop staging/);await db.exec('rollback');
 await db.exec("select set_config('test.payment_db','7703759698107299042',false)");
 await q("update payment_products set name='old', amount=1000, paid_gems=1, bonus_gems=9 where id='gem_1000'");
 await q("delete from payment_products where id='gem_55000'");
 await db.exec(shop);await db.exec(shop);
 assert.deepEqual(await q('select id,amount,paid_gems,bonus_gems from payment_products order by sort'),[
  {id:'gem_100',amount:1100,paid_gems:100,bonus_gems:0},{id:'gem_500',amount:5500,paid_gems:500,bonus_gems:25},
  {id:'gem_1000',amount:11000,paid_gems:1050,bonus_gems:0},{id:'gem_3000',amount:33000,paid_gems:3200,bonus_gems:0},
  {id:'gem_55000',amount:55000,paid_gems:5500,bonus_gems:0}]);
 assert.deepEqual(await q("select sku,price_krw,month_max,(reward->>'tickets') tickets,(reward->>'gold') gold,(reward->>'gem_paid') paid,(reward->>'gem_free') free from shop_products order by sort"),[
  {sku:'gem_100',price_krw:1100,month_max:null,tickets:null,gold:null,paid:'100',free:'0'},
  {sku:'gem_500',price_krw:5500,month_max:null,tickets:null,gold:null,paid:'500',free:'25'},
  {sku:'gem_1000',price_krw:11000,month_max:null,tickets:null,gold:null,paid:'1050',free:'0'},
  {sku:'gem_3000',price_krw:33000,month_max:null,tickets:null,gold:null,paid:'3200',free:'0'},
  {sku:'gem_55000',price_krw:55000,month_max:null,tickets:null,gold:null,paid:'5500',free:'0'},
  {sku:'ticket_10',price_krw:1100,month_max:1,tickets:'10',gold:null,paid:null,free:null},
  {sku:'ticket_45',price_krw:5500,month_max:1,tickets:'45',gold:null,paid:null,free:null},
  {sku:'ticket_160',price_krw:22000,month_max:2,tickets:'160',gold:null,paid:null,free:null},
  {sku:'ticket_220',price_krw:33000,month_max:null,tickets:'220',gold:null,paid:null,free:null},
  {sku:'level_1',price_krw:22000,month_max:2,tickets:null,gold:'150000',paid:null,free:null},
  {sku:'pass_1',price_krw:5500,month_max:null,tickets:null,gold:null,paid:null,free:null},
  {sku:'pass_2',price_krw:22000,month_max:null,tickets:null,gold:null,paid:null,free:null},
  {sku:'pass_3',price_krw:44000,month_max:null,tickets:null,gold:null,paid:null,free:null}]);
 const base=await v("select pg_get_functiondef('public._payment_settle_base_v1(uuid,text,text,integer,text,text,integer,text)'::regprocedure) v");
 const wrap=await v("select pg_get_functiondef('public._payment_settle_v1(uuid,text,text,integer,text,text,integer,text)'::regprocedure) v");
 assert.match(base,/shop_purchases/);assert.match(base,/paid_gems\*2/);assert.match(wrap,/_payment_settle_base_v1/);assert.doesNotMatch(wrap,/shop_purchases/);
 const a=randomUUID(),b=randomUUID(),c=randomUUID();
 await q('insert into auth.users(id) values ($1),($2),($3)',[a,b,c]);
 await assert.rejects(call('anon',a,"shop_buy('gem_100')"),/permission denied/);
 await assert.rejects(call('authenticated',a,"_shop_apply($1,'{}'::jsonb,'x','y')",[a]),/permission denied/);
 await assert.rejects(role('authenticated',a,()=>q('select * from shop_products')),/permission denied/);
 let r=await buy(a,'gem_100');assert.equal(r.first_bonus,true);assert.equal(r.paid,200);assert.equal(r.free,0);assert.equal((await product(a,'gem_100')).first_open,false);
 r=await buy(a,'gem_100');assert.equal(r.first_bonus,false);assert.equal(r.paid,300);
 const order=await call('authenticated',a,'payment_create_v1($1,$2)',['gem_1000',randomUUID()]);
 await call('service_role',a,'_payment_bind_v1($1,$2,$3,$4)',[a,order.order_id,'opaque_shop',order.amount]);
 const settled=await call('service_role',a,'_payment_settle_v1($1,$2,$3,$4,$5,$6,$7,$8)',[a,order.order_id,'opaque_shop',order.amount,'KRW','DONE',order.amount,new Date().toISOString()]);
 assert.equal(settled.paidGems,2100);assert.equal(settled.firstBonus,true);assert.equal((await wallet(a)).paid,2400);
 r=await buy(a,'gem_1000');assert.equal(r.first_bonus,false);assert.equal((await wallet(a)).paid,3450);
 r=await buy(a,'gem_500');assert.equal(r.first_bonus,true);assert.equal((await wallet(a)).paid,4450);assert.equal((await wallet(a)).free,50);
 await buy(a,'ticket_10');await assert.rejects(buy(a,'ticket_10'),/monthly limit/);
 await q("update shop_purchases set ym=(ym-interval '1 month')::date where user_id=$1 and sku='ticket_10'",[a]);
 await buy(a,'ticket_10');assert.equal(await tickets(a),20);
 await buy(a,'ticket_160');await buy(a,'ticket_160');await assert.rejects(buy(a,'ticket_160'),/monthly limit/);
 await buy(a,'ticket_220');await buy(a,'ticket_220');await buy(a,'ticket_220');assert.equal(await tickets(a),20+320+660);
 r=await buy(a,'level_1');assert.deepEqual(await wallet(a).then(w=>({gold:w.gold,blood:w.blood,shard:w.shard})),{gold:150000,blood:150000,shard:50000});
 await buy(a,'level_1');await assert.rejects(buy(a,'level_1'),/monthly limit/);
 await db.exec(`update player_wallet set gem_free=80, gem_paid=30 where user_id='${a}'`);
 r=await call('authenticated',a,"drink_buy('drink1')");assert.equal(r.bought,1);assert.equal(r.tradable,1);assert.equal(r.gem.free,0);assert.equal(r.gem.paid,10);
 r=await buy(b,'pass_2');assert.equal(r.grant.tickets,10);assert.equal(await tickets(b),10);
 await call('authenticated',b,'player_status()');
 const beforeB=await v('select stamina::int v from player_state where user_id=$1',[b]);
 r=await call('authenticated',b,'shop_pass_claim()');assert.equal(r.claimed.length,1);assert.equal(await tickets(b),11);assert.equal((await wallet(b)).free,50);assert.equal((await wallet(b)).gold,10000);
 assert.equal(await v('select stamina::int v from player_state where user_id=$1',[b]),beforeB+150);
 r=await call('authenticated',b,'shop_pass_claim()');assert.equal(r.claimed.length,0);
 await buy(b,'pass_1');r=await call('authenticated',b,'shop_pass_claim()');assert.equal(r.claimed.length,1);assert.equal(await tickets(b),12);assert.equal((await wallet(b)).gold,15000);
 await buy(b,'pass_1');
 assert.equal(await v("select count(*)::int v from shop_passes where user_id=$1 and sku='pass_1'",[b]),2);
 assert.equal(await v("select (b.starts_on=a.ends_on+1) v from shop_passes a join shop_passes b on b.user_id=a.user_id and b.sku=a.sku and b.seq=2 where a.user_id=$1 and a.sku='pass_1' and a.seq=1",[b]),true);
 r=await call('authenticated',b,'shop_pass_claim()');assert.equal(r.claimed.length,0);
 r=await buy(c,'pass_3');assert.equal((await wallet(c)).paid,300);assert.equal(await tickets(c),30);
 await call('authenticated',c,'player_status()');
 const beforeC=await v('select stamina::int v from player_state where user_id=$1',[c]);
 r=await call('authenticated',c,'shop_pass_claim()');assert.equal((await wallet(c)).free,100);assert.equal((await wallet(c)).paid,300);assert.equal(await tickets(c),31);
 assert.equal((await wallet(c)).gold,10000);assert.equal((await wallet(c)).blood,10000);assert.equal((await wallet(c)).shard,10000);
 assert.equal(await v('select stamina::int v from player_state where user_id=$1',[c]),beforeC+200);
 await q("update shop_pass_claims set day=date '2000-01-01' where user_id=$1",[c]);
 await q("update gem_ledger set ref=ref||':prev' where user_id=$1 and ref like 'pass-day:%'",[c]);
 r=await call('authenticated',c,'shop_pass_claim()');assert.equal(r.claimed.length,1);assert.equal((await wallet(c)).free,200);assert.equal((await wallet(c)).paid,300);assert.equal(await tickets(c),32);
 const kept=await v('select count(*)::int v from shop_purchases');await db.exec(shop);assert.equal(await v('select count(*)::int v from shop_purchases'),kept);
 await db.exec("select set_config('test.payment_db','7692130048193495360',false)");
 await assert.rejects(buy(a,'ticket_220'),/shop unavailable/);
 console.log('Shop BM: catalog, 2x once per SKU, Toss/mock share the flag, monthly limits, pass first+daily, drink free-then-paid OK');
}finally{await db.close();}
