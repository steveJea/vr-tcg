// supabase/story_ch12.sql 검증 + 챕터 12 데이터 검사 (PGlite, 실제 스토리·퀘스트 SQL 위에서). 실행: NODE_PATH=<pglite 설치 경로> node tools/test_ch12.mjs
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
await run('phaseE_4.sql'); await run('phaseE_5.sql'); await run('story_ch3.sql'); await run('story_ch4.sql'); await run('story_ch6.sql'); await run('story_ch7.sql'); await run('story_ch8.sql'); await run('story_ch9_11.sql'); await run('story_ch9_11.sql'); await run('story_ch10_rev.sql'); await run('story_ch11_wings.sql'); await run('story_ch11_p1_5.sql'); await run('story_level_gate.sql'); await run('story_ch12.sql'); await run('story_ch12.sql');
async function as(role, claims, sql) {
  await db.exec(`reset role; select set_config('request.jwt.claims', '${JSON.stringify(claims || {})}', false); set role ${role};`);
  try { return { rows: (await db.query(sql)).rows }; } catch (e) { return { err: e.message }; } finally { await db.exec('reset role'); }
}
// --- 데이터 ---
let fails = 0; const ok = (c, m) => { if (!c) { fails++; console.log('FAIL', m); } else console.log('ok  ', m); };
globalThis.window = { STORY_DATA: { chapters: [] } };
eval(readFileSync(new URL('../js/story-data.js', import.meta.url), 'utf8')); eval(readFileSync(new URL('../js/story-data-ch12.js', import.meta.url), 'utf8'));
const D = window.STORY_DATA, ch = D.chapters.find(c => c.id === 12);
const csv = f => Object.fromEntries(readFileSync(new URL('../data/' + f, import.meta.url), 'utf8').replace(/^\uFEFF/, '').trim().split(/\r?\n/).slice(1).map(l => l.split(',')).map(v => [v[0], v]));
const cards = { ...csv('npc_cards.csv'), ...csv('cards.csv') };
ok(ch && ch.phases.length === 21 && ch.subtitle === '위대한 개츠비' && ch.endingVideo === '_h0XmAQsVeY' && ch.hero === '10072', 'CH12 21페이즈 · 제목 · 엔딩 · 주인공 김지수');
ok(ch.phases.every(p => p.enemies.ids.every(id => cards[id])), '적 카드 모두 존재');
const P = n => ch.phases[n - 1];
ok(P(1).party.costBelow === 35 && P(5).party.costBelow === 40 && P(6).party.costBelow === 45, '코스트 제한');
ok(P(7).party.solo && P(7).party.forced[0] === '10505', 'P7 안혜진 단독');
ok(P(12).party.maxGrade === 'SUPER RARE' && P(16).party.maxGrade === 'HIGH RARE' && P(14).party.noMale, '등급·남성 제한');
ok(P(13).rules?.maxTurns === 6, 'P13 총 6턴');
ok(P(20).rules?.survive === 10 && P(20).rules.blind['10072'] === 0.4 && P(20).enemies.ids.length === 3, 'P20 10턴 생존 · 김지수 명중 -40% · 염원 이민채 3');
ok(P(21).type === 'normal' && P(21).final && Object.values(P(21).enemies.boost).every(b => b.storyLv === 91), 'P21 일반 전투 Lv91 · 마지막');
const sp = new Set(ch.phases.flatMap(p => [...p.lines.default, ...(p.after || [])]).concat(ch.start).map(L => L.speaker));
for (const n of ['김지수', '루비에르 회장 김정란', '김지우', '안지수', '안혜진', '한서린', '도예나', '최태석']) if (sp.has(n)) { const s = D.chapterPortraits[12][n]; ok(s && ['base', 'playful', 'angry', 'sad', 'surprised', 'hurt'].every(x => { try { readFileSync(new URL(`../img/story/portraits/${s}_${x}.webp`, import.meta.url)); return true; } catch { return false; } }), `초상화 ${n} → ${s}`); }
// --- SQL ---
const r = { rows: (await db.query("select count(*)::int n, sum(points)::int pts from public.story_phase_config where chapter = 12")).rows };
ok(r.rows?.[0]?.n === 21 && r.rows[0].pts === 65, `story_phase_config 12: ${JSON.stringify(r.rows || r.err)}`);
const g = await db.query("select public._player_unlock_level('chapter_12') v, public._player_unlock_level('chapter_11') w");
ok(g.rows[0].v === 22 && g.rows[0].w === 21, '입장 레벨 12 = 22');
console.log(fails ? `${fails} FAIL` : 'ALL OK'); process.exit(fails ? 1 : 0);
