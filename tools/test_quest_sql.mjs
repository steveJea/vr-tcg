// supabase/quest.sql 검증 (PGlite). 실행: NODE_PATH=<pglite 설치 경로> node tools/test_quest_sql.mjs
import { readFileSync } from 'fs';
import { createRequire } from 'module';
const require = createRequire(import.meta.url);
let PGlite; try { ({ PGlite } = require('@electric-sql/pglite')); } catch { console.log('SKIP: @electric-sql/pglite 없음'); process.exit(0); }
const db = new PGlite(), U = '00000000-0000-0000-0000-000000000002', ADMIN = '00000000-0000-0000-0000-000000000001';
await db.exec(`
create role anon nologin; create role authenticated nologin;
create schema auth;
create table auth.users (id uuid primary key, email text, email_confirmed_at timestamptz, created_at timestamptz default now(), last_sign_in_at timestamptz, raw_user_meta_data jsonb default '{}', raw_app_meta_data jsonb default '{}');
create function auth.jwt() returns jsonb language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $$;
create function auth.uid() returns uuid language sql stable as $$ select nullif(auth.jwt()->>'sub', '')::uuid $$;
grant usage on schema auth to anon, authenticated; grant execute on all functions in schema auth to anon, authenticated;
grant usage on schema public to anon, authenticated;
create table public.profiles (id uuid primary key, nickname text);
create table public.story_progress (user_id uuid primary key, data jsonb not null default '{}');
create table public.story_gacha (user_id uuid primary key, last_draw date not null, tickets int not null default 0 check (tickets >= 0), updated_at timestamptz default now());
create table public.story_gacha_log (id bigint generated always as identity primary key, user_id uuid, card_id text, grade text, kind text default 'daily', created_at timestamptz default now());
create table public.matches (id bigint generated always as identity primary key, user_id uuid, result text, reason text, turns int, damage int, mvp_name text, created_at timestamptz default now());
create table public.gallery (user_id uuid, card_id text, count int, mvp_count int);
insert into auth.users (id, email, email_confirmed_at) values ('${U}', 'u@x.com', now()), ('${ADMIN}', 'stevejean77@gmail.com', now());
`);
await db.exec(readFileSync(new URL('../supabase/admin.sql', import.meta.url), 'utf8'));
await db.exec(readFileSync(new URL('../supabase/quest.sql', import.meta.url), 'utf8'));
let fails = 0; const ok = (c, m) => { if (!c) { fails++; console.log('FAIL', m); } else console.log('ok  ', m); };
async function as(role, claims, sql) {
  await db.exec(`reset role; select set_config('request.jwt.claims', '${JSON.stringify(claims || {})}', false); set role ${role};`);
  try { return { rows: (await db.query(sql)).rows }; } catch (e) { return { err: e.message }; } finally { await db.exec('reset role'); }
}
const me = { sub: U, email: 'u@x.com' };
const q = sql => as('authenticated', me, sql);
const age = () => db.exec(`update public.quest_progress set battle = jsonb_set(battle, '{at}', to_jsonb((extract(epoch from now()) - 60)::bigint)) where user_id = '${U}'`);
const clear = async f => { await q(`select public.quest_start(${f})`); await age(); return (await q(`select public.quest_complete(${f}, '{"turns":12}') r`)).rows?.[0]?.r; };
ok(/permission denied/.test((await as('anon', {}, `select public.quest_status()`)).err || ''), 'anon 은 quest_status 불가');
ok((await q(`select public.quest_status() s`)).rows[0].s.best_floor === 0, '처음 최고 층 0');
ok(/floor locked/.test((await q(`select public.quest_start(2)`)).err || ''), '2층은 잠김');
ok(/invalid floor/.test((await q(`select public.quest_start(351)`)).err || ''), '351층 없음');
await q(`select public.quest_start(1)`);
ok(/too fast/.test((await q(`select public.quest_complete(1, '{"turns":3}')`)).err || ''), '최소 전투 시간 미만 거부');
ok(/battle not started/.test((await q(`select public.quest_complete(2, '{"turns":3}')`)).err || ''), '다른 층 완료 거부');
let r; for (let f = 1; f <= 10; f++) r = await clear(f);
ok(r.first && r.reward.tickets === 5 && r.tickets === 5, `10층 첫 클리어 소환권 +5 (${JSON.stringify(r)})`);
r = await clear(10); ok(r && !r.first && !r.reward.tickets, '10층 재클리어 보상 없음');
r = await clear(3); ok(r && !r.first, '아래 층 재도전 가능, 보상 없음');
ok(/battle not started/.test((await q(`select public.quest_complete(3, '{}')`)).err || ''), '같은 전투 두 번 완료 불가');
for (let f = 11; f <= 50; f++) r = await clear(f);
ok(r.reward.tickets === 10 && r.tickets === 5 * 4 + 10, `50층 소환권 +10 (누적 ${r.tickets})`);
const st = (await q(`select public.quest_status() s`)).rows[0].s;
ok(st.best_floor === 50 && st.rewards.tickets === 30 && st.max_floor === 350, '상태: 최고 50층, 받은 소환권 30');
await q(`select public.quest_start(51)`); await age();
ok(/invalid stats/.test((await q(`select public.quest_complete(51, '{"turns":99}')`)).err || ''), '턴 수 이상 거부');
ok(/permission denied/.test((await q(`update public.quest_progress set best_floor = 350`)).err || ''), '직접 수정 불가');
ok(/permission denied/.test((await q(`select public._quest_reward(10)`)).err || ''), '내부 보상 함수 직접 호출 불가');
ok(/forbidden/.test((await q(`select public.admin_user_quest('${U}')`)).err || ''), 'admin_user_quest 일반 유저 거부');
ok((await as('authenticated', { sub: ADMIN, email: 'stevejean77@gmail.com' }, `select public.admin_user_quest('${U}') a`)).rows?.[0].a.best_floor === 50, 'admin_user_quest 관리자 허용');
console.log(fails ? `\n${fails} FAILED` : '\nALL PASS'); process.exit(fails ? 1 : 0);
