// supabase/pvp_info_notices.sql 검증 (원본: guild4 테스트 헤더) (PGlite): 구역 전쟁 — 시즌 시간 · 참가/배치 · 잠금 · 대진 · NPC · 공격 순서/횟수/HP 유지/2번 덱 · 보스 즉승 · 정산/승점 · 보상 · 보안 · 관리자
import { readFileSync } from 'fs';
import { createRequire } from 'module';
const require = createRequire(import.meta.url);
let PGlite; try { ({ PGlite } = require('@electric-sql/pglite')); } catch { console.log('SKIP: @electric-sql/pglite 없음'); process.exit(0); }
const db = new PGlite();
const id = n => `00000000-0000-0000-0000-0000000000${String(n).padStart(2, '0')}`;
const ADMIN = id(1), U = Array.from({ length: 34 }, (_, i) => id(i + 10));   // U[0..10] = 1조직, U[11..21] = 2조직, U[22..32] = 3조직, U[33] = 무소속
await db.exec(`create role anon nologin; create role authenticated nologin; create schema auth;
create table auth.users (id uuid primary key, email text, email_confirmed_at timestamptz, created_at timestamptz default now(), last_sign_in_at timestamptz, raw_user_meta_data jsonb default '{}');
create function auth.jwt() returns jsonb language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $$;
create function auth.uid() returns uuid language sql stable as $$ select nullif(auth.jwt()->>'sub', '')::uuid $$;
grant usage on schema auth to anon, authenticated; grant execute on all functions in schema auth to anon, authenticated; grant usage on schema public to anon, authenticated;
create table public.profiles (id uuid primary key, nickname text);
create table public.matches (id bigint generated always as identity primary key, user_id uuid, result text, reason text, turns int, damage int, mvp_name text, created_at timestamptz default now());
create table public.gallery (user_id uuid, card_id text, count int, mvp_count int);
insert into auth.users (id, email, email_confirmed_at) values ('${ADMIN}','stevejean77@gmail.com',now()), ${U.map(u => `('${u}','${u}@x',now())`).join(',')};
insert into profiles (id, nickname) values ${U.map((u, i) => `('${u}','p${i}')`).join(',')};`);
const src = f => readFileSync(new URL('../supabase/' + f, import.meta.url), 'utf8');
const run = f => db.exec(src(f));
for (const f of ['story.sql', 'gacha.sql', 'story_server.sql', 'story_gacha.sql', 'story_levels.sql', 'story_merge.sql', 'story_ch2.sql', 'story_cards_1022.sql', 'story_leader_lock.sql', 'story_level_stats.sql', 'story_min_battle.sql', 'admin.sql', 'phaseE_1.sql', 'phaseE_2.sql', 'quest.sql', 'quest_sweep.sql', 'phaseE_3.sql', 'phaseE_4.sql', 'phaseE_5.sql', 'pvp.sql', 'pvp_tier.sql', 'gem.sql', 'guild.sql', 'guild2.sql', 'guild3.sql']) await run(f);

