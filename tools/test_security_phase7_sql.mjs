// Offline PGlite. Real handler + SQL. No network, keys, or production database.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { PGlite } from '@electric-sql/pglite';
import { buildSql, INSTALL_ACK } from './build_staging_sql.mjs';
import { ENGINE_VERSION as SWEEP_HASH } from '../supabase/functions/_shared/sweep-engine-v6.mjs';
import { ENGINE_VERSION as ARCADE_HASH } from '../supabase/functions/_shared/arcade-engine-v5.mjs';
import { ENGINE_VERSION, verifyDirect } from '../supabase/functions/story-direct-verify-v7/engine.mjs';
import { verifySweep } from '../supabase/functions/_shared/sweep-engine-v6.mjs';
import { createHandler } from '../supabase/functions/story-direct-verify-v7/handler.mjs';
import { dashboardHandler } from './load_phase7_dashboard.mjs';

assert.equal(SWEEP_HASH, '1dbdb45994799cdcf3db14bd6eb44689d35678a733774caffcfd9867df85685c');
assert.equal(ARCADE_HASH, 'e792c491ffafe19d047aa6f58db1920e5767e4059e14816611dd38d473871161');
assert.equal(ENGINE_VERSION, SWEEP_HASH);

const probe = { mode: 'tower', target: 'wind:1', seed: 3, snapshot: { cards: [{ id: '10111', uid: 'u1', level: 80 }], leader: 'u1' } };
for (const tower of ['wind', 'ice', 'fire', 'light', 'dark', 'normal']) {
  const result = verifyDirect({ ...probe, target: `${tower}:3` }, 'claim');
  assert.equal(typeof result.win, 'boolean');
  assert.equal(result.my_turns, Math.ceil(result.turns / 2));
}
assert.throws(() => verifyDirect({ ...probe, target: 'normal:10' }, 'claim'), /boss floor/);
assert.equal(verifyDirect({ mode: 'story', target: '12:14', seed: 1, snapshot: { stage: { loseClears: true }, cards: [] } }, 'loss').scripted, 'loseClears');
assert.equal(verifyDirect({ mode: 'story', target: '12:14', seed: 1, snapshot: { stage: { loseClears: true }, cards: [] } }, 'giveup').reason, 'giveup');
assert.throws(() => verifyDirect({ mode: 'story', target: '1:1', seed: 1, snapshot: { stage: { type: 'normal', enemies: { count: 1, rank: [0, 30] } }, cards: probe.snapshot.cards } }, 'claim'), /unsupported battle/);

