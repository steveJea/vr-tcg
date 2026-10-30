# 튜토리얼 가이드 (data/tutorials/&lt;id&gt;.json)

화면을 어둡게 하고 **대상 하나만 밝게(👆 손가락 + 노란 테두리)** + 말풍선. 대상만 누를 수 있고, 정보 단계는 아무 데나 탭하면 다음으로.
처음 한 번만 나옴 (사용자별 localStorage `vrTut:<user>:<id>`). 오른쪽 위 **건너뛰기** 가능.

## 파일 하나 = 튜토리얼 하나
```json
{
  "title": "챕터0 전투 1 · 공격과 기술",
  "locks": ["auto"],                   // 진행 중 막을 버튼
  "prep": { "fullMp": true },          // (선택) 시작 때 내 카드 MP 가득 → 첫 턴부터 기술 연습
  "steps": [ { ... }, { ... } ]
}
```

## 단계(step)
| 칸 | 뜻 | 예 |
|---|---|---|
| `target` | 밝게 할 대상. 없으면 정보 단계(화면 전체 어둡게) | `my_card:0` `enemy_card:0` `skill_btn:1` `skill_use` `attack_all` `end_turn` `auto_btn` `speed_btn` 또는 CSS 선택자 `#end-turn` |
| `text` | 말풍선 글 (짧게) | `"내 카드를 눌러 선택해."` |
| `speaker` | 말하는 사람 이름 | `"임유리"` |
| `face` | (선택) 얼굴 그림. `card:<카드id>` 또는 이미지 경로 | `"card:10325"` |
| `wait` | 다음으로 넘어가는 때 | 아래 표 |
| `match` | (선택) 이벤트 조건 | `{ "index": 0 }` = 0번 카드를 골랐을 때만 |
| `delay` | (선택) 이벤트 뒤 기다림 ms (기본 350) | |
| `pad` | (선택) 테두리 여백 px | |

`wait` 값
- `tap` (또는 생략): 아무 데나 탭
- `tap_target`: 밝힌 대상을 누르면
- `card_selected`: 내 카드를 골랐을 때 (`index` = 필드 순서 0부터)
- `attack_done`: 내 공격이 끝났을 때
- `skill_used`: 내 기술 사용이 끝났을 때 (`skill` = 기술 이름)
- `battle_end`: 전투가 끝났을 때 (`win` = true/false)

`locks` 값: `auto`(AUTO) · `skip`(연출 생략) · `attack_all`(일괄 공격) · `end_turn`(턴 종료) · `giveup`(포기)

`my_card:N` / `enemy_card:N` 은 화면 왼쪽부터 N번째(0부터). `skill_btn:N` 은 내 N번째 카드의 기술 버튼, `skill_use` 는 열린 카드 정보 창의 "사용" 버튼.

## 스토리 페이즈에 붙이기
페이즈 데이터(js/story-data*.js 의 phase)에 `tutorial: '<id>'` 한 줄. 그 페이즈 전투가 시작되고 내 차례가 오면 가이드가 뜸 (본 적 있으면 안 뜸).
화면 전투(PvP·전쟁·토벌)는 `TCG.viewBattle({ ..., tutorial: '<id>' })`.

## 시트(튜토리얼 칸) → 단계로 옮기기
"내 카드를 선택하고 상대 카드를 공격 · 기술 사용 (오토 비활성화)"
→ `locks: ["auto"]`, 단계: 정보(tap) → `my_card:0`/`card_selected` → `enemy_card:0`/`attack_done` → `skill_btn:N`/`tap_target` → `skill_use`/`skill_used` → 정보(tap). 예시: `ch0_battle1.json`.
소환·공격력 UP: `summoned` (`id` = 카드 id, 손패 소환·reserve 소환) · `action_used` (`type` = `buff` 등). 예시: `ch0_p4.json` (챕터 0 P4, 제한 마나 · 손패 `#me-hand .hand-card[data-id="…"]` → `#summon-btn`)

## 개발용
- 미리보기: `?tut=ch0_battle1` (연습 전투 + 가이드, 라이브 스토리와 무관 · json 의 `demo` 덱 사용)
- 다시 보기: `?tut_reset` (전부) 또는 `?tut_reset=ch0_battle1`, 콘솔 `VRTutorial.reset()`
