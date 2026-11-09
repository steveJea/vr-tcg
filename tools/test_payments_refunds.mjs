import assert from 'node:assert/strict';
import vm from 'node:vm';
import {parseHTML} from 'linkedom';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {PGlite} from '@electric-sql/pglite';
import {buildSql,INSTALL_ACK} from './build_staging_sql.mjs';
import {createHandler,validCancellation,STAGING} from '../supabase/functions/payments-confirm-v1/handler.mjs';
import {api,paymentError} from '../js/payments-core.js';
const read=p=>readFile(new URL('../'+p,import.meta.url),'utf8');
const source=await read('supabase/payments_refunds_staging.sql');
const migration=source.replaceAll('pg_catalog.pg_control_system()','public.test_payment_control()');
const db=new PGlite(),admin='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',user='11111111-1111-4111-8111-111111111111';
const q=async(s,p=[])=>(await db.query(s,p)).rows,v=async(s,p=[])=>(await q(s,p))[0]?.v;
const role=async(who,uid,fn,claims=uid===admin?{email:'stevejean77@gmail.com'}:{})=>{
 await db.exec('reset role');await q("select set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claims',$2,false)",[uid,JSON.stringify(claims)]);await db.exec('set role '+who);
 try{return await fn();}finally{await db.exec('reset role');}
};
const call=(who,uid,expr,args=[])=>role(who,uid,()=>v('select '+expr+' v',args));
const ac=(expr,args=[])=>call('authenticated',admin,expr,args);
const service=(expr,args=[])=>call('service_role',admin,expr,args);
async function fixture(product='gem_100',preFree=0,prePaid=0){
 const uid=randomUUID();await q('insert into auth.users(id) values ($1)',[uid]);
 if(preFree||prePaid)await v("select _gem_add($1,$2,$3,'test','old',null) v",[uid,preFree,prePaid]);
 const o=await call('authenticated',uid,'payment_create_v1($1,$2)',[product,randomUUID()]);
 await service('_payment_bind_v1($1,$2,$3,$4)',[uid,o.order_id,'opaque_'+uid,o.amount]);
 await service('_payment_settle_v1($1,$2,$3,$4,$5,$6,$7,$8)',[uid,o.order_id,'opaque_'+uid,o.amount,'KRW','DONE',o.amount,new Date().toISOString()]);
 return (await q('select * from payment_orders where order_id=$1',[o.order_id]))[0];
}
const prepare=o=>ac('admin_payment_refund_prepare_v1($1)',[o.order_id]);
const spend=(o,amount)=>v("select _gem_spend($1,$2,'test',null) v",[o.user_id,amount]);
const wallet=o=>q('select gem_paid::int paid,gem_free::int free from player_wallet where user_id=$1',[o.user_id]).then(r=>r[0]);
const proof=o=>[{cancelStatus:'DONE',cancelAmount:o.amount,transactionKey:'cancel_transaction',canceledAt:new Date().toISOString()}];
const finish=(o,patch={})=>service('_payment_refund_finish_v1($1,$2,$3,$4,$5,$6,$7)',[o.order_id,o.payment_key,patch.amount??o.amount,patch.currency??'KRW',patch.status??'CANCELED',patch.balance??0,JSON.stringify(patch.cancels??proof(o))]);
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
 await db.exec(`create function public.test_payment_control() returns table(system_identifier text) language sql as $$select current_setting('test.payment_db',true)$$;select set_config('test.payment_db','7703759698107299042',false);`);
 await db.exec((await read('supabase/payments_staging.sql')).replaceAll('pg_catalog.pg_control_system()','public.test_payment_control()'));
 await q("insert into auth.users(id,email,email_confirmed_at) values ($1,'stevejean77@gmail.com',now()),($2,'not-admin@example.test',now())",[admin,user]);
 await db.exec("select set_config('test.payment_db','7692130048193495360',false)");
 await assert.rejects(db.exec(migration),/STOP: refunds staging only/);await db.exec('rollback');
 assert.equal(await v("select to_regclass('public.payment_refunds') v"),null);
 await db.exec("select set_config('test.payment_db','7703759698107299042',false)");await db.exec(migration);await db.exec(migration);
 for(const expr of ['admin_payment_orders_v1()',"admin_payment_refund_prepare_v1('invalid')","admin_payment_refund_lookup_v1('invalid')"]){
  await assert.rejects(call('authenticated',user,expr),/forbidden/);await assert.rejects(call('anon',user,expr),/permission denied/);
 }
 await assert.rejects(role('authenticated',user,()=>v('select admin_payment_orders_v1() v'),{email:'stevejean77@gmail.com'}),/forbidden/);
 for(const who of ['anon','authenticated','service_role'])for(const expr of ["_payment_create_base_v1('gem_100',gen_random_uuid())","_payment_bind_base_v1(null,'x','x',100)","_payment_settle_base_v1(null,'x','x',100,'KRW','DONE',100,'now')"])await assert.rejects(call(who,user,expr),/permission denied/);
 for(const who of ['anon','authenticated']){
  await assert.rejects(call(who,user,"_payment_refund_note_v1('x','refund pending')"),/permission denied/);
  await assert.rejects(call(who,user,"_payment_refund_finish_v1('x','x',100,'KRW','CANCELED',0,'[]')"),/permission denied/);
  await assert.rejects(role(who,user,()=>q('select * from payment_refunds')),/permission denied/);
 }
 const o=await fixture('gem_500'),original=o.receipt;
 const held=await prepare(o);assert.equal(held.refund.state,'held');assert.equal(held.refund.idempotency_key,'vr-refund-'+o.order_id);assert.deepEqual(await wallet(o),{paid:0,free:0});
 assert.deepEqual(await prepare(o),held);assert.equal(await v("select count(*)::int v from gem_ledger where ref=$1",['toss-refund-hold:'+o.order_id]),1);
 await assert.rejects(spend(o,1),/not enough gem/);
 for(const patch of [{status:'DONE'},{balance:1},{amount:100},{currency:'USD'},{cancels:[]},{cancels:[{...proof(o)[0],cancelAmount:1}]},{cancels:[{...proof(o)[0],cancelStatus:'IN_PROGRESS'}]},{cancels:[{...proof(o)[0],cancelAmount:o.amount/2},{...proof(o)[0],cancelAmount:o.amount/2}]}])await assert.rejects(finish(o,patch),/payment mismatch/);
 for(const action of ['bind','settle'])await assert.rejects(service(action==='bind'?'_payment_bind_v1($1,$2,$3,$4)':'_payment_settle_v1($1,$2,$3,$4,$5,$6,$7,$8)',[o.user_id,o.order_id,o.payment_key,o.amount,...(action==='settle'?['KRW','DONE',o.amount,new Date().toISOString()]:[])]),/payment refunded/);
 const refunded=await finish(o);assert.equal(refunded.state,'refunded');assert.deepEqual(await finish(o),refunded);assert.deepEqual(await wallet(o),{paid:0,free:0});
 assert.deepEqual(await v('select receipt v from payment_orders where order_id=$1',[o.order_id]),original);
 assert.deepEqual((await q('select status,cancel_status,cancel_amount,canceled_at is not null canceled from payment_orders where order_id=$1',[o.order_id]))[0],{status:'paid',cancel_status:'refunded',cancel_amount:o.amount,canceled:true});
 const spent=await fixture();await spend(spent,1);await assert.rejects(prepare(spent),/refund cs review/);
 await v("select _gem_add($1,0,1,'test','later-paid',null) v",[spent.user_id]);await assert.rejects(prepare(spent),/refund cs review/);
 const bonus=await fixture('gem_500');await spend(bonus,1);await assert.rejects(prepare(bonus),/refund cs review/);
 await v("select _gem_add($1,1,0,'test','later-free',null) v",[bonus.user_id]);await assert.rejects(prepare(bonus),/refund cs review/);
 const old=await fixture('gem_500',100,100);await spend(old,50);await prepare(old);assert.deepEqual(await wallet(old),{paid:100,free:50});
 const late=await fixture();await q("update payment_orders set paid_at=now()-interval '8 days' where order_id=$1",[late.order_id]);await assert.rejects(prepare(late),/refund cs review/);
 await q("update payment_orders set paid_at=now()-interval '8 days' where order_id=$1",[old.order_id]);assert.equal((await prepare(old)).refund.state,'held','existing hold remains recoverable after seven-day deadline');
 const atomic=await fixture('gem_500');await db.exec("create function test_refund_fail() returns trigger language plpgsql as $$begin raise exception 'forced refund failure';end$$;create trigger refund_fail before insert on payment_refunds for each row execute function test_refund_fail();");
 await assert.rejects(prepare(atomic),/forced refund failure/);assert.deepEqual(await wallet(atomic),{paid:500,free:25});assert.equal(await v('select count(*)::int v from gem_ledger where ref=$1',['toss-refund-hold:'+atomic.order_id]),0);await db.exec('drop trigger refund_fail on payment_refunds');
 const pending=await call('authenticated',user,'payment_create_v1($1,$2)',['gem_100',randomUUID()]);
 await assert.rejects(call('authenticated',admin,'payment_abandon_v1($1,$2)',[pending.order_id,'canceled']),/order not found/);
 assert.equal((await call('authenticated',user,'payment_abandon_v1($1,$2)',[pending.order_id,'canceled'])).state,'canceled');
 assert.equal((await call('authenticated',user,'payment_abandon_v1($1,$2)',[pending.order_id,'failed'])).state,'canceled');
 await assert.rejects(service('_payment_bind_v1($1,$2,$3,$4)',[user,pending.order_id,'opaque',pending.amount]),/payment closed/);
 const bound=await call('authenticated',user,'payment_create_v1($1,$2)',['gem_100',randomUUID()]);await service('_payment_bind_v1($1,$2,$3,$4)',[user,bound.order_id,'bound',bound.amount]);
 assert.equal((await call('authenticated',user,'payment_abandon_v1($1,$2)',[bound.order_id,'failed'])).state,'confirmation_required');
 const exp=await call('authenticated',user,'payment_create_v1($1,$2)',['gem_100',randomUUID()]);await q("update payment_orders set expires_at=now()-interval '1 minute' where order_id=$1",[exp.order_id]);
 const listed=await ac('admin_payment_orders_v1()');
 const expired=listed.orders.find(x=>x.order_id===exp.order_id);
 assert.equal(expired.checkout_status,'expired');assert.equal(expired.paid_at,null);assert.ok(expired.created_at);assert.equal(expired.buyer,'not-admin');
 assert(!JSON.stringify(listed).includes('payment_key'));assert(!JSON.stringify(listed).includes('email'));assert(!JSON.stringify(listed).includes('@'));
 await q("update profiles set nickname='심연구매' where id=$1",[user]);
 assert.equal((await ac('admin_payment_orders_v1()')).orders.find(x=>x.order_id===exp.order_id).buyer,'심연구매');
 await q("update profiles set nickname=' ' where id=$1",[user]);
 assert.equal((await ac('admin_payment_orders_v1()')).orders.find(x=>x.order_id===exp.order_id).buyer,user);
 await q('delete from profiles where id=$1',[user]);
 assert.equal((await ac('admin_payment_orders_v1()')).orders.find(x=>x.order_id===exp.order_id).buyer,user);
 const paidRow=(await ac('admin_payment_orders_v1()')).orders.find(x=>x.order_id===o.order_id);
 assert.equal(paidRow.status,'paid');assert.equal(paidRow.buyer,'플레이어');assert.ok(paidRow.paid_at);assert.notEqual(paidRow.paid_at,null);
 const saved=await wallet(o);await db.exec(migration);assert.deepEqual(await wallet(o),saved);assert.equal((await prepare(o)).refund.state,'refunded');
 await db.exec("select set_config('test.payment_db','7692130048193495360',false)");await assert.rejects(ac('admin_payment_orders_v1()'),/payments unavailable/);
 console.log('Refund SQL: staging/runtime guard, admin+confirmed identity, RLS/helper ACL, immutable receipt, full paid+bonus hold, FIFO spent/recharge rejection, old-balance allowance, 7-day/CS boundary, repeat install, atomic rollback, once-only reclaim, closed/bound callback safety and lazy expiry OK');
}finally{await db.close();}

