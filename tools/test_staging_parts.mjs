// 네트워크/실제 계정 없이 분할 SQL 설치·재실행·오류 복구를 검증.
import assert from 'node:assert/strict';
import { readFile, readdir } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { PGlite } from '@electric-sql/pglite';
import { buildParts, DB_ID_PLACEHOLDER, STAGING_SYSTEM_ID, TARGET_REF, MAX_PART_BYTES } from './build_staging_parts.mjs';
import { splitStatements, stripLeadingComments } from './sql_statements.mjs';
const dir = new URL('../supabase/staging/', import.meta.url);
const manifest = JSON.parse(await readFile(new URL('manifest.json', dir), 'utf8'));
assert.equal(STAGING_SYSTEM_ID, '7703759698107299042');
assert.equal(manifest.systemId, STAGING_SYSTEM_ID);
assert.equal(typeof manifest.systemId, 'string');
assert.equal(manifest.systemId.length, 18);
assert.equal('productionSystemId' in manifest, false);
const sourceParts = await buildParts(manifest.systemId);
assert.deepEqual((await readdir(dir)).filter(n => n.endsWith('.sql')).sort(), sourceParts.map(p => p.name));
for (const [index, part] of sourceParts.entries()) {
  const sql = await readFile(new URL(part.name, dir), 'utf8');
  assert.equal(sql, part.sql, part.name + ': 재생성 필요');
  assert.ok(sql.includes("expected_db_id text := '7703759698107299042'"), '18자리 확인 값이 정확히 유지되어야 함');
  assert.ok(!sql.includes('production_db_id'));
  assert.ok(Buffer.byteLength(sql) < MAX_PART_BYTES);
  assert.equal(createHash('sha256').update(sql).digest('hex'), manifest.parts[index].sha256);
  splitStatements(sql); // 인용/함수 중간에서 끊기면 실패
}
// 달러 인용·중첩 주석·식별자·E 문자열·위치 인자를 문장 경계로 오인하지 않음.
const samples = [
  `select ';'; select 2;`,
  `do $$begin perform ';'; perform 1; end$$; select 2;`,
  `do $a$begin perform $$;$b$;$$; end$a$; select $1;`,
  `/* ; /* ; */ ; */ select 'a'';b'; -- ;\nselect 2;`,
  String.raw`select E'a\';b'; select ";";`,
];
for (const sql of samples) assert.equal(splitStatements(sql).length, 2);
assert.throws(() => splitStatements('do $$begin;'), /종료되지/);
assert.throws(() => splitStatements('select 1'), /세미콜론/);
assert.equal(stripLeadingComments('/* a /* b */ c */ -- x\n select 1;'), 'select 1;');
const setup = defaults => `
create role anon; create role authenticated;
create schema auth;
create table auth.users (id uuid primary key, email text, raw_user_meta_data jsonb default '{}', raw_app_meta_data jsonb default '{}', created_at timestamptz default now(), last_sign_in_at timestamptz, email_confirmed_at timestamptz);
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
create function auth.jwt() returns jsonb language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $$;
grant usage on schema auth, public to anon, authenticated;
${defaults ? 'alter default privileges in schema public grant all on tables to anon, authenticated; alter default privileges in schema public grant all on sequences to anon, authenticated; alter default privileges in schema public grant execute on functions to anon, authenticated;' : ''}
`;
const reject = async (db, sql, pattern) => { await assert.rejects(db.exec(sql), pattern); await db.exec('rollback'); };
const noChanges = async db => {
  assert.equal((await db.query("select to_regnamespace('vr_staging_install')::text n")).rows[0].n, null);
  assert.equal((await db.query("select count(*)::int n from pg_tables where schemaname='public'")).rows[0].n, 0);
};
async function snapshot(db) {
  const functions = (await db.query("select oid::text, pg_get_functiondef(oid) ddl from pg_proc where pronamespace='public'::regnamespace order by oid")).rows;
  const tables = (await db.query("select tablename from pg_tables where schemaname='public' order by tablename")).rows;
  const data = [];
  for (const t of tables) data.push((await db.query(`select md5(coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text)::text,'')) hash from public."${t.tablename}" t`)).rows[0].hash);
  const ledger = (await db.query('select * from vr_staging_install.parts order by part_no')).rows;
  const usage = (await db.query("select has_schema_privilege('anon','public','usage') anon, has_schema_privilege('authenticated','public','usage') authenticated")).rows;
  return { functions, data, ledger, usage };
}
for (const defaults of [false, true]) {
  const db = new PGlite();
  try {
    await db.exec(setup(defaults));
    const systemId = (await db.query('select system_identifier::text id from pg_catalog.pg_control_system()')).rows[0].id;
    const parts = await buildParts(systemId);
    const unbound = await buildParts(DB_ID_PLACEHOLDER);
    for (const part of unbound) await reject(db, part.sql, /고유번호가 아직/);
    for (const part of parts) {
      await reject(db, part.sql.replace(`confirmed_ref text := '${TARGET_REF}'`, "confirmed_ref text := 'htarwisgkkphutxxnuak'"), /운영 DB 금지/);
      await reject(db, part.sql.replace(`expected_db_id text := '${systemId}'`, "expected_db_id text := '2222222222222222222'"), /현재 접속한 DB/);
    }
    // 실제 배포 파일은 테스트 Supabase 번호에 고정: 다른 WASM DB에서는 그대로 거부.
    assert.notEqual(systemId, STAGING_SYSTEM_ID);
    for (const part of sourceParts) await reject(db, part.sql, /현재 접속한 DB/);
    const readStatement = 'select system_identifier::text into actual_db_id from pg_catalog.pg_control_system();';
    await reject(db, parts[0].sql.replace(readStatement, "raise insufficient_privilege using message = '가상 조회 권한 오류';"), /DB 식별 조회 권한/);
    await reject(db, parts[0].sql.replace(readStatement, 'actual_db_id := null;'), /현재 접속한 DB/);
    await noChanges(db);
    await reject(db, parts[1].sql, /앞 번호/);
    await noChanges(db);
    const broken = parts[0].sql.replace('  insert into vr_staging_install.parts(', '  perform 1 / 0;\n  insert into vr_staging_install.parts(');
    await reject(db, broken, /division by zero/);
    await noChanges(db);
    await db.exec('create table public.existing_data(id integer)');
    await reject(db, parts[0].sql, /새 테스트 프로젝트/);
    await db.exec('drop table public.existing_data');
    for (const [index, part] of parts.entries()) {
      await db.exec(part.sql);
      if (index < parts.length - 1) {
        assert.equal((await db.query("select has_schema_privilege('anon','public','usage') allowed")).rows[0].allowed, false, '설치 중 API 차단');
      }
      const before = await snapshot(db);
      await db.exec(part.sql);
      assert.deepEqual(await snapshot(db), before, part.name + ': 즉시 재실행 시 내용 변경');
    }
    const final = await snapshot(db);
    assert.equal(final.functions.length, 578);
    assert.equal(final.ledger.length, parts.length);
    assert.equal(final.usage[0].anon, true);
    assert.equal((await db.query('select count(*)::int n from auth.users')).rows[0].n, 0);
    assert.equal((await db.query("select count(*)::int n from pg_class where relnamespace='public'::regnamespace and relkind='r' and not relrowsecurity")).rows[0].n, 0);
    assert.deepEqual((await db.query("select has_schema_privilege('anon','vr_staging_install','usage') a, has_table_privilege('authenticated','vr_staging_install.parts','select') b")).rows[0], { a: false, b: false });
    for (const part of parts.toReversed()) await db.exec(part.sql);
    assert.deepEqual(await snapshot(db), final, '완료 후 역순 재실행으로 최신 함수/설정이 바뀜');
    const mixed = parts[0].sql.replaceAll(parts[0].bundle, '0'.repeat(64));
    await reject(db, mixed, /다른 버전/);
    assert.deepEqual(await snapshot(db), final);
    // 설치 뒤 생긴 가상 계정/진행 자료도 재실행으로 초기화되거나 보상을 중복 받지 않음.
    await db.exec("insert into auth.users(id,email,raw_user_meta_data) values ('11111111-1111-4111-8111-111111111111','parts@example.invalid','{\"name\":\"가상계정\"}'); update public.player_wallet set gem_paid=37 where user_id='11111111-1111-4111-8111-111111111111'");
    const withUser = await snapshot(db);
    for (const part of parts) await db.exec(part.sql);
    assert.deepEqual(await snapshot(db), withUser, '설치 후 계정/진행 자료가 재실행으로 변경됨');
    console.log(`분할 ${parts.length}개 설치·각 파일/전체 재실행·순서/버전/운영/다른 DB 차단·실패 롤백·설치 중 API 차단: OK (기본 권한 ${defaults ? '허용' : '없음'})`);
  } finally { await db.close(); }
}
console.log(`파일당 최대 ${Math.max(...sourceParts.map(p => Buffer.byteLength(p.sql)))}바이트; 실제 DB 고유번호 ${manifest.systemId === DB_ID_PLACEHOLDER ? '미등록 — 실서버 실행 차단 상태' : '등록됨'}`);
