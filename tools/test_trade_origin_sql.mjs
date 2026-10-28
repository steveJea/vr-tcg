// supabase/trade_origin.sql 검증 (PGlite): 새 인재 출처·귀속 스탬프 + 기존 보유분 소급 + 재실행 안전
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
for (const f of ['story.sql', 'gacha.sql', 'story_server.sql', 'story_gacha.sql', 'story_levels.sql', 'story_merge.sql', 'story_ch2.sql', 'story_cards_1022.sql', 'story_leader_lock.sql', 'story_level_stats.sql', 'story_min_battle.sql', 'admin.sql', 'phaseE_1.sql', 'phaseE_2.sql', 'pvp.sql', 'pvp_tier.sql', 'story_ch1_reward.sql']) await run(f);

const sv = async s => Object.values((await db.query(s)).rows[0])[0];
let fails = 0; const ok = (c, m) => { if (!c) { fails++; console.log('FAIL', m); } else console.log('ok  ', m); };
const as = async (sub, sql) => { await db.exec(`reset role; select set_config('request.jwt.claims', '${JSON.stringify({ sub })}', false); set role authenticated;`); try { return (await db.query(sql)).rows[0]; } catch (e) { return { err: e.message }; } finally { await db.exec('reset role'); } };
// 기존 보유분: U = 시작 인재 10462 ×1, 10325(임유리) ×1, 영입 기록 있는 A ×3 (기록 2), 기록 없는 B ×1, 페이즈 0-1 보상 10256 ×2 (기록 1)
const own = (id, n) => Array.from({ length: n }, (_, k) => ({ uid: id + '_' + k, id, level: 1 }));
const owned = [...own('10462', 1), ...own('10325', 1), ...own('A', 3), ...own('B', 1), ...own('10256', 2)];
await db.query(`insert into story_progress (user_id, data) values ($1, $2)`, [U, JSON.stringify({ starter: '10462', cleared: { 1: [1] }, owned })]);
await db.exec(`update story_phase_config set reward_card = '10256' where chapter = 1 and phase = 1;
insert into story_gacha_log (user_id, card_id, grade) values ('${U}','A','R'),('${U}','A','R'),('${U}','10256','R'),('${U}','B','R'),('${U}','B','R');
update story_gacha_log set card_id = 'Z' where card_id = 'B';`);
await run('trade_origin.sql'); await run('trade_origin.sql'); await run('trade_origin_v2.sql'); await run('trade_origin_v2.sql');
const rows = (await db.query(`select o->>'id' id, o->>'src' src, (o->>'bound')::bool bound from story_progress, jsonb_array_elements(data->'owned') o where user_id = '${U}'`)).rows;
const cnt = (id, src) => rows.filter(r => r.id === id && r.src === src).length;
ok(cnt('10462', 'starter') === 1 && cnt('10325', 'story') === 1, '시작 인재 → starter(거래 가능), 임유리 → story 귀속');
ok(cnt('A', 'recruit_backfill') === 2 && cnt('A', 'unknown') === 1, '영입 기록 2건 → 2장만 거래 가능, 나머지 1장 unknown(거래 가능)');
ok(cnt('B', 'unknown') === 1, '영입 기록 없음 → unknown(거래 가능)');
ok(cnt('10256', 'story') === 1 && cnt('10256', 'recruit_backfill') === 1, '챕터 보상 1장 story, 영입 기록 1건분 거래 가능');
ok(rows.every(r => r.bound === (r.src === 'story')), 'bound = story 만 true');
ok(rows.length === 8, '재실행해도 개수·출처 그대로');
// 새 경로
await db.query(`insert into story_progress (user_id, data) values ($1, '{}')`, [V]);
const st = await as(V, `select story_choose_starter('10111') r`);
const dd = await as(V, `select story_daily_draw() r`);
const vr = (await db.query(`select o->>'src' src, (o->>'bound')::bool bound, o ? 'got_at' g from story_progress, jsonb_array_elements(data->'owned') o where user_id = '${V}'`)).rows;
console.log('  starter', JSON.stringify(st).slice(0, 80), 'daily', JSON.stringify(dd).slice(0, 80));
ok(vr.some(r => r.src === 'starter' && !r.bound && r.g), '시작 인재 선택 → starter 거래 가능 + got_at');
ok(vr.some(r => r.src === 'recruit' && !r.bound), '일일 영입 → recruit 거래 가능');
ok(await sv(`select (public._story_new_card('X')->>'src')`) === 'other' && await sv(`select (public._story_new_card('X')->>'bound')`) === 'false', '모르는 경로 → other 거래 가능');
const anon = await as(U, `select public._trade_origin_backfill('${U}') r`);
ok(!!anon.err, '소급 함수는 클라이언트에서 호출 불가');
console.log(fails ? `${fails} FAIL` : 'ALL OK'); process.exit(fails ? 1 : 0);
