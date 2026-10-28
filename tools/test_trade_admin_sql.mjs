// supabase/trade_admin.sql 검증 (PGlite): 드링크 하루 이동량 · 취소 남발 · 의심 거래 표시 · 관리자 조회·강제 내림·환불·조절표
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
await run('trade_board.sql'); await run('trade_admin.sql'); await run('trade_admin.sql');
let fails = 0; const ok = (c, m) => { if (!c) { fails++; console.log('FAIL', m); } else console.log('ok  ', m); };
const sv = async s => Object.values((await db.query(s)).rows[0] || { x: null })[0];
const as = async (sub, sql, role = 'authenticated') => { await db.exec(`reset role; select set_config('request.jwt.claims', '${JSON.stringify(sub ? { sub } : {})}', false); set role ${role};`); try { return (await db.query(sql)).rows[0]?.r; } catch (e) { return { err: e.message }; } finally { await db.exec('reset role'); } };
const E = (r, m) => r && r.err && r.err.includes(m);
// 등급별 카드·장비 id
const cg = async g => sv(`select id from story_card_pool where grade = '${g}' order by id limit 1`);
const HR = await cg('HIGH RARE'), SR = await cg('SUPER RARE'), NR = await cg('RARE'), YURI = '2000100001';
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
const adm = s => as(ADMIN, s).then(r => r);
await db.exec(`reset role; select set_config('request.jwt.claims', '${JSON.stringify({ sub: ADMIN, email: 'stevejean77@gmail.com' })}', false)`);
const asAdmin = async sql => { await db.exec(`select set_config('request.jwt.claims', '${JSON.stringify({ sub: ADMIN, email: 'stevejean77@gmail.com' })}', false); set role authenticated;`); try { return (await db.query(sql)).rows[0]?.r; } catch (e) { return { err: e.message }; } finally { await db.exec('reset role'); } };
// 드링크 보내기 한도: 1,000 으로 낮춤
await db.exec(`update trade_config set val = 1000 where key in ('daily_drink_send', 'daily_drink_recv')`);
let r = await as(A, `select trade_list(array['a1'], null) r`); const L1 = r.listing_id;   // SR: 드링크 20~1000
r = await as(B, `select trade_offer(${L1}, null, null, 900, 0) r`); ok(r?.ok, '제안 900');
r = await as(A, `select trade_accept(${L1}, ${r.offer_id}) r`); ok(r?.ok, '수락 (오늘 보낸 900)');
r = await as(A, `select trade_list(array['a2'], null) r`); const L2 = r.listing_id;   // HR: 5~200
ok(E(await as(B, `select trade_offer(${L2}, null, null, 150, 0) r`), 'drink send limit'), '보내기 한도: 900 + 150 > 1,000 → 제안 불가');
r = await as(C, `select trade_offer(${L2}, null, null, 150, 0) r`); ok(r?.ok, 'C 는 제안 가능');
const drinkA = await sv(`select tradable from player_items where user_id = '${A}'`);
ok(E(await as(A, `select trade_accept(${L2}, ${r.offer_id}) r`), 'drink recv limit'), '받기 한도: A 오늘 810 받음 + 150 > 1,000 → 수락 불가');
ok(await sv(`select tradable from player_items where user_id = '${A}'`) === drinkA && await sv(`select status from trade_offers where id = ${r.offer_id}`) === 'pending', '수락 실패 시 아무것도 안 움직임');
await db.exec(`update trade_config set val = 10000 where key in ('daily_drink_send', 'daily_drink_recv')`);
// 취소 남발
await db.exec(`update trade_config set val = 2 where key = 'daily_cancels'`);
for (let i = 0; i < 2; i++) { const o = await as(D, `select trade_offer(${L2}, null, null, 10, 0) r`); await as(D, `select trade_offer_cancel(${o.offer_id}) r`); }
ok(E(await as(D, `select trade_offer(${L2}, null, null, 10, 0) r`), 'cancel limit'), '하루 취소 2번 넘으면 제안 불가');
// 의심 표시: 첫 거래(SR ↔ 900, 범위 끝 근처 1000×0.95=950 미만이라 아님) — 새 계정 아님. 반복: B↔A 두 번째 거래
await db.exec(`update trade_config set val = 0 where key = 'reoffer_cooldown_hours'`);
r = await as(A, `select trade_list(array['a6'], null) r`); const L3 = r.listing_id;   // HR
r = await as(B, `select trade_offer(${L3}, null, null, 200, 0) r`); r = await as(A, `select trade_accept(${L3}, ${r.offer_id}) r`); ok(r?.ok, 'A↔B 두 번째 거래 (HR ↔ 드링크 200 = 최대)');
const kinds = (await db.query(`select kind from trade_flags f join trade_log l on l.id = f.log_id where l.listing_id = ${L3}`)).rows.map(x => x.kind).sort().join(',');
ok(kinds.includes('repeat_pair') && kinds.includes('band_edge'), '의심 표시: 같은 상대 반복 + 범위 끝 → ' + kinds);
await db.exec(`update auth.users set created_at = now() where id = '${D}'; update trade_config set val = 0 where key = 'min_account_days'; update trade_config set val = 100 where key = 'daily_cancels'`);
await db.exec(`update story_progress set data = jsonb_set(data, '{owned}', (data->'owned') || '[{"uid":"d9","id":"${SR}","bound":false}]') where user_id = '${D}'`);
r = await as(D, `select trade_list(array['d9'], null) r`); const L4 = r.listing_id;
r = await as(C, `select trade_offer(${L4}, array['c1'], null, 0, 0) r`); ok(r?.ok, 'SR ↔ N 인재 (물건끼리)');
r = await as(D, `select trade_accept(${L4}, ${r.offer_id}) r`); ok(r?.ok, '수락');
const k4 = (await db.query(`select kind from trade_flags f join trade_log l on l.id = f.log_id where l.listing_id = ${L4}`)).rows.map(x => x.kind).sort().join(',');
ok(k4.includes('new_account') && k4.includes('lopsided'), '의심 표시: 새 계정 + 한쪽으로 기운 거래 → ' + k4);
// 관리자
ok(E(await as(B, `select admin_trade_log() r`), 'forbidden'), '일반 유저는 관리자 함수 불가');
r = await asAdmin(`select admin_trade_log() r`); ok(Array.isArray(r) && r.length === 3 && r[0].flags.length >= 1, '관리자: 거래 기록 3건 + 의심 표시');
r = await asAdmin(`select admin_trade_log('${D}') r`); ok(r.length === 1, '관리자: 유저별 거래 기록');
r = await asAdmin(`select admin_trade_flags() r`); ok(r.length >= 4, '관리자: 의심 거래 목록');
ok((await asAdmin(`select admin_trade_flag_review(${r[0].id}, '확인함') r`))?.ok && (await asAdmin(`select admin_trade_flags() r`)).length === r.length - 1, '확인 처리하면 목록에서 빠짐');
r = await asAdmin(`select admin_trade_pairs(7) r`); ok(r.some(p => p.trades === 2), '같은 상대 반복 상위');
// 강제 내림 · 강제 환불
r = await asAdmin(`select admin_trade_listings(null, 'open') r`); ok(r.some(l => l.id === L2), '관리자: 열린 글 조회');
ok(E(await asAdmin(`select admin_trade_void_listing(${L2}, '') r`), 'reason required'), '사유 필수');
const pend = await sv(`select id from trade_offers where listing_id = ${L2} and status = 'pending' limit 1`);
const cDr = await sv(`select tradable from player_items where user_id = '${C}'`);
r = await asAdmin(`select admin_trade_refund_offer(${pend}, '테스트 환불') r`); ok(r?.ok && await sv(`select tradable from player_items where user_id = '${C}'`) === cDr + 150, '제안 강제 환불 → C 드링크 돌아옴');
r = await asAdmin(`select admin_trade_void_listing(${L2}, '의심 글') r`); ok(r?.ok && await sv(`select status from trade_listings where id = ${L2}`) === 'cancelled', '글 강제 내림');
ok((await db.query(`select data from story_progress where user_id = '${A}'`)).rows[0].data.owned.some(o => o.uid === 'a2'), '강제 내림: 판매 물건 반환');
ok(+await sv(`select count(*) from admin_log where action like 'trade_%'`) === 2, 'admin_log 에 기록');
// 조절표
r = await asAdmin(`select admin_trade_config_set('max_open_listings', 3, '조정') r`); ok(r?.before === 5 && r.after === 3, '조절표 수정');
ok(E(await asAdmin(`select admin_trade_config_set('fee_pct', 90, 'x') r`), 'invalid value'), '수수료 50% 초과 불가');
ok(E(await asAdmin(`select admin_trade_config_set('nope', 1, 'x') r`), 'not found'), '없는 키');
r = await asAdmin(`select admin_trade_band_set('card_sr', 'g_max', 50000, '골드 허용 실험') r`); ok(E(r, 'invalid band'), 'g_min 없이 g_max 만 넣으면 거부');
r = await asAdmin(`select admin_trade_band_set('card_hr', 'g_max', null, '골드 금지') r`); ok(r?.ok && await sv(`select g_min from trade_band where gkey = 'card_hr'`) === null, 'HR 골드 금지로 (짝으로 null)');
r = await asAdmin(`select admin_trade_config() r`); ok(r.config.length > 15 && r.bands.length === 8, '조절표 보기');
for (const f of ['admin_trade_log()', 'admin_trade_flags()', 'admin_trade_config()']) ok(!!(await as(null, `select ${f} r`, 'anon')).err, `anon 거부: ${f}`);
ok(!!(await as(B, `select * from trade_flags`)).err, '의심 표 직접 읽기 불가');
console.log(fails ? `${fails} FAIL` : 'ALL OK'); process.exit(fails ? 1 : 0);
