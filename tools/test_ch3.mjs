// supabase/story_ch3.sql 검증 + 챕터 3 데이터 검사 (PGlite, 실제 스토리·퀘스트 SQL 위에서). 실행: NODE_PATH=<pglite 설치 경로> node tools/test_sweep_sql.mjs
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
await run('phaseE_4.sql'); await run('phaseE_5.sql'); await run('story_ch3.sql'); await run('story_ch3.sql');
let fails = 0; const ok = (c, m) => { if (!c) { fails++; console.log('FAIL', m); } else console.log('ok  ', m); };
// --- 데이터 (js/story-data-ch3.js) ---
globalThis.window = { STORY_DATA: { chapters: [] } };
eval(readFileSync(new URL('../js/story-data-ch3.js', import.meta.url), 'utf8'));
const ch = window.STORY_DATA.chapters[0];
const cards = Object.fromEntries(readFileSync(new URL('../data/cards.csv', import.meta.url), 'utf8').trim().split(/\r?\n/).slice(1).map(l => l.split(',')).map(v => [v[0], v[1]]));
const nm = id => cards[id];
ok(ch.id === 3 && ch.subtitle === 'Just For YOU' && ch.phases.length === 10 && ch.single && nm(ch.hero) === '조윤하', '챕터 3 · 10 페이즈 · 주인공 조윤하');
ok(ch.phases.every(p => p.enemies.ids.length === 5 && p.enemies.ids.every(id => cards[id])), '페이즈마다 적 5명, 모두 카드 있음');
ok(JSON.stringify(ch.phases[9].enemies.ids.map(nm)) === JSON.stringify(['송지은', '송지아', '박성관', '고정태', '소민섭']) && nm(ch.phases[9].bossId) === '소민섭' && ch.phases[9].type === 'boss', '10페이즈 적·보스(L) 소민섭');
ok(ch.phases[6].bossId === undefined && ch.phases[6].enemyName === '적군', '7페이즈 리더 없음');
const F = ch.phases.map(p => p.party.forced.map(nm).join('+'));
ok(JSON.stringify(F) === JSON.stringify(['조윤하', '조윤하', '조윤이', '조윤하', '조윤하', '조윤하', '조윤하+조윤이', '조윤하', '조윤이', '조윤하']), `강제 배정 ${F}`);
const P_ = n => ch.phases[n - 1];
ok(P_(1).party.noMale && P_(2).party.maxMor === 49 && [4, 5, 6].every(n => P_(n).party.exclude.map(nm)[0] === '조윤이') && P_(6).party.maxGrade === 'HIGH RARE' && P_(9).party.maxGrade === 'SUPER RARE', '추가 조건 (남성·MOR·조윤이·등급)');
ok(P_(7).enemyFirst && P_(8).enemyFirst && ch.phases.filter(p => p.enemyFirst).length === 2, '7·8 적 선공');
ok([8, 9, 10].every(n => P_(n).after?.length) && ch.phases.filter(p => p.after).length === 3 && ch.ending?.length && ch.start?.length && ch.tagline, '8·9·10 전투 후 대사 · 시작 · 엔딩');
ok(ch.phases.flatMap(p => p.lines.default).filter(l => l.expr).length > 20 && ch.phases.flatMap(p => p.lines.default).every(l => !l.expr || ['화남', '웃음'].includes(l.expr)), '표정 태그');
// --- SQL ---
async function as(role, claims, sql) {
  await db.exec(`reset role; select set_config('request.jwt.claims', '${JSON.stringify(claims || {})}', false); set role ${role};`);
  try { return { rows: (await db.query(sql)).rows }; } catch (e) { return { err: e.message }; } finally { await db.exec('reset role'); }
}
const me = { sub: U, email: 'u@x.com' }, q = s => as('authenticated', me, s);
const cfg = (await db.query(`select phase, type, points from public.story_phase_config where chapter = 3 order by phase`)).rows;
ok(cfg.length === 10 && cfg[9].type === 'boss' && cfg[9].points === 5 && cfg[0].points === 3, '페이즈 설정 10개 (멱등)');
await q(`select public.story_choose_starter('2000600126')`); await q('select public.player_status()');
await db.exec(`update public.player_state set stamina = 200, level = 10 where user_id='${U}'`);
ok(/phase locked/.test((await q('select public.story_start_phase(3, 1)')).err || ''), '챕터 2 미완료 시 잠김');
await db.exec(`update public.story_progress set data = jsonb_set(data, '{cleared}', (select jsonb_object_agg(chapter::text, ps) from (select chapter, jsonb_agg(phase) ps from public.story_phase_config where chapter < 3 group by chapter) x)) where user_id='${U}'`);
let r = await q('select public.story_start_phase(3, 1) r'); ok(!r.err, `챕터 2 완료 후 3-1 시작 (${r.err || ''})`);
await db.exec(`update public.story_progress set data = jsonb_set(data, '{battle,at}', to_jsonb((extract(epoch from now()) - 600)::bigint)) where user_id='${U}'`);
r = await q(`select public.story_complete_phase(3, 1, '[]'::jsonb) r`); const x = r.rows?.[0]?.r;
ok(x && x.first && x.drops && x.player, `3-1 클리어: 첫 클리어·드롭·플레이어 XP (${r.err || ''})`);
await db.exec(`update public.player_state set level = 10, stamina = 100 where user_id='${U}'`);
r = await q('select public.story_sweep(3, 1, 5) r'); ok(r.rows?.[0]?.r?.runs === 5, `3-1 소탕 (${r.err || ''})`);
ok(/phase locked/.test((await q('select public.story_start_phase(3, 3)')).err || ''), '3-3 은 3-2 전 잠김');
ok(/permission denied/.test((await as('anon', {}, 'select public.story_start_phase(3, 1)')).err || ''), 'anon 불가');
console.log(fails ? `${fails} FAIL` : 'ALL OK'); process.exit(fails ? 1 : 0);
