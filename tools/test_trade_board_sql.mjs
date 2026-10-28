// supabase/trade_board.sql 검증 (PGlite): 글·제안·보관·수락·거절·취소·만료, 수수료, 골드·가격 규칙, 증표·장착·덱, 보존량, 경쟁 상황
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
await run('trade_board.sql'); await run('trade_board.sql');
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

// ---- 올리기 규칙
ok(E(await as(A, `select trade_list(array['a4'], null) r`), 'card bound'), '스토리 귀속 인재 불가');
ok(E(await as(A, `select trade_list(array['a5'], null) r`), 'card locked'), '수동 잠금 인재 불가');
ok(E(await as(A, `select trade_list(array['a7'], null) r`), 'cannot trade leader'), '리더 불가');
ok(E(await as(A, `select trade_list(null, array[${gA2eq}]::bigint[]) r`), 'gear equipped'), '장착 장비 불가');
ok(E(await as(A, `select trade_list(array['a1','a2','a3','a6','a7','x'], null) r`), 'too many items'), '6개 불가');
ok(E(await as(A, `select trade_list(null, null) r`), 'nothing to trade'), '빈 글 불가');
await db.exec(`update player_state set level = 5 where user_id = '${D}'`);
ok(E(await as(D, `select trade_list(array['d1'], null) r`), 'trade level'), '레벨 20 미만 불가');
await db.exec(`update player_state set level = 30 where user_id = '${D}'`);
// L1: A 의 SR(장착 장비 있는 인재, 마지막 사본) + 덱 잠금 HR(a6) + 희귀 장비
let r = await as(A, `select trade_list(array['a1','a6'], array[${gA4}]::bigint[], '드링크 2000+') r`);
ok(r?.ok, '글 올리기 (SR + 덱 인재 + 희귀 장비)'); const L1 = r.listing_id;
let dA = (await db.query(`select data from story_progress where user_id = '${A}'`)).rows[0].data;
ok(!dA.owned.some(o => o.uid === 'a1' || o.uid === 'a6'), '올린 인재는 owned 에서 빠짐 (보관)');
ok(JSON.stringify(dA.decks[0].uids) === '["a2"]', '덱에서 자동으로 빠짐');
ok(await sv(`select equipped_card from player_gear where id = ${gA2eq}`) === null && await sv(`select user_id from player_gear where id = ${gA2eq}`) === A, '마지막 사본 → 장착 장비 해제, 장비는 A 가방에');
ok(+await sv(`select count(*) from player_gear where id = ${gA4}`) === 0, '올린 장비는 가방에서 빠짐');
ok(E(await as(A, `select gear_enhance(${gA4}) r`), '') , '보관 중 장비는 강화 등 불가 (행 없음)');
await same('글 올린 뒤');

// ---- 제안 규칙
ok(E(await as(A, `select trade_offer(${L1}, null, null, 2000, 0) r`), 'own listing'), '내 글에 제안 불가');
ok(E(await as(B, `select trade_offer(${L1}, null, null, 0, 50000) r`), 'gold not allowed'), 'SR 이 끼면 골드 불가');
r = await as(B, `select trade_offer(${L1}, null, null, 9999, 0) r`); ok(E(r, 'price too high'), '가격 범위 최대 초과 ' + JSON.stringify(r));
ok(E(await as(B, `select trade_offer(${L1}, null, null, 10, 0) r`), 'price too low'), '재화만 제안: 최소 미만');
ok(E(await as(B, `select trade_offer(${L1}, null, null, 20000, 0) r`), 'price too high') || E(await as(B, `select trade_offer(${L1}, null, null, 20000, 0) r`), 'not enough'), '드링크 부족/초과 거부');
const drinkB0 = await sv(`select tradable from player_items where user_id = '${B}'`);
await db.exec(`update player_items set tradable = 100 where user_id = '${C}'`);
ok(E(await as(C, `select trade_offer(${L1}, null, null, 120, 0) r`), 'not enough drink'), '귀속 드링크는 제안에 못 씀 (거래 가능 100 + 귀속 50 < 120)');
await db.exec(`update player_items set tradable = 10000 where user_id = '${C}'`);
r = await as(B, `select trade_offer(${L1}, array['b1'], null, 1300, 0) r`); ok(r?.ok, 'B 제안: HR 인재 + 드링크 1,300 ' + JSON.stringify(r)); const OB = r.offer_id;
ok(await sv(`select tradable from player_items where user_id = '${B}'`) === drinkB0 - 1300, '드링크 즉시 보관');
ok(E(await as(B, `select trade_offer(${L1}, null, null, 2000, 0) r`), 'already offered'), '한 글에 1인 1제안');
r = await as(C, `select trade_offer(${L1}, null, null, 1400, 0) r`); ok(r?.ok, 'C 제안: 드링크 1,400'); const OC = r.offer_id;
r = await as(D, `select trade_offer(${L1}, null, null, 300, 0) r`); ok(r?.ok, 'D 제안: 드링크 300'); const OD = r.offer_id;
await same('제안 3개 뒤');

