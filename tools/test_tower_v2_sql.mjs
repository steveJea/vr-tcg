// supabase/tower_v2.sql 검증 (탑 6종) (PGlite, 실제 스토리·퀘스트 SQL 위에서). 실행: NODE_PATH=<pglite 설치 경로> node tools/test_tower_v2_sql.mjs
import { readFileSync } from 'fs';
import { createRequire } from 'module';
const require = createRequire(import.meta.url);
let PGlite; try { ({ PGlite } = require('@electric-sql/pglite')); } catch { console.log('SKIP: @electric-sql/pglite 없음'); process.exit(0); }
const db = new PGlite();
const U = '00000000-0000-0000-0000-000000000002', M = '00000000-0000-0000-0000-000000000004';
await db.exec(`create role anon nologin; create role authenticated nologin; create schema auth;
create table auth.users (id uuid primary key, email text, email_confirmed_at timestamptz, created_at timestamptz default now(), last_sign_in_at timestamptz, raw_user_meta_data jsonb default '{}');
create function auth.jwt() returns jsonb language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $$;
create function auth.uid() returns uuid language sql stable as $$ select nullif(auth.jwt()->>'sub', '')::uuid $$;
grant usage on schema auth to anon, authenticated; grant execute on all functions in schema auth to anon, authenticated; grant usage on schema public to anon, authenticated;
create table public.profiles (id uuid primary key, nickname text);
create table public.matches (id bigint generated always as identity primary key, user_id uuid, result text, reason text, turns int, damage int, mvp_name text, created_at timestamptz default now());
create table public.gallery (user_id uuid, card_id text, count int, mvp_count int);
insert into auth.users (id, email, email_confirmed_at) values ('${U}','u@x.com',now()),('${M}','m@x.com',now());`);
const run = f => db.exec(readFileSync(new URL('../supabase/' + f, import.meta.url), 'utf8'));
for (const f of ['story.sql', 'gacha.sql', 'story_server.sql', 'story_gacha.sql', 'story_levels.sql', 'story_level_stats.sql', 'story_merge.sql', 'story_ch2.sql', 'story_cards_1022.sql', 'story_leader_lock.sql', 'story_min_battle.sql', 'quest.sql', 'admin.sql', 'phaseE_1.sql', 'phaseE_2.sql', 'phaseE_3.sql']) await run(f);
await run('phaseE_4.sql'); await run('phaseE_5.sql'); await run('quest_sweep.sql');
// 리셋 전 기존 기록: U 는 시련의 탑 25층까지 깸
await db.exec(`insert into public.quest_progress (user_id, best_floor, clears, rewards) values ('${U}', 25, 30, '{"tickets":10}')`);
await run('tower_v2.sql'); await run('tower_v2.sql');
let fails = 0; const ok = (c, m) => { if (!c) { fails++; console.log('FAIL', m); } else console.log('ok  ', m); };
async function as(role, claims, sql) {
  await db.exec(`reset role; select set_config('request.jwt.claims', '${JSON.stringify(claims || {})}', false); set role ${role};`);
  try { return { rows: (await db.query(sql)).rows }; } catch (e) { return { err: e.message }; } finally { await db.exec('reset role'); }
}
const me = { sub: U, email: 'u@x.com' }, q = s => as('authenticated', me, s);
const W = async () => (await db.query(`select gold::int, blood::int, shard::int, soul::int from public.player_wallet where user_id='${U}'`)).rows[0] || { gold: 0, blood: 0, shard: 0, soul: 0 };
const give = o => db.query(`select public._wallet_add('${U}', '${JSON.stringify(o)}', 'test')`);



const TP = async t => (await db.query(`select * from public.tower_progress where user_id='${U}' and tower='${t}'`)).rows[0];
const back = (t, s) => db.exec(`update public.tower_progress set battle = jsonb_set(battle, '{at}', to_jsonb((battle->>'at')::numeric - ${s})) where user_id='${U}' and tower='${t}'`);
const DOW = d => db.exec(`create or replace function public._tower_dow() returns int language sql stable as $$ select ${d} $$`);
const LV = l => db.exec(`insert into public.player_state (user_id, level) values ('${U}', ${l}) on conflict (user_id) do update set level = ${l}`);
const T = n => JSON.stringify({ turns: Array(n).fill(7) });
const win = async (t, f) => { const s = await q(`select public.tower_start('${t}', ${f}) r`); if (s.err) return s; await back(t, 10); return q(`select public.tower_complete('${t}', ${f}, '{"turns":5}') r`); };
const tk = async () => (await db.query(`select tickets from public.story_gacha where user_id='${U}'`)).rows[0]?.tickets | 0;

