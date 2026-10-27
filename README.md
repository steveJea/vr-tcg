# VR TCG

VR 캐릭터 카드로 즐기는 1:1 카드 배틀 (컴퓨터 AI 상대). 정적 HTML/JS + Tailwind CDN.

- 카드 데이터: `data/cards.csv` (power = 옵션 B 공식 `tools/power.py` · `js/rules.js` calcPower, 한글 이름/지역, cost)
- 이미지: `steveJea/vr-ideal-worldcup` 저장소의 `img/bt_img/{id}.jpg` (png 대체)
- 규칙 로직: `js/rules.js` (속성 배율, 데미지, 소환 조건, 덱 구성), UI/AI: `js/game.js`

## 규칙 v2
- 자기 첫 2턴: 영웅 공격·초과 피해 불가
- 상대 필드 4장 이상이면 카드만 공격 (3장 이하면 영웅 공격 가능), 도발(taunt) 카드 우선
- 레벨 최대 10 (XP = 처치 카드 코스트 × (1 + 레벨 × 0.2) + 공격당 5 + 턴 종료 시 생존 카드당 4, 필요 XP = round(5.5 × Lv^1.3)), Lv2~5 +10% / Lv6~10 +5% (원본 기준), Lv10 영웅 카드
- 아이템: 무기 💧30 ATK +15%, 방어구 💧30 HP +20% (카드당 각 1개), 회수 시 레벨·아이템 초기화
- 필드 회복 💧20: 필드 카드 최대 HP 10% 회복
- 스킬 훅: cards.csv에 `skills` 열(예: `taunt`, 여러 개는 `|`)을 추가하면 적용

## 스킬 · 시너지 (v3)
- 데이터: `data/skills.json`, `data/combos.json` ← 엑셀에서 `python3 tools/import_skills.py <xlsx>`로 생성
- 엔진: `js/skills.js` (스킬별 효과는 스킬 이름으로 연결, 상태이상·MP·시너지·조합·AI 스킬 선택)
- 연출 파일: 엑셀 '연출 파일' 칸에 파일명을 쓰고 `data/fx/`에 넣으면 컷인에 표시 (이미지 또는 mp4/webm)
- MR 스킬 영상: `data/fx/mr/<카드id>_<스킬번호>.mp4` (H.264 720p 이하, 오디오 없음, faststart). MR 카드가 전투에서 그 스킬을 처음 쓸 때 1회 재생, 이후·파일 없음은 기존 컷인
- 시뮬: `SIM_DETAIL=1 node tools/sim.mjs 3000` (스킬 사용 횟수·카드별 승률), `SIM_FORCE=<카드id> node tools/sim.mjs 300` (그 카드를 덱에 넣었을 때 승률)
