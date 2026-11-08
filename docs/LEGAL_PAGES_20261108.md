# 이용약관·개인정보처리방침 초안 — 2026-11-08

## 배포 범위와 상태

- 운영 표기: **entincode (엔터인코드)**. 상호·사업자·담당자·연락처 등 실제 미제공 값은 만들지 않았다.
- `/terms.html`, `/privacy.html`은 **법률 검토 전 / 시행 전 초안**이다. 시행일도 미정이다. 공개/열람을 약관·개인정보·국외이전 동의로 간주하지 않는다. 가입 동의 UI나 수집 동의 기능을 추가한 것이 아니다.
- 게임 로그인 화면과 설정에 두 문서 링크만 추가했다. 16px, 44px 터치 영역, 키보드 포커스, 새 탭·noopener/noreferrer. 작은 안내문은 추가하지 않았다.
- 문서 자체에는 스크립트·폼·분석·외부 폰트가 없다. 자체 CSS, no-referrer, 제한적 CSP, noindex 사용. 호스팅 요청 처리는 여전히 발생한다.
- **법률 전문가 검토 및 아래 빈칸 확정 전에는 정식 정책·개발자 앱 심사 완료본으로 사용하지 말 것.** 단순 문서 게시가 미구현 운영 절차를 대신하지 않는다.

## 환경 분리 — 중요

