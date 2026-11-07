# 보안 2단계 — 튜토리얼·스토리·타워 세션 정산

2026-11-07 KST. **로컬 구현·오프라인 검증만 완료. 실제 DB 적용/배포/운영 승인 아님.**

## 보장과 한계

이번 단계는 소유자가 지정한 **실용적 plausibility 검증**이다. 전체 결정론적 전투 replay는 구현하지 않았다.
서버가 발급한 계정별 세션, 보유 인재/스테이지 스냅샷, 입장 순서, 최소 시간, 턴/마나/EXP 입력 상한,
서버 보상표, 원자적 1회 정산을 사용한다. 새 클라이언트에 기존 완료 RPC로 돌아가는 fallback은 없다.

**세션/seed가 실제 전투 수행을 증명하지는 않는다.** 기다린 뒤 그럴듯한 승리·턴·마나·스킬·처치/블록 수를
조작하면 통과할 수 있다. 별·EXP·전투 미션에도 이 위험이 남는다. 서버 replay/서버 전투 엔진으로의 이관은
추가 강화 작업이다. “전투 조작 완전 차단”으로 안내하지 않는다. seed는 재시도에 안정적인 감사용 값이며,
브라우저의 모든 RNG를 구동하거나 재생 검증에 쓰지 않는다.

## staging 적용 순서 — 소유자 실행

1. 테스트 프로젝트 `cuyqchmdcnsgzkwyclji` 선택을 화면에서 직접 확인한다. 운영 실행 금지.
2. `supabase/security_phase1_preflight.sql` (읽기 전용)로 기존 함수/권한 차이를 확인한다.
3. **기존 DB**: `supabase/security_phase1_rewards.sql` → `supabase/security_phase2_clears.sql` 순서.
   1단계가 이미 정상 적용됐으면 2단계만 실행한다. 전체 파일이 한 트랜잭션이고 재실행 가능하다.
   잔액·과거 수령·진행도를 초기화하거나 SQL 설치 자체로 보상을 지급하지 않는다.
4. 새 프런트엔드를 같은 버전으로 배포한다. SQL을 먼저 적용하면 구 클라이언트의 완료 요청은 거절된다.
   서비스 중간 전환을 피하고 열린 전투는 재시작한다. 실제 배포는 별도 승인 후 소유자가 진행한다.
5. 아래 smoke test와 읽기 전용 점검을 한다. 실패 트랜잭션이면 `ROLLBACK;` 후 원인을 확인한다.

**비어 있는 신규 테스트 DB**만 `supabase/staging/01_install.sql`~`12_install.sql`을 같은 커밋의
번호순 전체 파일로 설치할 수 있다. 새 bundle에는 1→2단계가 포함된다. 기존 10개짜리 bundle을 설치한
DB에 새 bundle을 섞거나 재설치하지 않는다. 기존 DB에는 위의 개별 migration만 사용한다.
오래된 기능별 SQL 또는 1단계만 나중에 재실행하면 새 정산/권한을 덮어쓴다. 항상 1→2 순서를 지킨다.

## 다시 지급하는 항목

| 항목 | 근거 / 지급 방식 |
|---|---|
| 특강 튜토리얼 1~3 | 로그인 세션 순서대로 완료: 1단계 소환권 10, 2단계 젬 100, 3단계 젬 300. finish에서 자동 지급 |
| 스토리 페이즈 | 기존 서버 인재/포인트/EXP/플레이어 XP/드롭 정산을 비공개화하고 finish 내부에서만 호출 |
| 챕터 소환권·젬 | 해당 챕터의 **모든 페이즈를 새 세션으로 인정**받으면 소환권 10 + 서버 설정 젬(현재 50). 기존 지급 기록은 중복 차단 |
| 별 보상 | 서버가 해당 세션의 제한 마나·턴 설정과 bounded 결과로 별을 계산. 새 receipt 별 합계만 milestone 자격에 사용 |
| 일일·주간 전투 미션 | `win/story/tower/skill`을 새 서버 세션 이벤트로 계산하고 기존 claim 버튼에서 수령. 타워 도전은 start 때 1회, 승리·스킬은 finish 때 갱신 |
| 타워 수동·소탕 | 순차 층별 세션. 서버 타워 보상/재화 표로 1회 지급. 소탕도 층마다 start→시뮬레이션→finish, 보스층은 수동 |
| 관련 업적·획득 도감 | 새 챕터·별·타워·스킬 근거로 관련 업적 재개. 실제 새 스토리 보상 인재만 획득 도감에 추가 |
| 유료 스토리 소탕 | 해당 페이즈의 새 인정 receipt가 있어야 기존 행동력 소비 소탕 허용 |

