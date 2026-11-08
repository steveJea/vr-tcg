# 피드백 16-1 — 김성진 2번 스킬 봉인 대상 수정

- `Tempus est discerpi`: 사용자가 아니라 **상대의 고유기술을 상대 다음 턴 종료까지** 봉인한다.
- 적 전체가 자기 본진을 공격하는 교란은 유지한다. 다른 스킬로 걸린 기존 봉인을 지우거나 더 짧게 만들지 않는다.
- 아케이드/스토리/탑 공통 `skills.js`, PvP 및 토벌/조직전 서버 재현 엔진에 동일하게 반영했다. 설명에도 봉인 대상·기간을 명시했다.
- 피드백 17의 아케이드/전체 미션 지급 보류는 변경하지 않았다.

## 기존 staging에 적용 (운영 금지)

1. 진행 중인 **PvP·토벌·조직전 전투를 기존 화면/Edge에서 먼저 마친다**. 기존 버전 전투를 새 엔진으로 재현하지 않는다.
2. staging Supabase `cuyqchmdcnsgzkwyclji` SQL Editor에서 **`supabase/security_feedback16_skill_lock_staging.sql` 파일만 전체 실행**한다. 큰 보안 SQL이나 전체 설치본을 다시 실행하지 않는다.
   - DB 고유번호, 이전 엔진 버전, 진행 중인 전투를 확인한다. 다른 DB/버전 또는 미완료 전투가 있으면 두 엔진의 변경 모두 중단한다.
   - 미완료 전투는 기존 버전으로 마치거나 만료를 기다린다(PvP 최대 1시간, 토벌/조직전 최대 20분). 강제 초기화하지 않는다. 잠금 시간 초과면 잠시 후 동일 파일을 다시 실행한다.
   - 해시 두 개만 원자적으로 변경한다. 비상 정지 스위치·지갑·보상·시도권·방어 HP·덱·테스트 시계·refill 기록은 유지한다. 재실행 가능하다.
3. staging의 Edge Function **두 개 모두** 다시 배포한다. 기존 인증/환경변수 설정은 그대로 유지한다.
   - `pvp-verify-v3` ← `supabase/functions/pvp-verify-v3/dashboard_single_file.ts`
   - `guildbattle-verify-v4` ← `supabase/functions/guildbattle-verify-v4/dashboard_single_file.ts`
   - Dashboard에서는 해당 단일 파일 전체로 코드를 교체해 배포한다. CLI 배포라면 `index.ts`/`handler.mjs`와 재생성된 `_shared` 엔진을 함께 배포한다.
4. staging 웹 배포 후 새로고침한다. 새 웹·SQL·Edge의 버전이 모두 맞아야 새 전투가 시작된다. 순서가 어긋난 동안에는 버전 오류로 안전하게 차단될 수 있다.

새 DB 설치용 phase3/4 SQL 및 분할 설치 manifest도 새 엔진 해시로 갱신했다. 기존 DB에서 재실행할 파일이 아니다.

기존 토벌/조직전 테스트 상태를 다시 만들 필요는 없다. 이후 `refill`이 필요하면 **이 변경과 같은 커밋의** `staging_seed_raid_guildwar.sql`을 사용한다(구버전 고정 링크는 엔진 버전 검사에서 중단됨). 기존처럼 `refill`은 HP/시계를 유지하고 시도권만 충전한다.

## 확인

- 김성진 2번 사용 직후 내 고유기술은 사용 가능, 상대 고유기술은 상대 다음 턴 종료까지 사용 불가.
- 상대 교란의 자기 본진 공격 및 1턴 후 해제 유지. 적 AI가 사용할 때는 내 고유기술이 봉인된다.
- 기존 별도 봉인의 유지/긴 봉인의 비단축, PvP 3모드·토벌·조직전 AUTO/명시적 수동 스킬 재현 일치.
- staging 전용 SQL의 타 DB/예상 밖 버전/미완료 전투 차단, 재실행·중간 상태·비상 정지 및 기존 데이터/ACL 보존.
- 추가 Tailwind utility 없음. 두 dashboard_single_file.ts 및 SQL bundle/parts/manifest 재생성.
