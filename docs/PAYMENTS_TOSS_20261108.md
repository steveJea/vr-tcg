# 토스 심연석 충전 — staging 테스트 전용 (2026-11-08)

## 형님이 할 순서

**운영 Worker / 운영 DB / main에는 아무것도 적용하지 마세요. 실제 결제 기능이 아닙니다.**

1. Supabase **staging `cuyqchmdcnsgzkwyclji`** → SQL Editor → `supabase/payments_staging.sql` 전체 실행.
   - DB 식별자 `7703759698107299042`가 아니면 즉시 중단됩니다. 가드를 지우지 마세요.
   - 여러 번 실행해도 주문·심연석·원장을 초기화하지 않습니다. 기존 테스트 상품 가격 수정도 보존합니다.
2. [토스 개발자센터 → API 키](https://developers.tosspayments.com/my/api-keys)에 로그인합니다(계정이 없으면 이메일로 가입).
   - **개발 연동 체험 상점 → API 개별 연동 키 → 일반결제/결제창(구버전) → 테스트**에서 **같은 상점의 클라이언트 키(`test_ck_…`)와 시크릿 키(`test_sk_…`) 한 쌍**을 확인하세요. 브랜드페이·빌링 키 / `test_gck_…`, `test_gsk_…`는 아닙니다.
   - Supabase **staging → Edge Functions → Secrets**에서 **`TOSS_CLIENT_KEY`와 `TOSS_SECRET_KEY` 둘 다** 직접 넣습니다. 클라이언트 키도 이제 필수이며, GitHub 샘플로 자동 대체하지 않습니다.
   - 두 키를 채팅으로 보낼 필요가 없습니다. 시크릿은 환경변수에서만 읽고 Git·브라우저에는 넣지 않습니다. 클라이언트 키는 공개 값으로 본인 주문 응답에만 내려갑니다.
   - [현재 공식 카드 결제 가이드](https://docs.tosspayments.com/guides/v2/payment-window/integration#api-키-준비하기)는 `{CLIENT_KEY}` / `{SECRET_KEY}`에 **개발자센터의 내 테스트 키**를 넣도록 안내합니다. 아래 “공용 샘플 401” 참고.
3. **Edge Functions → 새 함수 `payments-confirm-v1`** → `supabase/functions/payments-confirm-v1/dashboard_single_file.ts` 전체 붙여넣고 배포.
   - **Verify JWT / JWT 검증 ON** 유지. 추가 npm 설치·import가 없는 대시보드용 단일 파일입니다.
   - Supabase의 기본 서버용 `SUPABASE_SERVICE_ROLE_KEY` 또는 `SUPABASE_SECRET_KEYS`, 공개 키 환경이 필요합니다(기존 검증 함수와 같은 방식). 값은 공유하지 마세요.
4. https://vr-tcg-staging.notcold.workers.dev/ 새로고침 → 로그인 → 심연석 `＋ 충전` → **테스트 충전 · 임시가** 상품 선택.
   - 토스 테스트 결제창에서 진행하면 `/payment-return.html`을 통해 서버 확인 후 지급됩니다. 결제창에 테스트임을 확인하세요.
   - 실패·취소는 토스트로 표시합니다. 승인 확인 지연 시 **다시 확인** 또는 심연석 충전 화면의 **충전 다시 확인**을 누르세요. 같은 주문을 다시 결제하지 않습니다.
   - 결제한 계정으로 로그인해야 합니다. Google/Kakao/X 이메일 미제공 계정도 사용 가능하며 결제 SDK에 이메일·전화·실명은 자동 전송하지 않습니다.

## 결제창이 뜨기 전에 오류가 날 때

- Secrets 수정은 즉시 반영됩니다. **키 변경만으로 함수 재배포는 필요하지 않습니다.** ([Supabase 공식 안내](https://supabase.com/docs/guides/functions/secrets))
- 초기 코드가 HTTP 인증/DB/SDK 실패까지 모두 “결제 확인 지연”으로 표시한 문제가 있어 구분했습니다. “주문 생성 지연”은 아직 결제창 전 단계이고, “결제 확인 지연”은 승인·지급 확인 단계입니다.
- “결제 DB 설정/권한/연결” → SQL 설치·권한/대상 DB 확인. “결제 서버의 로그인 설정” → 함수의 JWT 인증 오류 확인. JWT 검증을 임의로 끄지 마세요.
- “결제창을 불러오지/열지 못했어요” → Toss SDK 로딩/초기화/결제창 단계입니다. 서버 주문 생성 실패와 다릅니다.
- 업데이트된 Edge는 Logs에 `stage`와 PostgreSQL 오류 코드만 남깁니다. 토큰·키·주문/사용자 ID·SQL 원문은 남기지 않습니다. 문제가 계속되면 **토스트 문구와 stage/dbCode만** 알려주세요. 시크릿·사용자 JWT는 보내지 마세요.
- **함수 코드 업데이트 시에만** 새 `dashboard_single_file.ts`로 `payments-confirm-v1`을 재배포합니다. 이 진단 수정에는 SQL 재실행이 필요하지 않습니다.

## 결제창 실행 호환성 (클라이언트 보완)

- 공식 `https://js.tosspayments.com/v2/standard` + `TossPayments(test_ck_…).payment({customerKey})` 사용. 위젯용 `test_gck_…`/v1 API와 혼용하지 않습니다.
- PC 기본 iframe 대신 **PC·모바일 모두 `windowTarget: self` 리다이렉트**를 명시합니다. 새 팝업을 만들지 않으므로 서버 주문 생성 await 뒤 팝업 사용자 제스처 제한에 의존하지 않습니다. 승인 결과는 기존 successUrl/failUrl 콜백에서만 처리합니다.
- 서버 주문 번호·숫자 금액·상품명·고객 UUID를 SDK 호출 전에 검증합니다. 원래 서버 가격/소유자 검증과 1회 지급 조건은 바뀌지 않습니다.
- 오류 토스트 끝에 `INVALID_CLIENT_KEY`, `SDK_VERSION_MISMATCH` 같은 **실제 SDK 오류 코드**가 붙습니다. 알 수 없는 오류는 **실제로 받은 메시지(최대 120자)**를 보여줍니다. 콘솔에는 `sdk-init`/`checkout`, 코드, 키 종류와 **비밀값을 가린 메시지·스택(최대 1,200자)**을 기록합니다. 키·인증 헤더/JWT·이메일·고객/주문 ID·결제 키·URL 쿼리는 가리며, 서버 SQL/응답 원문은 여전히 표시하지 않습니다.
- `INVALID_CLIENT_KEY`/`UNAUTHORIZED_KEY` 또는 “테스트 결제 키를 설정해 주세요.”라면 **같은 일반결제 상점의 테스트 키 한 쌍**인지 확인합니다. `TOSS_CLIENT_KEY`를 생략하거나 인증이 거절된 기존 예제 키를 사용하면 SDK/새 주문 생성 전에 중단합니다. 승인 API의 401도 키 설정 오류로 구분합니다.
- **이번 공용 키 제거 수정은 Edge 코드도 변경됩니다.** 두 Secrets 설정 → 새 `dashboard_single_file.ts`로 **payments-confirm-v1 재배포(JWT ON)** → staging 새로고침 순서입니다. SQL 재실행은 필요 없습니다. 이후 키 값만 교체할 때는 함수 재배포가 필요 없습니다.
- 이 실행 환경에서 실브라우저를 직접 실행하지 않았습니다. 공식 SDK 파일을 오프라인 DOM mock으로 초기화했습니다(v2 payment API 생성 확인). 네트워크는 차단했으며 실제 결제창·사용자 계정 오류를 완전히 재현한 검사는 아닙니다. 실제 iPhone/PC 동작은 별도 확인이 필요합니다.

### 공용 샘플 401 — 확인된 원인과 수정

- 보고된 실제 staging 브라우저 재현 결과: 서버 주문 생성은 200, 결제창을 여는 SDK 요청은 **401 `UNAUTHORIZED_KEY`**였습니다. 당시 `official-sample`은 위젯 키가 아니라 **기존 GitHub express 샘플의 `test_ck_…`**였습니다.
- 같은 공식 express `apiSecretKey`를 **없는 주문의 공식 GET 조회 API**로 읽기 전용 확인한 결과도 **401 `UNAUTHORIZED_KEY`**였습니다. 사용자 Secrets는 읽지 않았습니다. 따라서 그 값을 넣으셨다면 **시크릿도 새 테스트 쌍으로 교체해야 합니다**.
- 현재 카드 결제 문서와 인증 안내에는 실제 공용 키 대신 `{CLIENT_KEY}` / `{SECRET_KEY}`가 표시됩니다. 유효한 새 공개 카드 결제 키 쌍은 확인하지 못했으므로 임의의 다른 키를 넣지 않았습니다. 문서 자산의 PayPal 예제 키를 국내 카드용으로 전용하지도 않습니다.
- 서버의 인증 거절된 샘플 자동 대체를 제거했습니다. 클라이언트도 예전 Edge에서 그 키가 내려오면 SDK를 실행하지 않습니다. **사용자 전용 테스트 한 쌍을 설정하기 전에는 결제창이 열리지 않는 것이 정상입니다.**
- 키를 바꿀 때는 항상 같은 상점 한 쌍으로 맞추세요. 이미 인증·승인된 보류 결제가 있다면 다른 상점으로 옮기기 전 기존 결제를 먼저 정산해야 합니다. 이 수정은 주문/재화/원장을 삭제하지 않습니다.

### `UNKNOWN` 진단 보완은 유지

- [`UNKNOWN`은 Toss SDK의 정식 오류 코드](https://docs.tosspayments.com/sdk/v2/error-codes)이며, SDK가 내부 401을 일반 오류로 감싸서 앱에 전달할 수 있습니다. 코드가 없다는 의미는 아닙니다.
- 일반 TypeError/코드 없는 Error는 민감값을 가린 메시지·스택으로 구분합니다. 전체 HAR·쿠키·토큰·키는 공유하지 마세요.
- 이 환경에서는 실제 브라우저를 직접 실행하지 않았습니다. SDK 401 원인은 전달받은 실브라우저 증거와 공식 API 읽기 전용 확인에 근거합니다. 새 사용자 키 설정 뒤 실제 결제창 성공 여부는 별도 확인해야 합니다.

## 임시 가격안 — 확정 BM 아님 / 실제 출금 없음

| 유료 심연석 | 무료 보너스 | 테스트 가격(KRW) |
|---:|---:|---:|
|100|0|1,100원|
|500|25|5,500원|
|1,000|100|11,000원|
|3,000|450|33,000원|

`payment_products`에서 서버가 가격·지급량을 읽고 주문 생성 시 복사합니다. 상품 변경은 **새 주문**에만 반영됩니다. 테스트 보너스는 `gem_free`, 기본 지급량은 `gem_paid`에 들어갑니다. UI에도 임시가/테스트라고 표시합니다.

## 확인할 테스트

- 4개 상품 정상 승인 → 정확한 유료/무료 지급.
- 성공 페이지 새로고침·뒤로가기·중복 클릭·다시 확인 → 같은 주문은 한 번만 지급.
- 결제 취소/실패 → 지급 없음. 네트워크 끊김 뒤 같은 계정으로 복귀 → 재확인으로 복구.
- 다른 계정으로 주문 확인, 금액/주문번호 변조 → 거절, 지급 없음.
- iPhone Safari에서도 결제창 이동과 복귀 확인(실기기 테스트 필요).
- SQL/Edge 설치 전에는 설정/연결 오류로 종료되며 허위로 성공·지급 처리하지 않습니다.

개발 검사는 **오프라인 PostgreSQL(PGlite) + Auth/Toss 모의 응답**을 사용합니다. 실제 사용자 세션·카드·실결제는 사용하지 않았습니다. 위 SQL/Edge/시크릿 적용 뒤 실제 staging 브라우저 테스트를 해주세요. 테스트 키는 형님 개발자센터의 일반결제 상점에서 발급받은 한 쌍을 사용합니다. 공용 예제 키의 현재 유효성을 보장하지 않습니다.

## 보안·복구 구조

- 클라이언트는 상품 ID와 요청 UUID만 전송 → `payment_create_v1`이 서버 가격·지급량·고유 주문번호 생성. 요청 UUID 재시도 멱등 + 사용자별 생성 제한.
- `payment_orders`: 본인 주문만 SELECT. 두 테이블 모두 클라이언트 INSERT/UPDATE/DELETE 금지. 활성 상품만 조회.
- Edge는 Auth API로 실제 JWT 사용자 확인 → 주문 소유자·금액 확인 → paymentKey를 DB에 고유 바인딩 → 토스 조회/승인 → **DONE/주문번호/key/KRW/금액/미취소 잔액/승인일/허용 결제수단** 확인.
- 승인에는 주문별 고정 `Idempotency-Key`. 토스 승인 후 응답/DB 통신이 끊겨도 같은 키 조회로 복구. 원장 ref와 주문·paymentKey UNIQUE + row lock + 단일 트랜잭션으로 한 번만 지급.
- 승인·지급 함수는 service role만 실행 가능. 카드번호·전체 토스 응답·시크릿은 저장/로그 출력하지 않습니다. DB에는 최소 주문/지급/고유 키만 남깁니다.
- 콜백은 분석 스크립트가 없는 별도 페이지. 외부 SDK 로딩 전에 쿼리 제거, no-referrer. 계정별 브라우저 보류 정보 + DB 키 바인딩으로 재시도하며 로그아웃/계정 전환으로 다른 계정에 지급되지 않습니다.
- HTTP/초기화/응답 파싱은 유한 타임아웃. “확인 지연”은 실패 확정이 아니므로 재시도 시 새 주문/새 승인 멱등키를 만들지 않습니다.
- **staging 호스트 + Supabase URL + DB 식별자 + test 키 prefix** 모두 제한. 라이브 키만 넣어 실결제로 바꾸는 것은 의도적으로 막았습니다. 운영 승격은 별도 승인·SQL/가드/약관/환불/대사 검토 후 작업해야 합니다. 시크릿을 환경변수로 읽는 구조는 그대로 재사용합니다.

## 환불/승인 취소는 다음 단계

이번에는 **승인 전 사용자 취소/실패 표시만 구현**했습니다. 승인 후 환불 API, 부분 취소, 관리자 환불 버튼, 웹훅·정기 대사는 아직 없습니다. 토스 대시보드에서 임의 취소해도 게임 심연석은 자동 회수되지 않습니다. 따라서 라이브 판매를 시작하면 안 됩니다.

다음 구현: 별도 환불 요청/원장과 unique 취소 멱등키 → 서버 권한·미사용 유료 잔액 확인/필요한 사용 잠금 → Toss 취소 → 취소 상태 재조회/웹훅의 서버 재검증 → 원결제 기준 회수·보너스 처리·누적 부분취소 정산. 이미 사용된 재화/보너스·잔액 부족·미성년자 취소·분쟁은 법률 검토한 CS 정책과 맞춰 처리하고, 외부 취소/차지백도 대사로 탐지해야 합니다. 단순 기존 잔액 음수 차감으로 끝내지 않습니다.

결제 주문은 금융 기록 보존 검토를 위해 계정 삭제 시 `RESTRICT`로 남깁니다. 향후 계정 탈퇴/법정 보존/익명화·처리방침에도 반영해야 합니다. 실결제 전에는 PG 계약·게임 등급·연령/보호자 결제·환불 동의·확률 공개·약관 및 개인정보의 토스 처리/보유/국외이전 고지도 별도로 확정해야 합니다.

## 공식 자료 (이번 작업에서 확인)

- https://docs.tosspayments.com/guides/v2/payment-window/integration
- https://docs.tosspayments.com/sdk/v2/js/payment
- https://docs.tosspayments.com/reference/using-api/api-keys
- https://docs.tosspayments.com/reference/using-api/authorization
- https://docs.tosspayments.com/guides/v2/payment-window/integration.md (현재 키 자리표시자 확인)
- https://docs.tosspayments.com/reference (Payment, confirm, 조회, 취소)

현재 공식 문서에서는 `test_ck_/test_sk_` 방식이 **결제창(구버전) / API 개별 연동**으로 분류됩니다. 이 구현은 API 개별 연동 경로를 사용하며, `test_gck_/test_gsk_` 주문서형·신규 결제창형 키와 혼용하지 않습니다.