**계속 보류**: PvP 랭크·시즌(3단계), 레이드·길드전(4단계), 일반 아케이드와 그 전투 업적/MVP(후속 단계),
아케이드가 포함된 일일·주간 `all`. 검증 안 된 플레이어/인재 레벨 관련 업적도 1단계 보류 상태를 유지한다.
출석·상점·기존 1단계 안전한 비전투 보상은 유지한다. 일반 아케이드와 특강 튜토리얼은 별개다.

## 과거 자료 — 삭제도 자동 인증도 하지 않음

- 설치 시 `battle_legacy_access_v2`에 기존 스토리 cleared / tower best·paid를 **접근 허용용**으로만 동결한다.
  기존 계정이 다음 페이즈/층으로 갈 수 있지만, 이 기록 자체로 새 별·챕터·미션·업적 보상은 받지 않는다.
  과거 진행이 조작됐을 가능성까지 소급 판정하지는 않는다.
- 기존 튜토리얼 claim은 유지하고 다음 튜토리얼 입장에 인정한다. guest localStorage 클리어를 로그인 보상으로
  복사하지 않는다. 비로그인 체험 후 보상은 로그인한 상태에서 다시 플레이한다.
- 1단계 중 보류된 챕터/별은 새 세션으로 해당 페이즈들을 다시 완료해야 지급된다. 자동 일괄 소급 지급 없음.
- 타워는 설치 시의 **paid baseline보다 높은 층**을 인정받으면 지급한다. phase-1 held floor를 다시 플레이하면
  받을 수 있고, 더 높은 층을 먼저 정산해도 낮은 미지급 층이 사라지지 않는다. 타워 목록에 과거 층도 표시하고 `미지급` 층의 재도전을 허용한다. baseline 이하 층은 재지급하지 않는다.
- 과거 인재/포인트/EXP/업적 수령 기록은 유지한다. 이미 받은 첫 클리어 인재를 replay로 또 주지 않는다.

## 프로토콜 / 입력 검증

- `battle_session_start_v2(p_mode,p_target,p_party,p_request)` → UUID 세션/seed/만료/서버 스냅샷.
  모드 `tutorial`, `story`, `tower`, `tower_sweep`. target은 `1` / `1:1` / `normal:1` 등 canonical 문자열.
  클라이언트 request UUID는 같은 인자로 재시도하면 같은 세션이며 다른 인자 재사용은 거절한다.
- 로그인 본인만 start/finish/status/abort 가능. 계정당 active 세션 1개; 새로운 시작은 이전 세션을 닫고
  스토리 행동력 예약을 한 번만 환불한다. stage seed는 abort/만료 후 재시작에도 동일하다.
- 실제 보유 UID/강화/레벨/리더, 합법 guest·길드 대여, 필수/제외 인재, 최대 출전 수(타워 5명), 속성·등급·비용 등
  스테이지 출전 제한을 검사한다. 스토리 데이터 241개 변형은 `tools/build_phase2_catalog.mjs`로 생성·동기화 검사한다.
- 기존 계정 레벨·행동력·타워 요일/일일 제한을 유지한다. 튜토리얼/스토리 최소 3초, 타워 수동 5초,
  층별 소탕 1초. 클라이언트는 빠른 정상 전투일 때 정산만 최소 시간까지 기다리고 전투 조작은 바꾸지 않는다.
- 세션 유효기간 2시간, KST 하루 계정당 발급 최대 500개. 정산 이벤트에도 일일 상한을 둔다.
- `battle_session_finish_v2(p_session,p_report)`는 본인 active 토큰, 시간, JSON 크기/키/형식, 턴/스킬 상한,
  반턴-내 턴 관계, 종료 사유, 선택했던 본인 인재의 EXP만 허용한다. 제한 마나는 서버 시작량 이하.
  일반 전투 최대 40 반턴(스테이지 override), 특강 안전 한계 400. 0턴 소탕/튜토리얼 승리와 포기 승리를 거절한다.
  필드 배치 패시브 때문에 스토리·수동 타워의 0턴 승리는 허용하되 0번의 내 턴에서 스킬 사용 보고는 거절한다. EXP의 실제 소환 여부는 replay 없이는 증명하지 못한다.
