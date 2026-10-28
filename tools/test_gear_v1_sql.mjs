// supabase/gear_v1.sql 검증 (PGlite): 장비 v1 — 시드·RLS·가방 확장(보석)·잠금·장착·영웅 초과 거부·우편·재실행 안전
import { readFileSync } from 'fs';
import { createRequire } from 'module';
const require = createRequire(import.meta.url);
let PGlite; try { ({ PGlite } = require('@electric-sql/pglite')); } catch { console.log('SKIP: @electric-sql/pglite 없음'); process.exit(0); }
const db = new PGlite();
const U = '00000000-0000-0000-0000-000000000002', V = '00000000-0000-0000-0000-000000000003', ADMIN = '00000000-0000-0000-0000-000000000001';
await db.exec(`create role anon nologin; create role authenticated nologin; create schema auth;
create table auth.users (id uuid primary key, email text, email_confirmed_at timestamptz, created_at timestamptz default now(), last_sign_in_at timestamptz, raw_user_meta_data jsonb default '{}');
create function auth.jwt() returns jsonb language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $$;
create function auth.uid() returns uuid language sql stable as $$ select nullif(auth.jwt()->>'sub', '')::uuid $$;
grant usage on schema auth to anon, authenticated; grant execute on all functions in schema auth to anon, authenticated; grant usage on schema public to anon, authenticated;
create table public.profiles (id uuid primary key, nickname text);
create table public.matches (id bigint generated always as identity primary key, user_id uuid, result text, reason text, turns int, damage int, mvp_name text, created_at timestamptz default now());
create table public.gallery (user_id uuid, card_id text, count int, mvp_count int);
insert into auth.users (id, email, email_confirmed_at) values ('${U}','u@x.com',now()),('${V}','v@x.com',now()),('${ADMIN}','stevejean77@gmail.com',now());
insert into profiles (id, nickname) values ('${U}','유'),('${V}','브이');`);
const src = f => readFileSync(new URL('../supabase/' + f, import.meta.url), 'utf8');
const run = f => db.exec(src(f));
for (const f of ['story.sql', 'gacha.sql', 'story_server.sql', 'story_gacha.sql', 'story_levels.sql', 'story_merge.sql', 'story_ch2.sql', 'story_cards_1022.sql', 'story_leader_lock.sql', 'story_level_stats.sql', 'story_min_battle.sql', 'admin.sql', 'phaseE_1.sql', 'phaseE_2.sql', 'pvp.sql', 'pvp_tier.sql']) await run(f);
await run('gem.sql'); await run('gear_v1.sql'); await run('gear_v1.sql');   // 두 번 실행해도 안전
let fails = 0; const ok = (c, m) => { if (!c) { fails++; console.log('FAIL', m); } else console.log('ok  ', m); };
async function as(role, claims, sql) {
  await db.exec(`reset role; select set_config('request.jwt.claims', '${JSON.stringify(claims || {})}', false); set role ${role};`);
  try { return { rows: (await db.query(sql)).rows }; } catch (e) { return { err: e.message }; } finally { await db.exec('reset role'); }
}
const one = r => r.rows?.[0] && Object.values(r.rows[0])[0];
const q = s => as('authenticated', { sub: U, email: 'u@x.com' }, s), qv = s => as('authenticated', { sub: V, email: 'v@x.com' }, s), qn = s => as('anon', {}, s);
const sv = async s => Object.values((await db.query(s)).rows[0])[0];

// 시드
ok(+await sv(`select count(*) from gear_defs`) === 60, 'gear_defs 60종 (무기 21·방어구 19·액세서리 20)');
ok(+await sv(`select count(*) from gear_defs where tier >= 6 and not event_only`) === 0, '전설·심연 = event_only');
ok(+await sv(`select count(*) from gear_raid_rewards`) === 9, '토벌 보상표 9행 (재실행 중복 없음)');
ok(+await sv(`select max(tier) from gear_raid_rewards`) <= 5 && +await sv(`select max(coalesce(up_tier,0)) from gear_raid_rewards`) <= 5, '토벌 보상 최고 영웅');
ok(+await sv(`select sum(frags) from sigil_cost`) === 530, '증표 조각 합계 530');
ok(+await sv(`select count(*) from sigil_defs`) === 3 && +await sv(`select jsonb_array_length(steps) from sigil_defs where card_id='2000100001'`) === 6, '증표 3종, +0~+5');
ok(+await sv(`select sum((slots_to - slots_from + 1) / 10 * gem) from gear_slot_price`) === 3700, '가방 확장 총 3,700 보석');
ok(await sv(`select string_agg(gem::text, ',' order by slots_from) from gear_slot_price`) === '100,100,150,150,200,200,400,400,1000,1000', '구간 가격 100/150/200/400/1000');

// RLS: anon 은 아무것도 못 읽음 / 함수 실행 불가
ok(!!(await qn(`select * from gear_defs`)).err, 'anon gear_defs 읽기 거부');
ok(!!(await qn(`select public.gear_status()`)).err, 'anon gear_status 거부');
ok(!!(await q(`insert into player_gear (user_id, def_id, source) values ('${U}','weapon_7_1','hack')`)).err, '직접 insert 거부');
ok(!!(await q(`select public._gear_grant('${U}','weapon_2_1','x')`)).err, '내부 지급 함수 직접 호출 거부');
ok(!!(await q(`select * from gear_event_grants`)).err, '이벤트 표 비공개');

