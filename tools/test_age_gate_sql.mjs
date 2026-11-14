// 만 19세 게이트 SQL: staging 가드·반복 실행·플래그 기본 OFF·결제 INSERT 차단 — 2026-11-14
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { PGlite } from '@electric-sql/pglite';

const STAGING = '7703759698107299042';
const sql = await readFile(new URL('../supabase/age_19plus_staging.sql', import.meta.url), 'utf8');
const check = await readFile(new URL('../supabase/age_19plus_check_staging.sql', import.meta.url), 'utf8');
const js = await readFile(new URL('../js/consent.js', import.meta.url), 'utf8');
const gate = await readFile(new URL('../js/age-gate.js', import.meta.url), 'utf8');
const ver = (/TERMS_VERSION = '([^']+)'/.exec(js) || [])[1];
assert.equal(ver, '2026-11-19plus');
assert.match(sql, new RegExp(`'terms', '${ver}', 'privacy', '${ver}'`));
assert.match(sql, /age_verification_required', false/);
assert.match(sql, /7703759698107299042/);
assert.doesNotMatch(sql, /\b(?:truncate|delete from|drop table)\b/i);
assert.match(check, /읽기만/);
assert.match(gate, /age_gate_status/);
assert.match(gate, /!r\.ok\) return true/);

const boot = async (ident) => {
  const db = new PGlite();
  await db.exec(`create role anon; create role authenticated; create schema auth;
    create table auth.users(id uuid primary key);
    create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
    grant usage on schema auth to authenticated; grant execute on function auth.uid() to authenticated;
    create table public.profiles(id uuid primary key references auth.users(id), nickname text, avatar_url text, nick_set boolean not null default false);
    create table public.payment_orders(
      order_id text primary key default 'vrs_test', user_id uuid not null references auth.users(id), request_id uuid not null default gen_random_uuid(),
      product_id text not null default 'gem_100', order_name text not null default 'x', amount integer not null default 1100,
      currency text not null default 'KRW', paid_gems integer not null default 100, bonus_gems integer not null default 0,
      status text not null default 'pending');
    create function public.test_control() returns table(system_identifier text) language sql as $$select '${ident}'::text$$;`);
  return db;
};
const guarded = s => s.replace('pg_catalog.pg_control_system()', 'public.test_control()').replace("notify pgrst, 'reload schema';", '');

let db = await boot('WRONG');
await assert.rejects(db.exec(guarded(sql)), /STOP: .* only/);
await db.exec('rollback');
await db.close();

db = await boot(STAGING);
await db.exec(guarded(sql));
await db.exec(guarded(sql)); // idempotent
const a = crypto.randomUUID(), b = crypto.randomUUID();
await db.query('insert into auth.users values($1),($2)', [a, b]);
await db.query('insert into public.profiles(id) values($1),($2)', [a, b]);

const as = async (uid, q, p = []) => {
  await db.exec(`begin; set local role authenticated; set local request.jwt.claim.sub = '${uid}';`);
  try { const r = await db.query(q, p); await db.exec('commit'); return r; }
  catch (e) { await db.exec('rollback'); throw e; }
};

let st = (await as(a, 'select public.age_gate_status() s')).rows[0].s;
assert.equal(st.required, false); assert.equal(st.verified, false); assert.equal(st.ok, true);
assert.equal((await db.query('select public._age_gate_ok($1) ok', [a])).rows[0].ok, true);
assert.equal((await db.query("select enabled from public.app_flags where key='age_verification_required'")).rows[0].enabled, false);
assert.equal((await db.query('select public._consent_versions()->>$$terms$$ v')).rows[0].v, ver);

await db.query('insert into public.payment_orders(order_id, user_id) values ($1, $2)', ['vrs_ok', a]);

await db.exec("update public.app_flags set enabled = true where key = 'age_verification_required'");
st = (await as(a, 'select public.age_gate_status() s')).rows[0].s;
assert.equal(st.required, true); assert.equal(st.ok, false);
await assert.rejects(db.query('insert into public.payment_orders(order_id, user_id) values ($1, $2)', ['vrs_block', a]), /age verification required/);

await db.query('update public.profiles set age_verified = true, age_verified_at = now() where id = $1', [a]);
st = (await as(a, 'select public.age_gate_status() s')).rows[0].s;
assert.equal(st.verified, true); assert.equal(st.ok, true);
await db.query('insert into public.payment_orders(order_id, user_id) values ($1, $2)', ['vrs_verified', a]);

await assert.rejects(db.exec(`begin; set local role anon; select public.age_gate_status();`), /permission denied/);
await db.exec('rollback');
await assert.rejects(as(a, "update public.app_flags set enabled = false"), /permission denied/);

const chk = (await db.query(check.replace('pg_catalog.pg_control_system()', 'public.test_control()'))).rows[0];
assert.equal(chk.is_staging, true);
assert.equal(chk.terms_version, ver);
assert.equal(chk.age_verified_col, true);
assert.equal(chk.flag_required, true); // we turned the flag on in this test
assert.equal(chk.status_fn, true);

await db.close();
console.log('Age gate SQL: staging guard, idempotent, flag default OFF, payment insert blocked when ON, status RPC OK');
process.exit(0);
