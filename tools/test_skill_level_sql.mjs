// supabase/phaseE_6.sql 검증 (스킬 레벨) (PGlite, 실제 스토리·퀘스트 SQL 위에서). 실행: NODE_PATH=<pglite 설치 경로> node tools/test_skill_level_sql.mjs
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
await run('phaseE_4.sql'); await run('phaseE_6.sql'); await run('phaseE_6.sql');   // 두 번 실행해도 안전
let fails = 0; const ok = (c, m) => { if (!c) { fails++; console.log('FAIL', m); } else console.log('ok  ', m); };
async function as(role, claims, sql) {
  await db.exec(`reset role; select set_config('request.jwt.claims', '${JSON.stringify(claims || {})}', false); set role ${role};`);
  try { return { rows: (await db.query(sql)).rows }; } catch (e) { return { err: e.message }; } finally { await db.exec('reset role'); }
}
const me = { sub: U, email: 'u@x.com' }, q = s => as('authenticated', me, s);
const W = async () => (await db.query(`select gold::int, blood::int, shard::int, soul::int from public.player_wallet where user_id='${U}'`)).rows[0] || { gold: 0, blood: 0, shard: 0, soul: 0 };
const give = o => db.query(`select public._wallet_add('${U}', '${JSON.stringify(o)}', 'test')`);
const card = async u => (await db.query(`select x.e c from public.story_progress sp, jsonb_array_elements(sp.data->'owned') x(e) where sp.user_id='${U}' and x.e->>'uid'='${u}'`)).rows[0]?.c;

