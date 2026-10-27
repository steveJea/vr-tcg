// supabase/manual_battle.sql 검증 (PGlite): 수동 전투 행동 기록 (토벌 raid_log · PvP pvp_log)
import { readFileSync } from 'fs';
import { createRequire } from 'module';
const require = createRequire(import.meta.url);
let PGlite; try { ({ PGlite } = require('@electric-sql/pglite')); } catch { console.log('SKIP: @electric-sql/pglite 없음'); process.exit(0); }
const db = new PGlite();
const id = n => `00000000-0000-0000-0000-0000000000${String(n).padStart(2, '0')}`;
const ADMIN = id(1), A = id(2), B = id(3), C = id(4), D = id(5);
await db.exec(`create role anon nologin; create role authenticated nologin; create schema auth;
create table auth.users (id uuid primary key, email text, email_confirmed_at timestamptz, created_at timestamptz default now(), last_sign_in_at timestamptz, raw_user_meta_data jsonb default '{}');
create function auth.jwt() returns jsonb language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $$;
create function auth.uid() returns uuid language sql stable as $$ select nullif(auth.jwt()->>'sub', '')::uuid $$;
grant usage on schema auth to anon, authenticated; grant execute on all functions in schema auth to anon, authenticated; grant usage on schema public to anon, authenticated;
create table public.profiles (id uuid primary key, nickname text);
create table public.matches (id bigint generated always as identity primary key, user_id uuid, result text, reason text, turns int, damage int, mvp_name text, created_at timestamptz default now());
create table public.gallery (user_id uuid, card_id text, count int, mvp_count int);
insert into auth.users (id, email, email_confirmed_at) values ('${ADMIN}','stevejean77@gmail.com',now()),('${A}','a@x',now()),('${B}','b@x',now()),('${C}','c@x',now()),('${D}','d@x',now());
insert into profiles (id, nickname) values ('${A}','에이'),('${B}','비'),('${C}','씨'),('${D}','디');`);
const src = f => readFileSync(new URL('../supabase/' + f, import.meta.url), 'utf8');
const run = f => db.exec(src(f));
for (const f of ['story.sql', 'gacha.sql', 'story_server.sql', 'story_gacha.sql', 'story_levels.sql', 'story_merge.sql', 'story_ch2.sql', 'story_cards_1022.sql', 'story_leader_lock.sql', 'story_level_stats.sql', 'story_min_battle.sql', 'admin.sql', 'phaseE_1.sql', 'phaseE_2.sql', 'quest.sql', 'quest_sweep.sql', 'phaseE_3.sql', 'phaseE_4.sql', 'phaseE_5.sql', 'pvp.sql', 'pvp_tier.sql', 'gem.sql', 'guild.sql', 'guild2.sql']) await run(f);
await run('guild3.sql'); await run('manual_battle.sql'); await run('manual_battle.sql');   // 두 번 실행해도 안전
let fails = 0; const ok = (c, m) => { if (!c) { fails++; console.log('FAIL', m); } else console.log('ok  ', m); };
async function as(uid, sql, role = 'authenticated') {
  await db.exec(`reset role; select set_config('request.jwt.claims', '${JSON.stringify(uid ? { sub: uid, email: uid === ADMIN ? 'stevejean77@gmail.com' : 'x@x' } : {})}', false); set role ${role};`);
  try { return { rows: (await db.query(sql)).rows }; } catch (e) { return { err: e.message }; } finally { await db.exec('reset role'); }
}
const one = r => r.rows?.[0] && Object.values(r.rows[0])[0];
const v = async (uid, sql) => one(await as(uid, sql));
const q1 = async sql => one({ rows: (await db.query(sql)).rows });
const gem = async u => +((await q1(`select coalesce(sum(d_free),0) from gem_ledger where user_id='${u}'`)) || 0);
const loyal = async u => +((await q1(`select balance from loyalty_wallet where user_id='${u}'`)) || 0);
for (const u of [A, B, C, D]) await db.exec(`insert into player_state (user_id, level, stamina) values ('${u}', 20, 40)`);
const cid = await q1(`select id from pvp_card_meta order by id limit 1`);
for (const u of [A, B, C, D]) await db.exec(`insert into story_progress (user_id, data) values ('${u}', '{"owned":[{"uid":"c1","id":"${cid}","level":10}]}') on conflict (user_id) do update set data = excluded.data`);
await db.exec(`select _wallet_add('${A}', '{"gold":50000}', 'test')`);
const gid = (await v(A, `select guild_create('검은장미',1,'','open','gold')`)).id;
for (const u of [B, C]) await as(u, `select guild_apply(${gid})`);
await db.exec(`update guild_members set joined_at = now() - interval '9 days'`);
const back = async () => db.exec(`update guild_raid_attempts set started_at = started_at - interval '5 seconds' where finished_at is null`);
const acts = JSON.stringify([{ k: 'atk', i: 0, t: 0 }, { k: 'end' }]);
ok(+(await q1(`select (_raid_numbers()->>'open_minutes')::int`)) === 20, '토벌 제한 시간 20분 (수동)');
let st = await v(B, `select raid_start('["c1"]')`);
ok(/no battle/.test((await as(C, `select raid_log(${st.id}, '${acts}')`)).err || ''), '남의 판에 기록 불가');
ok(/bad actions/.test((await as(B, `select raid_log(${st.id}, '{"k":1}')`)).err || ''), '배열 아니면 불가');
ok(/bad actions/.test((await as(B, `select raid_log(${st.id}, '${JSON.stringify(Array(200).fill({ k: 'end' }))}')`)).err || ''), '너무 긴 기록 불가');
ok(!(await as(B, `select raid_log(${st.id}, '${acts}')`)).err, '기록 저장');
ok(/already logged/.test((await as(B, `select raid_log(${st.id}, '${acts}')`)).err || ''), '기록은 한 번만');
await back();
ok(!(await as(B, `select raid_finish(${st.id}, 1000)`)).err, '기록 뒤 보고');
ok(+(await q1(`select jsonb_array_length(actions) from guild_raid_attempts where id=${st.id}`)) === 2, 'actions 저장됨');
ok(/already finished/.test((await as(B, `select raid_log(${st.id}, '${acts}')`)).err || ''), '끝난 판 기록 불가');
// PvP
ok(!(await as(A, `select pvp_set_deck('open','1v1',0,'["c1"]')`)).err, 'PvP 덱');
const p = await v(A, `select pvp_start('open','1v1')`);
ok(/bad actions/.test((await as(A, `select pvp_log(${p.id}, '[1,2,3,4]')`)).err || ''), 'PvP 판 수 초과 불가');
ok(/not found/.test((await as(B, `select pvp_log(${p.id}, '[${acts}]')`)).err || ''), 'PvP 남의 판 불가');
ok(!(await as(A, `select pvp_log(${p.id}, '[${acts}]')`)).err, 'PvP 기록 저장');
ok(!(await as(A, `select pvp_report(${p.id}, 1, 0)`)).err, 'PvP 보고');
ok(/already reported/.test((await as(A, `select pvp_log(${p.id}, '[${acts}]')`)).err || ''), '보고 뒤 기록 불가');
ok(/permission denied/.test((await as(null, `select raid_log(1, '[]')`, 'anon')).err || ''), 'anon 불가');
console.log(fails ? `FAIL ${fails}` : 'ALL PASS'); if (fails) process.exitCode = 1;
