# 테스트 서버 준비 안내

## 먼저 알아둘 점

- 이 변경은 **준비용**입니다. 새 Supabase 프로젝트 생성·SQL 실행·Cloudflare 연결·DNS 변경은 아직 하지 않았습니다.
- 운영은 그대로 `tcg.mbbs.kr` + 기존 Supabase입니다. 기존 GitHub Pages 배포와 CNAME은 건드리지 않습니다.
- 테스트는 **별도 사이트 + 별도 Supabase 프로젝트**로 분리합니다. 주소만 나누고 DB를 같이 쓰면 테스트가 아닙니다.
- 테스트의 카드·젬·진행 기록은 운영에 옮기지 않습니다. 운영 회원 자료도 테스트에 복사하지 않습니다.
- 이번 작업은 앞서 찾은 보상·전투 검증 문제의 수정본이 아닙니다. 서버를 나눈 뒤 별도 보안 작업이 필요합니다.

## 역할 구분

- 제가 PR로 준비하는 것: 접속 설정 통합·운영 DB 연결 차단·TEST 표시·Cloudflare 배포 파일·빈 테스트 DB 설치본·검사 도구. 공개 테스트 URL/키와 사이트 주소가 정해지면 그 값 반영도 PR로 할 수 있습니다.
- 형님이 직접 하시는 것: 새 Supabase 프로젝트 생성, 그 프로젝트에서 SQL 실행, Google 로그인 제공자 설정, Cloudflare의 GitHub 연결/배포 브랜치 선택, 필요할 때 DNS 연결. 계정 권한·비공개 입력은 형님 화면에서 처리합니다.

## 형님이 직접 하실 일 — 순서대로

### 1. Supabase에 새 테스트 프로젝트 만들기

1. 새 프로젝트를 만들고 이름을 `vr-tcg-staging`처럼 구별해 주세요. 운영 프로젝트 `htarwisgkkphutxxnuak`은 선택하지 마세요.
2. 지역은 운영과 같게, 아직 구글 로그인은 하지 않은 빈 프로젝트로 준비합니다.
3. 프로젝트의 **Project URL**과 **anon 또는 publishable 키**를 확인합니다. 둘은 공개 설정 값이라 저장소에 넣어도 됩니다.
4. 비밀 키·관리자 권한 키·DB 비밀번호는 이 작업에 필요하지 않습니다. 채팅이나 코드에 넣지 마세요.
5. 무료 프로젝트 할당이 남아 있으면 무료로 시작할 수 있지만 1주 미사용 시 정지될 수 있습니다. 같은 Pro 조직에 Micro 프로젝트를 추가하면 약 월 $10 추가입니다. 운영·테스트 Micro 두 개는 기본 약 월 $35, 초과 사용·세금 별도입니다.

### 2. 빈 테스트 DB에 분할 설치 SQL 실행

**통합 `supabase/staging_install.sql`은 SQL Editor 크기 제한을 넘으므로 붙여 넣지 않습니다.** 대신 [`supabase/staging/README.md`](../supabase/staging/README.md)의 01~10 분할본을 씁니다.

확인받은 테스트 DB 식별번호 **7703759698107299042 (18자리)**가 모든 분할 파일에 반영돼 있습니다. 운영 DB 번호 조회나 파일 수동 편집은 필요 없습니다.

1. Supabase 화면이 테스트 프로젝트 `cuyqchmdcnsgzkwyclji`인지 확인합니다. 운영에서 설치 실행 금지입니다.
2. 같은 커밋의 `supabase/staging/01_install.sql`부터 `10_install.sql`까지 **파일 하나 전체씩 순서대로** 붙여 실행합니다. 매번 성공 메시지 확인 후 다음 번호로 갑니다.
3. DB 식별번호 불일치/조회 오류가 나오면 중단합니다. 번호를 임의로 바꾸거나 guard를 삭제하지 말고 오류를 알려주세요.
4. 이미 완료한 파일은 재실행해도 건너뜁니다. 오류가 난 파일은 그 파일만 되돌아가므로 원인을 확인한 뒤 같은 파일부터 재개합니다. 앞선 성공 파일을 지우거나 전체 DB를 초기화하지 않습니다.
5. 마지막 파일까지 성공하기 전에는 회원 가입/로그인을 하지 마세요. 설치 중 API 접근은 차단되며 마지막에 개방됩니다.
6. 예전 `schema.sql`이나 폴더 전체 SQL을 추가 실행하지 마세요. 옛 함수로 덮어써질 수 있습니다.

