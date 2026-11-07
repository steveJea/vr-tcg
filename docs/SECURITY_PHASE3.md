# 보안 3단계 — 서버가 재생·확정하는 PvP

2026-11-07 KST. **로컬 구현/오프라인 검증. 실제 DB 적용·함수 배포·push는 하지 않음.**

## 적용 순서 — 소유자가 staging에서만 실행

1. 프로젝트 `cuyqchmdcnsgzkwyclji`를 화면에서 확인. 운영 `htarwisgkkphutxxnuak` 금지.
2. 기존 DB: `security_phase1_preflight.sql` 읽기 전용 확인 → `security_phase1_rewards.sql` →
   `security_phase2_clears.sql` → **`security_phase3_pvp.sql`**.
   1·2단계가 적용된 현재 staging은 **3단계 SQL만** 실행. 파일 전체가 한 트랜잭션이며 재실행 가능.
   `pg_control_system().system_identifier::text = '7703759698107299042'`를 강제한다.
   다른 DB/NULL/권한 오류는 중단. guard 삭제·임의 SET 우회 금지.
3. 같은 커밋의 **Supabase Edge Function `pvp-verify-v3`를 배포**한다.
   예시(소유자 실행): `supabase functions deploy pvp-verify-v3 --project-ref cuyqchmdcnsgzkwyclji`.
   `supabase/config.toml`의 `verify_jwt = true` 유지. `_shared/pvp-engine-v3.mjs`, handler, entrypoint를 함께 배포.
   함수는 runtime의 `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEYS`, `SUPABASE_SECRET_KEYS`를 사용한다.
   legacy `SUPABASE_ANON_KEY`/`SUPABASE_SERVICE_ROLE_KEY`도 지원한다. 키를 SQL/브라우저/명령 인수/로그에 넣지 않는다.
   새 secret key는 `apikey`에만, legacy service-role JWT는 서버의 Authorization에도 전달한다.
4. 같은 버전의 staging 웹 자산을 배포한다. **SQL만으로는 PvP가 재개되지 않는다. 함수까지 필수**다.
   함수 미배포/인증/버전/네트워크 오류는 fail-closed이며 로컬 승리를 지급 근거로 사용하지 않는다.
   점검 시간에 전환하고 진행 중인 옛 전투는 끝낸 뒤 적용한다. 옛 attempt는 승격/소급 지급하지 않는다.
   서버/SQL/브라우저 버전이 맞지 않으면 시작 전에 거절한다. 이미 발급된 구버전 세션은 1시간/시즌 말에 만료한다.
5. 아래 실제 staging smoke test를 소유자 테스트 계정 두 개로 진행한다.

**신규 빈 테스트 DB만** 같은 커밋의 `supabase/staging/01_install.sql`~`13_install.sql`을 번호순 설치한다.
기존 10/12개짜리 bundle 설치 DB에 새 bundle을 섞지 않는다. 기존 DB는 개별 migration만 사용한다.
옛 기능 SQL/1·2단계를 나중에 재실행하면 새 정의를 덮어쓸 수 있으므로 항상 **1→2→3** 순서다.

## 신뢰 경계 / 정상 플레이

- open/hr × 1v1/3v3/boss, AUTO·수동·AUTO↔PLAY·SKIP 모두 지원. 화면/속도/스킬 규칙은 유지한다.
- 시작 RPC가 소유 카드·강화·장비·증표를 다시 읽고 양쪽 덱/상대/seed/시즌/Elo 변동을 고정한다.
  유효하지 않은 상대 덱은 건너뛰고 기존 규칙대로 거울 봇(레벨 -10%, 레이팅 변동 절반)을 사용한다.
- 하루 기존 10회+구매 추가 횟수, KST 일/주 경계 유지. 옛 attempt도 당일 횟수에 포함.
  시작 간격 2초, 만료는 발급+1시간과 시즌 종료 중 빠른 시각이다. request UUID 재전송은 같은 세션이다.
- 함수는 JWT의 sub를 디코딩해 믿지 않고 **Auth `/user`로 유효 사용자 확인** 후 사용자 JWT로 시작 RPC를 호출한다.
  backend-only RPC에는 검증한 UID만 넘긴다. 요청의 UID/결과/보상/상대/seed/통계 필드는 허용하지 않는다.
- AUTO는 정식 엔진을 서버에서 시뮬레이션. 화면 전투는 **정식 행동만** 제출하며 서버가 같은 엔진으로 재실행한다.
  잘못된 스킬·대상·턴·행동 중복, 누락/추가 입력·라운드, client `auto` 명령, 통계 조작은 통과하지 않는다.
