// supabase/phaseE_3.sql 검증 (PGlite, 실제 스토리·퀘스트 SQL 위에서). 실행: NODE_PATH=<pglite 설치 경로> node tools/test_econ_sql.mjs
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
for (const f of ['story.sql', 'gacha.sql', 'story_server.sql', 'story_gacha.sql', 'story_levels.sql', 'story_level_stats.sql', 'story_merge.sql', 'story_ch2.sql', 'story_cards_1022.sql', 'story_leader_lock.sql', 'story_min_battle.sql', 'quest.sql', 'admin.sql', 'phaseE_1.sql', 'phaseE_2.sql']) await run(f);
// 이전 대상: 남은 EXP 255 + 40 = 295 → 피 29
await db.exec(`insert into public.story_progress (user_id, data) values ('${M}', '{"starter":"2000600126","leader":"a","owned":[{"uid":"a","id":"2000600126","level":5,"exp":255,"totalExp":1255},{"uid":"b","id":"2000200044","level":2,"exp":40,"totalExp":140}]}')`);
await run('phaseE_3.sql'); await run('phaseE_3.sql');   // 두 번 실행해도 안전 (이전 1회)
let fails = 0; const ok = (c, m) => { if (!c) { fails++; console.log('FAIL', m); } else console.log('ok  ', m); };
async function as(role, claims, sql) {
  await db.exec(`reset role; select set_config('request.jwt.claims', '${JSON.stringify(claims || {})}', false); set role ${role};`);
  try { return { rows: (await db.query(sql)).rows }; } catch (e) { return { err: e.message }; } finally { await db.exec('reset role'); }
}
const me = { sub: U, email: 'u@x.com' }, q = s => as('authenticated', me, s);
const W = async (u = U) => (await db.query(`select gold, blood, shard, soul from public.player_wallet where user_id='${u}'`)).rows[0] || { gold: 0, blood: 0, shard: 0, soul: 0 };
const C = async (ch, t, f, r1 = 0.9, r2 = 0.9) => (await db.query(`select public._story_drop_calc(${ch}, '${t}', ${f}, 6, ${r1}, ${r2}) d`)).rows[0].d;
// 드롭 표
let d = await C(1, 'normal', false); ok(d.gold === 120 && d.blood === 12 && d.shard === 0 && d.soul === 0, `ch1 일반 반복 (확률 실패): ${JSON.stringify(d)}`);
d = await C(1, 'normal', false, 0.1); ok(d.shard === 1, 'ch1 일반 반복 30% 성공 → 조각 1');
d = await C(1, 'normal', true); ok(d.gold === 360 && d.blood === 36 && d.shard === 1 && d.soul === 0, `ch1 첫 클리어 ×3: ${JSON.stringify(d)}`);
d = await C(1, 'boss', true); ok(d.gold === 720 && d.blood === 72 && d.shard === 3, `ch1 보스 첫 클리어 ×6: ${JSON.stringify(d)}`);
d = await C(3, 'normal', true); ok(d.gold === 540 && d.shard === 2, `ch3 첫 클리어: 골드 ${d.gold}, 조각 +1 = ${d.shard}`);
d = await C(4, 'normal', false); ok(d.soul === 0, 'ch4 혼 없음');
d = await C(5, 'normal', false, 0.9, 0.1); ok(d.soul === 1 && d.gold === 240, `ch5 반복 20% 성공 → 혼 1, 골드 ${d.gold}`);
d = await C(5, 'boss', false); ok(d.soul === 5 && d.shard === 5, `ch5 보스: 혼 5, 조각 3+2=${d.shard}`);
d = await C(5, 'normal', true); ok(d.soul === 2, 'ch5 첫 클리어 혼 2');
// 실제 클리어 → 지갑
await q(`select public.story_choose_starter('2000600126')`);
await q('select public.story_start_phase(1,1)');
await db.exec(`update public.story_progress set data = jsonb_set(data, '{battle,at}', to_jsonb((extract(epoch from now()) - 10)::bigint)) where user_id='${U}'`);
await db.exec(`update public.player_state set xp = 200 where user_id='${U}'`);   // 필요 경험치 3배(300): 200 + 110 → 레벨업
let r = await q(`select public.story_complete_phase(1,1,'[]'::jsonb) r`);
const dr = r.rows?.[0]?.r?.drops; ok(dr && dr.gold === 360 && dr.blood === 36 && dr.shard === 1, `첫 클리어 드롭 응답: ${JSON.stringify(dr)}`);
let w = await W(); ok(+w.gold === 360 + 200 && +w.blood === 36 && +w.shard === 1, `지갑 반영 (드롭 360 + 레벨업 200): ${JSON.stringify(w)}`);
ok(r.rows[0].r.player?.gained_xp === 110, 'E-2 경험치 처리 유지');
// 퀘스트
const q10 = (await db.query(`select public._quest_currency(10) c`)).rows[0].c; ok(q10.gold === 100 && q10.blood === 50 && !q10.shard && !q10.soul, '10층: 골드 100 · 피 50');
const qc = (await db.query(`select public._quest_currency(150) c`)).rows[0].c; ok(qc.gold === 800 && qc.blood === 750 && qc.soul === 10 && qc.shard === 5, `150층: ${JSON.stringify(qc)}`);
const before = await W();
await q('select public.quest_start(1)');
await db.exec(`update public.quest_progress set battle = jsonb_set(battle, '{at}', to_jsonb((extract(epoch from now()) - 60)::bigint)) where user_id='${U}'`);
r = await q(`select public.quest_complete(1, '{"turns":5}') r`);
ok(r.rows?.[0].r.currency?.gold === 55, `퀘스트 1층 첫 클리어 골드 55 (${JSON.stringify(r.rows?.[0].r.currency || r.err)})`);
ok(+(await W()).gold === +before.gold + 55, '지갑에 퀘스트 골드');
await q('select public.quest_start(1)');
await db.exec(`update public.quest_progress set battle = jsonb_set(battle, '{at}', to_jsonb((extract(epoch from now()) - 60)::bigint)) where user_id='${U}'`);
r = await q(`select public.quest_complete(1, '{"turns":5}') r`); ok(r.rows?.[0].r.currency === null, '재클리어는 재화 없음');
// 분해
await db.exec(`update public.story_progress set data = jsonb_set(data, '{owned}', data->'owned' || '[{"uid":"x1","id":"2000200044","level":3,"exp":0,"totalExp":300,"boost":{"ATK":2}},{"uid":"x2","id":"2000200044","level":1,"exp":0,"totalExp":0,"locked":true}]'::jsonb) where user_id='${U}'`);
const g = (await db.query(`select grade from public.story_card_pool where id='2000200044'`)).rows[0]?.grade;
const y = (await db.query(`select public._dismantle_yield('${g}') y`)).rows[0].y;
const w0 = await W(), pts0 = (await db.query(`select (data->>'points')::int p from public.story_progress where user_id='${U}'`)).rows[0].p;
r = await q(`select public.story_dismantle(array['x1']) r`);
const rr = r.rows?.[0]?.r; ok(rr && rr.gold === y.gold && rr.blood === y.blood + 15 && rr.soul === y.soul && rr.refund === 2, `분해 ${g}: ${JSON.stringify({ gold: rr?.gold, blood: rr?.blood, soul: rr?.soul, refund: rr?.refund, err: r.err })} (누적 EXP 300 → 피 +15)`);
w = await W(); ok(+w.gold === +w0.gold + y.gold && +w.blood === +w0.blood + y.blood + 15, '지갑 반영');
ok(!rr.data.owned.some(o => o.uid === 'x1'), '카드 제거');
ok((await db.query(`select (data->>'points')::int p from public.story_progress where user_id='${U}'`)).rows[0].p === pts0 + 2, '공용 포인트 환급');
ok(/locked/.test((await q(`select public.story_dismantle(array['x2'])`)).err || ''), '잠금 카드 거부');
const lead = (await db.query(`select data->>'leader' l from public.story_progress where user_id='${U}'`)).rows[0].l;
ok(/leader/.test((await q(`select public.story_dismantle(array['${lead}'])`)).err || ''), '리더 거부');
ok(/not owned/.test((await q(`select public.story_dismantle(array['nope'])`)).err || ''), '없는 카드 거부');
// 예전 RPC 는 EXP 대신 재화
await db.exec(`update public.story_progress set data = jsonb_set(data, '{owned}', data->'owned' || '[{"uid":"x3","id":"2000200044","level":1,"exp":0,"totalExp":0}]'::jsonb) where user_id='${U}'`);
const lv0 = (await db.query(`select data->'owned'->0 o from public.story_progress where user_id='${U}'`)).rows[0].o;
r = await q(`select public.story_discard_many(array['x3'], '${lead}') r`);
ok(r.rows?.[0].r.exp === 0 && r.rows[0].r.gold === y.gold, '예전 story_discard_many → 재화 분해, EXP 0');
ok(JSON.stringify((await db.query(`select data->'owned'->0 o from public.story_progress where user_id='${U}'`)).rows[0].o) === JSON.stringify(lv0), '대상 카드 EXP 변화 없음');
// 이전
const mi = (await db.query(`select data from public.story_progress where user_id='${M}'`)).rows[0].data;
ok(mi.econV === 3 && mi.owned[0].level === 5 && mi.owned[0].exp === 0 && mi.owned[0].totalExp === 1000 && mi.owned[1].exp === 0, '이전: 레벨 유지, 남은 EXP 0, 누적에서 차감');
ok(+(await W(M)).blood === 29, `이전: 남은 EXP 295 → 피 29 (${(await W(M)).blood})`);
ok(+(await db.query(`select count(*) c from public.wallet_log where user_id='${M}' and reason='migrate_exp'`)).rows[0].c === 1, '이전은 1회만 (재실행해도)');
// 탐침·권한
ok((await q('select public.economy_rates() e')).rows?.[0].e.dismantle['MYTHIC RARE'].gold === 2000, 'economy_rates 탐침');
ok(/permission denied/.test((await q(`select public._story_drops('${U}',1,1,true)`)).err || ''), '_story_drops 직접 호출 불가');
ok(/permission denied/.test((await as('anon', {}, `select public.story_dismantle(array['x'])`)).err || ''), 'anon 분해 불가');
// phaseE_2 재실행해도 드롭 유지 (감싸는 함수가 _story_drops 를 찾아 부름)
await run('phaseE_2.sql');
await q('select public.story_start_phase(1,1)');
await db.exec(`update public.story_progress set data = jsonb_set(data, '{battle,at}', to_jsonb((extract(epoch from now()) - 10)::bigint)) where user_id='${U}'`);
r = await q(`select public.story_complete_phase(1,1) r`); ok(r.rows?.[0].r.drops?.gold === 120, `phaseE_2 재실행 후에도 드롭 (반복 120): ${JSON.stringify(r.rows?.[0].r.drops || r.err)}`);
console.log(fails ? `\n${fails} FAIL` : '\nALL OK'); process.exit(fails ? 1 : 0);