설치본은 새 테스트 DB 전용입니다. 운영 회원/결제 자료, 기존 사용자 환급 및 운영 조회 스크립트를 넣지 않습니다. 원본 관리자 판정 규칙은 유지하며 기존 보안 문제를 고치는 작업은 아닙니다.

검증: 빈 PostgreSQL(WASM/PGlite)에 전체 설치·함수 578개 재컴파일, RLS/내부 함수 권한, 분할 설치 순서·재실행·오류 롤백을 검사합니다. 실제 Supabase에 SQL을 실행하거나 Google 로그인·메일·화면 동작까지 확인한 것은 아닙니다.

### 3. 테스트용 구글 로그인 설정

1. 테스트 Supabase의 Google 로그인 제공자를 켭니다. 필요한 비공개 값은 형님이 해당 서비스 화면에서 직접 입력합니다.
2. Google Cloud OAuth의 **승인된 리디렉션 URI**에 테스트 Supabase 화면이 안내하는 주소를 추가합니다. 보통 `https://새테스트프로젝트ID.supabase.co/auth/v1/callback`입니다. 이것은 게임 주소가 아닙니다.
3. Cloudflare에서 테스트 주소가 정해지면 테스트 Supabase의 **Site URL**을 `https://실제테스트주소/`로 설정합니다.
4. 테스트 Supabase의 **Redirect URLs**에 `https://실제테스트주소/`와 `https://실제테스트주소/admin.html`을 추가합니다. 로컬 테스트가 필요할 때만 `http://localhost:8787/`와 `/admin.html`도 추가합니다.
5. 자체 주소를 나중에 붙이면 Google 설정과 별개로 Supabase Site URL/Redirect URLs에도 새 주소를 추가합니다. 운영 Supabase의 기존 설정은 그대로 둡니다.
6. OAuth 앱이 테스트 모드라면 Google 쪽 테스트 사용자 목록에 실제로 확인할 계정을 추가해야 할 수 있습니다.

### 4. 코드의 공개 테스트 설정 채우기

`js/config.js` 위쪽 `STAGING`의 세 곳만 바꿉니다. 변경은 PR로 남겨 검토합니다.