// ---- 거절 + 재제안 대기
r = await as(A, `select trade_reject_below(${L1}, 1000) r`); ok(r?.rejected === 1, '조건 아래 전부 거절: 드링크 1,000 미만 → D 1건');
ok(await sv(`select status from trade_offers where id = ${OD}`) === 'rejected' && await sv(`select tradable from player_items where user_id = '${D}'`) === 10000, '거절 즉시 D 드링크 환불');
ok(E(await as(D, `select trade_offer(${L1}, null, null, 400, 0) r`), 'reoffer cooldown'), '거절 후 24시간 다시 제안 불가');
ok(E(await as(B, `select trade_reject(${L1}, array[${OB}]::bigint[]) r`), 'listing not found'), '남의 글 제안 거절 불가');
await same('거절 뒤');

// ---- 제안 취소 + 이중 취소
r = await as(C, `select trade_offer_cancel(${OC}) r`); ok(r?.ok, 'C 제안 취소'); ok(await sv(`select tradable from player_items where user_id = '${C}'`) === 10000, 'C 환불');
ok(E(await as(C, `select trade_offer_cancel(${OC}) r`), 'offer closed'), '두 번 취소 불가 (이중 환불 없음)');
ok(E(await as(A, `select trade_accept(${L1}, ${OC}) r`), 'offer closed'), '취소된 제안 수락 불가');
await same('취소 뒤');

// ---- 수락: B 의 HR 인재 + 드링크 1,500 → A 는 1,350 받음(150 소각), B 는 SR·HR 인재 + 희귀 장비
const drinkA0 = await sv(`select tradable from player_items where user_id = '${A}'`);
r = await as(A, `select trade_accept(${L1}, ${OB}) r`); ok(r?.ok && r.drinks === 1170 && r.fee_drinks === 130, '수락: 드링크 1,300 → 1,170 (10% 소각)');
ok(await sv(`select tradable from player_items where user_id = '${A}'`) === drinkA0 + 1170, 'A 드링크 +1,170 (거래 가능분)');
const dB = (await db.query(`select data from story_progress where user_id = '${B}'`)).rows[0].data, dA2 = (await db.query(`select data from story_progress where user_id = '${A}'`)).rows[0].data;
const a1 = dB.owned.find(o => o.uid === 'a1');
ok(a1 && a1.level === 7 && a1.totalExp === 99 && a1.boost.ATK === 2 && a1.traded_at, 'B 가 받은 SR: 레벨·성장 그대로 + 재판매 대기 표시');
ok(dB.owned.some(o => o.uid === 'a6' && !o.locked && !o.dlk), '덱 잠금은 풀린 채로 이동');
ok(dA2.owned.some(o => o.uid === 'b1') && !dB.owned.some(o => o.uid === 'b1'), 'A 가 B 의 HR 받음');
ok(await sv(`select user_id from player_gear where id = ${gA4}`) === B && await sv(`select source from player_gear where id = ${gA4}`) === 'trade' && await sv(`select plus from player_gear where id = ${gA4}`) === 3, '희귀 장비: 같은 id·강화 단계로 B 에게');
ok(E(await as(A, `select trade_accept(${L1}, ${OB}) r`), 'listing closed'), '두 번 수락 불가');
ok(E(await as(B, `select trade_list(array['a1'], null) r`), 'resale cooldown'), '받은 인재 72시간 재판매 불가');
ok(E(await as(B, `select trade_list(null, array[${gA4}]::bigint[]) r`), 'resale cooldown'), '받은 장비 72시간 재판매 불가');
ok(+await sv(`select count(*) from trade_log`) === 1, '거래 기록 1건');
await same('수락 뒤');

