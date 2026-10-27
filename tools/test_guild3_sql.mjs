// supabase/guild3.sql 검증 (PGlite): 균열 토벌 — 횟수 · 스냅샷 · 상한 · 공유 HP/단계 · 소탕 · 보상 · 가입 규칙 · 난이도 · 보안
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
for (const f of ['story.sql', 'gacha.sql', 'story_server.sql', 'story_gacha.sql', 'story_levels.sql', 'story_merge.sql', 'story_ch2.sql', 'story_cards_1022.sql', 'story_leader_lock.sql', 'story_level_stats.sql', 'story_min_battle.sql', 'admin.sql', 'phaseE_1.sql', 'phaseE_2.sql', 'quest.sql', 'quest_sweep.sql', 'phaseE_3.sql', 'phaseE_4.sql', 'phaseE_5.sql', 'pvp.sql', 'pvp_tier.sql', 'gem.sql', 'guild.sql', 'guild2.sql']) await run(f);
await run('guild3.sql'); await run('guild3.sql');   // 두 번 실행해도 안전
let fails = 0; const ok = (c, m) => { if (!c) { fails++; console.log('FAIL', m); } else console.log('ok  ', m); };
async function as(uid, sql, role = 'authenticated') {
  await db.exec(`reset role; select set_config('request.jwt.claims', '${JSON.stringify(uid ? { sub: uid, email: uid === ADMIN ? 'stevejean77@gmail.com' : 'x@x' } : {})}', false); set role ${role};`);
  try { return { rows: (await db.query(sql)).rows }; } catch (e) { return { err: e.message }; } finally { await db.exec('reset role'); }
}
const one = r => r.rows?.[0] && Object.values(r.rows[0])[0];
const v = async (uid, sql) => one(await as(uid, sql));
const q1 = async sql => one({ rows: (await db.query(sql)).rows });
const gem = async u => +((await q1(`select coalesce(sum(d_free),0) from gem_ledger where user_id='${u}'`)) || 0);
const loyal = async u => +((await q1(`select balance from loyalty_wallet where user_id='${u}'`)) || 0);
for (const u of [A, B, C, D]) await db.exec(`insert into player_state (user_id, level, stamina) values ('${u}', 20, 40)`);
const cid = await q1(`select id from pvp_card_meta order by id limit 1`);
for (const u of [A, B, C, D]) await db.exec(`insert into story_progress (user_id, data) values ('${u}', '{"owned":[{"uid":"c1","id":"${cid}","level":10}]}') on conflict (user_id) do update set data = excluded.data`);
await db.exec(`select _wallet_add('${A}', '{"gold":50000}', 'test')`);
const gid = (await v(A, `select guild_create('검은장미',1,'','open','gold')`)).id;
for (const u of [B, C]) await as(u, `select guild_apply(${gid})`);
await db.exec(`update guild_members set joined_at = now() - interval '9 days'`);
const back = async () => db.exec(`update guild_raid_attempts set started_at = started_at - interval '5 seconds' where finished_at is null`);

