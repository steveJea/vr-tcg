// supabase/gear_snap.sql 검증 (PGlite): PvP·토벌·세력전 스냅샷에 장착 장비·증표가 붙는지
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
await run('gem.sql'); await run('gear_v1.sql'); await run('gear_v1.sql');   // 두 번 실행해도 안전
await run('gem.sql'); await run('gear_v1.sql'); await run('gear_snap.sql'); await run('gear_snap.sql');   // 두 번 실행해도 안전
let fails = 0; const ok = (c, m) => { if (!c) { fails++; console.log('FAIL', m); } else console.log('ok  ', m); };
await db.exec(`insert into pvp_card_meta (id, grade, cost) values ('1000100007','SUPER RARE',43),('2000100001','ULTRA RARE',50) on conflict do nothing`);
await db.exec(`insert into story_progress (user_id, data) values ('${U}','{"owned":[{"uid":"a","id":"1000100007","level":5},{"uid":"b","id":"2000100001"}]}') on conflict (user_id) do update set data = excluded.data`);
const g = (await db.query(`select public._gear_grant('${U}','weapon_4_2','test') r`)).rows[0].r.gear_id;
await db.exec(`update player_gear set equipped_card='1000100007', plus=2 where id=${g}; insert into player_sigils (user_id, card_id, plus, frags) values ('${U}','1000100007',4,0),('${U}','2000100001',null,12)`);
const s = (await db.query(`select public._pvp_snap('${U}', '["a","b"]'::jsonb, 'open') r`)).rows[0].r.cards;
ok(s[0].gear.length === 1 && s[0].gear[0].def === 'weapon_4_2' && s[0].gear[0].stat === 'atk' && +s[0].gear[0].pct === 8 && s[0].gear[0].plus === 2, '장착 장비가 스냅샷에');
ok(s[0].sigil === 4, '증표 단계 4');
ok(s[1].gear.length === 0 && s[1].sigil === null, '장비 없음·증표 미제작 → 빈 값');
ok(s[0].level === 5 && s[0].uid === 'a', '기존 필드 유지');
let e = null; try { await db.query(`select public._pvp_snap('${U}', '["zz"]'::jsonb, 'open')`); } catch (x) { e = x.message; } ok(/not owned/.test(e || ''), '기존 검사 유지');
console.log(fails ? `\n${fails} FAIL` : '\nALL OK'); process.exit(fails ? 1 : 0);
