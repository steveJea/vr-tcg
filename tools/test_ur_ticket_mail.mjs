// Offline DB test (PGlite, full staging stack): UR 확정권 우편/사용 + 전체 우편 '기존 가입자만' + 운영 후속 20261111b.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
import {buildSql,INSTALL_ACK} from './build_staging_sql.mjs';
import {build,baselineMd5} from './build_ur_ticket_mail.mjs';
const rd=p=>readFile(new URL('../'+p,import.meta.url),'utf8');
const POOL11=['10051','10053','10054','10058','10176','10312','10323','10324','10325','10331','10358'];
const old='11111111-1111-4111-8111-111111111111', newbie='22222222-2222-4222-8222-222222222222', other='33333333-3333-4333-8333-333333333333';
async function fresh(){
 const db=new PGlite();
 await db.exec(`create role anon;create role authenticated;create role service_role;create schema auth;
 create table auth.users(id uuid primary key,email text,raw_user_meta_data jsonb default '{}',raw_app_meta_data jsonb default '{}',created_at timestamptz default now(),last_sign_in_at timestamptz,email_confirmed_at timestamptz);
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
 grant usage on schema auth,public to anon,authenticated,service_role;
 alter default privileges in schema public grant all on tables to anon,authenticated;
 alter default privileges in schema public grant all on sequences to anon,authenticated;
 alter default privileges in schema public grant execute on functions to anon,authenticated,service_role;`);
 await db.exec((await buildSql()).replace(`confirmed_ref text := '${INSTALL_ACK}'`,"confirmed_ref text := 'abcdefghijklmnopqrst'"));
 const q=async(s,p=[])=>(await db.query(s,p)).rows, val=async(s,p=[])=>(await q(s,p))[0]?.v;
 const as=async(uid,fn,role='authenticated')=>{await q("select set_config('request.jwt.claim.sub',$1,false), set_config('request.jwt.claims',$2,false)",[uid||'','{"email":"admin@x.invalid"}']);await db.exec('set role '+role);try{return await fn();}finally{await db.exec('reset role');}};
 const rpc=(uid,s,p=[])=>as(uid,()=>val(s,p));
 const id=await val('select system_identifier::text v from pg_control_system()');
 return {db,q,val,as,rpc,id};
}
const md5s=await baselineMd5(), files=await build(md5s);
for(const [p,t] of Object.entries(files)) assert.equal(await rd(p),t,p+' is stale: node tools/build_ur_ticket_mail.mjs');

