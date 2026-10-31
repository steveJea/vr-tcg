// supabase/story_ch15.sql 검증 + 챕터 15 데이터 검사 (PGlite, 실제 스토리·퀘스트 SQL 위에서). 실행: NODE_PATH=<pglite 설치 경로> node tools/test_ch15.mjs
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
async function as(role, claims, sql) {
  await db.exec(`reset role; select set_config('request.jwt.claims', '${JSON.stringify(claims || {})}', false); set role ${role};`);
  try { return { rows: (await db.query(sql)).rows }; } catch (e) { return { err: e.message }; } finally { await db.exec('reset role'); }
}
// --- 데이터 ---
let fails = 0; const ok = (c, m) => { if (!c) { fails++; console.log('FAIL', m); } else console.log('ok  ', m); };
globalThis.window = { STORY_DATA: { chapters: [] } };
eval(readFileSync(new URL('../js/story-data.js', import.meta.url), 'utf8')); eval(readFileSync(new URL('../js/story-data-ch15.js', import.meta.url), 'utf8'));
const D = window.STORY_DATA, ch = D.chapters.find(c => c.id === 15), P = n => ch.phases[n - 1];
const csv = f => Object.fromEntries(readFileSync(new URL('../data/' + f, import.meta.url), 'utf8').replace(/^\uFEFF/, '').trim().split(/\r?\n/).slice(1).map(l => l.split(',')).map(v => [v[0], v]));
const cards = { ...csv('npc_cards.csv'), ...csv('cards.csv') };
ok(ch && ch.phases.length === 16 && ch.subtitle === '검은 늪' && ch.hero === '10290', 'CH15 16페이즈 · 제목 · 주인공 윤진아');
ok(ch.phases.every(p => p.enemies.ids.every(id => cards[id])), '적 카드 모두 존재 (평가관 = 임시 불량배-Z)');
ok([25, 80, 80, 80, 80, 60, 59, 80, 80, 120, 80, 59, 80, 120, 80, 150].every((m, i) => ch.phases[i].mana === m), '보유 마나 (P6 60 = 시트)');
ok(P(1).joinAlly?.id === '10406' && P(1).joinAlly.storyLevel === 100 && P(1).party.solo, 'P1 단독 + 1턴 후 최국선 Lv100');
ok(['10383', '10384'].every(x => P(6).party.exclude.includes(x)) && ['10290', '10383'].every(x => P(13).party.exclude.includes(x)), 'P6·P13 둘 다 출전 금지');
ok(P(6).party.levels['10024'] === 80 && P(11).party.levels['10290'] === 83 && P(11).enemies.ids.length === 5 && P(11).enemies.boost['10123'].storyLv === 83, 'P6 Lv80 · P11 Lv83 · 박성관+불량배I×4');
ok([14, 15, 16].every(n => P(n).party.maxGrade === 'HIGH RARE' && P(n).party.noMale), 'P14~16 HR 이하 여성');
ok(P(10).rules.survive === 5 && P(14).rules.survive === 5 && P(16).rules.survive === 10 && P(16).rules.revive[0].id === '10143' && P(16).rules.revive[0].delay === 2 && P(16).enemies.boost['10143'].storyLv === 31 && P(16).party.mustLive.includes('10024') && P(16).final, 'P16 10턴 생존 · 불량배A Lv31 2턴 후 부활');
ok(P(1).starTurns === 10 && P(16).starMana === 0 && P(13).starMana === 0.2, '별점 조건');
const r = { rows: (await db.query("select count(*)::int n, sum(points)::int pts from public.story_phase_config where chapter = 15")).rows };
ok(r.rows[0].n === 16 && r.rows[0].pts === 50, `story_phase_config 15: ${JSON.stringify(r.rows)}`);
const g = await db.query("select public._player_unlock_level('chapter_15') v, public._player_unlock_level('chapter_14') w");
ok(g.rows[0].v === 25 && g.rows[0].w === 24, '입장 레벨 15 = 25');
console.log(fails ? `${fails} FAIL` : 'ALL OK'); process.exit(fails ? 1 : 0);
