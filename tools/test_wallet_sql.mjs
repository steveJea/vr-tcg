// supabase/phaseE_1.sql 검증 (PGlite). 실행: NODE_PATH=<pglite 설치 경로> node tools/test_wallet_sql.mjs
import { readFileSync } from 'fs';
import { createRequire } from 'module';
const require = createRequire(import.meta.url);
let PGlite;
try { ({ PGlite } = require('@electric-sql/pglite')); } catch { console.log('SKIP: @electric-sql/pglite 없음'); process.exit(0); }
const db = new PGlite();
const ADMIN = '00000000-0000-0000-0000-000000000001', USER = '00000000-0000-0000-0000-000000000002', OTHER = '00000000-0000-0000-0000-000000000003';
await db.exec(`
create role anon nologin; create role authenticated nologin;
create schema auth;
create table auth.users (id uuid primary key, email text, email_confirmed_at timestamptz, created_at timestamptz default now(), last_sign_in_at timestamptz, raw_user_meta_data jsonb default '{}');
create function auth.jwt() returns jsonb language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $$;
create function auth.uid() returns uuid language sql stable as $$ select nullif(auth.jwt()->>'sub', '')::uuid $$;
grant usage on schema auth to anon, authenticated; grant execute on all functions in schema auth to anon, authenticated;
create table public.profiles (id uuid primary key, nickname text);
create table public.story_progress (user_id uuid primary key, data jsonb not null default '{}');
create table public.story_gacha (user_id uuid primary key, last_draw date not null, tickets int not null default 0, updated_at timestamptz default now());
create table public.story_gacha_log (id bigint generated always as identity primary key, user_id uuid, card_id text, grade text, kind text, created_at timestamptz default now());
create table public.matches (id bigint generated always as identity primary key, user_id uuid, result text, reason text, turns int, damage int, mvp_name text, created_at timestamptz default now());
create table public.gallery (user_id uuid, card_id text, count int, mvp_count int);
grant usage on schema public to anon, authenticated;
insert into auth.users (id, email, email_confirmed_at) values ('${ADMIN}','stevejean77@gmail.com',now()),('${USER}','u@x.com',now()),('${OTHER}','o@x.com',now());
`);
await db.exec(readFileSync(new URL('../supabase/admin.sql', import.meta.url), 'utf8'));
const sql = readFileSync(new URL('../supabase/phaseE_1.sql', import.meta.url), 'utf8');
await db.exec(sql); await db.exec(sql);   // 두 번 실행해도 안전
let fails = 0;
const ok = (c, m) => { if (!c) { fails++; console.log('FAIL', m); } else console.log('ok  ', m); };
async function as(role, claims, q) {
  await db.exec(`reset role; select set_config('request.jwt.claims', '${JSON.stringify(claims || {})}', false); set role ${role};`);
  try { return { rows: (await db.query(q)).rows }; } catch (e) { return { err: e.message }; } finally { await db.exec('reset role'); }
}
const U = { sub: USER, email: 'u@x.com' }, A = { sub: ADMIN, email: 'stevejean77@gmail.com' }, O = { sub: OTHER, email: 'o@x.com' };
const st = await as('authenticated', U, 'select public.wallet_status() w');
ok(st.rows?.[0].w.ok && st.rows[0].w.gold === 0 && st.rows[0].w.soul === 0, 'wallet_status: 행 없으면 0');
ok(/permission denied/.test((await as('anon', {}, 'select public.wallet_status()')).err || ''), 'anon 은 wallet_status 불가');
ok(/permission denied/.test((await as('authenticated', U, `select public._wallet_add('${USER}', '{"gold":999}', 'hack')`)).err || ''), '유저가 _wallet_add 직접 호출 불가');
ok(/permission denied|policy/.test((await as('authenticated', U, `insert into public.player_wallet (user_id, gold) values ('${USER}', 999)`)).err || ''), '지갑 직접 쓰기 불가');
// 서버 내부 지급 (이후 단계 RPC 를 흉내)
let r = (await db.query(`select public._wallet_add('${USER}', '{"gold":120,"blood":12,"shard":0}', 'story_clear') w`)).rows[0].w;
ok(r.gold === 120 && r.blood === 12 && r.shard === 0, '_wallet_add 지급');
let e = ''; try { await db.query(`select public._wallet_add('${USER}', '{"gold":-121}', 'card_levelup')`); } catch (x) { e = x.message; }
ok(/not enough gold/.test(e), '잔액 부족 거부');
r = (await db.query(`select public._wallet_add('${USER}', '{"gold":-20,"blood":-12}', 'card_levelup') w`)).rows[0].w;
ok(r.gold === 100 && r.blood === 0, '사용(차감)');
for (const bad of [`'{"gem":1}'`, `'{"gold":1.5}'`, `'{"gold":"5"}'`, `'[1]'`]) { let m = ''; try { await db.query(`select public._wallet_add('${USER}', ${bad}, 'x')`); } catch (x) { m = x.message; } ok(/invalid/.test(m), `잘못된 입력 거부 ${bad}`); }
ok(+(await db.query(`select count(*) c from public.wallet_log where user_id='${USER}'`)).rows[0].c === 2, '변동 기록 2건 (실패는 기록 안 됨)');
const own = await as('authenticated', U, 'select gold from public.player_wallet'); ok(own.rows?.length === 1 && +own.rows[0].gold === 100, '본인 지갑 select 가능');
const oth = await as('authenticated', O, 'select gold from public.player_wallet'); ok(oth.rows?.length === 0, '남의 지갑 안 보임');
ok(/permission denied/.test((await as('authenticated', U, 'select * from public.wallet_log')).err || ''), 'wallet_log 직접 읽기 불가');
// 관리자
ok(/forbidden/.test((await as('authenticated', U, `select public.admin_grant_currency('${USER}','gold',100,'x')`)).err || ''), '일반 유저 지급 거부');
ok(/forbidden/.test((await as('authenticated', { sub: USER, email: 'stevejean77@gmail.com' }, `select public.admin_user_wallet('${USER}')`)).err || ''), 'JWT 위조 거부');
const g = await as('authenticated', A, `select public.admin_grant_currency('${USER}','soul',30,'보상') r`);
ok(g.rows?.[0].r.after === 30 && g.rows[0].r.before === 0, '관리자 혼 지급');
const g2 = await as('authenticated', A, `select public.admin_grant_currency('${USER}','gold',-500,'회수') r`);
ok(/not enough gold/.test(g2.err || ''), '잔액보다 많이 회수 거부');
ok(/amount/.test((await as('authenticated', A, `select public.admin_grant_currency('${USER}','gold',0,'x')`)).err || ''), '0 거부');
ok(/reason/.test((await as('authenticated', A, `select public.admin_grant_currency('${USER}','gold',5,' ')`)).err || ''), '사유 필수');
const aw = await as('authenticated', A, `select public.admin_user_wallet('${USER}') w`);
ok(aw.rows?.[0].w.soul === 30 && aw.rows[0].w.log.length === 3, '관리자 지갑 조회 + 기록');
ok(+(await db.query(`select count(*) c from public.admin_log where action='grant_soul'`)).rows[0].c === 1, 'admin_log 기록');
console.log(fails ? `\n${fails} FAIL` : '\nALL OK'); process.exit(fails ? 1 : 0);