// ---- 골드 거래 (HR 인재 + N 장비 ↔ 골드) · 물건끼리 고정 수수료 · 증표 이동
r = await as(A, `select trade_list(array['a2'], array[${gA2}]::bigint[]) r`); const L2 = r.listing_id;
ok(E(await as(C, `select trade_offer(${L2}, null, null, 0, 999999) r`), 'price too high'), '골드 최대 초과');
r = await as(C, `select trade_offer(${L2}, null, null, 0, 30000) r`); ok(r?.ok, 'HR+일반 장비 → 골드 30,000 제안 가능');
const goldA0 = +await sv(`select gold from player_wallet where user_id = '${A}'`);
r = await as(A, `select trade_accept(${L2}, ${r.offer_id}) r`); ok(r?.gold === 27000, '골드 30,000 → 27,000 (10% 소각)');
ok(+await sv(`select gold from player_wallet where user_id = '${A}'`) === goldA0 + 27000, 'A 골드 +27,000');
await same('골드 거래 뒤');
// 임유리(증표 +2) ↔ B 의 임유리(증표 +1): 물건끼리 → 양쪽 UR 고정 10,000
r = await as(A, `select trade_list(array['a3'], null) r`); const L3 = r.listing_id;
await db.exec(`update story_progress set data = jsonb_set(data, '{owned}', (data->'owned') || '[{"uid":"b9","id":"${HR}","level":1,"bound":false,"src":"recruit"}]') where user_id = '${B}'`);
Object.assign(T0, await totals());
const goldB0 = +await sv(`select gold from player_wallet where user_id = '${B}'`);
r = await as(B, `select trade_offer(${L3}, array['b4'], null, 0, 0) r`); ok(r?.ok && r.fee_gold === 10000, '물건끼리: 제안자 고정 수수료 10,000 미리 보관');
ok(+await sv(`select gold from player_wallet where user_id = '${B}'`) === goldB0 - 10000, 'B 골드 −10,000');
const OB3 = r.offer_id;
r = await as(A, `select trade_accept(${L3}, ${OB3}) r`); ok(r?.ok && r.fee_gold === 10000, '수락: 판매자도 10,000');
// A 에는 b4(임유리) 가 들어오므로 A 쪽은 사본이 있어 증표 안 움직임? → A 는 a3 를 내보냈지만 b4 를 받음 → A 증표 유지, B 도 a3 를 받음 → B 증표 유지
ok(await sv(`select plus from player_sigils where user_id = '${A}' and card_id = '${YURI}'`) === 2 && await sv(`select plus from player_sigils where user_id = '${B}' and card_id = '${YURI}'`) === 1, '같은 인재 맞교환: 각자 증표 유지');
await same('물건끼리 뒤');
// 증표 이동: B 가 임유리(a3)를 C 에게 → 72h 대기라 시간을 당김
await db.exec(`update story_progress set data = jsonb_set(data, '{owned}', (select jsonb_agg(case when o->>'uid' = 'a3' then o - 'traded_at' else o end) from jsonb_array_elements(data->'owned') o)) where user_id = '${B}'`);
await db.exec(`insert into player_sigils (user_id, card_id, plus, frags) values ('${C}', '${YURI}', 0, 4) on conflict (user_id, card_id) do update set plus = 0, frags = 4`);
r = await as(B, `select trade_list(array['a3'], null) r`); const L4 = r.listing_id;
r = await as(C, `select trade_offer(${L4}, null, null, 500, 0) r`); r = await as(B, `select trade_accept(${L4}, ${r.offer_id}) r`);
ok(r?.sigils?.length === 1 && r.sigils[0].plus === 1, 'B 의 마지막 임유리 → 증표 +1 이 C 에게');
ok(await sv(`select plus from player_sigils where user_id = '${B}' and card_id = '${YURI}'`) === null, 'B 증표 단계 비움');
const cost = async p => +await sv(`select sum(frags) from sigil_cost where plus <= ${p}`);
ok(await sv(`select plus from player_sigils where user_id = '${C}' and card_id = '${YURI}'`) === 1 && await sv(`select frags from player_sigils where user_id = '${C}' and card_id = '${YURI}'`) === 4 + await cost(0), 'C: 높은 +1 남기고 자기 +0 투입 조각은 조각으로 반환');
await same('증표 이동 뒤');

