// supabase/phaseE_5.sql 검증 (PGlite, 실제 스토리·퀘스트 SQL 위에서). 실행: NODE_PATH=<pglite 설치 경로> node tools/test_sweep_sql.mjs
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
await run('phaseE_4.sql'); await run('phaseE_5.sql'); await run('phaseE_5.sql');
let fails = 0; const ok = (c, m) => { if (!c) { fails++; console.log('FAIL', m); } else console.log('ok  ', m); };
async function as(role, claims, sql) {
  await db.exec(`reset role; select set_config('request.jwt.claims', '${JSON.stringify(claims || {})}', false); set role ${role};`);
  try { return { rows: (await db.query(sql)).rows }; } catch (e) { return { err: e.message }; } finally { await db.exec('reset role'); }
}
const me = { sub: U, email: 'u@x.com' }, q = s => as('authenticated', me, s);
const W = async () => (await db.query(`select gold::int, blood::int, shard::int, soul::int from public.player_wallet where user_id='${U}'`)).rows[0] || { gold: 0, blood: 0, shard: 0, soul: 0 };
const give = o => db.query(`select public._wallet_add('${U}', '${JSON.stringify(o)}', 'test')`);

await q(`select public.story_choose_starter('10111')`);
await q('select public.player_status()');
await db.exec(`update public.story_progress set data = jsonb_set(data, '{cleared}', '{"1":[1]}') where user_id='${U}'`);
const sw = (c, p, n) => q(`select public.story_sweep(${c}, ${p}, ${n}) r`);
const P = async () => (await db.query(`select level, xp, stamina from public.player_state where user_id='${U}'`)).rows[0];
ok(/sweep locked/.test((await sw(1, 1, 1)).err || ''), 'Lv1 소탕 불가');
await db.exec(`update public.player_state set level = 5, xp = 300, stamina = 50 where user_id='${U}'`);
ok(/not cleared/.test((await sw(1, 2, 1)).err || ''), '미클리어 페이즈 거부');
ok(/invalid runs/.test((await sw(1, 1, 3)).err || ''), '1/5/10 외 거부');
ok(/not enough stamina/.test((await sw(1, 1, 10)).err || ''), '행동력 60 > 50 거부');
ok((await P()).stamina === 50 && (await W()).gold === 0, '거부 시 변화 없음');
let r = await sw(1, 1, 5), x = r.rows?.[0]?.r;
ok(x && x.runs === 5 && x.stamina === 30 && x.per_run.length === 5, `5회 소탕 (${r.err || ''})`);
ok(x.drops.gold === 600 && x.drops.blood === 60 && x.drops.shard >= 0 && x.drops.shard <= 5 && x.drops.soul === 0, `반복 클리어 보상과 동일: ${JSON.stringify(x.drops)}`);
ok(x.per_run.every(d => d.gold === 120 && d.blood === 12 && (d.shard === 0 || d.shard === 1)), '회당 골드 120 · 피 12 · 조각 0/1 (첫 클리어 보상 없음)');
const w = await W(); ok(w.blood === 60 && w.gold >= 600 && w.shard === x.drops.shard, '지갑 반영 (레벨업 골드 포함 가능)');
ok(x.player.gained_xp === 300, '플레이어 XP 6×10×5 = 300');
const pl = await P(); ok(pl.level === 6 && pl.stamina >= 20, `레벨업 처리 ${JSON.stringify(pl)}`);
const c1 = (await db.query(`select data->'owned'->0 c from public.story_progress where user_id='${U}'`)).rows[0].c;
ok(!(c1.totalExp > 0), '카드 전투 EXP 없음');
await db.exec(`update public.story_progress set data = jsonb_set(data, '{cleared}', '{"5":[1]}') where user_id='${U}'`);
const has5 = +(await db.query(`select count(*) c from public.story_phase_config where chapter = 5 and phase = 1`)).rows[0].c;
if (has5) { await db.exec(`update public.player_state set stamina = 200 where user_id='${U}'`); r = await sw(5, 1, 10); ok(r.rows?.[0].r.per_run.every(d => d.soul === 0 || d.soul === 1), '5장 영혼 확률 드롭'); }
const i = (await q('select public.sweep_info() i')).rows?.[0].i; ok(i?.unlock_level === 5 && i.stamina_per_run === 6 && i.xp_per_run === 60, `탐침 ${JSON.stringify(i)}`);
ok(/permission denied/.test((await as('anon', {}, 'select public.story_sweep(1, 1, 1)')).err || ''), 'anon 불가');
console.log(fails ? `${fails} FAIL` : 'ALL OK'); process.exit(fails ? 1 : 0);
