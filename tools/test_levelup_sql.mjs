// supabase/phaseE_4.sql 검증 (PGlite, 실제 스토리·퀘스트 SQL 위에서). 실행: NODE_PATH=<pglite 설치 경로> node tools/test_levelup_sql.mjs
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
await run('phaseE_4.sql'); await run('phaseE_4.sql');   // 두 번 실행해도 안전 (이중으로 감싸지 않음)
let fails = 0; const ok = (c, m) => { if (!c) { fails++; console.log('FAIL', m); } else console.log('ok  ', m); };
async function as(role, claims, sql) {
  await db.exec(`reset role; select set_config('request.jwt.claims', '${JSON.stringify(claims || {})}', false); set role ${role};`);
  try { return { rows: (await db.query(sql)).rows }; } catch (e) { return { err: e.message }; } finally { await db.exec('reset role'); }
}
const me = { sub: U, email: 'u@x.com' }, q = s => as('authenticated', me, s);
const W = async () => (await db.query(`select gold::int, blood::int, shard::int, soul::int from public.player_wallet where user_id='${U}'`)).rows[0] || { gold: 0, blood: 0, shard: 0, soul: 0 };
const give = o => db.query(`select public._wallet_add('${U}', '${JSON.stringify(o)}', 'test')`);
const card = async u => (await db.query(`select x.e c from public.story_progress sp, jsonb_array_elements(sp.data->'owned') x(e) where sp.user_id='${U}' and x.e->>'uid'='${u}'`)).rows[0]?.c;
const idOf = async g => (await db.query(`select id from public.story_card_pool where grade='${g}' order by id limit 1`)).rows[0].id;
ok(+(await db.query(`select count(*) c from pg_proc where proname='_story_merge_e0'`)).rows[0].c === 1, '원래 합성 _e0 보관 (재실행해도 1개)');
ok(/permission denied/.test((await q(`select public._story_merge_e0('a','b')`)).err || ''), '_e0 직접 호출 불가 (조각 우회 차단)');
const t = (await q('select public.card_cost_table() t')).rows?.[0].t;
ok(t?.grades['NORMAL'].lv1.blood === 2 && t.grades['NORMAL'].lv1.gold === 10 && t.grades['RARE'].lv1.gold === 15 && t.grades['MYTHIC RARE'].shard === 30, `비용표 탐침 ${JSON.stringify(t?.grades['RARE'])}`);
const sum = async (g, a, b) => (await db.query(`select sum((public._lv_cost('${g}', l)->>'blood')::int)::int b, sum((public._lv_cost('${g}', l)->>'gold')::int)::int g from generate_series(${a}, ${b}) l`)).rows[0];
let s1 = await sum('NORMAL', 1, 19); ok(s1.b === 380 && s1.g === 1900, `N 1→20 합계 피 380 · 골드 1,900 (${s1.b}/${s1.g})`);
s1 = await sum('MYTHIC RARE', 1, 69); ok(s1.b === 43470 && s1.g === 144900, `MR 1→70 합계 피 43,470 · 골드 144,900 (${s1.b}/${s1.g})`);
s1 = await sum('RARE', 1, 29); ok(s1.b === 1305 && s1.g === 6525, `R 1→30 (${s1.b}/${s1.g})`);
// 카드 준비
await q(`select public.story_choose_starter('10111')`);
const nId = await idOf('NORMAL'), urId = await idOf('ULTRA RARE');
await db.exec(`update public.story_progress set data = jsonb_set(data, '{owned}', data->'owned' || '[{"uid":"n1","id":"${nId}","level":3,"exp":150,"totalExp":450},{"uid":"n2","id":"${nId}","level":1},{"uid":"n3","id":"${nId}","level":1,"locked":true},{"uid":"u1","id":"${urId}","level":1,"ex":4},{"uid":"u2","id":"${urId}","level":1}]'::jsonb) where user_id='${U}'`);
ok(/not enough gold|not enough blood/.test((await q(`select public.story_card_levelup('n1', 1)`)).err || ''), '재화 없으면 거부');
ok((await card('n1')).level === 3, '거부 시 레벨 그대로');
await give({ gold: 1000, blood: 100 });
let r = await q(`select public.story_card_levelup('n1', 2) r`); const rr = r.rows?.[0]?.r;
ok(rr && rr.from === 3 && rr.level === 5 && rr.blood === 14 && rr.gold === 70, `N Lv3→5: 피 6+8=14 · 골드 30+40=70 (${JSON.stringify({ l: rr?.level, b: rr?.blood, g: rr?.gold, e: r.err })})`);
let w = await W(); ok(w.gold === 930 && w.blood === 86, '지갑 차감');
let c = await card('n1'); ok(c.level === 5 && c.exp === 150 && c.bloodSpent === 14 && c.totalExp === 450, 'EXP 진행도·누적 유지, bloodSpent 기록');
r = await q(`select public.story_card_levelup('n1', 10) r`); let pr = r.rows?.[0]?.r;
ok(pr && pr.level === 10 && pr.gained === 5 && pr.blood === 70 && pr.gold === 350, `+10 → 감당 가능한 5단계만 (${JSON.stringify({ l: pr?.level, g: pr?.gained, e: r.err })})`);
w = await W(); ok(w.gold === 580 && w.blood === 16, '올린 만큼만 차감');
await give({ gold: 100000, blood: 10000 });
r = await q(`select public.story_card_levelup('n1', 100) r`); ok(r.rows?.[0].r.level === 20 && r.rows[0].r.cap === 20, 'N 최대 Lv20 까지만');
ok((await card('n1')).exp === 0, '최대 레벨이면 EXP 0');
ok(/max level/.test((await q(`select public.story_card_levelup('n1', 1)`)).err || ''), '최대 레벨 이후 거부');
ok(/invalid levels/.test((await q(`select public.story_card_levelup('n1', 0)`)).err || ''), '0단계 거부');
ok(/not owned/.test((await q(`select public.story_card_levelup('zz', 1)`)).err || ''), '없는 카드 거부');
// 전투 EXP 레벨업 경로 유지 (_story_gain)
const gn = (await db.query(`select public._story_gain('{"uid":"z","id":"${nId}","level":2,"exp":0}', 250, 'NORMAL') e`)).rows[0].e; ok(gn.level === 3 && gn.exp === 50, '전투 EXP 레벨업 그대로');
// 분해 시 bloodSpent 50% 환급 (E-3 규칙)
const ys = (await db.query(`select public._dismantle_yield('NORMAL') y`)).rows[0].y;
const b0 = (await W()).blood; r = await q(`select public.story_dismantle(array['n1']) r`);
const spent = 14 + (await sum('NORMAL', 5, 19)).b;
ok(r.rows?.[0].r.blood === ys.blood + Math.floor(450 * 0.5 / 10) + Math.floor(spent * 0.5), `분해: 쓴 피 ${spent} 의 50% 환급 포함 (${r.rows?.[0].r.blood})`);
// 합성 조각
const sh0 = (await W()).shard;
r = await q(`select public.story_merge('n2','n3')`); ok(/not enough shard|locked/.test(r.err || ''), '조각 없음/잠금 → 거부');
await give({ shard: 100 });
r = await q(`select public.story_merge('n2','n3')`); ok(/locked/.test(r.err || '') && (await W()).shard === sh0 + 100, '원래 합성이 거부하면 조각도 롤백');
await db.exec(`update public.story_progress set data = jsonb_set(data, '{owned}', (select jsonb_agg(case when x.e->>'uid'='n3' then x.e - 'locked' else x.e end) from jsonb_array_elements(data->'owned') x(e))) where user_id='${U}'`);
r = await q(`select public.story_merge('n2','n3') r`); ok(r.rows?.[0].r.shard === 1 && r.rows[0].r.ex === 1, `N EX1 = 조각 1 (${JSON.stringify(r.rows?.[0]?.r?.shard ?? r.err)})`);
r = await q(`select public.story_merge('u1','u2') r`); ok(r.rows?.[0].r.shard === 75 && r.rows[0].r.ex === 5, `UR EX4→5 = 15×5 = 75 (${r.rows?.[0]?.r?.shard ?? r.err})`);
ok((await W()).shard === sh0 + 100 - 1 - 75, '조각 차감 합계');
await db.exec(`update public.story_progress set data = jsonb_set(data, '{owned}', data->'owned' || '[{"uid":"u3","id":"${urId}","level":1}]'::jsonb) where user_id='${U}'`);
ok(/max ex/.test((await q(`select public.story_merge('u1','u3')`)).err || ''), 'UR EX5 이후 거부 (조각 안 씀)');
// EX 늘어난 구간도 같은 공식: UR EX5 최대 85, Lv60→61 = 피 720 · 골드 2,400
const ex = (await db.query(`select public._lv_cost('ULTRA RARE', 60) c, public._story_cap('ULTRA RARE', 5) cap`)).rows[0]; ok(ex.c.blood === 720 && ex.c.gold === 2400 && ex.cap === 85, `UR EX5 구간 Lv60→61 비용 ${JSON.stringify(ex.c)}, 최대 ${ex.cap}`);
ok(/permission denied/.test((await as('anon', {}, `select public.story_card_levelup('n2', 1)`)).err || ''), 'anon 불가');
// 스토리 SQL 재실행 후 다시 감싸기
await run('story_leader_lock.sql'); await run('phaseE_4.sql');
await db.exec(`update public.story_progress set data = jsonb_set(data, '{owned}', data->'owned' || '[{"uid":"n4","id":"${nId}","level":1},{"uid":"n5","id":"${nId}","level":1}]'::jsonb) where user_id='${U}'`);
const sh1 = (await W()).shard; r = await q(`select public.story_merge('n4','n5') r`); ok(r.rows?.[0].r.shard === 1 && (await W()).shard === sh1 - 1, 'story_leader_lock.sql 재실행 후 phaseE_4 재실행 → 다시 조각 차감');
console.log(fails ? `\n${fails} FAIL` : '\nALL OK'); process.exit(fails ? 1 : 0);