let s = await v(A, `select raid_status()`);
ok(s.ok && s.stage === 1 && s.difficulty === 'normal' && s.attempts_left === 3 && s.boss.name === '임유리', '상태: 1단계 임유리 · 하루 3회');
ok(+s.hp_max === 500000 * 5, 'HP = 1인 50만 × 최소 5명');
ok(/not in guild/.test((await as(D, `select raid_status()`)).err || ''), '조직 없으면 불가');
// 난이도
ok(/guild level/.test((await as(A, `select raid_set_difficulty('hard')`)).err || ''), 'Lv3 전에는 어려움 불가');
ok(/not allowed/.test((await as(B, `select raid_set_difficulty('normal')`)).err || ''), '조직원은 난이도 못 바꿈');
await db.exec(`update guilds set level = 5 where id = ${gid}`);
s = await v(A, `select raid_set_difficulty('abyss')`); ok(s.difficulty === 'abyss' && +s.hp_max === 3000000 * 5, '심연 HP');
s = await v(A, `select raid_set_difficulty('normal')`);
// 전투
ok(/card not owned/.test((await as(B, `select raid_start('["zz"]')`)).err || ''), '안 가진 카드 불가');
ok(/fight first/.test((await as(B, `select raid_sweep()`)).err || ''), '직접 싸우기 전 소탕 불가');
let st = await v(B, `select raid_start('["c1"]')`); ok(st.id && st.seed && st.deck.length === 1 && st.deck[0].id === cid, '시작: seed · 서버 스냅샷');
ok(/too fast/.test((await as(B, `select raid_finish(${st.id}, 1000)`)).err || ''), '최소 시간');
await back();
const capv = +(await q1(`select _raid_attempt_cap(1)`));
let f = await v(B, `select raid_finish(${st.id}, ${capv * 10})`); ok(+f.result.damage === capv && (await q1(`select flagged from guild_raid_attempts where id=${st.id}`)), '상한으로 자르고 표시');
ok(/already finished/.test((await as(B, `select raid_finish(${st.id}, 5)`)).err || ''), '두 번 보고 불가');
ok(+f.stage === 1 && +f.hp_left === 2500000 - capv, '공유 HP 감소');
// 소탕
f = await v(B, `select raid_sweep()`); ok(+f.result.damage === Math.floor(capv * 0.9), '소탕 = 최고 90%');
st = await v(B, `select raid_start('["c1"]')`); await back(); await v(B, `select raid_finish(${st.id}, 100)`);
ok(/no attempts/.test((await as(B, `select raid_start('["c1"]')`)).err || '') && /no attempts/.test((await as(B, `select raid_sweep()`)).err || ''), '하루 3회 (소탕 포함)');
// 단계 넘김 (넘친 피해 이월) · 보스 순환
await db.exec(`update guild_raids set hp_left = 10 where guild_id = ${gid}`);
st = await v(C, `select raid_start('["c1"]')`); ok(st.stage === 1, 'C 시작');
await back(); f = await v(C, `select raid_finish(${st.id}, 1000)`);
ok(f.stage === 2 && +f.hp_left === Math.round(2500000 * 1.35) - 990 && f.boss.name === '[각성] 임유리', '처치 → 2단계 (넘친 피해 이월) · 보스 교대');
ok((await q1(`select last_hit from guild_raid_stages where guild_id=${gid} and stage=1`)) === C, '막타 기록');
ok((await q1(`select _raid_boss(6)->>'name'`)) === '임유리' && (await q1(`select _raid_boss(5)->>'name'`)) === '이지영', '6단계 = 다시 임유리');
ok(/raid started/.test((await as(A, `select raid_set_difficulty('hard')`)).err || ''), '피해 들어간 뒤 난이도 고정');
// 단계 보상: 시도 안 한 A 도 받음 · D(나중 가입)는 처치 이후 가입이면 못 받음
const g0 = await gem(A);
let c = await v(A, `select raid_claim()`); ok(+c.got.gem === 30 && +c.got.gold === 2000 && (await gem(A)) - g0 === 30, '단계 보상 (시도 안 해도)');
ok(/nothing to claim/.test((await as(A, `select raid_claim()`)).err || ''), '두 번 못 받음');
await as(D, `select guild_apply(${gid})`);
ok(/nothing to claim/.test((await as(D, `select raid_claim()`)).err || ''), '처치 뒤 가입자는 그 단계 못 받음');
ok(+(await q1(`select _raid_stage_reward('abyss', 3)->>'gem'`)) === Math.round((30 + 150) * 2.5) && +(await q1(`select _raid_stage_reward('normal', 5)->>'tickets'`)) === 1, '단계 보상 배율 · 3단계 · 5단계');
// 주간 정산
await db.exec(`create or replace function public._raid_now() returns timestamptz language sql stable as $$ select _raid_end(_guild_week()) + interval '1 minute' $$`);
ok(/raid ended/.test((await as(C, `select raid_start('["c1"]')`)).err || ''), '정산 시간엔 전투 불가');
const gb = await gem(B), gc = await gem(C), ga = await gem(A);
c = await v(B, `select raid_claim()`); ok(c.got.rank === 1 && (await gem(B)) - gb === 1000 + 100 + 30, 'B 1위: 1000 + 참여 100 + 단계');
c = await v(C, `select raid_claim()`); ok(c.got.rank === 2 && (await gem(C)) - gc === 500 + 100 + 30, 'C 2위: 500 + 100 + 단계');
c = await v(A, `select raid_claim()`); ok(c.got.rank == null && (await gem(A)) - ga === 100, 'A 시도 0: 참여 100');
await db.exec(`update guild_members set joined_at = _raid_end(_guild_week()) - interval '2 hours' where user_id = '${D}'`);
ok(/nothing to claim/.test((await as(D, `select raid_claim()`)).err || ''), '정산 24시간 안 가입자 순위/참여 못 받음');
ok((await q1(`select count(*) from guild_claims where ref like 'raidrk:%'`)) == 3, '순위 보상 한 번씩');
await db.exec(`create or replace function public._raid_now() returns timestamptz language sql stable as $$ select now() $$`);
// 보안
ok(!!(await as(A, `select * from guild_raids`)).err && !!(await as(A, `select * from guild_raid_attempts`)).err, '테이블 직접 읽기 불가');
ok(!!(await as(A, `select _raid_hit(${gid}, _guild_week(), '${A}', 999999999)`)).err, '내부 함수 불가');
ok(!!(await as(null, `select raid_status()`, 'anon')).err, 'anon 불가');
ok(!!(await as(B, `select raid_finish(${st.id}, 5)`)).err, '남의 전투 보고 불가');
// 관리자
let ad = await v(ADMIN, `select admin_guild_raid(${gid})`); ok(ad.flagged.length === 1, '관리자: 의심 기록');
const bid = await q1(`select id from guild_raid_attempts where flagged limit 1`);
ok(/reason/.test((await as(ADMIN, `select admin_raid_void(${bid}, '')`)).err || ''), '무효 사유 필수');
const before = +(await q1(`select damage from guild_raid_damage where user_id='${B}'`));
await as(ADMIN, `select admin_raid_void(${bid}, '상한 초과')`); ok(+(await q1(`select damage from guild_raid_damage where user_id='${B}'`)) === before - capv, '무효: 개인 누적에서 뺌');
ok(!!(await as(A, `select admin_raid_void(${bid}, 'x')`)).err, '일반 유저 관리자 불가');
console.log(fails ? `${fails} FAIL` : 'ALL PASS'); process.exit(fails ? 1 : 0);