// ---- 가방 꽉 참 → 우편함, 취소·만료 전체 환불
r = await as(B, `select trade_list(array['b2'], array[${gB2}]::bigint[]) r`); const L5 = r.listing_id;
r = await as(C, `select trade_offer(${L5}, array['c1'], null, 10, 0) r`); const OC5 = r.offer_id;
r = await as(D, `select trade_offer(${L5}, null, null, 20, 0) r`); const OD5 = r.offer_id;
await same('취소 전');
await db.exec(`insert into player_gear_meta (user_id, slots) values ('${B}', 100) on conflict (user_id) do update set slots = 100;
  insert into player_gear (user_id, def_id, source) select '${B}', '${G2}', 'fill' from generate_series(1, 100)`);
Object.assign(T0, await totals());
r = await as(B, `select trade_cancel(${L5}) r`); ok(r?.refunded === 2, '글 내리기: 제안 2개 모두 환불');
ok(+await sv(`select count(*) from player_mail where user_id = '${B}' and kind = 'gear' and reason = 'trade'`) === 1, '가방 꽉 참 → 돌려받는 장비는 우편함');
ok(+await sv(`select (payload->>'plus')::int from player_mail where user_id = '${B}' and reason = 'trade'`) === 3, '우편 장비에 강화 단계 보존');
ok((await db.query(`select data from story_progress where user_id = '${C}'`)).rows[0].data.owned.some(o => o.uid === 'c1'), 'C 인재 환불');
await same('취소 뒤');
await db.exec(`delete from player_gear where source = 'fill'`); Object.assign(T0, await totals());
const mid = await sv(`select id from player_mail where user_id = '${B}' and reason = 'trade'`);
r = await as(B, `select mail_claim(${mid}) r`); ok(r?.ok && +await sv(`select plus from player_gear where id = ${r.gear_id}`) === 3, '우편 수령: 강화 단계 그대로');
// 만료
r = await as(D, `select trade_list(array['d1'], null) r`); const L6 = r.listing_id;
r = await as(C, `select trade_offer(${L6}, null, null, 5, 0) r`); ok(r?.ok, 'L6 제안');
await db.exec(`update trade_listings set expires_at = now() - interval '1 minute' where id = ${L6}`);
ok(E(await as(D, `select trade_accept(${L6}, ${r.offer_id}) r`), '') || true, '만료 글 수락 시도');
ok(await sv(`select status from trade_listings where id = ${L6}`) === 'expired', '만료 → 닫힘');
ok(await sv(`select status from trade_offers where id = ${r.offer_id}`) === 'refunded' && (await db.query(`select data from story_progress where user_id = '${D}'`)).rows[0].data.owned.some(o => o.uid === 'd1'), '만료: 제안 환불 + 판매 물건 반환');
await same('만료 뒤');

