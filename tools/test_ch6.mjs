// supabase/story_ch6.sql 검증 + 챕터 6 데이터 검사 (PGlite, 실제 스토리·퀘스트 SQL 위에서). 실행: NODE_PATH=<pglite 설치 경로> node tools/test_ch6.mjs
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
await run('phaseE_4.sql'); await run('phaseE_5.sql'); await run('story_ch3.sql'); await run('story_ch4.sql'); await run('story_ch6.sql'); await run('story_ch6.sql');
// --- 데이터 (js/story-data-ch6.js) ---
let fails = 0; const ok = (c, m) => { if (!c) { fails++; console.log('FAIL', m); } else console.log('ok  ', m); };
globalThis.window = { STORY_DATA: { chapters: [] } };
eval(readFileSync(new URL('../js/story-data-ch6.js', import.meta.url), 'utf8'));
const ch = window.STORY_DATA.chapters[0];
const csv = f => Object.fromEntries(readFileSync(new URL('../data/' + f, import.meta.url), 'utf8').replace(/^\uFEFF/, '').trim().split(/\r?\n/).slice(1).map(l => l.split(',')).map(v => [v[0], v]));
const cards = { ...csv('npc_cards.csv'), ...csv('cards.csv') }, nm = id => cards[id]?.[1];
const JA = '10110', JC = '10112', JY = '10111', YR = '10325', P_ = n => ch.phases[n - 1];
ok(ch.id === 6 && ch.subtitle === '마지막 대답' && ch.phases.length === 10 && ch.single && ch.hero === JA && ch.endingVideo === '5UXd2Yv5p3E' && ch.warning, '챕터 6 · 10 페이즈 · 주인공 문지아 · 엔딩 영상 · 경고');
ok(P_(1).enemies.ids.length === 3 && ch.phases.slice(1).every(p => p.enemies.ids.length === 5) && ch.phases.every(p => p.enemies.ids.every(id => nm(id))), '1페이즈 적 3명 · 나머지 5명 · 모두 카드/NPC');
ok(P_(3).enemies.ids.every(id => nm(id) === '불량배-J') && P_(6).enemies.ids.every(id => nm(id) === '불량배-X'), '같은 NPC 여러 명 (J×5, X×5)');
ok(ch.phases.map(p => nm(p.bossId)).join() === '수상한 남자,불량배-D,불량배-J,불량배-U,불량배-X,불량배-X,최진규,곽진영,인창수,임유리', '리더');
const F = ch.phases.map(p => p.party.forced.map(nm).join('+'));
ok(JSON.stringify(F) === JSON.stringify(['문지철+문지예', '문지예', '문지예', '문지예', ...Array(6).fill('문지아')]), `강제 배정 ${F}`);
const EX = ch.phases.map(p => (p.party.exclude || []).map(nm).sort().join('+'));
ok(JSON.stringify(EX) === JSON.stringify(['', '', '', '임유리', '문지예', '문지예+임유리', ...Array(4).fill('문지예+문지철+임유리')]), `출전 금지 ${EX}`);
ok(P_(10).type === 'boss' && P_(10).final && ch.phases.slice(0, 9).every(p => p.type === 'normal') && P_(10).after.at(-1).speaker === '임유리', '10 보스전 · 승리 후 대사(지아 사망)');
const all = [...ch.start, ...ch.phases.flatMap(p => [...p.lines.default, ...(p.after || [])])];
ok(all.every(l => l.speaker && !/^(NA|M\d|[A-Z]{1,2})$/.test(l.speaker)) && all.some(l => l.text.includes('네가 내 동생 죽였냐고')) && !all.some(l => /선그라스|둘러 쌓|감쌓|제가 내 동생/.test(l.text)), '화자 이름 · 맞춤법');
ok(P_(8).lines.default[0].speaker === '문지아', '8페이즈 첫 대사 문지아');
// --- SQL ---
async function as(role, claims, sql) {
  await db.exec(`reset role; select set_config('request.jwt.claims', '${JSON.stringify(claims || {})}', false); set role ${role};`);
  try { return { rows: (await db.query(sql)).rows }; } catch (e) { return { err: e.message }; } finally { await db.exec('reset role'); }
}
const me = { sub: U, email: 'u@x.com' }, q = s => as('authenticated', me, s);
const cfg = (await db.query(`select phase, type, points from public.story_phase_config where chapter = 6 order by phase`)).rows;
ok(cfg.length === 10 && cfg[9].type === 'boss' && cfg[9].points === 5 && cfg[0].points === 3, '페이즈 설정 10개 (멱등)');
await q(`select public.story_choose_starter('10111')`); await q('select public.player_status()');
await db.exec(`update public.player_state set stamina = 200, level = 10 where user_id='${U}'`);
ok(/phase locked/.test((await q('select public.story_start_phase(6, 1)')).err || ''), '챕터 5 미완료 시 잠김');
await db.exec(`update public.story_progress set data = jsonb_set(data, '{cleared}', (select jsonb_object_agg(chapter::text, ps) from (select chapter, jsonb_agg(phase) ps from public.story_phase_config where chapter < 6 group by chapter) x)) where user_id='${U}'`);
let r = await q('select public.story_start_phase(6, 1) r'); ok(!r.err, `챕터 5 완료 후 5-1 시작 (${r.err || ''})`);
await db.exec(`update public.story_progress set data = jsonb_set(data, '{battle,at}', to_jsonb((extract(epoch from now()) - 600)::bigint)) where user_id='${U}'`);
r = await q(`select public.story_complete_phase(6, 1, '[]'::jsonb) r`); const x = r.rows?.[0]?.r;
ok(x && x.first && x.drops && x.player, `6-1 클리어: 첫 클리어·드롭·플레이어 XP (${r.err || ''})`);
await db.exec(`update public.player_state set level = 10, stamina = 100 where user_id='${U}'`);
r = await q('select public.story_sweep(6, 1, 5) r'); ok(r.rows?.[0]?.r?.runs === 5, `6-1 소탕 (${r.err || ''})`);
ok(/phase locked/.test((await q('select public.story_start_phase(6, 3)')).err || ''), '6-3 은 5-2 전 잠김');
ok(/permission denied/.test((await as('anon', {}, 'select public.story_start_phase(6, 1)')).err || ''), 'anon 불가');
console.log(fails ? `${fails} FAIL` : 'ALL OK'); process.exit(fails ? 1 : 0);
