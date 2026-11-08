import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
import {buildSql,INSTALL_ACK} from './build_staging_sql.mjs';
import {createHandler,validPayment,STAGING} from '../supabase/functions/payments-confirm-v1/handler.mjs';
import {enabled,readReturn,paymentError,loadPending,savePending,api,checkoutParams,sdkErrorCode,sdkFailure} from '../js/payments-core.js';
const read=p=>readFile(new URL('../'+p,import.meta.url),'utf8'),sql=await read('supabase/payments_staging.sql');
assert(sql.includes("'7703759698107299042'"));assert(!sql.includes('7692130048193495360'));
// Offline-only substitute for unavailable pg_control_system in WASM. Production artifact is NOT edited.
const migration=sql.replaceAll('pg_catalog.pg_control_system()','public.test_payment_control()');
const db=new PGlite(),u='11111111-1111-4111-8111-111111111111',other='22222222-2222-4222-8222-222222222222';
const q=async(s,p=[])=>(await db.query(s,p)).rows,val=async(s,p=[])=>(await q(s,p))[0]?.v;
const role=async(who,fn,uid=u)=>{await db.exec(`reset role;select set_config('request.jwt.claim.sub','${uid}',false);set role ${who};`);try{return await fn();}finally{await db.exec('reset role');}};
const call=(who,s,p=[],uid=u)=>role(who,()=>val('select '+s+' v',p),uid);
const create=(product,req,uid=u)=>call('authenticated','payment_create_v1($1,$2)',[product,req],uid);
const bind=(o,key='opaque_key',amount=o.amount,uid=u)=>call('service_role','_payment_bind_v1($1,$2,$3,$4)',[uid,o.order_id,key,amount]);
const settle=(o,key='opaque_key',status='DONE',balance=o.amount,currency='KRW')=>call('service_role','_payment_settle_v1($1,$2,$3,$4,$5,$6,$7,$8)',[o.user_id,o.order_id,key,o.amount,currency,status,balance,'2026-11-08T21:00:00+09:00']);
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
 await q('insert into auth.users(id) values ($1),($2)',[u,other]);
 await db.exec(`create function public.test_payment_control() returns table(system_identifier text) language sql as $$select current_setting('test.payment_db',true)$$; select set_config('test.payment_db','7692130048193495360',false);`);
 await assert.rejects(db.exec(migration),/STOP: payments staging/);await db.exec('rollback');assert.equal(await val("select to_regclass('public.payment_products') v"),null);
 await db.exec("select set_config('test.payment_db','7703759698107299042',false)");await db.exec(migration);await db.exec(migration);
 assert.equal(await val('select count(*)::int v from payment_products'),4);
 await q("update payment_products set amount=6600 where id='gem_500'");await db.exec(migration);assert.equal(await val("select amount v from payment_products where id='gem_500'"),6600);
 for(const s of ["insert into payment_products(id,name,amount,paid_gems) values ('gem_9','forged',100,9999)","update payment_products set amount=100","delete from payment_products","update payment_orders set status='paid'","delete from payment_orders","insert into payment_orders(user_id,request_id,product_id,order_name,amount,currency,paid_gems,bonus_gems) values ('"+u+"',gen_random_uuid(),'gem_100','forged',100,'KRW',999,0)"])
  await assert.rejects(role('authenticated',()=>q(s)),/permission denied/);
 for(const f of ["_payment_bind_v1('"+u+"','fake','key',100)","_payment_settle_v1('"+u+"','fake','key',100,'KRW','DONE',100,'now')","_payments_guard_v1()"])
  for(const r of ['anon','authenticated'])await assert.rejects(call(r,f),/permission denied/);
 const req='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',o=await create('gem_100',req);assert.equal(o.amount,1100);assert.equal((await create('gem_100',req)).order_id,o.order_id);
 await assert.rejects(create('gem_500',req),/request conflict/);
 const b=await create('gem_500','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',other);
 assert.deepEqual(await role('authenticated',()=>q('select order_id from payment_orders')),[{order_id:o.order_id}]);
 assert.deepEqual(await role('authenticated',()=>q('select order_id from payment_orders'),other),[{order_id:b.order_id}]);
 await assert.rejects(bind(o,'opaque_key',100),/payment mismatch/);await assert.rejects(bind(o,'opaque_key',o.amount,other),/order not found/);
 await bind(o);await assert.rejects(bind(o,'other_key'),/payment conflict/);await assert.rejects(bind(b,'opaque_key',b.amount,other),/unique/);
 for(const [s,bal,c]of [['READY',1100,'KRW'],['DONE',100,'KRW'],['DONE',1100,'USD']])await assert.rejects(settle(o,'opaque_key',s,bal,c),/payment mismatch/);
 // A DB exception AFTER _gem_add must roll back both balance and ledger.
 await db.exec(`create function test_payment_failure() returns trigger language plpgsql as $$begin if new.status='paid' then raise exception 'forced failure';end if;return new;end$$;create trigger fail_payment before update on payment_orders for each row execute function test_payment_failure();`);
 await assert.rejects(settle(o),/forced failure/);assert.equal(await val("select count(*)::int v from gem_ledger where ref='toss:'||$1",[o.order_id]),0);
 await db.exec('drop trigger fail_payment on payment_orders');const receipt=await settle(o);assert.equal(receipt.paidGems,100);assert.deepEqual(await settle(o),receipt);
 assert.equal(await val('select gem_paid::int v from player_wallet where user_id=$1',[u]),100);assert.equal(await val("select count(*)::int v from gem_ledger where ref='toss:'||$1",[o.order_id]),1);
 await q("update payment_products set paid_gems=9999,amount=9999 where id='gem_500'");await bind(b,'bonus_key',b.amount,other);await settle(b,'bonus_key');assert.equal(await val('select gem_free::int v from player_wallet where user_id=$1',[other]),25);assert.equal(await val('select gem_paid::int v from player_wallet where user_id=$1',[other]),500);
 const exp=await create('gem_100','cccccccc-cccc-4ccc-8ccc-cccccccccccc');await q("update payment_orders set expires_at=now()-interval '1 second' where order_id=$1",[exp.order_id]);await assert.rejects(bind(exp,'expired'),/order expired/);
 await db.exec("select set_config('test.payment_db','7692130048193495360',false)");await assert.rejects(create('gem_100','dddddddd-dddd-4ddd-8ddd-dddddddddddd'),/payments unavailable/);
 console.log('Payments SQL: prod/unknown guard, repeat install/data preservation, own-row RLS, no direct writes/helper calls, server snapshots, opaque unique keys, atomic rollback/once-only paid+bonus ledger, expiry/runtime guard OK');
}finally{await db.close();}