// ---------- staging ----------
{
 const {db,q,val,as,rpc,id}=await fresh();
 // baseline pins == the staging stack's real md5(prosrc)
 for(const [sig,m] of Object.entries(md5s)) assert.equal(await val('select md5(prosrc) v from pg_proc where oid=to_regprocedure($1)',[sig]),m,sig);
 assert.deepEqual((await q('select w.id from story_premium_ur w join story_card_pool p on p.id=w.id and p.grade=$1 order by 1',['ULTRA RARE'])).map(r=>r.id),POOL11);
 const st=files['supabase/ur_ticket_mail_staging.sql'];
 await assert.rejects(db.exec(st),/STOP: staging only/);
 const ok=st.replaceAll("'7703759698107299042'",`'${id}'`);
 await db.exec(ok); await db.exec(ok);   // rerun safe
 await q("create or replace function public._is_admin() returns boolean language sql as 'select true'");   // test-only admin
 await q("insert into auth.users(id,email,created_at) values($1,'old@x.invalid',now()-interval '30 days'),($2,'other@x.invalid',now()-interval '30 days')",[old,other]);
 await q('insert into story_progress(user_id,data) values($1,$3),($2,$3)',[old,other,'{"owned":[]}']);
 await q('insert into player_wallet(user_id,gold,blood) values($1,10,20)',[old]);
 // 관리자 전체 우편: 4개 인자(예전 화면)도 그대로 호출됨
 const cur=await rpc(old,"select admin_mail_broadcast(p_title=>'업데이트 기념 재화',p_body=>'감사합니다',p_payload=>'{\"gem\":200,\"cur\":{\"gold\":50000,\"blood\":50000}}',p_days=>7) v");
 assert.equal(cur.existing_only,false);
 const urm=await rpc(old,"select admin_mail_broadcast('UR 확정권 선물','기존 가입자 전원','{\"ur_tickets\":1}',7,true) v");
 assert.equal(urm.existing_only,true);
 await assert.rejects(rpc(old,"select admin_mail_broadcast('x','','{\"ur_tickets\":11}',7,true) v"),/ur_tickets must be 0..10/);
 // 보낸 뒤 가입자
 await q("insert into auth.users(id,email,created_at) values($1,'new@x.invalid',now()+interval '1 second')",[newbie]);
 await q('insert into story_progress(user_id,data) values($1,$2)',[newbie,'{"owned":[]}']);
 const titles=async u=>(await rpc(u,'select mail_list() v')).map(m=>m.title).sort();
 assert.deepEqual(await titles(old),['UR 확정권 선물','업데이트 기념 재화']);
 assert.deepEqual(await titles(newbie),['업데이트 기념 재화'],'later signup: only the non-existing_only mail');
 assert.equal(await rpc(newbie,'select (story_ur_tickets()->>$1)::int v',['ur_tickets']),0);
 // 받기
 const list=await rpc(old,'select mail_list() v');
 for(const m of list){ const r=await rpc(old,'select mail_msg_claim($1) v',[m.id]); assert.equal(r.ok,true); }
 assert.equal((await rpc(old,'select mail_msg_claim($1) v',[list[0].id])).ok,false,'claim once');
 const w=(await q('select gold,blood,gem_free,gem_paid from player_wallet where user_id=$1',[old]))[0];
 assert.deepEqual([Number(w.gold),Number(w.blood),Number(w.gem_free),Number(w.gem_paid)],[50010,50020,200,0]);
 assert.equal(await rpc(old,'select (story_ur_tickets()->>$1)::int v',['ur_tickets']),1);
 // 사용
 await assert.rejects(as(old,()=>q('select story_ur_ticket_draw()'),'anon'),/permission denied/);
 const r=await rpc(old,'select story_ur_ticket_draw() v');
 assert.equal(r.ok,true); assert.equal(r.ur_tickets,0); assert.equal(r.cards.length,1); assert(POOL11.includes(r.cards[0].card_id)); assert.equal(r.cards[0].grade,'ULTRA RARE');
 const cid=r.cards[0].card_id;
 assert.equal(await val("select count(*)::int v from story_progress, jsonb_array_elements(data->'owned') o where user_id=$1 and o->>'id'=$2",[old,cid]),1,'owned');
 assert.equal(await val('select count(*)::int v from gallery where user_id=$1 and card_id=$2',[old,cid]),1,'gallery');
 assert.equal(await val("select count(*)::int v from verified_game_events where user_id=$1 and card_id=$2 and event_kind='card_acquired'",[old,cid]),1,'verified acquisition');
 assert.equal(await val("select kind v from story_gacha_log where user_id=$1 order by id desc limit 1",[old]),'ur_ticket');
 assert.deepEqual(await rpc(old,'select story_ur_ticket_draw() v'),{ok:false,reason:'ur_tickets',ur_tickets:0});
 // 무작위·중복 허용: 60장 모두 11명 안, 2명 이상 나옴
 await q('update story_gacha set ur_tickets=60 where user_id=$1',[old]);
 const seen=new Set(); for(let i=0;i<60;i++){ const x=await rpc(old,'select story_ur_ticket_draw() v'); assert(POOL11.includes(x.cards[0].card_id)); seen.add(x.cards[0].card_id); }
 assert(seen.size>=3,'random spread'); assert.equal(await rpc(old,'select (story_ur_tickets()->>$1)::int v',['ur_tickets']),0);
 assert.equal(await val("select count(*)::int v from story_progress, jsonb_array_elements(data->'owned') o where user_id=$1",[old]),61,'duplicates kept');
 assert.equal(await val("select count(*)::int v from pg_proc where proname='admin_mail_broadcast'"),1);
 await db.close();
}
// ---------- production follow-up 20261111b (on a fresh stack posing as production after 20261111) ----------
{
 const {db,q,val,rpc,id}=await fresh();
 const sub=s=>s.replaceAll("'7692130048193495360'",`'${id}'`);
 await q('create schema vr_rollout_private');
 await q('create table vr_rollout_private.releases(release_id text primary key,bundle_hash text not null,db_id text not null,completed_at timestamptz not null default now())');
 const inst=sub(files['supabase/production/20261111b/01_install.sql']);
 await assert.rejects(db.exec(inst),/STOP: release 20261111 is not installed/); await db.exec('rollback');
 await q("insert into vr_rollout_private.releases(release_id,bundle_hash,db_id) values('20261111','x',$1)",[id]);
 await assert.rejects(db.exec(files['supabase/production/20261111b/01_install.sql']),/STOP: production system_identifier mismatch/); await db.exec('rollback');
 await db.exec(sub(files['supabase/production/20261111b/00_preflight_readonly.sql']));   // read-only, runs clean
 const drift=(await q(sub(files['supabase/production/20261111b/00_preflight_readonly.sql']).split('-- 3)')[1].split('-- 4)')[0].replace(/^[^\n]*\n/,'')))[0];
 assert.equal(Number(drift.differs_must_be_0),0);
 // tonight's currency mail goes out BEFORE 20261111b with the old 4-arg function
 await q("create or replace function public._is_admin() returns boolean language sql as 'select true'");
 await q("insert into auth.users(id,email,created_at) values($1,'old@x.invalid',now()-interval '30 days')",[old]);
 const b=await rpc(old,"select admin_mail_broadcast('업데이트 기념 재화','','{\"gem\":200,\"cur\":{\"gold\":50000,\"blood\":50000}}',7) v");
 await q("update mail_broadcast set created_at=timestamptz '2026-11-11 23:30+09' where id=$1",[b.broadcast_id]);
 await q("insert into auth.users(id,email,created_at) values($1,'new@x.invalid',timestamptz '2026-11-12 01:00+09'),($2,'new2@x.invalid',timestamptz '2026-11-12 02:00+09')",[newbie,other]);
 const pre=await rpc(newbie,'select mail_list() v'); assert.equal(pre.length,1,'without 20261111b a later signup still gets the currency mail');
 await rpc(other,'select mail_list() v'); const om=(await rpc(other,'select mail_list() v'))[0]; await rpc(other,'select mail_msg_claim($1) v',[om.id]);
 // 03 before install refuses
 await assert.rejects(db.exec(sub(files['supabase/production/20261111b/03_mark_currency_mail_existing_only.sql'])),/먼저 설치/);
 await db.exec(inst); await db.exec(inst);   // rerun = no-op
 const post=(await q(sub(files['supabase/production/20261111b/02_postflight_readonly.sql'])))[0];
 for(const [k,v] of Object.entries(post)) assert.equal(v,true,k);
 // content change after install is refused
 await q("update vr_rollout_private.releases set bundle_hash='changed' where release_id='20261111b'");
 await assert.rejects(db.exec(inst),/content changed after installation/); await db.exec('rollback');
 await q("update vr_rollout_private.releases set bundle_hash=$1 where release_id='20261111b'",[(await rd('supabase/production/20261111b/MANIFEST.txt')).match(/bundle_hash ([0-9a-f]{64})/)[1]]);
 await db.exec(sub(files['supabase/production/20261111b/03_mark_currency_mail_existing_only.sql']));
 assert.equal(await val('select existing_only v from mail_broadcast where id=$1',[b.broadcast_id]),true);
 assert.equal(await val('select count(*)::int v from player_mail where user_id=$1 and broadcast_id=$2',[newbie,b.broadcast_id]),0,'unclaimed later-signup copy removed');
 assert.equal(await val('select count(*)::int v from player_mail where user_id=$1 and broadcast_id=$2 and claimed_at is not null',[other,b.broadcast_id]),1,'already-claimed copy kept');
 assert.equal((await rpc(newbie,'select mail_list() v')).length,0,'later signup no longer receives it');
 assert.equal((await rpc(old,'select mail_list() v')).length,1,'existing user still receives it');
 await db.exec(sub(files['supabase/production/20261111b/03_mark_currency_mail_existing_only.sql']));   // rerun safe
 await db.close();
}
console.log('UR 확정권: 우편 첨부·1회 수령·11명 풀 무작위(중복 허용)·소유/갤러리/획득 기록·기존 가입자만·운영 20261111b(사전점검/설치 재실행/사후점검/재화 우편 표시) OK');
