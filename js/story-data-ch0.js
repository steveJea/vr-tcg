// ===== 스토리 챕터 0 「공허한 여신」 (튜토리얼 · 시트 → python3 tools/ch0_import.py <csv> 로 생성. 직접 고쳐도 됨) =====
// 강제 출전 임유리. 페이즈별 tutorial(data/tutorials/<id>.json) · reserve(소환 대기) · awaken(임유리 쓰러지면 [각성] 임유리 난입)
window.STORY_DATA.chapters.unshift({
 "id": 0,
 "title": "CHAPTER 0",
 "subtitle": "공허한 여신",
 "single": true,
 "hero": "2000100001",
 "tutorial": true,
 "start": [
  {
   "speaker": "내레이션",
   "text": "임유리...SS급 안전지대의 여신으로 통한다.",
   "image": "img/story/ch0-01.webp"
  },
  {
   "speaker": "내레이션",
   "text": "SDK홀딩스 대주주이자 이 국가의 정치, 경제, 언론을 좌지우지 하는 임씨 가문의 혈통이다."
  },
  {
   "speaker": "내레이션",
   "text": "그 누구도 범접할 수 없는 기품과 화려함으로 대중을 압도하는 카리스마."
  },
  {
   "speaker": "내레이션",
   "text": "하지만 타인의 감정을 공감하지 못하는 소시오패스로,"
  },
  {
   "speaker": "내레이션",
   "text": "그녀는 항상 공허할 뿐이다"
  }
 ],
 "rewardCards": {
  "1": "2000100006",
  "2": "2000100004",
  "3": "2000900206"
 },
 "phases": [
  {
   "no": 1,
   "type": "normal",
   "enemyName": "오유나",
   "title": "공허한 여신님",
   "enemies": {
    "ids": [
     "2000100006"
    ],
    "boost": {
     "2000100006": {
      "HP": 700
     }
    }
   },
   "lines": {
    "default": [
     {
      "speaker": "임유리",
      "text": "...오늘은 얼마나 천천히 흘러갈까?",
      "expr": "하품"
     },
     {
      "speaker": "내레이션",
      "text": "유리는 그녀만의 성에 있다.",
      "image": "img/story/ch0-02.webp"
     },
     {
      "speaker": "내레이션",
      "text": "누군가가 문을 두드린다."
     },
     {
      "speaker": "임유리",
      "text": "어...들어와."
     },
     {
      "speaker": "오유나",
      "text": "유리님. 오늘 스케줄을 보고 드려도 될까요?",
      "expr": "웃음"
     },
     {
      "speaker": "임유리",
      "text": "후암...다 알어. 그나저나 유나야.",
      "expr": "웃음"
     },
     {
      "speaker": "오유나",
      "text": "예, 유리님!",
      "expr": "놀람"
     },
     {
      "speaker": "임유리",
      "text": "오랜만에 우리 몸이나 풀까?",
      "expr": "야비"
     },
     {
      "speaker": "오유나",
      "text": "...!!!",
      "expr": "놀람"
     }
    ]
   },
   "after": [
    {
     "speaker": "임유리",
     "text": "약하네...",
     "expr": "하품"
    },
    {
     "speaker": "내레이션",
     "text": "오유나가 동료가 되었다."
    }
   ],
   "tutorial": "ch0_p1",
   "party": {
    "forced": [
     "2000100001"
    ],
    "mustLive": [
     "2000100001"
    ],
    "noExtra": true,
    "auto": true,
    "battleLevels": {
     "2000100001": 2
    }
   },
   "fullMp": true
  },
  {
   "no": 2,
   "type": "normal",
   "enemyName": "불량배L",
   "title": "사냥",
   "enemies": {
    "ids": [
     "2000000024",
     "2000000023",
     "2000000023",
     "2000000023",
     "2000000023"
    ]
   },
   "lines": {
    "default": [
     {
      "speaker": "내레이션",
      "text": "유리는 유나를 데리고 어딘가로 향한다."
     },
     {
      "speaker": "내레이션",
      "text": "이곳은 SS 안전지대의 번화가"
     },
     {
      "speaker": "임유리",
      "text": "여긴...언제나 더럽네...",
      "expr": "짜증"
     },
     {
      "speaker": "오유나",
      "text": "...하하..",
      "expr": "웃음"
     },
     {
      "speaker": "내레이션",
      "text": "그 때 골목길에 불량해 보이는 사람들이 보였다."
     },
     {
      "speaker": "임유리",
      "text": "유나야..우리 심심한데 쟤들이나 혼내줄까?",
      "expr": "야비"
     },
     {
      "speaker": "오유나",
      "text": "...하하..네..유리님과 함께라면 가능해요!",
      "expr": "당황"
     },
     {
      "speaker": "임유리",
      "text": "거기 패배자들~ 언니가 놀아줄까?",
      "expr": "야비"
     },
     {
      "speaker": "불량배L",
      "text": "뭐야 쟤들은?"
     },
     {
      "speaker": "불량배K",
      "text": "혼나고 싶은거야?"
     },
     {
      "speaker": "임유리",
      "text": "잘 부탁할게여~",
      "expr": "하품",
      "image": "img/story/ch0-03.webp"
     }
    ]
   },
   "after": [
    {
     "speaker": "임유리",
     "text": "아...재미 없어. 유나야 쟤들 치워.",
     "expr": "하품"
    },
    {
     "speaker": "내레이션",
     "text": "쓰러진 불량배들 뒤, 한 소녀가 유리를 올려다본다."
    },
    {
     "speaker": "황보예",
     "text": "저… 저도 데려가 주세요!",
     "expr": "기쁨"
    },
    {
     "speaker": "임유리",
     "expr": "야비",
     "text": "귀엽네. 따라와."
    },
    {
     "speaker": "내레이션",
     "text": "황보예가 동료가 되었다."
    }
   ],
   "tutorial": "ch0_p2",
   "party": {
    "forced": [
     "2000100001"
    ],
    "mustLive": [
     "2000100001"
    ],
    "noExtra": true,
    "auto": true
   },
   "reserve": [
    "2000100006"
   ]
  },
  {
   "no": 3,
   "type": "normal",
   "enemyName": "임나리",
   "title": "위기",
   "enemies": {
    "ids": [
     "2000300083",
     "2000000038",
     "2000000038",
     "2000000038",
     "2000000038"
    ],
    "storyLevels": {
     "2000300083": 30,
     "2000000038": 30
    },
    "levels": {
     "2000300083": 5,
     "2000000038": 3
    }
   },
   "lines": {
    "default": [
     {
      "speaker": "내레이션",
      "text": "이곳은 유리의 성"
     },
     {
      "speaker": "내레이션",
      "text": "누군가의 그림자가 보인다"
     },
     {
      "speaker": "임유리",
      "text": "어머, 이게 누구야? 우리 나리?",
      "expr": "웃음"
     },
     {
      "speaker": "임나리",
      "text": "너...",
      "expr": "분노",
      "image": "img/story/ch0-04.webp"
     },
     {
      "speaker": "임유리",
      "text": "어머..언니한테 너가 뭐니?",
      "expr": "야비"
     },
     {
      "speaker": "임나리",
      "text": "너...왜 그랬어!!!!!?",
      "expr": "분노"
     },
     {
      "speaker": "임유리",
      "text": "나리야...뭐 그리 말이 많아?",
      "expr": "야비"
     }
    ]
   },
   "after": [
    {
     "speaker": "[각성] 임유리",
     "text": "....약해...",
     "image": "img/story/ch0-05.webp"
    },
    {
     "speaker": "내레이션",
     "text": "무너진 성 한쪽, 숨어 있던 소녀가 걸어 나온다."
    },
    {
     "speaker": "송지아",
     "text": "…방금 그거, 당신이 한 거야?"
    },
    {
     "speaker": "[각성] 임유리",
     "expr": "싸늘",
     "text": "…따라오든지."
    },
    {
     "speaker": "내레이션",
     "text": "송지아가 동료가 되었다."
    }
   ],
   "tutorial": "ch0_p3",
   "party": {
    "forced": [
     "2000100001"
    ],
    "mustLive": [],
    "fixedLevel": {
     "2000100001": 1
    },
    "only": [
     "2000100006",
     "2000100004"
    ],
    "guests": [
     "2000100006",
     "2000100004"
    ]
   },
   "awaken": {
    "on": "2000100001",
    "id": "2000000008",
    "storyLevel": 100,
    "battleLevel": 10,
    "line": "....약해...",
    "image": "img/story/ch0-05.webp"
   }
  }
 ]
});
