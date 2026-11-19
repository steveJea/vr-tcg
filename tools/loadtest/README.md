# Staging load test (STAGING ONLY)

대상은 `https://vr-tcg-staging.notcold.workers.dev` 와 Supabase `cuyqchmdcnsgzkwyclji` 뿐입니다. 운영 주소는 실행을 거부합니다. anon 키는 `js/config.js` 에서만 읽고 로그에 찍지 않습니다.

## 게스트 경로 (1라운드)

앱 시작(작은 정적 파일) + `maintenance_status`. 10 → 50 → 200 → 500명. 하드 오류 5% 또는 p95 급등 시 중지.

```bash
node tools/loadtest/run.mjs --plan
node tools/loadtest/run.mjs
```

## 로그인·전투 경로 (2라운드)

테스트 계정은 저장소 밖 `/workspace/.loadtest-accounts.json` (chmod 600) 에만 둡니다. 비밀번호는 커밋하거나 출력하지 마세요.

계정은 `VR_LOADTEST_PASSWORD` 환경 변수와 기본 주소 `loadtest1@example.test` … `loadtest5@example.test` 를 쓰는 것이 기본입니다. 비밀번호는 출력·커밋하지 않습니다. 파일에 저장하지 않는 쪽을 선호합니다.

직접 가입을 시도할 때만:

```bash
node tools/loadtest/provision-accounts.mjs
```

이메일 인증이 필요하거나, 익명 로그인이 꺼져 있고 확인 메일을 받을 수 없으면 가입 스크립트는 중단합니다.

로그인 홈 RPC(`global_notice_list`, `camp_status`, `player_status`, `wallet_status`, `mail_list`, `mail_unread`)와 소수 전투 검증:

```bash
node tools/loadtest/run.mjs --r2 --plan
node tools/loadtest/run.mjs --r2
```

전투는 계정마다 순차, 동시에 최대 3계정, 전체 검증 약 40회 한도입니다. 스토리는 `0:1` 시작 후 최소 시간만큼 기다리고 `giveup` 으로 검증합니다(전체 자동 전투 리플레이는 만들지 않음). 아케이드는 시작이 되면 `forfeit` 합니다. Edge Function 호출은 최대 수십 회(수백 회 미만)입니다.

결과는 `tools/loadtest/results/`(git 무시)와 `/workspace/loadtest-staging-last.json` 에 저장됩니다.