const env={SUPABASE_URL:STAGING,SUPABASE_PUBLISHABLE_KEYS:'{"default":"sb_publishable_unit"}',SUPABASE_SECRET_KEYS:'{"default":"sb_secret_unit"}',TOSS_SECRET_KEY:'test_sk_unit',TOSS_CLIENT_KEY:'test_ck_unit'};
const order={order_id:'vrs_'+'a'.repeat(32),user_id:user,amount:1100,currency:'KRW',payment_key:'opaque',paid_gems:100,bonus_gems:0,status:'paid',cancel_status:'none'};
const payment={paymentKey:'opaque',orderId:order.order_id,totalAmount:1100,balanceAmount:1100,currency:'KRW',method:'카드',status:'DONE',cancels:[]};
const canceled={...payment,status:'CANCELED',balanceAmount:0,cancels:proof(order)};
const response=(x,status=200)=>new Response(JSON.stringify(x),{status,headers:{'content-type':'application/json'}});
const req=(op='refund',extra={},token='Bearer admin',origin='https://vr-tcg-staging.notcold.workers.dev')=>new Request('https://edge.test',{method:'POST',headers:{'content-type':'application/json',authorization:token,origin},body:JSON.stringify({op,...(op==='orders'?{}:{orderId:order.order_id}),...extra})});
function mock({allowed=true,mode='ok',variant,failPrepare=false,loseCommit=false}={}){
 const state={events:[],posts:0,holds:0,finishes:0,done:false,held:false,receipt:null};
 const fetcher=async(url,opt={})=>{
  state.events.push({url,opt});const b=opt.body?JSON.parse(opt.body):{};
  if(url.endsWith('/auth/v1/user'))return response({id:admin});
  if(url.endsWith('/admin_check'))return response({admin:allowed});
  if(url.endsWith('/payment_abandon_v1'))return response({ok:true,state:b.p_reason});
  if(url.endsWith('/admin_payment_orders_v1'))return response({ok:true,orders:[]});
  if(url.endsWith('/admin_payment_refund_prepare_v1')||url.endsWith('/admin_payment_refund_lookup_v1')){
   assert.equal(opt.headers.authorization,'Bearer admin');
   if(failPrepare)return response({code:'P0001',message:'refund cs review'},400);
   if(!state.held){state.holds++;state.held=true;}
   return response({order,refund:{state:state.receipt?'refunded':'held',idempotency_key:'vr-refund-'+order.order_id,created_at:new Date().toISOString(),receipt:state.receipt}});
  }
  if(url.endsWith('/_payment_refund_finish_v1')){
   if(loseCommit){loseCommit=false;return response({code:'XX000',message:'private DB failure'},500);}
   assert.equal(opt.headers.apikey,'sb_secret_unit');assert(!opt.headers.authorization);assert.equal(b.p_amount,1100);assert.deepEqual(Object.keys(b.p_cancels[0]).sort(),['cancelAmount','cancelStatus','canceledAt','transactionKey']);
   if(!state.receipt){state.finishes++;state.receipt={ok:true,state:'refunded',amount:1100};}return response(state.receipt);
  }
  if(url.endsWith('/_payment_refund_note_v1'))return response(null);
  if(url.endsWith('/opaque/cancel')){
   state.posts++;assert(state.held,'wallet hold must precede PG call');assert.equal(opt.headers['Idempotency-Key'],'vr-refund-'+order.order_id);assert.equal(opt.headers.authorization,'Basic '+btoa('test_sk_unit:'));
   assert.deepEqual(b,{cancelReason:'미사용 상품 청약철회',cancelAmount:1100,refundableAmount:1100,currency:'KRW'});
   if(mode==='fail')return response({code:'PRIVATE_PROVIDER_ERROR',message:'private do not leak'},500);
   state.done=true;if(mode==='lost')throw Error('private network');if(mode==='hang')return new Promise(()=>{});return response(canceled);
  }
  if(url.endsWith('/opaque'))return response(state.done?(variant||canceled):payment);
  throw Error('Unexpected mocked destination');
 };return {state,fetcher};
}
for(const change of [{paymentKey:'other'},{orderId:'other'},{currency:'USD'},{totalAmount:100},{balanceAmount:1},{status:'PARTIAL_CANCELED'},{method:'가상계좌'},{cancels:[]},{cancels:[{...proof(order)[0],cancelStatus:'PENDING'}]},{cancels:[{...proof(order)[0],cancelAmount:1}]},{cancels:[{...proof(order)[0],canceledAt:'not-a-date'}]}])assert.equal(validCancellation({...canceled,...change},order),false);
assert(validCancellation(canceled,order));
for(const mode of ['ok','lost','hang']){
 const m=mock({mode}),h=createHandler(env,m.fetcher,mode==='hang'?180:9000),r=await h(req());assert.equal(r.status,200);assert.equal((await r.json()).state,'refunded');assert.equal(m.state.posts,1);assert.equal(m.state.holds,1);assert.equal(m.state.finishes,1);
 assert.equal((await h(req())).status,200);assert.equal(m.state.posts,1);assert.equal(m.state.finishes,1);
}
const lostDb=mock({loseCommit:true}),recoverDb=createHandler(env,lostDb.fetcher);assert.equal((await recoverDb(req())).status,409);assert(lostDb.state.done);assert.equal(lostDb.state.finishes,0);assert.equal((await recoverDb(req())).status,200);assert.equal(lostDb.state.posts,1);assert.equal(lostDb.state.holds,1);assert.equal(lostDb.state.finishes,1);
const denied=mock({allowed:false});assert.equal((await createHandler(env,denied.fetcher)(req())).status,403);assert.equal(denied.state.holds,0);assert.equal(denied.state.posts,0);
const spent=mock({failPrepare:true});const blocked=await createHandler(env,spent.fetcher)(req());assert.equal(blocked.status,409);assert.equal((await blocked.json()).error,'refund cs review');assert.equal(spent.state.posts,0);
const failing=mock({mode:'fail'});const pending=await createHandler(env,failing.fetcher)(req());assert.equal(pending.status,409);assert.deepEqual(await pending.json(),{error:'refund pending'});assert(failing.state.held);assert.equal(failing.state.finishes,0);
const mismatch=mock({variant:{...canceled,currency:'USD'}});assert.equal((await createHandler(env,mismatch.fetcher)(req())).status,409);assert.equal(mismatch.state.finishes,0);
const readOnly=mock();assert.equal((await createHandler(env,readOnly.fetcher)(req('refund-status'))).status,200);assert.equal(readOnly.state.posts,0);
const repeated=mock(),parallel=createHandler(env,repeated.fetcher);assert((await Promise.all([parallel(req()),parallel(req())])).every(r=>r.status===200));assert.equal(repeated.state.finishes,1);assert.equal(repeated.state.holds,1);
const list=mock();assert.equal((await createHandler(env,list.fetcher)(req('orders'))).status,200);assert.equal(list.state.posts,0);assert.equal(list.state.holds,0);
const abandon=mock();assert.equal((await createHandler(env,abandon.fetcher)(req('abandon',{reason:'failed'}))).status,200);assert(!abandon.state.events.some(e=>e.url.endsWith('/admin_check')));
const guarded=mock(),h=createHandler(env,guarded.fetcher);for(const extra of [{amount:1},{paymentKey:'foreign'},{userId:admin}])assert.equal((await h(req('refund',extra))).status,400);assert.equal(guarded.state.events.length,0);
assert.equal((await h(req('refund',{},'Bearer admin','https://ag.violenceroyale.com'))).status,403);
assert.equal((await createHandler({...env,SUPABASE_URL:'https://htarwisgkkphutxxnuak.supabase.co'},guarded.fetcher)(req())).status,503);
assert.equal((await createHandler({...env,TOSS_SECRET_KEY:'live_sk_never'},guarded.fetcher)(req())).status,503);
const authed={auth:{getSession:async()=>({data:{session:{access_token:'unit'}}})}},config={isStaging:true,supabaseUrl:STAGING,anonKey:'public'};
for(const error of ['forbidden','refund cs review','refund not eligible','refund pending','payment refunded','payment closed']){
 await assert.rejects(api(authed,config,{op:'refund',orderId:order.order_id},async()=>response({error},409)),e=>e.message===error);assert(!paymentError(error).includes('지연'));
}
await assert.rejects(api(authed,config,{op:'refund',orderId:order.order_id},()=>new Promise(()=>{}),10),/refund pending/);
assert((await read('tools/build_staging.mjs')).includes("'admin-payments.html'"));assert(!(await read('tools/build_production_assets.mjs')).includes("'admin-payments.html'"));
console.log('Refund Edge/client: exact body, verified admin, server-only amount/key, held-before-PG, stable idempotency/concurrent duplicate, re-fetch after timeout/lost response, exact cancel proof, sanitized audit, no release on uncertainty, retry without double debit/refund, status-only read, no player self-refund, prod/live-key rejection OK');