ok(+(await db.query(`select count(*) c from pg_proc where proname='_story_dismantle_e5'`)).rows[0].c === 1, '원래 분해 _e5 보관 (재실행해도 1개)');
ok(/permission denied/.test((await q(`select public._story_dismantle_e5(array['x'])`)).err || ''), '_e5 직접 호출 불가');
ok(/permission denied/.test((await as('anon', {}, `select public.skill_cost_table()`)).err || ''), 'anon 비용표 거부 (42501)');
ok(/permission denied/.test((await as('anon', {}, `select public.story_skill_levelup('a',1,1)`)).err || ''), 'anon 레벨업 거부');
ok(/permission denied/.test((await q(`select * from public.story_skill_meta`)).err || ''), '메타 테이블 직접 읽기 불가');
const t = (await q('select public.skill_cost_table() t')).rows?.[0].t;
ok(t?.max === 10 && t.skills === 142 && t.grades['SUPER RARE'].lv1.soul === 5 && t.grades['SUPER RARE'].lv1.gold === 300, `비용표 탐침 SR ${JSON.stringify(t?.grades['SUPER RARE'])}`);
const tot = g => t.grades[g].total;
ok(tot('NORMAL').soul === 25 && tot('NORMAL').gold === 4500 && tot('SUPER RARE').soul === 125 && tot('SUPER RARE').gold === 13500 && tot('ULTRA RARE').soul === 200 && tot('ULTRA RARE').gold === 18000 && tot('MYTHIC RARE').soul === 300 && tot('MYTHIC RARE').gold === 27000 && tot('RARE').gold === 6750 && tot('HIGH RARE').soul === 75, '등급별 Lv1→10 합계 = 초안 표');
// 카드 준비: SR 카드 중 해금 Lv 가 1보다 큰 액티브가 있는 것
const pk = (await db.query(`select m.card_id id, min(m.unlock) lo, max(m.unlock) ul from public.story_skill_meta m join public.story_card_pool p on p.id=m.card_id where p.grade='SUPER RARE' group by m.card_id having max(m.unlock) > min(m.unlock) order by 1 limit 1`)).rows[0];
const hiIdx = (await db.query(`select idx from public.story_skill_meta where card_id='${pk.id}' order by unlock desc limit 1`)).rows[0].idx;
const loIdx = (await db.query(`select idx from public.story_skill_meta where card_id='${pk.id}' order by unlock asc limit 1`)).rows[0].idx;
const passIdx = (await db.query(`select g::int i from generate_series(1,6) g where not exists (select 1 from public.story_skill_meta where card_id='${pk.id}' and idx=g) order by 1 limit 1`)).rows[0].i;
await q(`select public.story_choose_starter('2000600126')`);
await db.exec(`update public.story_progress set data = jsonb_set(data, '{owned}', data->'owned' || '[{"uid":"s1","id":"${pk.id}","level":${pk.lo}},{"uid":"s2","id":"${pk.id}","level":1,"skillLv":{"${loIdx}":7},"soulSpent":999},{"uid":"s3","id":"${pk.id}","level":1}]'::jsonb) where user_id='${U}'`);
ok(/not enough soul/.test((await q(`select public.story_skill_levelup('s1', ${loIdx}, 1)`)).err || ''), '혼 없으면 거부');
ok(/skill locked/.test((await q(`select public.story_skill_levelup('s1', ${hiIdx}, 1)`)).err || ''), `카드 Lv 미달 스킬 거부 (해금 Lv${pk.ul})`);
ok(/invalid skill/.test((await q(`select public.story_skill_levelup('s1', ${passIdx}, 1)`)).err || ''), '패시브·없는 스킬 거부');
ok(/invalid levels/.test((await q(`select public.story_skill_levelup('s1', ${loIdx}, 0)`)).err || ''), '0단계 거부');
ok(/not owned/.test((await q(`select public.story_skill_levelup('zz', 1, 1)`)).err || ''), '없는 카드 거부');
await give({ gold: 1000, soul: 100 });
ok(/not enough gold/.test((await q(`select public.story_skill_levelup('s1', ${loIdx}, 1)`)).err || '') === false, '골드 1000 → Lv1→2 (300) 가능');
let w = await W(); let c = await card('s1');
ok(c.skillLv?.[loIdx] === 2 && c.soulSpent === 5 && w.gold === 700 && w.soul === 95, `Lv1→2: 혼 5 · 골드 300 (${JSON.stringify({ sl: c.skillLv, w })})`);
let r = await q(`select public.story_skill_levelup('s1', ${loIdx}, 9) r`); let rr = r.rows?.[0]?.r;
ok(rr && rr.from === 2 && rr.level === 3 && rr.gained === 1 && rr.gold === 600 && rr.soul === 5, `+9 요청 → 골드 허락하는 1단계만 (${JSON.stringify(rr ?? r.err)})`);
await give({ gold: 100000, soul: 1000 });
r = await q(`select public.story_skill_levelup('s1', ${loIdx}, 9) r`); rr = r.rows?.[0]?.r;
ok(rr?.level === 10 && rr.soul === 115 && rr.gold === 12600, `Lv3→10: 혼 115 · 골드 12,600 (${JSON.stringify(rr ?? r.err)})`);
c = await card('s1'); ok(c.soulSpent === 125, `누적 soulSpent 125 = SR 합계 (${c.soulSpent})`);
ok(/max skill level/.test((await q(`select public.story_skill_levelup('s1', ${loIdx}, 1)`)).err || ''), 'Lv10 이후 거부');
await db.exec(`update public.story_progress set data = jsonb_set(data, '{owned}', (select jsonb_agg(case when x.e->>'uid'='s1' then x.e || '{"level":${pk.ul}}' else x.e end order by n) from jsonb_array_elements(data->'owned') with ordinality x(e,n))) where user_id='${U}'`);
r = await q(`select public.story_skill_levelup('s1', ${hiIdx}, 1) r`); ok(r.rows?.[0]?.r?.level === 2, '카드 Lv 도달 후 해금 스킬 레벨업');
c = await card('s1'); ok(c.skillLv[loIdx] === 10 && c.skillLv[hiIdx] === 2, '스킬별 레벨 따로 저장');
// 합성: 대상 유지, 재료 소멸
await give({ shard: 100 });
r = await q(`select public.story_merge('s1','s2') r`); c = await card('s1');
ok(!r.err && c.ex === 1 && c.level === 1 && c.skillLv[loIdx] === 10 && c.skillLv[hiIdx] === 2 && c.soulSpent === 130, `합성 후 대상 스킬 레벨 유지 (${r.err || JSON.stringify(c.skillLv)})`);
ok(!(await card('s2')), '재료(스킬 Lv7) 소멸, 환급 없음');
// 분해: 쓴 혼 50% (카드별 내림)
const s0 = (await W()).soul, gd0 = (await W()).gold;
const y = (await db.query(`select public._dismantle_yield('SUPER RARE') y`)).rows[0].y;
r = await q(`select public.story_dismantle(array['s1','s3']) r`); rr = r.rows?.[0]?.r; w = await W();
ok(rr && rr.skill_soul === 65 && rr.soul === y.soul * 2 + 65 && w.soul === s0 + y.soul * 2 + 65, `분해: 기본 혼 ${y.soul}×2 + 스킬 혼 130×50% = 65 (${JSON.stringify({ s: rr?.soul, k: rr?.skill_soul, e: r.err })})`);
ok(w.gold === gd0 + y.gold * 2, '골드는 기본 분해만 (스킬 골드 환급 없음)');
await db.exec(`update public.story_progress set data = jsonb_set(data, '{owned}', data->'owned' || '[{"uid":"s4","id":"${pk.id}","level":1,"soulSpent":11,"locked":true}]'::jsonb) where user_id='${U}'`);
const s1 = (await W()).soul; r = await q(`select public.story_dismantle(array['s4'])`);
ok(/locked/.test(r.err || '') && (await W()).soul === s1, '원래 분해가 거부하면 환급도 없음');
// phaseE_3 재실행 → phaseE_6 재실행하면 다시 감쌈
await run('phaseE_3.sql'); await run('phaseE_6.sql');
await db.exec(`update public.story_progress set data = jsonb_set(data, '{owned}', data->'owned' || '[{"uid":"s5","id":"${pk.id}","level":1,"soulSpent":11}]'::jsonb) where user_id='${U}'`);
r = await q(`select public.story_dismantle(array['s5']) r`); ok(r.rows?.[0]?.r?.skill_soul === 5, `재실행 후에도 환급 (11 → 5) ${r.err || ''}`);
console.log(fails ? `\n${fails} FAIL` : '\nALL OK'); process.exit(fails ? 1 : 0);
