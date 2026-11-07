// SQL Editor 크기 제한용 분할본. 운영 데이터/비밀 키/네트워크 접근 없음.
import { writeFile, mkdir } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { buildSql } from './build_staging_sql.mjs';
import { splitStatements, stripLeadingComments } from './sql_statements.mjs';
export const TARGET_REF = 'cuyqchmdcnsgzkwyclji';
export const DB_ID_PLACEHOLDER = 'REPLACE_WITH_STAGING_SYSTEM_IDENTIFIER';
// 형님이 확인한 18자리 값. JS Number로 변환하면 반올림되므로 항상 문자열로 유지.
export const STAGING_SYSTEM_ID = '7703759698107299042';
export const MAX_PART_BYTES = 140000;
const sha = text => createHash('sha256').update(text).digest('hex');
const dir = new URL('../supabase/staging/', import.meta.url);
function quoteStatement(statement) {
  let tag = '$vr_statement$';
  while (statement.includes(tag)) tag = tag.replace('$', '$x');
  return `  execute ${tag}${statement.trim()}${tag};\n`;
}
export async function buildParts(systemId = STAGING_SYSTEM_ID) {
  if (systemId !== DB_ID_PLACEHOLDER && !/^\d{16,20}$/.test(systemId)) throw Error('DB 고유번호 형식을 확인하세요');
  const original = splitStatements(await buildSql());
  const clean = original.map(stripLeadingComments);
  if (clean[0].toLowerCase() !== 'begin;' || !clean[1].startsWith('do $staging_guard$') || clean.at(-2).toLowerCase() !== 'commit;') throw Error('통합 설치본 구조 변경: 검토 필요');
  // 기존 확인 문자열은 실제 DB 식별 수단이 아니므로 분할본에서는 클러스터 고유번호를 추가 대조.
  const oldGuard = clean[1];
  const emptyGuard = 'do $vr_empty_db$\nbegin\n' + oldGuard.slice(oldGuard.indexOf('  if exists (select 1 from auth.users)'), oldGuard.indexOf('end $staging_guard$;')) + 'end $vr_empty_db$;';
  const payload = [emptyGuard, ...original.slice(3, -2)]; // BEGIN·옛 guard·check off·COMMIT·결과 SELECT만 제외
  const groups = [];
  let current = [], bytes = 0;
  for (const statement of payload) {
    const size = Buffer.byteLength(quoteStatement(statement));
    if (size > MAX_PART_BYTES - 14000) throw Error('한 문장이 너무 큼: 함수 내부 분할 금지');
    if (bytes + size > MAX_PART_BYTES - 14000 && current.length) { groups.push(current); current = []; bytes = 0; }
    current.push(statement); bytes += size;
  }
  if (current.length) groups.push(current);
  const bundle = sha(groups.map(group => group.map(quoteStatement).join('')).join('\n-- PART --\n'));
  return groups.map((statements, index) => {
    const number = index + 1, total = groups.length;
    const name = `${String(number).padStart(2, '0')}_install.sql`;
    const body = statements.map(quoteStatement).join('');
    const hash = sha(body);
    const sql = `-- ⚠ 테스트 전용 ${number}/${total}. 운영 실행 금지. 파일 전체를 번호 순서대로 실행.\n-- 대상 프로젝트: ${TARGET_REF}; 운영 htarwisgkkphutxxnuak 금지.\n-- 완료한 파일은 다시 실행해도 건너뜀. 중간 오류는 해당 파일만 되돌아감.\n-- 실제 project_ref는 SQL Editor가 보장해서 제공하지 않음: DB 고유번호를 대조.\n-- 지정 테스트 DB의 식별번호와 일치할 때만 허용. guard 삭제/SET 우회 금지.\n-- docs/STAGING.md 및 supabase/staging/README.md 먼저 확인.\n\nbegin;\ndo $vr_project_guard$\ndeclare\n  confirmed_ref text := '${TARGET_REF}';\n  expected_db_id text := '${systemId}';\n  actual_db_id text;\nbegin\n  if confirmed_ref is distinct from '${TARGET_REF}' or confirmed_ref = 'htarwisgkkphutxxnuak' then\n    raise exception 'STOP: 지정한 테스트 프로젝트만 허용합니다. 운영 DB 금지.';\n  end if;\n  if expected_db_id !~ '^[0-9]{16,20}$' then\n    raise exception 'STOP: 테스트 DB의 실제 고유번호가 아직 등록되지 않았습니다. 안내 문서를 확인하세요.';\n  end if;\n  select system_identifier::text into actual_db_id from pg_catalog.pg_control_system();\n  if actual_db_id is distinct from expected_db_id then\n    raise exception 'STOP: 현재 접속한 DB가 지정된 테스트 DB와 다릅니다. 실행 금지.';\n  end if;\nexception when insufficient_privilege or undefined_function then\n  raise exception 'STOP: DB 식별 조회 권한/기능이 없어 안전하게 중단합니다. guard를 삭제하지 마세요.';\nend $vr_project_guard$;\n\n-- 설치 기록은 API에서 접근할 수 없는 별도 스키마에 저장.\nselect pg_advisory_xact_lock(20261107, 490);\ncreate schema if not exists vr_staging_install;\nrevoke all on schema vr_staging_install from public, anon, authenticated;\ncreate table if not exists vr_staging_install.parts (\n  part_no integer primary key, bundle_hash text not null, part_hash text not null,\n  project_ref text not null, db_id text not null, applied_at timestamptz not null default now()\n);\nalter table vr_staging_install.parts enable row level security;\nrevoke all on vr_staging_install.parts from public, anon, authenticated;\nset local check_function_bodies = off;\n\ndo $vr_install_part$\nbegin\n  if exists (select 1 from vr_staging_install.parts where bundle_hash <> '${bundle}' or project_ref <> '${TARGET_REF}' or db_id <> '${systemId}') then\n    raise exception 'STOP: 다른 버전/DB의 설치 기록입니다. 파일을 섞지 마세요.';\n  end if;\n  if exists (select 1 from vr_staging_install.parts where part_no = ${number}) then\n    if not exists (select 1 from vr_staging_install.parts where part_no = ${number} and part_hash = '${hash}') then\n      raise exception 'STOP: 완료한 파일과 내용이 다릅니다.';\n    end if;\n    raise notice '${name}: 이미 완료, 변경 없이 건너뜀';\n    return;\n  end if;\n  if (select count(*) from vr_staging_install.parts where part_no < ${number}) <> ${number - 1} then\n    raise exception 'STOP: 앞 번호 파일을 먼저 실행하세요 (${name}).';\n  end if;\n  -- 설치 도중에는 클라이언트가 미완성 게임 스키마에 접근하지 못함. 마지막에만 개방.\n  revoke usage on schema public from public, anon, authenticated;\n${body}\n${number === total ? '  grant usage on schema public to public, anon, authenticated;\n' : ''}  insert into vr_staging_install.parts(part_no, bundle_hash, part_hash, project_ref, db_id)\n  values (${number}, '${bundle}', '${hash}', '${TARGET_REF}', '${systemId}');\nend $vr_install_part$;\ncommit;\nselect '${name}: 완료 또는 이미 완료 (${number}/${total})' as result;\n`;
    if (Buffer.byteLength(sql) > MAX_PART_BYTES) throw Error(name + ': 파일 크기 초과');
    return { name, sql, statements, hash, bundle };
  });
}
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  if (process.argv.length > 2) throw Error('명령행으로 DB 식별번호를 바꾸지 마세요. 확인된 상수만 사용합니다');
  const systemId = STAGING_SYSTEM_ID;
  const parts = await buildParts(systemId);
  await mkdir(dir, { recursive: true });
  for (const part of parts) await writeFile(new URL(part.name, dir), part.sql);
  await writeFile(new URL('manifest.json', dir), JSON.stringify({ projectRef: TARGET_REF, systemId, bundle: parts[0].bundle, parts: parts.map(p => ({ file: p.name, bytes: Buffer.byteLength(p.sql), sha256: sha(p.sql) })) }, null, 2) + '\n');
  console.log(`분할 설치본 ${parts.length}개 생성; 최대 ${Math.max(...parts.map(p => Buffer.byteLength(p.sql)))}바이트`);
}
