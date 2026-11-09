# 토스 심연석 충전 — staging 테스트 전용 (2026-11-08)

## 형님이 할 순서

**운영 Worker / 운영 DB / main에는 아무것도 적용하지 마세요. 실제 결제 기능이 아닙니다.**

1. Supabase **staging `cuyqchmdcnsgzkwyclji`** → SQL Editor → 최초 설치는 `supabase/payments_staging.sql` 실행 후 **`supabase/payments_refunds_staging.sql` 전체 실행**.
   - **충전이 이미 동작하면 새 `payments_refunds_staging.sql`만 실행**하면 됩니다. 기존 파일까지 재실행할 때는 반드시 새 환불 파일을 마지막에 실행하세요(확인/지급 보호 래퍼 복원).
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
- **함수 코드 업데이트 시에만** 새 `dashboard_single_file.ts`로 `payments-confirm-v1`을 재배포합니다. 이전 진단 수정만 적용할 때는 SQL 재실행이 필요 없었지만, **이번 환불 기능에는 새 환불 SQL 실행이 필요**합니다.

## 결제창 실행 호환성 (클라이언트 보완)

- 공식 `https://js.tosspayments.com/v2/standard` + `TossPayments(test_ck_…).payment({customerKey})` 사용. 위젯용 `test_gck_…`/v1 API와 혼용하지 않습니다.
- PC 기본 iframe 대신 **PC·모바일 모두 `windowTarget: self` 리다이렉트**를 명시합니다. 새 팝업을 만들지 않으므로 서버 주문 생성 await 뒤 팝업 사용자 제스처 제한에 의존하지 않습니다. 승인 결과는 기존 successUrl/failUrl 콜백에서만 처리합니다.
- 서버 주문 번호·숫자 금액·상품명·고객 UUID를 SDK 호출 전에 검증합니다. 원래 서버 가격/소유자 검증과 1회 지급 조건은 바뀌지 않습니다.
- 오류 토스트 끝에 `INVALID_CLIENT_KEY`, `SDK_VERSION_MISMATCH` 같은 **실제 SDK 오류 코드**가 붙습니다. 알 수 없는 오류는 **실제로 받은 메시지(최대 120자)**를 보여줍니다. 콘솔에는 `sdk-init`/`checkout`, 코드, 키 종류와 **비밀값을 가린 메시지·스택(최대 1,200자)**을 기록합니다. 키·인증 헤더/JWT·이메일·고객/주문 ID·결제 키·URL 쿼리는 가리며, 서버 SQL/응답 원문은 여전히 표시하지 않습니다.
- `INVALID_CLIENT_KEY`/`UNAUTHORIZED_KEY` 또는 “테스트 결제 키를 설정해 주세요.”라면 **같은 일반결제 상점의 테스트 키 한 쌍**인지 확인합니다. `TOSS_CLIENT_KEY`를 생략하거나 인증이 거절된 기존 예제 키를 사용하면 SDK/새 주문 생성 전에 중단합니다. 승인 API의 401도 키 설정 오류로 구분합니다.
- **이번 공용 키 제거 수정은 Edge 코드도 변경됩니다.** 두 Secrets 설정 → 새 `dashboard_single_file.ts`로 **payments-confirm-v1 재배포(JWT ON)** → staging 새로고침 순서입니다. 공용 키 제거 수정 자체는 SQL 재실행이 필요 없었습니다. **이번 환불 업데이트는 새 환불 SQL을 먼저 실행**합니다. 이후 키 값만 교체할 때는 함수 재배포가 필요 없습니다.
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

## 환불/취소 — 이번 추가 (staging만)

### 적용 순서 (충전 테스트가 이미 성공한 경우)