- 세션/계정/gem advisory 및 row lock, unique receipt, 보상 지급·진행·미션 이벤트·완료 캐시를 한 트랜잭션에 둔다.
  같은 제출 재시도는 저장된 결과를 반환하고 다른 결과 재사용은 거절한다. 만료 finish는 환불 후 `ok:false` 반환.
- 상태조회 `battle_session_status_v2`와 `battle_session_abort_v2` 제공. 화면 저장 실패 시 같은 세션/결과를
  다시 저장하며 새 전투나 로컬 보상을 생성하지 않는다. 새로고침으로 결과 telemetry를 잃으면 다시 플레이한다.
- 옛 `story_start/complete`, `story_set_stars`, `tower_*`, `quest_*` 완료/소탕 경로는 모든 오버로드의 API 실행권한 회수.
  서버 내부 원본은 private helper로만 보존. 새 세션/보상/이벤트 테이블은 RLS + public/anon/authenticated 직접 접근 금지.

## 중단 / 점검

문제가 생기면 소유자가 SQL Editor에서 해당 모드 발급·신규 정산을 중단한다(테이블은 클라이언트 접근 불가):

```sql
update public.battle_policy_v2 set enabled=false where mode in ('tutorial','story','tower');
-- 검토 후 필요한 모드만 true. migration 재실행은 이 값을 true로 바꾸지 않는다.
```

이미 완료한 같은 결과 재조회는 유지하며, 보류 이전 잔액/영수증을 지우지 않는다. 옛 SQL/프런트로 되돌려
우회 완료를 열지 않는다. owner 운영 도구·DB 소유권 자체는 이 경계의 보호 대상이 아니다.

읽기 전용 점검(민감한 snapshot/report나 계정 원문을 외부로 전달할 필요 없음):

```sql
select mode, enabled from public.battle_policy_v2 order by mode;
select mode,status,count(*) from public.battle_sessions_v2 group by 1,2;
select reward_kind,count(*) from public.reward_claims group by 1 order by 1;
select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.prokind='f' and
 (left(p.proname,1)='_' or p.proname in ('story_complete_phase','story_set_stars','tower_complete','quest_complete'))
 and pg_get_function_result(p.oid)<>'trigger'
 and (has_function_privilege('authenticated',p.oid,'execute') or has_function_privilege('anon',p.oid,'execute'));
-- 마지막 조회는 0행이어야 한다 (trigger-return helper 제외).
```

수동 smoke: 로그인 특강 1→3 보상, 스토리 1개 챕터 전 페이즈→10 tickets+젬, 별 milestone,
일일 story/win 미션, 타워 다음층/소탕/보스/요일 제한, 승리 저장 네트워크 재시도, 로그아웃·타 계정 토큰,
다른 탭 새 전투 후 옛 결과 거절, abort·만료 행동력 1회 환불을 staging에서 확인한다.

## 오프라인 검증 / 잔여 운영 위험

```bash
node tools/build_phase2_catalog.mjs --check
node tools/build_staging_sql.mjs && node tools/build_staging_parts.mjs
npm run check:staging && npm run test:staging && npm run build:staging
npm run test:security:phase1 && npm run test:security:phase2
```

PGlite는 빈 DB 설치·Supabase 기본 ACL 유무, 함수 재컴파일, 2계정, 재실행·잔액 보존, tutorial 지급,
챕터·별·미션·획득 도감, held tower catch-up, 잘못된 입력/순서/시간/소유권, 레거시/열 권한,
환불·만료·서버 중단·상한 및 payout 중간 오류의 전체 롤백을 검사한다.
PGlite는 단일 WASM 연결이며 실제 다중 연결 PostgreSQL 경쟁/지연·OAuth·모바일 UI를 검증하지 않는다.
실제 staging 부하/다중 탭·동시 claim, reward baseline 검토는 소유자의 적용 전후 확인 항목이다.
새 Tailwind 클래스가 없어 css/tw.css는 변경하지 않는다.
