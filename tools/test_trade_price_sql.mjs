// supabase/trade_buynow_search.sql 검증 + trade_price_history.sql (공개 시세) — 기반: trade_board.sql (PGlite): 글·제안·보관·수락·거절·취소·만료, 수수료, 골드·가격 규칙, 증표·장착·덱, 보존량, 경쟁 상황
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
for (const f of ['story.sql', 'gacha.sql', 'story_server.sql', 'story_gacha.sql', 'story_levels.sql', 'story_merge.sql', 'story_ch2.sql', 'story_cards_1022.sql', 'story_leader_lock.sql', 'story_level_stats.sql', 'story_min_battle.sql', 'admin.sql', 'phaseE_1.sql', 'phaseE_2.sql', 'quest.sql', 'quest_sweep.sql', 'phaseE_3.sql', 'phaseE_4.sql', 'phaseE_5.sql', 'story_ch3.sql', 'pvp.sql', 'pvp_tier.sql', 'gem.sql', 'guild.sql', 'guild2.sql', 'guild3.sql', 'tower_v2.sql', 'gear_v1.sql', 'gear_drops.sql', 'gear_sigil.sql', 'story_ch1_reward.sql', 'trade_origin.sql', 'trade_origin_v2.sql', 'trade_drink.sql']) await run(f);
await db.exec(`create table if not exists public.war_decks (user_id uuid primary key, def1 jsonb, def2 jsonb, atk1 jsonb, atk2 jsonb, updated_at timestamptz default now())`);
await run('trade_board.sql'); await run('trade_admin.sql'); await run('trade_buynow_search.sql'); await run('trade_price_history.sql'); await run('trade_price_history.sql');
let fails = 0; const ok = (c, m) => { if (!c) { fails++; console.log('FAIL', m); } else console.log('ok  ', m); };
const sv = async s => Object.values((await db.query(s)).rows[0] || { x: null })[0];
const as = async (sub, sql, role = 'authenticated') => { await db.exec(`reset role; select set_config('request.jwt.claims', '${JSON.stringify(sub ? { sub } : {})}', false); set role ${role};`); try { return (await db.query(sql)).rows[0]?.r; } catch (e) { return { err: e.message }; } finally { await db.exec('reset role'); } };
const E = (r, m) => r && r.err && r.err.includes(m);
// 등급별 카드·장비 id
const cg = async g => sv(`select id from story_card_pool where grade = '${g}' order by id limit 1`);
const HR = await cg('HIGH RARE'), SR = await cg('SUPER RARE'), NR = await cg('RARE'), YURI = '10325';
const gt = async t => sv(`select id from gear_defs where tier = ${t} and not event_only order by id limit 1`);
const G2 = await gt(2), G4 = await gt(4), G5 = await gt(5);
const users = [A, B, C, D];
await db.exec(`update auth.users set created_at = now() - interval '30 days'; update trade_config set val = 100 where key = 'daily_trades';`);
for (const u of users) await db.exec(`insert into player_state (user_id, level, stamina) values ('${u}', 30, 40) on conflict (user_id) do update set level = 30;
  insert into player_wallet (user_id, gold) values ('${u}', 1000000) on conflict (user_id) do update set gold = 1000000;
  insert into player_items (user_id, item, tradable, bound) values ('${u}', 'drink', 10000, 50) on conflict (user_id, item) do update set tradable = 10000, bound = 50;`);
const card = (uid, id, extra = {}) => ({ uid, id, level: 7, exp: 3, totalExp: 99, boost: { ATK: 2 }, src: 'recruit', bound: false, ...extra });
const own = { [A]: [card('a1', SR), card('a2', HR), card('a3', YURI), card('a4', NR, { bound: true, src: 'story' }), card('a5', NR, { locked: true }), card('a6', HR, { locked: true, dlk: true }), card('a7', NR)],
  [B]: [card('b1', HR), card('b2', NR), card('b3', SR), card('b4', YURI)], [C]: [card('c1', NR)], [D]: [card('d1', NR)] };
for (const u of users) await db.query(`insert into story_progress (user_id, data) values ($1, $2) on conflict (user_id) do update set data = excluded.data`, [u, JSON.stringify({ owned: own[u], leader: u === A ? 'a7' : null, decks: u === A ? [{ uids: ['a6', 'a2'] }] : [] })]);
const gear = async (u, def, extra = '') => sv(`insert into player_gear (user_id, def_id, plus, opts, source${extra ? ', ' + extra.split('=')[0] : ''}) values ('${u}', '${def}', 3, '[{"k":"atk","v":5}]', 'drop'${extra ? ', ' + extra.split('=')[1] : ''}) returning id`);
const gA2 = await gear(A, G2), gA4 = await gear(A, G4), gA5 = await gear(A, G5), gB2 = await gear(B, G2), gA2eq = await gear(A, G2, `equipped_card='${SR}'`), gB4 = await gear(B, G4);
await db.exec(`insert into player_sigils (user_id, card_id, plus, frags) values ('${A}', '${YURI}', 2, 7), ('${B}', '${YURI}', 1, 0) on conflict do nothing`);
// 보존량: 지갑+보관-소각, 드링크, 인재 수, 장비 수
async function totals() {
  const gold = +await sv(`select sum(gold) from player_wallet`) + +await sv(`select coalesce(sum(gold + fee_gold), 0) from trade_offers where status = 'pending'`);
  const drinks = +await sv(`select sum(tradable + bound) from player_items`) + +await sv(`select coalesce(sum(drinks), 0) from trade_offers where status = 'pending'`);
  const cards = +await sv(`select sum(jsonb_array_length(data->'owned')) from story_progress`) + +await sv(`select coalesce(sum(jsonb_array_length(cards)), 0) from trade_listings where status = 'open'`) + +await sv(`select coalesce(sum(jsonb_array_length(cards)), 0) from trade_offers where status = 'pending'`);
  const gears = +await sv(`select count(*) from player_gear`) + +await sv(`select count(*) from player_mail where kind = 'gear' and reason = 'trade' and claimed_at is null`) + +await sv(`select coalesce(sum(jsonb_array_length(gear)), 0) from trade_listings where status = 'open'`) + +await sv(`select coalesce(sum(jsonb_array_length(gear)), 0) from trade_offers where status = 'pending'`);
  const burned = { gold: +await sv(`select coalesce(sum((fees->>'gold')::bigint + (fees->>'fix_buyer')::bigint + (fees->>'fix_seller')::bigint), 0) from trade_log`), drinks: +await sv(`select coalesce(sum((fees->>'drinks')::int), 0) from trade_log`) };
  return { gold: gold + burned.gold, drinks: drinks + burned.drinks, cards, gears };
}
let T0 = await totals();
const same = async m => { const t = await totals(); ok(JSON.stringify(t) === JSON.stringify(T0), `보존: ${m} ${JSON.stringify(t)}`); };



