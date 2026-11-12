// 첫 로그인 동의 SQL: staging/production 가드·반복 실행·버전 확인·만14세 필수·마케팅 변경 기록·RLS(본인만) — 2026-11-12
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { PGlite } from '@electric-sql/pglite';
const ids = ['7703759698107299042', '7692130048193495360'];
const files = await Promise.all(['staging', 'production'].map(env => readFile(new URL(`../supabase/consent_${env}.sql`, import.meta.url), 'utf8')));
const body = s => s.slice(s.indexOf('-- ===== 첫 로그인 동의 기록'));
assert.equal(body(files[0]), body(files[1]), 'staging/production bodies identical');
const js = await readFile(new URL('../js/consent.js', import.meta.url), 'utf8');
const ver = (/TERMS_VERSION = '([^']+)'/.exec(js) || [])[1], pver = (/PRIVACY_VERSION = '([^']+)'/.exec(js) || [])[1];
assert.match(files[0], new RegExp(`'terms', '${ver}', 'privacy', '${pver}'`), 'SQL versions match js/consent.js');
for (const [i, sql] of files.entries()) {
  assert.match(sql, new RegExp(`is distinct from '${ids[i]}'`)); assert.doesNotMatch(sql, /\b(?:truncate|delete from|drop table|update public\.(?!user_consents))\b/i);
  const db = new PGlite();
  await db.exec(`create role anon; create role authenticated; create schema auth; create table auth.users(id uuid primary key);
    create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
    grant usage on schema auth to authenticated; grant execute on function auth.uid() to authenticated;`);
  const guarded = sql.replace('pg_catalog.pg_control_system()', 'public.test_control()').replace("notify pgrst, 'reload schema';", '');
  await db.exec(`create function public.test_control() returns table(system_identifier text) language sql as $$select 'WRONG'::text$$;`);
  await assert.rejects(db.exec(guarded), /STOP: .* only/); await db.exec('rollback');
  await db.exec(`create or replace function public.test_control() returns table(system_identifier text) language sql as $$select '${ids[i]}'::text$$;`);
  await db.exec(guarded); await db.exec(guarded);   // idempotent
  const a = crypto.randomUUID(), b = crypto.randomUUID(); await db.query('insert into auth.users values($1),($2)', [a, b]);
  const as = async (uid, q, p = []) => { await db.exec(`begin; set local role authenticated; set local request.jwt.claim.sub = '${uid}';`); try { return await db.query(q, p); } finally { await db.exec('rollback'); } };
  const asKeep = async (uid, q, p = []) => { await db.exec(`begin; set local role authenticated; set local request.jwt.claim.sub = '${uid}';`); try { const r = await db.query(q, p); await db.exec('commit'); return r; } catch (e) { await db.exec('rollback'); throw e; } };
  let st = (await as(a, 'select public.consent_status() s')).rows[0].s; assert.equal(st.current, false); assert.equal(st.record, null); assert.equal(st.terms_current, ver);
  await assert.rejects(asKeep(a, "select public.consent_accept('old', $1, true, false)", [pver]), /version mismatch/);
  await assert.rejects(asKeep(a, 'select public.consent_accept($1, $2, false, false)', [ver, pver]), /age14 required/);
  st = (await asKeep(a, "select public.consent_accept($1, $2, true, true, 'UA test') s", [ver, pver])).rows[0].s;
  assert.equal(st.current, true); assert.equal(st.record.marketing, true);
  st = (await asKeep(a, 'select public.consent_set_marketing(false) s')).rows[0].s; assert.equal(st.record.marketing, false);
  st = (await asKeep(a, 'select public.consent_set_marketing(false) s')).rows[0].s;   // 같은 값이면 새 행 없음
  assert.equal((await db.query('select count(*)::int n from user_consents where user_id=$1', [a])).rows[0].n, 2);
  await assert.rejects(asKeep(b, 'select public.consent_set_marketing(true)'), /consent required/);
  assert.equal((await as(b, 'select count(*)::int n from user_consents')).rows[0].n, 0, 'RLS: cannot read others');
  assert.equal((await as(a, 'select count(*)::int n from user_consents')).rows[0].n, 2, 'RLS: reads own');
  await assert.rejects(as(a, 'update user_consents set marketing = true'), /permission denied/);
  await assert.rejects(as(a, 'delete from user_consents'), /permission denied/);
  await assert.rejects(as(b, 'insert into user_consents(user_id, terms_version, privacy_version, age14) values ($1, $2, $3, true)', [a, ver, pver]), /row-level security/);
  await as(b, 'insert into user_consents(user_id, terms_version, privacy_version, age14) values ($1, $2, $3, true)', [b, ver, pver]);   // direct own insert ok
  await assert.rejects(db.exec(`begin; set local role anon; select public.consent_status();`), /permission denied/); await db.exec('rollback');
  await db.close();
}
console.log(`Consent SQL: staging/prod guards, idempotent, version ${ver}, age14 required, marketing history, RLS own-only, no update/delete OK`);
