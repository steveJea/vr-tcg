# 포트원 + 다날 휴대폰 본인인증 (테섭 연동)

형님이 포트원 콘솔에서 직접 가입·신청합니다. 이 문서는 나중에 건네줄 공개 값과, **채팅에 붙여 넣으면 안 되는** 시크릿 위치를 적습니다.

## 테섭에 이미 넣어 둔 것
- 플래그 `age_verification_required`가 꺼져 있으면 인증 창을 열지 않습니다.
- Store ID·채널 키가 비어 있으면 SDK를 부르지 않습니다.
- 모바일 복귀 주소는 코드에 있습니다.
  - 테섭: `https://vr-tcg-staging.notcold.workers.dev/age-verify-return.html`
  - 실섭(나중에): `https://ag.violenceroyale.com/age-verify-return.html` (이번 배포에는 운영 빌드에 넣지 않음)
- 본인인증은 포트원 결제 웹훅이 필요 없습니다. 인증 결과는 서버가 `GET https://api.portone.io/identity-verifications/{id}` 로 조회합니다.

## 형님이 가입 후 준비하는 값
채팅에 주셔도 되는 공개 값:
- 상점 아이디(Store ID) — 콘솔 [결제 연동] → [연동 관리]
- 본인인증 채널의 채널 키(Channel Key) — [결제 연동] → [연동 관리] → [채널 관리], 채널 속성 **본인인증**

채팅·깃에 절대 넣지 말 것:
- V2 API Secret — [결제 연동] → [연동 관리] → [식별코드·API Keys] → [V2 API] → 새로운 API Secret 발급. 발급 직후에만 보임.
- 넣는 곳: 테섭 Supabase **Edge Functions → Secrets** 이름 `PORTONE_API_SECRET`. 안전한 비밀 입력으로만 전달.

권장(공개 값, 서버 검증용):
- 같은 Store ID를 시크릿 `PORTONE_STORE_ID`로도 넣으면 조회 요청에 상점을 고정합니다.

Edge Function `age-verify-v1` 은 테섭에 배포하고 Verify JWT 를 켭니다. JWT 검증용 시크릿은 기존 결제 함수와 같습니다.

## SQL
테섭 SQL 편집기에서 `supabase/age_verify_staging.sql` 실행, `supabase/age_verify_check_staging.sql` 로 확인.
