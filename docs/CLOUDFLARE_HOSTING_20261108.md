# Cloudflare 정적 호스팅 1–2단계 (2026-11-08 KST)

## 범위 / 변경하지 않는 것

- staging Worker: `vr-tcg-staging` / `https://vr-tcg-staging.notcold.workers.dev`.
- 운영 콘텐츠 후보 Worker: `vr-tcg-prod` / `https://vr-tcg-prod.notcold.workers.dev`.
- 후보는 `main`의 운영 콘텐츠(기준 `12c5e005ce4c1e184b6e4ffe013aa2a21e6329f5`) + 이 호스팅 전용 변경. staging 전용 게임 변경을 가져오지 않는다.
- **tcg.mbbs.kr DNS·Custom Domain·GitHub Pages·main은 그대로**. 후보 생성은 tcg.mbbs.kr의 이전이 아니다. 후속 승인으로 아래 ag 서브도메인만 연결한다.
- DB는 그대로 Supabase. 운영 후보는 `htarwisgkkphutxxnuak`, staging은 `cuyqchmdcnsgzkwyclji`. SQL/Edge Function 재배포·데이터 이전 없음.
- 후보도 **실제 운영 계정·재화**를 사용한다. 임의의 테스트 보상/계정 생성/결제 테스트를 하지 않는다.

## iPhone/Safari 영상 Range

Cloudflare Static Assets는 Range를 무시하고 전체 파일을 200으로 돌려준다. 변경 전 opening.mp4의 `Range: bytes=0-1` 요청도 18,604,433바이트 전체 200이었다.

`worker/media-range.mjs`가 MP4/MP3만 가로채 ASSETS의 원본을 스트리밍으로 잘라 `206`, `Content-Range`, `Accept-Ranges: bytes`, 정확한 `Content-Length`로 반환한다. ASSETS 내부 응답에는 Content-Length가 빠질 수 있어 빌드 시 생성한 `worker/media-sizes.json`을 함께 번들한다. 자산과 크기 목록은 같은 버전으로 배포하며 두 빌드 모두 자동 생성한다. 전체 영상의 arrayBuffer 적재 없음. 시작/끝/접미 범위, 416, HEAD, ETag/If-Range/304, 취소를 처리한다. 다중·잘못된 범위는 RFC 허용대로 전체 200. 압축 표현/크기 미상은 무리하게 자르지 않는다.

`/*.mp4`, `/*.mp3` 라우팅은 하위 경로도 포함한다. 오프닝뿐 아니라 `video/story`, `data/fx/mr`, `img/gacha/video/v1`, `audio`, `data/voice`, `data/event` 전체를 포함한다. 이미지/HTML/JS는 기존 무료 정적 자산 경로를 유지한다. 미디어 요청만 Worker 실행량에 포함되므로 사용량을 관찰한다. 대규모 스트리밍/반복 seek는 추후 R2/전용 미디어 CDN 검토.

## 분리 빌드와 배포

```bash
npm ci
npm run check:staging
npm run test:staging
npm run build:staging
node tools/test_media_range_integration.mjs
# origin/staging을 기준으로 검증한 staging 작업트리에서만:
npm run deploy:staging

# main을 기준으로 검증한 운영 작업트리에서만 (이번에는 hosting-only PR 브랜치):
npm run build:production:worker
node tools/test_media_range_integration.mjs --production
npx --no-install wrangler deploy --config wrangler.production.jsonc
```

- staging `.staging-dist`와 운영 `.production-dist`를 절대 혼용하지 않는다.
- 배포 목록은 index/admin/favicon/js/css/data/img/audio/video만. SQL/tools/docs/설정/비밀파일 제외.
- 운영 후보만 hostname 한정 `X-Robots-Tag: noindex, nofollow`. staging robots.txt를 복사하지 않으며 tcg.mbbs.kr 검색 정책은 바꾸지 않는다.
- `wrangler.production.jsonc`: 정확한 계정/스크립트명, workers.dev 유지, 승인된 `ag.violenceroyale.com` Custom Domain 하나만 선언, 버전별 preview URL 비활성. apex/www/Pages 및 tcg.mbbs.kr 설정은 변경하지 않는다.
- JS의 운영 허용 주소는 tcg.mbbs.kr, **정확한** 후보 주소 및 ag.violenceroyale.com뿐. 임의 workers.dev/접미 위장/쿼리 변경으로 운영 연결 불가. 운영 후보에는 TEST 배지 없음.
- Cloudflare에 DB 서비스키나 새 secret은 필요 없다. 공개 anon 키는 기존 브라우저 설정 그대로.
- 소스 CSS/게임 엔진/서버 검증 해시 변화 없음. Cloudflare 자산 해시는 배포 시 자동 갱신.