await run('pvp_info_notices.sql'); await run('pvp_info_notices.sql');   // 두 번 실행해도 안전
let fails = 0; const ok = (c, m) => { if (!c) { fails++; console.log('FAIL', m); } else console.log('ok  ', m); };
async function as(uid, sql, role = 'authenticated') {
  await db.exec(`reset role; select set_config('request.jwt.claims', '${JSON.stringify(uid ? { sub: uid, email: uid === ADMIN ? 'stevejean77@gmail.com' : 'x@x' } : {})}', false); set role ${role};`);
  try { return { rows: (await db.query(sql)).rows }; } catch (e) { return { err: e.message }; } finally { await db.exec('reset role'); }
}
const v = async (uid, sql, role) => { const r = await as(uid, sql, role); return r.err ? { err: r.err } : Object.values(r.rows[0])[0]; };
const ids = (await db.query(`select id from pvp_card_meta order by id limit 6`)).rows.map(r => r.id);
for (const u of U.slice(0, 3)) {
  await db.exec(`insert into player_state (user_id, level) values ('${u}', 7) on conflict (user_id) do update set level = 7`);
  await db.exec(`insert into story_progress (user_id, data) values ('${u}', '${JSON.stringify({ leader: 'c1', owned: ids.map((x, i) => ({ uid: 'c' + i, id: x, level: 10 })) })}') on conflict (user_id) do update set data = excluded.data`);
}
await db.exec(`insert into pvp_ratings (user_id, league, mode, season, rating, wins, losses) values ('${U[0]}','open','1v1',_pvp_season(),1500,5,1),('${U[1]}','open','1v1',_pvp_season(),1400,3,2)`);
const sd = await as(U[0], `select pvp_set_deck('open','1v1',0,'["c0","c2"]'::jsonb)`); ok(!sd.err, 'deck set ' + (sd.err || ''));
const gi = await db.query(`insert into guilds (name, name_key, boss) values ('흑표파','흑표파','${U[0]}') returning id`);
await db.exec(`insert into guild_members (user_id, guild_id, role) values ('${U[0]}', ${gi.rows[0].id}, 'boss')`);
const info = await v(U[1], `select pvp_user_info('open','1v1',1)`);
ok(info?.name === 'p0' && info.level === 7 && info.leader === ids[1], 'info basics');
ok(info?.decks?.[0]?.cards?.length === 2 && info.decks[0].cards[0].id === ids[0] && info.decks[0].cards[0].level === 10, 'info deck');
ok(info?.guild?.name === '흑표파', 'info guild');
ok(!JSON.stringify(info).includes(U[0]) && !('user_id' in info), 'no uid leak');
const i2 = await v(U[0], `select pvp_user_info('open','1v1',2)`); ok(i2?.name === 'p1' && i2.guild === null && i2.decks.length === 0, 'rank2 no guild/deck');
ok(/not found/.test((await v(U[0], `select pvp_user_info('open','1v1',3)`)).err || ''), 'rank3 not found');
ok(/permission|denied/.test((await v(null, `select pvp_user_info('open','1v1',1)`, 'anon')).err || ''), 'anon denied info');
// 공지
const n1 = await v(ADMIN, `select admin_notice_save(null, '  첫 공지  ', false)`); ok(n1?.body === '첫 공지', 'admin create');
const n2 = await v(ADMIN, `select admin_notice_save(null, '고정 공지', true)`); ok(n2?.pinned === true, 'admin pinned');
ok((await v(ADMIN, `select admin_notice_save(${n1.id}, '수정됨', true)`))?.body === '수정됨', 'admin edit');
ok(/forbidden/.test((await v(U[0], `select admin_notice_save(null, 'x', false)`)).err || ''), 'non-admin save denied');
ok(/forbidden/.test((await v(U[0], `select admin_notice_delete(${n1.id})`)).err || ''), 'non-admin delete denied');
ok(/permission|denied/.test((await v(null, `select admin_notice_save(null, 'x', false)`, 'anon')).err || ''), 'anon save denied');
ok(/permission|denied/.test((await v(U[0], `insert into notices (body) values ('x') returning id`)).err || ''), 'direct insert denied');
ok(/permission|denied/.test((await v(U[0], `update notices set body='h' returning id`)).err || ''), 'direct update denied');
ok(/permission|denied/.test((await v(null, `delete from notices returning id`, 'anon')).err || ''), 'direct delete denied');
ok(+(await v(null, `select count(*) from notices`, 'anon')) === 2, 'anon can read');
ok(/body/.test((await v(ADMIN, `select admin_notice_save(null, '', false)`)).err || ''), 'empty body rejected');
ok((await v(ADMIN, `select admin_notice_delete(${n2.id})`))?.ok === true, 'admin delete');
ok(+(await v(U[1], `select count(*) from notices`)) === 1, 'after delete');
console.log(fails ? `FAILS: ${fails}` : 'ALL PASS'); process.exit(fails ? 1 : 0);
