// supabase/gear_craft.sql 검증 (PGlite): 강화 · 재설정 · 분해 · 매각
import { readFileSync } from 'fs';
import { createRequire } from 'module';
const require = createRequire(import.meta.url);
let PGlite; try { ({ PGlite } = require('@electric-sql/pglite')); } catch { console.log('SKIP: @electric-sql/pglite 없음'); process.exit(0); }
const db = new PGlite();
const U = '00000000-0000-0000-0000-000000000002', V = '00000000-0000-0000-0000-000000000003', ADMIN = '00000000-0000-0000-0000-000000000001';
await db.exec(`create role anon nologin; create role authenticated nologin; create schema auth;
create table auth.users (id uuid primary key, email text, email_confirmed_at timestamptz, created_at timestamptz default now(), last_sign_in_at timestamptz, raw_user_meta_data jsonb default '{}');
create function auth.jwt() returns jsonb language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $$;
create function auth.uid() returns uuid language sql stable as $$ select nullif(auth.jwt()->>'sub', '')::uuid $$;
grant usage on schema auth to anon, authenticated; grant execute on all functions in schema auth to anon, authenticated; grant usage on schema public to anon, authenticated;
create table public.profiles (id uuid primary key, nickname text);
create table public.matches (id bigint generated always as identity primary key, user_id uuid, result text, reason text, turns int, damage int, mvp_name text, created_at timestamptz default now());
create table public.gallery (user_id uuid, card_id text, count int, mvp_count int);
insert into auth.users (id, email, email_confirmed_at) values ('${U}','u@x.com',now()),('${V}','v@x.com',now()),('${ADMIN}','stevejean77@gmail.com',now());
insert into profiles (id, nickname) values ('${U}','유'),('${V}','브이');`);
const src = f => readFileSync(new URL('../supabase/' + f, import.meta.url), 'utf8');
const run = f => db.exec(src(f));
for (const f of ['story.sql', 'gacha.sql', 'story_server.sql', 'story_gacha.sql', 'story_levels.sql', 'story_merge.sql', 'story_ch2.sql', 'story_cards_1022.sql', 'story_leader_lock.sql', 'story_level_stats.sql', 'story_min_battle.sql', 'admin.sql', 'phaseE_1.sql', 'phaseE_2.sql', 'pvp.sql', 'pvp_tier.sql']) await run(f);
await run('gem.sql'); await run('gear_v1.sql'); await run('gear_craft.sql'); await run('gear_craft.sql');   // 두 번 실행해도 안전
let fails = 0; const ok = (c, m) => { if (!c) { fails++; console.log('FAIL', m); } else console.log('ok  ', m); };
async function as(uid, sql, role = 'authenticated') {
  await db.exec(`reset role; select set_config('request.jwt.claims', '${JSON.stringify(uid ? { sub: uid, email: 'x@x' } : {})}', false); set role ${role};`);
  try { return { rows: (await db.query(sql)).rows }; } catch (e) { return { err: e.message }; } finally { await db.exec('reset role'); }
}
const v = async (u, s) => { const r = await as(u, s); return r.err ? { err: r.err } : Object.values(r.rows[0])[0]; };
const q1 = async s => Object.values((await db.query(s)).rows[0] || {})[0];
const gold = async u => +(await q1(`select coalesce((select gold from player_wallet where user_id='${u}'), 0)`));
const dust = async u => +(await q1(`select coalesce((select dust from player_gear_meta where user_id='${u}'), 0)`));
const give = async (u, def) => (await db.query(`select (public._gear_grant('${u}', '${def}', 'test') ->> 'gear_id')::bigint id`)).rows[0].id;
const a = await give(U, 'weapon_4_1');
ok(/not enough gold/.test((await v(U, `select gear_enhance(${a})`)).err || ''), '골드 부족: 강화 불가');
await db.exec(`select _wallet_add('${U}', '{"gold":100000}', 'test')`);
ok(/not enough dust/.test((await v(U, `select gear_enhance(${a})`)).err || '') && (await gold(U)) === 100000, '가루 부족: 불가 · 골드 그대로 (롤백)');
await db.exec(`select _gear_dust_add('${U}', 200)`);
for (let i = 1; i <= 5; i++) await v(U, `select gear_enhance(${a})`);
ok(+(await q1(`select plus from player_gear where id=${a}`)) === 5 && (await gold(U)) === 100000 - 30000 && (await dust(U)) === 200 - 115, '+5까지: 골드 30k · 가루 115');
ok((await v(U, `select gear_enhance(${a})`)).reason === 'max plus', '+5 이상 불가');
const before = JSON.stringify(await q1(`select opts from player_gear where id=${a}`));
const rr = await v(U, `select gear_reroll(${a})`); ok(rr.ok && rr.opts.length === 1 && (await gold(U)) === 70000 - 2000 && (await dust(U)) === 85 - 8, `재설정: 희귀 골드 2000 · 가루 8 (${before} → ${JSON.stringify(rr.opts)})`);
const low = await give(U, 'weapon_1_1'); ok((await v(U, `select gear_reroll(${low})`)).reason === 'no options', '부옵션 없는 장비 재설정 불가');
ok(!!(await v(V, `select gear_enhance(${a})`)).err, '남의 장비 강화 불가');
// 분해·매각
const b = await give(U, 'armor_3_1'), c = await give(U, 'acc_2_1'), e = await give(U, 'weapon_5_1');
await db.exec(`update player_gear set locked = true where id = ${e}`);
ok((await v(U, `select gear_sell(array[${b}, ${e}]::bigint[])`)).reason === 'locked or equipped' && +(await q1(`select count(*) from player_gear where id in (${b}, ${e})`)) === 2, '잠금 섞이면 전체 거부');
await db.exec(`insert into story_progress (user_id, data) values ('${U}', '{"owned":[{"uid":"x","id":"1000100007"}]}') on conflict (user_id) do update set data = excluded.data`);
await db.exec(`update player_gear set equipped_card = '1000100007' where id = ${a}`);
ok((await v(U, `select gear_dismantle(array[${a}]::bigint[])`)).reason === 'locked or equipped', '장착 장비 분해 불가');
const g0 = await gold(U), s = await v(U, `select gear_sell(array[${b}, ${c}]::bigint[])`);
ok(s.ok && s.count === 2 && (await gold(U)) - g0 === 700, '매각 2개: 고급 500 + 일반 200 골드');
const d0 = await dust(U), dm = await v(U, `select gear_dismantle(array[${low}]::bigint[])`);
ok(dm.ok && (await dust(U)) - d0 === 1, '분해: 낡은 → 가루 1');
ok((await v(U, `select gear_sell(array[${b}]::bigint[])`)).reason === 'not found', '이미 판 장비 다시 못 팖');
const f = await give(V, 'weapon_1_1'); ok((await v(U, `select gear_sell(array[${f}]::bigint[])`)).reason === 'not found', '남의 장비 못 팖');
ok((await v(U, `select gear_sell(array[]::bigint[])`)).reason === 'empty', '빈 목록');
// 보안
ok(!!(await as(null, `select gear_sell(array[1]::bigint[])`, 'anon')).err, 'anon RPC 거부');
ok(!!(await as(U, `select _gear_salvage(array[${f}]::bigint[], true)`)).err && !!(await as(U, `select _gear_dust_add('${U}', 999)`)).err, '내부 함수 직접 호출 불가');
for (const t of ['gear_enhance_cost', 'gear_salvage', 'gear_reroll_cost']) ok(!!(await as(null, `select * from ${t}`, 'anon')).err && (await as(U, `select * from ${t}`)).rows?.length > 0, `${t}: anon 거부 · 로그인 읽기`);
ok(!!(await as(U, `update gear_enhance_cost set gold = 0`)).err, '비용표 쓰기 불가');
console.log(fails ? `\n${fails} FAIL` : '\nALL OK'); process.exit(fails ? 1 : 0);
