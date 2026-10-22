// supabase/story_ch4.sql 검증 + 챕터 4 데이터 검사 (PGlite, 실제 스토리·퀘스트 SQL 위에서). 실행: NODE_PATH=<pglite 설치 경로> node tools/test_ch4.mjs
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
await run('phaseE_4.sql'); await run('phaseE_5.sql'); await run('story_ch3.sql'); await db.exec(`insert into public.story_card_pool (id, grade) values ('2000000022','SUPER RARE') on conflict do nothing`); await run('story_ch4.sql')// --- 데이터 (js/story-data-ch4.js) ---
let fails = 0; const ok = (c, m) => { if (!c) { fails++; console.log('FAIL', m); } else console.log('ok  ', m); };
globalThis.window = { STORY_DATA: { chapters: [] } };
eval(readFileSync(new URL('../js/story-data-ch4.js', import.meta.url), 'utf8'));
const ch = window.STORY_DATA.chapters[0];
const csv = f => Object.fromEntries(readFileSync(new URL('../data/' + f, import.meta.url), 'utf8').replace(/^\uFEFF/, '').trim().split(/\r?\n/).slice(1).map(l => l.split(',')).map(v => [v[0], v]));
const cards = csv('cards.csv'), npc = csv('npc_cards.csv'), nm = id => (cards[id] || npc[id])?.[1];
const AW = '2000000022', MC = '2000100003', YR = '2000100001';
ok(npc[AW] && npc[AW][1] === '[각성] 이민채' && npc[AW][16] === '1' && !cards[AW], 'NPC 카드는 npc_cards.csv 에만 (일반 카드 목록·뽑기·갤러리 제외)');
const SK = JSON.parse(readFileSync(new URL('../data/skills.json', import.meta.url), 'utf8'));
ok(SK[AW]?.length === 2 && SK[AW][0].name === '사랑해!!!' && SK[AW][1].mode === 'passive', 'NPC 스킬 2개');
ok(ch.id === 4 && ch.subtitle === '카르밀라' && ch.phases.length === 10 && ch.single && nm(ch.hero) === '이민채', '챕터 4 · 10 페이즈 · 주인공 이민채');
ok(ch.phases.every(p => p.enemies.ids.length === 5 && p.enemies.ids.every(id => nm(id))), '페이즈마다 적 5명, 모두 카드 있음');
const P_ = n => ch.phases[n - 1];
ok(JSON.stringify(P_(8).enemies.ids.map(nm)) === JSON.stringify(['윤은별', '황보예', '김지우', '오유나', '김지수']) && nm(P_(8).bossId) === '김지수', '8페이즈 적·리더 김지수');
ok(P_(10).enemies.ids[0] === AW && P_(10).enemies.ids.slice(1).every(id => id === MC) && P_(10).bossId === AW, '10페이즈: 각성 이민채(L) + 분신 이민채 4');
const F = ch.phases.map(p => p.party.forced.map(nm).join('+'));
ok(JSON.stringify(F) === JSON.stringify(['이민채', '이민채', '이민채', '이민채+임유리', '이민채+임유리', '이민채', '이민채', '이민채', '이민채', '임유리']), `강제 배정 ${F}`);
ok([4, 5, 6, 7].every(n => P_(n).rules.mustLive[0] === MC) && [1, 2, 3, 8, 9, 10].every(n => !P_(n).rules?.mustLive), '4~7 이민채 사망 시 패배');
ok(P_(8).rules.revive[0].id === '2000100005' && P_(8).rules.revive[0].level === 1 && P_(8).rules.revive[0].delay === 2 && !P_(8).rules.revive[0].times && P_(9).rules.revive.every(r => r.delay === 2 && !r.times) && P_(9).rules.revive.map(r => nm(r.id) + r.level).join() === '김지수keep,오유나keep', '8 김지수 Lv1 · 9 김지수·오유나 레벨 승계: 2턴 후 부활(무제한)');
ok(P_(10).rules.invuln === AW && P_(10).rules.expire === 10 && P_(10).rules.revive[0].id === MC && !P_(10).rules.revive[0].times && P_(10).final && P_(10).party.forced[0] === YR, '10 각성 무적·10턴 자동 사망·분신 부활 · 임유리 조작');
ok([2, 4, 6, 9, 10].every(n => P_(n).after?.length) && ch.ending?.length && ch.start?.length && ch.tagline, '전투 후 대사 · 시작 · 엔딩');
ok(ch.phases.flatMap(p => p.lines.default).filter(l => l.expr).length > 20 && ch.phases.flatMap(p => p.lines.default).every(l => !l.expr || ['화남', '웃음'].includes(l.expr)), '표정 태그');
// --- SQL ---
async function as(role, claims, sql) {
  await db.exec(`reset role; select set_config('request.jwt.claims', '${JSON.stringify(claims || {})}', false); set role ${role};`);
  try { return { rows: (await db.query(sql)).rows }; } catch (e) { return { err: e.message }; } finally { await db.exec('reset role'); }
}
const me = { sub: U, email: 'u@x.com' }, q = s => as('authenticated', me, s);
const cfg = (await db.query(`select phase, type, points from public.story_phase_config where chapter = 4 order by phase`)).rows;
ok(cfg.length === 10 && cfg[9].type === 'boss' && cfg[9].points === 5 && cfg[0].points === 3, '페이즈 설정 10개 (멱등)');
await q(`select public.story_choose_starter('2000600126')`); await q('select public.player_status()');
await db.exec(`update public.player_state set stamina = 200, level = 10 where user_id='${U}'`);
ok(/phase locked/.test((await q('select public.story_start_phase(4, 1)')).err || ''), '챕터 3 미완료 시 잠김');
await db.exec(`update public.story_progress set data = jsonb_set(data, '{cleared}', (select jsonb_object_agg(chapter::text, ps) from (select chapter, jsonb_agg(phase) ps from public.story_phase_config where chapter < 4 group by chapter) x)) where user_id='${U}'`);
let r = await q('select public.story_start_phase(4, 1) r'); ok(!r.err, `챕터 3 완료 후 4-1 시작 (${r.err || ''})`);
await db.exec(`update public.story_progress set data = jsonb_set(data, '{battle,at}', to_jsonb((extract(epoch from now()) - 600)::bigint)) where user_id='${U}'`);
r = await q(`select public.story_complete_phase(4, 1, '[]'::jsonb) r`); const x = r.rows?.[0]?.r;
ok(x && x.first && x.drops && x.player, `4-1 클리어: 첫 클리어·드롭·플레이어 XP (${r.err || ''})`);
await db.exec(`update public.player_state set level = 10, stamina = 100 where user_id='${U}'`);
r = await q('select public.story_sweep(4, 1, 5) r'); ok(r.rows?.[0]?.r?.runs === 5, `4-1 소탕 (${r.err || ''})`);
ok(/phase locked/.test((await q('select public.story_start_phase(4, 3)')).err || ''), '4-3 은 4-2 전 잠김');
ok(/permission denied/.test((await as('anon', {}, 'select public.story_start_phase(4, 1)')).err || ''), 'anon 불가');
ok(+(await db.query(`select count(*) c from public.story_card_pool where id='2000000022'`)).rows[0].c === 0, 'NPC 뽑기 풀에서 제거');
console.log(fails ? `${fails} FAIL` : 'ALL OK'); process.exit(fails ? 1 : 0);
