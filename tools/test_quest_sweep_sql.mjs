// supabase/quest_sweep.sql 검증 (PGlite, 실제 스토리·퀘스트 SQL 위에서). 실행: NODE_PATH=<pglite 설치 경로> node tools/test_quest_sweep_sql.mjs
import { readFileSync } from 'fs';
import { createRequire } from 'module';
const require = createRequire(import.meta.url);
let PGlite; try { ({ PGlite } = require('@electric-sql/pglite')); } catch { console.log('SKIP: @electric-sql/pglite 없음'); process.exit(0); }
const db = new PGlite();
const U = '00000000-0000-0000-0000-000000000002', M = '00000000-0000-0000-0000-000000000004';
await db.exec(`create role anon nologin; create role authenticated nologin; create schema auth;
create table auth.users (id uuid primary key, email text, email_confirmed_at timestamptz, created_at timestamptz default now(), last_sign_in_at timestamptz, raw_user_meta_data jsonb default '{}');
create function auth.jwt() returns jsonb language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $$;
create function auth.uid() returns uuid language sql stable as $$ select nullif(auth.jwt()->>'sub', '')::uuid $$;
grant usage on schema auth to anon, authenticated; grant execute on all functions in schema auth to anon, authenticated; grant usage on schema public to anon, authenticated;
create table public.profiles (id uuid primary key, nickname text);
create table public.matches (id bigint generated always as identity primary key, user_id uuid, result text, reason text, turns int, damage int, mvp_name text, created_at timestamptz default now());
create table public.gallery (user_id uuid, card_id text, count int, mvp_count int);
insert into auth.users (id, email, email_confirmed_at) values ('${U}','u@x.com',now()),('${M}','m@x.com',now());`);
const run = f => db.exec(readFileSync(new URL('../supabase/' + f, import.meta.url), 'utf8'));
for (const f of ['story.sql', 'gacha.sql', 'story_server.sql', 'story_gacha.sql', 'story_levels.sql', 'story_level_stats.sql', 'story_merge.sql', 'story_ch2.sql', 'story_cards_1022.sql', 'story_leader_lock.sql', 'story_min_battle.sql', 'quest.sql', 'admin.sql', 'phaseE_1.sql', 'phaseE_2.sql', 'phaseE_3.sql']) await run(f);
await run('phaseE_4.sql'); await run('phaseE_5.sql'); await run('quest_sweep.sql'); await run('quest_sweep.sql');
let fails = 0; const ok = (c, m) => { if (!c) { fails++; console.log('FAIL', m); } else console.log('ok  ', m); };
async function as(role, claims, sql) {
  await db.exec(`reset role; select set_config('request.jwt.claims', '${JSON.stringify(claims || {})}', false); set role ${role};`);
  try { return { rows: (await db.query(sql)).rows }; } catch (e) { return { err: e.message }; } finally { await db.exec('reset role'); }
}
const me = { sub: U, email: 'u@x.com' }, q = s => as('authenticated', me, s);
const W = async () => (await db.query(`select gold::int, blood::int, shard::int, soul::int from public.player_wallet where user_id='${U}'`)).rows[0] || { gold: 0, blood: 0, shard: 0, soul: 0 };
const give = o => db.query(`select public._wallet_add('${U}', '${JSON.stringify(o)}', 'test')`);


const QP = async () => (await db.query(`select best_floor, battle, clears, rewards from public.quest_progress where user_id='${U}'`)).rows[0];
const back = s => db.exec(`update public.quest_progress set battle = jsonb_set(battle, '{at}', to_jsonb((battle->>'at')::numeric - ${s})) where user_id='${U}'`);
const T = n => JSON.stringify({ turns: Array(n).fill(7) });
let i = (await q('select public.quest_sweep_info() i')).rows?.[0].i; ok(i?.from === 1 && i.boss === 10 && i.max_floors === 9 && i.stamina === 0, `탐침 ${JSON.stringify(i)}`);
ok(/sweep not started/.test((await q(`select public.quest_sweep_complete(3, '${T(3)}')`)).err || ''), '시작 없이 완료 불가');
let s = (await q('select public.quest_sweep_start() s')).rows?.[0].s; ok(s?.from === 1 && s.last === 9, '1층부터, 9층까지');
ok(/too fast/.test((await q(`select public.quest_sweep_complete(5, '${T(5)}')`)).err || ''), '층당 1초 미만 거부');
await back(10);
ok(/invalid range/.test((await q(`select public.quest_sweep_complete(10, '${T(10)}')`)).err || ''), '보스 층(10) 포함 거부');
ok(/invalid stats/.test((await q(`select public.quest_sweep_complete(5, '${JSON.stringify({ turns: [1, 2] })}')`)).err || ''), '턴 기록 부족 거부');
ok(/invalid stats/.test((await q(`select public.quest_sweep_complete(5, '${JSON.stringify({ turns: [1, 2, 3, 99, 5] })}')`)).err || ''), '턴 범위 밖 거부');
let r = (await q(`select public.quest_sweep_complete(5, '${T(5)}') r`)), x = r.rows?.[0].r;
ok(x?.cleared === 5 && x.best_floor === 5 && x.floors.length === 5, `1~5층 소탕 ${r.err || ''}`);
const g = 5 * 50 + 5 * (1 + 2 + 3 + 4 + 5);
ok(x.total.gold === g && (await W()).gold === g, `첫 클리어 골드 합 ${g} (${JSON.stringify(x.total)})`);
let p = await QP(); ok(p.best_floor === 5 && p.battle === null && p.clears === 5 && p.rewards.gold === g, '진행 기록');
ok(/sweep not started/.test((await q(`select public.quest_sweep_complete(6, '${T(1)}')`)).err || ''), '같은 기록 재사용 불가');
s = (await q('select public.quest_sweep_start() s')).rows?.[0].s; await back(5);
x = (await q(`select public.quest_sweep_complete(5, '${T(0)}') r`)).rows?.[0].r; ok(x?.cleared === 0 && (await QP()).best_floor === 5, '첫 층에서 패배 → 0층, 변화 없음');
s = (await q('select public.quest_sweep_start() s')).rows?.[0].s; await back(5);
x = (await q(`select public.quest_sweep_complete(9, '${T(4)}') r`)).rows?.[0].r; ok(x?.best_floor === 9, '6~9층 → 9층');
ok(/boss floor/.test((await q('select public.quest_sweep_start()')).err || ''), '다음이 보스 층(10)이면 소탕 불가');
await q('select public.quest_start(10)'); await db.exec(`update public.quest_progress set battle = jsonb_set(battle, '{at}', to_jsonb((battle->>'at')::bigint - 10)) where user_id='${U}'`);
r = await q(`select public.quest_complete(10, '{"turns":5}') r`); ok(r.rows?.[0].r.first && r.rows[0].r.reward.tickets === 5, `보스 층 직접 클리어 (소환권 5) ${r.err || ''}`);
s = (await q('select public.quest_sweep_start() s')).rows?.[0].s; ok(s?.from === 11 && s.last === 19, '보스 후 11~19층');
await q('select public.quest_start(11)');
ok(/sweep not started/.test((await q(`select public.quest_sweep_complete(11, '${T(1)}')`)).err || ''), '일반 전투 시작하면 소탕 기록 무효');
ok(/permission denied/.test((await as('anon', {}, 'select public.quest_sweep_start()')).err || ''), 'anon 불가');
console.log(fails ? `${fails} FAIL` : 'ALL OK'); process.exit(fails ? 1 : 0);