운영 Worker의 기존 배포 기반은 `b0a8dbab0f69f25b128bcf184bedcd0ffdaa271f` (#505 호스팅 브랜치)다. 이 브랜치를 기반으로 정적 문서/문서 CSS/HTML 링크만 추가하여 운영 Worker에 배포한다. **staging의 Kakao/X·인증·게임·SQL 변경을 운영으로 같이 배포하지 않는다.**

- 운영용 작업 트리: `feat/legal-static-pages-20261108`, `wrangler.production.jsonc`, `.production-dist`.
- staging: 최신 `origin/staging`에 임시 브랜치로 이 변경을 병합하고 `wrangler.jsonc`, `.staging-dist`로 별도 배포한다. 기존 Kakao/X 코드·테스트는 유지한다.
- draft PR은 main 대상이며 #505 호스팅 변경을 포함한다. **main은 병합하지 않는다.** DB/Edge/OAuth 설정/DNS 변경 없음.
- `test_legal_pages.mjs --production-build`는 index가 기존 운영 HTML에 정책 링크만 덧댄 결과인지, 인증·설정·Worker 코드가 기존 운영 기반과 같은지 검사한다. staging 작업 트리에서 이 운영 배포를 실행하지 말 것.
- HTML은 두 빌드 allowlist에 포함했다. 신규 Tailwind 클래스/미디어 없음: tw.css 재생성 불필요, 미디어 매니페스트 체크는 유지한다.

## URL

| 환경 | 이용약관 | 개인정보처리방침 |
| --- | --- | --- |
| staging | https://vr-tcg-staging.notcold.workers.dev/terms.html | https://vr-tcg-staging.notcold.workers.dev/privacy.html |
| 운영 Worker | https://ag.violenceroyale.com/terms.html | https://ag.violenceroyale.com/privacy.html |

Cloudflare HTML 정규화 설정에 따라 `.html`은 확장자 없는 `/terms`, `/privacy`로 이동할 수 있다. 둘 다 같은 문서를 제공한다. 기존 `tcg.mbbs.kr` GitHub Pages(main)는 이 draft PR 병합 전까지 변경하지 않는다.

## 코드에서 확인한 실제 처리

기능 대조 기준: staging `da73103059b33b06f94fd53604a120b36fda572c`, 운영 Worker 기반 `b0a8dba`.

| 근거 | 확인 내용 |
| --- | --- |
| `js/cloud.js`, staging `js/auth-oauth.js` | Supabase UUID 기반 저장·세션·프로필, 공급자 ID/닉네임/이미지/이메일(제공 시), 이메일 없는 계정 지원. 공급자 활성화는 환경별로 다름 |
| `js/player.js`, `js/story.js`, 서버 검증 관련 모듈 | 게임 상태·보상·전적·검증 기록 등. 모든 기능이 완전 리플레이 검증된다고 주장하지 않음 |
| `supabase/friends.sql`, `supabase/guild.sql` 및 관련 UI | 친구 코드·접속/최근 활동·조직 정보와 닉네임/이미지 등의 기능상 공개 |
| `js/kakao-share.js` | 공유 선택 시 Kakao SDK를 지연 로드하고 선택한 카드 이미지를 Kakao에 업로드, 제목/설명/링크 전달 |
| `index.html` | GA4 `G-NP3VPPBRKL`, Google Fonts, jsDelivr Supabase SDK가 실제 사용됨. 게임에 분석 동의 배너/거부 스위치는 없음 |
| `js/gem.js` | 현금 충전은 준비 중. 결제업체/토스/포트원 계약이나 카드 수집을 이미 시행한다고 기재하지 않음 |
| `js/main-menu.js`, 관련 인증 코드 | 계정삭제 UI/전체 데이터 보유기간 자동 파기·미성년자 동의 검증 기능은 없음. 로그아웃/연결해제는 서버 데이터 삭제와 다름 |
| `wrangler*.jsonc`, `worker/media-range.mjs` | Cloudflare 호스팅·요청/오류 처리. 기존 tcg.mbbs.kr은 GitHub Pages 병행 |

## 운영자가 채우고 확정할 항목

아래 표시를 모두 실제 운영·계약·법률 검토 결과로 치환한다. 존재하지 않는 조치/보유기간/국가/담당자를 추정해 넣지 않는다.

- [GA4 보유기간·법적근거·동의/거부 방식 확정 필요]
- [Kakao 국외 처리·재위탁 여부 확인 필요]
- [Supabase 프로젝트 리전·처리국가 확인 필요]
- [개인정보 담당부서·이메일·전화번호 입력 필요]
- [개인정보 보호책임자 성명·직책 입력 필요]
- [게임물 이용등급·등급분류번호 입력 필요]
- [결제사업자·상품별 판매/환불정책 확정 필요]
- [고객문의 이메일 입력 필요]
- [고객문의 전화번호 입력 필요]
- [공고일 입력 필요]
- [기록별 보유기간·파기 일정 확정 필요]
- [대표자명 입력 필요]
- [만14세 미만 이용정책·법정대리인 동의절차 확정 필요]
- [목적별 처리근거·선택 동의사항 확정 필요]
- [백업 보유·삭제 반영기간 확정 필요]
- [법적 사업자명 입력 필요]
- [사업자등록번호 입력 필요]
- [사업장 주소 입력 필요]
- [시행일 입력 필요]
- [업체별 계약법인·개인정보 연락처 확인 필요]
- [업체별 로그·처리정보 보유기간 확인 필요]
- [업체별 실제 처리·이전국가 확인 필요]
- [운영 보안·파기·사고대응 절차 확인 필요]
- [유형별 국외이전 근거·고지/동의 요건 확정 필요]
- [이용 가능 연령·확인 방식 확정 필요]
- [이전 거부·철회 접수절차와 제한 범위 확정 필요]
- [제재·이의제기 처리 기준 확정 필요]
- [통신판매업 신고번호·신고기관 입력 필요]
- [확률형 아이템 정보공개 위치·내용 확정 필요]
- [회원 탈퇴·삭제 처리절차와 처리기한 확정 필요]

## 특히 문서 외에 필요한 결정/작업

1. 실제 고객문의·권리행사 채널, 탈퇴 본인확인/처리 기한·DB/백업 삭제 절차를 정해야 한다. 현재 연락처 빈칸은 접수 채널이 아니다.
2. 만 14세 미만 허용 여부·법정대리인 동의/연령 확인·게임물 등급을 정해야 한다. 문서만으로 구현되었다고 고지하지 않았다.
3. Supabase 실제 리전·계약/DPA·재수탁, Cloudflare/Google/Kakao/X/CDN의 수령 법인/연락처/국가/시기·방법/보유기간/이전 근거·거부 방법을 확인해야 한다. 국내 DB 리전이라고 모든 처리가 국내라는 뜻이 아니다.
4. GA4 실제 보유기간·법적근거·분석 동의/거부 방식을 정해야 한다. OAuth 복귀 URL·쿼리 등이 분석/요청 로그에 불필요하게 남지 않는지 별도 점검도 권장한다(이번 작업에서 유출을 확인했다는 의미는 아니다).
5. 유료 판매 전 상품별 고지·청약철회 제한 요건·7일 원칙/디지털콘텐츠 예외·환급/잔액 정산·미성년자 결제·확률 공개를 실제 결제 흐름과 맞춘다. 향후 유료 상품이라는 사실과 현재 미시행 상태를 구분했다.

## 검토 참고 자료

법률 자문이 아니며 실제 적용·최신 개정·사업자 해당 여부는 전문가 확인이 필요하다.

- 개인정보보호위원회 2026 개인정보 처리방침 작성지침: https://www.privacy.go.kr/front/bbs/bbsView.do?bbsNo=BBSMSTR_000000000049&bbscttNo=20885
- 개인정보 국외이전 안내: https://www.privacy.go.kr/front/contents/cntntsView.do?contsNo=367
- 전자상거래법 청약철회·환급 안내(현행 규정 기준): https://www.easylaw.go.kr/CSP/CSP/CnpClsMain.laf?ccfNo=4&cciNo=1&cnpClsNo=2&csmSeq=835&popMenu=ov
- 콘텐츠이용자 보호지침: https://www.law.go.kr/LSW/admRulInfoP.do?admRulSeq=2100000237546
- Supabase 데이터 위치/국외이전: https://supabase.com/legal/privacy-resources/data-residency-and-transfers-faq
