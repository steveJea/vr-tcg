// supabase/pvp_tier.sql 검증 (PGlite): 티어·연승 보너스·시즌 티어 보상·심연 칭호
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
insert into auth.users (id, email, email_confirmed_at) values ('${U}','u@x.com',now()),('${V}','v@x.com',now()),('${ADMIN}','stevejean77@gmail.com',now());`);
const run = f => db.exec(readFileSync(new URL('../supabase/' + f, import.meta.url), 'utf8'));
for (const f of ['story.sql', 'gacha.sql', 'story_server.sql', 'story_gacha.sql', 'story_levels.sql', 'story_merge.sql', 'story_ch2.sql', 'story_cards_1022.sql', 'story_leader_lock.sql', 'story_level_stats.sql', 'story_min_battle.sql', 'admin.sql', 'phaseE_1.sql', 'phaseE_2.sql']) await run(f);
await run("pvp.sql"); await run("pvp_tier.sql"); await run("pvp_tier.sql");
let fails = 0; const ok = (c, m) => { if (!c) { fails++; console.log('FAIL', m); } else console.log('ok  ', m); };
async function as(role, claims, sql) {
  await db.exec(`reset role; select set_config('request.jwt.claims', '${JSON.stringify(claims || {})}', false); set role ${role};`);
  try { return { rows: (await db.query(sql)).rows }; } catch (e) { return { err: e.message }; } finally { await db.exec('reset role'); }
}
const me = { sub: U, email: 'u@x.com' }, q = s => as('authenticated', me, s);
const W = '00000000-0000-0000-0000-000000000004';
await db.exec(`insert into auth.users (id, email, email_confirmed_at) values ('${W}','w@x.com',now()); insert into profiles (id, nickname) values ('${U}','유','),('${V}','브이'),('${W}','더블');`.replace("'유','", "'유'"));
const owned = [{ uid: 'a', id: '10370', level: 5 }, { uid: 'b', id: '10368' }, { uid: 'c', id: '10351' }, { uid: 'd', id: '10370' }, { uid: 'mr', id: '10060' }];
for (const x of [U, V]) await db.exec(`insert into story_progress (user_id, data) values ('${x}', '${JSON.stringify({ owned })}'::jsonb) on conflict (user_id) do update set data = excluded.data`);
const as2 = (id, s) => as('authenticated', { sub: id, email: 'x' }, s);
const one = r => r.rows?.[0] && Object.values(r.rows[0])[0];
const gold = async id => +((await db.query(`select gold from player_wallet where user_id='${id}'`)).rows[0]?.gold || 0);
let r = await q(`select pvp_set_deck('open','1v1',0,'["a","b"]')`); ok(!r.err, '덱 등록 ' + (r.err || ''));
r = await q(`select pvp_status('open','1v1')`); let st = one(r);
ok(!r.err && st.tier === 'silver' && st.streak === 0 && st.tiers.length === 6 && st.streaks.length === 3 && st.pending === null, '상태: 티어·연승·표 ' + (r.err || JSON.stringify({ t: st.tier, s: st.streak })));
// 티어 경계
const tierOf = async n => one(await db.query(`select _pvp_tier(${n}) t`).then(x => ({ rows: x.rows })));
ok(await tierOf(949) === 'bronze' && await tierOf(950) === 'silver' && await tierOf(1050) === 'gold' && await tierOf(1150) === 'platinum' && await tierOf(1250) === 'diamond' && await tierOf(1400) === 'abyss', '티어 경계 950/1050/1150/1250/1400');
// 연승: 승 3 → 보너스(골드 300), 승 5 → 골드 600+영혼 5
const win = async () => { const s = one(await q(`select pvp_start('open','1v1')`)); return one(await q(`select pvp_report(${s.id}, 1, 0)`)); };
const lose = async () => { const s = one(await q(`select pvp_start('open','1v1')`)); return one(await q(`select pvp_report(${s.id}, 0, 1)`)); };
let g0 = await gold(U), x;
await win(); x = await win(); ok(x.streak === 2 && x.streak_reward === null, '2연승: 보너스 없음');
x = await win(); ok(x.streak === 3 && x.streak_reward?.gold === 300 && await gold(U) === g0 + 300, '3연승: 골드 300 ' + JSON.stringify(x));
x = await win(); x = await win(); ok(x.streak === 5 && x.streak_reward?.soul === 5 && await gold(U) === g0 + 900, '5연승: 골드 600 + 영혼 5');
ok(one(await q(`select pvp_status('open','1v1')`)).streak === 5, '허브 연승 5');
x = await lose(); ok(x.streak === 0 && one(await q(`select pvp_status('open','1v1')`)).streak === 0, '패배 → 연승 0');
// 미보고(1시간 지남) = 패배로 연승 끊김
await win(); const s2 = one(await q(`select pvp_start('open','1v1')`)); await db.exec(`update pvp_attempts set created_at = now() - interval '2 hours' where id = ${s2.id}`);
await db.exec(`delete from pvp_attempts where day = _pvp_day() and id < ${s2.id} - 3`);   // 하루 10회 제한 피하기
x = await win(); ok(x.streak === 1, '미보고 판 = 패배 → 연승 다시 1 ' + JSON.stringify(x));
// 시즌 티어 보상
ok(/not eligible/.test((await q(`select pvp_claim_tier('open','1v1')`)).err || ''), '지난 시즌 기록 없으면 불가');
await db.exec(`update pvp_ratings set season = season - 7, rating = 1420 where user_id = '${U}'`);
st = one(await q(`select pvp_status('open','1v1')`)); ok(st.pending?.tier === 'abyss', '미수령 티어 보상 표시 ' + JSON.stringify(st.pending));
const t0 = +((await db.query(`select tickets from story_gacha where user_id='${U}'`)).rows[0]?.tickets || 0); g0 = await gold(U);
r = await q(`select pvp_claim_tier('open','1v1')`); ok(!r.err && one(r).tier === 'abyss' && one(r).reward.gold === 4000, '심연 보상 ' + (r.err || ''));
ok(await gold(U) === g0 + 4000 && +(await db.query(`select tickets from story_gacha where user_id='${U}'`)).rows[0].tickets === t0 + 20, '골드 4000 · 소환권 20');
ok((await db.query(`select count(*)::int n from pvp_titles where user_id='${U}' and title='abyss'`)).rows[0].n === 1, '심연 칭호');
ok(/already/.test((await q(`select pvp_claim_tier('open','1v1')`)).err || ''), '티어 보상 1회');
st = one(await q(`select pvp_status('open','1v1')`)); ok(st.abyss === true && st.pending === null, '칭호 표시 · 미수령 없음');
ok(!!(await as('anon', {}, `select pvp_claim_tier('open','1v1')`)).err, 'anon 불가');
ok(!!(await q(`insert into pvp_tier_claims values ('${U}','open','1v1',current_date,'abyss',0,'{}')`)).err, '클라이언트 직접 쓰기 불가');
ok(!!(await q(`select _pvp_grant('${U}','{"gold":99999}','x','open','1v1',current_date)`)).err, '내부 지급 함수 호출 불가');
r = await as('anon', {}, `select pvp_rankings('open','1v1', _pvp_season() - 7)`); ok(!r.err && one(r).top[0].tier === 'abyss' && one(r).top[0].abyss === true, '랭킹: 티어·칭호 ' + (r.err || ''));
// 클라이언트 티어 경계 = 서버 표
{ const js = readFileSync(new URL('../js/pvp.js', import.meta.url), 'utf8'); const cli = [...js.matchAll(/k: '(\w+)', label: '[^']+', min: (\d+)/g)].map(m => m[1] + ':' + m[2]).join(',');
  const srv = (await db.query(`select string_agg(tier || ':' || min_rating, ',' order by ord) s from pvp_tier_table`)).rows[0].s; ok(cli === srv, '클라이언트 티어 경계 = 서버 ' + cli); }
console.log(fails ? `${fails} FAIL` : 'ALL PASS'); process.exit(fails ? 1 : 0);
