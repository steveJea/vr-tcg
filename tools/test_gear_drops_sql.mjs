// supabase/gear_drops.sql 검증 (PGlite): 소탕·탑·토벌 드롭 · 등급 상한 · 가방 꽉 참 · 우편 · 상자
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
for (const f of ['story.sql', 'gacha.sql', 'story_server.sql', 'story_gacha.sql', 'story_levels.sql', 'story_merge.sql', 'story_ch2.sql', 'story_cards_1022.sql', 'story_leader_lock.sql', 'story_level_stats.sql', 'story_min_battle.sql', 'admin.sql', 'phaseE_1.sql', 'phaseE_2.sql', 'quest.sql', 'quest_sweep.sql', 'phaseE_3.sql', 'phaseE_4.sql', 'phaseE_5.sql', 'story_ch3.sql', 'pvp.sql', 'pvp_tier.sql', 'gem.sql', 'guild.sql', 'guild2.sql', 'guild3.sql', 'tower_v2.sql', 'gear_v1.sql']) await run(f);
await run('gear_drops.sql'); await run('gear_drops.sql'); await run('gear_sigil.sql');   // 두 번 실행해도 안전
let fails = 0; const ok = (c, m) => { if (!c) { fails++; console.log('FAIL', m); } else console.log('ok  ', m); };
async function as(uid, sql, role = 'authenticated') {
  await db.exec(`reset role; select set_config('request.jwt.claims', '${JSON.stringify(uid ? { sub: uid, email: 'x@x' } : {})}', false); set role ${role};`);
  try { return { rows: (await db.query(sql)).rows }; } catch (e) { return { err: e.message }; } finally { await db.exec('reset role'); }
}
const one = r => r.rows?.[0] && Object.values(r.rows[0])[0];
const v = async (uid, sql) => { const r = await as(uid, sql); if (r.err) console.log('  err:', r.err); return one(r); };
const q1 = async sql => Object.values((await db.query(sql)).rows[0] || {})[0];
const bag = async u => +(await q1(`select count(*) from player_gear where user_id='${u}'`));
await db.exec(`update gear_drop_rate set pct = 100`);

// 등급 대역
const tiers = async (ch, fl, n = 300) => (await db.query(`select public._gear_roll_tier(${ch ?? 'null'}, ${fl ?? 'null'}, 'normal') t from generate_series(1, ${n})`)).rows.map(r => r.t);
let t = await tiers(3); ok(t.every(x => x <= 2) && t.includes(1), '챕터 0~5: 낡은 (가끔 일반)');
t = await tiers(9); ok(t.every(x => x >= 2 && x <= 3), '챕터 6~10: 일반·고급만 (희귀 없음)');
t = await tiers(12, null, 2000); const r4 = t.filter(x => x === 4).length; ok(t.every(x => x <= 4) && r4 > 10 && r4 < 100, `챕터 11~15: 희귀 약 2% (${r4}/2000)`);
t = await tiers(30, null, 2000); ok(t.every(x => x <= 5), '챕터 26~30: 최대 영웅');
t = (await db.query(`select public._gear_roll_tier(30, null, 'abyss') t from generate_series(1, 2000)`)).rows.map(r => r.t); ok(Math.max(...t) === 5, '심연 모드도 최대 영웅');
ok(/out of range/.test((await as(null, `select public._gear_give_tier('${A}', 6, null, 'x', true)`, 'postgres')).err || ''), '6등급 이상 드롭 거부');
ok(/event only/.test((await as(null, `select public._gear_grant('${A}', 'weapon_6_1', 'raid', true)`, 'postgres')).err || ''), '전설은 이벤트 외 지급 거부');
ok(!!(await as(A, `select public._gear_try_drop('${A}', 1, null, 'story_sweep')`)).err, '내부 함수는 직접 호출 불가');

