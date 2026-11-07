# 테스트 DB 분할 설치본 — 현재는 DB 식별번호 등록 전이라 실행 차단

대상은 **cuyqchmdcnsgzkwyclji** 테스트 프로젝트뿐입니다. 운영 **htarwisgkkphutxxnuak**에서 실행하지 마세요.

## 중요한 안전 조건

Supabase SQL Editor는 현재 접속한 `project_ref`를 보장해서 SQL 변수로 넘겨주지 않습니다. 코드에 테스트 ID를 써 놓는 것만으로는 운영 DB 선택 실수를 막을 수 없습니다. 존재가 확인되지 않은 `current_setting('app.settings.project_ref')` 등을 믿고 진행하지 않습니다.

그래서 이 분할본은 매 파일 시작에 **실제 DB의 클러스터 식별번호(`pg_control_system().system_identifier`)**까지 대조합니다. 이 값은 비밀번호나 관리자 키가 아닙니다. 아직 테스트/운영 DB의 식별번호를 받지 못해서 모든 파일은 기본으로 중단됩니다. 복제된 DB는 같은 번호일 수 있어 두 값이 다름을 확인하고 운영 번호를 명시적으로 차단합니다. 실제 Supabase에서 식별 조회 권한이 있는지도 아직 확인하지 않았습니다.

먼저 형님이 Supabase 화면에서 **테스트**(`cuyqchmdcnsgzkwyclji`)와 **운영**(`htarwisgkkphutxxnuak`) 프로젝트를 각각 확인하고, 각 SQL Editor에서 **아래 읽기 전용 조회 한 줄만** 실행합니다. 결과에 어느 프로젝트인지 표시해 구별합니다. 운영에서는 이 SELECT 조회만 하며 설치 SQL은 절대 실행하지 않습니다.

```sql
select system_identifier::text as database_cluster_id from pg_catalog.pg_control_system();
```

- 각 프로젝트의 숫자 두 개를 확인하고, 서로 다름을 확인한 뒤 설치 파일에 일괄 반영·검증해야 합니다. 같으면 이 식별 방법으로 구별할 수 없으므로 진행하지 않습니다. 그전에는 01번도 실행하지 않습니다.
- 조회 자체가 권한 오류라면 중단합니다. 비밀 키나 DB 비밀번호를 보내거나, 권한을 높이거나, guard를 삭제하지 않습니다.
- 고유번호는 DB 재생성/복구로 바뀔 수 있습니다. 바뀌었다고 임의로 고치지 말고 프로젝트와 설치 상태를 다시 확인합니다.

개발자가 공개 고유번호를 확인받은 뒤 사용하는 재생성 명령:

```bash
node tools/build_staging_parts.mjs --system-id '테스트조회숫자' --production-system-id '운영조회숫자'
npm run test:staging
```

## 번호를 반영한 뒤 실행할 순서

SQL Editor의 내용을 매번 지우고 **파일 하나 전체만** 붙여 넣어 Run 합니다. 성공 메시지를 확인한 뒤 다음 파일로 갑니다. 파일 안의 함수·달러 인용을 나누거나, 여러 파일을 한꺼번에 합쳐 붙이지 마세요. 모든 파일이 끝나기 전에는 회원 가입/로그인을 하지 마세요.

1. [`01_install.sql`](01_install.sql) — 129,670바이트
2. [`02_install.sql`](02_install.sql) — 130,191바이트
3. [`03_install.sql`](03_install.sql) — 129,965바이트
4. [`04_install.sql`](04_install.sql) — 129,293바이트
5. [`05_install.sql`](05_install.sql) — 130,149바이트
6. [`06_install.sql`](06_install.sql) — 130,249바이트
7. [`07_install.sql`](07_install.sql) — 130,256바이트
8. [`08_install.sql`](08_install.sql) — 130,095바이트
9. [`09_install.sql`](09_install.sql) — 130,119바이트
10. [`10_install.sql`](10_install.sql) — 29,345바이트

## 재실행과 오류

- 같은 파일을 다시 실행하면 비공개 설치 기록을 보고 변경 없이 건너뜁니다. 최신 함수가 옛 함수로 되돌아가지 않습니다.
- 앞 파일이 빠졌거나 서로 다른 버전의 파일을 섞으면 중단합니다. 같은 커밋의 파일만 사용합니다.
- 각 파일은 한 트랜잭션입니다. 실패한 파일의 변경과 설치 기록은 함께 되돌아가며, 먼저 성공한 파일은 유지됩니다.
- 오류가 나면 번호와 오류 내용을 확인하고 그 파일부터 다시 진행합니다. 설치 기록을 지우거나 운영/기존 DB에서 시작하지 않습니다.
- 설치 도중에는 API 계정의 `public` 스키마 사용을 차단하고, 마지막 파일까지 성공한 뒤 엽니다. 마지막 검사는 함수 재컴파일·RLS·내부 함수 권한·사용자 자료 없음입니다.
- SQL Editor가 연결을 끊었다고 나오면 새 편집기에서 해당 파일 전체를 다시 실행하면 됩니다. 같은 세션에서 이미 실패한 트랜잭션이라는 오류가 계속될 때만 `ROLLBACK;`으로 실패 상태를 끝낸 뒤 해당 파일 전체를 다시 실행합니다.

## 검증 범위

WASM PostgreSQL에서 로컬 DB 고유번호를 테스트용으로 바인딩해 전체 순서 설치, 각 파일/완료 후 역순 재실행, 순서·버전·운영 확인 문자열·다른 DB 차단, 중간 실패 롤백을 검사합니다. 실제 테스트 Supabase에 SQL을 실행한 것은 아니며, Google 로그인·메일·휴대폰 동작 검증도 별도입니다.

옛 통합 파일 `supabase/staging_install.sql`은 개발 검사용으로 유지합니다. SQL Editor에는 그 큰 파일을 다시 붙이지 마세요.

참고: [프로젝트 ref의 SQL 조회 제한](https://www.answeroverflow.com/m/1014410968916308020), [PostgreSQL DB 고유번호 함수](https://www.postgresql.org/docs/current/functions-info.html#FUNCTIONS-CONTROLDATA-TABLE).
