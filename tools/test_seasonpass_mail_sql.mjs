// 시즌패스 우편 (supabase/seasonpass_mail_staging.sql): 지난 날 우편 생성·중복 없음·기한 없음, 직접 받은 날 제외, 모두 받기(행동력 포함), 구 받기 차단, 환불 중단, 확인 SQL.
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
 await service('_payment_settle_v1($1,$2,$3,$4,$5,$6,$7,$8)',[uid,o.order_id,'key_'+o.order_id,o.amount,'KRW','DONE',o.amount,new Date().toISOString()]);
 return o;
};
const shift=(uid,sku,k)=>q("update shop_passes set starts_on=starts_on-$3::int, ends_on=ends_on-$3::int where user_id=$1 and sku=$2",[uid,sku,k]);
const stamina=async uid=>{await q('select public._player_sync($1)',[uid]);return v('select stamina::int v from player_state where user_id=$1',[uid]);};
const passMails=uid=>q("select pass_key,payload,claimed_at is not null claimed,expires_at='infinity'::timestamptz forever from player_mail where user_id=$1 and pass_key is not null order by pass_key",[uid]);
try{
 await db.exec(`create role anon;create role authenticated;create role service_role bypassrls;create schema auth;
 create table auth.users(id uuid primary key,email text,raw_user_meta_data jsonb default '{}',raw_app_meta_data jsonb default '{}',created_at timestamptz default now(),last_sign_in_at timestamptz,email_confirmed_at timestamptz);
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
 grant usage on schema auth,public to anon,authenticated,service_role;
 alter default privileges in schema public grant all on tables to anon,authenticated;
 alter default privileges in schema public grant all on sequences to anon,authenticated;
 alter default privileges in schema public grant execute on functions to anon,authenticated;`);
 await db.exec((await buildSql()).replace(`confirmed_ref text := '${INSTALL_ACK}'`,"confirmed_ref text := 'abcdefghijklmnopqrst'"));
 const realId=await v('select system_identifier::text v from pg_control_system()');
 await db.exec((await read('supabase/ur_ticket_mail_staging.sql')).replaceAll("'7703759698107299042'",`'${realId}'`));
 await db.exec(`create function public.test_payment_control() returns table(system_identifier text) language sql as $$select current_setting('test.payment_db',true)$$;select set_config('test.payment_db','7703759698107299042',false);`);
 for(const f of ['payments_staging','payments_refunds_staging','payments_webhook_staging','shop_bm_staging','seasonpass_31_staging'])await db.exec(swap(await read('supabase/'+f+'.sql')));
 const [a,b,c,d]=[randomUUID(),randomUUID(),randomUUID(),randomUUID()];
 await q('insert into auth.users(id) values ($1),($2),($3),($4)',[a,b,c,d]);
 const today=await v("select public._shop_day()::text v"), day=k=>v("select (public._shop_day()+$1::int)::text v",[k]);
 // before mail install: a bought pass_2 three days ago, claimed only today directly
 await pay(a,'pass_2');await shift(a,'pass_2',3);
 await call('authenticated',a,'shop_pass_claim()');
 const t0=await tickets(a);
 const sql=swap(await read('supabase/seasonpass_mail_staging.sql'));
 await db.exec("select set_config('test.payment_db','7692130048193495360',false)");
 await assert.rejects(db.exec(sql),/STOP: season pass mail staging only/);await db.exec('rollback');
 await db.exec("select set_config('test.payment_db','7703759698107299042',false)");
 await db.exec(sql);await db.exec(sql);
 // backfill: days 1..3 mailed, day 4 (today, claimed directly) not
 let pm=await passMails(a);
 assert.deepEqual(pm.map(r=>r.pass_key),[`pass:pass_2:1:${await day(-3)}`,`pass:pass_2:1:${await day(-2)}`,`pass:pass_2:1:${await day(-1)}`]);
 assert.ok(pm.every(r=>r.forever&&!r.claimed));
 assert.deepEqual(pm[0].payload,{tickets:1,gem:50,stamina:150,cur:{gold:10000}});
 // list/unread are idempotent (unique key)
 await call('authenticated',a,'mail_unread()');const list=await call('authenticated',a,'mail_list()');await call('authenticated',a,'mail_list()');
 assert.equal((await passMails(a)).length,3);assert.equal(list.filter(m=>/프리미엄|시즌|패스/.test(m.title)).length>=3||list.length>=3,true);
 // old direct claim no longer grants
 const old=await call('authenticated',a,'shop_pass_claim()');assert.deepEqual(old.claimed,[]);assert.equal(old.via,'mail');assert.equal(await tickets(a),t0);
 let cal=await call('authenticated',a,'shop_pass_days()');
 assert.equal(cal.mail_pending,3);
 assert.deepEqual(cal.passes[0].claimed,[today]);
 assert.deepEqual(cal.passes[0].sent,[await day(-3),await day(-2),await day(-1)]);
 // claim all: sums, stamina added once
 const s0=await stamina(a),w0=await wallet(a);
 const all=await call('authenticated',a,'mail_claim_all()');
 assert.equal(all.claimed,3);assert.deepEqual(all.got,{tickets:3,gem:150,stamina:450,cur:{gold:30000}});
 assert.equal(await tickets(a),t0+3);assert.equal(await stamina(a),s0+450);
 const w1=await wallet(a);assert.equal(w1.gold,w0.gold+30000);assert.equal(w1.free,w0.free+150);
 assert.equal((await call('authenticated',a,'mail_claim_all()')).claimed,0);
 cal=await call('authenticated',a,'shop_pass_days()');
 assert.equal(cal.mail_pending,0);assert.equal(cal.passes[0].claimed.length,4);assert.deepEqual(cal.passes[0].sent,[]);
 // lazy: b's pass started 5 days ago, no visit → first mailbox load creates 6 mails (incl. today), never lost
 await pay(b,'pass_3');await shift(b,'pass_3',5);
 assert.equal((await passMails(b)).length,0);
 await call('authenticated',b,'mail_unread()');
 pm=await passMails(b);assert.equal(pm.length,6);
 assert.deepEqual(pm[0].payload,{tickets:1,gem:100,stamina:200,cur:{gold:10000,blood:10000,shard:10000}});
 // single claim keeps stamina, and cannot be claimed twice
 const id=await v("select id v from player_mail where user_id=$1 and pass_key is not null order by id limit 1",[b]);
 const sb0=await stamina(b);const one=await call('authenticated',b,'mail_msg_claim($1)',[id]);
 assert.equal(one.ok,true);assert.equal(one.got.stamina,200);assert.equal(await stamina(b),sb0+200);
 assert.equal((await call('authenticated',b,'mail_msg_claim($1)',[id])).ok,false);assert.equal(await stamina(b),sb0+200);
 // refund approved → revoke: today's already-sent mail stays; c (no visit yet) gets only days before today
 await q("create or replace function public._is_admin() returns boolean language sql as 'select true'");
 const oc=await pay(c,'pass_1');await shift(c,'pass_1',4);
 const rv=await call('authenticated',c,'admin_shop_pass_revoke($1)',[oc.order_id]);assert.equal(rv.revoked_on,today);
 await call('authenticated',c,'mail_list()');
 assert.deepEqual((await passMails(c)).map(r=>r.pass_key.split(':')[3]),[await day(-4),await day(-3),await day(-2),await day(-1)]);
 const ob=(await q("select order_id from payment_orders where user_id=$1 and product_id='pass_3'",[b]))[0].order_id;
 await call('authenticated',b,'admin_shop_pass_revoke($1)',[ob]);
 assert.equal((await passMails(b)).length,6);
 // refunded order: no mails
 const od=await pay(d,'pass_1');await q("update payment_orders set cancel_status='refunded' where order_id=$1",[od.order_id]);
 await call('authenticated',d,'mail_unread()');assert.equal((await passMails(d)).length,0);
 // stamina attachment validation for admin mails
 assert.deepEqual(await v("select public._mail_clean_payload('{\"stamina\":20,\"tickets\":1}') v"),{tickets:1,stamina:20});
 await assert.rejects(q("select public._mail_clean_payload('{\"stamina\":20000}')"),/stamina must be/);
 await assert.rejects(q("select public._mail_clean_payload('{\"cur\":{\"stamina\":1}}')"),/invalid currency/);
 // internals not callable by players
 await q("select set_config('request.jwt.claim.sub','',false)");
 await assert.rejects(call('authenticated',a,'_mail_msg_claim_base_pass_v1($1)',[1]));
 await assert.rejects(call('authenticated',a,'_shop_pass_mail_sync($1)',[a]));
 await assert.rejects(call('anon',null,'mail_claim_all()'));
 // re-applying the original UR mail file then this file again re-wraps cleanly (CRLF-tolerant marker)
 await db.exec((await read('supabase/ur_ticket_mail_staging.sql')).replaceAll("'7703759698107299042'",`'${realId}'`));
 await db.exec(sql.replaceAll('\n','\r\n'));
 assert.deepEqual(await v("select public._mail_clean_payload('{\"stamina\":5}') v"),{stamina:5});
 // check SQL: single SELECT, ok
 const chk=(await read('supabase/seasonpass_mail_check_staging.sql')).replaceAll('pg_catalog.pg_control_system()','public.test_payment_control()');
 const res=(await db.query(chk)).rows;assert.equal(res.length,1);const cr=res[0].check_result;
 assert.equal(cr.ok,true,JSON.stringify(cr));assert.equal(cr.double_grant_0,0);assert.equal(cr.dup_mail_0,0);assert.equal(cr.expiring_pass_mail_0,0);assert.equal(cr.days_not_mailed_yet_0,0);
 console.log('seasonpass mail sql ok',JSON.stringify(cr));
}finally{await db.close();}