const env={SUPABASE_URL:STAGING,SUPABASE_PUBLISHABLE_KEYS:'{"default":"sb_publishable_unit"}',SUPABASE_SECRET_KEYS:'{"default":"sb_secret_unit"}',TOSS_SECRET_KEY:'test_sk_unit'};
const order={order_id:'vrs_'+ 'a'.repeat(32),user_id:u,amount:1100,currency:'KRW',order_name:'test',paid_gems:100,bonus_gems:0,status:'pending'};
const payment={paymentKey:'opaque_key',orderId:order.order_id,currency:'KRW',totalAmount:1100,balanceAmount:1100,status:'DONE',approvedAt:'2026-11-08T21:00:00+09:00',method:'카드'};
let events=[],count=0,done=false,lose=false,variant=null,paid=false;
const response=(x,status=200)=>new Response(JSON.stringify(x),{status,headers:{'content-type':'application/json'}});
const fetcher=async(url,opt={})=>{events.push({url,opt});
 if(url.endsWith('/auth/v1/user'))return response({id:u});
 if(url.endsWith('/payment_create_v1')){assert.equal(opt.headers.authorization,'Bearer login');assert.deepEqual(JSON.parse(opt.body),{p_product:'gem_100',p_request:'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'});return response(order);}
 if(url.endsWith('/_payment_bind_v1')){assert.equal(opt.headers.apikey,'sb_secret_unit');assert(!opt.headers.authorization);return response({...order,status:paid?'paid':'pending',receipt:paid?{ok:true}:null});}
 if(url.endsWith('/_payment_settle_v1')){count++;paid=true;return response({ok:true});}
 if(url==='https://api.tosspayments.com/v1/payments/confirm'){
  assert.equal(opt.headers.authorization,'Basic '+btoa('test_sk_unit:'));assert.equal(opt.headers['Idempotency-Key'],'vr-toss-'+order.order_id);assert.equal(JSON.parse(opt.body).amount,order.amount);done=true;if(lose){lose=false;throw Error('lost response');}return response(variant||payment);
 }
 if(url==='https://api.tosspayments.com/v1/payments/opaque_key')return response(done?(variant||payment):{...payment,status:'IN_PROGRESS'});
 throw Error('unexpected destination '+url);
};
const body={op:'confirm',orderId:order.order_id,paymentKey:'opaque_key',amount:1100};
const req=(b=body,origin='https://vr-tcg-staging.notcold.workers.dev',token='Bearer login')=>new Request('https://edge.test',{method:'POST',headers:{'content-type':'application/json',origin,authorization:token},body:JSON.stringify(b)});
const handler=createHandler(env,fetcher);
assert.equal((await handler(req({op:'create',product:'gem_100',request:'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'}))).status,200);
events=[];for(const bad of [{...body,amount:0},{...body,amount:'1100'},{...body,uid:u},{...body,paymentKey:'x'.repeat(201)}])assert.equal((await handler(req(bad))).status,400);assert.equal(events.length,0);
assert.equal((await handler(req(body,'https://ag.violenceroyale.com'))).status,403);assert.equal((await handler(req(body,undefined,''))).status,401);
assert.equal((await createHandler({...env,SUPABASE_URL:'https://htarwisgkkphutxxnuak.supabase.co'},fetcher)(req())).status,503);
assert.equal((await createHandler({...env,TOSS_SECRET_KEY:'live_sk_never'},fetcher)(req())).status,503);
assert.equal((await createHandler({...env,TOSS_SECRET_KEY:''},fetcher)(req())).status,503);
assert.equal((await createHandler({...env,TOSS_CLIENT_KEY:'live_ck_never'},fetcher)(req())).status,503);
lose=true;assert.equal((await handler(req())).status,409);assert(done);assert.equal(count,0);assert.equal((await handler(req())).status,200);assert.equal(count,1);assert.equal((await handler(req())).status,200);assert.equal(count,1);
for(const change of [{orderId:'other'},{paymentKey:'other'},{totalAmount:100},{balanceAmount:100},{currency:'USD'},{status:'CANCELED'},{approvedAt:null},{method:'가상계좌'},{cancels:[{}]}])assert.equal(validPayment({...payment,...change},order,'opaque_key'),false);
const hung=createHandler(env,()=>new Promise(()=>{}),15);assert.equal((await hung(req())).status,504);
const creation={op:'create',product:'gem_100',request:'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'};
for(const [dbCode,message,want]of [['PGRST202','raw SQL must not leak','payment sql required'],['42501','raw private SQL','payment database permissions'],['P0001','payments unavailable','payment database unavailable'],['XX000','unrecognized private DB failure','order creation failed']]){
 const failed=createHandler(env,async url=>url.endsWith('/auth/v1/user')?response({id:u}):response({code:dbCode,message},400));
 const result=await failed(req(creation));assert.equal(result.status,503);assert.deepEqual(await result.json(),{error:want,stage:'order'});
}
const orderHung=createHandler(env,async url=>url.endsWith('/auth/v1/user')?response({id:u}):new Promise(()=>{}),15);
const oh=await orderHung(req(creation));assert.equal(oh.status,504);assert.deepEqual(await oh.json(),{error:'order creation delayed',stage:'order'});