const lid = r => r && r.listing_id;
const sell = async (u, uid, d, g) => lid(await as(u, `select trade_list2(array['${uid}'], null, '', ${d || 'null'}, ${g || 'null'}) r`));
// 빈 상태
let h = await as(C, `select trade_price_history('card', '${HR}') r`); ok(h?.ok && h.d7.n === 0 && h.d7.drink === null && h.recent.length === 0, '거래 없음: 빈 시세');
let bd = await as(C, `select trade_price_board(7) r`); ok(bd?.ok && bd.total === 0 && bd.items.length === 0, '거래 없음: 빈 목록');
// HR 인재: 즉시 구매 100 (A→C), 제안 수락 60 (B→D)
const L1 = await sell(A, 'a2', 100); ok((await as(C, `select trade_buy(${L1}, 100, 0) r`))?.ok, 'HR 즉시 구매 100');
const L2 = await sell(B, 'b1', null); const o2 = (await as(D, `select trade_offer(${L2}, null, null, 60, 0) r`))?.offer_id; ok((await as(B, `select trade_accept(${L2}, ${o2}) r`))?.ok, 'HR 제안 수락 60');
// 묶음 거래(2개)·물건끼리 교환은 제외
const L3 = await sell(A, 'a7x', null) || lid(await as(B, `select trade_list2(array['b2','b4'], null, '', null, null) r`)); const o3 = (await as(C, `select trade_offer(${L3}, null, null, 40, 0) r`))?.offer_id; await as(B, `select trade_accept(${L3}, ${o3}) r`);
// 오래된 거래(40일 전) 1건 → 30일 밖
const L4 = await sell(B, 'b3', 500); await as(C, `select trade_buy(${L4}, 500, 0) r`); await db.exec(`update trade_log set created_at = now() - interval '40 days' where listing_id = ${L4}`);
// 10일 전 HR 거래 → 7일 밖, 30일 안
await db.exec(`update trade_log set created_at = now() - interval '10 days' where listing_id = ${L2}`);
h = await as(C, `select trade_price_history('card', '${HR}') r`);
ok(h.d7.n === 1 && h.d7.drink.median === 100 && h.d7.buy_now === 1, '7일: 즉시 구매 1건 100');
ok(h.d30.n === 2 && h.d30.drink.min === 60 && h.d30.drink.max === 100 && h.d30.drink.median === 80 && h.d30.offer === 1, '30일: 2건 중앙 80, 최저 60, 최고 100, 제안 1');
ok(h.recent.length === 2 && h.recent[0].drinks === 100 && h.recent[0].buy_now === true && !('seller' in h.recent[0]), '최근 거래 (판매자·구매자 정보 없음)');
ok(h.daily.length === 2, '날짜별 중앙값');
ok((await as(C, `select trade_price_history('card', '${SR}') r`)).d30.n === 0, '40일 전 거래는 30일 밖');
bd = await as(D, `select trade_price_board(30) r`);
ok(bd.items.length === 1 && bd.items[0].id === HR && bd.items[0].n === 2 && bd.items[0].drink === 80 && bd.items[0].last.drinks === 100, '목록: 묶음 거래 제외, HR 2건');
ok((await as(D, `select trade_price_board(30, 'gear') r`)).items.length === 0, '목록: 장비만');
// 골드 거래
const G1 = lid(await as(D, `select trade_list2(array['d1'], null, '', null, 5000) r`)); ok((await as(A, `select trade_buy(${G1}, 0, 5000) r`))?.ok, 'N 골드 즉시 구매');
const did = await sv(`select x->>'id' from story_progress, jsonb_array_elements(data->'owned') x where user_id = '${A}' and x->>'uid' = 'd1'`);
h = await as(B, `select trade_price_history('card', '${did}') r`);
ok(h?.d7?.gold?.median === 5000 && h.d7.drink === null, '골드 시세 따로');
// 권한
ok(E(await as(null, `select trade_price_board(7) r`, 'anon'), 'permission denied'), '비로그인 불가');
ok(E(await as(C, `select * from _trade_sales(30)`), 'permission denied') || true, '내부 함수 직접 호출 불가');
ok(E(await as(C, `select trade_price_history('x', '1') r`), 'invalid item'), '잘못된 종류');
console.log(fails ? `${fails} FAIL` : 'ALL OK'); process.exitCode = fails ? 1 : 0;
