// supabase/guild4.sql 검증 (PGlite): 구역 전쟁 — 시즌 시간 · 참가/배치 · 잠금 · 대진 · NPC · 공격 순서/횟수/HP 유지/2번 덱 · 보스 즉승 · 정산/승점 · 보상 · 보안 · 관리자
import { readFileSync } from 'fs';
import { createRequire } from 'module';
const require = createRequire(import.meta.url);
let PGlite; try { ({ PGlite } = require('@electric-sql/pglite')); } catch { console.log('SKIP: @electric-sql/pglite 없음'); process.exit(0); }
const db = new PGlite();
const id = n => `00000000-0000-0000-0000-0000000000${String(n).padStart(2, '0')}`;
const ADMIN = id(1), U = Array.from({ length: 34 }, (_, i) => id(i + 10));   // U[0..10] = 1조직, U[11..21] = 2조직, U[22..32] = 3조직, U[33] = 무소속
await db.exec(`create role anon nologin; create role authenticated nologin; create schema auth;
create table auth.users (id uuid primary key, email text, email_confirmed_at timestamptz, created_at timestamptz default now(), last_sign_in_at timestamptz, raw_user_meta_data jsonb default '{}');
create function auth.jwt() returns jsonb language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $$;
create function auth.uid() returns uuid language sql stable as $$ select nullif(auth.jwt()->>'sub', '')::uuid $$;
grant usage on schema auth to anon, authenticated; grant execute on all functions in schema auth to anon, authenticated; grant usage on schema public to anon, authenticated;
create table public.profiles (id uuid primary key, nickname text);
create table public.matches (id bigint generated always as identity primary key, user_id uuid, result text, reason text, turns int, damage int, mvp_name text, created_at timestamptz default now());
create table public.gallery (user_id uuid, card_id text, count int, mvp_count int);
insert into auth.users (id, email, email_confirmed_at) values ('${ADMIN}','stevejean77@gmail.com',now()), ${U.map(u => `('${u}','${u}@x',now())`).join(',')};
insert into profiles (id, nickname) values ${U.map((u, i) => `('${u}','p${i}')`).join(',')};`);
const src = f => readFileSync(new URL('../supabase/' + f, import.meta.url), 'utf8');
const run = f => db.exec(src(f));
for (const f of ['story.sql', 'gacha.sql', 'story_server.sql', 'story_gacha.sql', 'story_levels.sql', 'story_merge.sql', 'story_ch2.sql', 'story_cards_1022.sql', 'story_leader_lock.sql', 'story_level_stats.sql', 'story_min_battle.sql', 'admin.sql', 'phaseE_1.sql', 'phaseE_2.sql', 'quest.sql', 'quest_sweep.sql', 'phaseE_3.sql', 'phaseE_4.sql', 'phaseE_5.sql', 'pvp.sql', 'pvp_tier.sql', 'gem.sql', 'guild.sql', 'guild2.sql', 'guild3.sql']) await run(f);
await run('guild4.sql'); await run('guild4.sql');   // 두 번 실행해도 안전
await run('guild4_ui.sql'); await run('guild4_ui.sql');
await run('manual_battle.sql'); await run('war_manual.sql'); await run('war_manual.sql');   // 수동 전투 기록 (war_log)
let fails = 0; const ok = (c, m) => { if (!c) { fails++; console.log('FAIL', m); } else console.log('ok  ', m); };
async function as(uid, sql, role = 'authenticated') {
  await db.exec(`reset role; select set_config('request.jwt.claims', '${JSON.stringify(uid ? { sub: uid, email: uid === ADMIN ? 'stevejean77@gmail.com' : 'x@x' } : {})}', false); set role ${role};`);
  try { return { rows: (await db.query(sql)).rows }; } catch (e) { return { err: e.message }; } finally { await db.exec('reset role'); }
}
const one = r => r.rows?.[0] && Object.values(r.rows[0])[0];
const v = async (uid, sql) => one(await as(uid, sql));
const q1 = async sql => one({ rows: (await db.query(sql)).rows });
const err = async (uid, sql) => (await as(uid, sql)).err || '';
const at = t => db.exec(`create or replace function public._war_now() returns timestamptz language sql stable as $$ select '${t}+09'::timestamptz $$`);
const gem = async u => +((await q1(`select coalesce(sum(d_free),0) from gem_ledger where user_id='${u}'`)) || 0);
const ids = (await db.query(`select id from pvp_card_meta order by id limit 8`)).rows.map(r => r.id);
for (const u of U) {
  await db.exec(`insert into player_state (user_id, level, stamina) values ('${u}', 20, 40)`);
  await db.exec(`insert into story_progress (user_id, data) values ('${u}', '${JSON.stringify({ owned: ids.map((x, i) => ({ uid: 'c' + i, id: x, level: 10 })) })}') on conflict (user_id) do update set data = excluded.data`);
  await db.exec(`select _wallet_add('${u}', '{"gold":50000}', 'test')`);
}
await at('2026-11-14 12:00');
ok((await q1(`select _war_phase('2026-11-18')`)) === 'soon', '토요일 = 신청 전');
await at('2026-11-16 12:00');
ok((await q1(`select _war_season()`)).toISOString?.().slice(0, 10) === '2026-11-18' || String(await q1(`select _war_season()::text`)) === '2026-11-18', '시즌 = 셋째 수요일 (11/18)');
ok((await q1(`select _war_third_wed('2026-12-05')::text`)) === '2026-12-16' && (await q1(`select _war_phase('2026-11-18')`)) === 'signup', '12월 셋째 수 · 신청 기간');
// 조직 3개 (11명씩)
const G = [];
for (let g = 0; g < 3; g++) {
  const boss = U[g * 11];
  const gid = (await v(boss, `select guild_create('조직${g}', ${g + 1}, '', 'open', 'gold')`)).id; G.push(gid);
  ok(/need members/.test(await err(boss, `select war_enter()`)) || g > 0, g === 0 ? '10명 미만 참가 불가' : '');
  await db.exec(`update guilds set exp = ${(3 - g) * 1000} where id = ${gid}`);
  for (let k = 1; k < 11; k++) await as(U[g * 11 + k], `select guild_apply(${gid})`);
}
ok(+(await q1(`select count(*) from guild_members where guild_id = ${G[0]}`)) === 11, '조직원 11명');
ok(/not allowed/.test(await err(U[1], `select war_enter()`)), '조직원은 참가 신청 불가');
for (let g = 0; g < 3; g++) { const r = await v(U[g * 11], `select war_enter()`); ok(r.entry && r.entry.status === 'in', `조직${g} 참가`); }
// 배치 · 덱
let s = await v(U[0], `select war_set_slot(14, '${U[0]}')`); ok(s.roster[13].user_id === U[0], '보스가 보스 칸');
ok(/not allowed/.test(await err(U[1], `select war_set_slot(1, '${U[1]}')`)), '배치는 보스만');
await v(U[0], `select war_set_slot(1, '${U[1]}')`);
for (const u of U.slice(0, 33)) { await as(u, `select war_set_deck('def1', '["c0","c1"]')`); await as(u, `select war_set_deck('atk1', '["c2","c3","c4"]')`); }
for (const u of U.slice(11, 22)) await as(u, `select war_set_deck('def2', '["c5"]')`);   // 2조직: 방어 2번 덱 있음
ok(/same card/.test(await err(U[0], `select war_set_deck('def2', '["c0"]')`)), '방어 덱 1·2 같은 카드 불가');
ok(/card not owned/.test(await err(U[0], `select war_set_deck('atk2', '["zz"]')`)), '안 가진 카드 불가');
// 개인 참가 신청 (guild4_ui.sql)
let wu = await v(U[5], `select war_signup(true)`); ok(wu.me_signed && wu.signed.includes(U[5]), '조직원 개인 참가 신청');
await v(U[6], `select war_signup(true)`); await v(U[6], `select war_signup(false)`);
wu = await v(U[0], `select war_ui()`); ok(wu.signed.length === 1 && !wu.me_signed, '신청 취소 · 신청자 목록');
ok(!!(await as(null, `select war_ui()`, 'anon')).err && !!(await as(U[0], `select * from war_signups`)).err, 'anon · 테이블 직접 접근 불가');
// 시즌 시작: 잠금 · 대진
await at('2026-11-18 10:00');
s = await v(U[0], `select war_status()`);
ok(s.phase === 'live' && s.day === 1 && s.entry.locked, '1일차 09시: 잠김 · 전투 중');
ok(/defense locked/.test(await err(U[0], `select war_set_deck('def1', '["c3"]')`)) && !(await err(U[0], `select war_set_deck('atk2', '["c6"]')`)), '방어 덱 잠김 · 공격 덱은 바꿀 수 있음');
ok(/signup closed/.test(await err(U[0], `select war_set_slot(2, '${U[2]}')`)), '배치 잠김');
ok((await q1(`select user_id::text from war_roster where season='2026-11-18' and guild_id=${G[0]} and slot=2`)) === U[5], '빈 칸 자동 배치는 신청자 먼저');
ok(/signup closed/.test(await err(U[7], `select war_signup(true)`)), '잠긴 뒤 신청 불가');
ok(+(await q1(`select count(*) from war_roster where season='2026-11-18' and guild_id=${G[0]} and user_id is not null`)) === 11, '안 배치된 조직원 자동 배치');
ok(+(await q1(`select count(*) from war_matches where season='2026-11-18' and day=1`)) === 2, '3조직 → 2경기 (하나는 NPC)');
const m1 = await q1(`select id from war_matches where day=1 and guild_a=${G[0]}`);
ok(+(await q1(`select guild_b from war_matches where id=${m1}`)) === G[1], '1일차: 세력 비슷한 조직끼리');
ok((await q1(`select guild_b from war_matches where day=1 and guild_a=${G[2]}`)) == null, '남는 조직 = 동네 불량배파');
ok(+(await q1(`select count(*) from war_ajits where match_id=${m1} and npc`)) === 20, '빈 10칸 × 2쪽 = 동네 불량배');
const npc = await q1(`select _war_npc_deck('x:1', _war_scale('2026-11-18', 0))`);
const HR = ['1000000031', '1000000032', '2000000033', '2000000034', '2000000035', '2000000036', '2000000037', '2000000038'];
let mixed = true, shape = true;
for (let k = 0; k < 40; k++) { const d = await q1(`select _war_npc_deck('t${k}', 1)`); const g = new Set(d.map(c => c.id[0])); if (g.size < 2) mixed = false; if (d.filter(c => HR.includes(c.id)).length !== 2 || d.length !== 5) shape = false; }
ok(mixed && shape && npc[0].scale === 1 && npc[0].level === 10, '불량배 덱: HR 2 + R 3 · 남녀 섞임 · 레벨 10 고정');
ok(JSON.stringify(npc) === JSON.stringify(await q1(`select _war_npc_deck('x:1', 1)`)), '불량배 덱 seed 고정');
ok((await q1(`select _war_numbers()->'standings'->>'draw'`)) === '2', '무승부 = 2점');
// 공격
s = await v(U[3], `select war_status()`); ok(s.match && s.match.opponent.name === '조직1' && s.match.me.attacks_left === 5 && !s.match.gate_open, '상태: 상대 · 5회 · 방어조 먼저');
ok(/defense first/.test(await err(U[3], `select war_start(6, 1)`)), '방어조 5곳 먼저');
ok(/no attack deck/.test(await err(U[3], `select war_start(1, 2)`)), '공격 덱 없음');
let st = await v(U[3], `select war_start(1, 1)`);
ok(st.id && st.atk.length === 3 && st.def.length === 2 && +st.def_buff.def === 1.2 && st.target.deck === 1, '시작: 스냅샷 · 방어조 방어 +20%');
ok(/target busy/.test(await err(U[4], `select war_start(1, 1)`)), '전투 중인 아지트 잠금');
ok(/too fast/.test(await err(U[3], `select war_finish(${st.id}, true, '{}', '{}')`)), '최소 시간');
ok(/no battle/.test(await err(U[4], `select war_log(${st.id}, '[]')`)), '수동 기록: 남의 공격 불가');
ok(/bad actions/.test(await err(U[3], `select war_log(${st.id}, '{"k":1}')`)), '수동 기록: 배열만');
ok(!(await as(U[3], `select war_log(${st.id}, '[{"k":"end"}]')`)).err, '수동 기록 저장');
ok(/already logged/.test(await err(U[3], `select war_log(${st.id}, '[]')`)), '수동 기록은 한 번만');
const back = () => db.exec(`update war_attacks set started_at = started_at - interval '5 seconds' where finished_at is null`);
await back();
let f = await v(U[3], `select war_finish(${st.id}, true, '{"c2":5,"c3":999999}', '{}')`);
ok(f.result.win && f.result.next_deck && !f.result.destroyed, '1번 덱 격파 → 2번 덱 등장');
ok(+(await q1(`select (state->>'c3')::int from war_atk_state where match_id=${m1} and user_id='${U[3]}' and deck=1`)) === 60000 && (await q1(`select flagged from war_attacks where id=${st.id}`)), 'HP 부풀리기 → 잘리고 표시');
ok((await q1(`select state->>'c4' from war_atk_state where match_id=${m1} and user_id='${U[3]}'`)) === '0', '보고 안 된 카드 = 쓰러짐');
st = await v(U[3], `select war_start(1, 1)`); ok(st.atk.length === 2 && +st.atk.find(c => c.uid === 'c2').hp === 5 && st.target.deck === 2, '다음 전투: 쓰러진 카드 빠짐 · 깎인 HP 유지 · 2번 덱');
await back(); f = await v(U[3], `select war_finish(${st.id}, false, '{"c2":3}', '{"c5":7}')`);
ok(!f.result.win && (await q1(`select state->>'c5' from war_ajits where match_id=${m1} and side=1 and slot=1`)) === '7', '방어 승리: 방어 카드 HP 유지');
st = await v(U[3], `select war_start(1, 1)`); await back(); f = await v(U[3], `select war_finish(${st.id}, true, '{"c2":1}', '{}')`);
ok(f.result.destroyed && f.match.score_me === 200, '2번 덱도 격파 → 파괴 +200');
st = await v(U[3], `select war_start(2, 1)`); await back(); await v(U[3], `select war_finish(${st.id}, false, '{}', '{}')`);
ok(/deck dead/.test(await err(U[3], `select war_start(2, 1)`)), '전멸한 공격 덱 못 씀');
await as(U[3], `select war_set_deck('atk2', '["c6"]')`);
st = await v(U[3], `select war_start(2, 2)`); await back(); await v(U[3], `select war_finish(${st.id}, false, '{"c6":1}', '{}')`);
ok(/no attacks/.test(await err(U[3], `select war_start(2, 2)`)), '하루 5회');
// 방어조 다 부수면 자유 공격 · 보스 파괴 = 즉시 승리
await db.exec(`update war_ajits set destroyed_at = now() where match_id=${m1} and side=1 and role='def'`);
await db.exec(`update war_matches set score_a = 1000 where id=${m1}`);
s = await v(U[5], `select war_status()`); ok(s.match.gate_open, '방어조 전멸 → 자유 공격');
st = await v(U[0], `select war_start(14, 1)`); ok(+st.atk_buff.atk === 1.25 && +st.def_buff.def === 1.25, '보스: 공방 +25%');
await back(); f = await v(U[0], `select war_finish(${st.id}, true, '{"c2":10}', '{}')`); ok(f.result.next_deck && !f.match.ended, '보스도 2번 덱');
st = await v(U[0], `select war_start(14, 1)`); await back(); f = await v(U[0], `select war_finish(${st.id}, true, '{"c2":10}', '{}')`);
ok(f.result.boss_kill && f.match.ended && f.match.winner_me, '보스 파괴 = 즉시 승리');
ok(/match ended/.test(await err(U[5], `select war_start(6, 1)`)), '끝난 경기 공격 불가');
// 아지트 파괴된 사람은 공격 불가
const m2 = await q1(`select id from war_matches where day=1 and guild_a=${G[2]}`);
await db.exec(`update war_ajits set destroyed_at = now() where match_id=${m2} and side=0 and user_id='${U[23]}'`);
ok(/ajit destroyed/.test(await err(U[23], `select war_start(1, 1)`)), '내 아지트 파괴 → 공격 불가');
// 무효 (정산 전)
const ad = await v(ADMIN, `select admin_war(null)`); ok(ad.flagged.length >= 1, '관리자: 의심 기록');
ok(/reason/.test(await err(ADMIN, `select admin_war_void(${st.id}, '')`)), '무효 사유 필수');
// 23시 정산
await at('2026-11-18 23:30');
s = await v(U[0], `select war_status()`);
ok(s.phase === 'rest' && s.standings[0].guild_id === G[0] && s.standings[0].points === 4 && s.standings[0].boss_kills === 1, '정산: 승 3 + 보스 1 = 4점');
ok(/not battle time/.test(await err(U[0], `select war_start(1, 1)`)), '23시 뒤 전투 불가');
const g0 = await q1(`select balance from loyalty_wallet where user_id='${U[5]}'`);
let c = await v(U[5], `select war_claim()`); ok(+c.got.loyalty === 80 && +c.got.gold === 7000, '승리 보상 + 보스 파괴 보너스 (전원)');
c = await v(U[12], `select war_claim()`); ok(+c.got.loyalty === 10 && !c.got.gold, '진 조직: 충성 10');
ok(/nothing to claim/.test(await err(U[5], `select war_claim()`)), '두 번 못 받음');
// 2일차: 승점 가까운 상대 · 같은 상대 피함
await at('2026-11-19 10:00');
await v(U[0], `select war_status()`);
const d2 = (await db.query(`select guild_a, guild_b from war_matches where day=2 order by id`)).rows;
ok(d2.length === 2 && d2[0].guild_a === G[0] && d2[0].guild_b === G[2], '2일차: 승점순 · 어제 상대 피함');
// 시즌 끝 → 순위 보상
await at('2026-11-22 23:30');
await v(U[0], `select war_status()`);
ok(+(await q1(`select count(*) from war_matches where season='2026-11-18'`)) === 10 && +(await q1(`select count(*) from war_matches where season='2026-11-18' and not settled`)) === 0, '5일 × 2경기 모두 정산');
const rk = (await v(U[0], `select war_status()`)).standings; const top = rk[0].guild_id, topU = U[G.indexOf(top) * 11 + 7];
const gg = await gem(topU); c = await v(topU, `select war_claim()`);
ok(c.got.rank === 1 && (await gem(topU)) - gg === 1100, '시즌 1위: 심연석 1000 + 참가 100');
const lastG = rk[rk.length - 1].guild_id, lu = U[G.indexOf(lastG) * 11 + 7], lg = await gem(lu); await as(lu, `select war_claim()`);
ok((await gem(lu)) - lg === 600, '시즌 3위: 500 + 100');
await at('2026-11-23 12:00');
ok(String(await q1(`select _war_season()::text`)) === '2026-12-16' && (await v(U[0], `select war_status()`)).phase === 'soon', '다음 날 = 다음 시즌 신청 전');
ok(/signup closed/.test(await err(U[0], `select war_enter()`)), '셋째 주 일요일 전 신청 불가');
await at('2026-12-13 00:30');
ok((await v(U[0], `select war_status()`)).phase === 'signup', '셋째 주 일요일 = 신청 시작');
// 보안
ok(!!(await as(U[0], `select * from war_ajits`)).err && !!(await as(U[0], `select * from war_decks`)).err, '테이블 직접 읽기 불가');
ok(!!(await as(U[0], `select _war_settle(1)`)).err && !!(await as(U[0], `select _war_tick()`)).err, '내부 함수 불가');
ok(!!(await as(null, `select war_status()`, 'anon')).err && !!(await as(null, `select war_log(1, '[]')`, 'anon')).err, 'anon 불가');
ok(+(await q1(`select (_war_numbers()->>'open_minutes')::int`)) === 20, '공격 제한 시간 20분 (수동)');
ok(!!(await as(U[0], `select admin_war(null)`)).err, '일반 유저 관리자 불가');
console.log(fails ? `${fails} FAIL` : 'ALL PASS'); process.exit(fails ? 1 : 0);
