// supabase/phaseE_2.sql 검증 (PGlite, 실제 스토리 SQL 위에서). 실행: NODE_PATH=<pglite 설치 경로> node tools/test_player_sql.mjs
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
for (const f of ['story.sql', 'gacha.sql', 'story_server.sql', 'story_gacha.sql', 'story_levels.sql', 'story_merge.sql', 'story_ch2.sql', 'story_cards_1022.sql', 'story_leader_lock.sql', 'story_level_stats.sql', 'story_min_battle.sql', 'admin.sql', 'phaseE_1.sql']) await run(f);
await run('phaseE_2.sql'); await run('phaseE_2.sql');   // 두 번 실행해도 안전 (이중으로 감싸지 않음)
let fails = 0; const ok = (c, m) => { if (!c) { fails++; console.log('FAIL', m); } else console.log('ok  ', m); };
async function as(role, claims, sql) {
  await db.exec(`reset role; select set_config('request.jwt.claims', '${JSON.stringify(claims || {})}', false); set role ${role};`);
  try { return { rows: (await db.query(sql)).rows }; } catch (e) { return { err: e.message }; } finally { await db.exec('reset role'); }
}
const me = { sub: U, email: 'u@x.com' }, q = s => as('authenticated', me, s);
const P = async () => (await q('select public.player_status() s')).rows[0].s;
const age = (sec = 10) => db.exec(`update public.story_progress set data = jsonb_set(data, '{battle,at}', to_jsonb((extract(epoch from now()) - ${sec})::bigint)) where user_id = '${U}'`);
const wrapped = (await db.query(`select count(*) c from pg_proc where proname in ('_story_start_phase_e0','_story_complete_phase_e0')`)).rows[0].c;
ok(+wrapped === 2, '원래 함수 _e0 로 보관 (재실행해도 2개)');
ok(/permission denied/.test((await q(`select public._story_start_phase_e0(1,1)`)).err || ''), '_e0 직접 호출 불가 (행동력 우회 차단)');
ok(/permission denied/.test((await as('anon', {}, 'select public.player_status()')).err || ''), 'anon 은 player_status 불가');
await q(`select public.story_choose_starter('10111')`);
let s = await P();
ok(s.level === 1 && s.stamina === 40 && s.stamina_max === 40 && s.xp_next === 300 && s.cost.story === 6 && s.cost.quest === 0, `처음: Lv1 행동력 40/40 (${JSON.stringify(s).slice(0, 120)})`);
// 시작 → 6 차감
let r = await q('select public.story_start_phase(1,1) d');
ok(r.rows?.[0].d.battle.stamina === 6, 'battle.stamina = 6 기록');
s = await P(); ok(s.stamina === 34 && s.next_regen_secs > 0 && s.next_regen_secs <= 360, `시작 시 6 차감 → 34, 다음 회복 ${s.next_regen_secs}초`);
// 포기 → 반환
r = await q('select public.story_abort_phase() a'); ok(r.rows?.[0].a.refunded === 6 && r.rows[0].a.stamina === 40, '포기 시 전부 반환');
ok((await q('select public.story_abort_phase() a')).rows[0].a.refunded === 0, '전투 없을 때 포기 = 반환 0');
// 미완료 상태에서 새 전투 시작 → 이전 분 반환 후 다시 차감
await q('select public.story_start_phase(1,1)'); await q('select public.story_start_phase(1,1)');
ok((await P()).stamina === 34, '끝내지 않고 다시 시작해도 이중 차감 없음');
// 승리 → 경험치 60 + 첫 클리어 50
await db.exec(`update public.player_state set xp = 200 where user_id='${U}'`);   // 필요 경험치 3배(300): 200 + 110 = 310 → Lv2, 10 남음
await age(); r = await q(`select public.story_complete_phase(1,1,'[]'::jsonb) r`);
const pl = r.rows?.[0]?.r?.player; ok(pl && pl.gained_xp === 110 && pl.level === 2 && pl.xp === 10 && pl.levelups === 1, `첫 클리어 경험치 110 → Lv2 (${JSON.stringify(pl)?.slice(0, 160)})`);
ok(pl.stamina === 34 + 40 && pl.levelup_gold === 200, `레벨업: 행동력 +최대치(40) 초과 보관 = 74, 골드 +200`);
ok(+(await db.query(`select gold from public.player_wallet where user_id='${U}'`)).rows[0].gold === 200, '레벨업 골드가 지갑에 들어감');
ok(r.rows[0].r.first === true && r.rows[0].r.data, '원래 결과(first·data) 유지');
// 재클리어: 60 만
await q('select public.story_start_phase(1,1)'); await age(); r = await q(`select public.story_complete_phase(1,1) r`);
ok(r.rows?.[0].r.player.gained_xp === 60 && r.rows[0].r.player.xp === 70, '재클리어 경험치 60 (2인자 호출도 감싼 함수 경유)');
// 보스도 6
await db.exec(`update public.story_progress set data = jsonb_set(data, '{cleared,1}', '[1,2,3,4]') where user_id='${U}'`);
await q('select public.story_start_phase(1,5)'); s = await P(); ok(s.stamina === 68 - 6 + 0 || s.stamina === 62, `보스 페이즈도 6 (${s.stamina})`);
await q('select public.story_abort_phase()');
// 부족
await db.exec(`update public.player_state set stamina = 5, stamina_at = now() where user_id='${U}'`);
r = await q('select public.story_start_phase(1,1)'); ok(/not enough stamina/.test(r.err || ''), '행동력 5 → 시작 거부');
ok((await P()).stamina === 5 && !(await db.query(`select data->'battle' b from public.story_progress where user_id='${U}'`)).rows[0].b, '거부 시 차감·전투 기록 없음');
// 회복: 13분 전 기준 → +2, 남은 시간 1분대
await db.exec(`update public.player_state set stamina = 5, stamina_at = now() - interval '13 minutes' where user_id='${U}'`);
s = await P(); ok(s.stamina === 7 && s.next_regen_secs > 290 && s.next_regen_secs <= 300, `13분 → +2 회복, 다음 ${s.next_regen_secs}초`);
await db.exec(`update public.player_state set stamina = 5, stamina_at = now() - interval '30 days' where user_id='${U}'`);
s = await P(); ok(s.stamina === s.stamina_max && s.next_regen_secs === 0, '오래 지나도 최대치까지만');
// 기존 유저: 클리어 기록이 있어도 소급 없이 Lv1
await db.exec(`insert into public.story_progress (user_id, data) values ('${V}', '{"starter":"10111","cleared":{"1":[1,2,3,4,5]}}')`);
const sv = (await as('authenticated', { sub: V, email: 'v@x.com' }, 'select public.player_status() s')).rows[0].s;
ok(sv.level === 1 && sv.xp === 0 && sv.stamina === 40 && sv.stamina_max === 40, `소급 없음: Lv1 xp0 행동력 40/40 (${sv.level}/${sv.xp}/${sv.stamina})`);
ok(!(await db.query(`select 1 from public.player_wallet where user_id='${V}'`)).rows.length, '기존 유저 골드 지급 없음');
// 최대 레벨
await db.exec(`update public.player_state set level = 99, xp = 0 where user_id='${U}'`);
await db.query(`select public._player_add_xp('${U}', 999999, true)`); s = await P(); ok(s.level === 100 && s.xp === 0 && s.xp_next === 0, 'Lv100 상한');
ok((await db.query(`select public._player_unlocked('${U}','sweep') a, public._player_unlocked('${V}','skill') b`)).rows.map(x => [x.a, x.b]).join() === 'true,false', '해금 확인 (Lv100 소탕 O, Lv1 기술 X)');
// 관리자
ok(/forbidden/.test((await q(`select public.admin_user_player('${V}')`)).err || ''), '일반 유저 admin_user_player 거부');
ok((await as('authenticated', { sub: ADMIN, email: 'stevejean77@gmail.com' }, `select public.admin_user_player('${V}') p`)).rows?.[0].p.level === 1, '관리자 조회');
ok(/permission denied|policy/.test((await q(`update public.player_state set stamina = 999`)).err || 'x') , '행동력 직접 수정 불가');
// 스토리 SQL 을 다시 실행해 원본이 덮였을 때 → phaseE_2 재실행으로 다시 감쌈
await run('story_merge.sql'); await run('phaseE_2.sql');
await db.exec(`update public.player_state set stamina = 20, stamina_at = now() where user_id='${U}'`);
await q('select public.story_start_phase(1,1)'); ok((await P()).stamina === 14, 'story_merge.sql 재실행 후 phaseE_2 재실행 → 다시 행동력 차감');
await age(); ok((await q(`select public.story_complete_phase(1,1,'[]'::jsonb) r`)).rows?.[0].r.player.gained_xp === 60, '재감싼 완료 함수도 경험치 지급');
console.log(fails ? `\n${fails} FAIL` : '\nALL OK'); process.exit(fails ? 1 : 0);
