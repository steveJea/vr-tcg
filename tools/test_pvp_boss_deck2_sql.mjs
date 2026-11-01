// supabase/pvp_boss_deck2.sql 검증 (PGlite): 보스리그 덱 = 리더 1 (HR 이하) + 멤버 1~5
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
for (const f of ['story.sql', 'gacha.sql', 'story_server.sql', 'story_gacha.sql', 'story_levels.sql', 'story_merge.sql', 'story_ch2.sql', 'story_cards_1022.sql', 'story_leader_lock.sql', 'story_level_stats.sql', 'story_min_battle.sql', 'admin.sql', 'phaseE_1.sql', 'phaseE_2.sql', 'pvp.sql', 'pvp_tier.sql', 'gem.sql', 'gear_v1.sql', 'gear_snap.sql', 'pvp_boss_league.sql', 'pvp_boss_deck2.sql', 'pvp_boss_deck2.sql']) await run(f);
let fails = 0; const ok = (c, m) => { if (!c) { fails++; console.log('FAIL', m); } else console.log('ok  ', m); };
async function as(sql) {
  await db.exec(`reset role; select set_config('request.jwt.claims', '${JSON.stringify({ sub: U, email: 'u@x.com' })}', false); set role authenticated;`);
  try { return { rows: (await db.query(sql)).rows }; } catch (e) { return { err: e.message }; } finally { await db.exec('reset role'); }
}
await db.exec(`insert into pvp_card_meta (id, grade, cost) values ('t_hr','HIGH RARE',30),('t_sr1','SUPER RARE',40),('t_sr2','SUPER RARE',40),('t_sr3','SUPER RARE',40),('t_sr4','SUPER RARE',40),('t_sr5','SUPER RARE',40),('t_sr6','SUPER RARE',40),('t_ur','ULTRA RARE',50) on conflict do nothing`);
const own = ['t_hr','t_sr1','t_sr2','t_sr3','t_sr4','t_sr5','t_sr6','t_ur'].map((id, i) => ({ uid: 'u' + i, id, level: 5 }));
await db.exec(`insert into story_progress (user_id, data) values ('${U}','${JSON.stringify({ owned: own })}') on conflict (user_id) do update set data = excluded.data`);
const set = (mode, uids) => as(`select pvp_set_deck('open','${mode}',0,'${JSON.stringify(uids)}')`);
let r = await set('boss', ['u0']); ok(/boss members/.test(r.err || ''), 'HR 리더 1장만 → 거절 ' + (r.err || ''));
r = await set('boss', ['u0', 'u1']); ok(!r.err, '리더 + 멤버 1장 → 저장 ' + (r.err || ''));
r = await set('boss', ['u0', 'u1', 'u2', 'u3', 'u4', 'u5']); ok(!r.err, '리더 + 멤버 5장 → 저장 ' + (r.err || ''));
const snap = (await db.query(`select snap from pvp_decks where user_id='${U}' and mode='boss'`)).rows[0]?.snap;
ok(snap?.length === 6 && snap[0].id === 't_hr', '스냅샷 6장 · 첫 장 리더');
r = await set('boss', ['u0', 'u1', 'u2', 'u3', 'u4', 'u5', 'u6']); ok(/deck size/.test(r.err || ''), '멤버 6장 → 거절');
r = await set('boss', ['u7', 'u1']); ok(/guard grade/.test(r.err || ''), 'UR 리더 → 거절');
r = await set('boss', ['u0', 'u0']); ok(!!r.err, '같은 카드 중복 → 거절');
r = await set('1v1', ['u0', 'u1', 'u2', 'u3', 'u4', 'u5']); ok(/deck size/.test(r.err || ''), '1v1 6장 → 그대로 거절');
r = await set('1v1', ['u7']); ok(!r.err, '1v1 1장 → 그대로 저장 ' + (r.err || ''));
r = await as(`select pvp_start('open','boss')`); ok(!/deck size|boss members|guard grade/.test(r.err || ''), 'pvp_start 보스 6장 덱 → 덱 검사 통과 ' + (r.err || ''));
console.log(fails ? `${fails} FAIL` : 'ALL PASS'); process.exit(fails ? 1 : 0);
