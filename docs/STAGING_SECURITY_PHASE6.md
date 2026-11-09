# 보안 6단계 — 시련의 탑 소탕 재계산 (스테이징만)

스토리와 탑을 직접 싸워 이기는 길은 아직 서버가 전투를 다시 계산하지 않습니다. 이번 단계는 시련의 탑 **소탕**만 해당합니다. SQL을 넣는 것만으로 소탕 재계산이 켜지지는 않습니다.

## 이미 있던 보호

로그인 계정만 자기 전투를 기록할 수 있습니다. 다른 사람 세션, 앞 단계를 건너뛴 페이즈·층, 같은 보상의 두 번 지급, 만료된 세션, 출전 불가 인재, 필수 인재 누락, 제한 마나를 넘는 별점, 포기·생존 턴은 서버가 거절하거나 서버 보상표로만 지급합니다. 예전 완료 함수로 우회하는 길은 닫혀 있습니다.

이 검사는 전투를 실제로 했다는 증거가 아닙니다. 몇 초를 기다린 뒤 그럴듯한 승리 숫자를 보내면 스토리와 탑 **직접 도전**은 통과할 수 있습니다. 표식은 `plausibility-v3`입니다.

## 소탕에서 화면과 서버가 같이 쓰는 규칙

화면 미리보기(`js/quest-sim.js`)와 서버 재계산은 같은 `js/sweep-core.js`의 `runSweep`을 씁니다.

- 양쪽 인재는 필드에 나온 채로 자동으로만 싸웁니다. 손패, 드로우, 진영, 소환, 장비 구매는 없습니다.
- 시드의 첫 난수로 선공을 정하고, 그다음 난수는 스킬·확률에 씁니다. 난수 함수는 서버 시드 하나에서만 나옵니다.
- 스킬 판정은 `skills.js`의 `aiPickSkill` / `useSkill` / `turnStart` / `turnEnd`이고, 공격은 `rules.js`의 `resolveAttack`입니다.
- 적 구성은 `quest.json`과 카드 목록으로 층 번호를 시드 삼아 정합니다. 속성 탑은 그 속성 카드와 NPC를 씁니다. 보스 층은 소탕하지 않습니다.
- 내 인재 스탯은 레벨, EX, 포인트, 스킬 레벨, 장비, 증표를 서버가 전투 시작 때 저장한 값으로 다시 계산합니다. 계산식은 스토리 카드의 레벨·장비 공식과 같습니다. 리더가 그 전투에 있으면 스토리 리더 배율(공격·방어·체력 퍼센트)을 더합니다.
- 화면은 전투 시작 뒤에 지금 가진 카드로 미리보기를 만듭니다. 시작 직후 장비를 갈아끼우면 미리보기와 서버 결과가 달라질 수 있습니다. 보상은 서버 결과만 따릅니다.
- 화면이 읽는 `data/skills.json`, `data/combos.json`과 Edge에 붙여넣는 묶음은 **같은 커밋**이어야 합니다. 다른 커밋을 섞으면 스킬이 어긋날 수 있습니다.

이 규칙은 탑을 직접 클릭해서 싸우는 화면(`js/game.js`)과는 다릅니다. 그 전투는 이번 단계에서 다시 계산하지 않습니다.

## 스위치

표는 `battle_replay_policy_v6` 한 줄입니다. 이 SQL을 실행하면 `enabled`는 **false**입니다. 파일을 다시 실행해도 끄고 켠 상태를 바꾸지 않고, 전투 버전 해시만 맞춥니다.

`enabled=false`인 동안 소탕은 지금까지처럼 화면이 보낸 승리 기록으로 지급됩니다. 스토리와 직접 도전은 스위치와 상관없이 그 방식입니다.

`enabled=true`인 뒤에만 소탕 승리 기록은 거절되고, Edge가 다시 계산한 승리만 지급됩니다.

## 형님이 할 순서

테스트 프로젝트 `cuyqchmdcnsgzkwyclji`만 사용합니다. 운영 프로젝트에서는 실행하지 마세요. 이미 설치된 테스트 DB에 설치본 전체를 다시 돌리지 마세요. 보안 2단계 SQL을 나중에 다시 실행하면 소탕 함수가 덮입니다.

확인할 사이트는 `https://vr-tcg-staging.notcold.workers.dev` 입니다. 이 주소가 `js/config.js`의 테스트 호스트이며 Supabase `cuyqchmdcnsgzkwyclji`에 연결됩니다. `dev-tcg.mbbs.kr`도 설정 목록에 남아 있지만, 이번 확인 주소로 쓰지 않습니다.

1. SQL Editor에서 이 커밋의 `supabase/security_phase6_story_tower.sql` **전체**를 실행합니다. 이미 받은 보상과 진행도는 지우지 않습니다. 이 시점에는 스위치가 꺼져 있으므로 지금 사이트에서 소탕은 그대로 됩니다.
2. Edge Function 이름 `story-tower-verify-v6`를 새로 만듭니다. 같은 커밋의 `supabase/functions/story-tower-verify-v6/dashboard_single_file.ts` **전체**를 Dashboard index.ts에 붙여넣고 Deploy 합니다. **JWT verification ON**. 비밀키는 만들거나 붙여넣지 않습니다. 스위치가 꺼져 있으면 이 함수는 보상을 주지 않습니다.
3. 이 PR을 `staging`에 합친 뒤, Cloudflare Worker `vr-tcg-staging`이 그 브랜치를 빌드하게 합니다. 빌드 명령은 `npm run build:staging`이고, 만들어지는 폴더는 `.staging-dist`입니다. 배포 설정은 `wrangler.jsonc`이며 사이트 이름은 `vr-tcg-staging`입니다. 운영 Worker와 GitHub Pages는 쓰지 않습니다. 새 화면은 Edge가 아직 재계산을 받지 않으면 지금까지의 소탕 기록 방식으로 이어갑니다.
4. 위 사이트를 연 뒤 강력 새로고침하고 다시 로그인합니다. 그 다음에만 스위치를 켭니다.

```sql
do $$ begin
 if (select system_identifier::text from pg_control_system()) <> '7703759698107299042' then
  raise exception 'STOP: staging only';
 end if;
 update public.battle_replay_policy_v6 set enabled=true where singleton;
end $$;
```

스위치를 화면보다 먼저 켜면, 예전 화면의 소탕 저장이 거절됩니다. 새 화면이 나온 뒤에 켜세요. 켠 뒤에는 예전 화면을 가진 브라우저는 새로고침 전까지 소탕 저장이 실패합니다. 스토리와 직접 도전은 그 경우에도 기록됩니다.

PvP, 토벌, 조직전, 아케이드, 결제 Edge는 이번 파일로 다시 배포하지 않습니다. 결제 관리 화면의 구매자, 서울 결제 시각, 취소 주체(게임 관리자 / 토스)는 이 변경에 포함되지 않습니다.

## 긴급 중지

```sql
do $$ begin
 if (select system_identifier::text from pg_control_system()) <> '7703759698107299042' then
  raise exception 'STOP: staging only';
 end if;
 update public.battle_replay_policy_v6 set enabled=false where singleton;
end $$;
```

소탕은 다시 예전 기록 방식으로 돌아갑니다. 이미 확정된 보상은 지우지 않습니다. 스토리·직접 도전은 이 스위치로 멈추지 않습니다.
