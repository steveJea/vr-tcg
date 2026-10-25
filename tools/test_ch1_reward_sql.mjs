// supabase/story_ch1_reward.sql 검증 (PGlite): 챕터 1 페이즈별 고정 보상 카드, 중복 지급, 재클리어 없음
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
await run('story_ch1_reward.sql'); await run('story_ch1_reward.sql');   // 두 번 실행해도 안전
let fails = 0; const ok = (c, m) => { if (!c) { fails++; console.log('FAIL', m); } else console.log('ok  ', m); };
async function as(role, claims, sql) {
  await db.exec(`reset role; select set_config('request.jwt.claims', '${JSON.stringify(claims || {})}', false); set role ${role};`);
  try { return { rows: (await db.query(sql)).rows }; } catch (e) { return { err: e.message }; } finally { await db.exec('reset role'); }
}
const me = { sub: U, email: 'u@x.com' }, q = s => as('authenticated', me, s);
const age = () => db.exec(`update public.story_progress set data = jsonb_set(data, '{battle,at}', to_jsonb((extract(epoch from now()) - 60)::bigint)) where user_id = '${U}'`);
const W = ['2000800171', '2001700341', '2000400085', '2001100231', '2000400086'];
const cfg = (await db.query(`select phase, reward_card from public.story_phase_config where chapter = 1 order by phase`)).rows;
ok(cfg.map(r => r.reward_card).join() === W.join(), '챕터 1 페이즈 1~5 보상 카드 설정');
ok(/permission denied/.test((await q(`select public._story_complete_phase_e0(1,1,'[]'::jsonb)`)).err || ''), '_e0 직접 호출 불가');
await q(`select public.story_choose_starter('2000600126')`);
await db.exec(`update public.player_state set stamina = 999 where user_id='${U}'`);
// 1-1 예유진을 미리 보유 → 한 장 더
await db.exec(`update public.story_progress set data = jsonb_set(data, '{owned}', coalesce(data->'owned','[]'::jsonb) || '[{"uid":"pre1","id":"2000800171","level":3,"exp":0,"totalExp":0,"boost":{}}]') where user_id='${U}'`);
const owned = async () => (await db.query(`select data->'owned' o from public.story_progress where user_id='${U}'`)).rows[0].o;
for (let ph = 1; ph <= 5; ph++) {
  if (ph === 5) await db.exec(`update public.story_progress set data = jsonb_set(data, '{cleared,1}', '[1,2,3,4]') where user_id='${U}'`);
  const s = await q(`select public.story_start_phase(1,${ph}) d`); if (s.err) console.log('start err', s.err);
  await age(); const r = await q(`select public.story_complete_phase(1,${ph},'[{"uid":"pre1","id":"2000800171","kills":0}]'::jsonb) r`);
  if (r.err) console.log('ERR', r.err);
  const x = r.rows?.[0]?.r; ok(x?.first === true && x.reward_id === W[ph - 1] && x.reward_uid, `1-${ph} 첫 클리어 보상 = ${W[ph - 1]}`);
  if (ph === 1) { const o = await owned(); ok(o.filter(c => c.id === W[0]).length === 2, '이미 보유한 예유진 → 한 장 더 (2장)');
    ok(x.exp.some(e => e.uid === 'pre1' && e.exp > 0), '기존 사본 경험치는 그대로 받음'); }
}
const s = await q(`select public.story_start_phase(1,1) d`); await age(); const r = await q(`select public.story_complete_phase(1,1,'[]'::jsonb) r`);
ok(r.rows?.[0]?.r?.first === false && !r.rows[0].r.reward_id, '재클리어: 보상 카드 없음');
const o = await owned(); ok(W.every(id => o.some(c => c.id === id)), '5장 모두 보유');
console.log(fails ? `${fails} FAILED` : 'ALL PASS'); process.exit(fails ? 1 : 0);
