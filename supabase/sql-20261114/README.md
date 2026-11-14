# SQL 2026-11-14 (KST)

## A. 운영 20261111b (우편 v2 / UR 확정권) — 진단만. 설치 파일은 아직 없음
- `A1_prod_mail_diag_readonly.sql`: **운영 SQL Editor**, 읽기 전용, 결과 표 1개. 운영(7692130048193495360)이 아니면 STOP 한 줄만 나옴.
  - 함수 5개 (이름이 같은 다른 버전도 모두): 지금 md5 · `same_as_mail_v2_baseline` · `same_as_20261111b_target` · 줄끝(CRLF) 무시 비교 `same_as_mail_v2_ignoring_crlf` / `same_as_20261111b_ignoring_crlf` · 공백을 뺀 md5 · 전체 정의
  - 유력: 스테이징 camp_status 가 줄끝만 CRLF 로 들어가 md5 가 달랐음 (내용 동일). 우편 함수도 `same_as_mail_v2_ignoring_crlf=true` 면 같은 이유 → 20261111b 를 CRLF 무시 비교로 다시 만들면 안전
  - 참고 줄: 배포 기록, `story_gacha.ur_tickets` / `mail_broadcast.existing_only` 칸이 이미 있는지
- 결과를 CSV로 내려받거나 (definition 칸 포함) 통째로 붙여 보내 주시면 repo 의 두 버전과 diff 함.
- repo 기록으로 본 원인: mail_v2.sql 은 10/31 에 한 번만 만들어졌고 (4fa5719/#315), 그 뒤 5개 함수를 다시 만드는 SQL 은 20261111b 하나뿐.
  11/08 운영 설치의 함수 본문 자동 수정(unlock-policy 게이트)도 우편 함수는 건드리지 않음. → repo 밖에서 바뀐 것
  (SQL Editor 에서 직접 수정, 다른 초안을 붙여 넣음, 줄바꿈/공백 변형 중 하나). 무엇인지는 진단 결과로만 알 수 있음.
- 진단 결과에 따라:
  1. `same_as_20261111b_target=true`, 칸 2개가 true → 이미 설치됨. 배포 기록만 빠짐 → 기록만 남기는 작은 SQL 을 따로 드림
  2. 공백만 다름 (공백 뺀 md5 가 원본과 같음) → 기준 md5 를 운영 값으로 바꿔 20261111b 를 다시 만듦 (안전)
  3. 내용이 다름 → 운영에서 바뀐 부분을 tools/ur_ticket/core.sql 에 먼저 합친 뒤 다시 만듦. 그냥 설치하면 그 수정이 덮어써짐
  → 그래서 01_install 의 기준을 지금 바로 바꾸지는 않음.

## B. 스테이징 디버그 57 (2차: 15:01 KST B1 STOP 원인 = 스테이징 camp_status 가 camp.sql 본문 그대로인데 줄끝만 CRLF, md5 b82026c8… → B1/B2/B3 는 이제 줄끝 무시 비교) — 훈련소에 넣어 두면 열지 않아도 레벨 오름 (PR #607)
- 실행 순서 (**스테이징 SQL Editor**, 7703759698107299042 가드):
  1. `B1_staging_camp_auto_exp_install.sql`: `camp_status()` 하나만 바꿈. 받을 EXP 가 있으면 기존 `camp_claim()` 을 그대로 실행
     (시간당 20 + 플레이어 Lv×1.5, 훈련소 Lv 보너스, 마지막 정산 뒤 최대 24시간, 상한 min(등급 최대, 플레이어 Lv−5) 모두 그대로).
     camp_status 는 로그인 2초 뒤와 10분마다 모든 화면에서 이미 불리므로 훈련소를 안 열어도 반영됨.
     지금 camp_status 가 camp.sql 원본과 다르면 멈춤. 다시 실행해도 안전 ('already installed').
  2. `B2_staging_camp_check_readonly.sql`: 읽기 전용 확인. 첫 줄 `installed=true` + 훈련 중인 칸 목록 (마지막 정산 뒤 시간).
     테스트 계정으로 로그인 → 2~3초 뒤 다시 실행하면 그 계정 hours_since_last 가 0 근처, 인재 레벨이 오름. 화면에는 '훈련소 EXP +N' 알림.
  3. (필요할 때만) `B3_staging_camp_auto_exp_rollback.sql`: 원래 camp_status 로 되돌림.
- pg_cron 은 일부러 안 씀: 매시간 전원 정산하면 접속 안 한 유저의 '24시간까지만 쌓임' 한도가 사라짐 = 밸런스 변경.
- 같은 파일이 repo `supabase/camp_auto_exp_{staging,check_staging,rollback_staging}.sql` 에도 있음. 오프라인 테스트 `tools/test_camp_auto_exp_sql.mjs`.
