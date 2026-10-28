// supabase/story_ch0.sql 검증: 스타터 없이 챕터 0 · 보상 3장 · 기존 사용자 챕터 1 그대로 // (PGlite): 챕터 1 페이즈별 고정 보상 카드, 중복 지급, 재클리어 없음
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
await run('story_ch1_reward.sql'); await run('story_ch0.sql'); await run('story_ch0.sql');
let fails = 0; const ok = (c, m) => { if (!c) { fails++; console.log('FAIL', m); } else console.log('ok  ', m); };
async function as(role, claims, sql) {
  await db.exec(`reset role; select set_config('request.jwt.claims', '${JSON.stringify(claims || {})}', false); set role ${role};`);
  try { return { rows: (await db.query(sql)).rows }; } catch (e) { return { err: e.message }; } finally { await db.exec('reset role'); }
}
const qa = (u, s) => as('authenticated', { sub: u, email: 'x@x.com' }, s);
const age = u => db.exec(`update public.story_progress set data = jsonb_set(data, '{battle,at}', to_jsonb((extract(epoch from now()) - 60)::bigint)) where user_id = '${u}'`);
const W = ['2000100006', '2000100004', '2000900206'];
await qa(U, `select public.player_status()`); await db.exec(`update public.player_state set stamina = 999`);
ok(/locked/.test((await qa(U, `select public.story_start_phase(0,2)`)).err || ''), '0-2 는 0-1 클리어 전 잠김');
for (let ph = 1; ph <= 3; ph++) {
  const s = await qa(U, `select public.story_start_phase(0,${ph}) d`); ok(!s.err, `0-${ph} 스타터 없이 시작 ${s.err || ''}`);
  await age(U); const r = await qa(U, `select public.story_complete_phase(0,${ph},'[]'::jsonb) r`);
  ok(r.rows?.[0]?.r?.reward_id === W[ph - 1], `0-${ph} 보상 ${W[ph - 1]} ${r.err || ''}`);
}
ok(/starter/.test((await qa(U, `select public.story_start_phase(1,1)`)).err || ''), '챕터 1 은 여전히 스타터 필요');
await qa(V, `select public.story_choose_starter('2000600126')`); await db.exec(`update public.player_state set stamina = 999`);
ok(!(await qa(V, `select public.story_start_phase(1,1)`)).err, '기존 사용자: 챕터 0 없이 1-1 시작');
await db.exec(`update public.story_progress set data = jsonb_set(data, '{cleared}', '{"1":[1,2,3,4,5]}') where user_id='${V}'`);
ok(!(await qa(V, `select public.story_start_phase(2,1)`)).err, '기존 사용자: 챕터 1 클리어 → 2-1 (챕터 0 무관)');
ok(!(await qa(V, `select public.story_start_phase(0,1)`)).err, '기존 사용자도 0-1 가능');
await age(V); const r = await qa(V, `select public.story_complete_phase(0,1,'[]'::jsonb) r`); ok(r.rows?.[0]?.r?.reward_id === W[0], '기존 사용자 0-1 첫 클리어 보상 오유나');
await run('story_ch0_pull.sql'); await run('story_ch0_pull.sql');
const tk = await qa(U, `select public.story_tickets() t`); ok(tk.rows?.[0]?.t?.tickets >= 10, `챕터 0 클리어 → 소환권 10 (${JSON.stringify(tk.rows?.[0]?.t)})`);
ok((await qa(U, `select public.story_tickets() t`)).rows[0].t.added === 0, '소환권은 한 번만');
const ms = await qa(U, `select public.story_mark_seen('ch0Pull') d`); ok(ms.rows?.[0]?.d?.ch0Pull === true, 'ch0Pull 표시 저장');
ok(/invalid key/.test((await qa(U, `select public.story_mark_seen('foo')`)).err || ''), '다른 키는 거부');
const dr = await qa(U, `select public.story_ticket_draw(10) r`); ok(dr.rows?.[0]?.r?.ok && dr.rows[0].r.cards.length === 10, `스타터 없이 10회 영입 ${dr.err || ''}`);
console.log(fails ? `${fails} FAILED` : 'ALL PASS'); process.exit(fails ? 1 : 0);
