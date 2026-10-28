// supabase/gear_shop.sql 검증 (PGlite): 조직 상점(충성) · PvP 상점(혼) — 증표 조각 · 상자 · 가루 · 한도
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
for (const f of ['story.sql', 'gacha.sql', 'story_server.sql', 'story_gacha.sql', 'story_levels.sql', 'story_merge.sql', 'story_ch2.sql', 'story_cards_1022.sql', 'story_leader_lock.sql', 'story_level_stats.sql', 'story_min_battle.sql', 'admin.sql', 'phaseE_1.sql', 'phaseE_2.sql', 'quest.sql', 'quest_sweep.sql', 'phaseE_3.sql', 'phaseE_4.sql', 'phaseE_5.sql', 'pvp.sql', 'pvp_tier.sql', 'gem.sql', 'guild.sql', 'guild2.sql', 'guild3.sql', 'tower_v2.sql', 'gear_v1.sql', 'gear_drops.sql', 'gear_craft.sql', 'gear_sigil.sql', 'gear_sigil_story_off.sql']) await run(f);
await run('gear_shop.sql'); await run('gear_shop.sql');   // 두 번 실행해도 안전
let fails = 0; const ok = (c, m) => { if (!c) { fails++; console.log('FAIL', m); } else console.log('ok  ', m); };
async function as(uid, sql, role = 'authenticated') {
  await db.exec(`reset role; select set_config('request.jwt.claims', '${JSON.stringify(uid ? { sub: uid, email: 'x@x' } : {})}', false); set role ${role};`);
  try { return { rows: (await db.query(sql)).rows }; } catch (e) { return { err: e.message }; } finally { await db.exec('reset role'); }
}
const v = async (u, s) => { const r = await as(u, s); return r.err ? { err: r.err } : Object.values(r.rows[0])[0]; };
const q1 = async s => Object.values((await db.query(s)).rows[0] || {})[0];
const MIN = '10118', YUN = '10415', YURI = '10325';
const frags = async (u, c) => +((await q1(`select frags from player_sigils where user_id='${u}' and card_id='${c}'`)) ?? 0);
const soul = async u => +(await q1(`select coalesce((select soul from player_wallet where user_id='${u}'), 0)`));
// PvP 상점
ok(/not enough soul/.test((await v(A, `select pvp_shop_buy('sigil_min')`)).err || ''), '혼 부족: 구매 불가');
await db.exec(`select _wallet_add('${A}', '{"soul":500}', 'test')`);
let st = await v(A, `select pvp_shop_status()`); ok(st.items.length === 5 && st.soul === 500 && st.items.find(i => i.item === 'sigil_min').left === 3, `PvP 상점 목록 (${st.items.length})`);
await v(A, `select pvp_shop_buy('sigil_min')`); await v(A, `select pvp_shop_buy('sigil_min')`); const r3 = await v(A, `select pvp_shop_buy('sigil_yun')`);
ok((await frags(A, MIN)) === 2 && (await frags(A, YUN)) === 1 && (await soul(A)) === 470 && r3.left === 0, '민홍기 2 + 최윤희 1 = 주 3개 묶음 · 혼 30');
ok(/limit reached/.test((await v(A, `select pvp_shop_buy('sigil_yun')`)).err || '') && (await soul(A)) === 470, '주 3개 넘으면 불가 · 혼 그대로');
const pk = await v(A, `select pvp_shop_buy('sigil_pick5')`); ok(pk.sigil_mail && /limit reached/.test((await v(A, `select pvp_shop_buy('sigil_pick5')`)).err || ''), '월 1회 선택 5개 → 우편');
ok((await v(A, `select sigil_mail_claim(${pk.sigil_mail}, '${YURI}')`)).reason === 'not selectable', 'PvP 선택 조각: 임유리 불가');
ok((await v(A, `select sigil_mail_claim(${pk.sigil_mail}, '${YUN}')`)).ok && (await frags(A, YUN)) === 6, 'PvP 선택 조각: 최윤희 5');
const bx = await v(A, `select pvp_shop_buy('gbox_rare')`); const ml = await q1(`select payload from player_mail where id = ${bx.box_mail}`);
ok(ml.tier === 4 && ml.up_tier === 5, '희귀 상자 (영웅 5%) → 우편');
await db.exec(`insert into player_gear (user_id, def_id, opts, source) select '${A}', 'weapon_1_1', '[]', 'fill' from generate_series(1, 100)`);
ok((await v(A, `select gear_box_open(${bx.box_mail}, 'weapon')`)).reason === 'bag full', '가방 꽉 차면 상자 못 엶 (우편에 남음)');
await db.exec(`delete from player_gear where user_id='${A}'`);
const op = await v(A, `select gear_box_open(${bx.box_mail}, 'weapon')`); ok(op.ok && op.tier >= 4 && op.tier <= 5, `상자 열기 (${op.tier})`);
const d0 = +(await q1(`select coalesce((select dust from player_gear_meta where user_id='${A}'),0)`)); await v(A, `select pvp_shop_buy('gdust10')`);
ok(+(await q1(`select dust from player_gear_meta where user_id='${A}'`)) === d0 + 10 && /limit reached/.test((await v(A, `select pvp_shop_buy('gdust10')`)).err || ''), '가루 10 · 하루 1회');
ok(!!(await as(A, `select _shop_give_gear('${A}', '{"gear_box":{"tier":7}}', 'x')`)).err, '내부 지급 직접 호출 불가');
ok(/out of range/.test((await as(null, `select _shop_give_gear('${A}', '{"gear_box":{"tier":6}}', 'x')`, 'postgres')).err || ''), '전설 상자 거부 (영웅까지)');
// 조직 상점
await db.exec(`insert into player_state (user_id, level, stamina) values ('${A}', 20, 40) on conflict do nothing`);
await db.exec(`select _wallet_add('${A}', '{"gold":50000}', 'test')`);
const gid = (await v(A, `select guild_create('검은장미',1,'','open','gold')`)).id;
ok(/not enough loyalty|loyalty/.test((await v(A, `select guild_shop_buy('sigil_yuri')`)).err || ''), '충성 부족');
await db.exec(`select _loyalty_add('${A}', 5000, 'test', null, '{}')`);
for (let i = 0; i < 3; i++) await v(A, `select guild_shop_buy('sigil_yuri')`);
ok((await frags(A, YURI)) === 3 && /limit reached/.test((await v(A, `select guild_shop_buy('sigil_yuri')`)).err || ''), '임유리 조각 주 3개');
const gs = await v(A, `select guild_status()`); ok(gs.shop.some(s => s.item === 'gbox_adv' && s.left === 2), '조직 상점 목록에 장비 상품');
const ga = await v(A, `select guild_shop_buy('gbox_adv')`); ok(ga.ok && ga.box_mail && !ga.wallet, '고급 상자 → 우편 (지갑 안 건드림)');
ok(/guild level/.test((await v(A, `select guild_shop_buy('gbox_rare')`)).err || ''), '희귀 상자: 조직 Lv3 부터');
ok((await v(A, `select guild_shop_buy('gold5k')`)).wallet?.gold > 0, '기존 상품 그대로 동작');
// 보안
ok(!!(await as(null, `select pvp_shop_buy('gdust10')`, 'anon')).err && !!(await as(null, `select * from pvp_shop`, 'anon')).err, 'anon 거부');
ok(!!(await as(A, `insert into pvp_shop_log (user_id, item, grp, price) values ('${A}','x','x',1)`)).err && !!(await as(A, `update pvp_shop set price = 1`)).err, '표 직접 쓰기 불가');
console.log(fails ? `\n${fails} FAIL` : '\nALL OK'); process.exit(fails ? 1 : 0);
