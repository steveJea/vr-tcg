// arcade_mvp_gallery_{staging,production}.sql (PGlite): verified-win MVP -> 도감 once per session.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { PGlite } from '@electric-sql/pglite';
import { buildSql, INSTALL_ACK } from './build_staging_sql.mjs';
import { ENGINE_VERSION } from '../supabase/functions/_shared/arcade-engine-v5.mjs';
import { createHandler } from '../supabase/functions/arcade-verify-v5/handler.mjs';
import { fixture } from './phase5_fixture.mjs';
const rd = p => readFile(new URL('../' + p, import.meta.url), 'utf8');
const db = new PGlite(), me = '11111111-1111-4111-8111-111111111111', other = '22222222-2222-4222-8222-222222222222';
const q = async (s, p = []) => (await db.query(s, p)).rows, val = async (s, p = []) => (await q(s, p))[0]?.v;
async function as(u, fn, role = 'authenticated') { await q(`select set_config('request.jwt.claim.sub',$1,false)`, [u || '']); await db.exec(`set role ${role}`); try { return await fn(); } finally { await db.exec('reset role'); } }
const req = n => `aaaaaaaa-aaaa-4aaa-8aaa-${String(n).padStart(12, '0')}`;
const env = { SUPABASE_URL: 'https://cuyqchmdcnsgzkwyclji.supabase.co', SUPABASE_PUBLISHABLE_KEYS: JSON.stringify({ default: 'sb_publishable_fixture' }), SUPABASE_SECRET_KEYS: JSON.stringify({ default: 'sb_secret_fixture' }) };
const signatures = { arcade_start_v5: ['p_request', 'p_options', 'p_engine_hash'], arcade_engine_session_v5: ['p_uid', 'p_id'], arcade_engine_settle_v5: ['p_uid', 'p_id', 'p_engine_hash', 'p_submission', 'p_result'] };
const fetcher = async (url, opts) => {
  if (url.endsWith('/auth/v1/user')) { const id = opts.headers.authorization === 'Bearer fixture-me' ? me : null; return Response.json(id ? { id } : { error: 'x' }, { status: id ? 200 : 401 }); }
  const name = url.split('/').at(-1), args = JSON.parse(opts.body), trusted = opts.headers.apikey === 'sb_secret_fixture';
  const ps = signatures[name].map(k => typeof args[k] === 'object' && args[k] !== null ? JSON.stringify(args[k]) : args[k]);
  try { return Response.json(await as(trusted ? null : me, () => val(`select public.${name}(${ps.map((_, i) => '$' + (i + 1)).join(',')}) v`, ps), trusted ? 'service_role' : 'authenticated')); }
  catch (e) { return Response.json({ message: e.message }, { status: 400 }); }
};
const handler = createHandler(env, fetcher);
const http = async body => { const r = await handler(new Request('https://example.invalid/arcade-verify-v5', { method: 'POST', headers: { 'content-type': 'application/json', authorization: 'Bearer fixture-me' }, body: JSON.stringify(body) })); const data = await r.json(); delete data.trace; return { status: r.status, data }; };
try {
  await db.exec(`create role anon; create role authenticated; create role service_role; create schema auth;
  create table auth.users(id uuid primary key,email text,raw_user_meta_data jsonb default '{}',raw_app_meta_data jsonb default '{}',created_at timestamptz default now(),last_sign_in_at timestamptz,email_confirmed_at timestamptz);
  create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
  create function auth.jwt() returns jsonb language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb $$;
  grant usage on schema auth,public to anon,authenticated,service_role;
  alter default privileges in schema public grant all on tables to anon,authenticated;
  alter default privileges in schema public grant all on sequences to anon,authenticated;
  alter default privileges in schema public grant execute on functions to anon,authenticated,service_role;`);
  let base = await buildSql(); const at = base.indexOf('-- ===== SOURCE: security_phase5_arcade.sql ====='); assert(at > 0); base = base.slice(0, at) + base.slice(base.indexOf('-- 공개 게임 설정만 명시적으로 조회 허용', at));
  await db.exec(base.replace(`confirmed_ref text := '${INSTALL_ACK}'`, "confirmed_ref text := 'abcdefghijklmnopqrst'"));
  const system = await val('select system_identifier::text v from pg_control_system()');
  const local = t => t.replaceAll("'7703759698107299042'", `'${system}'`);
  await q(`insert into auth.users(id,email) values($1,'one@example.invalid'),($2,'two@example.invalid')`, [me, other]);
  await db.exec(local(await rd('supabase/security_phase5_arcade.sql')));
  const cat = (await q(`select card_id from reward_card_catalog order by card_id limit 3`)).map(r => r.card_id); assert.equal(cat.length, 3);
  // Sessions settled directly with a server verdict (as arcade-verify-v5 would after its re-run).
  let n = 100;
  const session = async (u = me) => { await q(`update arcade_sessions_v5 set created_at=created_at-interval '3 seconds' where user_id=$1`, [u]); return Number(await as(u, () => val(`select (arcade_start_v5($1,'{"grades":null,"turns":10,"clearFirst":false}'::jsonb,$2))->>'id' v`, [req(n++), ENGINE_VERSION]))); };
  const settle = async (id, result, mvp, u = me) => (await val(`select arcade_engine_settle_v5($1,$2,$3,'{"actions":[]}'::jsonb,$4::jsonb) v`, [u, id, ENGINE_VERSION, JSON.stringify({ result, reason: 'ko', skills: 1, turns: 3, damage: 10, mvp_id: mvp, mvp_name: 'x', merc_id: null })])).result;
  const gal = (u, c) => q(`select count,mvp_count from gallery where user_id=$1 and card_id=$2`, [u, c]).then(r => r[0] || null);
  // Before the fix: verified wins never touch the gallery.
  await settle(await session(), 'win', cat[0]); await settle(await session(), 'win', cat[0]); await settle(await session(), 'lose', cat[1]); await settle(await session(), 'win', 'npc-not-in-catalog');
  const fid = await session(); await val(`select arcade_engine_settle_v5($1,$2,$3,'{"forfeit":true}'::jsonb,null) v`, [me, fid, ENGINE_VERSION]);
  assert.equal(await gal(me, cat[0]), null);
  const have0 = await val(`select _gallery_have($1) v`, [me]);
  const fx = await rd('supabase/arcade_mvp_gallery_staging.sql'), check = await rd('supabase/arcade_mvp_gallery_check_staging.sql');
  const ok = async () => (await q(local(check).replace(/^--.*$/gm, '')))[0];
  await assert.rejects(ok(), /arcade_gallery_v5/, "check before the fix: table missing");
  await assert.rejects(db.exec(fx), /STOP: staging only/);
  await assert.rejects(db.exec(await rd('supabase/arcade_mvp_gallery_production.sql')), /STOP: production only/);
  await db.exec(local(fx)); await db.exec(local(fx));
  assert.deepEqual(await ok(), { ok: true, missing: 0, registered: 2 }, 'backfill: two verified wins, lose/forfeit/NPC skipped');
  assert.deepEqual(await gal(me, cat[0]), { count: 2, mvp_count: 2 }, 'rerun does not double the backfill');
  assert.equal(await gal(me, cat[1]), null, 'lose MVP not registered');
  assert.equal(await val(`select _gallery_have($1) v`, [me]), have0 + 1, 'gallery % counts the arcade MVP card once');
  // New verified win: receipt says new; replay of the same session adds nothing.
  const s1 = await session(); const r1 = await settle(s1, 'win', cat[2]);
  assert.deepEqual(r1.gallery, { card_id: cat[2], new: true, mvp_count: 1 });
  assert.deepEqual((await settle(s1, 'win', cat[2])).gallery, r1.gallery, 'settled replay returns the same receipt');
  assert.deepEqual(await gal(me, cat[2]), { count: 1, mvp_count: 1 });
  const r2 = await settle(await session(), 'win', cat[2]);
  assert.deepEqual(r2.gallery, { card_id: cat[2], new: false, mvp_count: 2 });
  assert.equal((await settle(await session(), 'draw', cat[1])).gallery, undefined, 'draw: nothing');
  assert.equal(await val(`select _gallery_have($1) v`, [me]), have0 + 2);
  assert.equal(await val(`select _gallery_have($1) v`, [other]), 0, 'other user unaffected');
  // Real handler path: the MVP comes from the server re-run, not from the request.
  await q(`update arcade_sessions_v5 set created_at=created_at-interval '3 seconds' where user_id=$1`, [me]);
  const st = await http({ op: 'start', request: req(900), options: { grades: null, turns: 10, clearFirst: false }, version: ENGINE_VERSION }); assert.equal(st.status, 200, JSON.stringify(st));
  const f = fixture(st.data.seed, { grades: null, turns: 10, clearFirst: false });
  assert.equal((await http({ op: 'finish', id: st.data.id, actions: f.actions, mvp_id: cat[0] })).status, 400, 'a browser-chosen MVP is rejected outright');
  const fin = await http({ op: 'finish', id: st.data.id, actions: f.actions }); assert.equal(fin.status, 200, JSON.stringify(fin));
  const rc = fin.data.result; if (process.env.DEBUG) console.log('real', rc.result, rc.mvp_id, rc.gallery); assert.equal(rc.mvp_id, f.result.mvp_id, 'MVP = engine verdict');
  if (rc.result === 'win' && (await q(`select 1 from reward_card_catalog where card_id=$1`, [rc.mvp_id])).length) assert.equal(rc.gallery.card_id, rc.mvp_id); else assert.equal(rc.gallery, undefined);
  // Browser can neither read the ledger nor call the registrar.
  for (const role of ['anon', 'authenticated']) {
    await as(me, () => assert.rejects(q('select * from arcade_gallery_v5'), /permission denied/), role);
    await as(me, () => assert.rejects(q(`select _arcade_gallery_v5(1,$1,'{}')`, [me]), /permission denied/), role);
    await as(me, () => assert.rejects(q(`select gallery_register(array['1'],'1')`), /reward verification pending|permission denied/), role);
  }
  assert.equal((await ok()).ok, true);
  console.log('arcade MVP gallery SQL: verified win only, once per session, server MVP, backfill/rerun, ACL OK');
} catch (e) { console.error(e); process.exitCode = 1; } finally { await db.close(); }
