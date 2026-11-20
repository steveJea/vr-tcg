import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { PGlite } from '@electric-sql/pglite';

const STAGING = '7703759698107299042';
const sql = await readFile(new URL('../supabase/age_verify_staging.sql', import.meta.url), 'utf8');
const check = await readFile(new URL('../supabase/age_verify_check_staging.sql', import.meta.url), 'utf8');
assert.match(sql, /7703759698107299042/);
assert.doesNotMatch(sql, /\b(?:truncate|delete from|drop table)\b/i);
assert.match(sql, /age_ci_hash/);
assert.match(sql, /service_role/);
assert.match(check, /읽기만/);

const boot = async (ident) => {
  const db = new PGlite();
  await db.exec(`create role anon; create role authenticated; create role service_role bypassrls;
    create schema auth; create table auth.users(id uuid primary key);
    create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
    grant usage on schema auth to authenticated, service_role; grant execute on function auth.uid() to authenticated, service_role;
    create table public.profiles(id uuid primary key references auth.users(id), nickname text);
    create table public.app_flags(key text primary key, enabled boolean not null default false);
    insert into public.app_flags(key, enabled) values ('age_verification_required', false);
    create function public.test_control() returns table(system_identifier text) language sql as $$select '${ident}'::text$$;`);
  return db;
};
const guarded = s => s.replaceAll('pg_catalog.pg_control_system()', 'public.test_control()').replace("notify pgrst, 'reload schema';", '');

let db = await boot('WRONG');
await assert.rejects(db.exec(guarded(sql)), /STOP: .* only/);
await db.exec('rollback');
await db.close();

db = await boot(STAGING);
await db.exec(guarded(sql));
await db.exec(guarded(sql));
const a = crypto.randomUUID(), b = crypto.randomUUID();
const vid = 'identity-verification-aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
const vid2 = 'identity-verification-aaaaaaaa-bbbb-4ccc-8ddd-ffffffffffff';
const hash = 'a'.repeat(64), hash2 = 'b'.repeat(64);
await db.query('insert into auth.users values($1),($2)', [a, b]);
await db.query('insert into public.profiles(id) values($1),($2)', [a, b]);

const asRole = async (role, q, p = []) => {
  await db.exec(`begin; set local role ${role};`);
  try { const r = await db.query(q, p); await db.exec('commit'); return r; }
  catch (e) { await db.exec('rollback'); throw e; }
};

await assert.rejects(asRole('authenticated', 'select public.age_verify_apply($1,$2,$3)', [a, vid, hash]), /permission denied/);
const ok = (await asRole('service_role', 'select public.age_verify_apply($1,$2,$3) s', [a, vid, hash])).rows[0].s;
assert.equal(ok.ok, true); assert.equal(ok.idempotent, false);
const again = (await asRole('service_role', 'select public.age_verify_apply($1,$2,$3) s', [a, vid, hash])).rows[0].s;
assert.equal(again.idempotent, true);
await assert.rejects(asRole('service_role', 'select public.age_verify_apply($1,$2,$3)', [b, vid, hash2]), /identity already used/);
await assert.rejects(asRole('service_role', 'select public.age_verify_apply($1,$2,$3)', [b, vid2, hash]), /identity already used/);
const other = (await asRole('service_role', 'select public.age_verify_apply($1,$2,$3) s', [b, vid2, hash2])).rows[0].s;
assert.equal(other.ok, true);

const row = (await db.query('select age_verified, age_ci_hash, nickname from public.profiles where id=$1', [a])).rows[0];
assert.equal(row.age_verified, true);
assert.equal(row.age_ci_hash, hash);
assert.equal(row.nickname, null); // no extra PII columns invented on the row beyond hash/id

const chk = (await db.query(check.replace('pg_catalog.pg_control_system()', 'public.test_control()'))).rows[0];
assert.equal(chk.is_staging, true);
assert.equal(chk.ci_hash_col, true);
assert.equal(chk.apply_fn, true);
assert.equal(chk.flag_required, false);

await db.close();
console.log('Age-verify SQL: staging guard, idempotent, CI hash unique, service_role only OK');
process.exit(0);