// 리셋·이전
let p = await TP('normal'); ok(p && p.best_floor === 0 && p.paid_floor === 25 && p.clears === 30 && p.rewards.tickets === 10, `리셋: 0층, paid 25 유지 (재실행해도 1회) ${JSON.stringify(p)}`);
ok(/permission denied/.test((await as('anon', {}, 'select public.tower_status()')).err || ''), 'anon 불가');
// 레벨 제한
await DOW(1); await LV(4);
ok(/level too low/.test((await q(`select public.tower_start('normal', 1)`)).err || ''), 'normal Lv5 미만 불가');
await LV(29); ok(/level too low/.test((await q(`select public.tower_start('wind', 1)`)).err || ''), 'wind Lv30 미만 불가');
await LV(49); ok(!(await q(`select public.tower_start('wind', 1)`)).err, 'wind Lv30 이상 가능'); await DOW(4); ok(/level too low/.test((await q(`select public.tower_start('light', 1)`)).err || ''), 'light Lv50 미만 불가'); await DOW(1);
await LV(60);
// 요일 (월=1)
ok(/closed/.test((await q(`select public.tower_start('ice', 1)`)).err || '') && /closed/.test((await q(`select public.tower_start('dark', 1)`)).err || ''), '월요일: ice·dark 닫힘');
await DOW(5); ok(!(await q(`select public.tower_start('dark', 1)`)).err && /closed/.test((await q(`select public.tower_start('wind', 1)`)).err || ''), '금요일: dark 열림 · wind 닫힘');
await DOW(7); ok((await Promise.all(['normal','wind','ice','fire','light','dark'].map(t => q(`select public.tower_start('${t}', 1)`)))).every(r => !r.err), '일요일: 6종 모두 열림');
ok(/invalid tower/.test((await q(`select public.tower_start('water', 1)`)).err || ''), '없는 탑 거부');
ok(/invalid floor/.test((await q(`select public.tower_start('normal', 351)`)).err || ''), '351층 거부');
// 첫 클리어: paid_floor 이하는 보상 없음 (이중 지급 방지)
let t0 = await tk(), w0 = await W();
let r = (await win('normal', 1)).rows?.[0].r; ok(r?.first && !r.paid && (await W()).gold === w0.gold, `normal 1층: 진행은 오르지만 보상 없음 (이미 받음) ${JSON.stringify(r)}`);
ok(/floor locked/.test((await q(`select public.tower_start('normal', 3)`)).err || ''), '건너뛰기 불가');
// 속성 탑: 골드·피·조각만, 소환권 없음
await DOW(6);
for (let f = 1; f <= 9; f++) { const x = await win('fire', f); if (x.err) { ok(false, `fire ${f}: ${x.err}`); break; } }
w0 = await W(); t0 = await tk();
r = (await win('fire', 10)).rows?.[0].r; const w1 = await W();
ok(r?.paid && w1.gold - w0.gold === 100 && w1.blood - w0.blood === 50 && (await tk()) === t0 && !r.reward.tickets, `fire 10층: 골드 100 · 피 50 · 소환권 없음 ${JSON.stringify(r)}`);
// 일일 제한 10 (fire 오늘 10층 이김)
ok(/daily limit/.test((await q(`select public.tower_start('fire', 11)`)).err || ''), 'fire 하루 10층 제한');
let st = (await q(`select public.tower_status() s`)).rows?.[0].s; ok(st?.towers.fire.today === 10 && st.towers.fire.daily === 10 && st.towers.normal.daily === 30 && st.towers.fire.open_today && st.towers.wind.min_level === 30, `상태 ${JSON.stringify(st?.towers.fire)}`);
// 날짜 바뀌면 리셋
await db.exec(`update public.tower_progress set day = day - 1 where user_id='${U}' and tower='fire'`);
ok(!(await q(`select public.tower_start('fire', 11)`)).err, '다음 날 fire 다시 가능');
// 소탕: 일일 제한 포함, 탑별
await db.exec(`update public.tower_progress set day_floors = 25, best_floor = 2 where user_id='${U}' and tower='normal'`);
let s = (await q(`select public.tower_sweep_start('normal') s`)).rows?.[0].s; ok(s?.from === 3 && s.last === 7, `normal 소탕: 남은 5층만 (3~7) ${JSON.stringify(s)}`);
await back('normal', 30);
ok(/invalid range/.test((await q(`select public.tower_sweep_complete('normal', 8, '${T(6)}')`)).err || ''), '일일 제한 넘는 소탕 거부');
r = (await q(`select public.tower_sweep_complete('normal', 7, '${T(5)}') r`)).rows?.[0].r; p = await TP('normal');
ok(r?.cleared === 5 && p.best_floor === 7 && p.day_floors === 30 && p.paid_floor === 25 && Object.keys(r.total).length === 0, `소탕 5층 · paid 25 이하라 보상 없음 ${JSON.stringify(r?.total)}`);
ok(/daily limit/.test((await q(`select public.tower_sweep_start('normal')`)).err || ''), '오늘 30층 다 쓰면 소탕 불가');
// 보상 이어서: paid 초과부터 지급
await db.exec(`update public.tower_progress set day_floors = 0, best_floor = 25 where user_id='${U}' and tower='normal'`);
w0 = await W(); s = (await q(`select public.tower_sweep_start('normal') s`)).rows?.[0].s; await back('normal', 30);
r = (await q(`select public.tower_sweep_complete('normal', 29, '${T(4)}') r`)).rows?.[0].r;
ok(r?.cleared === 4 && r.total.gold === (50+5*26)+(50+5*27)+(50+5*28)+(50+5*29) && (await TP('normal')).paid_floor === 29, `26~29층 보상 지급 ${JSON.stringify(r?.total)}`);
// 예전 RPC = normal
let qs = (await q('select public.quest_status() s')).rows?.[0].s; ok(qs?.best_floor === 29 && qs.max_floor === 350, `quest_status → normal ${JSON.stringify(qs)}`);
ok((await TP('wind')).best_floor === 0 && (await TP('fire')).best_floor === 10, '탑마다 따로 진행');
console.log(fails ? `${fails} FAIL` : 'ALL OK'); process.exit(fails ? 1 : 0);
