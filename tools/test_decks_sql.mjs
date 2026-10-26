// supabase/story_decks.sql 검증 (PGlite): 마이 덱 10개·자동 잠금·즐겨찾기
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
insert into auth.users (id, email, email_confirmed_at) values ('${U}','u@x.com',now()),('${V}','v@x.com',now()),('${ADMIN}','stevejean77@gmail.com',now());`);
const run = f => db.exec(readFileSync(new URL('../supabase/' + f, import.meta.url), 'utf8'));
for (const f of ['story.sql', 'gacha.sql', 'story_server.sql', 'story_gacha.sql', 'story_levels.sql', 'story_merge.sql', 'story_ch2.sql', 'story_cards_1022.sql', 'story_leader_lock.sql', 'story_level_stats.sql', 'story_min_battle.sql', 'admin.sql', 'phaseE_1.sql', 'phaseE_2.sql']) await run(f);
await run("story_ch1_reward.sql"); await run("story_decks.sql"); await run("story_decks.sql");
let fails = 0; const ok = (c, m) => { if (!c) { fails++; console.log('FAIL', m); } else console.log('ok  ', m); };
async function as(role, claims, sql) {
  await db.exec(`reset role; select set_config('request.jwt.claims', '${JSON.stringify(claims || {})}', false); set role ${role};`);
  try { return { rows: (await db.query(sql)).rows }; } catch (e) { return { err: e.message }; } finally { await db.exec('reset role'); }
}
const me = { sub: U, email: 'u@x.com' }, q = s => as('authenticated', me, s);
const owned = [{ uid: 'a', id: '1' }, { uid: 'b', id: '2' }, { uid: 'c', id: '3', locked: true }, { uid: 'guest:x', id: '4' }];
await db.exec(`insert into story_progress (user_id, data) values ('${U}', '${JSON.stringify({ starter: '1', owned })}'::jsonb) on conflict (user_id) do update set data = excluded.data`);
const get = async () => (await db.query(`select data from story_progress where user_id='${U}'`)).rows[0].data;
const O = (d, u) => d.owned.find(o => o.uid === u);
let r = await q(`select story_set_decks('[{"name":"A","uids":["a","c"]}]'::jsonb)`); ok(!r.err, 'save deck ' + (r.err || ''));
let d = await get(); ok(O(d, 'a').locked && O(d, 'a').dlk, 'deck card auto-locked'); ok(O(d, 'c').locked && !O(d, 'c').dlk, 'manual lock kept');
r = await q(`select story_set_lock('a', false)`); ok(/card in deck/.test(r.err || ''), 'unlock deck card blocked');
r = await q(`select story_discard_many(array['a'], 'b')`); ok(!!r.err, 'discard deck card blocked');
r = await q(`select story_set_decks('[{"name":"A","uids":["c"]}]'::jsonb)`); d = await get();
ok(!O(d, 'a').locked && !O(d, 'a').dlk, 'auto-lock removed'); ok(O(d, 'c').locked, 'manual lock still kept');
ok(/not owned/.test((await q(`select story_set_decks('[{"uids":["zz"]}]'::jsonb)`)).err || ''), 'unowned rejected');
ok(/not owned/.test((await q(`select story_set_decks('[{"uids":["guest:x"]}]'::jsonb)`)).err || ''), 'guest rejected');
ok(/too many/.test((await q(`select story_set_decks('${JSON.stringify(Array(11).fill({ uids: [] }))}'::jsonb)`)).err || ''), '>10 decks rejected');
ok(/too large/.test((await q(`select story_set_decks('[{"uids":["a","b","c","a","b","c"]}]'::jsonb)`)).err || ''), '>5 cards rejected');
r = await q(`select story_set_fav('b', true)`); d = await get(); ok(O(d, 'b').fav === true, 'fav on');
await q(`select story_set_fav('b', false)`); d = await get(); ok(!('fav' in O(d, 'b')), 'fav off');
ok(!!(await as('anon', {}, `select story_set_decks('[]'::jsonb)`)).err, 'anon denied');
ok(!!(await as('authenticated', { sub: V }, `select story_set_fav('b', true)`)).err, 'other user cannot touch');
console.log(fails ? `${fails} FAIL` : 'ALL OK'); process.exit(fails ? 1 : 0);