## 형님이 할 일

1. 운영 Supabase > Authentication > URL Configuration > Redirect URLs에 아래 세 주소를 **추가** (기존 주소 삭제 금지):
   - `https://vr-tcg-prod.notcold.workers.dev/`
   - `https://vr-tcg-prod.notcold.workers.dev/admin` (Cloudflare가 .html을 정리한 실제 경로)
   - `https://vr-tcg-prod.notcold.workers.dev/admin.html`
2. Site URL은 `https://tcg.mbbs.kr` 그대로. Google OAuth 콜백도 기존 Supabase `/auth/v1/callback` 그대로. Worker별로 브라우저 저장소가 달라 새 주소에서는 재로그인이 필요할 수 있다.
3. iPhone Safari 실기기로 staging 먼저: 오프닝, 스토리 연출, MR 스킬, 소환 영상 재생·일시정지·탐색·반복·복귀 확인. 실제 기기 검증은 curl 206 검사와 별개다.
4. 후보 운영 주소에서 로그인/영상 확인. 실제 계정의 운영 데이터이므로 조심. **ag 이외 DNS/도메인 변경 및 main 병합은 하지 않는다.**

## 검증 / 되돌리기

```bash
curl -sS -D - -o /tmp/vr-range.bin -H 'Range: bytes=0-1' https://vr-tcg-staging.notcold.workers.dev/video/opening.mp4
# HTTP 206, Content-Range: bytes 0-1/18604433, Content-Length: 2
curl -sS -D - -o /tmp/vr-prod-range.bin -H 'Range: bytes=0-1' https://vr-tcg-prod.notcold.workers.dev/video/opening.mp4
```

단위 검사 + 실제 로컬 workerd 양쪽 설정 통합 검사 + staging/prod 공개 URL 검사를 수행한다. 기존 check/test/build:staging, 보안 1–5단계 및 production SQL 회귀 검사를 유지한다. 문제가 있으면 Cloudflare 해당 Worker의 이전 배포 버전으로 롤백 가능. tcg.mbbs.kr은 이번 작업에서 건드리지 않아 영향 없음. 로컬 자산 빌드/코드만 되돌리고 DB는 롤백하지 않는다.

근거: [Static Assets 제한](https://developers.cloudflare.com/workers/static-assets/billing-and-limitations/), [Worker-first 라우팅](https://developers.cloudflare.com/workers/static-assets/routing/worker-script/), [FixedLengthStream](https://developers.cloudflare.com/workers/runtime-apis/response/#set-the-content-length-header).

## 후속 승인: ag.violenceroyale.com만 연결 (2026-11-08 KST)

- `ag.violenceroyale.com` → `vr-tcg-prod` Workers Custom Domain. Cloudflare가 이 호스트의 DNS/TLS만 자동 관리한다.
- 계정 `a7cf57f7e3db3f2d94466da0c79c70b5`, zone `0b28d33a15fa0bd4550d82f2cabd9c70` (`violenceroyale.com`).
- apex `violenceroyale.com`, `www.violenceroyale.com`의 기존 Pages CNAME/프로젝트와 `tcg.mbbs.kr`은 그대로 유지한다. `*.violenceroyale.com` 같은 광역 route를 추가하지 않는다.
- app 설정은 ag의 정확한 hostname만 운영 Supabase로 허용한다. TEST 배지 없음. 기존 workers.dev 주소도 유지한다. 게임/DB/검증 함수/재화 규칙 변화 없음.
- 운영 Supabase Auth Redirect URLs에 다음을 **추가** (기존 항목/Site URL/OAuth 콜백은 유지):
  - `https://ag.violenceroyale.com/`
  - `https://ag.violenceroyale.com/admin` (.html 자동 정리 경로)
  - `https://ag.violenceroyale.com/admin.html`
- 새 호스트는 별도 브라우저 저장소를 사용하므로 재로그인이 필요할 수 있다. 계정/재화는 같은 운영 DB다.
- 검증: 기본 TLS 검증을 켠 HTTPS 200, 영상 `Range: bytes=0-1` → 206/2바이트, 내려받은 config의 운영 DB/TEST 없음, apex/www 및 기존 게임 홈페이지 내용 유지. Supabase Auth redirect는 형님이 설정하며 실제 로그인/아이폰 실기기 확인은 별도다.
