# VR TCG

VR 캐릭터 카드로 즐기는 1:1 카드 배틀 (컴퓨터 AI 상대). 정적 HTML/JS + Tailwind CDN.

- 카드 데이터: `data/cards.csv` (power = 옵션 B, 한글 이름/지역, cost)
- 이미지: `steveJea/vr-ideal-worldcup` 저장소의 `img/bt_img/{id}.jpg` (png 대체)
- 규칙 로직: `js/rules.js` (속성 배율, 데미지, 소환 조건, 덱 구성), UI/AI: `js/game.js`

## 규칙 v2
- 자기 첫 2턴: 영웅 공격·초과 피해 불가
- 상대 필드 4장 이상이면 카드만 공격 (3장 이하면 영웅 공격 가능), 도발(taunt) 카드 우선
- 레벨 최대 10 (XP = 처치 카드 코스트 + 공격당 5 + 턴 종료 시 생존 카드당 4, 필요 XP = round(4 × Lv^1.3)), Lv2~5 +10% / Lv6~10 +5% (원본 기준), Lv10 영웅 카드
- 아이템: 무기 💧30 ATK +15%, 방어구 💧30 HP +20% (카드당 각 1개), 회수 시 레벨·아이템 초기화
- 필드 회복 💧20: 필드 카드 최대 HP 10% 회복
- 스킬 훅: cards.csv에 `skills` 열(예: `taunt`, 여러 개는 `|`)을 추가하면 적용