1. staging SQL Editor에서 **`supabase/payments_refunds_staging.sql` 전체 실행**. 새 작은 추가 파일이며 주문/기존 지급/원장은 보존합니다. DB 식별자 가드를 지우지 마세요.
2. 기존 **`payments-confirm-v1`**에 최신 **`supabase/functions/payments-confirm-v1/dashboard_single_file.ts`** 전체 붙여넣고 **재배포, Verify JWT ON**. 새 함수 이름을 만들 필요 없습니다. 기존 `TOSS_SECRET_KEY`/`TOSS_CLIENT_KEY` 그대로 사용합니다.
3. staging 게임에 **기존 관리자 계정으로 로그인**한 뒤 같은 브라우저에서 **https://vr-tcg-staging.notcold.workers.dev/admin-payments.html** 접속 → **전액 환불**. 관리자 권한은 기존 `admin_check`/`_admin_guard` 기준입니다. 일반 유저에게는 환불 버튼을 제공하지 않습니다.
4. 지연되면 같은 주문의 **환불 다시 확인**. 새 주문/멱등키를 만들거나 PG 대시보드에서 별도로 취소하지 마세요.

### 관리자 목록의 구매자·결제 시각

이미 환불이 설치된 staging에서는 **`supabase/payments_refunds_staging.sql` 전체만 다시 실행**합니다. 주문·지급·원장은 유지되고, DB 식별자가 아니면 중단됩니다. **Edge `payments-confirm-v1`은 이번 변경으로 재배포하지 않습니다.** 화면은 staging Worker 배포 후 `admin-payments.html`을 새로고침합니다.

- **구매자**: `profiles.nickname`. 없거나 공백이면 사용자 ID. 이메일·paymentKey는 목록에 없습니다.
- **결제 시각 (한국시간)**: 지급이 기록된 `paid_at`을 `Asia/Seoul`로 표시합니다. 미결제 주문은 `paid_at`이 없으므로 **미결제 · 생성**과 `created_at`만 표시합니다.

### 선택 정책: 음수 잔액 대신 미사용·회수 가능 주문만 전액 환불

- 기본 운영안: **지급/결제 완료(`paid_at`) 후 7일 이내의 미사용 패키지**는 관리자 확인 후 **수수료 없이 원결제 전액 환불**, 해당 **유료 심연석과 무료 보너스 전량 회수**. 별도 유저 셀프 환불·부분 환불은 없습니다.
- 잔액만 채워넣어 사용을 숨기는 것을 막기 위해 **원장 기준 보수적 FIFO(같은 종류의 기존 잔액부터 사용)**로 판정합니다. 후속 충전/무료 지급이 이전 패키지 사용 기록을 지우지 않습니다. 유료/무료 각각 원결제 이전 잔액으로 사용량을 충당할 수 있었고 원지급분 전체가 회수 가능해야 합니다.
- 사용·잔액 부족·사용 이력 불명확·7일 경과는 **자동 전액 환불 경로를 중단하고 CS 검토**로 보냅니다. 다른 주문 환불/관리자 차감도 보수적으로 사용량에 포함하므로 자동 판정이 실제보다 엄격할 수 있습니다. 이는 법적 환불권의 일괄 부인이 아닙니다.
- **법률 초안/전문가 검토 필요**: 7일은 기본 청약철회 원칙입니다. 계약서면 미교부/공급시점/철회 방해, 일부 미사용 잔여분, 표시·광고와 다른 이행·하자, 미성년자/법정대리인 동의, 도용·분쟁 등의 예외는 별도 CS/법정 권리로 검토해야 합니다. “디지털 재화라 지급 즉시 무조건 환불 불가” 또는 “조금 썼으니 남은 금액도 전부 환불 불가”라고 고지하면 안 됩니다. 부분 환급이 필요한 사안은 이 전액 환불 버튼으로 처리하지 않습니다.
- 법적 청약철회 기간은 실제 계약·공급·고지 자료를 기준으로 판단해야 하며, 위 `paid_at` 제한은 자동처리 편의상 기준입니다. 기간 내 접수했으나 관리자가 늦게 처리한 신청 등도 CS 예외 처리 대상입니다. **실결제 출시 전 고객지원 접수/처리 절차·법정 환급기한·고지·약관 확정이 필요**합니다.

### 서버 처리와 장애 복구

