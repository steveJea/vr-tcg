// 상점 개편 (supabase/shop_v2_staging.sql, 시트 68): 모든 지급은 우편, 시즌패스 30일·중복 불가, 아이템 패키지 월 제한,
// 심연석 상점(수량·무료 먼저), 장비 9칸(하루 1회), 팝업스토어(계정 1회, 2·3일차 우편), 첫 구매 2배, 운영본 차단, 확인 SQL.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {PGlite} from '@electric-sql/pglite';
import {buildSql,INSTALL_ACK} from './build_staging_sql.mjs';
import {productionSql} from './build_shop_v2_sql.mjs';
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
const wallet=uid=>q('select coalesce(gold,0)::int gold, coalesce(blood,0)::int blood, coalesce(shard,0)::int shard, coalesce(gem_paid,0)::int paid, coalesce(gem_free,0)::int free from player_wallet where user_id=$1',[uid]).then(r=>r[0]||{gold:0,blood:0,shard:0,paid:0,free:0});
const tickets=async uid=>(await v('select coalesce(tickets,0)::int v from story_gacha where user_id=$1',[uid]))??0;
const special=async uid=>(await v('select coalesce(tickets,0)::int v from special_wallet where user_id=$1',[uid]))??0;
const drinks=async uid=>(await q('select coalesce(tradable,0)::int t, coalesce(bound,0)::int b from player_items where user_id=$1 and item=$2',[uid,'drink']))[0]||{t:0,b:0};
const mails=uid=>q("select id,pass_key,payload,title,claimed_at is not null claimed,expires_at='infinity'::timestamptz forever from player_mail where user_id=$1 and kind='msg' order by id",[uid]);
const claimAll=uid=>call('authenticated',uid,'mail_claim_all()');
const setDb=id=>db.exec(`select set_config('test.payment_db','${id}',false)`);
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
 await db.exec(`create function public.test_payment_control() returns table(system_identifier text) language sql as $$select current_setting('test.payment_db',true)$$;`);
 await setDb('7703759698107299042');
 for(const f of ['payments_staging','payments_refunds_staging','payments_webhook_staging','shop_bm_staging','seasonpass_31_staging','seasonpass_mail_staging','special_summon_staging'])await db.exec(swap(await read('supabase/'+f+'.sql')));
 const [a,b,c,d]=[randomUUID(),randomUUID(),randomUUID(),randomUUID()];
 await q('insert into auth.users(id) values ($1),($2),($3),($4)',[a,b,c,d]);
 // an old-style pass bought before v2 (31 days, stamina daily) keeps working
 await buy(d,'pass_1');
 const sql=swap(await read('supabase/shop_v2_staging.sql'));
 await setDb('7692130048193495360');
 await assert.rejects(db.exec(sql),/STOP: shop v2 staging only/);await db.exec('rollback');
 await setDb('7703759698107299042');
 await db.exec(sql);await db.exec(sql.replaceAll('\n','\r\n'));
 const today=await v("select public._shop_day()::text v");
 // catalog
 let st=await call('authenticated',a,'shop_status()');
 assert.equal(st.v,2);assert.equal(st.krw_test,true);
 const P=Object.fromEntries(st.products.map(p=>[p.sku,p]));
 assert.deepEqual(Object.keys(P).sort(),['gem_100','gem_1000','gem_3000','gem_500','gem_55000','level_1','pass_1','pass_2','pass_3','popup_first','popup_special','prem_10','prem_25','prem_45','spec_10','spec_25','spec_45']);
 assert.deepEqual(['pass_1','pass_2','pass_3'].map(k=>[P[k].name,P[k].price_krw,P[k].grant.days]),[['프리미엄 시즌패스',5500,30],['스페셜 시즌패스',22000,30],['럭셔리 시즌패스',44000,30]]);
 assert.deepEqual(['prem_10','prem_25','prem_45','spec_10','spec_25','spec_45','level_1'].map(k=>[P[k].price_krw,P[k].month_max]),[[11000,3],[33000,3],[66000,2],[11000,3],[33000,3],[66000,2],[22000,2]]);
 assert.deepEqual([P.prem_25.grant,P.prem_45.grant,P.spec_25.grant,P.spec_45.grant],[{tickets:25},{tickets:45},{special_tickets:25},{special_tickets:45}]);
 assert.deepEqual([P.popup_first.price_krw,P.popup_special.price_krw,P.popup_first.acct_max],[1650,16500,1]);
 assert.deepEqual(st.gem_items.map(g=>[g.sku,g.price]),[['gem_prem_ticket',150],['gem_spec_ticket',150],['gem_drink',100]]);
 assert.equal(st.gear.length,9);assert.deepEqual(st.gear.map(g=>g.slot),['weapon','weapon','weapon','armor','armor','armor','acc','acc','acc']);
 assert.ok(st.gear.every(g=>({HR:[4,500],SR:[5,1000],UR:[6,5000]})[g.grade].join()===[g.tier,g.price].join()));
 assert.equal(await v("select count(*)::int v from shop_products where sku like 'ticket_%' and active"),0);
 // gear slots are stable for the day
 assert.deepEqual((await call('authenticated',a,'shop_status()')).gear.map(g=>g.def_id),st.gear.map(g=>g.def_id));
 // gem package: nothing granted directly, one mail with paid gems, first buy x2 once
 let w0=await wallet(a);
 let r=await buy(a,'gem_500');assert.equal(r.first_bonus,true);assert.equal(r.mailed,true);
 assert.deepEqual(await wallet(a),w0);
 let m=await mails(a);assert.equal(m.length,1);assert.deepEqual(m[0].payload,{gem:50,gem_paid:1000});assert.equal(m[0].forever,true);assert.match(m[0].title,/첫 구매 2배/);
 r=await buy(a,'gem_500');assert.equal(r.first_bonus,false);
 let all=await claimAll(a);assert.equal(all.claimed,2);assert.deepEqual(all.got,{gem:75,gem_paid:1500});
 let w1=await wallet(a);assert.equal(w1.paid,w0.paid+1500);assert.equal(w1.free,w0.free+75);
 // item packages: monthly limit, special tickets via mail
 const t0=await tickets(a),s0=await special(a);
 for(let i=0;i<3;i++)await buy(a,'spec_25');
 await assert.rejects(buy(a,'spec_25'),/monthly limit/);
 await buy(a,'prem_45');await buy(a,'prem_45');await assert.rejects(buy(a,'prem_45'),/monthly limit/);
 assert.equal(await special(a),s0);assert.equal(await tickets(a),t0);
 all=await claimAll(a);assert.deepEqual(all.got,{special_tickets:75,tickets:90});
 assert.equal(await special(a),s0+75);assert.equal(await tickets(a),t0+90);
 await buy(a,'level_1');all=await claimAll(a);assert.deepEqual(all.got,{cur:{gold:150000,blood:150000,shard:50000}});
 // season pass: 30 days, instant + today's daily by mail, cannot stack the same pass, others can
 r=await buy(b,'pass_3');
 const sp=(await q("select starts_on::text s, ends_on::text e from shop_passes where user_id=$1 and sku='pass_3'",[b]))[0];
 assert.equal(sp.s,today);assert.equal(await v("select ($1::date - $2::date)::int v",[sp.e,sp.s]),29);
 await assert.rejects(buy(b,'pass_3'),/pass active/);
 assert.equal((await call('authenticated',b,'shop_status()')).products.find(p=>p.sku==='pass_3').pass_until,sp.e);
 await buy(b,'pass_1');await buy(b,'pass_2');
 m=await mails(b);
 const inst=m.filter(x=>x.pass_key.startsWith('shop:'));assert.deepEqual(inst.map(x=>x.payload),[{gem_paid:300,special_tickets:30},{tickets:10}]);
 const daily=Object.fromEntries(m.filter(x=>x.pass_key.startsWith('pass:')).map(x=>[x.pass_key.split(':')[1],x.payload]));
 assert.deepEqual(daily.pass_1,{tickets:1,drink_bound:1,cur:{gold:5000}});
 assert.deepEqual(daily.pass_2,{gem:50,tickets:1,drink_bound:2,cur:{gold:10000}});
 assert.deepEqual(daily.pass_3,{gem:100,tickets:1,drink_bound:2,cur:{gold:10000,blood:10000,shard:10000}});
 const db0=await drinks(b);all=await claimAll(b);
 assert.equal(all.got.drink_bound,5);assert.equal(all.got.special_tickets,30);assert.equal(all.got.gem_paid,300);
 assert.equal((await drinks(b)).b,db0.b+5);
 let cal=await call('authenticated',b,'shop_pass_days()');assert.equal(cal.mail_pending,0);assert.equal(cal.passes.length,3);
 // after the pass ends it can be bought again
 await q("update shop_passes set starts_on=starts_on-40, ends_on=ends_on-40 where user_id=$1 and sku='pass_1'",[b]);
 await buy(b,'pass_1');
 // gem shop: quantity, free gems first, mail only
 await q("update player_wallet set gem_free=200, gem_paid=1000 where user_id=$1",[c]);
 await q("insert into player_wallet(user_id,gem_free,gem_paid) select $1,200,1000 where not exists (select 1 from player_wallet where user_id=$1)",[c]);
 r=await call('authenticated',c,'shop_gem_buy($1,$2)',['gem_prem_ticket',3]);assert.equal(r.spent,450);
 let wc=await wallet(c);assert.deepEqual([wc.free,wc.paid],[0,750]);
 await call('authenticated',c,'shop_gem_buy($1,$2)',['gem_drink',2]);
 await call('authenticated',c,'shop_gem_buy($1,$2)',['gem_spec_ticket',1]);
 await assert.rejects(call('authenticated',c,'shop_gem_buy($1,$2)',['gem_drink',0]),/invalid qty/);
 await assert.rejects(call('authenticated',c,'shop_gem_buy($1,$2)',['gem_drink',100]),/invalid qty/);
 await assert.rejects(call('authenticated',c,'shop_gem_buy($1,$2)',['gem_drink',99]),/not enough gem/);
 assert.deepEqual((await mails(c)).map(x=>x.payload),[{tickets:3},{drink:2},{special_tickets:1}]);
 const dc0=await drinks(c);all=await claimAll(c);assert.deepEqual(all.got,{tickets:3,drink:2,special_tickets:1});assert.equal((await drinks(c)).t,dc0.t+2);
 // gear: buy a slot once per day, gear arrives by mail
 await q("update player_wallet set gem_free=0, gem_paid=20000 where user_id=$1",[c]);
 const gs=(await call('authenticated',c,'shop_status()')).gear[0];
 r=await call('authenticated',c,'shop_gear_buy($1)',[1]);assert.equal(r.gear[0].bought,true);
 assert.equal((await wallet(c)).paid,20000-gs.price);
 await assert.rejects(call('authenticated',c,'shop_gear_buy($1)',[1]),/sold out/);
 m=await mails(c);assert.deepEqual(m.at(-1).payload,{gear:gs.def_id});
 const g0=await v('select count(*)::int v from player_gear where user_id=$1',[c]);
 await call('authenticated',c,'mail_msg_claim($1)',[m.at(-1).id]);
 assert.equal(await v('select count(*)::int v from player_gear where user_id=$1',[c]),g0+1);
 // grade roll ≈ 95/4.9/0.1 (tiers 4/5/6)
 await q("delete from shop_gear_daily");
 const counts={HR:0,SR:0,UR:0};
 for(let i=0;i<120;i++){const u=randomUUID();await q('insert into auth.users(id) values($1)',[u]);await q('select public._shop_gear_roll($1)',[u]);}
 for(const row of await q('select grade, count(*)::int n from shop_gear_daily group by grade'))counts[row.grade]=row.n;
 const n=counts.HR+counts.SR+counts.UR;assert.equal(n,1080);
 assert.ok(Math.abs(counts.HR/n-.95)<.03&&counts.SR/n<.09&&counts.UR/n<.01,JSON.stringify(counts));
 // popup store: once per account; day 1 now (card + gold + blood), day 2/3 queued
 const owned=async uid=>(await v("select coalesce(jsonb_array_length(data->'owned'),0)::int v from story_progress where user_id=$1",[uid]))??0;
 const o0=await owned(d);
 await buy(d,'popup_first');await assert.rejects(buy(d,'popup_first'),/account limit/);
 m=(await mails(d)).filter(x=>x.pass_key?.startsWith('shop:'));
 assert.deepEqual(m.map(x=>x.payload),[{card:'10325',cur:{gold:10000,blood:10000}}]);
 assert.equal(await v("select count(*)::int v from shop_mail_queue where user_id=$1",[d]),2);
 r=await call('authenticated',d,'mail_msg_claim($1)',[m[0].id]);assert.equal(r.ok,true);assert.equal(r.got.card,'10325');
 assert.equal(await owned(d),o0+1);
 assert.equal(await v("select count(*)::int v from story_gacha_log where user_id=$1 and kind='shop' and card_id='10325'",[d]),1);
 assert.equal((await call('authenticated',d,'mail_msg_claim($1)',[m[0].id])).ok,false);assert.equal(await owned(d),o0+1);
 // move time: day 2 and 3 arrive lazily, once
 await q("update shop_mail_queue set deliver_on=deliver_on-2 where user_id=$1",[d]);
 await call('authenticated',d,'mail_unread()');await call('authenticated',d,'mail_list()');
 m=(await mails(d)).filter(x=>/^shop:\d+:[23]$/.test(x.pass_key||''));
 assert.deepEqual(m.map(x=>x.payload),[{tickets:10},{special_tickets:10}]);
 await buy(d,'popup_special');
 assert.equal(await v("select count(*)::int v from shop_mail_queue where user_id=$1",[d]),4);
 // old v1 pass of d (bought before v2) still mails daily with the new rewards and stays 31 days
 assert.equal(await v("select (ends_on-starts_on)::int v from shop_passes where user_id=$1 and sku='pass_1' and seq=1",[d]),30);
 // internals not callable; anon blocked
 await assert.rejects(call('authenticated',a,'_shop_mail($1,$2,$3,$4,$5)',[a,'{"gem_paid":1}','x','y','k']));
 await assert.rejects(call('authenticated',a,'_shop_gear_roll($1)',[a]));
 await assert.rejects(call('anon',null,'shop_gem_buy($1,$2)',['gem_drink',1]));
 // admin mail validation unchanged (stamina wrapper kept)
 assert.deepEqual(await v("select public._mail_clean_payload('{\"stamina\":20,\"tickets\":1}') v"),{tickets:1,stamina:20});
 // re-running the season pass mail file then this file again re-wraps cleanly
 await db.exec(swap(await read('supabase/seasonpass_mail_staging.sql')));await db.exec(sql);
 assert.match(await v("select prosrc v from pg_proc where oid='public.mail_msg_claim(bigint)'::regprocedure"),/shop-v2/);
 // check SQL: single SELECT, ok
 const chk=swap(await read('supabase/shop_v2_check_staging.sql'));
 const res=(await db.query(chk)).rows;assert.equal(res.length,1);assert.equal(res[0].ok,true,JSON.stringify(res[0]));
 // production file: guard id + KRW test grant blocked, otherwise identical
 const prod=await read('supabase/shop_v2_production.sql');assert.equal(prod,productionSql(await read('supabase/shop_v2_staging.sql')));
 assert.ok(!prod.includes('7703759698107299042'));assert.match(prod,/7692130048193495360/);
 const prodChk=await read('supabase/shop_v2_check_production.sql');assert.ok(!prodChk.includes('7703759698107299042'));
 console.log('shop v2 sql ok',JSON.stringify(counts));
}finally{await db.close();}
// production-like DB (no shop BM / payments / season pass mail installed): prod file installs, KRW blocked, gem shop + mail work.
{
 const db2=new PGlite();const q2=async(s,p=[])=>(await db2.query(s,p)).rows;
 try{
  await db2.exec(`create role anon;create role authenticated;create role service_role bypassrls;create schema auth;
  create table auth.users(id uuid primary key,email text,raw_user_meta_data jsonb default '{}',raw_app_meta_data jsonb default '{}',created_at timestamptz default now(),last_sign_in_at timestamptz,email_confirmed_at timestamptz);
  create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
  create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
  grant usage on schema auth,public to anon,authenticated,service_role;
  alter default privileges in schema public grant execute on functions to anon,authenticated;`);
  await db2.exec((await buildSql()).replace(`confirmed_ref text := '${INSTALL_ACK}'`,"confirmed_ref text := 'abcdefghijklmnopqrst'"));
  const rid=(await q2('select system_identifier::text v from pg_control_system()'))[0].v;
  await db2.exec((await read('supabase/ur_ticket_mail_staging.sql')).replaceAll("'7703759698107299042'",`'${rid}'`));
  await db2.exec(`create function public.test_payment_control() returns table(system_identifier text) language sql as $$select current_setting('test.payment_db',true)$$;select set_config('test.payment_db','7703759698107299042',false);`);
  await db2.exec(swap(await read('supabase/special_summon_staging.sql')));
  await db2.exec("select set_config('test.payment_db','7692130048193495360',false)");
  assert.equal((await q2("select to_regclass('public.shop_products') v"))[0].v,null);
  const prod=swap(await read('supabase/shop_v2_production.sql'));await db2.exec(prod);await db2.exec(prod);
  const u=randomUUID();await q2('insert into auth.users(id) values($1)',[u]);
  const as=async(expr,args=[])=>{await q2("select set_config('request.jwt.claim.sub',$1,false)",[u]);await db2.exec('set role authenticated');try{return (await q2('select '+expr+' v',args))[0].v;}finally{await db2.exec('reset role');}};
  const st=await as('shop_status()');assert.equal(st.krw_test,false);assert.equal(st.products.length,17);
  await assert.rejects(as('shop_buy($1)',['gem_100']),/payment not ready/);
  await q2("insert into player_wallet(user_id,gem_free,gem_paid) values($1,0,300) on conflict (user_id) do update set gem_free=0, gem_paid=300",[u]);
  await as('shop_gem_buy($1,$2)',['gem_spec_ticket',2]);
  const all=await as('mail_claim_all()');assert.deepEqual(all.got,{special_tickets:2});
  const chk=swap(await read('supabase/shop_v2_check_production.sql'));assert.equal((await db2.query(chk)).rows[0].ok,true,JSON.stringify((await db2.query(chk)).rows[0]));
  console.log('shop v2 production sql ok (KRW blocked, gem shop via mail)');
 }finally{await db2.close();}
}

