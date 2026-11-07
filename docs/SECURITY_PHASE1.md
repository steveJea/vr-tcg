# 보안 1단계 — 지급 통로 / 도감 / 미션

작성: 2026-11-07 KST. 기준: `origin/main` 2d2a12c. **DB 적용·배포·운영 승인 아님.**

## 먼저 알아둘 점

전투 엔진 검증기는 2~5단계 작업이다. 1단계에서는 검증되지 않은 전투 결과로
젬·소환권을 지급하지 않도록 **지급만 보류**한다. 정상 플레이도 해당 보상을
당분간 못 받는다. 이를 “게임 전체 보상은 그대로” 또는 “전투 검증 완료”라고
안내하면 안 된다. 운영 적용 전 보류 범위와 과거 진행도 정책에 소유자의 별도
승인이 필요하다. 이번 변경은 운영 DB/사이트를 건드리지 않는다.

- 전투 룰, 덱, 전투 조작, 기존 잔액/소환권 소비/상점 가격은 변경하지 않는다.
- 도감 화면의 기존 카드·왕관·과거 수령 기록은 삭제/초기화하지 않는다.
- 과거 조작 가능 카운터/도감 행/보유 JSON을 새 검증 이벤트로 복사하지 않는다.
- 새 지급 자격은 검증 근거로 계산하므로 **기존 표시 진행도와 지급용 진행도가
  다를 수 있다.** 과거 도감/뽑기 횟수/전투 미션의 자동 소급 지급은 없다.
- 예전 업적 점수로 열었던 꾸미기는 별도 legacy 계산을 유지한다. 새 점수
  재화 보상은 이번 경계 이후 안전하게 수령한 업적 영수증만 계산한다.
- 보류는 기존 버튼/결과 위치의 `지급 보류` 상태로 표시한다. 새 작은 설명문이나
  Tailwind 클래스는 추가하지 않았다.

## 소유자의 staging 적용 순서

1. Supabase SQL Editor가 테스트 프로젝트 `cuyqchmdcnsgzkwyclji`인지 직접 확인한다.
   테스트 주소: https://vr-tcg-staging.notcold.workers.dev/
2. `supabase/security_phase1_preflight.sql`만 실행한다(읽기 전용).
   함수 시그니처/본문 해시/실행권한, raw/column 권한, 정책, 트리거를 확인한다.
   `supabase/audit_live.sql`도 기존 안내대로 함께 점검 가능하다. 사용자 원문이나
   키/토큰을 조회하거나 보내지 않아도 된다.
3. 이 파일들의 실제 적용 여부는 구현 환경에서 확인하지 못했다. 저장소와 다른
   함수/오버로드/트리거가 있으면 결과를 먼저 검토한다. 필수 객체가 없으면 새
   migration이 `STOP`으로 전부 롤백된다. 옛 SQL로 전제조건을 억지로 채우지 않는다.
4. **기존 테스트 DB에는 `supabase/security_phase1_rewards.sql` 하나만** 실행한다.
   전체가 한 트랜잭션이며, 재실행해도 기존 자료를 리셋하거나 보상하지 않는다.
   실패하면 전체 롤백된다. SQL Editor가 실패한 트랜잭션 상태를 남겼으면
   `ROLLBACK;` 후 원인을 확인한다.
5. preflight를 다시 실행한다. 모든 `_` helper는 anon/authenticated 실행 불가,
   대상 테이블/열의 직접 쓰기는 불가여야 한다. 새 테이블은 RLS+API 접근 차단이다.
   `story_progress_gallery` 트리거는 없어야 하고 `reward_gacha_event`만 새 획득을 기록한다.
6. 그 다음 staging 클라이언트를 배포하고 아래 실기기 시험을 한다.
   **운영은 아직 적용하지 않는다.** 결과와 보류/소급 정책을 승인받은 다음,
   운영 preflight → 백업/복구점 확인 → 같은 migration → 클라이언트 순서로 별도 진행한다.

`supabase/staging_install.sql` 및 `staging/01~10_install.sql`은 **비어 있는 신규
테스트 DB 전용**이다. 새 설치에도 이 보안 migration이 마지막에 포함된다.
이미 설치된 테스트 DB에는 재생성된 설치본을 다시 실행하지 않는다. 새 bundle
해시가 과거 설치 기록과 달라 거부되는 것이 정상이다. 설치 기록을 지우지 않는다.

## 지급/이벤트 지도

전체 관련 RPC 시그니처·권한·본문 해시는
[`SECURITY_PHASE1_RPC_INVENTORY.json`](SECURITY_PHASE1_RPC_INVENTORY.json)에 있다.
이는 PGlite에서 저장소 순서대로 구성한 **기대 정의**이며 live DB 증명이 아니다.
`node tools/test_security_phase1_sql.mjs --inventory`로 재생성한다.

