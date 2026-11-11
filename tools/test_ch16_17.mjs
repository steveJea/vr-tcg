// supabase/story_ch16_17.sql 검증 + 챕터 16·17 데이터 검사 (PGlite). 실행: NODE_PATH=<pglite 설치 경로> node tools/test_ch16_17.mjs
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
await run('phaseE_4.sql'); await run('phaseE_5.sql'); await run('story_ch3.sql'); await run('story_ch4.sql'); await run('story_ch6.sql'); await run('story_ch7.sql'); await run('story_ch8.sql'); await run('story_ch9_11.sql'); await run('story_ch9_11.sql'); await run('story_ch10_rev.sql'); await run('story_ch11_wings.sql'); await run('story_ch11_p1_5.sql'); await run('story_level_gate.sql'); await run('story_ch12.sql'); await run('story_ch13.sql'); await run('story_ch14.sql'); await run('story_ch15.sql'); await run('story_ch15.sql');
// story_ch16_17.sql 가드: PGlite system_identifier 가 스테이징이 아니므로 가드만 우회한 복사본을 실행
const sql16 = readFileSync(new URL('../supabase/story_ch16_17.sql', import.meta.url), 'utf8')
  .replaceAll("is distinct from '7703759698107299042'", "is distinct from (select system_identifier::text from pg_catalog.pg_control_system())");
await db.exec(sql16);
let fails = 0; const ok = (c, m) => { if (!c) { fails++; console.log('FAIL', m); } else console.log('ok  ', m); };
globalThis.window = { STORY_DATA: { chapters: [] } };
eval(readFileSync(new URL('../js/story-data.js', import.meta.url), 'utf8'));
eval(readFileSync(new URL('../js/story-data-ch16.js', import.meta.url), 'utf8'));
eval(readFileSync(new URL('../js/story-data-ch17.js', import.meta.url), 'utf8'));
const D = window.STORY_DATA, ch16 = D.chapters.find(c => c.id === 16), ch17 = D.chapters.find(c => c.id === 17);
const P = (ch, n) => ch.phases[n - 1];
const csv = f => Object.fromEntries(readFileSync(new URL('../data/' + f, import.meta.url), 'utf8').replace(/^\uFEFF/, '').trim().split(/\r?\n/).slice(1).map(l => l.split(',')).map(v => [v[0], v]));
const cards = { ...csv('npc_cards.csv'), ...csv('cards.csv') };
ok(ch16 && ch16.phases.length === 12 && ch16.subtitle === '젊은 베르테르의 슬픔' && ch16.hero === '10406' && ch16.endingVideo === 'Hr8_z9yFB_g', 'CH16 12페이즈 · 제목 · 주인공 최국선 · 엔딩 영상');
ok(ch17 && ch17.phases.length === 15 && ch17.subtitle === '폭풍의 언덕' && ch17.hero === '10307' && ch17.endingVideo === 'jhBi0xojOOM', 'CH17 15페이즈 · 제목 · 주인공 이영하 · 엔딩 영상');
ok([...ch16.phases, ...ch17.phases].filter(p => !p.scene).every(p => p.enemies.ids.every(id => cards[id])), '전투 페이즈 적 카드 모두 존재');
ok(P(ch16, 1).enemies.ids[0] === '10514' && P(ch16, 11).enemies.ids.includes('10306') && P(ch16, 11).party.forced[0] === '10200', '16-1 강두식 · 16-11 이영아(10306) · 필수 소민섭');
ok(P(ch16, 11).enemies.ids.length === 6 && P(ch16, 11).rules.revive[0].become === '10291', '16-11 적 6명 · 윤진아 사망 시 [각성] 윤진아');
ok(P(ch16, 6).party.solo && P(ch16, 6).party.forced.join() === '10123,10025,10183' && P(ch16, 12).scene, '16-6 빈소 필수 3인 단독 · 16-12 스토리 페이즈');
ok(P(ch16, 1).party.noFemale && P(ch16, 1).party.maxGrade === 'SUPER RARE' && P(ch16, 1).mana === 100, '16-1 여성 금지 · SR 이하 · 마나 100');
ok(ch16.phases.some(p => (p.lines.default || []).some(L => L.slug === 'jo_yuni_school')), '조윤이 ch16 교복 slug');
ok(P(ch17, 1).party.noMale && P(ch17, 1).party.maxGrade === 'SUPER RARE' && P(ch17, 14).enemyFirst && P(ch17, 14).awaken?.id === '10311' && P(ch17, 14).party.mustLive[0] === '10311', '17-1 남성 금지 · 17-14 적 선공 · 이지영 난입/생존');
ok(P(ch17, 7).scene && P(ch17, 12).scene && P(ch17, 15).scene && P(ch17, 15).final, '17-7·12·15 스토리 페이즈 · 15가 마지막');
ok(ch17.phases.some(p => (p.lines.default || []).some(L => L.slug === 'choi_yunhee_school')), '최윤희 ch17 교복 slug');
ok([1, 6, 11].every(n => P(ch16, n).mana === (n === 6 || n === 11 ? 200 : 100)), 'CH16 마나 100/200');
const r16 = (await db.query("select count(*)::int n, sum(points)::int pts, sum(enemy_count)::int enc from public.story_phase_config where chapter = 16")).rows[0];
const r17 = (await db.query("select count(*)::int n, sum(points)::int pts, sum(enemy_count)::int enc from public.story_phase_config where chapter = 17")).rows[0];
ok(r16.n === 12 && r16.pts === 36, `story_phase_config 16: ${JSON.stringify(r16)}`);
ok(r17.n === 15 && r17.pts === 45, `story_phase_config 17: ${JSON.stringify(r17)}`);
ok((await db.query("select enemy_count from public.story_phase_config where chapter=16 and phase=12")).rows[0].enemy_count === 0, '16-12 enemy_count=0');
// 2026-11-08 해금 정책 보호: CH16/17 SQL은 _player_unlock_level 을 다시 만들지 않는다 (챕터 레벨 벽 없음).
const chSrc = readFileSync(new URL('../supabase/story_ch16_17.sql', import.meta.url), 'utf8');
ok(!/create\s+or\s+replace\s+function\s+public\._player_unlock_level\s*\(/i.test(chSrc), 'story_ch16_17.sql 이 _player_unlock_level 을 재정의하지 않음');
const lu = readFileSync(new URL('../supabase/level_unlocks_staging.sql', import.meta.url), 'utf8').match(/create or replace function public\._player_unlock_level\(p_key text\)[\s\S]*?\n\$\$;/)[0];
await db.exec(lu); await db.exec(sql16);
const g = await db.query("select public._player_unlock_level('chapter_16') a, public._player_unlock_level('chapter_17') b, public._player_unlock_level('skill') s, public._player_unlock_level('equip') e");
ok(g.rows[0].a === 1 && g.rows[0].b === 1 && g.rows[0].s === 13 && g.rows[0].e === 3, '재실행 후에도 11-08 정책 유지 (챕터 1 · 스킬 13 · 장비 3)');
console.log(fails ? `${fails} FAIL` : 'ALL OK'); process.exit(fails ? 1 : 0);
