// supabase/guild2.sql 검증 (PGlite): 집결·출석률 보너스·주간 개근·일일/주간 의뢰·이벤트 훅·보안·연동 복사본
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
for (const f of ['story.sql', 'gacha.sql', 'story_server.sql', 'story_gacha.sql', 'story_levels.sql', 'story_merge.sql', 'story_ch2.sql', 'story_cards_1022.sql', 'story_leader_lock.sql', 'story_level_stats.sql', 'story_min_battle.sql', 'admin.sql', 'phaseE_1.sql', 'phaseE_2.sql', 'quest.sql', 'quest_sweep.sql', 'phaseE_3.sql', 'phaseE_4.sql', 'phaseE_5.sql', 'pvp.sql', 'pvp_tier.sql', 'gem.sql', 'guild.sql']) await run(f);
await run('guild2.sql'); await run('guild2.sql');   // 두 번 실행해도 안전
let fails = 0; const ok = (c, m) => { if (!c) { fails++; console.log('FAIL', m); } else console.log('ok  ', m); };
async function as(uid, sql, role = 'authenticated') {
  await db.exec(`reset role; select set_config('request.jwt.claims', '${JSON.stringify(uid ? { sub: uid, email: uid === ADMIN ? 'stevejean77@gmail.com' : 'x@x' } : {})}', false); set role ${role};`);
  try { return { rows: (await db.query(sql)).rows }; } catch (e) { return { err: e.message }; } finally { await db.exec('reset role'); }
}
const one = r => r.rows?.[0] && Object.values(r.rows[0])[0];
const v = async (uid, sql) => one(await as(uid, sql));
const q1 = async sql => one({ rows: (await db.query(sql)).rows });
const loyal = async u => +((await q1(`select balance from loyalty_wallet where user_id='${u}'`)) || 0);
const gold = async u => +((await q1(`select gold from player_wallet where user_id='${u}'`)) || 0);
for (const u of [A, B, C, D]) await db.exec(`insert into player_state (user_id, level, stamina) values ('${u}', 20, 40)`);
await db.exec(`select _wallet_add('${A}', '{"gold":50000}', 'test')`);
const gid = (await v(A, `select guild_create('검은장미',1,'','open','gold')`)).id;
for (const u of [B, C]) await as(u, `select guild_apply(${gid})`);
await db.exec(`update guild_members set joined_at = now() - interval '2 days'`);   // 오늘 가입 아님

