# Staging load test (STAGING ONLY)

대상은 `https://vr-tcg-staging.notcold.workers.dev` 와 Supabase `cuyqchmdcnsgzkwyclji` 뿐입니다. 운영(ag.violenceroyale.com, vr-tcg-prod, htarwisgkkphutxxnuak)은 주소가 맞으면 실행을 거부합니다.

anon/publishable 키는 `js/config.js` 의 공개 STAGING 값에서만 읽고, 로그에 찍지 않습니다.

## 하는 일

가상 유저가 앱 시작(Worker 정적 파일 몇 개) → `maintenance_status` 를 반복합니다. 생각 시간은 기본 12초 안팎입니다.

단계: 워밍업 10명 30초 → 50명 2분 → 200명 2분 → 500명 2분. 하드 오류율 5%를 넘거나 p95가 크게 치솟으면 바로 멈춥니다.

## 하지 않는 일 (의도적)

- **전투 검증 Edge Function** (`story-direct-verify-v7`, `arcade-verify-v5` 등): 호출 자체 요금은 보통 월 한도 안이면 거의 없지만, 스테이징 DB에 전투/전적이 쌓이고, 계정마다 동시 세션 1개·짧은 속도 제한·아케이드 일일 한도가 있어 500명 부하를 재현할 수 없습니다. `--verify` 는 거부합니다.
- **계정 대량 생성**: 하지 않습니다. 공지(`global_notice_list`, 로그인 필요)나 캠프/전투 RPC를 보려면 기존 테스트 계정 몇 개를 `LOADTEST_AUTH_FILE` JSON(`[{"email":"...","password":"..."}]`, 최대 8개)으로 넘기세요. 파일은 커밋하지 마세요. 현재 기본 실행은 게스트(비로그인)만 합니다.
- 결제, 본인인증, 네이버, 운영 SQL/배포.

## 실행

```bash
node tools/loadtest/run.mjs --plan    # 예상 요청 수만 보기
node tools/loadtest/run.mjs           # 스테이징 부하 테스트
```

결과는 `tools/loadtest/results/` (git 무시) 와 `/workspace/loadtest-staging-last.json` 에 저장됩니다.
