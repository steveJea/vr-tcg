// supabase/admin.sql 검증 (PGlite 로 실제 Postgres 실행). 실행: NODE_PATH=<pglite 설치 경로> node tools/test_admin_sql.mjs
// 관리자/비관리자/미인증 이메일/비로그인 각각에서 RPC 가 거부·허용되는지 확인
import { readFileSync } from 'fs';
import { createRequire } from 'module';
const require = createRequire(import.meta.url);
let PGlite;
try { ({ PGlite } = require('@electric-sql/pglite')); } catch { console.log('SKIP: @electric-sql/pglite 없음 (npm i @electric-sql/pglite 후 NODE_PATH 지정)'); process.exit(0); }
const db = new PGlite();
const ADMIN = '00000000-0000-0000-0000-000000000001', USER = '00000000-0000-0000-0000-000000000002', FAKE = '00000000-0000-0000-0000-000000000003';
await db.exec(`
create role anon nologin; create role authenticated nologin;
create schema auth;
create table auth.users (id uuid primary key, email text, email_confirmed_at timestamptz, created_at timestamptz default now(), last_sign_in_at timestamptz, raw_user_meta_data jsonb default '{}', raw_app_meta_data jsonb default '{}');
create function auth.jwt() returns jsonb language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $$;
create function auth.uid() returns uuid language sql stable as $$ select nullif(auth.jwt()->>'sub', '')::uuid $$;
grant usage on schema auth to anon, authenticated; grant execute on all functions in schema auth to anon, authenticated;
create table public.profiles (id uuid primary key, nickname text);
create table public.story_progress (user_id uuid primary key, data jsonb not null default '{}');
create table public.story_gacha (user_id uuid primary key, last_draw date not null, tickets int not null default 0 check (tickets >= 0), updated_at timestamptz default now());
create table public.story_gacha_log (id bigint generated always as identity primary key, user_id uuid, card_id text, grade text, kind text default 'daily', created_at timestamptz default now());
create table public.matches (id bigint generated always as identity primary key, user_id uuid, result text, reason text, turns int, damage int, mvp_name text, created_at timestamptz default now());
create table public.gallery (user_id uuid, card_id text, count int, mvp_count int);
grant usage on schema public to anon, authenticated;
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
 ('${ADMIN}', 'stevejean77@gmail.com', now(), '{"full_name":"Steve"}'),
 ('${USER}', 'someone@gmail.com', now(), '{"full_name":"유저"}'),
 ('${FAKE}', 'StevejeAn77@gmail.com', null, '{}');
insert into public.story_progress values ('${USER}', '{"owned":[{"uid":"a","id":"1000000001","level":3}],"leader":"a","cleared":{"1":[1,2]}}');
insert into public.matches (user_id, result) values ('${USER}','win'),('${USER}','win'),('${USER}','lose');
insert into public.story_gacha_log (user_id, card_id, grade, kind) values ('${USER}','1000000001','NORMAL','ticket');
`);
await db.exec(readFileSync(new URL('../supabase/admin.sql', import.meta.url), 'utf8'));
let fails = 0;
const ok = (c, m) => { if (!c) { fails++; console.log('FAIL', m); } else console.log('ok  ', m); };
async function as(role, claims, sql) {
  await db.exec(`reset role; select set_config('request.jwt.claims', '${JSON.stringify(claims || {})}', false); set role ${role};`);
  try { return { rows: (await db.query(sql)).rows }; } catch (e) { return { err: e.message }; } finally { await db.exec('reset role'); }
}
const adminC = { sub: ADMIN, email: 'stevejean77@gmail.com' }, userC = { sub: USER, email: 'someone@gmail.com' };
const calls = [`select public.admin_list_users()`, `select public.admin_user_detail('${USER}')`, `select public.admin_grant_tickets('${USER}', 5, 'test')`, `select public.admin_gacha_log('${USER}')`, `select public.admin_logs()`];
for (const q of calls) {
  const r = await as('authenticated', userC, q); ok(r.err && /forbidden/.test(r.err), `일반 유저 거부: ${q.slice(14, 40)} (${r.err})`);
  const a = await as('anon', {}, q); ok(a.err && /permission denied|forbidden/.test(a.err), `비로그인(anon) 거부: ${q.slice(14, 40)}`);
  // 관리자 이메일을 JWT 에 위조해도 auth.users 의 본인 이메일이 아니면 거부
  const f = await as('authenticated', { sub: USER, email: 'stevejean77@gmail.com' }, q); ok(f.err && /forbidden/.test(f.err), `JWT 이메일 위조 거부: ${q.slice(14, 40)}`);
  // 이메일 미인증 계정 (대소문자만 다른 관리자 주소) 거부
  const v = await as('authenticated', { sub: FAKE, email: 'stevejean77@gmail.com' }, q); ok(v.err && /forbidden/.test(v.err), `미인증 이메일 거부: ${q.slice(14, 40)}`);
}
for (const fn of ['_is_admin()', '_admin_guard()']) { const r = await as('authenticated', adminC, `select public.${fn}`); ok(r.err && /permission denied/.test(r.err), `내부 함수 직접 호출 불가: ${fn}`); }
ok((await as('authenticated', userC, `select public.admin_check() c`)).rows?.[0].c.admin === false, 'admin_check: 일반 유저 false');
ok((await as('authenticated', adminC, `select public.admin_check() c`)).rows?.[0].c.admin === true, 'admin_check: 관리자 true');
const lu = await as('authenticated', adminC, `select * from public.admin_list_users()`);
ok(lu.rows?.length === 3 && lu.rows.find(r => r.id === USER).wins === 2 && lu.rows.find(r => r.id === USER).cards === 1, '관리자 유저 목록 (전적·카드 수)');
const ud = await as('authenticated', adminC, `select public.admin_user_detail('${USER}') d`);
ok(ud.rows?.[0].d.record.wins === 2 && ud.rows[0].d.owned.length === 1 && ud.rows[0].d.leader === 'a', '관리자 유저 상세');
const g1 = await as('authenticated', adminC, `select public.admin_grant_tickets('${USER}', 7, '보상') r`);
ok(g1.rows?.[0].r.tickets === 7 && g1.rows[0].r.before === 0, '소환권 지급 (행 없을 때 생성)');
const g2 = await as('authenticated', adminC, `select public.admin_grant_tickets('${USER}', 3, '추가') r`);
ok(g2.rows?.[0].r.tickets === 10, '소환권 누적');
ok(/amount/.test((await as('authenticated', adminC, `select public.admin_grant_tickets('${USER}', 0, 'x')`)).err || ''), '지급 수량 0 거부');
ok(/amount/.test((await as('authenticated', adminC, `select public.admin_grant_tickets('${USER}', 1001, 'x')`)).err || ''), '지급 수량 1001 거부');
ok(/reason/.test((await as('authenticated', adminC, `select public.admin_grant_tickets('${USER}', 1, ' ')`)).err || ''), '사유 없음 거부');
const lg = await as('authenticated', adminC, `select * from public.admin_logs()`);
ok(lg.rows?.length === 2 && lg.rows[0].target_email === 'someone@gmail.com' && lg.rows[0].after_val === 10, '관리자 로그 기록');
ok((await as('authenticated', adminC, `select * from public.admin_gacha_log('${USER}')`)).rows?.length === 1, '뽑기 기록 조회');
ok(/permission denied/.test((await as('authenticated', adminC, `select * from public.admin_log`)).err || ''), 'admin_log 테이블 직접 읽기 불가');
console.log(fails ? `\n${fails} FAILED` : '\nALL PASS'); process.exit(fails ? 1 : 0);
