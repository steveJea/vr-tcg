// Offline PGlite. Real handler + SQL. No network, keys, or production database.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { PGlite } from '@electric-sql/pglite';
import { buildSql, INSTALL_ACK } from './build_staging_sql.mjs';
import { ENGINE_VERSION, verifySweep } from '../supabase/functions/_shared/sweep-engine-v6.mjs';
import { createHandler } from '../supabase/functions/story-tower-verify-v6/handler.mjs';
import { dashboardHandler } from './load_phase6_dashboard.mjs';

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
  battle_sweep_session_v6: ['p_uid', 'p_id'],
  battle_sweep_settle_v6: ['p_uid', 'p_id', 'p_engine_hash', 'p_result'],
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
  const r = await handler(new Request('https://example.invalid/story-tower-verify-v6', {
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
const receipts = () => val(`select count(*)::int v from battle_clear_receipts_v2 where user_id=$1 and mode='tower'`, [me]);

try {
  await db.exec(`create role anon; create role authenticated; create role service_role; create schema auth;
    create table auth.users(id uuid primary key, email text, raw_user_meta_data jsonb default '{}', raw_app_meta_data jsonb default '{}', created_at timestamptz default now(), last_sign_in_at timestamptz, email_confirmed_at timestamptz);
    create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
    create function auth.jwt() returns jsonb language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $$;
    grant usage on schema auth, public to anon, authenticated, service_role;
    alter default privileges in schema public grant all on tables to anon, authenticated;
    alter default privileges in schema public grant all on sequences to anon, authenticated;
    alter default privileges in schema public grant execute on functions to anon, authenticated, service_role;`);
  let base = await buildSql();
  const at = base.indexOf('-- ===== SOURCE: security_phase6_story_tower.sql =====');
  assert.ok(at > 0);
  base = base.slice(0, at) + base.slice(base.indexOf('-- 공개 게임 설정만 명시적으로 조회 허용', at));
  await db.exec(base.replace(`confirmed_ref text := '${INSTALL_ACK}'`, "confirmed_ref text := 'abcdefghijklmnopqrst'"));
  const system = await val('select system_identifier::text v from pg_control_system()');
  const migration = await rd('supabase/security_phase6_story_tower.sql');
  await assert.rejects(db.exec(migration), /STOP: phase6 only/);
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
  assert.equal(await val('select enabled v from battle_replay_policy_v6'), false, 'install leaves sweep replay off');
  await reject(`select battle_sweep_session_v6($1,$2)`, [me, req(1)]);
  await reject(`select battle_sweep_settle_v6($1,$2,$3,$4::jsonb)`, [me, req(1), ENGINE_VERSION, '{"win":true,"reason":"wipe","turns":2,"my_turns":1}']);
  await reject(`select _phase6_old_finish_v2($1,$2::jsonb)`, [req(1), '{}']);
  await unlockBefore(1, 1);

  const story = await start('story', '1:1', [owned.uid, 'guest:10112'], req(10));
  await age(story.session);
  const storyWin = await finish(story.session, { ...report, mana: story.snapshot.mana, cards: [{ uid: owned.uid, kills: 1, blocks: 0 }] });
  assert.equal(storyWin.validation, 'plausibility-v3');
  assert.equal(storyWin.win, true);
  assert.equal(storyWin.stars, 3);
  assert.deepEqual(await finish(story.session, { ...report, mana: story.snapshot.mana, cards: [{ uid: owned.uid, kills: 1, blocks: 0 }] }), storyWin);
  await reject(`select battle_session_finish_v2($1,$2::jsonb)`, [story.session, JSON.stringify({ ...report, mana: story.snapshot.mana, turns: 6, my_turns: 3, cards: [] })], /submission conflict/);
  await reject(`select battle_session_finish_v2($1,$2::jsonb)`, [story.session, JSON.stringify(report)], /not found/, other);
  const tooMuch = await start('story', '1:2', [owned.uid], req(11));
  await age(tooMuch.session);
  await reject(`select battle_session_finish_v2($1,$2::jsonb)`, [tooMuch.session, JSON.stringify({ ...report, mana: tooMuch.snapshot.mana + 1, cards: [] })], /mana/);
  const give = await start('story', '1:2', [owned.uid], req(12));
  await age(give.session);
  const gaveUp = await finish(give.session, { ...report, win: false, reason: 'giveup', mana: null, cards: [] });
  assert.equal(gaveUp.win, false);
  assert.equal(await val(`select count(*)::int v from battle_clear_receipts_v2 where user_id=$1 and target='1:2'`, [me]), 0);

  await unlockBefore(12, 14);
  await reject(`select battle_session_start_v2('story','12:14',$1::jsonb,$2)`, [JSON.stringify([owned.uid]), req(20)], /required card/);
  const scriptedLoss = await start('story', '12:14', [heroine.uid], req(21));
  await age(scriptedLoss.session);
  const noGive = await finish(scriptedLoss.session, { win: false, reason: 'giveup', turns: 2, my_turns: 1, mana: scriptedLoss.snapshot.mana, skills: 0, cards: [] });
  assert.equal(noGive.cleared, false);
  const scripted = await start('story', '12:14', [heroine.uid], req(22));
  await age(scripted.session);
  const lostOk = await finish(scripted.session, { win: false, reason: 'wipe', turns: 4, my_turns: 2, mana: scripted.snapshot.mana, skills: 0, cards: [] });
  assert.equal(lostOk.validation, 'plausibility-v3');
  assert.equal(lostOk.cleared, true);
  assert.equal(lostOk.stars, 3);

  await unlockBefore(13, 15);
  const survive = await start('story', '13:15', [heroine.uid], req(23));
  await age(survive.session);
  await reject(`select battle_session_finish_v2($1,$2::jsonb)`, [survive.session, JSON.stringify({ win: true, reason: 'survive', turns: 1, my_turns: 1, mana: survive.snapshot.mana, skills: 0, cards: [] })], /end reason/);
  const survived = await finish(survive.session, { win: true, reason: 'survive', turns: 2, my_turns: 1, mana: survive.snapshot.mana, skills: 0, cards: [] });
  assert.equal(survived.validation, 'plausibility-v3', 'survive turns are still a bounded report, not a combat replay');
  assert.equal(survived.cleared, true);

  const held = await start('tower_sweep', 'normal:1', [owned.uid], req(29));
  await age(held.session);
  const heldWin = await finish(held.session, report);
  assert.equal(heldWin.validation, 'plausibility-v3');
  assert.equal(heldWin.cleared, true);
  await q(`update battle_replay_policy_v6 set enabled=true where singleton`);

  await q(`update player_state set level=1 where user_id=$1`, [me]);
  await reject(`select battle_session_start_v2('tower','normal:1',$1::jsonb,$2)`, [JSON.stringify([owned.uid]), req(30)], /level too low/);
  await q(`update player_state set level=50 where user_id=$1`, [me]);
  await reject(`select battle_session_start_v2('tower','normal:5',$1::jsonb,$2)`, [JSON.stringify([owned.uid]), req(31)], /floor locked/);
  const wind = await val(`select id v from battle_card_meta_v2 where definition->>'class'='WIND' limit 1`);
  const windCard = await val(`select _story_new_card($1) v`, [wind]);
  await q(`update story_progress set data=jsonb_set(data,'{owned}', data->'owned' || $2::jsonb) where user_id=$1`, [me, JSON.stringify(windCard)]);
  const elem = await as(me, () => q(`select battle_session_start_v2('tower','wind:1',$1::jsonb,$2)`, [JSON.stringify([owned.uid]), req(32)]).then(() => null).catch(e => e));
  assert.match(String(elem), /tower element|tower closed today/);
  const manual = await start('tower', 'normal:1', [owned.uid], req(33));
  await age(manual.session);
  const manualWin = await finish(manual.session, report);
  assert.equal(manualWin.validation, 'plausibility-v3');
  assert.equal(manualWin.cleared, true);

  const before = await gold();
  const beforeReceipts = await receipts();
  const sweep = await start('tower_sweep', 'normal:2', [owned.uid], req(40));
  await age(sweep.session);
  await reject(`select battle_session_finish_v2($1,$2::jsonb)`, [sweep.session, JSON.stringify({ ...report, win: true })], /sweep replay required/);
  assert.equal(await gold(), before);
  assert.equal(await receipts(), beforeReceipts);
  let winning = null;
  for (let seed = 1; seed <= 40 && !winning; seed++) {
    const loaded = await as(null, () => val(`select battle_sweep_session_v6($1,$2) v`, [me, sweep.session]), 'service_role');
    loaded.seed = seed;
    loaded.snapshot.cards[0].level = 80;
    const result = verifySweep(loaded);
    if (result.win) winning = { seed, result };
  }
  assert.ok(winning, 'expected a deterministic winning seed for the fixture');
  await q(`update battle_sessions_v2 set seed=$2, snapshot=jsonb_set(snapshot,'{cards,0,level}','80'::jsonb) where id=$1`, [sweep.session, winning.seed]);
  const call = { op: 'sweep', id: sweep.session, version: ENGINE_VERSION };
  assert.equal((await http({ ...call, win: true })).status, 400);
  assert.equal((await http(call, 'invalid')).status, 401);
  assert.equal((await http(call, 'fixture-other')).status, 409);
  let settled = await http(call);
  assert.equal(settled.status, 200, JSON.stringify(settled));
  assert.equal(settled.data.validation, 'replay-v6');
  assert.equal(settled.data.win, true);
  assert.equal(settled.data.floor, 2);
  const paid = await gold();
  const again = await http(call);
  assert.deepEqual(again.data, settled.data);
  assert.equal(await gold(), paid);
  assert.equal(await receipts(), beforeReceipts + 1);
  await as(null, () => assert.rejects(q(`select battle_sweep_settle_v6($1,$2,$3,$4::jsonb)`, [me, sweep.session, ENGINE_VERSION, JSON.stringify({ ...winning.result, turns: winning.result.turns === 40 ? 39 : winning.result.turns + 1 })]), /submission conflict/), 'service_role');
  assert.equal(await gold(), paid);

  await q(`update tower_progress set best_floor=38 where user_id=$1 and tower='normal'`, [me]);
  await q(`update battle_legacy_access_v2 set tower_best=jsonb_set(coalesce(tower_best,'{}'),'{normal}','38'::jsonb) where user_id=$1`, [me]);
  const loss = await start('tower_sweep', 'normal:39', [owned.uid], req(41));
  await age(loss.session);
  await q(`update battle_sessions_v2 set seed=3 where id=$1`, [loss.session]);
  const unpaid = await http({ op: 'sweep', id: loss.session, version: ENGINE_VERSION });
  assert.equal(unpaid.status, 200, JSON.stringify(unpaid));
  assert.equal(unpaid.data.win, false);
  assert.equal(unpaid.data.validation, 'replay-v6');
  assert.equal(unpaid.data.reason, 'wipe');
  assert.equal(await val(`select best_floor::int v from tower_progress where user_id=$1 and tower='normal'`, [me]), 38);
  assert.equal(await receipts(), beforeReceipts + 1);

  const stale = await start('tower_sweep', 'normal:39', [owned.uid], req(42));
  await q(`update battle_sessions_v2 set issued_at=clock_timestamp()-interval '3 hours', expires_at=clock_timestamp()-interval '1 second' where id=$1`, [stale.session]);
  const expired = await as(null, () => val(`select battle_sweep_settle_v6($1,$2,$3,$4::jsonb) v`, [me, stale.session, ENGINE_VERSION, JSON.stringify(winning.result)]), 'service_role');
  assert.equal(expired.status, 'expired');
  assert.equal(expired.ok, false);
  await as(null, () => assert.rejects(q(`select battle_sweep_settle_v6($1,$2,$3,$4::jsonb)`, [me, req(99), ENGINE_VERSION, JSON.stringify(winning.result)]), /not found/), 'service_role');

  const bad = await start('tower_sweep', 'normal:39', [owned.uid], req(43));
  await age(bad.session);
  await as(null, () => assert.rejects(q(`select battle_sweep_settle_v6($1,$2,$3,$4::jsonb)`, [me, bad.session, 'b'.repeat(64), JSON.stringify(winning.result)]), /verifier unavailable/), 'service_role');
  await q(`update battle_replay_policy_v6 set enabled=false where singleton`);
  await as(null, () => assert.rejects(q(`select battle_sweep_settle_v6($1,$2,$3,$4::jsonb)`, [me, bad.session, ENGINE_VERSION, JSON.stringify(winning.result)]), /verifier unavailable/), 'service_role');
  await q(`update battle_replay_policy_v6 set enabled=true where singleton`);
  const restored = await http({ op: 'sweep', id: bad.session, version: ENGINE_VERSION });
  assert.equal(restored.status, 200, JSON.stringify(restored));
  assert.equal(restored.data.validation, 'replay-v6');
  console.log('phase6 SQL + ' + (process.argv.includes('--dashboard') ? 'Dashboard' : 'modular') + ' handler: story plausibility kept, sweep replay/idempotency/ACL/locks OK');
} catch (e) {
  console.error(e);
  process.exitCode = 1;
} finally {
  await db.close();
}
