// supabase/gem.sql 검증 (PGlite): 심연석 잔액(무료/유료)·원장·상점·무료 획득·관리자·PvP 연동
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
await run('gem.sql'); await run('gem.sql');   // 두 번 실행해도 안전
let fails = 0; const ok = (c, m) => { if (!c) { fails++; console.log('FAIL', m); } else console.log('ok  ', m); };
async function as(role, claims, sql) {
  await db.exec(`reset role; select set_config('request.jwt.claims', '${JSON.stringify(claims || {})}', false); set role ${role};`);
  try { return { rows: (await db.query(sql)).rows }; } catch (e) { return { err: e.message }; } finally { await db.exec('reset role'); }
}
const one = r => r.rows?.[0] && Object.values(r.rows[0])[0];
const q = s => as('authenticated', { sub: U, email: 'u@x.com' }, s), qa = s => as('authenticated', { sub: ADMIN, email: 'stevejean77@gmail.com' }, s);
const bal = async () => (await db.query(`select gem_free f, gem_paid p from player_wallet where user_id='${U}'`)).rows[0] || { f: 0, p: 0 };
const tickets = async () => +((await db.query(`select tickets from story_gacha where user_id='${U}'`)).rows[0]?.tickets || 0);

// 상태 · 7일 접속
let r = await q(`select gem_status()`), st = one(r);
ok(!r.err && st.gem === 0 && st.shop.length === 5 && st.login_streak === 1 && Array.isArray(st.log), '처음 상태 ' + (r.err || ''));
ok(st.shop.find(s => s.item === 'ticket').price === 150 && st.shop.find(s => s.item === 'pull10').price === 1500 && st.shop.find(s => s.item === 'stamina').price === 100 && st.shop.find(s => s.item === 'pvp_try').price === 50 && st.shop.find(s => s.item === 'gold10k').price === 100, '가격표 150/1500/100/50/100');
await db.exec(`update gem_login set last_day = _gem_day() - 1, streak = 6 where user_id = '${U}'`);
st = one(await q(`select gem_status()`)); ok(st.granted.some(g => g.reason === 'login_7') && st.gem === 30, '7일 연속 접속 +30');
st = one(await q(`select gem_status()`)); ok(st.granted.length === 0 && st.gem === 30, '같은 날 다시 → 중복 없음');
await db.exec(`update gem_login set last_day = _gem_day() - 3, streak = 6 where user_id = '${U}'`);
st = one(await q(`select gem_status()`)); ok(st.login_streak === 1 && st.gem === 30, '하루 빠지면 연속 1부터');
// 챕터 첫 클리어 +50 (1회)
const phases = (await db.query(`select phase from story_phase_config where chapter = 1 order by phase`)).rows.map(x => x.phase);
await db.exec(`insert into story_progress (user_id, data) values ('${U}', '${JSON.stringify({ cleared: { 1: phases }, owned: [] })}'::jsonb) on conflict (user_id) do update set data = excluded.data`);
st = one(await q(`select gem_status()`)); ok(phases.length > 0 && st.granted.some(g => g.reason === 'chapter_clear' && g.chapter === 1) && st.gem === 80, '챕터1 첫 클리어 +50');
st = one(await q(`select gem_status()`)); ok(st.gem === 80, '챕터 보상 1회');
// 구매: 부족 → 롤백
const t0 = await tickets();
r = await q(`select gem_buy('pull10')`); ok(/not enough gem/.test(r.err || '') && await tickets() === t0, '부족하면 실패 · 소환권 그대로');
// 무료 먼저 사용: 유료 200 (나중 결제 흉내), 무료 80 → 소환권 150 = 무료 80 + 유료 70
await db.exec(`select _gem_add('${U}', 0, 200, 'iap', 'iap:test-1', '{}')`);
r = await q(`select gem_buy('ticket')`); ok(!r.err && one(r).gem === 130 && one(r).tickets === t0 + 1, '소환권 1장 구매 ' + (r.err || ''));
let b = await bal(); ok(+b.f === 0 && +b.p === 130, '무료 먼저 소진 (무료 0 · 유료 130)');
ok(one(await db.query(`select _gem_add('${U}', 0, 200, 'iap', 'iap:test-1', '{}') x`).then(x => ({ rows: x.rows }))) === null && +(await bal()).p === 130, '같은 ref 중복 지급 없음');
// 골드 10,000
const gold = async () => +((await db.query(`select gold from player_wallet where user_id='${U}'`)).rows[0]?.gold || 0); const g0 = await gold();
r = await q(`select gem_buy('gold10k')`); ok(!r.err && await gold() === g0 + 10000 && one(r).gem === 30, '골드 10,000 = 100');
// 행동력: 가득이면 거절, 100 → 150 → … 최대 5회
await db.exec(`select _gem_add('${U}', 5000, 0, 'test', null, '{}')`);
r = await q(`select gem_buy('stamina')`); ok(/stamina full/.test(r.err || ''), '행동력 가득이면 구매 불가');
const prices = [];
for (let i = 0; i < 6; i++) { await db.exec(`insert into player_state (user_id, stamina) values ('${U}', 0) on conflict (user_id) do update set stamina = 0, stamina_at = now()`); const x = await q(`select gem_buy('stamina')`); prices.push(x.err ? 'X' : one(x).price); if (!x.err && i === 0) ok(one(x).stamina > 0, '행동력 충전됨 ' + one(x).stamina); }
ok(prices.join() === '100,150,200,250,300,X', '행동력 가격 +50 · 하루 5회 ' + prices.join());
// PvP 추가 도전 (최대 3)
await q(`select pvp_set_deck('open','1v1',0,'["a","b"]')`);
r = await q(`select gem_buy('pvp_try')`); ok(/invalid|league|mode/.test(r.err || ''), 'pvp_try 리그·모드 필요 ' + r.err);
let s0 = one(await q(`select pvp_status('open','1v1')`));
for (let i = 0; i < 3; i++) r = await q(`select gem_buy('pvp_try','open','1v1')`);
ok(!r.err && one(r).pvp_extra === 3, '추가 도전 3회 ' + (r.err || ''));
ok(/daily limit/.test((await q(`select gem_buy('pvp_try','open','1v1')`)).err || ''), '추가 도전 하루 3회 제한');
let s1 = one(await q(`select pvp_status('open','1v1')`)); ok(s1 && s1.max === 13 && s1.left === s0.left + 3, 'PvP 남은 횟수 +3 ' + JSON.stringify({ l: s1?.left, m: s1?.max }));
ok(/invalid item/.test((await q(`select gem_buy('blood')`)).err || ''), '피·조각·혼 변환 없음');
// 보안
ok(!!(await q(`select _gem_add('${U}', 999, 0, 'x', null, '{}')`)).err, '지급 함수 클라이언트 호출 불가');
ok(!!(await q(`select _gem_spend('${U}', 1, 'x', '{}')`)).err, '사용 함수 클라이언트 호출 불가');
ok(!!(await q(`update player_wallet set gem_free = 99999 where user_id = '${U}'`)).err || +(await bal()).f !== 99999, '잔액 직접 수정 불가');
ok(!!(await q(`select * from gem_ledger`)).err, '원장 직접 읽기 불가');
ok(!!(await q(`insert into gem_ledger (user_id, free_after, paid_after, reason) values ('${U}', 1, 1, 'x')`)).err, '원장 직접 쓰기 불가');
ok(!!(await as('anon', {}, `select gem_status()`)).err, 'anon 불가');
// 지갑 상태
let w = one(await q(`select wallet_status()`)); b = await bal(); ok(w.gem === +b.f + +b.p && w.gem_free === +b.f && w.gem_paid === +b.p, 'wallet_status 심연석 합계·분리');
// 최근 20건
st = one(await q(`select gem_status()`)); ok(st.log.length === 14 && st.log[0].reason === 'buy:pvp_try' && st.log[0].d === -50, '최근 기록 (최대 20) ' + st.log.length);
for (let i = 0; i < 8; i++) await db.exec(`select _gem_add('${U}', 1, 0, 'test', null, '{}')`);
ok(one(await q(`select gem_status()`)).log.length === 20, '최근 기록 20건까지');
// 관리자
ok(!!(await q(`select admin_grant_gem('${U}', 100, 'x')`)).err, '일반 유저는 관리자 지급 불가');
const before = +(await bal()).f + +(await bal()).p; r = await qa(`select admin_grant_gem('${U}', 100, '보상')`); ok(!r.err && one(r).after === before + 100, '관리자 지급 ' + (r.err || ''));
r = await qa(`select admin_gem_ledger('${U}', 10)`); ok(!r.err && one(r).log[0].reason === 'admin' && one(r).log.length === 10, '관리자 원장 보기');
ok(/not enough/.test((await qa(`select admin_grant_gem('${U}', -999999, '회수')`)).err || ''), '잔액보다 많이 회수 불가');
// PvP 시즌 티어 보상 · 10연승에 심연석
await db.exec(`insert into pvp_ratings (user_id, league, mode, season, rating, wins, losses) values ('${U}','open','1v1', _pvp_season() - 7, 1420, 5, 0) on conflict (user_id, league, mode, season) do update set rating = 1420, wins = 5, losses = 0`);
const gb = (await bal()); r = await q(`select pvp_claim_tier('open','1v1')`); const ga = await bal();
ok(!r.err && (+ga.f - +gb.f) === 1000, '심연 시즌 보상 +1000 ' + (r.err || ''));
const tiers = Object.fromEntries((await db.query(`select tier, (reward->>'gem')::int g from pvp_tier_table`)).rows.map(x => [x.tier, x.g]));
ok(tiers.bronze == null && tiers.silver === 50 && tiers.gold === 100 && tiers.platinum === 200 && tiers.diamond === 400 && tiers.abyss === 1000, '티어 심연석 표 50/100/200/400/1000');
ok((await db.query(`select (reward->>'gem')::int g from pvp_streak_table where n = 10`)).rows[0].g === 30, '10연승 +30');
// gem.sql 의 PvP 복사본 = 원본 (원본을 고치면 gem.sql 도 같이)
const fn = (s, n) => { const i = s.indexOf(`create or replace function public.${n}(`); return s.slice(i, s.indexOf(' $$;', i)); };
const G = src('gem.sql');
for (const [f, n] of [['pvp.sql', 'pvp_start'], ['pvp.sql', '_pvp_extra'], ['pvp_tier.sql', '_pvp_grant'], ['pvp_tier.sql', 'pvp_status']]) ok(fn(src(f), n) === fn(G, n), `gem.sql 의 ${n} = ${f}`);
// pvp_tier.sql 다시 실행해도 심연석 보상 유지
await run('pvp_tier.sql'); ok((await db.query(`select (reward->>'gem')::int g from pvp_tier_table where tier='abyss'`)).rows[0].g === 1000, 'pvp_tier.sql 재실행 후에도 유지');
console.log(fails ? `${fails} FAIL` : 'ALL PASS'); process.exit(fails ? 1 : 0);