// 스토리 소탕
await db.exec(`insert into player_state (user_id, level, stamina) values ('${A}', 30, 500) on conflict (user_id) do update set level = 30, stamina = 500`);
await db.exec(`insert into story_progress (user_id, data) values ('${A}', '{"owned":[],"cleared":{"3":[1]}}') on conflict (user_id) do update set data = excluded.data`);
let s = await v(A, `select story_sweep(3, 1, 5)`);
ok(s?.gear?.length === 5 && (await bag(A)) === 5, `소탕 5회 → 장비 5개 (${s?.gear?.length})`);
const o = await q1(`select opts from player_gear where user_id='${A}' limit 1`); ok(Array.isArray(o), '부옵션 드롭 때 굴림');
let tk = await v(A, `select gear_drops_take()`); ok(tk.length === 5 && tk.every(x => x.source === 'story_sweep' && x.def_id && x.tier <= 2), '결과 화면용 기록 5개 (챕터 3 → 일반 이하)');
ok((await v(A, `select gear_drops_take()`)).length === 0, '한 번 가져가면 끝');
// 가방 꽉 참
await db.exec(`insert into player_gear (user_id, def_id, opts, source) select '${A}', 'weapon_1_1', '[]', 'fill' from generate_series(1, 95)`);
const st0 = +(await q1(`select stamina from player_state where user_id='${A}'`));
ok(/bag full/.test((await as(A, `select story_sweep(3, 1, 1)`)).err || '') && +(await q1(`select stamina from player_state where user_id='${A}'`)) === st0, '가방 100/100: 소탕 막힘 (행동력 그대로)');
await db.exec(`insert into tower_progress (user_id, tower, best_floor) values ('${A}', 'normal', 70) on conflict do nothing`);
ok(/bag full/.test((await as(null, `update tower_progress set battle = '{"floor":71}' where user_id='${A}'`, 'postgres')).err || ''), '가방 꽉 참: 탑 시작 막힘');
// 탑: 층 클리어 → 드롭 (중간에 차면 우편)
await db.exec(`delete from player_gear where user_id='${A}' and source='fill'`);
await db.exec(`update tower_progress set battle = '{"floor":71}' where user_id='${A}'`);
await db.exec(`update tower_progress set battle = null, clears = clears + 1, best_floor = 71 where user_id='${A}'`);
tk = await v(A, `select gear_drops_take()`); ok(tk.length === 1 && tk[0].source === 'tower' && tk[0].tier >= 2 && tk[0].tier <= 4, `탑 71층 → 일반~희귀 (${tk[0]?.tier})`);
await db.exec(`insert into player_gear (user_id, def_id, opts, source) select '${A}', 'weapon_1_1', '[]', 'fill' from generate_series(1, 94)`);
await db.exec(`update tower_progress set clears = clears + 3 where user_id='${A}'`);
ok((await bag(A)) === 100 && +(await q1(`select count(*) from player_mail where user_id='${A}' and kind='gear'`)) === 3, '소탕 중 가득 차면 넘친 건 우편');
const ml = await v(A, `select mail_list()`); ok(ml.length === 3 && Array.isArray(ml[0].payload.opts), '우편: 부옵션 들고 있음');
ok((await v(A, `select mail_claim(${ml[0].id})`)).reason === 'bag full', '가방 꽉 차면 우편 못 받음');
await db.exec(`delete from player_gear where user_id='${A}' and source='fill'`);
const cl = await v(A, `select mail_claim(${ml[0].id})`); ok(cl.ok && JSON.stringify(await q1(`select opts from player_gear where id=${cl.gear_id}`)) === JSON.stringify(ml[0].payload.opts), '우편 받기: 드롭 때 부옵션 그대로');
await v(A, `select gear_drops_take()`);