- `supabaseUrl`: 새 테스트 Project URL
- `anonKey`: 새 테스트 anon 또는 publishable 키
- `hostnames`: 실제 테스트 사이트의 정확한 호스트 이름 (https://와 경로는 빼기)

`vr-tcg-staging.notcold.workers.dev`는 실제 테스트 주소입니다. `dev-tcg.mbbs.kr`을 쓰지 않으면 목록에서 빼도 됩니다. 모든 `workers.dev` 주소를 통째로 허용하지 않습니다.

설정 전에는 테스트 DB에 접속하지 않고 `TEST · DB 미설정`만 표시합니다. 운영 URL/키를 잘못 넣거나, 등록하지 않은 주소에서 열어도 운영 DB로 자동 연결하지 않습니다. 등록된 테스트 주소의 작은 `TEST` 표시는 관리자 화면에도 나옵니다.

### 5. Cloudflare에 테스트 사이트만 연결

이 저장소는 GitHub Pages 운영용이므로 기존 Pages 설정은 바꾸지 않습니다. Cloudflare 쪽에 **별도 Worker**를 만듭니다.

1. Cloudflare Workers의 GitHub 연결에서 `steveJea/vr-tcg` 저장소 접근을 승인합니다.
2. 검토한 준비 변경으로 `staging` 브랜치를 만듭니다. 처음 연결하기 전에는 적어도 환경 분리 코드가 이 브랜치에 있어야 합니다. 운영 코드를 그대로 복사해 테스트 주소로 배포하면 안 됩니다.
3. Worker 이름: `vr-tcg-staging`, 연결 브랜치(배포 기준 브랜치): **staging**. `main`을 선택하지 마세요.
4. 루트 폴더: 저장소 루트. Node.js 22 이상. 의존성 설치: `npm ci`.
5. Build command: `npm run check:staging && npm run test:staging && npm run build:staging`
6. Deploy command: `npx wrangler deploy`
7. 이 Worker의 다른 브랜치 자동 빌드/프리뷰는 우선 끕니다. `staging`만 자동 배포하고, 운영은 기존 GitHub Pages가 담당합니다.
8. 최초 발급된 `https://vr-tcg-staging.계정서브도메인.workers.dev/`를 확인하고 3·4번의 로그인/호스트 설정을 마무리한 뒤 재배포합니다. 처음 주소가 목록에 없으면 DB 접속은 차단됩니다.

`wrangler.jsonc`는 테스트 전용입니다. SQL·도구·문서·CNAME은 업로드하지 않고, 게임 웹 자산만 `.staging-dist`에 복사합니다. 테스트 사이트는 검색 제외 설정을 넣지만, **주소를 아는 사람은 열 수 있는 공개 사이트**입니다. 검색 제외는 비밀번호 보호가 아닙니다. 실제 결제는 연결하지 않습니다.

### 6. 자체 주소는 나중에 선택

처음에는 `workers.dev` 주소면 충분하므로 DNS 작업은 필요 없습니다. 원하면 Cloudflare에서 `dev-tcg.mbbs.kr`을 이 테스트 Worker의 Custom Domain으로 연결합니다. DNS/인증서 안내를 따른 뒤 `hostnames`와 테스트 Supabase의 로그인 복귀 주소를 맞춥니다. 운영 `tcg.mbbs.kr`의 DNS는 건드리지 않습니다.

## 이제부터 배포하는 순서

1. 기능 브랜치에서 작업 → PR 검토.
2. 테스트할 코드를 `staging`에 반영 → 테스트 주소 자동 배포.
3. 형님 폰에서 확인: `TEST` 표시, 로그인/로그아웃, 아케이드 턴 종료, 스토리, 보상/젬, 카드 이미지, 음악·스킬 영상.
4. 운영 계정의 젬·진행도가 그대로인지 확인합니다. 테스트 DB가 별도임을 처음 한 번은 꼭 확인하세요.
5. 문제없을 때 형님 승인 → 같은 변경을 `main`에 반영 → 기존 방식으로 운영 배포.
6. DB 변경도 테스트 프로젝트에서 먼저 실행하고 확인한 뒤 운영에 적용합니다. 테스트 사용자 자료를 운영으로 복사하지 않습니다.

준비 PR을 올리거나 머지하는 것만으로 테스트 서버가 생기지는 않습니다. 위의 프로젝트 생성·설치·로그인·호스팅 연결이 필요합니다.

## 개발용 명령 (계정 연결 없이 검증)

```bash
npm ci
npm run check:staging
npm run test:staging
npm run build:staging
WRANGLER_SEND_METRICS=false npx wrangler deploy --dry-run
```

- 로컬 서버는 `npm run build:staging && npx wrangler dev`로 켭니다. 이 명령은 배포하지 않습니다.
- 로컬은 기본으로 DB 접속 차단입니다. 설정을 채운 뒤 `http://localhost:8787/?vrEnv=staging`처럼 **명시한 경우만** 테스트 DB를 씁니다.
- 꼭 운영 연결이 필요한 개발자만 `?vrEnv=production`을 선택할 수 있습니다. 운영 DB에 실제 영향을 주므로 평소에는 사용하지 않습니다. 외부 주소에서는 이 플래그가 무시됩니다.
- SQL 소스/순서표 변경 후에는 `node tools/build_staging_sql.mjs`와 `node tools/build_staging_parts.mjs`로 설치본을 다시 만들고 테스트합니다. 새 SQL을 설치 순서표에서 빼먹으면 안 됩니다.
- PostgreSQL 서버 설치가 어려운 환경에서도 PGlite로 검증할 수 있습니다. 실제 Supabase 확장/인증 제공자/동시성/성능 검증을 대신하지는 않습니다.

## 비용·운영 공개 전 참고

정적 자산은 Cloudflare 무료 범위로 시작할 수 있습니다. GitHub Pages는 상거래 중심 무료 호스팅을 제한하므로, 유료 오픈 전에는 운영 호스팅 이전을 별도 계획으로 검토합니다. 이번 PR은 운영을 이전하지 않습니다.

- https://supabase.com/pricing
- https://developers.cloudflare.com/workers/static-assets/billing-and-limitations/
- https://developers.cloudflare.com/workers/ci-cd/builds/configuration/
- https://docs.github.com/en/pages/getting-started-with-github-pages/github-pages-limits