1. Edge가 Auth로 사용자 확인 → `admin_check` 검증 → 사용자 JWT로 관리자 전용 준비 RPC. RPC도 `_admin_guard`를 다시 검사합니다.
2. 같은 주문 행 + 기존 재화 차감과 동일한 지갑 행을 잠그고 미사용/기간/잔액을 검사합니다. **PG 호출 전에 유료+무료 보너스를 한 트랜잭션으로 임시 회수**하고 `refund_hold` 원장 + `payment_refunds` 한 행 + `cancel_status=processing`을 저장합니다. 중간 실패는 모두 롤백됩니다. 보류분은 다른 구매에서 쓸 수 없고 지갑은 음수가 되지 않습니다.
3. 서버에 저장된 paymentKey/금액만 사용하여 Toss GET 확인 → `POST /v1/payments/{paymentKey}/cancel`. 고정 사유 `미사용 상품 청약철회`, 원금 전액, 원금과 같은 `refundableAmount`, 주문별 고정 **`vr-refund-<orderId>`** 멱등키입니다. 브라우저에서 금액/key/대상 유저를 받지 않습니다.
4. POST 응답을 그대로 믿지 않고 **다시 GET**으로 주문/key/KRW/원금/잔액 0/`CANCELED`/완료된 취소 거래 합계와 고유 거래 키를 검증하고 취소 금액·시각·최소 취소 증빙을 저장합니다. 재호출은 원장을 다시 차감하지 않습니다. 취소 확인 대기에는 짧은 POST 제한시간 뒤 같은 호출 안에서 재조회를 시도합니다.
5. **타임아웃/PG 오류/DB 응답 유실은 실패 확정이 아닙니다.** 보류 재화를 자동 반환하지 않습니다. 같은 주문 **환불 다시 확인**으로 재조회/동일 멱등키 재시도. Toss 취소 성공 후 DB 확정 실패도 재조회로 완결합니다. 15일 멱등키 보관기간에 대비해 보류 생성 14일 이후 새 POST를 금지하고 CS 검토로 넘기지만, 이미 취소된 건의 GET/DB 확정은 가능합니다.
6. 지속 오류·취소 증빙 불일치·부분 취소는 `review` 또는 처리 대기로 남겨 **CS에서 PG와 DB를 대사**합니다. **보류 해제/예외 환급의 자동 버튼은 없습니다.** 임의 수동 재지급·새 멱등키 재시도를 하지 마세요. 취소 불성립이 확정된 보류 해제는 별도 운영자 검토/승인 후 처리해야 합니다. 이 제한도 실결제 전 보강할 운영 항목입니다.

### DB 상태/보존

- 원결제 `status=paid`, `receipt`, `paid_at`은 **최초 승인·지급의 역사 기록**으로 유지합니다. **현재 환불 상태는 `cancel_status`**, 누적 취소 금액은 `cancel_amount`, PG 완료 시각은 `canceled_at`입니다. 순매출 계산은 원결제 금액에서 취소 금액을 빼고 보류/검토 상태를 별도로 대사해야 합니다.
- `payment_refunds`에는 요청 관리자 UUID, 원금·회수 재화 수량, 고정 멱등키, 처리 상태, 시각, 취소 거래 키/금액/시각/완료 여부만 보관합니다. RLS + client 권한 없음. 카드번호·시크릿·전체 Toss 응답은 저장하지 않습니다.
- 환불 처리 중/완료/검토 주문의 confirm/settle을 서버에서 차단합니다. 과거 성공 콜백으로 재지급되지 않으며 클라이언트도 종료된 재확인 자료를 정리합니다.
- 승인 전 닫기/실패는 인증된 본인 요청으로 `checkout_status=canceled/failed`, `closed_at` 저장. **이미 paymentKey가 바인딩됐거나 지급된 주문은 fail URL만으로 바꾸지 않습니다.** 브라우저 강제 종료는 콜백이 보장되지 않으므로 미바인딩 주문을 30분 후 **다음 주문 생성/관리자 목록 조회 시 서버에서 expired**로 반영합니다. 별도 스케줄러는 없습니다.