// The actual administrator page: no side effect before explicit click/confirmation,
// no HTML injection, forbidden/prod fail closed, successful refund rerenders as final.
const adminHtml=await read('admin-payments.html');
const adminCode=(await read('js/payments-admin.js')).replace(/^import .*;$/gm,'').replace("await import('https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.45.4/+esm')",'await getSDK()').replace('init();','window.__init=init;');
async function adminPage({forbidden=false,production=false,orders}={}){
 const {document}=parseHTML(adminHtml),calls=[];let confirm=false,refunded=false;
 const window={confirm:()=>confirm};
 vm.runInNewContext(adminCode,{window,document,config:{...config,enabled:true},enabled:()=>!production,paymentError,
  api:async(sb,c,b)=>{calls.push(b);if(forbidden)throw Error('forbidden');if(b.op==='refund'){refunded=true;return {ok:true,state:'refunded'};}return {ok:true,orders:orders||[{...order,order_name:'<img src=x onerror=bad>',checkout_status:'open',cancel_status:refunded?'refunded':'none',cancel_amount:refunded?1100:0}]};},
  getSDK:async()=>({createClient:()=>({auth:{initialize:async()=>{}}})})});
 await window.__init();return {document,calls,approve:()=>{confirm=true;}};
}
const page=await adminPage();assert.equal(page.calls.length,1);assert.equal(page.document.querySelector('tbody img'),null);let button=page.document.querySelector('tbody button');assert.equal(button.textContent,'전액 환불');await button.onclick();assert.equal(page.calls.length,1);page.approve();await button.onclick();assert.deepEqual(JSON.parse(JSON.stringify(page.calls[1])),{op:'refund',orderId:order.order_id});assert.equal(page.document.querySelector('tbody button'),null);assert.match(page.document.getElementById('pay-message').textContent,/환불 완료/);
const noAdmin=await adminPage({forbidden:true});assert.match(noAdmin.document.getElementById('pay-message').textContent,/관리자/);assert.equal(noAdmin.document.querySelectorAll('tbody button').length,0);
const prod=await adminPage({production:true});assert.equal(prod.calls.length,0);assert.equal(prod.document.getElementById('pay-load').disabled,true);
const paidAt='2026-11-08T14:05:06.000Z',createdAt='2026-11-08T13:00:00.000Z',pendingId='vrs_'+'b'.repeat(32),fallbackId='22222222-2222-4222-8222-222222222222';
const identity=await adminPage({orders:[
 {order_id:order.order_id,order_name:'paid',amount:1100,paid_gems:100,bonus_gems:0,status:'paid',checkout_status:'open',cancel_status:'none',cancel_amount:0,buyer:'심연구매',user_id:user,paid_at:paidAt,created_at:createdAt,payment_key:'opaque',email:'hidden@example.test'},
 {order_id:pendingId,order_name:'wait',amount:1100,paid_gems:100,bonus_gems:0,status:'pending',checkout_status:'open',cancel_status:'none',cancel_amount:0,buyer:'   ',user_id:fallbackId,paid_at:null,created_at:createdAt,email:'hidden@example.test'}
]});
assert.match(identity.document.querySelector('thead').textContent,/구매자/);assert.match(identity.document.querySelector('thead').textContent,/결제 시각 \(한국시간\)/);
const identityRows=[...identity.document.querySelectorAll('tbody tr')];assert.equal(identityRows.length,2);
assert.match(identityRows[0].textContent,/심연구매/);assert.match(identityRows[0].textContent,/2026-11-08 23:05:06/);assert.doesNotMatch(identityRows[0].textContent,/미결제/);assert.doesNotMatch(identityRows[0].textContent,/2026-11-08 22:00:00/);
assert.match(identityRows[1].textContent,/미결제 · 생성 2026-11-08 22:00:00/);assert.match(identityRows[1].textContent,new RegExp(fallbackId));assert.doesNotMatch(identityRows[1].textContent,/23:05:06/);
assert.equal(identity.document.querySelectorAll('tbody button').length,1);assert.doesNotMatch(identity.document.body.textContent,/hidden@example\.test|opaque/);
console.log('Admin refund DOM: explicit confirm only, no self-refund on page load, safe text rendering, terminal status, forbidden/prod gates, buyer nickname/id and Seoul paid-vs-created time OK');
