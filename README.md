# VR TCG

VR 캐릭터 카드로 즐기는 1:1 카드 배틀 (컴퓨터 AI 상대). 정적 HTML/JS + Tailwind CDN.

- 카드 데이터: `data/cards.csv` (power = 옵션 B, 한글 이름/지역, cost)
- 이미지: `steveJea/vr-ideal-worldcup` 저장소의 `img/bt_img/{id}.jpg` (png 대체)
- 규칙 로직: `js/rules.js` (속성 배율, 데미지, 소환 조건, 덱 구성), UI/AI: `js/game.js`