// staging-like DB WITHOUT ur_ticket_mail (real staging state 2026-11-17): installs in one go, mail + gem shop + popup card work.
{
 const db3=new PGlite();const q3=async(s,p=[])=>(await db3.query(s,p)).rows;
 try{
  await db3.exec(`create role anon;create role authenticated;create role service_role bypassrls;create schema auth;
  create table auth.users(id uuid primary key,email text,raw_user_meta_data jsonb default '{}',raw_app_meta_data jsonb default '{}',created_at timestamptz default now(),last_sign_in_at timestamptz,email_confirmed_at timestamptz);
  create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
  create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
  grant usage on schema auth,public to anon,authenticated,service_role;
  alter default privileges in schema public grant execute on functions to anon,authenticated;`);
  await db3.exec((await buildSql()).replace(`confirmed_ref text := '${INSTALL_ACK}'`,"confirmed_ref text := 'abcdefghijklmnopqrst'"));
  await db3.exec(`create function public.test_payment_control() returns table(system_identifier text) language sql as $$select current_setting('test.payment_db',true)$$;select set_config('test.payment_db','7703759698107299042',false);`);
  for(const f of ['payments_staging','payments_refunds_staging','payments_webhook_staging','shop_bm_staging','seasonpass_31_staging','seasonpass_mail_staging','special_summon_staging'])await db3.exec(swap(await read('supabase/'+f+'.sql')));
  assert.equal((await q3("select count(*)::int v from information_schema.columns where table_name='story_gacha' and column_name='ur_tickets'"))[0].v,0,'no ur_ticket_mail');
  const s3=swap(await read('supabase/shop_v2_staging.sql'));await db3.exec(s3);await db3.exec(s3);
  const u=randomUUID();await q3('insert into auth.users(id) values($1)',[u]);
  const as=async(expr,args=[])=>{await q3("select set_config('request.jwt.claim.sub',$1,false)",[u]);await db3.exec('set role authenticated');try{return (await q3('select '+expr+' v',args))[0].v;}finally{await db3.exec('reset role');}};
  await as('shop_buy($1)',['popup_first']);await as('shop_buy($1)',['pass_2']);await as('shop_buy($1)',['gem_100']);
  const all=await as('mail_claim_all()');
  assert.equal(all.got.cards,1);assert.equal(all.got.gem_paid,200);assert.equal(all.got.tickets,11);assert.equal(all.got.drink_bound,2);
  const chk=swap(await read('supabase/shop_v2_check_staging.sql'));const r=(await db3.query(chk)).rows[0];assert.equal(r.ok,true,JSON.stringify(r));
  console.log('shop v2 staging without ur_ticket_mail ok');
 }finally{await db3.close();}
}

