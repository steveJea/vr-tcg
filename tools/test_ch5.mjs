// supabase/story_ch5.sql 검증 + 챕터 5 데이터 검사 (PGlite, 실제 스토리·퀘스트 SQL 위에서). 실행: NODE_PATH=<pglite 설치 경로> node tools/test_ch5.mjs
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
await run('phaseE_4.sql'); await run('phaseE_5.sql'); await run('story_ch3.sql'); await run('story_ch4.sql'); await run('story_ch5.sql'); await run('story_ch5.sql');
// --- 데이터 (js/story-data-ch5.js) ---
let fails = 0; const ok = (c, m) => { if (!c) { fails++; console.log('FAIL', m); } else console.log('ok  ', m); };
globalThis.window = { STORY_DATA: { chapters: [] } };
eval(readFileSync(new URL('../js/story-data-ch5.js', import.meta.url), 'utf8'));
const ch = window.STORY_DATA.chapters[0];
const csv = f => Object.fromEntries(readFileSync(new URL('../data/' + f, import.meta.url), 'utf8').replace(/^\uFEFF/, '').trim().split(/\r?\n/).slice(1).map(l => l.split(',')).map(v => [v[0], v]));
const cards = { ...csv('npc_cards.csv'), ...csv('cards.csv') }, nm = id => cards[id]?.[1];
const GW = '2000600116', HR = '2001900347', AY = '2000600129', SY = '2000600128';
ok(ch.id === 5 && ch.subtitle === '영원히 멈추지 않는 비' && ch.phases.length === 10 && ch.single && ch.hero === GW, '챕터 5 · 10 페이즈 · 주인공 한겨울');
ok(ch.phases.every(p => p.enemies.ids.length === 5 && p.enemies.ids.every(id => nm(id))), '페이즈마다 적 5명, 모두 카드 있음');
const P_ = n => ch.phases[n - 1];
const F = ch.phases.map(p => p.party.forced.map(nm).join('+'));
ok(JSON.stringify(F) === JSON.stringify([...Array(9).fill('한겨울'), '진하린']), `강제 배정 ${F}`);
ok(P_(7).party.banClass?.join() === 'DARK' && P_(8).party.banClass?.join() === 'LIGHT' && [9, 10].every(n => P_(n).party.maxGrade === 'SUPER RARE') && [1, 2, 3, 4, 5, 6].every(n => !P_(n).party.banClass && !P_(n).party.maxGrade), '7 어둠 불가 · 8 빛 불가 · 9~10 UR 불가');
ok(P_(10).type === 'boss' && P_(10).final && P_(10).bossId === AY && P_(10).rules.undying[0] === SY && ch.phases.slice(0, 9).every(p => p.type === 'normal'), '10 보스전(본진 파괴) 리더 정아영 · 정서영 불사');
ok(P_(3).bossId === AY && P_(3).enemies.boost[AY].HP > 89 && P_(10).enemies.boost[AY].ATK > 12, '정아영 스토리 전용 능력치');
ok(ch.phases.map(p => nm(p.bossId)).join() === '남다윤,허진서,정아영,노정아,오채원,황보재규,불량배-H,불량배-H,서오성,정아영', '리더(L)');
ok(P_(10).party.exclude?.includes(GW) && ch.warning && !ch.start.some(l => l.text === ch.tagline) && ch.phases.flatMap(p => [...p.lines.default, ...(p.after || [])]).every(l => l.speaker !== 'NA' && !/환락가|몸으로 떼|떼우/.test(l.text)), '10 한겨울 출전 불가 · 경고 문구 · NA→내레이션 · 수위 조정');
ok(window.STORY_DATA.noPortrait.includes('겨울 친구') && ch.phases.some(p => p.lines.default.some(l => l.speaker === '겨울 친구')), '겨울 친구: 이름만');
ok([3, 9, 10].every(n => P_(n).after?.length) && ch.ending?.length && ch.start?.length && ch.tagline, '전투 후 대사 · 시작 · 엔딩');
ok(ch.phases.flatMap(p => p.lines.default).filter(l => l.expr).length > 20 && ch.phases.flatMap(p => p.lines.default).every(l => !l.expr || ['화남', '웃음'].includes(l.expr)), '표정 태그');
ok(/5: 'US-L-am2Tws'/.test(readFileSync(new URL('../js/story.js', import.meta.url), 'utf8').match(/ENDING_VIDEO = \{[^}]*\}/)[0]), '엔딩 영상 US-L-am2Tws');
// --- SQL ---
async function as(role, claims, sql) {
  await db.exec(`reset role; select set_config('request.jwt.claims', '${JSON.stringify(claims || {})}', false); set role ${role};`);
  try { return { rows: (await db.query(sql)).rows }; } catch (e) { return { err: e.message }; } finally { await db.exec('reset role'); }
}
const me = { sub: U, email: 'u@x.com' }, q = s => as('authenticated', me, s);
const cfg = (await db.query(`select phase, type, points from public.story_phase_config where chapter = 5 order by phase`)).rows;
ok(cfg.length === 10 && cfg[9].type === 'boss' && cfg[9].points === 5 && cfg[0].points === 3, '페이즈 설정 10개 (멱등)');
await q(`select public.story_choose_starter('2000600126')`); await q('select public.player_status()');
await db.exec(`update public.player_state set stamina = 200, level = 10 where user_id='${U}'`);
ok(/phase locked/.test((await q('select public.story_start_phase(5, 1)')).err || ''), '챕터 4 미완료 시 잠김');
await db.exec(`update public.story_progress set data = jsonb_set(data, '{cleared}', (select jsonb_object_agg(chapter::text, ps) from (select chapter, jsonb_agg(phase) ps from public.story_phase_config where chapter < 5 group by chapter) x)) where user_id='${U}'`);
let r = await q('select public.story_start_phase(5, 1) r'); ok(!r.err, `챕터 4 완료 후 5-1 시작 (${r.err || ''})`);
await db.exec(`update public.story_progress set data = jsonb_set(data, '{battle,at}', to_jsonb((extract(epoch from now()) - 600)::bigint)) where user_id='${U}'`);
r = await q(`select public.story_complete_phase(5, 1, '[]'::jsonb) r`); const x = r.rows?.[0]?.r;
ok(x && x.first && x.drops && x.player, `5-1 클리어: 첫 클리어·드롭·플레이어 XP (${r.err || ''})`);
await db.exec(`update public.player_state set level = 10, stamina = 100 where user_id='${U}'`);
r = await q('select public.story_sweep(5, 1, 5) r'); ok(r.rows?.[0]?.r?.runs === 5, `5-1 소탕 (${r.err || ''})`);
ok(/phase locked/.test((await q('select public.story_start_phase(5, 3)')).err || ''), '5-3 은 5-2 전 잠김');
ok(/permission denied/.test((await as('anon', {}, 'select public.story_start_phase(5, 1)')).err || ''), 'anon 불가');
console.log(fails ? `${fails} FAIL` : 'ALL OK'); process.exit(fails ? 1 : 0);
