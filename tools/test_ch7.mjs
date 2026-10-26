// supabase/story_ch7.sql 검증 + 챕터 7 데이터 검사 (PGlite, 실제 스토리·퀘스트 SQL 위에서). 실행: NODE_PATH=<pglite 설치 경로> node tools/test_ch7.mjs
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
await run('phaseE_4.sql'); await run('phaseE_5.sql'); await run('story_ch3.sql'); await run('story_ch4.sql'); await run('story_ch6.sql'); await run('story_ch7.sql'); await run('story_ch7.sql');
// --- 데이터 (js/story-data-ch7.js) ---
let fails = 0; const ok = (c, m) => { if (!c) { fails++; console.log('FAIL', m); } else console.log('ok  ', m); };
globalThis.window = { STORY_DATA: { chapters: [] } };
eval(readFileSync(new URL('../js/story-data-ch7.js', import.meta.url), 'utf8'));
const ch = window.STORY_DATA.chapters[0];
const csv = f => Object.fromEntries(readFileSync(new URL('../data/' + f, import.meta.url), 'utf8').replace(/^\uFEFF/, '').trim().split(/\r?\n/).slice(1).map(l => l.split(',')).map(v => [v[0], v]));
const npc = csv('npc_cards.csv'), cards = { ...npc, ...csv('cards.csv') }, nm = id => cards[id]?.[1];
const YY = '2000100008', GE = '2000000040', HK = '1000100007', YW = '2000000045', P_ = n => ch.phases[n - 1];
ok(ch.id === 7 && ch.subtitle === 'THE BELL JAR' && ch.phases.length === 10 && ch.single && ch.hero === YY && ch.endingVideo === '0aHko1s4-tA' && ch.warning, '챕터 7 · 10 페이즈 · 주인공 민유연 · 엔딩 영상 · 경고');
ok(['2000000041', '2000000042', '2000000043', '2000000044', YW].every(id => npc[id] && npc[id][16] === '1' && +npc[id][8] > 0 && +npc[id][15] > 0), '신규 NPC 5장 (소녀1~4 · [염원] 민유연) power/cost');
ok(ch.phases.every(p => p.enemies.ids.every(id => nm(id))) && P_(6).enemies.ids.length === 1 && P_(7).enemies.ids.length === 4 && P_(10).enemies.ids.every(id => id === YW), '적: 모두 카드/NPC · 6페이즈 유가을 1명 · 10페이즈 [염원] 민유연×5');
ok(ch.phases.every(p => Object.keys(p.enemies.boost).length && Object.values(p.enemies.boost).every(b => b.HP > 0 && b.storyLv >= (p.no === 6 ? 30 : 40))) && P_(6).enemies.boost['2000000040'].storyLv === 30, '적 스토리 레벨 boost (40~60 · 6페이즈 유가을 30)');
ok(P_(1).party.noMale && P_(8).party.noFemale && P_(6).party.max === 3 && P_(6).party.maxGrade === 'SUPER RARE' && P_(7).party.noFemale && P_(7).party.maxMor === 39 && !P_(7).party.noExtra && P_(7).party.max === 5 && P_(7).party.forced.length === 4, '출전 조건 (남/여 금지 · 최대 3명 · UR↑ 금지 · 7페이즈 4인방 필수 + MOR 40 미만 남성 1장)');
ok(P_(5).party.forced.join() === GE && P_(5).party.exclude.includes(YY) && P_(9).party.exclude.sort().join() === [GE, HK].sort().join() && P_(10).party.exclude.includes(HK), '필수·출전 금지');
ok(P_(1).party.mustLive.join() === YY && P_(5).party.mustLive.join() === GE && P_(6).party.mustLive.length === 0 && P_(7).party.mustLive.length === 0, '패배 조건 (YY/GE 사망 · 6·7페이즈 전멸만)');
const all = [...ch.start, ...ch.phases.flatMap(p => [...p.lines.default, ...(p.after || [])])];
ok(all.every(l => l.speaker && !/^(NA|YY2?|GE|HK|TA|TJ|MS|CM|[A-Z])$/.test(l.speaker)), '화자 실명 (약어 없음)');
ok(all.filter(l => l.image || l.video).length === 16 && all.some(l => l.video === 'video/story/ch7-15.mp4'), '멀티미디어 16개 (영상 1)');
ok(!all.some(l => l.expr === '징닌') && all.filter(l => l.expr).length > 90, '표정 반영');
const sk = JSON.parse(readFileSync(new URL('../data/skills.json', import.meta.url), 'utf8'))[YW];
ok(sk?.[0]?.name === '제발...살려줘...' && sk[0].mp === 30 && sk[0].cooldown === 3, '[염원] 민유연 스킬');
// --- SQL ---
async function as(role, claims, sql) {
  await db.exec(`reset role; select set_config('request.jwt.claims', '${JSON.stringify(claims || {})}', false); set role ${role};`);
  try { return { rows: (await db.query(sql)).rows }; } catch (e) { return { err: e.message }; } finally { await db.exec('reset role'); }
}
const me = { sub: U, email: 'u@x.com' }, q = s => as('authenticated', me, s);
const cfg = (await db.query(`select phase, type, points from public.story_phase_config where chapter = 7 order by phase`)).rows;
ok(cfg.length === 10 && cfg[9].type === 'boss' && cfg[9].points === 5 && cfg[0].points === 3, '페이즈 설정 10개 (멱등)');
await q(`select public.story_choose_starter('2000600126')`); await q('select public.player_status()');
await db.exec(`update public.player_state set stamina = 200, level = 10 where user_id='${U}'`);
ok(/phase locked/.test((await q('select public.story_start_phase(7, 1)')).err || ''), '챕터 6 미완료 시 잠김');
await db.exec(`update public.story_progress set data = jsonb_set(data, '{cleared}', (select jsonb_object_agg(chapter::text, ps) from (select chapter, jsonb_agg(phase) ps from public.story_phase_config where chapter < 7 group by chapter) x)) where user_id='${U}'`);
let r = await q('select public.story_start_phase(7, 1) r'); ok(!r.err, `챕터 6 완료 후 7-1 시작 (${r.err || ''})`);
await db.exec(`update public.story_progress set data = jsonb_set(data, '{battle,at}', to_jsonb((extract(epoch from now()) - 600)::bigint)) where user_id='${U}'`);
r = await q(`select public.story_complete_phase(7, 1, '[]'::jsonb) r`); const x = r.rows?.[0]?.r;
ok(x && x.first && x.drops && x.player, `7-1 클리어: 첫 클리어·드롭·플레이어 XP (${r.err || ''})`);
await db.exec(`update public.player_state set level = 10, stamina = 100 where user_id='${U}'`);
r = await q('select public.story_sweep(7, 1, 5) r'); ok(r.rows?.[0]?.r?.runs === 5, `7-1 소탕 (${r.err || ''})`);
ok(/phase locked/.test((await q('select public.story_start_phase(7, 3)')).err || ''), '7-3 은 7-2 전 잠김');
ok(/permission denied/.test((await as('anon', {}, 'select public.story_start_phase(7, 1)')).err || ''), 'anon 불가');
console.log(fails ? `${fails} FAIL` : 'ALL OK'); process.exit(fails ? 1 : 0);