const huge=new Request('https://edge.test',{method:'POST',headers:{'content-type':'application/json'},body:' '.repeat(4097)});assert.equal((await handler(huge)).status,413);
console.log('Payments Edge: host/project/test-key fail-closed, Auth user validation, bounded inputs/deadlines, SDK server amount, stable Toss idempotency, lost approval recovery, exact DONE/currency/amount/key/balance/method, service-only grant OK');
const c={enabled:true,isStaging:true,supabaseUrl:STAGING,anonKey:'public'};
assert(enabled(c,{hostname:'vr-tcg-staging.notcold.workers.dev'}));for(const host of ['ag.violenceroyale.com','vr-tcg-staging.notcold.workers.dev.evil','localhost'])assert(!enabled(c,{hostname:host}));assert(!enabled({...c,isStaging:false},{hostname:'vr-tcg-staging.notcold.workers.dev'}));
assert.equal(readReturn('https://x?vrpay=success&orderId='+order.order_id+'&paymentKey=opaque_key&amount=1100').amount,1100);assert.equal(readReturn('https://x?vrpay=success&orderId='+order.order_id+'&paymentKey=x&amount=-1'),null);
assert.equal(paymentError('<script>bad</script>'),paymentError('unknown'));assert.match(paymentError('USER_CANCEL'),/취소/);
const map=new Map(),store={setItem:(k,v)=>map.set(k,v),getItem:k=>map.get(k)};savePending(store,u,body);assert.equal(loadPending(store,u).orderId,order.order_id);assert.equal(loadPending(store,other),null);
await assert.rejects(api({auth:{getSession:()=>new Promise(()=>{})}},c,body,fetch,10),/pending/);
const authed={auth:{getSession:async()=>({data:{session:{access_token:'test_user_session'}}})}};
for(const [status,payload,want]of [[401,{code:'UNAUTHORIZED_INVALID_JWT_FORMAT',message:'Invalid JWT'},'payment gateway authentication'],[404,{message:'Function not found'},'payment function missing'],[503,{error:'payment sql required'},'payment sql required'],[409,{error:'payment confirmation pending'},'order creation failed'],[500,{message:'private SQL must not appear'},'order creation failed'],[504,{error:'payment confirmation pending'},'order creation delayed']])await assert.rejects(api(authed,c,creation,async()=>response(payload,status)),e=>e.message===want);
await assert.rejects(api(authed,c,creation,async()=>{throw new TypeError('private network detail');}),e=>e.message==='order creation failed');
await assert.rejects(api(authed,c,creation,()=>new Promise(()=>{}),10),e=>e.message==='order creation delayed');
await assert.rejects(api(authed,c,body,async()=>response({error:'payment confirmation pending'},504)),e=>e.message==='payment confirmation pending');
for(const code of ['order creation failed','order creation delayed','payment gateway authentication','payment sdk unavailable','payment checkout failed','payment sql required','payment database permissions'])assert.notEqual(paymentError(code),paymentError('unknown'));
console.log('Pre-checkout diagnostics: gateway 401, missing function, SQL/ACL/runtime/unknown DB errors, order timeout vs confirmation timeout and SDK failures remain distinct; no raw data leaked');

