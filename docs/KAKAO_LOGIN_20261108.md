# 카카오 로그인 설정 (staging 먼저)

코드는 카카오 공급자가 켜져 있을 때만 버튼을 표시합니다. 공개 Auth 설정 조회가 실패하면 카카오는 숨기고 구글은 유지합니다. 설정 저장 후 게임을 새로고침하세요. 운영 main/Worker에는 아직 반영하지 않습니다.

## 형님이 하는 순서

1. **staging Supabase SQL Editor**에서 `supabase/kakao_profile_staging.sql` **이 작은 파일만** 실행합니다. `cuyqchmdcnsgzkwyclji` DB 고유번호를 검사하며, 운영에서는 중단됩니다. 이메일/초기 이름이 빈 계정의 가입·관리자 초기화 실패를 막습니다. 기존 닉네임·진행도·재화는 변경하지 않습니다. 기존 대형 설치 SQL 재실행은 필요 없습니다.
2. [Kakao Developers](https://developers.kakao.com/) → **앱 만들기**: 앱 이름/아이콘/회사명/카테고리/대표 도메인을 입력합니다. staging/운영 앱은 분리 권장입니다. 카카오 로그인 → 일반 → **사용 ON**.
3. **앱 → 플랫폼 키 → REST API 키**를 선택합니다. 예전 콘솔의 Web 사이트 도메인/새 콘솔의 웹 도메인(제품 링크 관리)에 등록할 게임 주소는 아래와 같습니다. Supabase REST OAuth 방식이라 **JavaScript SDK 키/SDK 도메인은 로그인에 필수 아님**입니다. 사이트 도메인과 다음 단계의 Redirect URI는 다른 값입니다.

   - `https://vr-tcg-staging.notcold.workers.dev` (테스트)
   - `https://ag.violenceroyale.com` (운영)
   - `https://vr-tcg-prod.notcold.workers.dev` (운영 Worker)
   - `https://tcg.mbbs.kr` (기존 운영)

4. 위 **REST API 키 편집 → 카카오 로그인 Redirect URI**에 등록합니다. 앱을 분리했다면 해당 환경 것만, 앱을 공유한다면 둘 다 등록합니다.

   - staging: `https://cuyqchmdcnsgzkwyclji.supabase.co/auth/v1/callback`
   - 운영(나중에): `https://htarwisgkkphutxxnuak.supabase.co/auth/v1/callback`

5. **카카오 로그인 → 동의항목**에서 닉네임(`profile_nickname`)·프로필 사진(`profile_image`)을 설정합니다. 게임은 이메일이 필요 없습니다. 이메일(`account_email`)은 Biz 앱에서만 설정 가능하며, 요청하더라도 **선택 동의**로 둡니다. 이메일 미제공 시에도 UUID로 가입·닉네임 설정·CH0/스타터 선택을 진행합니다.
6. **앱 → 플랫폼 키 → REST API 키**의 **REST API 키**가 Supabase의 **Client ID**입니다. 같은 편집 화면의 **카카오 로그인 Client Secret 코드**를 발급하고 **활성화**합니다. JavaScript 키/네이티브 키/어드민 키를 넣는 것이 아닙니다.
7. staging Supabase → **Authentication → Sign In / Providers → Kakao**: Enable ON, 위 Client ID/Client Secret을 **형님이 직접 대시보드에** 붙이고 저장합니다. **Allow users without an email ON**. 키/Secret은 채팅·저장소·브라우저 코드로 보내지 않습니다.
8. Supabase → **Authentication → URL Configuration → Redirect URLs**에 `https://vr-tcg-staging.notcold.workers.dev/`를 추가합니다. 게임의 현재 경로로 돌아오므로 `/index.html`로도 접속한다면 그 주소도 추가하세요. 기존 Site URL/구글 설정은 바꾸지 않습니다. 운영 배치 때는 위 운영 세 호스트 각각 `/`와 실제 사용하는 `/index.html`을 추가합니다. 이번 UI 작업은 관리자 로그인을 변경하지 않습니다.
9. 기존 구글 계정에 카카오를 붙이려면 Supabase의 **Allow manual linking**도 켭니다. 기존 구글 로그인 → 게임설정 **카카오 연결**을 사용합니다. 카카오 계정에서 **구글 연결**도 가능합니다. 이미 두 개로 가입한 계정은 클라이언트에서 임의 병합하지 않습니다.
10. staging 게임 새로고침 → 구글 옆 카카오 버튼 확인 → 아래 테스트를 합니다. **운영 Kakao provider/SQL 활성화는 다음 운영 배치 때** 합니다. 운영 전용 동반 파일은 `supabase/kakao_profile_production.sql`이며, 운영 DB 고유번호를 검사합니다. Edge 재배포는 없습니다.

## 이메일 권한 주의: KOE205가 뜨면

Supabase 공식 문서는 `account_email` 없이 가입할 수 있다고 안내하지만, 확인한 upstream Kakao 구현은 기본 scope에 여전히 `account_email`을 넣습니다. 이 부분을 제거하는 [upstream PR #2579](https://github.com/supabase/auth/pull/2579)는 확인 시점에 미병합입니다. 따라서 **실제 Supabase Auth 배포 버전에 따라**, 이메일 권한이 없는 일반 앱은 동의 화면 전에 `KOE205 (account_email)`로 막힐 수 있습니다.

- 먼저 이메일 동의 없이 + **Allow users without an email ON**으로 staging에서 실제 확인합니다.
- `KOE205 account_email`이면 **Biz 앱 전환 후 account_email을 선택 동의**로 설정하는 방식이 필요할 수 있습니다. 개인 개발자도 카카오의 본인인증·비즈니스 약관 절차로 사업자번호 없는 Biz 앱 전환이 가능한지 콘솔에서 확인하세요. 이메일 제공을 게임 이용의 필수 조건으로 만들지는 않습니다.
- `scopes`를 브라우저에서 빈 값으로 바꾸는 것은 서버 기본 scope를 제거하지 못하므로 우회 코드를 넣지 않았습니다. Secret 오류/Redirect URI 오류와 KOE205는 구분해서 확인하세요.

## 계정 연결 원칙

- 데이터는 **Supabase user UUID** 기준입니다. 이메일/닉네임이 같다고 브라우저가 다른 계정을 합치지 않습니다.
- Supabase가 검증된 동일 이메일 identity를 자동 연결할 수 있지만, 이메일이 없거나 다르면 같은 사람인지 추정할 수 없습니다. **기존 계정 로그인 상태에서 연결**하는 것이 안전합니다.
- 이미 별도 계정에 붙은 로그인은 연결 실패를 표시하고 원래 계정/진행도는 유지합니다. 관리자 이메일 권한은 그대로이며, 카카오 닉네임으로 관리자 권한을 주지 않습니다.
- OAuth PKCE·리다이렉트 처리는 구글과 동일합니다. 연타로 PKCE verifier가 덮이지 않게 잠그며, 취소/실패 콜백의 민감 파라미터는 URL에서 제거합니다.

## staging 확인표

- [ ] 공급자 OFF: 구글만 표시, 게스트/기존 구글 로그인 정상.
- [ ] 공급자 ON: 인트로·상단 계정 영역에 카카오 버튼, 다른 로그인 진입점도 공급자 선택 가능.
- [ ] 카카오 신규(이메일 동의 안 함): 닉네임 정하기 → 스토리 CH0 → 기존 강제 소환/스타터 선택 경로 정상.
- [ ] 로그아웃 후 같은 카카오로 복귀: 같은 UUID/닉네임/진행도.
- [ ] 구글 기존 계정 → 카카오 연결 → 카카오로 재로그인: 기존 UUID/진행도 유지.
- [ ] 이미 다른 계정에 연결됨/동의 취소/로그인 실패: 기존 진행도 손상 없음, 재시도 가능.
- [ ] PC Chrome + iPhone Safari, 특히 인앱브라우저→브라우저 복귀 실제 확인.

자동 테스트는 SDK mock·이메일 없는 프로필·UUID 격리·DB 트리거 회귀를 검증합니다. 키 설정 전 실제 카카오 OAuth/카카오톡 인앱 전환까지 성공했다고 보장하지 않습니다.

버튼 심볼은 [카카오 공식 리소스](https://developers.kakao.com/tool/resource/login)의 원형을 유지하고 노란 컨테이너/검은 심볼을 사용합니다. 좁은 상단 버튼만 공식 축약형인 「로그인」을 씁니다.

공식 참고: [Supabase Kakao](https://supabase.com/docs/guides/auth/social-login/auth-kakao), [계정 연결](https://supabase.com/docs/guides/auth/auth-identity-linking), [카카오 앱 설정](https://developers.kakao.com/docs/ko/app-setting/app), [플랫폼 키 변경 안내](https://developers.kakao.com/docs/ko/getting-started/app-key-migration).

## 계정 연결 복귀 오류 수정 (후속)

- 연결할 구글 계정이 이미 다른 staging 사용자에게 속해 있으면 Supabase는 `identity_already_exists`로 연결을 거절합니다. **이미 따로 있는 두 계정을 합치는 기능이 아닙니다.** 신규 메시지는 「이미 다른 계정에 연결된 구글 계정이에요.」입니다. 기존 계정/진행도는 삭제·이동하지 않습니다.
- 이전 화면은 콜백의 오류 종류를 버리고 모두 「취소되었거나 완료되지 않았어요」로 표시했습니다. 또한 현재 고정 SDK(auth-js 2.65.0)는 PKCE의 오류 전용 URL을 잘못 처리해 기존 로그인 세션까지 제거하는 동작이 실제 SDK 테스트에서 재현되었습니다. 오류를 안전하게 분류·제거한 뒤 SDK를 초기화해 기존 세션을 보존합니다.
- 정상 `?code=`는 SDK가 **딱 한 번** 교환합니다. 앱이 추가로 수동 교환하지 않습니다. 연결 시작 계정/공급자/시각만 탭 저장소에 임시 보관하고(토큰·코드·원문 오류 저장 없음), 복귀 시 `auth.getUser()`의 서버 identity와 동일 UUID로 실제 연결 여부를 확인합니다. 연결된 상태면 성공, 다른 계정에 속했으면 충돌, 확인 통신 실패면 미확인으로 구분합니다.
- 공개 `/auth/v1/settings`는 구글/카카오 ON 여부만 보여 주며 **Allow manual linking 값은 노출하지 않습니다**. 그 설정이 OFF라면 연결 시작 API에서 곧바로 거절되므로 공급자 동의 화면 이후 복귀하는 현상과 구분됩니다. `manual_linking_disabled`일 때만 Supabase **Authentication → Sign In / Providers → Allow manual linking** 설정을 확인하세요. 이번 수정은 SQL/Edge/대시보드 설정 변경이 없습니다.
- 기존 실패 URL은 이전 코드가 이미 지웠으므로, 익명 조회만으로 형님 계정의 원래 오류 코드나 identity 소유자를 단정할 수는 없습니다. 새로고침 후 같은 연결을 한 번 더 시도하면 구체적인 결과가 나옵니다. 콜백 URL 전체/토큰을 채팅으로 보내지 말고 결과 문구만 확인하세요.
- 개발 회귀 테스트는 기존 브라우저 SDK와 정확히 같은 auth-js 버전을 사용합니다. 해당 구버전의 malformed-path 관련 low advisory는 기존 런타임에도 해당하는 별도 SDK 유지보수 항목입니다. 이 UI는 공급자를 고정된 google/kakao/x/twitter만 허용하며 버전을 임의 업그레이드하지 않았습니다.

- 후속 회귀: SDK의 오래된 `INITIAL_SESSION`/동일 UUID `SIGNED_IN` 알림이 서버에서 확인한 연결 상태를 덮어쓰지 않도록 했다. 실제 `USER_UPDATED`/`TOKEN_REFRESHED`와 계정 변경은 계속 반영한다.
