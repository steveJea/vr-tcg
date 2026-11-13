// UR 확정권 + 전체 우편 '기존 가입자만' (2026-11-11 형님 결정).
// One reviewed source (tools/ur_ticket/core.sql) → staging DO block + production follow-up 20261111b.
// Never part of staging_install / release 20261111. `--check` fails if generated files are stale.
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {createHash} from 'node:crypto';
const root=new URL('../',import.meta.url), rd=p=>readFile(new URL(p,root),'utf8');
const STAGING_ID='7703759698107299042', PROD_ID='7692130048193495360', RELEASE='20261111b';
// md5(prosrc) of the functions this replaces, as shipped in supabase/mail_v2.sql (same on main 12c5e00 and staging)
export const BASELINE={
 '_mail_clean_payload(jsonb)':'@clean','_mail_sync(uuid)':'@sync','mail_msg_claim(bigint)':'@claim',
 'admin_mail_broadcast(text,text,jsonb,integer)':'@bcast','admin_mail_broadcasts(integer)':'@blist'};
export async function parts(){
 const src=await rd('tools/ur_ticket/core.sql');
 return src.split(/^-- @@ /m).filter(s=>s.trim()).map(s=>{const i=s.indexOf('\n');return {title:s.slice(0,i).trim(),sql:s.slice(i+1).trim()};});
}
const tag=i=>`$ur${i}$`;
const execs=ps=>ps.map((p,i)=>`  -- ${p.title}\n  execute ${tag(i)}\n${p.sql}\n${tag(i)};`).join('\n');
const CHECKS=`  if public._mail_clean_payload('{"ur_tickets":1,"gem":200,"cur":{"gold":50000,"blood":50000}}') <> '{"ur_tickets":1,"gem":200,"cur":{"gold":50000,"blood":50000}}'::jsonb then raise exception 'STOP: 첨부 검증 확인 실패'; end if;
  if (select count(*) from public.story_premium_ur w join public.story_card_pool p on p.id=w.id and p.grade='ULTRA RARE') < 1 then raise exception 'STOP: 고급 소환 UR 목록(story_premium_ur)이 비어 있음'; end if;
  if (select count(*) from pg_proc where pronamespace='public'::regnamespace and proname='admin_mail_broadcast') <> 1 then raise exception 'STOP: admin_mail_broadcast 가 1개여야 함'; end if;
  if has_function_privilege('anon','public.story_ur_ticket_draw()','execute') or not has_function_privilege('authenticated','public.story_ur_ticket_draw()','execute') then raise exception 'STOP: 권한 확인 실패'; end if;`;
