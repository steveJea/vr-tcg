// 시즌패스 31일 (supabase/seasonpass_31_staging.sql): Toss 결제 정산 → 패스 31일, 중복 정산 방지, 당일 수령, 달력 데이터, 기존 패스/심연석 2배 보존.
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
const service=(expr,args=[])=>call('service_role',null,expr,args);
const pay=async(uid,product)=>{
 const o=await call('authenticated',uid,'payment_create_v1($1,$2)',[product,randomUUID()]);
 await service('_payment_bind_v1($1,$2,$3,$4)',[uid,o.order_id,'key_'+o.order_id,o.amount]);
 const settle=()=>service('_payment_settle_v1($1,$2,$3,$4,$5,$6,$7,$8)',[uid,o.order_id,'key_'+o.order_id,o.amount,'KRW','DONE',o.amount,new Date().toISOString()]);
 return {o,r:await settle(),settle};
};
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
 for(const f of ['payments_staging','payments_refunds_staging','payments_webhook_staging','shop_bm_staging'])await db.exec(swap(await read('supabase/'+f+'.sql')));
 const a=randomUUID(),b=randomUUID();await q('insert into auth.users(id) values ($1),($2)',[a,b]);
 // existing 30-day pass from the old test grant stays 30 days
 await buy(a,'pass_1');
 const sql=swap(await read('supabase/seasonpass_31_staging.sql'));
 await db.exec("select set_config('test.payment_db','7692130048193495360',false)");
 await assert.rejects(db.exec(sql),/STOP: season pass staging only/);await db.exec('rollback');
 await db.exec("select set_config('test.payment_db','7703759698107299042',false)");
 // unknown gem settlement body must stop, not be overwritten
 await db.exec("create or replace function public._payment_settle_base_v1(p_uid uuid,p_order text,p_key text,p_amount integer,p_currency text,p_status text,p_balance integer,p_approved text) returns jsonb language sql as $$select '{}'::jsonb$$");
 await assert.rejects(db.exec(sql),/STOP: unexpected gem settlement/);await db.exec('rollback');
 await db.exec(swap(await read('supabase/shop_bm_staging.sql')));
 // CRLF-stored body (Supabase paste) still matches
 const src=await v("select prosrc v from pg_proc where oid='public._payment_settle_base_v1(uuid,text,text,integer,text,text,integer,text)'::regprocedure");
 await db.exec("create or replace function public._payment_settle_base_v1(p_uid uuid,p_order text,p_key text,p_amount integer,p_currency text,p_status text,p_balance integer,p_approved text) returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $crlf$"+src.replaceAll('\n','\r\n')+"$crlf$");
 await db.exec(sql);await db.exec(sql);
 assert.deepEqual(await q("select sku,price_krw,payment_sku,(reward->>'days')::int days,reward->'daily' daily,reward->'first' first from shop_products where tab='pass' order by sort"),[
  {sku:'pass_1',price_krw:5500,payment_sku:'pass_1',days:31,daily:{tickets:1,stamina:100,gold:5000},first:{}},
  {sku:'pass_2',price_krw:22000,payment_sku:'pass_2',days:31,daily:{tickets:1,stamina:150,gold:10000,gem_free:50},first:{tickets:10}},
  {sku:'pass_3',price_krw:44000,payment_sku:'pass_3',days:31,daily:{tickets:1,stamina:200,gold:10000,blood:10000,shard:10000,gem_free:100},first:{tickets:30,gem_paid:300}}]);
 assert.deepEqual(await q("select id,amount,paid_gems,bonus_gems from payment_products where id like 'pass_%' order by sort"),[
  {id:'pass_1',amount:5500,paid_gems:0,bonus_gems:0},{id:'pass_2',amount:22000,paid_gems:0,bonus_gems:0},{id:'pass_3',amount:44000,paid_gems:0,bonus_gems:0}]);
 await assert.rejects(q("insert into payment_products(id,name,amount,paid_gems,bonus_gems,sort) values('pass_9','x',1,0,0,1)"));
 await assert.rejects(q("insert into payment_products(id,name,amount,paid_gems,bonus_gems,sort) values('gem_9','x',1,0,0,1)"));
 // gem charge keeps first-purchase 2x
 const g1=await pay(b,'gem_500');assert.equal(g1.r.firstBonus,true);assert.deepEqual(await wallet(b),{gold:0,blood:0,shard:0,paid:1000,free:50});
 const g2=await pay(b,'gem_500');assert.equal(g2.r.firstBonus,false);
 // pass_3 via Toss settle: queued after existing pass_1? no — different sku, starts today, 31 days, first reward once
 const t0=await tickets(a),w0=(await wallet(a))||{paid:0};
 const p3=await pay(a,'pass_3');
 assert.equal(p3.r.kind,'pass');assert.equal(p3.r.sku,'pass_3');assert.equal(p3.r.paidGems,0);assert.equal(p3.r.firstBonus,false);
 assert.equal(await tickets(a),t0+30);assert.equal((await wallet(a)).paid,w0.paid+300);
 assert.deepEqual(await p3.settle(),p3.r);assert.equal(await tickets(a),t0+30);
 const days=await q("select sku,seq,(ends_on-starts_on+1) n from shop_passes where user_id=$1 order by sku,seq",[a]);
 assert.deepEqual(days,[{sku:'pass_1',seq:1,n:30},{sku:'pass_3',seq:1,n:31}]);
 // repurchase queues right after
 const p3b=await pay(a,'pass_3');
 assert.equal(await v("select (select starts_on from shop_passes where user_id=$1 and sku='pass_3' and seq=2)-(select ends_on from shop_passes where user_id=$1 and sku='pass_3' and seq=1) v",[a]),1);
 assert.equal(p3b.r.seq,2);
 // amount mismatch rejected
 const o=await call('authenticated',b,'payment_create_v1($1,$2)',['pass_1',randomUUID()]);
 assert.equal(o.paid_gems,0);
 await service('_payment_bind_v1($1,$2,$3,$4)',[b,o.order_id,'kx',o.amount]);
 await assert.rejects(service('_payment_settle_v1($1,$2,$3,$4,$5,$6,$7,$8)',[b,o.order_id,'kx',1,'KRW','DONE',1,new Date().toISOString()]),/mismatch/);
 // claim today only once; calendar shows it
 const c1=await call('authenticated',a,'shop_pass_claim()');assert.ok(c1);
 const tAfter=await tickets(a);await call('authenticated',a,'shop_pass_claim()');assert.equal(await tickets(a),tAfter);
 const cal=await call('authenticated',a,'shop_pass_days()');
 const today=await v("select public._shop_day()::text v");
 assert.equal(cal.today,today);
 const p3c=cal.passes.filter(p=>p.sku==='pass_3');
 assert.deepEqual(p3c.map(p=>[p.seq,p.days,p.state,p.claimed]),[[1,31,'active',[today]],[2,31,'queued',[]]]);
 assert.deepEqual(cal.passes.find(p=>p.sku==='pass_1').claimed,[today]);
 await q("select set_config('request.jwt.claim.sub','',false)");
 await assert.rejects(call('anon',null,'shop_pass_days()'));
 // refunds of pass orders go to CS review (no 'toss:' gem ledger row)
 const adm='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';await q("insert into auth.users(id,email,email_confirmed_at) values($1,'stevejean77@gmail.com',now())",[adm]);
 await db.exec('reset role');await q("select set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claims',$2,false)",[adm,JSON.stringify({sub:adm,email:'stevejean77@gmail.com'})]);
 await db.exec('set role authenticated');
 try{await assert.rejects(q('select admin_payment_refund_prepare_v1($1) v',[p3.o.order_id]),/refund cs review/);}finally{await db.exec('reset role');}
 assert.equal(await tickets(a)>=t0+30,true);
 console.log('seasonpass sql ok');
}finally{await db.close();}