// 집결
ok(/not in guild/.test((await as(D, `select guild_checkin()`)).err || ''), '조직 없으면 집결 불가');
let r = await as(A, `select guild_checkin()`); let x = one(r);
ok(!r.err && x.checked && await loyal(A) === 20 && await gold(A) === 1000, '집결: 충성 20 · 골드 1,000 ' + (r.err || ''));
ok(+(await q1(`select exp from guilds where id=${gid}`)) === 10, '집결: 세력 +10');
ok(/already/.test((await as(A, `select guild_checkin()`)).err || ''), '하루 1번');
ok(x.count === 1 && x.total === 3 && x.tiers[0].reached && !x.tiers[1].reached, '출석 1/3 = 33% → 30% 달성');
r = await as(A, `select guild_rally_claim(30)`); ok(!r.err && await loyal(A) === 30 && +(await q1(`select exp from guilds where id=${gid}`)) === 40, '30% 보너스 충성 10 · 조직 세력 30');
ok(/already/.test((await as(A, `select guild_rally_claim(30)`)).err || ''), '보너스 1번');
ok(/not reached/.test((await as(A, `select guild_rally_claim(60)`)).err || ''), '60% 미달');
ok(/check in first/.test((await as(B, `select guild_rally_claim(30)`)).err || ''), '집결 안 하면 보너스 불가');
await as(B, `select guild_checkin()`); await as(C, `select guild_checkin()`);
await db.exec(`select _gem_add('${C}', 0, 0, 'x', null, '{}')`);
r = await as(C, `select guild_rally_claim(90)`); ok(!r.err && +(await q1(`select gem_free from player_wallet where user_id='${C}'`)) === 5, '90% 보너스 심연석 +5 ' + (r.err || ''));
const e0 = +(await q1(`select exp from guilds where id=${gid}`)); await as(B, `select guild_rally_claim(90)`);
ok(+(await q1(`select exp from guilds where id=${gid}`)) === e0, '조직 세력 보너스는 조직당 1번');
// 오늘 가입자는 출석률 계산 제외
await as(D, `select guild_apply(${gid})`); await as(D, `select guild_checkin()`);
x = await v(A, `select guild_rally()`); ok(x.count === 3 && x.total === 4, '오늘 가입자는 출석 수 제외 (3/4)');
// 다른 조직으로 옮겨도 하루 1번
await as(D, `select guild_leave()`); await db.exec(`delete from guild_cooldowns`); await db.exec(`select _wallet_add('${D}', '{"gold":50000}', 'test')`);
await as(D, `select guild_create('까마귀',2,'','open','gold')`);
ok(/already/.test((await as(D, `select guild_checkin()`)).err || ''), '조직을 옮겨도 하루 1번');
// 주간 개근
ok(/not reached/.test((await as(A, `select guild_rally_claim(7)`)).err || ''), '개근 미달');
await db.exec(`insert into guild_attendance (user_id, day, guild_id) select '${A}', _guild_week() + i, ${gid} from generate_series(0, 6) i on conflict do nothing`);
const t0 = +((await q1(`select tickets from story_gacha where user_id='${A}'`)) || 0);
r = await as(A, `select guild_rally_claim(7)`); ok(!r.err && +(await q1(`select tickets from story_gacha where user_id='${A}'`)) === t0 + 1, '7일 개근: 충성 100 + 소환권 ' + (r.err || ''));
// 일일 의뢰
await db.exec(`delete from guild_daily_quests where user_id='${A}'`);
await db.exec(`insert into guild_daily_quests (user_id, day, slot, qkey, goal) values ('${A}', _guild_day(), 1, 'd_draw', 1), ('${A}', _guild_day(), 2, 'd_levelup', 1), ('${A}', _guild_day(), 3, 'd_tower', 1)`);
let qs = await v(A, `select guild_quests()`); ok(qs.daily.length === 3 && qs.weekly.length === 3 && qs.reroll_left === 1, '의뢰: 일일 3 · 주간 3');
ok(qs.weekly.every(w => w.goal % 4 === 0 || w.goal % 3 === 0), '주간 목표 = 1인 목표 × 인원');
ok(/not reached/.test((await as(A, `select guild_quest_claim(1)`)).err || ''), '미완료 의뢰 보상 불가');
// 트리거: 뽑기 · 레벨업 · 탑
await db.exec(`insert into story_gacha_log (user_id, card_id, grade) values ('${A}', '1000000001', 'RARE')`);
await db.exec(`select _wallet_add('${A}', '{"gold":-10}', 'card_levelup')`);
await db.exec(`insert into quest_progress (user_id) values ('${A}') on conflict do nothing; update quest_progress set clears = clears + 1 where user_id = '${A}'`);
qs = await v(A, `select guild_quests()`); ok(qs.daily.every(d => d.progress === 1), '뽑기·레벨업·탑 트리거로 진행 ' + JSON.stringify(qs.daily.map(d => d.progress)));
const l0 = await loyal(A);
for (const s of [1, 2, 3]) await as(A, `select guild_quest_claim(${s})`);
ok(await loyal(A) === l0 + 10 + 10 + 15, '일일 의뢰 보상 충성');
ok(/already/.test((await as(A, `select guild_quest_claim(1)`)).err || ''), '의뢰 보상 1번');
r = await as(A, `select guild_quest_claim(0)`); ok(!r.err && await loyal(A) === l0 + 35 + 20, '3개 완료 보너스 충성 20');
// 교체
await db.exec(`delete from guild_daily_quests where user_id='${B}'`);
qs = await v(B, `select guild_quests()`); const k0 = qs.daily[0].key;
r = await as(B, `select guild_quest_reroll(1)`); ok(!r.err && one(r).daily[0].key !== k0 && one(r).reroll_left === 0, '교체 1번');
ok(/reroll used/.test((await as(B, `select guild_quest_reroll(2)`)).err || ''), '교체는 하루 1번');
// PvP 승리 이벤트 (pvp_report → _guild_feed → _guild_event)
await db.exec(`delete from guild_daily_quests where user_id='${C}'; insert into guild_daily_quests (user_id, day, slot, qkey, goal) values ('${C}', _guild_day(), 1, 'd_pvp', 2), ('${C}', _guild_day(), 2, 'd_phase', 5), ('${C}', _guild_day(), 3, 'd_stamina', 60)`);
await db.exec(`insert into story_progress (user_id, data) values ('${C}', '{"owned":[{"uid":"a","id":"1000000001"},{"uid":"b","id":"1000000002"}],"leader":"a"}') on conflict (user_id) do update set data = excluded.data`);
await as(C, `select pvp_set_deck('open','1v1',0,'["a","b"]')`);
const s = await v(C, `select pvp_start('open','1v1')`); await as(C, `select pvp_report(${s.id}, 1, 0)`);
qs = await v(C, `select guild_quests()`); ok(qs.daily[0].progress === 1, 'PvP 승리 → 의뢰 진행');
// 스토리 소탕 이벤트 (story_sweep: 페이즈·행동력)
await db.exec(`update story_progress set data = jsonb_set(data, '{cleared}', '{"1":[1]}') where user_id = '${C}'; update player_state set level = 20, stamina = 40, stamina_at = now() where user_id = '${C}'`);
r = await as(C, `select story_sweep(1, 1, 5)`);
qs = await v(C, `select guild_quests()`); ok(!r.err && qs.daily[1].progress === 5 && qs.daily[2].progress === 30, '소탕 5회 → 페이즈 5 · 행동력 30 ' + (r.err || JSON.stringify(qs.daily.map(d => d.progress))));
// 주간 공동 의뢰
await db.exec(`delete from guild_weekly_quests where guild_id=${gid}; delete from guild_weekly_contrib where guild_id=${gid};
  insert into guild_weekly_quests (guild_id, week, slot, qkey, goal) values (${gid}, _guild_week(), 1, 'w_draw', 15), (${gid}, _guild_week(), 2, 'w_tower', 15), (${gid}, _guild_week(), 3, 'w_checkin', 15)`);
