// supabase/guild.sql 검증 (PGlite): 창설·가입·권한·쿨타임·세력/충성·상점·보스 승계·보안·연동 복사본
import { readFileSync } from 'fs';
import { createRequire } from 'module';
const require = createRequire(import.meta.url);
let PGlite; try { ({ PGlite } = require('@electric-sql/pglite')); } catch { console.log('SKIP: @electric-sql/pglite 없음'); process.exit(0); }
const db = new PGlite();
const id = n => `00000000-0000-0000-0000-0000000000${String(n).padStart(2, '0')}`;
const ADMIN = id(1), A = id(2), B = id(3), C = id(4), D = id(5), E = id(6);
await db.exec(`create role anon nologin; create role authenticated nologin; create schema auth;
create table auth.users (id uuid primary key, email text, email_confirmed_at timestamptz, created_at timestamptz default now(), last_sign_in_at timestamptz, raw_user_meta_data jsonb default '{}');
create function auth.jwt() returns jsonb language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $$;
create function auth.uid() returns uuid language sql stable as $$ select nullif(auth.jwt()->>'sub', '')::uuid $$;
grant usage on schema auth to anon, authenticated; grant execute on all functions in schema auth to anon, authenticated; grant usage on schema public to anon, authenticated;
create table public.profiles (id uuid primary key, nickname text);
create table public.matches (id bigint generated always as identity primary key, user_id uuid, result text, reason text, turns int, damage int, mvp_name text, created_at timestamptz default now());
create table public.gallery (user_id uuid, card_id text, count int, mvp_count int);
insert into auth.users (id, email, email_confirmed_at) values ('${ADMIN}','stevejean77@gmail.com',now()),('${A}','a@x',now()),('${B}','b@x',now()),('${C}','c@x',now()),('${D}','d@x',now()),('${E}','e@x',now());
insert into profiles (id, nickname) values ('${A}','에이'),('${B}','비'),('${C}','씨'),('${D}','디'),('${E}','이');`);
const src = f => readFileSync(new URL('../supabase/' + f, import.meta.url), 'utf8');
const run = f => db.exec(src(f));
for (const f of ['story.sql', 'gacha.sql', 'story_server.sql', 'story_gacha.sql', 'story_levels.sql', 'story_merge.sql', 'story_ch2.sql', 'story_cards_1022.sql', 'story_leader_lock.sql', 'story_level_stats.sql', 'story_min_battle.sql', 'admin.sql', 'phaseE_1.sql', 'phaseE_2.sql', 'pvp.sql', 'pvp_tier.sql', 'gem.sql']) await run(f);
await run('guild.sql'); await run('guild.sql');   // 두 번 실행해도 안전
let fails = 0; const ok = (c, m) => { if (!c) { fails++; console.log('FAIL', m); } else console.log('ok  ', m); };
async function as(uid, sql, role = 'authenticated') {
  await db.exec(`reset role; select set_config('request.jwt.claims', '${JSON.stringify(uid ? { sub: uid, email: uid === ADMIN ? 'stevejean77@gmail.com' : 'x@x' } : {})}', false); set role ${role};`);
  try { return { rows: (await db.query(sql)).rows }; } catch (e) { return { err: e.message }; } finally { await db.exec('reset role'); }
}
const one = r => r.rows?.[0] && Object.values(r.rows[0])[0];
const v = async (uid, sql) => one(await as(uid, sql));
const gold = async u => +((await db.query(`select gold from player_wallet where user_id='${u}'`)).rows[0]?.gold || 0);
const loyal = async u => +((await db.query(`select balance from loyalty_wallet where user_id='${u}'`)).rows[0]?.balance || 0);
for (const u of [A, B, C, D, E]) await db.exec(`insert into player_state (user_id, level, stamina) values ('${u}', 20, 40)`);
await db.exec(`update player_state set level = 10 where user_id = '${E}'`);

