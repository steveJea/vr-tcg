// 실제 Supabase/네트워크를 쓰지 않는 빈 PostgreSQL(WASM) 설치 검사.
import assert from 'node:assert/strict';
import { readFile, readdir } from 'node:fs/promises';
import { PGlite } from '@electric-sql/pglite';
import { buildSql, INSTALL_ACK } from './build_staging_sql.mjs';
const sql = await readFile(new URL('../supabase/staging_install.sql', import.meta.url), 'utf8');
assert.equal(sql, await buildSql(), '생성 SQL과 소스가 다릅니다. node tools/build_staging_sql.mjs');
const manifest = JSON.parse(await readFile(new URL('./staging_sql_sources.json', import.meta.url), 'utf8'));
const sources = (await readdir(new URL('../supabase/', import.meta.url))).filter(f => f.endsWith('.sql') && f !== 'staging_install.sql').sort();
assert.deepEqual([...manifest.ordered, ...Object.keys(manifest.excluded), 'schema.sql'].sort(), sources, '설치 순서표에서 빠지거나 중복된 SQL');
const defaults = process.argv.includes('--supabase-defaults');
const db = new PGlite();
await db.exec(`
create role anon; create role authenticated;
create schema auth;
create table auth.users (id uuid primary key, email text, raw_user_meta_data jsonb default '{}', raw_app_meta_data jsonb default '{}', created_at timestamptz default now(), last_sign_in_at timestamptz, email_confirmed_at timestamptz);
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
create function auth.jwt() returns jsonb language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $$;
grant usage on schema auth to anon, authenticated;
-- Supabase public 스키마의 기본 권한 재현 (권한 회수도 검사).
grant usage on schema public to anon, authenticated;
${defaults ? 'alter default privileges in schema public grant all on tables to anon, authenticated; alter default privileges in schema public grant all on sequences to anon, authenticated; alter default privileges in schema public grant execute on functions to anon, authenticated;' : ''}
`);
try {
  await assert.rejects(db.exec(sql), /STOP:/);
  await db.exec('rollback');
  const wrongProject = sql.replace(`confirmed_ref text := '${INSTALL_ACK}'`, "confirmed_ref text := 'htarwisgkkphutxxnuak'");
  await assert.rejects(db.exec(wrongProject), /STOP:/);
  await db.exec('rollback');
  // 확인 문자열 선언만 교체하고 비교 대상은 유지. 실제 계정/키는 사용하지 않음.
  const allowed = sql.replace(`confirmed_ref text := '${INSTALL_ACK}'`, "confirmed_ref text := 'abcdefghijklmnopqrst'");
  await db.exec(allowed);
  console.log(`빈 DB 전체 설치 (프로젝트 기본 권한 ${defaults ? '허용' : '없음'}): OK`);
  // 전방 참조를 허용해 설치한 함수들도 최종 스키마 위에서 다시 검증.
  const defs = await db.query(`select p.oid, p.proname, pg_get_functiondef(p.oid) ddl from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prokind='f' and not exists (select 1 from pg_depend d where d.objid=p.oid and d.deptype='e')`);
  for (const fn of defs.rows) {
    try { await db.exec(fn.ddl); }
    catch (e) { throw new Error(`최종 함수 검증 실패: ${fn.proname}: ${e.message}`, { cause: e }); }
  }
  console.log(`최종 함수 ${defs.rows.length}개 재컴파일: OK`);
  const weak = await db.query(`select c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r' and not c.relrowsecurity`);
  assert.deepEqual(weak.rows, [], 'RLS가 없는 테이블');
  const exposed = await db.query(`select p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosecdef and left(p.proname, 1) = '_' and pg_get_function_result(p.oid) <> 'trigger' and (has_function_privilege('anon',p.oid,'execute') or has_function_privilege('authenticated',p.oid,'execute'))`);
  assert.deepEqual(exposed.rows, [], '앱에서 직접 호출 가능한 내부 서버 함수');
  const userCount = await db.query('select count(*)::int n from auth.users');
  assert.equal(userCount.rows[0].n, 0, '설치 중 사용자 자료가 들어감');
  // 재실행/기존 DB 거부: 덮어쓰지 않아야 함.
  await assert.rejects(db.exec(allowed), /STOP:/);
  await db.exec('rollback');
  console.log('RLS·내부 함수 권한·개인정보 없음·기존 DB 설치 거부: OK');
  // 아래 계정은 인터넷/운영 DB와 무관한 일회용 가상 자료.
  const me = '11111111-1111-4111-8111-111111111111';
  const other = '22222222-2222-4222-8222-222222222222';
  await db.query(`insert into auth.users(id,email,raw_user_meta_data) values ($1,'one@example.invalid','{"name":"테스트하나"}'), ($2,'two@example.invalid','{"name":"테스트둘"}')`, [me, other]);
  await db.exec(`set role authenticated; select set_config('request.jwt.claim.sub', '${me}', false)`);
  const ownProfiles = await db.query('select id from profiles');
  assert.deepEqual(ownProfiles.rows, [{ id: me }], '다른 계정 프로필 비공개');
  await db.query('select public.player_status()');
  await db.query('select public.wallet_status()');
  await db.query('select public.gem_status()');
  const admin = await db.query('select public.admin_check() data');
  assert.equal(admin.rows[0].data.admin, false);
  await assert.rejects(db.query(`select public.admin_list_users()`), /forbidden/);
  await assert.rejects(db.query(`update public.player_wallet set gem_paid=1000000 where user_id=$1`, [me]), /permission denied/);
  await db.exec('reset role; set role anon');
  await assert.rejects(db.query('select * from player_wallet'), /permission denied/);
  await db.exec('reset role');
  console.log('가상 2계정 본인행 조회·일반 계정 관리자 차단·지갑 직접 변경 차단: OK');

} finally { await db.close(); }