// follow-up odds SQL on a DB that already ran shop_v2_staging.sql at bd8e0700 (85/14/1, check weight<=100)
{
 const {execSync}=await import('node:child_process');
 const old=execSync('git show bd8e0700c7670e95674ada85ee5a3f09275f38b8:supabase/shop_v2_staging.sql',{encoding:'utf8',maxBuffer:1e8});
 const db4=new PGlite();const q4=async(s,p=[])=>(await db4.query(s,p)).rows;
 try{
  await db4.exec(`create role anon;create role authenticated;create role service_role bypassrls;create schema auth;
  create table auth.users(id uuid primary key,email text,raw_user_meta_data jsonb default '{}',raw_app_meta_data jsonb default '{}',created_at timestamptz default now(),last_sign_in_at timestamptz,email_confirmed_at timestamptz);
  create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
  create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
  grant usage on schema auth,public to anon,authenticated,service_role;
  alter default privileges in schema public grant execute on functions to anon,authenticated;`);
  await db4.exec((await buildSql()).replace(`confirmed_ref text := '${INSTALL_ACK}'`,"confirmed_ref text := 'abcdefghijklmnopqrst'"));
  await db4.exec(`create function public.test_payment_control() returns table(system_identifier text) language sql as $$select current_setting('test.payment_db',true)$$;select set_config('test.payment_db','7703759698107299042',false);`);
  for(const f of ['payments_staging','payments_refunds_staging','payments_webhook_staging','shop_bm_staging','seasonpass_31_staging','seasonpass_mail_staging','special_summon_staging'])await db4.exec(swap(await read('supabase/'+f+'.sql')));
  await db4.exec(swap(old));
  assert.equal((await q4("select string_agg(grade||'='||weight, ',' order by grade) v from shop_gear_grades"))[0].v,'HR=85,SR=14,UR=1');
  const f=swap(await read('supabase/shop_v2_gear_odds_staging.sql'));await db4.exec(f);await db4.exec(f);
  const r=(await db4.query(swap(await read('supabase/shop_v2_gear_odds_check_staging.sql')))).rows[0];
  assert.equal(r.ok,true);assert.equal(r.odds,'HR 95% · SR 4.9% · UR 0.1%');
  // main check still ok, and rerunning the new main file keeps the new odds
  assert.equal((await db4.query(swap(await read('supabase/shop_v2_check_staging.sql')))).rows[0].ok,true);
  await db4.exec(swap(await read('supabase/shop_v2_staging.sql')));
  assert.equal((await db4.query(swap(await read('supabase/shop_v2_gear_odds_check_staging.sql')))).rows[0].ok,true);
  console.log('shop v2 gear odds follow-up ok',r.odds);
 }finally{await db4.close();}
}