// 지급 (서버 내부) + 영웅 초과 거부
await db.exec(`insert into story_progress (user_id, data) values ('${U}','{"owned":[{"id":"1000100007"},{"id":"2000100001"}]}') on conflict (user_id) do update set data = excluded.data`);
const g1 = (await db.query(`select public._gear_grant('${U}','weapon_4_2','test') r`)).rows[0].r.gear_id;
const g2 = (await db.query(`select public._gear_grant('${U}','weapon_2_1','test') r`)).rows[0].r.gear_id;
let e = null; try { await db.query(`select public._gear_grant('${U}','weapon_6_1','raid')`); } catch (x) { e = x.message; }
ok(/event only/.test(e || ''), '전설 일반 지급 거부');
e = null; try { await db.query(`select public._gear_grant('${U}','acc_7_1','event',true,'nope')`); } catch (x) { e = x.message; }
ok(/event only/.test(e || ''), '이벤트 표에 없으면 심연 거부');
await db.exec(`insert into gear_event_grants (event_key, def_id, starts_at, ends_at) values ('t1','weapon_6_1', now() - interval '1 day', now() + interval '1 day')`);
const ev = (await db.query(`select public._gear_grant('${U}','weapon_6_1','event',false,'t1') r`)).rows[0].r;
ok(ev.ok && await sv(`select locked from player_gear where id=${ev.gear_id}`) === true, '이벤트 표에 있으면 전설 지급 + 자동 잠금');
let maxT = 0; for (let i = 0; i < 300; i++) { const t = +await sv(`select public._gear_roll_tier(30, 999, 'abyss')`); maxT = Math.max(maxT, t); }
ok(maxT <= 5, `등급 결정 최대 ${maxT} (≤ 영웅)`);
let lowMax = 0; for (let i = 0; i < 200; i++) lowMax = Math.max(lowMax, +await sv(`select public._gear_roll_tier(1, null, 'normal')`));
ok(lowMax <= 2, `챕터 1 일반 모드 최대 ${lowMax} (≤ 일반)`);
const opts = await sv(`select opts from player_gear where id=${g1}`);
ok(Array.isArray(opts) && opts.length === 1, '희귀 무기 부옵션 1개 랜덤');

// 상태·잠금·장착
const st = one(await q(`select public.gear_status()`));
ok(st.slots === 100 && st.count === 3 && st.next_expand.gem === 100, 'gear_status 100칸, 다음 확장 100 보석');
ok(one(await qv(`select count(*) from player_gear`)) == 0, '다른 사람 장비 안 보임');
ok(one(await q(`select public.gear_lock(${g1}, true)`)).ok && one(await qv(`select public.gear_lock(${g1}, false)`)).ok === false, '잠금: 본인만');
ok(one(await q(`select public.gear_equip(${g1}, '1000100007')`)).ok, '장착');
ok(one(await q(`select public.gear_equip(${g2}, '1000100007')`)).ok && await sv(`select equipped_card from player_gear where id=${g1}`) === null, '같은 슬롯 교체 시 이전 장비 해제');
ok(one(await q(`select public.gear_equip(${g1}, '9999')`)).reason === 'card not owned', '없는 인재 장착 거부');
ok(one(await q(`select public.gear_unequip(${g2})`)).ok && await sv(`select equipped_card from player_gear where id=${g2}`) === null, '해제');

// 가방 확장
await db.exec(`select public._gem_add('${U}', 250, 0, 'test', null, '{}'::jsonb)`);
let r = one(await q(`select public.gear_expand()`)); ok(r.ok && r.slots === 110, '확장 100→110 (100 보석)');
r = one(await q(`select public.gear_expand()`)); ok(r.ok && r.slots === 120, '110→120');
r = one(await q(`select public.gear_expand()`)); ok(!r.ok && r.reason === 'gem' && r.need === 150, '121~ 150 보석 부족 → 거부');
ok(+await sv(`select gem_free from player_wallet where user_id='${U}'`) === 50, '보석 50 남음');
await db.exec(`update player_gear_meta set slots = 200 where user_id='${U}'`);
ok(one(await q(`select public.gear_expand()`)).reason === 'max', '200칸이면 max');

// 가방 꽉 참 → 소탕 거부 / 우편
await db.exec(`update player_gear_meta set slots = 100 where user_id='${U}'; insert into player_gear (user_id, def_id, source) select '${U}', 'weapon_1_1', 'fill' from generate_series(1, 97)`);
e = null; try { await db.query(`select public._gear_drop('${U}', 1, null, 'normal', 'sweep')`); } catch (x) { e = x.message; }
ok(/bag full/.test(e || ''), '꽉 차면 소탕 드롭 거부');
ok((await db.query(`select public._gear_grant('${U}','armor_5_1','raid',true) r`)).rows[0].r.mail === true, '꽉 차면 토벌 보상은 우편함');
const mails = one(await q(`select public.mail_list()`)); ok(mails.length === 1, '우편 1개');
ok(one(await q(`select public.mail_claim(${mails[0].id})`)).reason === 'bag full', '가방 꽉 차면 우편 받기 거부');
await db.exec(`delete from player_gear where user_id='${U}' and source='fill' and id in (select id from player_gear where source='fill' limit 1)`);
ok(one(await q(`select public.mail_claim(${mails[0].id})`)).ok, '자리 나면 우편 받기');
ok(one(await qv(`select public.mail_claim(${mails[0].id})`)).ok === false, '남의 우편 거부');

// 재실행 후에도 사용자 조절값 유지
await db.exec(`update gear_mode_config set gear_pct = 40 where mode='pvp'`); await run('gear_v1.sql');
ok(+await sv(`select gear_pct from gear_mode_config where mode='pvp'`) === 40, '재실행해도 PvP 배율(사용자 조절값) 유지');
ok(+await sv(`select count(*) from player_gear where user_id='${U}'`) === 100, '재실행해도 보유 장비 유지');

console.log(fails ? `\n${fails} FAIL` : '\nALL OK'); process.exit(fails ? 1 : 0);