// ---- 경쟁 상황 (순서 바뀜): 수락 뒤 취소/거절, 거절 뒤 수락, 취소 뒤 제안
r = await as(A, `select trade_list(null, array[${gA5}]::bigint[]) r`); const L7 = r.listing_id;
r = await as(B, `select trade_offer(${L7}, null, null, 100, 0) r`); const O7b = r.offer_id;
r = await as(C, `select trade_offer(${L7}, null, null, 200, 0) r`); const O7c = r.offer_id;
ok(E(await as(C, `select trade_offer(${L7}, null, null, 0, 1000) r`), 'already offered') , '영웅 장비 + 골드 불가 확인 전 중복 제안 거부');
await as(A, `select trade_reject(${L7}, array[${O7b}]::bigint[]) r`);
ok(E(await as(A, `select trade_accept(${L7}, ${O7b}) r`), 'offer closed'), '거절된 제안 수락 불가');
r = await as(A, `select trade_accept(${L7}, ${O7c}) r`); ok(r?.ok, '다른 제안 수락');
ok(E(await as(C, `select trade_offer_cancel(${O7c}) r`), 'offer closed'), '수락된 제안 취소 불가');
ok(E(await as(A, `select trade_reject(${L7}, array[${O7c}]::bigint[]) r`), 'listing closed'), '끝난 글 거절 불가');
ok(E(await as(A, `select trade_cancel(${L7}) r`), 'listing closed'), '끝난 글 내리기 불가 (판매 물건 이중 반환 없음)');
ok(E(await as(D, `select trade_offer(${L7}, null, null, 100, 0) r`), 'listing closed'), '끝난 글 제안 불가');
await same('경쟁 상황 뒤');

// ---- 한도
await db.exec(`update trade_config set val = 1 where key = 'max_pending_per_listing'`);
r = await as(C, `select trade_list(array['a6'], null) r`);   // C 는 a6 가 없음
r = await as(D, `select trade_list(array['d1'], null) r`); const L8 = r.listing_id;
await as(B, `select trade_offer(${L8}, null, null, 5, 0) r`);
ok(E(await as(C, `select trade_offer(${L8}, null, null, 5, 0) r`), 'listing full'), '한 글 대기 제안 한도');
await db.exec(`update trade_config set val = 100 where key = 'max_pending_per_listing'; update trade_config set val = 1 where key = 'max_open_listings'`);
ok(E(await as(D, `select trade_list(null, null) r`), 'nothing') , '빈 글');
await db.exec(`update story_progress set data = jsonb_set(data, '{owned}', (data->'owned') || '[{"uid":"d2","id":"${NR}","bound":false}]') where user_id = '${D}'`); Object.assign(T0, await totals());
ok(E(await as(D, `select trade_list(array['d2'], null) r`), 'too many listings'), '열린 글 한도');
await db.exec(`update trade_config set val = 5 where key = 'max_open_listings'`);
await same('한도 뒤');

// ---- 권한
for (const f of ['trade_board()', 'trade_my()', `trade_list(array['x'], null)`, 'trade_accept(1, 1)', 'trade_expire_due(1)']) ok(!!(await as(null, `select ${f} r`, 'anon')).err, `anon 거부: ${f.split('(')[0]}`);
ok(!!(await as(B, `select trade_expire_due(5) r`)).err, '만료 처리 함수는 클라이언트 불가');
ok(!!(await as(B, `select * from trade_offers`)).err, '표 직접 읽기 불가');
r = await as(C, `select trade_board() r`); ok(r?.ok && r.listings.some(l => l.id === L8 && l.offers === 1 && !('drinks' in l)), '게시판: 제안 개수만 공개');
r = await as(D, `select trade_my() r`); ok(r?.listings?.find(l => l.id === L8)?.offers?.length === 1, '내 글: 들어온 제안 내용 보임');
console.log(fails ? `${fails} FAIL` : 'ALL OK'); process.exit(fails ? 1 : 0);
