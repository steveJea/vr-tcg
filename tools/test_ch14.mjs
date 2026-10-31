// supabase/story_ch14.sql 검증 + 챕터 14 데이터 검사 (PGlite, 실제 스토리·퀘스트 SQL 위에서). 실행: NODE_PATH=<pglite 설치 경로> node tools/test_ch14.mjs
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
await run('phaseE_4.sql'); await run('phaseE_5.sql'); await run('story_ch3.sql'); await run('story_ch4.sql'); await run('story_ch6.sql'); await run('story_ch7.sql'); await run('story_ch8.sql'); await run('story_ch9_11.sql'); await run('story_ch9_11.sql'); await run('story_ch10_rev.sql'); await run('story_ch11_wings.sql'); await run('story_ch11_p1_5.sql'); await run('story_level_gate.sql'); await run('story_ch12.sql'); await run('story_ch13.sql'); await run('story_ch14.sql'); await run('story_ch14.sql');
async function as(role, claims, sql) {
  await db.exec(`reset role; select set_config('request.jwt.claims', '${JSON.stringify(claims || {})}', false); set role ${role};`);
  try { return { rows: (await db.query(sql)).rows }; } catch (e) { return { err: e.message }; } finally { await db.exec('reset role'); }
}
// --- 데이터 ---
let fails = 0; const ok = (c, m) => { if (!c) { fails++; console.log('FAIL', m); } else console.log('ok  ', m); };
globalThis.window = { STORY_DATA: { chapters: [] } };
eval(readFileSync(new URL('../js/story-data.js', import.meta.url), 'utf8')); eval(readFileSync(new URL('../js/story-data-ch14.js', import.meta.url), 'utf8'));
const D = window.STORY_DATA, ch = D.chapters.find(c => c.id === 14), P = n => ch.phases[n - 1];
const csv = f => Object.fromEntries(readFileSync(new URL('../data/' + f, import.meta.url), 'utf8').replace(/^\uFEFF/, '').trim().split(/\r?\n/).slice(1).map(l => l.split(',')).map(v => [v[0], v]));
const cards = { ...csv('npc_cards.csv'), ...csv('cards.csv') };
ok(ch && ch.phases.length === 18 && ch.subtitle === '작은 아씨들' && ch.endingVideo === 'FzaL3RXwWNU' && ch.hero === '10317', 'CH14 18페이즈 · 제목 · 엔딩 · 주인공 이혜경');
ok(ch.phases.every(p => p.enemies.ids.every(id => cards[id])), '적 카드 모두 존재');
ok([80, 80, 80, 80, 80, 80, 89, 67, 67, 67, 67, 67, 100, 150, 67, 67, 90, 90].every((m, i) => ch.phases[i].mana === m), '보유 마나 (P8 67 · P14 150 = 시트)');
ok(P(5).rules.survive === 2 && P(14).rules.survive === 5 && !P(18).rules, 'P5 2턴 생존 · P14 5턴 생존(또는 전멸) · P18 전멸');
ok(P(13).party.forced.length === 0 && P(13).enemies.boost['10504'].storyLv === 85, 'P13 필수 없음 · 날개 Lv85');
ok(P(5).party.exclude.includes('10312') && P(6).party.mustLive.includes('10317') && P(6).party.levels['10317'] === 78, 'P5 이진경 출전 불가 · P6 이혜경 Lv78');
ok(P(17).party.maxGrade === 'SUPER RARE' && P(17).party.exclude.includes('10317') && P(18).final, 'P17·18 UR 금지 · 이혜경 금지');
const sp = new Set(ch.phases.flatMap(p => [...p.lines.default, ...(p.after || [])]).map(L => L.speaker));
ok(sp.has('아빠') && !sp.has('윤희 아버지') && ![...sp].some(s => s.includes('염원')), '아빠 = 진경 아빠 (윤희 아버지 X)');
ok(D.exprMap?.['당황'] === 'surprised' || JSON.stringify(D).includes('"당황":"surprised"'), '당황 → surprised');
ok(P(14).starTurns === 5 && P(14).starMana === 0 && P(18).starTurns === 10, '별점 조건');
const r = { rows: (await db.query("select count(*)::int n, sum(points)::int pts from public.story_phase_config where chapter = 14")).rows };
ok(r.rows[0].n === 18 && r.rows[0].pts === 56, `story_phase_config 14: ${JSON.stringify(r.rows)}`);
const g = await db.query("select public._player_unlock_level('chapter_14') v, public._player_unlock_level('chapter_13') w");
ok(g.rows[0].v === 24 && g.rows[0].w === 23, '입장 레벨 14 = 24');
console.log(fails ? `${fails} FAIL` : 'ALL OK'); process.exit(fails ? 1 : 0);
