// supabase/trade_buynow_search.sql 검증 (즉시 구매·서버 검색) — 기반: trade_board.sql (PGlite): 글·제안·보관·수락·거절·취소·만료, 수수료, 골드·가격 규칙, 증표·장착·덱, 보존량, 경쟁 상황
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
await run('trade_board.sql'); await run('trade_admin.sql'); await run('trade_buynow_search.sql'); await run('trade_buynow_search.sql');
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
// ---- 올리기: 즉시 구매가 범위 검사
ok(E(await as(A, `select trade_list2(array['a2'], null, '', 999999, null) r`), 'price too high'), '즉시 구매가: 범위 위 → 실패');
ok(E(await as(A, `select trade_list2(array['a2'], null, '', 1, null) r`), 'price too low'), '즉시 구매가: 범위 아래 → 실패');
ok(E(await as(A, `select trade_list2(array['a1'], null, '', null, 50000) r`), 'gold not allowed'), 'SR 골드 즉시 구매가 불가');
ok(E(await as(A, `select trade_list2(array['a2'], null, '', 10, 6000) r`), 'buy one currency'), '드링크·골드 동시 불가');
await same('실패한 올리기는 보관 되돌림');
const L1 = lid(await as(A, `select trade_list2(array['a2'], null, 'hr 팝니다', 100, null) r`)); ok(L1, '즉시 구매가 드링크 100 글');
const L2 = lid(await as(A, `select trade_list2(array['a1'], null, '', null, null) r`)); ok(L2, '가격 없는 글 (예전과 같음)');
const L3 = lid(await as(B, `select trade_list2(array['b2'], array[${gB2}]::bigint[], '', null, 8000) r`)); ok(L3, '골드 즉시 구매가 글');
await same('올리기');
// ---- 게시판·검색
const bd = await as(C, `select trade_board(50) r`); ok(bd.listings.find(x => x.id === L1)?.buy_drinks === 100, '게시판에 즉시 구매가');
let sr = await as(C, `select trade_search(p_buy_only => true) r`); ok(sr.listings.length === 2 && sr.listings.every(x => x.buy_drinks || x.buy_gold), '검색: 즉시 구매만');
sr = await as(C, `select trade_search(p_type => 'gear') r`); ok(sr.listings.length === 1 && sr.listings[0].id === L3, '검색: 장비 포함 글');
sr = await as(C, `select trade_search(p_gkeys => array['card_sr']) r`); ok(sr.listings.length === 1 && sr.listings[0].id === L2, '검색: 등급 키');
sr = await as(C, `select trade_search(p_card_ids => array['${HR}']) r`); ok(sr.listings.some(x => x.id === L1) && !sr.listings.some(x => x.id === L2), '검색: 인재 id (이름→id)');
const gname = await sv(`select left(name, 2) from gear_defs where id = '${G2}'`);
sr = await as(C, `select trade_search(p_q => '${gname}') r`); ok(sr.listings.some(x => x.id === L3), '검색: 장비 이름 일부 ' + gname);
sr = await as(C, `select trade_search(p_q => '%') r`); ok(sr.listings.length === 0 || sr.listings.every(x => x.gear.length), '검색: % 는 글자 그대로');
sr = await as(C, `select trade_search(p_sort => 'price', p_buy_only => true) r`); ok(sr.listings[0].id === L3, '검색: 가격 낮은 순 (골드 8000≈드링크 80 < 100)');
sr = await as(C, `select trade_search(p_limit => 1) r`); const sr2 = await as(C, `select trade_search(p_limit => 1, p_offset => 1) r`);
ok(sr.more === true && sr.listings.length === 1 && sr2.listings[0].id !== sr.listings[0].id, '검색: 페이지 (more · offset)');
ok(E(await as(null, `select trade_search() r`, 'anon'), 'permission denied') || E(await as(null, `select trade_search() r`, 'anon'), 'login'), '비로그인 검색 불가');
// ---- 즉시 구매
ok(E(await as(A, `select trade_buy(${L1}, 100, 0) r`), 'own listing'), '내 글 구매 불가');
ok(E(await as(C, `select trade_buy(${L2}, 100, 0) r`), 'no buy price'), '가격 없는 글 즉시 구매 불가');
ok(E(await as(C, `select trade_buy(${L1}, 90, 0) r`), 'price changed'), '화면 가격과 다르면 실패');
const aDr0 = +await sv(`select tradable from player_items where user_id = '${A}'`), cDr0 = +await sv(`select tradable from player_items where user_id = '${C}'`);
const r1 = await as(C, `select trade_buy(${L1}, 100, 0) r`); ok(r1?.ok && r1.buy_now, '즉시 구매 성공');
ok(+await sv(`select tradable from player_items where user_id = '${A}'`) - aDr0 === 90, '판매자 드링크 +90 (10% 소각)');
ok(cDr0 - +await sv(`select tradable from player_items where user_id = '${C}'`) === 100, '구매자 드링크 -100');
ok(await sv(`select data->'owned' @> '[{"uid":"a2"}]' from story_progress where user_id = '${C}'`), '구매자가 인재 받음');
ok(await sv(`select buy_now from trade_log where listing_id = ${L1}`) === true, '기록: buy_now 표시 · 가격은 buyer_gave');
ok(E(await as(D, `select trade_buy(${L1}, 100, 0) r`), 'listing closed'), '이미 팔린 글 → 실패');
await same('즉시 구매');
// 제안이 있던 글을 즉시 구매 → 다른 제안은 환불
await as(D, `select trade_offer(${L3}, null, null, 0, 9000) r`);
ok(E(await as(D, `select trade_buy(${L3}, 0, 8000) r`), 'already offered'), '내 제안이 있으면 먼저 취소 안내');
const r3 = await as(C, `select trade_buy(${L3}, 0, 8000) r`); ok(r3?.ok && r3.refunded === 1, '골드 즉시 구매 + 다른 제안 환불');
await same('제안 있던 글 즉시 구매');
// 만료
const L4 = lid(await as(A, `select trade_list2(array['a7x'], null, '', 10, null) r`)) || lid(await as(B, `select trade_list2(array['b1'], null, '', 10, null) r`));
await db.exec(`update trade_listings set expires_at = now() - interval '1 minute' where id = ${L4}`);
const r4 = await as(C, `select trade_buy(${L4}, 10, 0) r`); ok(r4 && r4.ok === false && await sv(`select status from trade_listings where id = ${L4}`) === 'expired', '만료된 글: 즉시 만료 처리 후 실패');
await same('만료');
// 판매자 수락 경로는 그대로
const L5 = lid(await as(B, `select trade_list2(array['b3'], null, '', null, null) r`)); const o5 = (await as(C, `select trade_offer(${L5}, null, null, 50, 0) r`))?.offer_id;
const r5 = await as(B, `select trade_accept(${L5}, ${o5}) r`); ok(r5?.ok && r5.buy_now === false, '기존 수락(trade_accept) 그대로 동작');
ok(E(await as(C, `select trade_accept(${L5}, ${o5}) r`), 'listing not found'), '남의 글 수락 불가 (그대로)');
await same('수락');
ok(E(await as(null, `select _trade_accept_core(1, 1, '${A}', true) r`, 'authenticated'), 'permission denied'), '수락 본체는 직접 호출 불가');
console.log(fails ? `${fails} FAIL` : 'ALL OK'); process.exitCode = fails ? 1 : 0;