export async function build(md5s){
 const ps=await parts(), body=execs(ps), hash=createHash('sha256').update(JSON.stringify(ps)).digest('hex');
 const staging=`-- 스테이징 전용: UR 확정권(우편 첨부·사용) + 전체 우편 '기존 가입자만' (tools/build_ur_ticket_mail.mjs 로 생성, 직접 고치지 말 것)
-- 스테이징 SQL Editor 에 이 파일 전체를 붙여넣고 한 번 실행. 다시 실행해도 안전. 유저 데이터는 바꾸지 않음 (컬럼 추가 + 함수 교체).
-- 운영 금지: system_identifier ${STAGING_ID} 가 아니면 멈춤.
do $ur_ticket_staging$
begin
  if (select system_identifier::text from pg_control_system()) <> '${STAGING_ID}' then raise exception 'STOP: staging only'; end if;
  if to_regclass('public.mail_broadcast') is null or to_regclass('public.story_premium_ur') is null or to_regclass('public.story_gacha') is null then raise exception 'STOP: mail_v2.sql / gacha_premium_ur.sql 가 먼저 있어야 함'; end if;
${body}
${CHECKS}
  raise notice 'UR 확정권 + 기존 가입자만 우편 설치 완료 (스테이징)';
end $ur_ticket_staging$;
-- 확인: select public._mail_clean_payload('{"ur_tickets":1}'), (select count(*) from public.story_premium_ur) as ur_pool;
`;
 const drift=Object.keys(BASELINE).map(s=>` ('${s}','${md5s[s]}')`).join(',\n');
 const driftQ=`with expected(sig,src) as (values\n${drift}\n)\nselect count(*) filter (where e.src is not distinct from md5(p.prosrc)) as baseline_match, count(*) filter (where e.src is distinct from md5(p.prosrc)) as differs_must_be_0, string_agg(case when e.src is distinct from md5(p.prosrc) then e.sig end, ', ') as differs_list\nfrom expected e left join pg_proc p on to_regprocedure(e.sig)=p.oid;`;
 const pre=`-- 운영 후속 ${RELEASE} 읽기 전용 사전 점검. 운영 SQL Editor 에서 실행. 아무것도 바꾸지 않음.
-- 1) ${PROD_ID} 이어야 함. 아니면 멈춤.
select system_identifier::text as production_system_identifier, system_identifier::text='${PROD_ID}' as pinned_ok from pg_control_system();
-- 2) 배포 기록: 20261111 이 있어야 하고, ${RELEASE} 는 아직 없어야 함.
select release_id, completed_at from vr_rollout_private.releases order by completed_at;
-- 3) 이번에 바꾸는 함수가 mail_v2.sql 원본과 같은지. differs_must_be_0 이 0 이 아니면 누가 운영에서 직접 고친 것 → 실행 전에 목록을 보내 주세요.
${driftQ}
-- 4) UR 확정권 풀: 고급 소환 UR 11명이어야 함 (전부 ULTRA RARE).
select w.id, w.name, p.grade, p.grade='ULTRA RARE' as ur_ok from public.story_premium_ur w left join public.story_card_pool p on p.id=w.id order by w.id;
select count(*) as ur_pool_must_be_11 from public.story_premium_ur w join public.story_card_pool p on p.id=w.id and p.grade='ULTRA RARE';
-- 5) 아직 설치 전인지 (둘 다 false 가 정상. true 면 이미 설치됨)
select exists(select 1 from information_schema.columns where table_schema='public' and table_name='story_gacha' and column_name='ur_tickets') as ur_tickets_column, exists(select 1 from information_schema.columns where table_schema='public' and table_name='mail_broadcast' and column_name='existing_only') as existing_only_column;
select exists(select 1 from information_schema.columns where table_schema='public' and table_name='story_gacha_log' and column_name='kind') as gacha_log_kind_ok;
-- 6) 최근 전체 우편 (오늘 밤 재화 우편 확인용)
select id, title, payload, created_at, expires_at from public.mail_broadcast order by id desc limit 5;
`;
 const install=`-- 운영 후속 ${RELEASE}: UR 확정권(우편 첨부·사용) + 전체 우편 '기존 가입자만'. tools/build_ur_ticket_mail.mjs 로 생성.
-- 대상: htarwisgkkphutxxnuak (system_identifier ${PROD_ID}). 20261111 다음에만. 한 트랜잭션 + 배포 기록: 재실행은 아무것도 안 함.
-- 유저 데이터는 바꾸지 않음 (컬럼 추가 + 함수 교체). 엔진 해시·전투 정책 무관.
begin;
do $production_guard$
declare actual text;
begin
  select system_identifier::text into actual from pg_catalog.pg_control_system();
  if actual is distinct from '${PROD_ID}' or actual='${STAGING_ID}' then raise exception 'STOP: production system_identifier mismatch; staging/unknown DB refused'; end if;
end $production_guard$;
set local lock_timeout='5s';
set local statement_timeout='60s';
select pg_advisory_xact_lock(hashtext('vr:production:${RELEASE}'));
do $production_install$
declare h text; f record;
begin
  if to_regclass('vr_rollout_private.releases') is null or not exists(select 1 from vr_rollout_private.releases where release_id='20261111') then raise exception 'STOP: release 20261111 is not installed; refusing ${RELEASE}'; end if;
  select bundle_hash into h from vr_rollout_private.releases where release_id='${RELEASE}';
  if found then
    if h is distinct from '${hash}' then raise exception 'STOP: ${RELEASE} content changed after installation'; end if;
    raise notice '${RELEASE} already installed: no changes'; return;
  end if;
  for f in select * from (values
${Object.keys(BASELINE).map(s=>`    ('${s}','${md5s[s]}')`).join(',\n')}
  ) e(sig,src) loop
    if to_regprocedure(f.sig) is null or (select md5(prosrc) from pg_proc where oid=to_regprocedure(f.sig)) is distinct from f.src then raise exception 'STOP: % differs from mail_v2.sql baseline (hand-edited in production?)', f.sig; end if;
  end loop;
  if (select count(*) from public.story_premium_ur w join public.story_card_pool p on p.id=w.id and p.grade='ULTRA RARE') <> 11 then raise exception 'STOP: 고급 소환 UR 목록이 11명이 아님'; end if;
${body}
${CHECKS}
  insert into vr_rollout_private.releases(release_id,bundle_hash,db_id) values('${RELEASE}','${hash}',(select system_identifier::text from pg_catalog.pg_control_system()));
  raise notice 'Production ${RELEASE} installed';
end $production_install$;
commit;
`;
 const post=`-- 운영 후속 ${RELEASE} 설치 후 읽기 전용 확인. 모두 true 여야 함.
select exists(select 1 from vr_rollout_private.releases where release_id='${RELEASE}' and bundle_hash='${hash}') as ledger_ok,
 exists(select 1 from information_schema.columns where table_schema='public' and table_name='story_gacha' and column_name='ur_tickets') as ur_tickets_column_ok,
 exists(select 1 from information_schema.columns where table_schema='public' and table_name='mail_broadcast' and column_name='existing_only') as existing_only_ok,
 public._mail_clean_payload('{"ur_tickets":1}') = '{"ur_tickets":1}'::jsonb as payload_ok,
 to_regprocedure('public.story_ur_ticket_draw()') is not null and to_regprocedure('public.story_ur_tickets()') is not null as rpc_ok,
 not has_function_privilege('anon','public.story_ur_ticket_draw()','execute') as anon_blocked_ok,
 (select count(*) from pg_proc where pronamespace='public'::regnamespace and proname='admin_mail_broadcast')=1 as one_broadcast_fn_ok,
 (select count(*) from public.story_premium_ur w join public.story_card_pool p on p.id=w.id and p.grade='ULTRA RARE')=11 as ur_pool_11_ok;
`;
 const mark=`-- (선택) 오늘 밤 보낸 재화 전체 우편(심연석 200 · 골드 50,000 · 피 50,000)을 '기존 가입자만'으로 바꾸기. ${RELEASE} 설치 뒤 운영에서 한 번.
-- 보낸 뒤 가입한 계정이 아직 받지 않은(미수령) 사본은 지움. 이미 받은 사본은 되돌리지 않고 개수만 보여 줌. 다시 실행해도 안전.
do $mark_currency_mail$
declare n int; bid bigint; removed int; kept int;
begin
  if (select system_identifier::text from pg_control_system()) is distinct from '${PROD_ID}' then raise exception 'STOP: production only'; end if;
  if not exists(select 1 from vr_rollout_private.releases where release_id='${RELEASE}') then raise exception 'STOP: ${RELEASE} 먼저 설치'; end if;
  select count(*), min(id) into n, bid from public.mail_broadcast
   where created_at >= timestamptz '2026-11-11 22:30+09' and created_at < timestamptz '2026-11-13 00:00+09'
     and payload = '{"gem":200,"cur":{"gold":50000,"blood":50000}}'::jsonb;
  if n <> 1 then raise exception 'STOP: 재화 우편이 정확히 1개여야 함 (찾은 수 %)', n; end if;
  update public.mail_broadcast set existing_only = true where id = bid;
  delete from public.player_mail m using auth.users u, public.mail_broadcast b
   where m.broadcast_id = bid and b.id = bid and u.id = m.user_id and u.created_at > b.created_at and m.claimed_at is null;
  get diagnostics removed = row_count;
  select count(*) into kept from public.player_mail m join auth.users u on u.id = m.user_id join public.mail_broadcast b on b.id = m.broadcast_id
   where m.broadcast_id = bid and u.created_at > b.created_at and m.claimed_at is not null;
  raise notice '재화 우편 % : 기존 가입자만으로 변경. 보낸 뒤 가입자 미수령 사본 % 개 삭제, 이미 받은 % 개는 그대로', bid, removed, kept;
end $mark_currency_mail$;
`;
 const manifest=`release ${RELEASE} (follow-up after 20261111)\nbundle_hash ${hash}\nsource tools/ur_ticket/core.sql\nstatements:\n${ps.map((p,i)=>`  ${i+1}. ${p.title}`).join('\n')}\nreplaces (md5(prosrc) pinned):\n${Object.keys(BASELINE).map(s=>`  ${s} ${md5s[s]}`).join('\n')}\nfiles: 00_preflight_readonly.sql, 01_install.sql, 02_postflight_readonly.sql, 03_mark_currency_mail_existing_only.sql (optional)\n`;
 return {'supabase/ur_ticket_mail_staging.sql':staging,[`supabase/production/${RELEASE}/00_preflight_readonly.sql`]:pre,[`supabase/production/${RELEASE}/01_install.sql`]:install,[`supabase/production/${RELEASE}/02_postflight_readonly.sql`]:post,[`supabase/production/${RELEASE}/03_mark_currency_mail_existing_only.sql`]:mark,[`supabase/production/${RELEASE}/MANIFEST.txt`]:manifest};
}
// md5(prosrc) of the baseline functions straight from supabase/mail_v2.sql (prosrc = text between $$ … $$)
export async function baselineMd5(){
 const src=await rd('supabase/mail_v2.sql'), out={};
 const pick=(name)=>{const re=new RegExp(`create or replace function public\\.${name}\\([^]*?as \\$\\$([^]*?)\\$\\$`,'i');const m=src.match(re);if(!m)throw new Error('baseline missing '+name);return createHash('md5').update(m[1]).digest('hex');};
 out['_mail_clean_payload(jsonb)']=pick('_mail_clean_payload');out['_mail_sync(uuid)']=pick('_mail_sync');out['mail_msg_claim(bigint)']=pick('mail_msg_claim');
 out['admin_mail_broadcast(text,text,jsonb,integer)']=pick('admin_mail_broadcast');out['admin_mail_broadcasts(integer)']=pick('admin_mail_broadcasts');
 return out;
}
if(import.meta.url===`file://${process.argv[1]}`){
 const files=await build(await baselineMd5()), check=process.argv.includes('--check');let stale=[];
 for(const [p,t] of Object.entries(files)){
  if(check){const cur=await rd(p).catch(()=>null);if(cur!==t)stale.push(p);}
  else{await mkdir(new URL(p.replace(/[^/]+$/,''),root),{recursive:true});await writeFile(new URL(p,root),t);}
 }
 if(stale.length){console.error('stale:',stale.join(', '),'→ node tools/build_ur_ticket_mail.mjs');process.exit(1);}
 console.log(`UR 확정권 ${RELEASE}: staging DO block + production preflight/install/postflight/mark ${check?'up to date':'written'}`);
}