```sql
-- 읽기 전용: staging 관리자 SQL Editor에서 확인. 날짜는 KST.
select order_id, amount, status, checkout_status, cancel_status, cancel_amount,
       paid_at at time zone 'Asia/Seoul' as paid_at_kst,
       canceled_at at time zone 'Asia/Seoul' as canceled_at_kst
from public.payment_orders order by created_at desc limit 20;
```

### staging 환불 확인법

1. 테스트 결제로 **심연석 100** 또는 보너스 포함 패키지를 구매하고 **아직 쓰지 마세요**. 환불 전 유료/무료 잔액을 기록합니다.
2. 관리자 계정 로그인 → 위 관리 페이지 → 해당 주문 **전액 환불** → **환불 완료**, 취소 금액=원결제 전액 확인.
3. 구매 계정 게임 새로고침 → 유료 기본분/무료 보너스만큼 각각 줄었는지 확인. 관리자 페이지 다시 확인/중복 요청·성공 콜백 새로고침에도 추가 환불/추가 차감/재지급이 없어야 합니다.
4. 별도 계정에서 패키지를 구매해 **그 패키지의 심연석이나 보너스를 실제 사용** → 환불 시 **고객지원 확인** 및 PG 취소 없음. 기존 무료/유료 잔액으로 쓴 경우에는 FIFO에 따라 해당 패키지가 아직 미사용일 수 있습니다.
5. 결제창 취소/실패 복귀 → 관리자 목록의 종료 상태 확인. 승인 대기/완료 주문의 fail URL을 재방문해도 유료 지급/승인 정보가 취소되면 안 됩니다.
6. 네트워크 끊김이면 같은 주문 **환불 다시 확인**. 토스 테스트 상점 거래의 취소도 확인합니다. 실제 키·카드·실결제는 사용하지 않습니다.

### 토스 대시보드 취소 대사 (staging 웹훅)

게임 밖(토스 개발자센터/대시보드)에서 취소되면 `PAYMENT_STATUS_CHANGED`만 받습니다. 국내 카드·간편결제의 취소는 이 이벤트입니다. `CANCEL_STATUS_CHANGED`는 해외 비동기 간편결제 전용이라 등록하지 않습니다. 가상계좌 `DEPOSIT_CALLBACK`도 등록하지 않습니다.

웹훅 JSON의 상태·금액·사용자는 사용하지 않습니다. 서명이 맞으면 저장된 paymentKey로 결제 조회 API를 다시 호출하고, 그 결과만 주문·취소 금액·원장에 반영합니다. `PAYMENT_STATUS_CHANGED`에는 `eventId`가 없고, `tosspayments-webhook-transmission-id`는 재전송마다 바뀌므로 중복 방지에 쓰지 않습니다. 같은 주문은 원장 ref `toss-refund-hold:<orderId>`로 한 번만 회수합니다.

- 전액 `CANCELED`이고 관리자 환불과 같은 FIFO로 그 패키지가 미사용이면 유료·보너스를 회수하고 **외부 취소 반영**입니다. 이미 관리자 환불 보류가 있으면 그 보류를 끝내며 다시 빼지 않습니다.
- 일부만 취소(`PARTIAL_CANCELED`)면 심연석을 비율로 깎지 않습니다. PG 취소 금액만 기록하고 **외부 부분취소**입니다.
- 이미 쓴 패키지는 잔액이 있어도 미사용으로 보지 않습니다. 지갑을 음수로 만들지 않고, PG 실패로 적지 않습니다. **외부 취소 · 재화 불일치**로 남기고 재화를 새로 만들지 않습니다.
- 관리자 전액 환불이 진행 중인데 조회가 부분 취소면 DB를 확정하지 않고 503을 돌려 토스가 다시 보내게 합니다. 전액 취소로 조회되면 보류분을 그대로 완료합니다.
- 결제 완료 통지가 나중에 도착해도 이미 회수한 심연석을 되돌리지 않습니다.

200이 10초 안에 없으면 토스는 1, 4, 16, 64, 256, 1024, 4096분 간격으로 최대 7회(최초로부터 약 3일 19시간) 재전송한 뒤 이메일로 알립니다. 개발자센터에서 **다시 시도**할 수 있습니다. 서명이 틀리거나 10분을 벗어난 전송 시각이면 401이며 원장은 바꾸지 않습니다.

