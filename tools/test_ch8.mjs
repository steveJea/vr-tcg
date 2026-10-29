// supabase/story_ch8.sql 검증 + 챕터 8 데이터 검사 (PGlite, 실제 스토리·퀘스트 SQL 위에서). 실행: NODE_PATH=<pglite 설치 경로> node tools/test_ch8.mjs
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
await run('phaseE_4.sql'); await run('phaseE_5.sql'); await run('story_ch3.sql'); await run('story_ch4.sql'); await run('story_ch6.sql'); await run('story_ch7.sql'); await run('story_ch8.sql'); await run('story_ch8.sql');
async function as(role, claims, sql) {
  await db.exec(`reset role; select set_config('request.jwt.claims', '${JSON.stringify(claims || {})}', false); set role ${role};`);
  try { return { rows: (await db.query(sql)).rows }; } catch (e) { return { err: e.message }; } finally { await db.exec('reset role'); }
}
// --- 데이터 (js/story-data-ch8.js) ---
let fails = 0; const ok = (c, m) => { if (!c) { fails++; console.log('FAIL', m); } else console.log('ok  ', m); };
globalThis.window = { STORY_DATA: { chapters: [] } };
eval(readFileSync(new URL('../js/story-data-ch8.js', import.meta.url), 'utf8'));
const ch = window.STORY_DATA.chapters[0];
const csv = f => Object.fromEntries(readFileSync(new URL('../data/' + f, import.meta.url), 'utf8').replace(/^\uFEFF/, '').trim().split(/\r?\n/).slice(1).map(l => l.split(',')).map(v => [v[0], v]));
const cards = { ...csv('npc_cards.csv'), ...csv('cards.csv') }, nm = id => cards[id]?.[1];
const JY = '10231', SR = '10493', P_ = n => ch.phases[n - 1];
ok(ch.id === 8 && ch.subtitle === '주홍글씨' && ch.phases.length === 15 && ch.single && ch.hero === JY, '챕터 8 · 15 페이즈 · 주인공 안지윤');
ok(ch.phases.every((p, i) => p.no === i + 1) && P_(15).type === 'boss' && ch.phases.filter(p => p.type === 'boss').length === 1, '페이즈 1~15 · 마지막만 보스');
ok(ch.phases.every(p => p.enemies.ids.length === 5 && p.enemies.ids.every(id => nm(id))) && P_(15).enemies.ids.every(id => id === '10502') && P_(1).enemies.ids[0] === '10494', '적: 모두 카드 · P1 가해자 부모1 · P15 [염원] 안지윤×5');
ok(ch.phases.every(p => Object.values(p.enemies.boost).every(b => b.HP > 0 && b.storyLv >= 40 && b.storyLv <= 60)), '적 스토리 레벨 40~60');
ok([1, 2, 9, 11].every(n => P_(n).party.forced.join() === SR && P_(n).party.mustLive.join() === SR) && P_(1).party.levels[SR] === 80, '안소라 페이즈 (게스트 Lv80)');
ok([9, 11].every(n => P_(n).party.exclude.join() === JY && !P_(n).party.noMale) && [3, 4, 5, 15].every(n => P_(n).party.noMale && P_(n).party.forced.join() === JY), '출전 조건 (남성 불가 · 안지윤 출전 금지)');
const all = [...ch.start, ...ch.phases.flatMap(p => [...p.lines.default, ...(p.after || [])])];
ok(all.length > 250 && all.every(l => l.speaker && !/^(NA|JY\d?|SR|A\d|C\d|DV\d|[A-Z])$/.test(l.speaker)), `화자 실명 (${all.length}줄)`);
ok(ch.endingVideo === 'hZVw28WEYHY', '엔딩 영상');
ok(all.filter(l => l.image).length === 1 && ch.start.some(l => l.image === 'img/story/ch8-01.webp'), 'CG CH08-01');
const me = { sub: U, email: 'u@x.com' }, q = s => as('authenticated', me, s);
const cfg = (await db.query(`select phase, type, points from public.story_phase_config where chapter = 8 order by phase`)).rows;
ok(cfg.length === 15 && cfg[14].type === 'boss' && cfg[14].points === 5 && cfg[0].points === 3, '페이즈 설정 15개 (멱등)');
await q(`select public.story_choose_starter('10111')`); await q('select public.player_status()');
await db.exec(`update public.player_state set stamina = 999, level = 10 where user_id='${U}'`);
ok(/phase locked/.test((await q('select public.story_start_phase(8, 1)')).err || ''), '챕터 7 미완료 시 잠김');
await db.exec(`update public.story_progress set data = jsonb_set(data, '{cleared}', (select jsonb_object_agg(chapter::text, ps) from (select chapter, jsonb_agg(phase) ps from public.story_phase_config where chapter < 8 group by chapter) x)) where user_id='${U}'`);
const t0 = (await q('select public.story_tickets() r')).rows?.[0]?.r?.tickets | 0;
for (let n = 1; n <= 15; n++) {
  await db.exec(`update public.player_state set stamina = 999 where user_id='${U}'`);
  let r = await q(`select public.story_start_phase(8, ${n}) r`); if (r.err) { ok(false, `8-${n} 시작 (${r.err})`); break; }
  await db.exec(`update public.story_progress set data = jsonb_set(data, '{battle,at}', to_jsonb((extract(epoch from now()) - 600)::bigint)) where user_id='${U}'`);
  r = await q(`select public.story_complete_phase(8, ${n}, '[]'::jsonb) r`); if (!r.rows?.[0]?.r?.first) { ok(false, `8-${n} 클리어 (${r.err || ''})`); break; }
  if (n === 10 || n === 15) ok(true, `8-${n} 클리어 (10 넘는 페이즈)`);
}
const t1 = (await q('select public.story_tickets() r')).rows?.[0]?.r;
ok(t1 && (t1.tickets | 0) - t0 === 10 && t1.chapters?.includes?.(8), `챕터 8 클리어 → 소환권 +10 (${JSON.stringify(t1)})`);
ok(/permission denied/.test((await as('anon', {}, 'select public.story_start_phase(8, 1)')).err || ''), 'anon 불가');
console.log(fails ? `${fails} FAIL` : 'ALL OK'); process.exit(fails ? 1 : 0);
