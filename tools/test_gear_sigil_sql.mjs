// supabase/gear_sigil.sql 검증 (PGlite): 증표 제작·강화 · 보스 소탕 조각 · 토벌 순위 조각 · 교환
import { readFileSync } from 'fs';
import { createRequire } from 'module';
const require = createRequire(import.meta.url);
let PGlite; try { ({ PGlite } = require('@electric-sql/pglite')); } catch { console.log('SKIP: @electric-sql/pglite 없음'); process.exit(0); }
const db = new PGlite();
const id = n => `00000000-0000-0000-0000-0000000000${String(n).padStart(2, '0')}`;
const ADMIN = id(1), A = id(2), B = id(3), C = id(4), D = id(5);
await db.exec(`create role anon nologin; create role authenticated nologin; create schema auth;
create table auth.users (id uuid primary key, email text, email_confirmed_at timestamptz, created_at timestamptz default now(), last_sign_in_at timestamptz, raw_user_meta_data jsonb default '{}');
create function auth.jwt() returns jsonb language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $$;
create function auth.uid() returns uuid language sql stable as $$ select nullif(auth.jwt()->>'sub', '')::uuid $$;
grant usage on schema auth to anon, authenticated; grant execute on all functions in schema auth to anon, authenticated; grant usage on schema public to anon, authenticated;
create table public.profiles (id uuid primary key, nickname text);
create table public.matches (id bigint generated always as identity primary key, user_id uuid, result text, reason text, turns int, damage int, mvp_name text, created_at timestamptz default now());
create table public.gallery (user_id uuid, card_id text, count int, mvp_count int);
insert into auth.users (id, email, email_confirmed_at) values ('${ADMIN}','stevejean77@gmail.com',now()),('${A}','a@x',now()),('${B}','b@x',now()),('${C}','c@x',now()),('${D}','d@x',now());
insert into profiles (id, nickname) values ('${A}','에이'),('${B}','비'),('${C}','씨'),('${D}','디');`);
const src = f => readFileSync(new URL('../supabase/' + f, import.meta.url), 'utf8');
const run = f => db.exec(src(f));
for (const f of ['story.sql', 'gacha.sql', 'story_server.sql', 'story_gacha.sql', 'story_levels.sql', 'story_merge.sql', 'story_ch2.sql', 'story_cards_1022.sql', 'story_leader_lock.sql', 'story_level_stats.sql', 'story_min_battle.sql', 'admin.sql', 'phaseE_1.sql', 'phaseE_2.sql', 'quest.sql', 'quest_sweep.sql', 'phaseE_3.sql', 'phaseE_4.sql', 'phaseE_5.sql', 'story_ch3.sql', 'pvp.sql', 'pvp_tier.sql', 'gem.sql', 'guild.sql', 'guild2.sql', 'guild3.sql', 'tower_v2.sql', 'gear_v1.sql', 'gear_drops.sql']) await run(f);
await run('gear_sigil.sql'); await run('gear_sigil.sql');   // 두 번 실행해도 안전
let fails = 0; const ok = (c, m) => { if (!c) { fails++; console.log('FAIL', m); } else console.log('ok  ', m); };
async function as(uid, sql, role = 'authenticated') {
  await db.exec(`reset role; select set_config('request.jwt.claims', '${JSON.stringify(uid ? { sub: uid, email: 'x@x' } : {})}', false); set role ${role};`);
  try { return { rows: (await db.query(sql)).rows }; } catch (e) { return { err: e.message }; } finally { await db.exec('reset role'); }
}
const v = async (u, s) => { const r = await as(u, s); return r.err ? { err: r.err } : Object.values(r.rows[0])[0]; };
const q1 = async s => Object.values((await db.query(s)).rows[0] || {})[0];
const MIN = '10118', YUN = '10415', YURI = '10325';
const frags = async (u, c) => +((await q1(`select frags from player_sigils where user_id='${u}' and card_id='${c}'`)) ?? -1);
const plus = async (u, c) => await q1(`select plus from player_sigils where user_id='${u}' and card_id='${c}'`);
ok(+(await q1(`select sum(frags) from sigil_cost`)) === 530, '제작~+5 합계 530');
// 보스 소탕 조각 (테스트: 임유리 챕터를 3으로)
await db.exec(`update sigil_story_boss set chapter = 3 where card_id = '${YURI}'; update sigil_drop_config set v = 100 where key = 'story_boss_pct'; update gear_drop_rate set pct = 0`);
await db.exec(`insert into player_state (user_id, level, stamina) values ('${A}', 30, 900) on conflict (user_id) do update set level = 30, stamina = 900`);
await db.exec(`insert into story_progress (user_id, data) values ('${A}', '{"owned":[],"cleared":{"3":[1,10]}}') on conflict (user_id) do update set data = excluded.data`);
let s = await v(A, `select story_sweep(3, 1, 5)`); ok(s.sigil?.length === 0 && (await frags(A, YURI)) === -1, '일반 페이즈 소탕: 조각 없음');
s = await v(A, `select story_sweep(3, 10, 5)`); ok(s.sigil?.length === 3 && (await frags(A, YURI)) === 3, `보스 소탕 5회: 하루 최대 3개 (${s.sigil?.length ?? s.err})`);
s = await v(A, `select story_sweep(3, 10, 1)`); ok(s.sigil?.length === 0, '오늘 상한 도달');
const tk = await v(A, `select gear_drops_take()`); ok(tk.filter(x => x.kind === 'sigil' && x.def_id === YURI).length === 3, '결과 화면 기록 (증표 조각)');
// 제작·강화
ok((await v(A, `select sigil_craft('${YURI}')`)).reason === 'card not owned', '인재 없으면 제작 불가');
await db.exec(`update story_progress set data = jsonb_set(data, '{owned}', '[{"uid":"y","id":"${YURI}"}]') where user_id='${A}'`);
ok((await v(A, `select sigil_craft('${YURI}')`)).reason === 'not enough frags', '조각 50 미만: 제작 불가');
await db.exec(`update player_sigils set frags = 530 where user_id='${A}' and card_id='${YURI}'`);
ok((await v(A, `select sigil_enhance('${YURI}')`)).reason === 'not crafted', '제작 전 강화 불가');
let c = await v(A, `select sigil_craft('${YURI}')`); ok(c.ok && (await plus(A, YURI)) === 0 && (await frags(A, YURI)) === 480, '제작: 50 사용 → +0');
ok((await v(A, `select sigil_craft('${YURI}')`)).reason === 'already crafted', '두 번 제작 불가');
for (let i = 1; i <= 5; i++) await v(A, `select sigil_enhance('${YURI}')`);
ok((await plus(A, YURI)) === 5 && (await frags(A, YURI)) === 0, '+5까지 530 전부 사용');
ok((await v(A, `select sigil_enhance('${YURI}')`)).reason === 'max plus', '+5 이상 불가');
await db.exec(`update player_sigils set frags = 10, plus = 3 where user_id='${A}' and card_id='${YURI}'`);
ok((await v(A, `select sigil_enhance('${YURI}')`)).reason === 'not enough frags' && (await plus(A, YURI)) === 3, '조각 부족: +4 불가');
// 교환
ok((await v(A, `select sigil_exchange('${YURI}', '${MIN}', 4)`)).reason === 'not enough frags', '교환: 3×4 = 12 필요');
const ex = await v(A, `select sigil_exchange('${YURI}', '${MIN}', 3)`); ok(ex.ok && (await frags(A, YURI)) === 1 && (await frags(A, MIN)) === 3, '교환: 9 → 3');
ok((await v(A, `select sigil_exchange('${YURI}', '${YURI}', 1)`)).reason === 'invalid', '같은 인재 교환 불가');
// 토벌 순위 조각
await db.exec(`insert into player_state (user_id, level, stamina) values ('${B}', 20, 40) on conflict do nothing`);
const cid = await q1(`select id from pvp_card_meta order by id limit 1`);
for (const u of [A, B]) await db.exec(`update story_progress set data = data || '{"owned":[{"uid":"c1","id":"${cid}","level":10}]}' where user_id='${u}'; insert into story_progress (user_id, data) values ('${u}', '{"owned":[{"uid":"c1","id":"${cid}","level":10}]}') on conflict do nothing`);
await db.exec(`select _wallet_add('${A}', '{"gold":50000}', 'test')`);
const gid = (await v(A, `select guild_create('검은장미',1,'','open','gold')`)).id;
await as(B, `select guild_apply(${gid})`); await db.exec(`update guild_members set joined_at = now() - interval '9 days'`);
const st = await v(B, `select raid_start('["c1"]')`); await db.exec(`update guild_raid_attempts set started_at = started_at - interval '5 seconds' where finished_at is null`);
await v(B, `select raid_finish(${st.id}, 1000)`);
await db.exec(`create or replace function public._raid_now() returns timestamptz language sql stable as $$ select _raid_end(_guild_week()) + interval '1 minute' $$`);
await v(B, `select raid_claim()`);
const ml = (await v(B, `select mail_list()`)).find(m => m.kind === 'sigil_frag');
ok(ml && ml.payload.n === 6, `순위 1위: 증표 조각 6개 선택 우편 (${ml?.payload?.n})`);
ok((await v(B, `select gear_drops_take()`)).some(x => x.kind === 'sigil' && x.mail), '결과 기록 (우편)');
ok((await v(B, `select sigil_mail_claim(${ml.id}, '10370')`)).reason === 'not selectable', '고를 수 없는 인재 거부');
const mc = await v(B, `select sigil_mail_claim(${ml.id}, '${YUN}')`); ok(mc.ok && (await frags(B, YUN)) === 6, '최윤희 조각 6개 받음');
ok((await v(B, `select sigil_mail_claim(${ml.id}, '${YUN}')`)).reason === 'not found', '두 번 못 받음');
// 보안
for (const f of [`sigil_craft('${YURI}')`, `sigil_enhance('${YURI}')`, `sigil_exchange('${YURI}','${MIN}',1)`, `sigil_mail_claim(1,'${YUN}')`]) ok(!!(await as(null, `select ${f}`, 'anon')).err, `anon 거부: ${f.split('(')[0]}`);
ok(!!(await as(A, `select _sigil_add('${A}', '${YURI}', 500, 'x')`)).err, '내부 함수 직접 호출 불가');
ok(!!(await as(A, `update player_sigils set frags = 999`)).err || +(await frags(A, YURI)) !== 999, '조각 직접 수정 불가');
ok(!!(await as(null, `select * from sigil_daily`, 'anon')).err && !!(await as(null, `select * from sigil_story_boss`, 'anon')).err, '표 anon 거부');
// 후속: 스토리 조각 끄기 (gear_sigil_story_off.sql, 두 번 실행)
await run('gear_sigil_story_off.sql'); await run('gear_sigil_story_off.sql');
ok(+(await q1(`select count(*) from sigil_story_boss`)) === 0 && +(await q1(`select v from sigil_drop_config where key='story_boss_on'`)) === 0, '끄기: 매핑 비움 · 꺼짐');
await db.exec(`insert into sigil_story_boss (card_id, chapter) values ('${YURI}', 3); delete from sigil_daily`);
s = await v(A, `select story_sweep(3, 10, 1)`); ok(s.sigil?.length === 0, `꺼져 있으면 매핑이 있어도 조각 없음 (${s.err || ''})`);
await db.exec(`update sigil_drop_config set v = 1 where key = 'story_boss_on'`);
s = await v(A, `select story_sweep(3, 10, 1)`); ok(s.sigil?.length === 1, '다시 켜면 나옴');
console.log(fails ? `\n${fails} FAIL` : '\nALL OK'); process.exit(fails ? 1 : 0);