for (let i = 0; i < 8; i++) await db.exec(`insert into story_gacha_log (user_id, card_id, grade) values ('${B}', '1000000001', 'RARE')`);
qs = await v(B, `select guild_quests()`); ok(qs.weekly[0].progress === 8 && qs.weekly[0].mine === 8 && qs.weekly[0].tiers[0].reached && !qs.weekly[0].tiers[1].reached, '주간: 8/15 → 50% 달성');
ok(/contribution too low/.test((await as(A, `select guild_weekly_claim(1, 50)`)).err || ''), '기여 1% 미만 보상 불가');
const eb = +(await q1(`select exp from guilds where id=${gid}`)); r = await as(B, `select guild_weekly_claim(1, 50)`);
ok(!r.err && +(await q1(`select exp from guilds where id=${gid}`)) === eb + 100, '50% 보상 · 조직 세력 +100 ' + (r.err || ''));
for (let i = 0; i < 7; i++) await db.exec(`insert into story_gacha_log (user_id, card_id, grade) values ('${B}', '1000000001', 'RARE')`);
const gb = +((await q1(`select gem_free from player_wallet where user_id='${B}'`)) || 0);
r = await as(B, `select guild_weekly_claim(1, 100)`); ok(!r.err && +(await q1(`select gem_free from player_wallet where user_id='${B}'`)) === gb + 10, '100%: 심연석 +10 · 골드 3,000 ' + (r.err || ''));
ok(/not reached/.test((await as(B, `select guild_weekly_claim(1, 150)`)).err || ''), '150% 미달');
// 빨간 점
x = await v(C, `select guild_dots()`); ok(x.ok && typeof x.rally === 'boolean' && typeof x.quest === 'boolean', '빨간 점');
// 보안
ok(!!(await as(A, `select * from guild_attendance`)).err && !!(await as(A, `select * from guild_claims`)).err, '테이블 직접 읽기 불가');
ok(!!(await as(A, `select _guild_event('${A}', 'draw', 99)`)).err && !!(await as(A, `select _guild_reward('${A}', ${gid}, '{"gem":999}', 'x', 'y')`)).err, '내부 함수 호출 불가');
ok(!!(await as(A, `insert into guild_attendance (user_id, day, guild_id) values ('${A}', current_date + 1, ${gid})`)).err, '출석 직접 쓰기 불가');
ok(!!(await as(null, `select guild_rally()`, 'anon')).err, 'anon 불가');
// 조직 없는 사람 이벤트는 무시 + 원래 동작 유지
await db.exec(`insert into auth.users (id, email) values ('${id(9)}', 'z@x')`);
ok(!(await as(ADMIN, `select 1`)).err && !(await db.query(`insert into story_gacha_log (user_id, card_id, grade) values ('${id(9)}', '1', 'RARE') returning id`).then(() => null, e => e)), '조직 없는 유저 뽑기 정상');
// 관리자
r = await as(ADMIN, `select admin_guild_activity(${gid})`); ok(!r.err && one(r).weekly.length === 3, '관리자 활동 보기');
ok(!!(await as(A, `select admin_guild_reset_weekly(${gid}, 'x')`)).err, '일반 유저 관리자 불가');
// 복사본 = 원본
const fn = (t, n) => { const i = t.indexOf(`create or replace function public.${n}(`); return t.slice(i, t.indexOf('end $$;', i)); };
const G = src('guild2.sql');
for (const [f, n] of [['phaseE_3.sql', 'story_complete_phase'], ['phaseE_5.sql', 'story_sweep'], ['guild.sql', '_guild_feed']]) ok(fn(src(f), n) === fn(G, n), `guild2.sql 의 ${n} = ${f}`);
console.log(fails ? `${fails} FAIL` : 'ALL PASS'); process.exit(fails ? 1 : 0);