| 입력/원인 | 상태/근거 | 수령/지급 | 1단계 정책 |
|---|---|---|---|
| `daily_track(text,int)`, `weekly_track(text,int)`, `ach_track(text,int)` | 옛 `daily_progress`, `weekly_progress`, `ach_counters` | 일간/주간·전투 업적 | 증가 요청 거부. 기간/수령 기록 유지. 상태는 지급용 진행도 0 + 보류 |
| `gallery_register(text[],text)` / 브라우저 MVP | 옛 `gallery` | 도감·MVP 보상 | 획득/MVP 증가 거부. 클라이언트 RPC/오프라인 재전송 제거 |
| `story_daily_draw()`, `story_ticket_draw(int)` | 서버 추첨/비용·KST 일일 제한 → `story_gacha_log` INSERT | `verified_game_events` → `gallery` | 서버 로그 트리거만 이벤트 생성. `(user,source,event)` unique, catalog/alias 정규화 |
| 보유 JSON 저장/스토리 카드 | `story_progress.data.owned` | 도감 자동 등록 | 옛 트리거 제거, helper no-op. 검증 전에는 지급 자격으로 인정하지 않음 |
| 새 검증 획득 카드 수 | events × `reward_card_catalog` (cards.csv 438장) | `gallery_reward_claim(int)` / 도감 업적 | 실제 획득 이벤트만. 판매/합성 후에도 이력 유지. 숨겨진 풀 카드는 수집률 제외 |
| 새 뽑기 횟수 | events (실제 서버 로그 1행=1회) | `achievements_claim(text)`, `_all()` | 별도 이벤트 복사 없이 같은 근거를 각각 1회 소비/수령 |
| 출석 | `auth.uid()` + `_gem_day()` + `daily_attend` | `attend_claim()` | KST 00:00/7칸 보상표 유지, 계정/일 잠금 + 공통 영수증 |
| 연속 접속 | `gem_login` + 서버 KST | `gem_status()` / `_gem_sync` | 7일 보상 유지. 챕터 자동 50젬은 보류 |
| 캠프 확장/장비 강화/친구·조직 가입/선물 전송 | 서버 거래/실제 관계 테이블 | 해당 비전투 업적 | 서버 상태만 사용. 보상표/기존 수령 PK + 공통 영수증 |
| `arcade_tut_claim(int)` | 로컬 튜토리얼 승리 | 초급10티켓/중급100젬/상급300젬 | **전부 보류**. 로컬 진행/연습은 가능, 수령 기록도 소비하지 않음 |
| `story_star_claim(int,text)` / 챕터 클리어 JSON | 미검증 별/클리어 | 별 티켓·골드 / `_story_ticket_sync` 챕터10티켓 | 보류. 기존 티켓은 조회/사용 가능. 허위 클리어로 자동 티켓/젬 없음 |
| `tower_complete(text,int,jsonb)`, `_sweep_complete(...)`, 옛 `quest_*` wrapper | 미검증 층 완료 | `_tower_pay` | 지급 보류, `paid_floor` 미진행. 완료/연습 진행은 유지. 해금/진행 검증 자체는 2단계 |
| `pvp_report(bigint,int,int)` | 미검증 승패 | `_pvp_grant` 연승 / `pvp_claim_tier(text,text)`, `pvp_claim_reward(text,text,date)` | 젬·티켓·기타 보상 보류. 전적/레이팅 보호는 아직 3단계. 지급/수령 ID 미소비 |
| `raid_finish`/`raid_sweep` | 미검증 피해 | `_guild_reward` raid_attempt/raid_last_hit, `raid_claim()` | 시도/마지막일격 자동지급 no-op, 결과 `got={}`+보류. 정산 수령 거부 |
| `war_finish` / 조직 일간·주간 미션 | 미검증 전투 누적 | `war_claim()`, `guild_quest_claim`, `guild_weekly_claim` → `_guild_reward` | 정산/의뢰 지급 보류. 피해·조직 점수 검증은 4단계 |
| 전투 활동 충성 → 조직 상점 티켓 | `_guild_feed` | `_loyalty_add` → `guild_shop_buy` | 검증 전 활동 충성/세력 공급 no-op. 예전 잔액은 유지 |
| 조직 출석/집결 | 서버 날짜/실제 집결 상태 | `guild_checkin`, `guild_rally_claim` | 유지: 기존 `guild_claims(user,ref)` 전체 트랜잭션 중복 방지 |
| 젬/조직 상점 구매 | 서버 가격/잔액/기간별 제한 | `gem_buy`, `guild_shop_buy` | 유지. 무료 지급 RPC가 아니라 검증된 비용 지불 거래 |
| 파견/운영자 우편/관리자 지급 | 서버 파견 종료시각·소유권/운영자 생성 메일/`_admin_guard` | `dispatch_claim`, `mail_msg_claim`, `admin_grant_*` | 기존 서버 원인·지급표·중복키 유지. 관리자 검사는 생략하지 않음 |

