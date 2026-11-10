// Offline PGlite. Real handler + SQL. No network, keys, or production database.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { PGlite } from '@electric-sql/pglite';
import { buildSql, INSTALL_ACK } from './build_staging_sql.mjs';
import { ENGINE_VERSION as SWEEP_HASH, verifySweep } from '../supabase/functions/_shared/sweep-engine-v6.mjs';
import { ENGINE_VERSION as ARCADE_HASH } from '../supabase/functions/_shared/arcade-engine-v5.mjs';
import { ENGINE_VERSION, verifyDirect, runDirect, towerEnemies } from '../supabase/functions/story-direct-verify-v7/engine.mjs';
import { runSweep } from '../js/sweep-core.js';
import { initPlayers, placeUnit, turnStart, turnEnd, useSkill, aiPickSkill, refreshAll, setRng, setEmitter, getEmitter } from '../js/skills.js';
import { clearBuff, refillMana, endTurnXp, makeUnit, resolveAttack, aiPickTarget } from '../js/rules.js';
import { createHandler } from '../supabase/functions/story-direct-verify-v7/handler.mjs';
import { dashboardHandler } from './load_phase7_dashboard.mjs';

assert.equal(SWEEP_HASH, 'e262b1b775c3e9d5c8faf5fc3103409ed20f7ed82ead9cd0c228e3160228c3f5');
assert.equal(ARCADE_HASH, '0f427022636e17286bdaa61024e640aae28c6a15f3b0f1121fc8ad5d2f252de6');
assert.notEqual(ENGINE_VERSION, SWEEP_HASH);

