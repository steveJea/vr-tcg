// GENERATED from tools/unlocks/policy.json; do not edit.
window.VR_UNLOCK_POLICY = {
  "version": 1,
  "sheet": "1LVVLanwmvhaI9Cef21jQXCGVniwWZxuxUSqMS_Qlmpw",
  "features": {
    "pvp_hr": 3,
    "gear": 3,
    "dispatch": 5,
    "guild": 6,
    "friends": 8,
    "tower": 10,
    "raid": 11,
    "camp": 12,
    "merge": 13,
    "skill": 13,
    "lend": 13,
    "sigil": 14,
    "pvp_open": 15,
    "trade": 15,
    "pvp_3v3": 17,
    "war": 18,
    "pvp_boss": 20,
    "tower_wind": 25,
    "tower_ice": 25,
    "tower_fire": 25,
    "tower_light": 40,
    "tower_dark": 40,
    "forge": 20,
    "dojo": 20
  },
  "entries": [
    {
      "key": "ch0",
      "level": 1,
      "title": "프리미엄 소환",
      "text": "🎟️ 프리미엄 10회 소환 오픈",
      "reward": {},
      "route": "summon",
      "trigger": "ch0",
      "source_text": "챕터0 클리어- 소환(프리미엄) 10회"
    },
    {
      "key": "leader",
      "level": 1,
      "title": "인재 레벨업",
      "text": "리더 레벨업 (+1 / +10)",
      "reward": {
        "blood": 5000,
        "gold": 5000
      },
      "route": "cards",
      "trigger": "1:1",
      "source_text": "ch1 P1클리어- 지급된 리더 레벨업. lv1업, lv10업"
    },
    {
      "key": "deck",
      "level": 1,
      "title": "덱 설정",
      "text": "🗂 덱 설정 오픈",
      "reward": {
        "gold": 5000
      },
      "route": "decks",
      "trigger": "1:3",
      "source_text": "ch1 p3클리어- 덱 설정 및 방법 설명"
    },
    {
      "key": "pvp_hr",
      "level": 3,
      "title": "PvP · 장비 가방",
      "text": "⚔️ HR 이하 1대1 리그 오픈",
      "reward": {
        "gold": 5000
      },
      "route": "pvp",
      "trigger": "",
      "source_text": "pvp덱배치 및 다른 pvp설명."
    },
    {
      "key": "dispatch",
      "level": 5,
      "title": "파견",
      "text": "🧭 파견 오픈 · 시간 지나면 보상",
      "reward": {
        "gold": 5000
      },
      "route": "dispatch",
      "trigger": "",
      "source_text": "레벨5 되면 파견 설명 및 실행"
    },
    {
      "key": "guild",
      "level": 6,
      "title": "조직",
      "text": "조직 오픈 · 가입/창설",
      "reward": {
        "gold": 5000,
        "boxes": 2
      },
      "route": "guild",
      "trigger": "",
      "source_text": "레벨6 되면 조직 가입 또는 창설 설명"
    },
    {
      "key": "friends",
      "level": 8,
      "title": "친구 · 선물",
      "text": "👥 친구 오픈 · 🎁 행동력 선물",
      "reward": {},
      "route": "friends",
      "trigger": "",
      "source_text": "친구를 추가하고 행동력 선물을 주고받을 수 있어요."
    },
    {
      "key": "tower",
      "level": 10,
      "title": "시련의 탑",
      "text": "🗼 시련의 탑 오픈",
      "reward": {
        "gold": 5000,
        "boxes": 2
      },
      "route": "tower",
      "trigger": "",
      "source_text": "시련의탑 설명, 강제 실행(일반+소탕)"
    },
    {
      "key": "raid",
      "level": 11,
      "title": "토벌",
      "text": "🐉 토벌 오픈",
      "reward": {
        "tickets": 10
      },
      "route": "raid",
      "trigger": "",
      "source_text": "토벌 방법 및 내용 설명, 시행(길드 가입자 한정)"
    },
    {
      "key": "camp",
      "level": 12,
      "title": "훈련소",
      "text": "🏋️ 훈련소 오픈 · 맡기면 EXP",
      "reward": {
        "gold": 5000,
        "boxes": 2
      },
      "route": "camp",
      "trigger": "",
      "source_text": "훈련소 설명 및 강제 배정(가장 레벨 낮은 캐릭터)"
    },
    {
      "key": "skill",
      "level": 13,
      "title": "EX 합성 · 스킬 강화 · 대여",
      "text": "EX 합성 · 스킬 강화 · 대여 오픈",
      "reward": {
        "soul": 1000,
        "gold": 5000
      },
      "route": "cards",
      "trigger": "",
      "source_text": "스킬 강화 방법 알려줌"
    },
    {
      "key": "sigil",
      "level": 14,
      "title": "증표",
      "text": "증표 오픈 · 📬 선택 상자",
      "reward": {
        "sigil_boxes": 10
      },
      "route": "cards",
      "trigger": "",
      "source_text": "증표 설명"
    },
    {
      "key": "trade",
      "level": 15,
      "title": "무제한 1대1 · 거래소",
      "text": "무제한 1대1 · 거래소 오픈 (가입 7일 후)",
      "reward": {
        "tickets": 10
      },
      "route": "trade",
      "trigger": "",
      "source_text": "거래소 설명 및 방법"
    },
    {
      "key": "pvp_3v3",
      "level": 17,
      "title": "3대3 리그",
      "text": "3대3 리그 오픈",
      "reward": {},
      "route": "pvp",
      "trigger": "",
      "source_text": "세 덱으로 겨루는 3대3 리그가 열렸어요. 두 리그에서 모두 도전할 수 있어요."
    },
    {
      "key": "war",
      "level": 18,
      "title": "조직전",
      "text": "🏴 구역 전쟁 오픈",
      "reward": {},
      "route": "war",
      "trigger": "",
      "source_text": "조직원들과 방어 덱을 배치하고 상대 조직에 도전해 보세요."
    },
    {
      "key": "pvp_boss",
      "level": 20,
      "title": "보스 리그",
      "text": "👑 보스 리그 오픈",
      "reward": {},
      "route": "pvp",
      "trigger": "",
      "source_text": "진영 보스를 지키는 보스 리그가 열렸어요. 두 리그에서 모두 도전할 수 있어요."
    },
    {
      "key": "facilities",
      "level": 20,
      "title": "연마소 · 도장",
      "text": "⚒️ 연마소 · 🥋 도장 오픈",
      "reward": {
        "gold": 5000
      },
      "route": "camp",
      "trigger": "",
      "source_text": "연마소, 도장 설명"
    },
    {
      "key": "attr25",
      "level": 25,
      "title": "바람 · 얼음 · 불의 탑",
      "text": "속성 탑 3곳 오픈 · 요일별",
      "reward": {},
      "route": "tower",
      "trigger": "",
      "source_text": "같은 속성 인재로 도전하는 세 탑이 열렸어요. 각 탑의 개방 요일에 도전해 보세요."
    },
    {
      "key": "attr40",
      "level": 40,
      "title": "빛의 섬 · 어둠의 늪",
      "text": "빛·어둠 탑 오픈 · 요일별",
      "reward": {},
      "route": "tower",
      "trigger": "",
      "source_text": "빛과 어둠의 인재를 위한 두 탑이 열렸어요. 각 탑의 개방 요일에 도전해 보세요."
    }
  ]
};