주요 근거 소스: `daily.sql`, `daily_social.sql`, `achievements.sql`, `achievements2.sql`,
`gallery_owned.sql`, `gallery_register_new.sql`, `gacha_premium_ur.sql`, `gem.sql`,
`story_gacha.sql`, `arcade_tut_gem.sql`, `story_star_rewards.sql`, `tower_v2.sql`,
`guild.sql`, `guild2.sql`, `guild3.sql`, `guild4.sql` 및 새 migration.

보안 1단계는 모든 경제 전이를 재검증하는 작업은 아니다. 스토리 골드/경험치,
아이템/장비 드롭·거래, 미검증 PvP 레이팅/토벌 피해/조직 점수/아케이드 랭킹은
다음 단계에 남는다. 이 값을 새 검증 전투 이벤트로 간주하지 않는다.

## 중복/권한/기간

- `_daily_grant`는 비공개다. 호출자가 서버 보상표/자격을 검사한 뒤,
  `reward_claims(user,reward_kind,source_or_period)`를 저장하고 골드·젬·티켓을
  같은 트랜잭션에서 지급한다. 젬은 기존 `gem_ledger(user,ref)`도 유지한다.
- 같은 지급 재시도는 같은 결과, 다른 보상량으로 같은 ID는 오류. 티켓 실패 시
  골드·젬·원장·수령 기록도 모두 롤백한다. 예전 gem ref는 다른 재화 재지급에 쓰지 않는다.
- 업적 점수 키의 `score:000100` 같은 정수 별칭도 거부한다(여러 키로 반복 수령 방지).
- 새 이벤트/영수증/카탈로그/플래그에 공개 INSERT/UPDATE RPC는 없다. 이벤트는 현재
  가챠 트리거 하나만 생성한다. 이후 검증기 연결에는 별도 migration이 필요하다.
- 전투 보상 플래그는 기본 false이며 CHECK로 true 변경까지 막았다. 단순 설정 변경이나
  일반 JWT로 `verified=true`를 보내는 임시 우회는 제공하지 않는다.
- 기존 track/register/claim의 모든 오버로드 권한을 회수한 뒤 검토한 시그니처만
  허용한다. 옛 JSON/지갑·아이템/진행 테이블의 table-level 및 column-level 쓰기도 회수한다.
- 새/교체 helper는 `pg_catalog, public, pg_temp` 고정 search_path. 모든 `_` helper의
  anon/authenticated EXECUTE 회수. 수령 시 계정은 언제나 `auth.uid()`에서 결정한다.
- 출석/접속/일간은 기존 KST 날짜, 주간은 KST 월요일. 브라우저 날짜/기간 인자는 없다.

## 검증

로컬(외부 DB/키 없음, PGlite + 최소 브라우저 VM 이벤트 검사):

```bash
npm run check:staging
npm run test:staging
npm run test:security:phase1
```

PGlite: 이전 설치본 위 조작된 legacy 상태 → migration 두 번 → 잔액/원장/과거 기록
불변; 임의 카드/MVP/kind/n/미보유·타인 이벤트/raw writes/column grants/옛 오버로드
거부; 실제 일일·티켓 뽑기만 이벤트 생성; 정상 도감/개별·전체 업적 수령; 8개 재시도
중복 방지; 정수 별칭; 입력 한계·전체 지급 롤백; 탑·PvP 지급 게이트; KST 경계.
PGlite의 요청 큐 테스트는 **실제 다중 연결 동시성 검증은 아니다.** SQL의 잠금+PK가
동시성 경계이며 실제 Supabase의 병렬 요청/기간 경계/성능은 staging에서 별도 확인한다.

소유자 실기기 시험(아직 미실시):

- TEST 표시, Google 로그인, 실제 요청의 Supabase 목적지가 테스트 프로젝트인지 확인.
- 일일 무료 뽑기 1회, 티켓 뽑기, 출석, 가능한 비전투 업적 수령 후 새로고침/재로그인.
- 튜토리얼/스토리/탑/PvP/토벌/조직전 플레이: 기존 조작·화면 정상, 보류 보상에
  +재화 연출/로컬 잔액 증가/수령 완료가 없어야 함. 출석·상점 소비는 정상이어야 함.
- 동의한 테스트 두 계정으로 임의 RPC/직접 REST 쓰기/동시 수령을 시험.
  키/JWT/사용자 원문을 로그나 채팅에 남기지 않는다.

## 복구와 다음 단계

- 실패한 migration은 트랜잭션 전체 롤백. 적용 후 문제가 생기면 클라이언트는
  이전 자산으로 돌릴 수 있지만 DB의 권한/지급 차단은 유지한다. 옛 보상 SQL을
  다시 실행하는 롤백은 금지한다. 새 함수의 문제는 fail-closed 상태로 교정한다.
- 신규 이벤트·영수증은 삭제하지 않고, 이미 정당하게 지급된 보상을 회수하지 않는다.
- legacy 자료의 승인된 소급/보상 정책과 실제 전투 검증기를 연결한 뒤 모드별로
  별도 migration+회귀 시험을 거쳐 연다. `paid_floor`나 기존 미검증 클리어만으로
  보류분을 자동 지급하면 안 된다.