// 창설
let st = await v(A, `select guild_status()`); ok(st.guild === null && st.cost.gold === 50000 && st.cost.gem === 300, '조직 없음 상태 · 비용');
ok(/level required/.test((await as(E, `select guild_create('낮은레벨',1,'','open','gold')`)).err || ''), 'Lv.15 미만 창설 불가');
ok(/not enough gold/.test((await as(A, `select guild_create('검은장미',1,'','open','gold')`)).err || ''), '골드 부족 창설 불가');
await db.exec(`select _wallet_add('${A}', '{"gold":60000}', 'test')`);
ok(/bad name/.test((await as(A, `select guild_create('a',1,'','open','gold')`)).err || '') && /bad name/.test((await as(A, `select guild_create('관리자팀',1,'','open','gold')`)).err || ''), '이름 규칙·금칙어');
let r = await as(A, `select guild_create('검은장미',3,'심연의 가족','open','gold')`); ok(!r.err && await gold(A) === 10000, '골드 50,000 으로 창설 ' + (r.err || ''));
const gid = one(r).id;
await db.exec(`select _gem_add('${B}', 300, 0, 'test', null, '{}')`);
ok(/name taken/.test((await as(B, `select guild_create('검은장미',1,'','open','gem')`)).err || ''), '이름 중복 불가 (대소문자 무시)');
r = await as(B, `select guild_create('Crows',2,'','approval','gem')`); ok(!r.err && +(await db.query(`select gem_free from player_wallet where user_id='${B}'`)).rows[0].gem_free === 0, '심연석 300 으로 창설 ' + (r.err || ''));
const gid2 = one(r).id;
ok(/already in guild/.test((await as(A, `select guild_create('또하나',1,'','open','gold')`)).err || ''), '한 사람 한 조직');
// 가입
st = await v(C, `select guild_status()`); ok(st.list.length === 2, '조직 목록');
r = await as(C, `select guild_apply(${gid})`); ok(!r.err && one(r).joined, '공개 조직 바로 가입');
r = await as(D, `select guild_apply(${gid2})`); ok(!r.err && one(r).pending, '승인제 → 신청');
st = await v(B, `select guild_status()`); ok(st.requests.length === 1 && st.me.role === 'boss', '보스: 신청 목록');
ok(/no permission/.test((await as(C, `select guild_respond(${st.requests[0].id}, true)`)).err || ''), '다른 조직은 승인 불가');
r = await as(B, `select guild_respond(${st.requests[0].id}, true)`); ok(!r.err && (await v(D, `select guild_status()`)).guild.id === gid2, '승인 → 가입');
await db.exec(`update guilds set join_mode = 'closed' where id = ${gid}`);
ok(/closed/.test((await as(E, `select guild_apply(${gid})`)).err || ''), '비공개 조직 신청 불가');
r = await as(A, `select guild_invite('이')`); ok(!r.err, '초대 ' + (r.err || ''));
st = await v(E, `select guild_status()`); ok(st.invites.length === 1, '초대 받음');
r = await as(E, `select guild_respond(${st.invites[0].id}, true)`); ok(!r.err && (await v(E, `select guild_status()`)).guild.id === gid, '초대 수락 (Lv 무관 가입)');
// 권한
ok(/no permission/.test((await as(C, `select guild_update('{"notice":"x"}')`)).err || ''), '조직원 공지 불가');
r = await as(A, `select guild_set_role('${C}','officer')`); ok(!r.err, '간부 임명');
ok(/officer slots full/.test((await as(A, `select guild_set_role('${E}','officer')`)).err || ''), 'Lv1 간부 1명 상한');
r = await as(C, `select guild_update('{"notice":"오늘 밤 집결"}')`); ok(!r.err, '간부 공지 가능');
ok(/no permission/.test((await as(C, `select guild_update('{"intro":"x"}')`)).err || ''), '간부 소개 변경 불가');
ok(/no permission/.test((await as(C, `select guild_kick('${A}')`)).err || ''), '간부는 보스 추방 불가');
ok(/boss must transfer/.test((await as(A, `select guild_leave()`)).err || ''), '보스는 넘기기 전 탈퇴 불가');
// 추방 · 쿨타임
r = await as(C, `select guild_kick('${E}')`); ok(!r.err, '간부가 조직원 추방');
await db.exec(`update guilds set join_mode = 'open' where id = ${gid}`);
ok(/cooldown/.test((await as(E, `select guild_apply(${gid})`)).err || ''), '추방된 조직 72시간 재가입 불가');
r = await as(E, `select guild_apply(${gid2})`); ok(!r.err, '다른 조직은 바로 신청 가능');
await db.exec(`update guild_requests set status='cancelled' where user_id='${E}'`);
r = await as(D, `select guild_leave()`); ok(!r.err, '탈퇴');
ok(/cooldown/.test((await as(D, `select guild_apply(${gid})`)).err || ''), '탈퇴 후 24시간 가입 불가');
await db.exec(`update guild_cooldowns set until = now() - interval '1 minute' where user_id = '${D}'`);
ok(!(await as(D, `select guild_apply(${gid})`)).err, '쿨타임 지나면 가입');
// 세력 · 충성: 스토리(경험치 60=1, 하루 100) · PvP 승리 +10 (하루 100)
await db.exec(`select _player_add_xp('${C}', 600, true)`);
let g = (await db.query(`select exp from guilds where id=${gid}`)).rows[0]; ok(+g.exp === 10 && await loyal(C) === 10, '스토리 행동력 60 → 세력·충성 +10');
await db.exec(`select _player_add_xp('${C}', 60000, true)`); ok(await loyal(C) === 100, '스토리 하루 상한 100');
await db.exec(`select _guild_feed('${C}', 'pvp', 10)`); ok(await loyal(C) === 110, 'PvP 승리 +10');
// PvP 실제 승리 연동
await db.exec(`insert into story_progress (user_id, data) values ('${A}', '{"owned":[{"uid":"a","id":"1000000001"},{"uid":"b","id":"1000000002"}],"leader":"a"}') on conflict (user_id) do update set data = excluded.data`);
await as(A, `select pvp_set_deck('open','1v1',0,'["a","b"]')`);
const s = await v(A, `select pvp_start('open','1v1')`); r = await as(A, `select pvp_report(${s.id}, 1, 0)`);
ok(!r.err && await loyal(A) === 10, 'pvp_report 승리 → 충성 +10 ' + (r.err || ''));
// 레벨업 (세력 1000 → Lv2, 인원 18 · 간부 2)
await db.exec(`select _guild_exp(${gid}, null, 1000, 'test', 'lvtest')`);
st = await v(A, `select guild_status()`); ok(st.guild.level === 2 && st.guild.max_members === 18 && st.guild.officers_max === 2, '세력 1000 → Lv2 (18명 · 간부 2)');
ok((await db.query(`select _guild_exp(${gid}, null, 1000, 'test', 'lvtest') n`)).rows[0].n === 0, '같은 ref 세력 중복 없음');
ok(st.members[0].role === 'boss' && st.members[0].card === '1000000001', '멤버 목록: 보스 먼저 · 리더 카드');
// 충성 상점
await db.exec(`select _loyalty_add('${C}', 1000, 'test', null, '{}')`);
const t0 = +((await db.query(`select tickets from story_gacha where user_id='${C}'`)).rows[0]?.tickets || 0);
r = await as(C, `select guild_shop_buy('ticket')`); ok(!r.err && one(r).tickets === t0 + 1, '충성 300 → 소환권 ' + (r.err || ''));
await as(C, `select guild_shop_buy('ticket')`); ok(/limit/.test((await as(C, `select guild_shop_buy('ticket')`)).err || ''), '소환권 주 2회');
ok(/guild level required/.test((await as(C, `select guild_shop_buy('shard5')`)).err || ''), '조직 Lv3 품목 잠금');
const gc = await gold(C); r = await as(C, `select guild_shop_buy('gold5k')`); ok(!r.err && await gold(C) === gc + 5000, '골드 5,000');
ok(/not enough loyalty/.test((await as(D, `select guild_shop_buy('gold5k')`)).err || ''), '충성 부족');
// 보스 넘기기 · 승계
r = await as(A, `select guild_transfer('${C}')`); ok(!r.err && (await v(C, `select guild_status()`)).me.role === 'boss', '보스 넘기기');
ok(/boss active/.test((await as(A, `select guild_claim_boss()`)).err || ''), '보스 활동 중이면 승계 불가');
await db.exec(`update guild_members set seen_at = now() - interval '15 days' where user_id = '${C}'`);
ok(/not heir/.test((await as(D, `select guild_claim_boss()`)).err || ''), '간부가 있으면 조직원은 승계 불가');
r = await as(A, `select guild_claim_boss()`); ok(!r.err && (await v(A, `select guild_status()`)).me.role === 'boss', '14일 미접속 → 간부 승계');
// 보안
ok(!!(await as(A, `select * from guilds`)).err && !!(await as(A, `select * from guild_members`)).err, '테이블 직접 읽기 불가');
ok(!!(await as(A, `update guilds set level = 10`)).err, '직접 수정 불가');
ok(!!(await as(A, `select _guild_exp(${gid}, null, 99999, 'x', null)`)).err && !!(await as(A, `select _loyalty_add('${A}', 99999, 'x', null, '{}')`)).err, '내부 함수 호출 불가');
ok(!!(await as(null, `select guild_status()`, 'anon')).err, 'anon 불가');
// 관리자
ok(!!(await as(A, `select admin_guild_list(null)`)).err, '일반 유저 관리자 불가');
r = await as(ADMIN, `select admin_guild_list(null)`); ok(!r.err && one(r).length === 2, '관리자 목록');
r = await as(ADMIN, `select admin_guild_edit(${gid2}, 'disband', null, '테스트')`); ok(!r.err && !(await db.query(`select 1 from guilds where id=${gid2}`)).rows.length, '관리자 해산');
// 해산: 혼자 남은 보스
const solo = await v(B, `select guild_status()`); ok(solo.guild === null, '해산된 조직 멤버는 조직 없음');
// 복사본 = 원본
const fn = (t, n) => { const i = t.indexOf(`create or replace function public.${n}(`); return t.slice(i, t.indexOf('end $$;', i)); };
const G = src('guild.sql');
for (const [f, n] of [['phaseE_2.sql', '_player_add_xp'], ['pvp_tier.sql', 'pvp_report']]) ok(fn(src(f), n) === fn(G, n), `guild.sql 의 ${n} = ${f}`);
// 클라이언트 엠블럼 12개
{ const js = readFileSync(new URL('../js/guild.js', import.meta.url), 'utf8'); ok(/EMB = \[([^\]]+)\]/.test(js) && js.match(/EMB = \[([^\]]+)\]/)[1].split(',').length === 12, '클라이언트 엠블럼 12개'); }
console.log(fails ? `${fails} FAIL` : 'ALL PASS'); process.exit(fails ? 1 : 0);