- 엔진은 기존 `pvp-core.js`/rules/skills/AI/gear와 CSV·skills·combos 데이터로 생성한다.
  canonical 입력 9개 SHA-256이 SQL/함수/브라우저에 결속된다. 수동 재생의 느슨한 offline `replay()`는 지급에 쓰지 않는다. `tools/pvp_verify.mjs`도 같은 strict 엔진의 읽기 전용 감사로 바꾸고 옛 `verified UPDATE` SQL 출력을 제거했다.
  동기적 engine 호출 안에서만 RNG/스킬 전역을 사용하므로 요청 사이 await로 상태가 섞이지 않는다.
- 검증한 라운드/스킬 수만 backend-only 정산 RPC에 전달한다. 한 트랜잭션에서 양쪽 레이팅·승패·연승,
  세션 영수증·미션 이벤트·지갑/심연석/티켓/칭호·공통 보상 원장을 확정한다.
- 사용자별 request 유일성, 세션 PK, 공통 영수증 유일성, 리그/모드/시즌 advisory lock으로 재전송을 직렬화한다.
  동일 제출은 저장된 결과, 다른 제출은 충돌이다. 시즌 보상도 같은 시즌 잠금 안에서 순위/보상을 계산한다.
- **기존 이탈 패배 규칙 유지:** 시작 때 패배/방어승 레이팅을 예약하고 검증 승리만 이를 뒤집는다.
  새 매칭 시작·명시적 포기·만료는 서버가 확정하는 무보상 패배다. 포기/미완료는 검증 경기 수/승리/미션/보상 자격을 만들지 않는다.
  제출되지 않은 패배도 이미 예약돼 시즌 순위가 나중에 뒤집히지 않는다. 시즌 종료 후 승리 확정은 불가능하다.
- 결과 표시에는 서버 응답만 사용. 미정산 때 가짜 로컬 WIN/레이팅 fallback 없음.
  시작 UUID와 완료 transcript는 계정별 localStorage에 보관해 새로고침/네트워크 복구 후 같은 요청을 다시 보낸다.
  미정산 영수증이 남으면 새 매칭 대신 다시 저장한다. 타 탭/만료로 먼저 정산됐으면 Auth로 결속한 status 조회로 서버 영수증만 복구한다. 로그아웃/다른 계정에는 해당 계정 캐시를 쓰지 않는다.

## 과거 기록과 새 검증 래더 (중요)

**기존 `pvp_ratings`·attempt·수령·지갑은 지우거나 재설정하지 않는다.** 그러나 옛 승리/연승/9999 레이팅은
서버 replay 증거가 아니므로 새 돈/업적/칭호를 발행하는 데 복사하지 않는다.
공식 PvP는 별도 `pvp_ratings_v3`의 **새 검증 래더(기본 1000)**를 사용한다.
로비에 `서버 검증 래더 · 이전 기록 … 보존` 표시, 랭킹/랭커 상세도 v3로 일치시킨다.
옛 프로필 장착값/기존 수령 기록은 보존하고, 새 티어 기반 cosmetic unlock은 검증 경기 근거를 요구한다.
전환 직전 당일 남은 횟수는 초기화하지 않는다. 옛 시즌 보류 보상/옛 미완료 전투의 소급 인증은 하지 않는다.

## 지급 재개 / 계속 보류

| 항목 | 재개 조건 |
|---|---|
| PvP 3·5·10 연승 보상 | 서버 재생 확정 승리와 실제 v3 연승. attempt별 원장 1회 |
| 지난 시즌 티어 보상 | 지난 주 v3 **검증 완료 3경기 이상**. 리그/모드/시즌별 1회 |
| 종료 시즌 순위 보상 | 해당 시즌 v3 **검증 완료 1경기 이상**. 서버 순위표, 1회 |
| 심연 칭호·티어 cosmetic | 검증 래더/티어 보상에 따른 서버 확정 |
| PvP 승리/티어 업적 | v3 승리·검증 경기의 티어만. 기존 수령 키와 중복 불가 |
| 일반 일일/주간 승리·스킬 미션 | 새 검증 PvP 이벤트만 합산. phase2 스토리/타워 근거 유지 |
| PvP 조직 활동 feed | 확정 승리 +10 EXP/충성, KST 하루 100. 원장 ref=`pvp3:attempt`; 재전송 무증가 |

1단계의 안전한 비전투 지급과 2단계 tutorial/chapter/star/story-battle-mission/tower 지급은 유지한다.
**4단계:** raid/war 피해·승리 기반 보상·업적, 검증되지 않은 조직 의뢰/전쟁 보상은 계속 보류.
글로벌 `_guild_feed`, 옛 `_pvp_grant`는 열지 않는다. arcade 일반 전투 EXP/승리 등 미검증 근거도 계속 보류.
친선전 `friend_battle_*`는 기존 **비랭크·무보상** 경로이며 v3 랭킹/보상/승리 이벤트로 인정하지 않는다.

## 닫는 우회 경로