assert.throws(() => verifySweep({ mode: 'tower_sweep', target: 'normal:10', seed: 3, snapshot: { cards: [{ id: '10111', uid: 'u1', level: 80 }] } }), /boss floor/);
function bossCdFight(cd) {
  // 이지영(10311) Lv20: both cooldowns wipe the player, and bossCdMinus 2 ends that wipe sooner.
  const session = { mode: 'story', target: '10:17', seed: 8, snapshot: { mana: null, leader: null, cards: [{ id: '10311', uid: 'p', level: 20 }],
    stage: { type: 'boss', bossId: '10051', bossCdMinus: cd, baseHp: 999999, enemies: { ids: ['10051'], levels: { '10051': 2 }, boost: { '10051': { ATK: 200 } } } } } };
  const log = [];
  for (let n = 0; n < 40; n++) {
    const res = verifyDirect(session, log);
    if (res.reason !== 'incomplete') return res;
    log.push({ t: res.my_turns, k: 'end' });
  }
  return null;
}
const bossCdPlain = bossCdFight(0), bossCdCut = bossCdFight(2);
assert.equal(bossCdPlain.reason, 'wipe');
assert.equal(bossCdCut.reason, 'wipe');
assert.ok(bossCdCut.turns < bossCdPlain.turns, `bossCdMinus should make the boss skill return sooner (${bossCdCut.turns} vs ${bossCdPlain.turns})`);
const claimBody = (id, actions = [], cards = []) => ({ op: 'direct', id, version: ENGINE_VERSION, actions, cards });
function legalLog(session) {
  const log = [];
  for (let n = 0; n < 40; n++) {
    let res;
    try { res = verifyDirect(session, log); } catch { return null; }
    if (res.win) return { res, log };
    if (res.reason !== 'incomplete') return { res, log };
    const t = res.my_turns;
    const opts = [];
    for (let i = 0; i < 6; i++) opts.push({ t, k: 'atk', i, g: -1 });
    for (let i = 0; i < 6; i++) for (let g = 0; g < 8; g++) opts.push({ t, k: 'atk', i, g });
    opts.push({ t, k: 'end' });
    let picked = null;
    for (const opt of opts) { try { verifyDirect(session, log.concat(opt)); picked = opt; break; } catch { /* illegal action */ } }
    if (!picked) return { res, log };
    log.push(picked);
  }
  return null;
}

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
  assert.equal(await val('select engine_hash v from battle_replay_policy_v7'), ENGINE_VERSION);
  assert.notEqual(ENGINE_VERSION, SWEEP_HASH);
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
  const forgedStoryHttp = await http(claimBody(forgedStory.session, []));
  assert.equal(forgedStoryHttp.status, 200, JSON.stringify(forgedStoryHttp));
  assert.equal(forgedStoryHttp.data.cleared, false);
  assert.equal(forgedStoryHttp.data.win, false);
  assert.equal(await gold(), beforeStoryGold);

  const bossStory = await start('story', '1:1', [owned.uid, 'guest:10112'], req(21));
  const bossStage = { type: 'boss', baseHp: 250, bossId: '10051', enemies: { ids: ['10074', '10051'], boost: { '10051': { HP: 999999, ATK: 20, DEF: 50 } } } };
  const bossSnap = bossStory.snapshot;
  bossSnap.stage = bossStage;
  bossSnap.cards = [{ id: '10111', uid: owned.uid, level: 40 }];
  bossSnap.mana = null;
  await q(`update battle_sessions_v2 set seed=4, snapshot=$2::jsonb where id=$1`, [bossStory.session, JSON.stringify(bossSnap)]);
  const bossLoaded = await as(null, () => val(`select battle_direct_session_v7($1,$2) v`, [me, bossStory.session]), 'service_role');
  const manual = legalLog(bossLoaded);
  assert.equal(manual?.res?.win, true, JSON.stringify(manual?.res));
  assert.equal(manual.res.reason, 'ko');
  const swept = runSweep(
    { initPlayers, placeUnit, turnStart, turnEnd, useSkill, aiPickSkill, refreshAll, setRng, setEmitter, getEmitter },
    { clearBuff, refillMana, endTurnXp, makeUnit, resolveAttack, aiPickTarget },
    { me: [{ id: '10111', HP: 800, ATK: 200, DEF: 80, grade: 'RARE', class: 'FIRE', attribute: 'CHARGE', PHY: 70, MEN: 40, MOR: 40, cost: 20, power: 5000, uid: owned.uid }],
      ai: [{ id: '10074', HP: 80, ATK: 10, DEF: 5, grade: 'NORMAL', class: 'WIND', attribute: 'DEFENSE', PHY: 10, MEN: 10, MOR: 10, cost: 5, power: 300 }, { id: '10051', HP: 999999, ATK: 20, DEF: 50, grade: 'ULTRA RARE', class: 'FIRE', attribute: 'CHARGE', PHY: 80, MEN: 40, MOR: 40, cost: 40, power: 80000 }],
      seed: 4, maxTurns: 40 });
  assert.equal(swept.win, false);
  await age(bossStory.session);
  const storyCall = claimBody(bossStory.session, manual.log);
  const storyWin = await http(storyCall);
  assert.equal(storyWin.status, 200, JSON.stringify(storyWin));
  assert.equal(storyWin.data.validation, 'replay-v7');
  assert.equal(storyWin.data.win, true);
  assert.equal(storyWin.data.cleared, true);
  const storyGold = await gold();
  const storyAgain = await http(storyCall);
  assert.deepEqual(storyAgain.data, storyWin.data);
  assert.equal(await gold(), storyGold);
  const tampered = manual.log.map(a => a.k === 'atk' ? { ...a, g: 9 } : a);
  const bad = await http(claimBody(bossStory.session, tampered));
  assert.equal(bad.status, 422);
  assert.match(bad.data.error, /전투 기록/);
  assert.equal(await gold(), storyGold);

  const ids = ['10051', '10323', '10058', '10311', '10118'];
  const made = [];
  for (const id of ids) made.push(await val(`select _story_new_card($1) v`, [id]));
  await q(`update story_progress set data=jsonb_set(data,'{owned}', data->'owned' || $2::jsonb) where user_id=$1`, [me, JSON.stringify(made)]);
  await q(`update battle_legacy_access_v2 set tower_best=jsonb_set(coalesce(tower_best,'{}'),'{normal}','9'::jsonb) where user_id=$1`, [me]);
  const floor = await start('tower', 'normal:10', made.map(c => c.uid), req(30));
  const floorSnap = floor.snapshot;
  floorSnap.cards = made.map(c => ({ ...c, level: 60 }));
  await q(`update battle_sessions_v2 set seed=3, snapshot=$2::jsonb where id=$1`, [floor.session, JSON.stringify(floorSnap)]);
  const floorLoaded = await as(null, () => val(`select battle_direct_session_v7($1,$2) v`, [me, floor.session]), 'service_role');
  const floorLog = legalLog(floorLoaded);
  assert.equal(floorLog?.res?.win, true, JSON.stringify(floorLog?.res));
  assert.equal(floorLog.res.reason, 'ko');
  const beforeFloor = await gold();
  const floorHttp = await http(claimBody(floor.session, floorLog.log));
  assert.equal(floorHttp.status, 200, JSON.stringify(floorHttp));
  assert.equal(floorHttp.data.win, true);
  assert.equal(floorHttp.data.floor, 10);
  const floorGold = await gold();
  assert.ok(floorGold >= beforeFloor);
  const floorAgain = await http(claimBody(floor.session, floorLog.log));
  assert.deepEqual(floorAgain.data, floorHttp.data);
  assert.equal(await gold(), floorGold);
  const otherRoster = { ...floorLoaded, snapshot: { ...floorLoaded.snapshot, cards: [{ id: '10074', uid: 'w', level: 1 }] } };
  assert.throws(() => verifyDirect(otherRoster, floorLog.log), /tampered/);

  const add = await start('story', '1:2', [owned.uid], req(40));
  const addSnap = add.snapshot;
  addSnap.mana = null;
  addSnap.cards = [{ id: '10074', uid: owned.uid, level: 1 }];
  addSnap.stage = { type: 'normal', enemies: { ids: ['10051'], boost: { '10051': { HP: 800, ATK: 400, DEF: 20 } } }, awaken: { on: '10074', id: '10311', battleLevel: 40 } };
  await q(`update battle_sessions_v2 set seed=4, snapshot=$2::jsonb where id=$1`, [add.session, JSON.stringify(addSnap)]);
  const addLoaded = await as(null, () => val(`select battle_direct_session_v7($1,$2) v`, [me, add.session]), 'service_role');
  const addLog = legalLog(addLoaded);
  assert.equal(addLog?.res?.win, true, JSON.stringify(addLog?.res));
  const without = { ...addLoaded, snapshot: { ...addLoaded.snapshot, stage: { ...addSnap.stage, awaken: null } } };
  let noAwaken = false;
  try { noAwaken = verifyDirect(without, addLog.log).win; } catch { noAwaken = false; }
  assert.equal(noAwaken, false);
  await age(add.session);
  const addHttp = await http(claimBody(add.session, addLog.log));
  assert.equal(addHttp.status, 200, JSON.stringify(addHttp));
  assert.equal(addHttp.data.cleared, true);
  assert.equal(addHttp.data.win, true);

  await unlockBefore(12, 14);
  const scripted = await start('story', '12:14', [heroine.uid], req(50));
  await age(scripted.session);
  const scriptedHttp = await http(claimBody(scripted.session, [{ t: 1, k: 'end' }]));
  assert.equal(scriptedHttp.status, 200, JSON.stringify(scriptedHttp));
  assert.equal(scriptedHttp.data.cleared, true);
  assert.equal(scriptedHttp.data.win, false);
  assert.equal(scriptedHttp.data.stars, 3);
  const give = await start('story', '12:14', [heroine.uid], req(51));
  const gave = await http(claimBody(give.session, [{ t: 1, k: 'giveup' }]));
  assert.equal(gave.status, 200, JSON.stringify(gave));
  assert.equal(gave.data.cleared, false);

  await q(`update battle_replay_policy_v6 set enabled=true where singleton`);
  await q(`update tower_progress set best_floor=38 where user_id=$1 and tower='normal'`, [me]);
  await q(`update battle_legacy_access_v2 set tower_best=jsonb_set(coalesce(tower_best,'{}'),'{normal}','38'::jsonb) where user_id=$1`, [me]);
  const sweep = await start('tower_sweep', 'normal:39', [owned.uid], req(60));
  await reject(`select battle_session_finish_v2($1,$2::jsonb)`, [sweep.session, JSON.stringify(report)], /sweep replay required/);
  const loadedSweep = await as(null, () => val(`select battle_sweep_session_v6($1,$2) v`, [me, sweep.session]), 'service_role');
  const sweepResult = verifySweep(loadedSweep);
  const sweepSettled = await as(null, () => val(`select battle_sweep_settle_v6($1,$2,$3,$4::jsonb) v`, [me, sweep.session, SWEEP_HASH, JSON.stringify(sweepResult)]), 'service_role');
  assert.equal(sweepSettled.validation, 'replay-v6');
  assert.equal(sweepSettled.win, sweepResult.win);
  assert.ok(towerEnemies('normal', 10).bossId);

  console.log('phase7 SQL + ' + (process.argv.includes('--dashboard') ? 'Dashboard' : 'modular') + ' handler: manual replay grants, forged and tampered logs rejected, phase6 sweep kept');
} catch (e) {
  console.error(e);
  process.exitCode = 1;
} finally {
  await db.close();
}