const rd = p => readFile(new URL('../' + p, import.meta.url), 'utf8');
const db = new PGlite();
const me = '11111111-1111-4111-8111-111111111111';
const other = '22222222-2222-4222-8222-222222222222';
const req = n => `bbbbbbbb-bbbb-4bbb-8bbb-${String(n).padStart(12, '0')}`;
const q = async (s, p = []) => (await db.query(s, p)).rows;
const val = async (s, p = []) => (await q(s, p))[0]?.v;
async function as(uid, fn, role = 'authenticated') {
  await q(`select set_config('request.jwt.claim.sub',$1,false)`, [uid || '']);
  await db.exec(`set role ${role}`);
  try { return await fn(); } finally { await db.exec('reset role'); }
}
const rpc = (s, p = [], uid = me) => as(uid, () => val(s, p));
const reject = (s, p = [], pat = /permission denied/, uid = me) => as(uid, () => assert.rejects(q(s, p), pat));
const start = (m, t, p, r, uid = me) => rpc(`select battle_session_start_v2($1,$2,$3::jsonb,$4) v`, [m, t, JSON.stringify(p), r], uid);
const finish = (id, report, uid = me) => rpc(`select battle_session_finish_v2($1::uuid,$2::jsonb) v`, [id, JSON.stringify(report)], uid);
const age = async id => {
  await q(`update battle_sessions_v2 set issued_at=clock_timestamp()-interval '10 seconds' where id=$1`, [id]);
  await q(`update story_progress set data=jsonb_set(data,'{battle,at}',to_jsonb((extract(epoch from clock_timestamp())-10)::bigint)) where data->'battle'->>'session'=$1`, [id]);
};
const report = { win: true, reason: 'wipe', turns: 4, my_turns: 2, mana: null, skills: 0, cards: [] };
const env = {
  SUPABASE_URL: 'https://cuyqchmdcnsgzkwyclji.supabase.co',
  SUPABASE_PUBLISHABLE_KEYS: JSON.stringify({ default: 'sb_publishable_fixture' }),
  SUPABASE_SECRET_KEYS: JSON.stringify({ default: 'sb_secret_fixture' }),
};
const signatures = {
  battle_direct_session_v7: ['p_uid', 'p_id'],
  battle_direct_settle_v7: ['p_uid', 'p_id', 'p_engine_hash', 'p_result', 'p_client'],
};
const fetcher = async (url, opts) => {
  assert.ok(url.startsWith(env.SUPABASE_URL));
  if (url.endsWith('/auth/v1/user')) {
    const id = opts.headers.authorization === 'Bearer fixture-me' ? me : opts.headers.authorization === 'Bearer fixture-other' ? other : null;
    return Response.json(id ? { id } : { error: 'invalid JWT' }, { status: id ? 200 : 401 });
  }
  const name = url.split('/').at(-1);
  const args = JSON.parse(opts.body);
  assert.ok(signatures[name], name);
  assert.equal(opts.headers.apikey, 'sb_secret_fixture');
  assert.equal(opts.headers.authorization, undefined);
  const ps = signatures[name].map(k => typeof args[k] === 'object' && args[k] !== null ? JSON.stringify(args[k]) : args[k]);
  try {
    return Response.json(await as(null, () => val(`select public.${name}(${ps.map((_, i) => '$' + (i + 1)).join(',')}) v`, ps), 'service_role'));
  } catch (e) {
    return Response.json({ message: e.message }, { status: 400 });
  }
};
const factory = process.argv.includes('--dashboard') ? dashboardHandler : createHandler;
const handler = factory(env, fetcher);
const http = async (body, token = 'fixture-me') => {
  const r = await handler(new Request('https://example.invalid/story-direct-verify-v7', {
    method: 'POST', headers: { 'content-type': 'application/json', authorization: 'Bearer ' + token }, body: JSON.stringify(body),
  }));
  const data = await r.json();
  assert.match(data.trace || '', /^[0-9a-f-]{36}$/);
  delete data.trace;
  return { status: r.status, data };
};
const claimBody = (id, extra = {}) => ({ op: 'direct', id, version: ENGINE_VERSION, outcome: 'claim', mana: null, cards: [], ...extra });
async function unlockBefore(chapter, phase) {
  await q(`with phases as (
     select chapter, phase from story_phase_config
     where chapter < $2 or (chapter = $2 and phase < $3)
   ), ins as (
     insert into battle_sessions_v2(user_id, request_id, mode, target, party, seed, snapshot, status)
     select $1, gen_random_uuid(), 'story', chapter::text || ':' || phase::text, '[]'::jsonb, 1, '{}'::jsonb, 'settled' from phases
     returning id, target
   )
   insert into battle_clear_receipts_v2(user_id, mode, target, session_id, stars)
   select $1, 'story', target, id, 1 from ins
   on conflict do nothing`, [me, chapter, phase]);
  await q(`update story_progress set data=jsonb_set(data,'{cleared}',(
     select coalesce(jsonb_object_agg(chapter::text, phases), '{}'::jsonb) from (
       select c.chapter, jsonb_agg(c.phase order by c.phase) phases from story_phase_config c
       where c.chapter < $2 or (c.chapter=$2 and c.phase < $3) group by c.chapter) s))
     where user_id=$1`, [me, chapter, phase]);
}
const gold = () => val(`select gold::int v from player_wallet where user_id=$1`, [me]);
const storyReceipts = target => val(`select count(*)::int v from battle_clear_receipts_v2 where user_id=$1 and mode='story' and target=$2`, [me, target]);
const towerReceipts = () => val(`select count(*)::int v from battle_clear_receipts_v2 where user_id=$1 and mode='tower'`, [me]);

