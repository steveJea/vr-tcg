// 소스 SQL을 수정하지 않고, 빈 테스트 DB에만 쓰는 설치본을 재생성.
import { readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
const root = new URL('../', import.meta.url);
const read = name => readFile(new URL('supabase/' + name, root), 'utf8');
const manifest = JSON.parse(await readFile(new URL('./staging_sql_sources.json', import.meta.url), 'utf8'));
export const INSTALL_ACK = 'REPLACE_WITH_TEST_PROJECT_REF';
export async function buildSql() {
  const base = (await read('schema.sql')).split('-- ===== 스토리 모드')[0].split('\n').slice(7).join('\n');
  const sections = [base + `\n-- Supabase 프로젝트별 기본 권한 차이에 기대지 않는 최소 직접 접근.\ngrant select on public.profiles to authenticated;\ngrant select, insert, update on public.saves to authenticated;\ngrant select, insert on public.matches to authenticated;\n`];
  for (const name of manifest.ordered) {
    let sql = await read(name);
    if (name === 'security_phase3_pvp.sql') {
      // Standalone upgrade is fixed to staging's cluster. Clean installers already
      // enforce EMPTY DB here, and split installers also enforce the cluster guard.
      sql = sql.replace(/do \$phase3_staging_guard\$[\s\S]*?end \$phase3_staging_guard\$;/, '-- Standalone phase3 guard: enforced by installer entry guard instead.');
    }
    if (name === 'security_phase4_raid_guildwar.sql') sql = sql.replace(/do \$phase4_staging_guard\$[\s\S]*?end \$phase4_staging_guard\$;/, '-- Phase4 cluster guard is enforced by installer outer guard.');
    if (name === 'level_unlocks_staging.sql') sql = sql.replace(/do \$guard\$[\s\S]*?end \$guard\$;/, '-- Unlock cluster guard is enforced by installer outer guard.');
    if (name === 'card_id_remap.sql') {
      // 이 저장소의 카드 ID는 이미 변경 완료. 기존 데이터/함수 일괄 치환은 실행하지 않음.
      const alias = sql.slice(sql.indexOf('create table if not exists public.card_id_alias'), sql.indexOf('-- 글자 안의 옛 ID'));
      const npc = sql.match(/create or replace function public\._war_npc_deck\([\s\S]*?\$\$\s*;/)?.[0];
      if (!npc) throw new Error('카드 ID 설치 구간을 확인하세요');
      sql = alias + '\n' + npc;
    }
    // 여러 소스의 바깥 트랜잭션을 한 트랜잭션으로 묶음. 함수 내부 BEGIN은 세미콜론이 없어 매칭되지 않음.
    sql = sql.replace(/^(begin|commit);[ \t]*$/gmi, '-- 설치본의 단일 트랜잭션에 포함');
    sections.push(`\n-- ===== SOURCE: ${name} =====\n${sql}`);
  }
  const header = `-- ⚠ 테스트 전용 신규 설치. 운영 프로젝트에서는 절대 실행하지 마세요.\n-- tools/build_staging_sql.mjs 로 생성. 수동 편집 대신 소스/순서표를 수정하고 재생성.\n-- 운영 유저·세이브·결제·우편 자료를 복사하지 않음. 보안 1단계 지급 차단 포함, 전투 검증 완료 아님.\n-- 먼저 docs/STAGING.md를 읽고, 아래 확인 문자열을 새 테스트 프로젝트 ID로 바꾸세요.\n\nbegin;\ndo $staging_guard$\ndeclare confirmed_ref text := '${INSTALL_ACK}';\nbegin\n  if confirmed_ref = 'htarwisgkkphutxxnuak'\n     or confirmed_ref !~ '^[a-z0-9]{20}$' then\n    raise exception 'STOP: 새 테스트 프로젝트 ID를 확인 문자열에 입력하세요. 운영 DB 금지.';\n  end if;\n  if exists (select 1 from auth.users) or exists (\n    select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace\n    where n.nspname = 'public' and c.relkind in ('r','p')\n      and not exists (select 1 from pg_depend d where d.objid = c.oid and d.deptype = 'e')\n  ) or exists (\n    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace\n    where n.nspname = 'public'\n      and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')\n  ) then\n    raise exception 'STOP: 사용자/게임 테이블·함수가 없는 새 테스트 프로젝트에서만 실행할 수 있어요.';\n  end if;\nend $staging_guard$;\n\n-- SQL 함수의 앞쪽 참조 허용. 마지막에 카탈로그/실행 검사를 수행합니다.\nset local check_function_bodies = off;\n`;
  return header + sections.join('\n') + `\n-- 공개 게임 설정만 명시적으로 조회 허용 (사용자 자료 아님).\ngrant select on public.story_card_pool, public.story_phase_config, public.story_premium_ur,\n  public.pvp_card_meta, public.pvp_reward_table, public.pvp_tier_table, public.pvp_streak_table,\n  public.dispatch_card_meta, public.dispatch_zones to anon, authenticated;\n-- 설치 완료 (원본 SQL의 사용자 테이블은 처음부터 비어 있어야 함).\nset local check_function_bodies = on;\ndo $staging_verify$\ndeclare f record;\nbegin\n  for f in\n    select pg_get_functiondef(p.oid) ddl from pg_proc p join pg_namespace n on n.oid = p.pronamespace\n    where n.nspname = 'public' and p.prokind = 'f'\n      and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')\n  loop execute f.ddl; end loop;\n  if exists (select 1 from auth.users) then raise exception 'STOP: 설치 중 사용자 자료 발견'; end if;\n  if exists (select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace\n    where n.nspname='public' and c.relkind='r' and not c.relrowsecurity\n      and not exists (select 1 from pg_depend d where d.objid = c.oid and d.deptype = 'e')) then\n    raise exception 'STOP: RLS 없는 테이블 발견';\n  end if;\n  if exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace\n    where n.nspname='public' and p.prosecdef and left(p.proname,1)='_'\n      and pg_get_function_result(p.oid) <> 'trigger'\n      and (has_function_privilege('anon',p.oid,'execute') or has_function_privilege('authenticated',p.oid,'execute'))) then\n    raise exception 'STOP: 외부 호출 가능한 내부 서버 함수 발견';\n  end if;\nend $staging_verify$;\ncommit;\nselect 'staging install complete — 테스트 DB에서만 사용' as result;\n`;
}
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  await writeFile(new URL('supabase/staging_install.sql', root), await buildSql());
  console.log('supabase/staging_install.sql 생성 완료');
}
