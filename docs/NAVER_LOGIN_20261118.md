# 네이버 로그인 설정 — staging 먼저

Supabase에는 네이버 기본 공급자가 없어 **Custom OAuth 공급자 `custom:naver`** 와 userinfo 변환 함수 `naver-userinfo`를 사용합니다. 코드는 공급자가 켜져 있을 때만 버튼을 표시합니다. 이 작업은 운영 Auth/Worker/DB를 바꾸지 않습니다.

## 테섭 Custom Provider 입력값 (순서대로)

Supabase(테섭 `cuyqchmdcnsgzkwyclji`) → **Authentication → Sign In / Providers → Custom Providers**. Client ID/Secret은 형님이 대시보드에 직접 입력합니다. 채팅·저장소·브라우저 코드로 보내지 않습니다.

1. Configuration method / 유형: **Manual configuration (OAuth2)**. Auto-discovery(OIDC)는 쓰지 않습니다.
2. Display name / 이름: `네이버`
3. Identifier / 식별자: `custom:naver` (이 값 그대로)
4. Enable / 사용: **ON**
5. Issuer URL (칸이 있으면): `https://nid.naver.com`
6. Authorization URL: `https://nid.naver.com/oauth2/authorize`
7. Token URL: `https://nid.naver.com/oauth2/token`
8. Userinfo URL: `https://cuyqchmdcnsgzkwyclji.supabase.co/functions/v1/naver-userinfo`  
   (네이버 `https://openapi.naver.com/v1/nid/me`를 직접 넣지 않습니다.)
9. JWKS URI (칸이 있으면): 비우거나 `https://nid.naver.com/oauth2/jwks`
10. Client ID / Client Secret: 네이버 개발자센터 테섭 앱 값. 형님이 직접 입력.
11. Scopes: `profile` 만. `openid`를 넣지 않습니다.
12. PKCE: **ON** (기본값 유지)
13. Allow users without an email / 이메일 없이 가입 허용: **ON**
14. Callback URL(읽기 전용, 네이버 앱에 이미 등록됨): `https://cuyqchmdcnsgzkwyclji.supabase.co/auth/v1/callback`

네이버 개발자센터 테섭 앱: 사용 API = 네이버 로그인, 제공 정보는 이용자 식별자만, 서비스 URL `https://vr-tcg-staging.notcold.workers.dev`, Callback은 위 값. 검수 전에는 테스터/관리자 ID만 로그인됩니다.

## Edge Function `naver-userinfo`

네이버 프로필을 `{ sub, name?, nickname?, picture?, email? }` 형태로 바꿉니다. 시크릿은 없습니다. **JWT verification OFF** — Authorization 헤더는 네이버 access token입니다.

- 소스: `supabase/functions/naver-userinfo/`
- 대시보드 붙여넣기용: `supabase/functions/naver-userinfo/dashboard_single_file.ts` 전체
- 테섭 프로젝트 `cuyqchmdcnsgzkwyclji`에만 배포합니다. 운영 함수/키는 건드리지 않습니다.

## 계정 연결

기존 구글/카카오 진행도를 유지하려면 그 계정으로 로그인한 뒤 게임설정 **네이버 연결**을 사용합니다. **Allow manual linking**이 켜져 있어야 합니다. 이미 다른 계정에 붙은 네이버는 「이미 다른 계정에 연결된 네이버 계정이에요.」로 안내하며 계정을 합치거나 지우지 않습니다. 제공 정보를 식별자만 받으므로 같은 이메일 자동 병합은 하지 않습니다. 만 19세 확인은 기존 동의·본인인증 게이트를 쓰며 네이버 연령대는 쓰지 않습니다.

## staging 확인표

- [ ] 공급자 또는 함수 미배포: 네이버 버튼 숨김, 구글/카카오/게스트 정상.
- [ ] 공급자 ON + 함수 배포: 인트로·로그인 선택창·설정에 공식 초록 네이버 버튼.
- [ ] 테스터 네이버 신규(이메일 없음): 동의 → 닉네임 → CH0/스타터 경로 정상. 재로그인 시 같은 UUID.
- [ ] 기존 구글 계정 → 네이버 연결 → 네이버로 재로그인: 같은 UUID/진행도.
- [ ] 이미 다른 계정에 연결됨/취소/실패: 기존 진행도 유지, 구체적 안내.
- [ ] 운영 Auth/Worker는 변경하지 않음.

공식 참고: [Supabase Custom OAuth](https://supabase.com/docs/guides/auth/custom-oauth-providers), [네이버 로그인](https://developers.naver.com/docs/login/devguide/devguide.md), [사전 검수](https://developers.naver.com/docs/login/verify/verify.md/), [버튼 가이드](https://developers.naver.com/docs/login/bi/bi.md).