// 조직 토벌
await db.exec(`insert into player_state (user_id, level, stamina) values ('${B}', 20, 40) on conflict do nothing`);
const cid = await q1(`select id from pvp_card_meta order by id limit 1`);
for (const u of [A, B]) await db.exec(`insert into story_progress (user_id, data) values ('${u}', '{"owned":[{"uid":"c1","id":"${cid}","level":10}]}') on conflict (user_id) do update set data = story_progress.data || excluded.data`);
await db.exec(`select _wallet_add('${A}', '{"gold":50000}', 'test')`);
const gid = (await v(A, `select guild_create('검은장미',1,'','open','gold')`)).id;
await as(B, `select guild_apply(${gid})`); await db.exec(`update guild_members set joined_at = now() - interval '9 days'`);
const b0 = await bag(B);
let st = await v(B, `select raid_start('["c1"]')`); await db.exec(`update guild_raid_attempts set started_at = started_at - interval '5 seconds' where finished_at is null`);
await v(B, `select raid_finish(${st.id}, 1000)`);
tk = await v(B, `select gear_drops_take()`); ok(tk.length === 1 && tk[0].source === 'raid' && tk[0].tier >= 3 && tk[0].tier <= 4 && (await bag(B)) === b0 + 1, `토벌 도전 → 1단계 고급(희귀 10%) (${tk[0]?.tier})`);
// 처치 상자: 1단계 HP 를 깎아 처치시키고 받기
await db.exec(`update guild_raids set hp_left = 1 where guild_id = ${gid}`);
st = await v(B, `select raid_start('["c1"]')`); await db.exec(`update guild_raid_attempts set started_at = started_at - interval '5 seconds' where finished_at is null`);
await v(B, `select raid_finish(${st.id}, 1000)`); await v(B, `select gear_drops_take()`);
await v(B, `select raid_claim()`);
tk = await v(B, `select gear_drops_take()`); const box = (await v(B, `select mail_list()`)).find(m => m.kind === 'box');
ok(tk.some(x => x.kind === 'box') && box && box.payload.tier === 4, '처치 보상: 희귀 상자 → 우편');
ok(/invalid slot/.test((await as(B, `select gear_box_open(${box.id}, 'hat')`)).err || ''), '상자: 잘못된 슬롯 거부');
const ob = await v(B, `select gear_box_open(${box.id}, 'armor')`);
ok(ob.ok && ob.tier === 4 && (await q1(`select d.slot from player_gear g join gear_defs d on d.id = g.def_id where g.id = ${ob.gear_id}`)) === 'armor', '상자 열기: 고른 슬롯 희귀');
ok((await v(B, `select gear_box_open(${box.id}, 'armor')`)).ok === false, '상자 두 번 못 엶');
ok(!!(await as(B, `select mail_claim(${box.id})`)).rows, '상자를 mail_claim 으로 받아도 오류 없음');
// 주간 순위 상자
await db.exec(`create or replace function public._raid_now() returns timestamptz language sql stable as $$ select _raid_end(_guild_week()) + interval '1 minute' $$`);
await v(B, `select raid_claim()`);
const rb = (await v(B, `select mail_list()`)).filter(m => m.kind === 'box' && m.reason === 'raid_rank');
ok(rb.length === 1 && rb[0].payload.tier === 5, `순위 1위: 영웅 상자 1 (${rb.length})`);
// 보안
for (const tb of ['gear_drop_log', 'gear_drop_rate', 'player_mail']) ok(!!(await as(null, `select * from ${tb} limit 1`, 'anon')).err, `${tb}: anon 거부`);
ok(!!(await as(A, `insert into gear_drop_log (user_id, source, def_id) values ('${A}', 'x', 'weapon_1_1')`)).err, '기록 직접 쓰기 불가');
ok((await as(A, `select * from gear_drop_log where user_id = '${B}'`)).rows?.length === 0, '남의 기록 안 보임');
ok(!!(await as(null, `select gear_drops_take()`, 'anon')).err, 'anon RPC 거부');
console.log(fails ? `\n${fails} FAIL` : '\nALL OK'); process.exit(fails ? 1 : 0);