`pvp_start`/`pvp_report`/`pvp_log` 모든 오버로드 EXECUTE를 일반 역할에서 제거.
옛 start/report 본문도 거절하도록 교체. 새 backend RPC 둘은 `service_role`만 EXECUTE 가능.
새 테이블 RLS+무정책/권한 회수, 옛 PvP 테이블과 신규 테이블 직접/컬럼 쓰기·identity sequence 조작 차단.
공개 보상표 SELECT는 유지. 타인 세션 조회·settle은 backend의 Auth UID 결속으로 거절한다.

## 검증 / 실제 staging smoke test

```bash
node tools/build_phase3_engine.mjs          # 엔진/데이터 변경 때 생성
node tools/build_staging_sql.mjs
node tools/build_staging_parts.mjs
npm run check:staging
npm run test:staging
npm run test:security:phase1
npm run test:security:phase2
npm run test:security:phase3
npm run build:staging
```

오프라인: 120개 browser/server AUTO 및 live 수동·SKIP canonical 재생 fixture(세 모드), RNG 복구,
불법/누락/추가 행동, 실제 handler→모의 Auth/REST→PGlite SQL 정산, 타인/위조 JWT·옛 overload·컬럼 쓰기,
시즌/일일 제한·재전송·연승/양쪽 Elo·티어/순위 지급·업적/미션·조직 feed·중간 오류 전체 롤백을 검사한다.
PGlite의 클러스터 번호만 **메모리**에서 바인딩한다. 배포 SQL의 고정 guard는 변경하지 않는다.
이전 보안 suites와 전체 설치·분할 설치·렌더링 suite도 함께 실행한다.

소유자 실제 staging 확인(아직 미실행):
1. 두 테스트 계정, 각 리그/모드 AUTO·수동·SKIP 승패 및 방어측 변화 확인.
2. 결과 body에 wins/seed/상대 추가 → 거절, 수동 불가능/생략 입력 → 보상 불변.
3. 같은 완료 동시 제출·서로 다른 완료 동시 제출 → 영수증/양쪽 Elo/지갑 각 1회.
4. 양 계정 상호 동시 전투·다른 모드 동시 승리 → 연승·조직 일일 cap 확인.
5. 새로고침/함수 응답 유실·재로그인 재시도, 1시간 만료·KST 월요일 시즌 경계·다음 주 보상 확인.

## 잔여 위험 / 운영 유의

- 실제 Supabase/Deno 배포·JWT gateway·네트워크·동시 Postgres MVCC smoke는 수행하지 않았다.
  PGlite는 단일 연결이라 실제 병렬 잠금/교착 회피를 증명하지 않는다. 리그/시즌 전체 잠금은 규모가 커지면 병목이 될 수 있다.
- service-role/secret은 신뢰 경계다. backend 침해/SQL 관리자/탈취 키까지 방어하지 않는다. 키는 클라이언트에 배포하지 않는다.
- 정식 엔진의 규칙 버그, 오래된 데이터/버전 롤아웃 불일치는 여전히 위험하다. 엔진·SQL·프런트를 같은 커밋으로 맞춘다.
  기존 장비/소유 카드 스탯의 과거 출처 전체를 정화하는 migration은 아니다. phase2의 plausibility 잔여 위험도 그대로다.
- seed/스냅샷은 플레이에 공개된다. 합법 입력 offline 탐색·봇/다계정·의도적 패배/승부 조작까지 막는 anti-cheat는 아니다.
  자동은 서버 결과로 고정되지만 수동은 유효한 법적 행동열임을 보장할 뿐 실제 사람이 실시간으로 클릭했다는 증명은 아니다.
- 정상 start 횟수/2초 간격/본문·행동 수 상한은 있으나, 잘못된 finish 반복은 Edge CPU 비용을 유발할 수 있다.
  별도 WAF/IP·계정별 ingress rate limit과 관측/알림은 추후 운영 작업이다.
- 구버전/만료 전투는 무보상 패배이며 보류된 과거 PvP 보상을 추측해 일괄 지급하지 않는다.
  캐시 삭제/브라우저 종료 전 완료 transcript 미보관·버전 전환 시 진행 전투는 복구가 제한된다.

긴급 중단은 소유자가 staging에서 `update public.pvp_policy_v3 set enabled=false;`.
일반 사용자는 변경할 수 없다. 재실행해도 false를 true로 되돌리지 않는다.
프런트만 옛 버전으로 롤백하면 금지 RPC를 호출하므로, 안전하게 PvP를 닫고 원인을 수정한다.

참고: [Supabase Functions Auth](https://supabase.com/docs/guides/functions/auth),
[Auth headers](https://supabase.com/docs/guides/functions/auth-headers),
[Runtime secrets](https://supabase.com/docs/guides/functions/secrets).