const callback=await read('payment-return.html');assert(callback.indexOf('history.replaceState')<callback.indexOf('src='));assert(!/googletagmanager|gtag\(|google-analytics/.test(callback));assert(callback.includes('no-referrer'));
const client=await read('js/payments.js');assert(client.includes('test_ck_'));assert(!/test_sk_[A-Za-z0-9]{5}|live_[sc]k_|TOSS_SECRET_KEY/.test(client));assert(client.includes('checkoutParams(o,uid,location.origin)'));assert((await read('js/payments-core.js')).includes('value:order.amount'));assert(!client.includes('customerEmail'));
assert((await read('tools/build_staging.mjs')).includes("'payment-return.html'"));assert(!(await read('tools/build_production_assets.mjs')).includes("'payment-return.html'"));
assert.equal(await read('supabase/functions/payments-confirm-v1/dashboard_single_file.ts'),'// Generated from handler.mjs; staging only; JWT verification ON.\n'+await read('supabase/functions/payments-confirm-v1/handler.mjs')+'\nDeno.serve(createHandler(Deno.env.toObject()));\n');
console.log('Payments client: staging-only, no-email safe, trusted server checkout amount, account-scoped durable recovery, URL scrub before SDK/no analytics, bounded API, no secret in public assets, dashboard parity OK');

const params=checkoutParams({orderId:order.order_id,orderName:'심연석 100',amount:1100},u,'https://vr-tcg-staging.notcold.workers.dev');
assert.equal(params.windowTarget,'self');assert.deepEqual(params.amount,{currency:'KRW',value:1100});assert.equal(params.customerEmail,undefined);assert.equal(params.customerName,undefined);
for(const [patch,uid,code]of [[{orderId:undefined},u,'INVALID_ORDER_ID'],[{amount:'1100'},u,'INVALID_AMOUNT_VALUE'],[{orderName:''},u,'INVALID_ORDER_NAME'],[{},'abc','INVALID_CUSTOMER_KEY']])assert.throws(()=>checkoutParams({orderId:order.order_id,orderName:'심연석 100',amount:1100,...patch},uid,'https://vr-tcg-staging.notcold.workers.dev'),new RegExp(code));
assert.equal(sdkErrorCode({code:'INVALID_CLIENT_KEY',message:'must never leak'}),'INVALID_CLIENT_KEY');assert.equal(sdkErrorCode({code:'<script>private</script>',name:'TypeError'}),'TypeError');assert.equal(sdkErrorCode({code:'test_sk_private'}),'SDK_UNKNOWN');assert.match(paymentError('sdk:INVALID_CLIENT_KEY'),/INVALID_CLIENT_KEY/);assert(!paymentError('sdk:<script>').includes('<script>'));
const originalWarn=console.warn,captured=[];console.warn=x=>captured.push(x);try{assert.equal(sdkFailure({code:'INVALID_CLIENT_KEY',message:'private token'},'sdk-init','test_ck_custom').message,'sdk:INVALID_CLIENT_KEY');}finally{console.warn=originalWarn;}
assert(!captured.join('').includes('private'));assert(!captured.join('').includes('test_ck_custom'));assert.match(captured.join(''),/sdk-init/);
console.log('SDK checkout: documented full-page redirect, trusted typed fields, valid UUID customer, no PII, safe code in toast/logs, no key/error-message leakage OK');