try {
  await db.exec(`create role anon; create role authenticated; create role service_role; create schema auth;
    create table auth.users(id uuid primary key, email text, raw_user_meta_data jsonb default '{}', raw_app_meta_data jsonb default '{}', created_at timestamptz default now(), last_sign_in_at timestamptz, email_confirmed_at timestamptz);
    create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
    create function auth.jwt() returns jsonb language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $$;
    grant usage on schema auth, public to anon, authenticated, service_role;
    alter default privileges in schema public grant all on tables to anon, authenticated;
    alter default privileges in schema public grant all on sequences to anon, authenticated;
    alter default privileges in schema public grant execute on functions to anon, authenticated, service_role;`);
  await db.exec((await buildSql()).replace(`confirmed_ref text := '${INSTALL_ACK}'`, "confirmed_ref text := 'abcdefghijklmnopqrst'"));
  const system = await val('select system_identifier::text v from pg_control_system()');
  const migration = await rd('supabase/security_phase7_direct_replay.sql');
  await assert.rejects(db.exec(migration), /STOP: phase7 only/);
  await db.exec('rollback');
  await q(`insert into auth.users(id,email) values($1,'one@example.invalid'),($2,'two@example.invalid')`, [me, other]);
  await q(`insert into player_wallet(user_id,gold) values($1,100),($2,100)`, [me, other]);
  await q(`insert into story_gacha(user_id,last_draw,tickets) values($1,_gem_day()-1,0),($2,_gem_day()-1,0)`, [me, other]);
  const owned = await val(`select _story_new_card('10111') v`);
  const heroine = await val(`select _story_new_card('10229') v`);
  const ownedOther = await val(`select _story_new_card('10224') v`);
  await q(`insert into story_progress(user_id,data) values($1,$2::jsonb),($3,$4::jsonb)`, [
    me, JSON.stringify({ owned: [owned, heroine], starter: '10111', leader: owned.uid }),
    other, JSON.stringify({ owned: [ownedOther], starter: '10224', leader: ownedOther.uid }),
  ]);
  await q(`insert into player_state(user_id,level,stamina) values($1,50,200),($2,50,200)`, [me, other]);
  const sql = migration.replaceAll("'7703759698107299042'", `'${system}'`);
  await db.exec(sql);
  await db.exec(sql);
  assert.equal(await val('select enabled v from battle_replay_policy_v7'), false);
  assert.equal(await val('select engine_hash v from battle_replay_policy_v7'), SWEEP_HASH);
  assert.equal(await val(`select enabled v from battle_replay_policy_v6`), false);
  await reject(`select battle_direct_settle_v7($1,$2,$3,$4::jsonb,$5::jsonb)`, [me, req(1), SWEEP_HASH, '{"win":false,"reason":"wipe","turns":2,"my_turns":1}', '{"mana":null,"cards":[]}']);
  await reject(`select _phase7_prev_finish_v2($1,$2::jsonb)`, [req(1), '{}']);
  const phase6 = await rd('supabase/security_phase6_story_tower.sql');
  assert.match(phase6, /sweep replay required/);
  assert.doesNotMatch(phase6, /direct replay required/);
  assert.match(phase6, /battle_sweep_settle_v6/);

  const oldTower = await start('tower', 'normal:1', [owned.uid], req(10));
  await age(oldTower.session);
  const oldWin = await finish(oldTower.session, report);
  assert.equal(oldWin.validation, 'plausibility-v3');
  assert.equal(oldWin.cleared, true);
  const beforeStoryGold = await gold();
  await q(`update battle_replay_policy_v7 set enabled=true where singleton`);
  await unlockBefore(1, 1);

  const forgedStory = await start('story', '1:1', [owned.uid, 'guest:10112'], req(20));
  await reject(`select battle_session_finish_v2($1,$2::jsonb)`, [forgedStory.session, JSON.stringify({ ...report, mana: forgedStory.snapshot.mana, cards: [] })], /direct replay required/);
  assert.equal(await storyReceipts('1:1'), 0);
  assert.equal(await gold(), beforeStoryGold);
  await q(`update battle_sessions_v2 set snapshot=jsonb_set(snapshot,'{stage,enemies,boost}','{"10210":{"HP":9000000,"ATK":1,"DEF":1}}'::jsonb) where id=$1`, [forgedStory.session]);
  const forgedStoryHttp = await http(claimBody(forgedStory.session, { mana: Math.trunc(forgedStory.snapshot.mana) }));
  assert.equal(forgedStoryHttp.status, 200, JSON.stringify(forgedStoryHttp));
  assert.equal(forgedStoryHttp.data.validation, 'replay-v7');
  assert.equal(forgedStoryHttp.data.cleared, false);
  assert.equal(forgedStoryHttp.data.win, false);
  assert.equal(await storyReceipts('1:1'), 0);
  assert.equal(await gold(), beforeStoryGold);

  const legitStory = await start('story', '1:1', [owned.uid, 'guest:10112'], req(21));
  await q(`update battle_sessions_v2 set snapshot=jsonb_set(jsonb_set(snapshot,'{cards,0,level}','80'::jsonb),'{cards,1,level}','80'::jsonb) where id=$1`, [legitStory.session]);
  let winningStory = null;
  for (let seed = 1; seed <= 20 && !winningStory; seed++) {
    const loaded = await as(null, () => val(`select battle_direct_session_v7($1,$2) v`, [me, legitStory.session]), 'service_role');
    loaded.seed = seed;
    const result = verifyDirect(loaded, 'claim');
    if (result.win) winningStory = { seed, result };
  }
  assert.ok(winningStory, 'expected a deterministic story win');
  await q(`update battle_sessions_v2 set seed=$2 where id=$1`, [legitStory.session, winningStory.seed]);
  await age(legitStory.session);
  const storyCall = claimBody(legitStory.session, { mana: Math.trunc(legitStory.snapshot.mana), cards: [{ uid: owned.uid, kills: 1, blocks: 0 }] });
  assert.equal((await http({ ...storyCall, win: true })).status, 400);
  const storyWin = await http(storyCall);
  assert.equal(storyWin.status, 200, JSON.stringify(storyWin));
  assert.equal(storyWin.data.validation, 'replay-v7');
  assert.equal(storyWin.data.cleared, true);
  assert.equal(storyWin.data.win, true);
  assert.ok(storyWin.data.stars >= 1);
  const storyGold = await gold();
  const storyAgain = await http(storyCall);
  assert.deepEqual(storyAgain.data, storyWin.data);
  assert.equal(await gold(), storyGold);
  assert.equal(await storyReceipts('1:1'), 1);

  await q(`update tower_progress set best_floor=38 where user_id=$1 and tower='normal'`, [me]);
  await q(`update battle_legacy_access_v2 set tower_best=jsonb_set(coalesce(tower_best,'{}'),'{normal}','38'::jsonb) where user_id=$1`, [me]);
  const forgedTower = await start('tower', 'normal:39', [owned.uid], req(30));
  const towerGold = await gold();
  const towerReceiptsBefore = await towerReceipts();
  await reject(`select battle_session_finish_v2($1,$2::jsonb)`, [forgedTower.session, JSON.stringify(report)], /direct replay required/);
  assert.equal(await gold(), towerGold);
  assert.equal(await towerReceipts(), towerReceiptsBefore);
  const forgedTowerHttp = await http(claimBody(forgedTower.session));
  assert.equal(forgedTowerHttp.status, 200, JSON.stringify(forgedTowerHttp));
  assert.equal(forgedTowerHttp.data.validation, 'replay-v7');
  assert.equal(forgedTowerHttp.data.win, false);
  assert.equal(forgedTowerHttp.data.cleared, false);
  assert.equal(await val(`select best_floor::int v from tower_progress where user_id=$1 and tower='normal'`, [me]), 38);
  assert.equal(await gold(), towerGold);
  assert.equal(await towerReceipts(), towerReceiptsBefore);

  const legitTower = await start('tower', 'normal:2', [owned.uid], req(31));
  await q(`update battle_sessions_v2 set snapshot=jsonb_set(snapshot,'{cards,0,level}','80'::jsonb) where id=$1`, [legitTower.session]);
  let winningTower = null;
  for (let seed = 1; seed <= 30 && !winningTower; seed++) {
    const loaded = await as(null, () => val(`select battle_direct_session_v7($1,$2) v`, [me, legitTower.session]), 'service_role');
    loaded.seed = seed;
    const result = verifyDirect(loaded, 'claim');
    if (result.win) winningTower = { seed, result };
  }
  assert.ok(winningTower, 'expected a deterministic tower win');
  await q(`update battle_sessions_v2 set seed=$2 where id=$1`, [legitTower.session, winningTower.seed]);
  const towerCall = claimBody(legitTower.session);
  const towerWin = await http(towerCall);
  assert.equal(towerWin.status, 200, JSON.stringify(towerWin));
  assert.equal(towerWin.data.validation, 'replay-v7');
  assert.equal(towerWin.data.win, true);
  assert.equal(towerWin.data.cleared, true);
  assert.equal(towerWin.data.floor, 2);
  const paid = await gold();
  assert.ok(paid >= towerGold);
  const towerAgain = await http(towerCall);
  assert.deepEqual(towerAgain.data, towerWin.data);
  assert.equal(await gold(), paid);
  assert.equal(await towerReceipts(), towerReceiptsBefore + 1);

  await unlockBefore(12, 14);
  const scripted = await start('story', '12:14', [heroine.uid], req(40));
  await reject(`select battle_session_finish_v2($1,$2::jsonb)`, [scripted.session, JSON.stringify(report)], /direct replay required/);
  await age(scripted.session);
  const scriptedHttp = await http(claimBody(scripted.session, { outcome: 'loss', mana: Math.trunc(scripted.snapshot.mana || 0) }));
  assert.equal(scriptedHttp.status, 200, JSON.stringify(scriptedHttp));
  assert.equal(scriptedHttp.data.cleared, true);
  assert.equal(scriptedHttp.data.win, false);
  assert.equal(scriptedHttp.data.stars, 3);
  const give = await start('story', '12:14', [heroine.uid], req(41));
  const gave = await http(claimBody(give.session, { outcome: 'giveup' }));
  assert.equal(gave.status, 200, JSON.stringify(gave));
  assert.equal(gave.data.cleared, false);

  await unlockBefore(1, 5);
  const boss = await start('story', '1:5', [owned.uid], req(50));
  const bossHttp = await http(claimBody(boss.session, { mana: boss.snapshot.mana == null ? null : Math.trunc(boss.snapshot.mana) }));
  assert.equal(bossHttp.status, 422);
  assert.equal(bossHttp.data.error, '이 전투는 서버가 다시 계산할 수 없어요');
  await age(boss.session);
  const bossFinish = await finish(boss.session, { ...report, mana: boss.snapshot.mana, cards: [] });
  assert.equal(bossFinish.validation, 'plausibility-v3');
  const towerBoss = await start('tower', 'normal:10', [owned.uid], req(51));
  const towerBossHttp = await http(claimBody(towerBoss.session));
  assert.equal(towerBossHttp.status, 422);
  assert.equal(towerBossHttp.data.error, '보스 층은 서버가 다시 계산할 수 없어요');

  await q(`update battle_replay_policy_v6 set enabled=true where singleton`);
  const sweep = await start('tower_sweep', 'normal:39', [owned.uid], req(60));
  await reject(`select battle_session_finish_v2($1,$2::jsonb)`, [sweep.session, JSON.stringify(report)], /sweep replay required/);
  const loadedSweep = await as(null, () => val(`select battle_sweep_session_v6($1,$2) v`, [me, sweep.session]), 'service_role');
  const sweepResult = verifySweep(loadedSweep);
  const sweepSettled = await as(null, () => val(`select battle_sweep_settle_v6($1,$2,$3,$4::jsonb) v`, [me, sweep.session, SWEEP_HASH, JSON.stringify(sweepResult)]), 'service_role');
  assert.equal(sweepSettled.validation, 'replay-v6');
  assert.equal(sweepSettled.win, sweepResult.win);

  console.log('phase7 SQL + ' + (process.argv.includes('--dashboard') ? 'Dashboard' : 'modular') + ' handler: forged story/tower wins rejected, verified win granted, phase6 sweep kept');
} catch (e) {
  console.error(e);
  process.exitCode = 1;
} finally {
  await db.close();
}