#### 형님이 하실 일

1. staging SQL Editor에서 환불 SQL 다음으로 **`supabase/payments_webhook_staging.sql` 전체**를 실행합니다. 식별자가 아니면 중단됩니다. 주문·원장은 지우지 않습니다. 환불 SQL을 다시 실행했다면 이 파일을 그 다음에 다시 실행합니다.
2. 기존 `TOSS_SECRET_KEY` / `TOSS_CLIENT_KEY`는 바꾸지 않습니다. Supabase staging → Edge Functions → Secrets에 **`TOSS_WEBHOOK_SECRET`만 추가**합니다. 값은 토스 개발자센터 웹훅 화면의 **보안 키**입니다. API 시크릿 키(`test_sk_…`)가 아닙니다. 채팅·저장소에 넣지 마세요.
3. Edge Functions → 새 함수 **`payments-webhook-v1`** → `supabase/functions/payments-webhook-v1/dashboard_single_file.ts` 전체를 붙여넣고 배포합니다. **Verify JWT / JWT 검증 OFF.** 토스는 Supabase JWT를 보내지 않습니다. 기존 `payments-confirm-v1`은 **JWT ON을 유지**하고, 이번 변경으로 다시 배포하지 않습니다.
4. 토스 개발자센터 **테스트 상점** 웹훅에 URL `https://cuyqchmdcnsgzkwyclji.supabase.co/functions/v1/payments-webhook-v1` 와 이벤트 **`PAYMENT_STATUS_CHANGED`만** 등록합니다. 운영 상점에는 등록하지 않습니다.
5. 화면 문구는 staging Worker 배포 후 `admin-payments.html` 새로고침으로 보입니다. 배포 브랜치는 이 웹훅 브랜치여야 합니다. `origin/staging`만 배포하면 아직 병합되지 않은 구매자·결제 시각 표시가 빠집니다.

### 아직 제외한 범위

**정기 폴링, 가상계좌, 해외 비동기 `CANCEL_STATUS_CHANGED`, 차지백 자동화, 부분 취소 금액에 맞춘 심연석 분할 회수, CS 보류 자동 해제**는 없습니다. 7회 재전송이 모두 실패하면 토스 이메일의 **다시 시도**로 같은 웹훅을 다시 보냅니다. 운영 Worker/DB/main에는 적용하지 않았습니다.

결제 주문은 금융 기록 보존 검토를 위해 계정 삭제 시 `RESTRICT`로 남깁니다. 향후 계정 탈퇴/법정 보존/익명화·처리방침에도 반영해야 합니다. 실결제 전에는 PG 계약·게임 등급·연령/보호자 결제·환불 동의·확률 공개·약관 및 개인정보의 토스 처리/보유/국외이전 고지도 별도로 확정해야 합니다.

## 공식 자료 (이번 작업에서 확인)

- https://docs.tosspayments.com/guides/v2/payment-window/integration
- https://docs.tosspayments.com/sdk/v2/js/payment
- https://docs.tosspayments.com/reference/using-api/api-keys
- https://docs.tosspayments.com/reference/using-api/authorization
- https://docs.tosspayments.com/guides/v2/payment-window/integration.md (현재 키 자리표시자 확인)
- https://docs.tosspayments.com/reference (Payment, confirm, 조회, 취소)
- https://docs.tosspayments.com/guides/v2/cancel-payment.md (전액 취소·멱등키·거래 증빙)
- https://docs.tosspayments.com/reference/using-api/authorization.md (멱등키 15일·중복 처리)
- https://www.law.go.kr/LSW/lsLinkCommonInfo.do?lsJoLnkSeq=1029561411 (전자상거래법 제17조, 2026-07-21 시행)

현재 공식 문서에서는 `test_ck_/test_sk_` 방식이 **결제창(구버전) / API 개별 연동**으로 분류됩니다. 이 구현은 API 개별 연동 경로를 사용하며, `test_gck_/test_gsk_` 주문서형·신규 결제창형 키와 혼용하지 않습니다.
