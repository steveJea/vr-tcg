// ===== 스토리 챕터 10 「마지막 랠리」 (시트 CH10 → python3 tools/ch9_11_import.py <csv9> <csv10> <csv11> 로 생성. 직접 고쳐도 됨) =====
// 단일 루트(single) · 페이즈 17개 (마지막 보스). 최윤희 복장 = 대사 slug. 적 레벨은 시트 값 → enemies.boost · maxGrade (P4 UR 이상 금지, 나머지 SR 이상 금지, 필수 카드 예외) · 보스 bossCdMinus 1 (스킬 쿨타임 -1)
// 10/30 시트 개정: 시트 P17 없음 → 페이즈 17개 (시트 18 → 17 보스)
window.STORY_DATA.chapters.push({
 "id": 10,
 "title": "CHAPTER 10",
 "subtitle": "마지막 랠리",
 "rewardCard": null,
 "hero": "10413",
 "single": true,
 "phases": [
  {
   "no": 1,
   "type": "normal",
   "enemyName": "불량배-B",
   "title": "끝나지 않던 겨울",
   "enemies": {
    "ids": [
     "10144",
     "10145",
     "10153",
     "10153",
     "10154"
    ],
    "boost": {
     "10144": {
      "HP": 72,
      "ATK": 17,
      "DEF": 13,
      "storyLv": 45,
      "power": 1018
     },
     "10145": {
      "HP": 86,
      "ATK": 19,
      "DEF": 14,
      "storyLv": 45,
      "power": 1170
     },
     "10153": {
      "HP": 86,
      "ATK": 14,
      "DEF": 10,
      "storyLv": 45,
      "power": 1074
     },
     "10154": {
      "HP": 101,
      "ATK": 16,
      "DEF": 12,
      "storyLv": 45,
      "power": 1257
     }
    }
   },
   "lines": {
    "default": [
     {
      "speaker": "내레이션",
      "text": "10년 전. 아빠가 끌려가고, 엄마가 떠난 겨울."
     },
     {
      "speaker": "내레이션",
      "text": "어린 윤아는 방 밖으로 나오지 않았다. 라켓은 침대 밑에서 먼지를 뒤집어썼다."
     },
     {
      "speaker": "최윤희",
      "text": "윤아 언니...밥 먹자. 내가 계란 부쳤어. 조금 탔는데...",
      "expr": "슬픔",
      "slug": "choi_yunhee_kid"
     },
     {
      "speaker": "최윤아",
      "text": "...안 먹어. 배 안 고파.",
      "expr": "슬픔"
     },
     {
      "speaker": "최윤희",
      "text": "언니 3일째 안 먹었잖아...언니까지 없어지면 나 어떡해...",
      "expr": "슬픔",
      "slug": "choi_yunhee_kid"
     },
     {
      "speaker": "내레이션",
      "text": "문 너머에서 윤희가 훌쩍이는 소리가 들렸다. 윤아는 이불을 머리끝까지 뒤집어썼다."
     },
     {
      "speaker": "최윤정",
      "text": "최윤아. 문 열어.",
      "expr": "보통"
     },
     {
      "speaker": "최윤아",
      "text": "싫어! 언니는 아무렇지도 않지? 엄마 아빠 없어졌는데 울지도 않잖아!",
      "expr": "분노",
      "image": "img/story/ch10-01.webp"
     },
     {
      "speaker": "최윤정",
      "text": "...응. 안 울어. 내가 울면 너희가 무너지니까.",
      "expr": "보통"
     },
     {
      "speaker": "내레이션",
      "text": "문이 열렸다. 윤정은 먼지 쌓인 라켓을 윤아의 손에 쥐여 줬다."
     },
     {
      "speaker": "최윤정",
      "text": "공 100개만 쳐. 그다음에 밥 먹어. 내일은 200개.",
      "expr": "보통",
      "image": "img/story/ch10-02.webp"
     },
     {
      "speaker": "최윤아",
      "text": "...언니 진짜 얼음이야.",
      "expr": "슬픔"
     },
     {
      "speaker": "최윤정",
      "text": "알아.",
      "expr": "보통"
     },
     {
      "speaker": "내레이션",
      "text": "그날 밤, 윤아는 화장실에 가다 들었다. 굳게 닫힌 윤정의 방에서 새어 나오는, 아주 작은 울음소리를."
     },
     {
      "speaker": "최윤아",
      "text": "(언니도...겨우 14살이었지.)",
      "expr": "슬픔"
     }
    ]
   },
   "party": {
    "forced": [
     "10413"
    ],
    "noMale": true,
    "mustLive": [
     "10413"
    ],
    "levels": {
     "10413": 45
    },
    "maxGrade": "HIGH RARE"
   },
   "hero": [
    "10413"
   ],
   "bossId": "10144",
   "after": [
    {
     "speaker": "내레이션",
     "text": "다음 날 아침, 윤아는 공을 100개 쳤다. 그리고 처음으로, 밥을 남기지 않았다."
    }
   ],
   "afterTitle": "전투 후"
  },
  {
   "no": 2,
   "type": "normal",
   "enemyName": "불량배-C",
   "title": "괴물 신인",
   "enemies": {
    "ids": [
     "10145",
     "10146",
     "10154",
     "10155",
     "10155"
    ],
    "boost": {
     "10145": {
      "HP": 87,
      "ATK": 19,
      "DEF": 14,
      "storyLv": 46,
      "power": 1178
     },
     "10146": {
      "HP": 102,
      "ATK": 20,
      "DEF": 16,
      "storyLv": 46,
      "power": 1400
     },
     "10154": {
      "HP": 102,
      "ATK": 16,
      "DEF": 12,
      "storyLv": 46,
      "power": 1265
     },
     "10155": {
      "HP": 116,
      "ATK": 17,
      "DEF": 13,
      "storyLv": 46,
      "power": 1406
     }
    }
   },
   "lines": {
    "default": [
     {
      "speaker": "내레이션",
      "text": "현재. 전국 오픈 대회. 성별 구분 없이 치러지는 정부의 '통합 리그'."
     },
     {
      "speaker": "내레이션",
      "text": "결승 상대는 국가대표 남자 선수. 관중석이 술렁였다."
     },
     {
      "speaker": "권명호",
      "text": "윤아야, 저 녀석 서브가 시속 210이야. 무리하지 마. 2세트만 버텨도 대단한 거야.",
      "expr": "놀람"
     },
     {
      "speaker": "최윤아",
      "text": "코치님, 저 버티러 온 거 아닌데요? 이기러 왔지.",
      "expr": "기쁨",
      "image": "img/story/ch10-03.webp"
     },
     {
      "speaker": "권명호",
      "text": "...하. 너는 진짜 겁이라는 게 없냐.",
      "expr": "기쁨"
     },
     {
      "speaker": "최윤아",
      "text": "있죠. 윤정 언니 잔소리. 그거 말곤 없어요~",
      "expr": "기쁨"
     },
     {
      "speaker": "내레이션",
      "text": "6-2, 6-1. 경기는 1시간도 걸리지 않았다."
     },
     {
      "speaker": "내레이션",
      "text": "관중석 맨 앞, 윤희가 펄쩍펄쩍 뛰었고 윤정은 팔짱을 낀 채 아주 조금 웃었다."
     },
     {
      "speaker": "최윤희",
      "text": "최윤아!!! 최고야!!!",
      "expr": "기쁨",
      "slug": "choi_yunhee_casual",
      "image": "img/story/ch10-04.webp"
     },
     {
      "speaker": "최윤아",
      "text": "봤지 윤정 언니!? 박수 좀 쳐 줘!",
      "expr": "기쁨"
     },
     {
      "speaker": "최윤정",
      "text": "...잘했어. 근데 두 번째 세트 3번째 게임, 백핸드 늦었어.",
      "expr": "기쁨"
     },
     {
      "speaker": "최윤아",
      "text": "아 진짜! 칭찬을 해 줘도 꼭 그렇게 해!?",
      "expr": "분노"
     },
     {
      "speaker": "내레이션",
      "text": "그 순간, VIP석에서 누군가 천천히 일어나 박수를 쳤다. 금테 안경을 쓴 남자였다."
     }
    ]
   },
   "party": {
    "forced": [
     "10413"
    ],
    "noMale": true,
    "mustLive": [
     "10413"
    ],
    "levels": {
     "10413": 46
    },
    "maxGrade": "HIGH RARE"
   },
   "hero": [
    "10413"
   ],
   "bossId": "10145",
   "after": [
    {
     "speaker": "백시훈",
     "text": "훌륭하군요. 각하께서 아주 좋아하시겠어.",
     "expr": "기쁨"
    }
   ],
   "afterTitle": "전투 후"
  },
  {
   "no": 3,
   "type": "normal",
   "enemyName": "남궁현",
   "title": "초대장",
   "enemies": {
    "ids": [
     "10488",
     "10146",
     "10147",
     "10155",
     "10156"
    ],
    "boost": {
     "10488": {
      "HP": 1319,
      "ATK": 196,
      "DEF": 173,
      "storyLv": 48,
      "power": 116171
     },
     "10146": {
      "HP": 103,
      "ATK": 21,
      "DEF": 16,
      "storyLv": 48,
      "power": 1426
     },
     "10147": {
      "HP": 118,
      "ATK": 22,
      "DEF": 18,
      "storyLv": 48,
      "power": 1591
     },
     "10155": {
      "HP": 118,
      "ATK": 18,
      "DEF": 13,
      "storyLv": 48,
      "power": 1440
     },
     "10156": {
      "HP": 132,
      "ATK": 19,
      "DEF": 15,
      "storyLv": 48,
      "power": 1697
     }
    }
   },
   "lines": {
    "default": [
     {
      "speaker": "내레이션",
      "text": "라커룸. 검은 정장의 남자가 금박 봉투를 내밀었다."
     },
     {
      "speaker": "남궁현",
      "text": "최윤아 선수. 대통령 비서실장 남궁현입니다. 각하께서 선수를 용산으로 초대하셨습니다.",
      "expr": "기쁨"
     },
     {
      "speaker": "최윤아",
      "text": "...용산이요? 저를요?",
      "expr": "놀람"
     },
     {
      "speaker": "남궁현",
      "text": "각하께선 테니스를 무척 사랑하십니다. 매주 주말 각하의 전속 상대가 되어 주시면 됩니다.",
      "expr": "기쁨"
     },
     {
      "speaker": "남궁현",
      "text": "국가대표 자격, 해외 투어 지원, 자매분들의 안전지대 등급 상향...원하시는 건 뭐든.",
      "expr": "보통"
     },
     {
      "speaker": "권명호",
      "text": "윤아야...이건 엄청난 기회야. 다신 없을 거야.",
      "expr": "놀람"
     },
     {
      "speaker": "최윤아",
      "text": "...저희 아빠, 국가보안법으로 끌려갔어요. 아시죠?",
      "expr": "보통"
     },
     {
      "speaker": "남궁현",
      "text": "과거는 과거죠. 각하께선 관대하십니다.",
      "expr": "기쁨"
     },
     {
      "speaker": "내레이션",
      "text": "윤아는 봉투를 내려다봤다. 금박 위에 정부의 문장이 새겨져 있었다. 아빠를 데려간 그 문장."
     },
     {
      "speaker": "최윤아",
      "text": "(넘으면 안 되는 선. 베이스라인 밖으로 나간 공은...아웃이야.)",
      "expr": "슬픔"
     },
     {
      "speaker": "최윤아",
      "text": "생각해 볼게요.",
      "expr": "보통"
     }
    ]
   },
   "party": {
    "forced": [
     "10413"
    ],
    "noMale": true,
    "mustLive": [
     "10413"
    ],
    "levels": {
     "10413": 48
    },
    "maxGrade": "HIGH RARE"
   },
   "hero": [
    "10413"
   ],
   "bossId": "10488",
   "after": [
    {
     "speaker": "남궁현",
     "text": "물론입니다. 다만 각하께선 기다리는 걸 그리 좋아하지 않으십니다.",
     "expr": "기쁨"
    }
   ],
   "afterTitle": "전투 후"
  },
  {
   "no": 4,
   "type": "normal",
   "enemyName": "불량배-E",
   "title": "하지 말자",
   "enemies": {
    "ids": [
     "10147",
     "10148",
     "10156",
     "10156",
     "10157"
    ],
    "boost": {
     "10147": {
      "HP": 118,
      "ATK": 22,
      "DEF": 18,
      "storyLv": 49,
      "power": 1591
     },
     "10148": {
      "HP": 176,
      "ATK": 29,
      "DEF": 20,
      "storyLv": 49,
      "power": 5495
     },
     "10156": {
      "HP": 133,
      "ATK": 19,
      "DEF": 15,
      "storyLv": 49,
      "power": 1705
     },
     "10157": {
      "HP": 148,
      "ATK": 21,
      "DEF": 16,
      "storyLv": 49,
      "power": 1884
     }
    }
   },
   "lines": {
    "default": [
     {
      "speaker": "내레이션",
      "text": "그날 밤. 윤희가 잠든 뒤, 식탁 위에 금박 봉투가 놓였다."
     },
     {
      "speaker": "최윤정",
      "text": "...용산이라.",
      "expr": "보통"
     },
     {
      "speaker": "최윤아",
      "text": "언니. 나 어떡해? 가면...우리 다 편해질 수 있어. 윤희도 S급 학교 갈 수 있고.",
      "expr": "슬픔",
      "image": "img/story/ch10-05.webp"
     },
     {
      "speaker": "최윤정",
      "text": "그 사람 옆에 서면, 넌 평생 그 사람 거야. 공 하나 칠 때마다 그 사람 눈치를 보겠지.",
      "expr": "보통"
     },
     {
      "speaker": "최윤아",
      "text": "알아! 나도 알아! 근데 거절하면? 우리 아빠처럼 되면?",
      "expr": "분노"
     },
     {
      "speaker": "최윤정",
      "text": "...",
      "expr": "슬픔"
     },
     {
      "speaker": "내레이션",
      "text": "윤정은 오래 말이 없었다. 시계 초침 소리만 거실을 채웠다. 똑딱똑딱"
     },
     {
      "speaker": "최윤정",
      "text": "윤아야. 너, 아빠가 끌려가던 날 기억나?",
      "expr": "보통"
     },
     {
      "speaker": "최윤아",
      "text": "...응. 아빠가 우리한테 웃어 줬어. 괜찮다고.",
      "expr": "슬픔"
     },
     {
      "speaker": "최윤정",
      "text": "아빠는 고개를 안 숙였어. 그래서 끌려갔지만...그래서 나는 아빠가 부끄럽지 않아.",
      "expr": "슬픔"
     },
     {
      "speaker": "최윤정",
      "text": "윤아야. 하지 말자.",
      "expr": "보통"
     },
     {
      "speaker": "내레이션",
      "text": "윤아는 아주 작게, 고개를 한 번 저었다."
     },
     {
      "speaker": "내레이션",
      "text": "그 작은 몸짓 하나로, 세 자매의 계절이 바뀌었다."
     },
     {
      "speaker": "최윤아",
      "text": "...역시 얼음공주. 무섭다, 진짜.",
      "expr": "기쁨"
     }
    ]
   },
   "party": {
    "forced": [
     "10414"
    ],
    "exclude": [
     "10413"
    ],
    "mustLive": [
     "10414"
    ],
    "levels": {
     "10414": 49
    },
    "maxGrade": "SUPER RARE"
   },
   "hero": [
    "10414"
   ],
   "bossId": "10147",
   "after": [
    {
     "speaker": "최윤정",
     "text": "알아.",
     "expr": "기쁨"
    }
   ],
   "afterTitle": "전투 후"
  },
  {
   "no": 5,
   "type": "normal",
   "enemyName": "마동철",
   "title": "위험인물",
   "enemies": {
    "ids": [
     "10480",
     "10481",
     "10148",
     "10149",
     "10157"
    ],
    "boost": {
     "10480": {
      "HP": 475,
      "ATK": 62,
      "DEF": 112,
      "storyLv": 51,
      "power": 26759
     },
     "10481": {
      "HP": 470,
      "ATK": 62,
      "DEF": 62,
      "storyLv": 51,
      "power": 23445
     },
     "10148": {
      "HP": 180,
      "ATK": 30,
      "DEF": 20,
      "storyLv": 51,
      "power": 5618
     },
     "10149": {
      "HP": 220,
      "ATK": 40,
      "DEF": 30,
      "storyLv": 51,
      "power": 7686
     },
     "10157": {
      "HP": 150,
      "ATK": 21,
      "DEF": 16,
      "storyLv": 51,
      "power": 1900
     }
    }
   },
   "lines": {
    "default": [
     {
      "speaker": "내레이션",
      "text": "거절 의사를 전한 지 일주일. 집 우편함에 관공서 봉투가 꽂혔다."
     },
     {
      "speaker": "내레이션",
      "text": "[최윤정, 최윤아, 최윤희. 위 3인을 '위험인물 관리 등급'으로 지정함.]",
      "image": "img/story/ch10-06.webp"
     },
     {
      "speaker": "최윤아",
      "text": "위험인물...? 우리가 뭘 했는데?",
      "expr": "놀람"
     },
     {
      "speaker": "최윤정",
      "text": "아무것도 안 했지. 그게 죄인 거야.",
      "expr": "보통"
     },
     {
      "speaker": "내레이션",
      "text": "다음 날, 윤아의 메일함에 협회 공문이 도착했다. [모든 공식 대회 출전 자격 정지.]"
     },
     {
      "speaker": "권명호",
      "text": "윤아야...미안하다. 위에서 연락이 왔어. 나도 더는 너 못 가르친대.",
      "expr": "슬픔"
     },
     {
      "speaker": "최윤아",
      "text": "코치님까지요...?",
      "expr": "슬픔"
     },
     {
      "speaker": "권명호",
      "text": "내 가족이 있어서 그래. 정말...정말 미안하다.",
      "expr": "슬픔"
     },
     {
      "speaker": "내레이션",
      "text": "텅 빈 연습장. 윤아는 혼자 벽에 공을 쳤다. 퉁. 퉁. 퉁. 대답하는 건 벽뿐이었다."
     },
     {
      "speaker": "마동철",
      "text": "어이, 최윤아 선수? 여기 사유지 무단 사용 신고 들어왔는데.",
      "expr": "보통"
     },
     {
      "speaker": "최윤아",
      "text": "...여기 공공 코트예요. 10년째 썼다고요.",
      "expr": "분노"
     }
    ]
   },
   "party": {
    "forced": [
     "10413"
    ],
    "noMale": true,
    "mustLive": [
     "10413"
    ],
    "levels": {
     "10413": 51
    },
    "maxGrade": "HIGH RARE"
   },
   "hero": [
    "10413"
   ],
   "bossId": "10480",
   "after": [
    {
     "speaker": "구태만",
     "text": "어제까진 공공이었지. 오늘부턴 아니야. 짐 싸.",
     "expr": "기쁨"
    }
   ],
   "afterTitle": "전투 후"
  },
  {
   "no": 6,
   "type": "normal",
   "enemyName": "구태만",
   "title": "보이는 감시",
   "enemies": {
    "ids": [
     "10481",
     "10480",
     "10149",
     "10158",
     "10158"
    ],
    "boost": {
     "10481": {
      "HP": 476,
      "ATK": 63,
      "DEF": 63,
      "storyLv": 52,
      "power": 23773
     },
     "10480": {
      "HP": 481,
      "ATK": 63,
      "DEF": 114,
      "storyLv": 52,
      "power": 27151
     },
     "10149": {
      "HP": 222,
      "ATK": 40,
      "DEF": 30,
      "storyLv": 52,
      "power": 7727
     },
     "10158": {
      "HP": 151,
      "ATK": 23,
      "DEF": 23,
      "storyLv": 52,
      "power": 2062
     }
    }
   },
   "lines": {
    "default": [
     {
      "speaker": "내레이션",
      "text": "집 앞엔 늘 같은 차가 서 있었다. 숨길 생각도 없는 듯 시동을 켜 둔 채로."
     },
     {
      "speaker": "최윤아",
      "text": "저 차 또 있어. 3일째야.",
      "expr": "분노"
     },
     {
      "speaker": "최윤정",
      "text": "일부러 보이게 하는 거야. 우리가 겁먹으라고.",
      "expr": "보통"
     },
     {
      "speaker": "최윤아",
      "text": "겁 안 먹어! 내가 가서 창문 두드려 볼까?",
      "expr": "분노"
     },
     {
      "speaker": "최윤정",
      "text": "최윤아. 그게 그 사람들이 원하는 거야. 먼저 손대게 만드는 거.",
      "expr": "분노"
     },
     {
      "speaker": "내레이션",
      "text": "그때, 윤희가 현관을 들어서며 웃었다."
     },
     {
      "speaker": "최윤희",
      "text": "언니들 다녀왔어~ 오늘 지킴이 애들이 쿠키 맛있대!",
      "expr": "기쁨",
      "slug": "choi_yunhee_school"
     },
     {
      "speaker": "최윤아",
      "text": "오~ 우리 윤희 인기쟁이~ 언니도 줘!",
      "expr": "기쁨"
     },
     {
      "speaker": "내레이션",
      "text": "윤희가 2층으로 올라가자, 두 언니의 웃음이 동시에 꺼졌다.",
      "image": "img/story/ch10-07.webp"
     },
     {
      "speaker": "최윤아",
      "text": "...윤희는 모르지?",
      "expr": "슬픔"
     },
     {
      "speaker": "최윤정",
      "text": "몰라야 해. 끝까지.",
      "expr": "보통"
     }
    ]
   },
   "party": {
    "forced": [
     "10413"
    ],
    "noMale": true,
    "mustLive": [
     "10413"
    ],
    "levels": {
     "10413": 52
    },
    "maxGrade": "HIGH RARE"
   },
   "hero": [
    "10413"
   ],
   "bossId": "10481",
   "after": [
    {
     "speaker": "최윤아",
     "text": "(근데 언니...끝까지가 언제까지야?)",
     "expr": "슬픔"
    }
   ],
   "afterTitle": "전투 후"
  },
  {
   "no": 7,
   "type": "normal",
   "enemyName": "백시훈",
   "title": "보복의 실",
   "enemies": {
    "ids": [
     "10475",
     "10158",
     "10159",
     "10149",
     "10150"
    ],
    "boost": {
     "10475": {
      "HP": 749,
      "ATK": 137,
      "DEF": 119,
      "storyLv": 54,
      "power": 68355
     },
     "10158": {
      "HP": 153,
      "ATK": 23,
      "DEF": 23,
      "storyLv": 54,
      "power": 2078
     },
     "10159": {
      "HP": 206,
      "ATK": 41,
      "DEF": 33,
      "storyLv": 54,
      "power": 7126
     },
     "10149": {
      "HP": 227,
      "ATK": 41,
      "DEF": 31,
      "storyLv": 54,
      "power": 7919
     },
     "10150": {
      "HP": 309,
      "ATK": 62,
      "DEF": 52,
      "storyLv": 54,
      "power": 11484
     }
    }
   },
   "lines": {
    "default": [
     {
      "speaker": "내레이션",
      "text": "윤희의 팬클럽이 사라졌다. 현관 앞에 하얀 상자가 놓였다. 윤희의 휴대폰엔 모르는 번호가 쌓여 갔다."
     },
     {
      "speaker": "내레이션",
      "text": "윤아는 상자를 치우며 깨달았다. 이건 우연이 아니라고."
     },
     {
      "speaker": "최윤아",
      "text": "...전부 연결돼 있어. 내가 고개 저은 그날부터.",
      "expr": "분노"
     },
     {
      "speaker": "내레이션",
      "text": "그날 밤, 윤아의 휴대폰에 메시지가 왔다."
     },
     {
      "speaker": "내레이션",
      "text": "[최윤아 선수. 막내 동생분이 요즘 많이 예민하시죠? 다 선수 덕분입니다.]"
     },
     {
      "speaker": "내레이션",
      "text": "[각하의 초대는 아직 유효합니다. -백시훈-]"
     },
     {
      "speaker": "최윤아",
      "text": "이 개OO...!",
      "expr": "분노"
     },
     {
      "speaker": "최윤아",
      "text": "(나 때문이야. 윤희가 밤마다 문을 3번씩 확인하는 것도, 밥을 못 먹는 것도...)",
      "expr": "슬픔"
     },
     {
      "speaker": "최윤아",
      "text": "(내가 그냥 고개를 끄덕였으면...)",
      "expr": "슬픔"
     },
     {
      "speaker": "내레이션",
      "text": "윤아는 휴대폰을 쥔 채 윤희의 방문 앞에 섰다. 문틈으로 불빛이 새어 나왔다. 윤희는 또 불을 켠 채 자고 있었다."
     }
    ]
   },
   "party": {
    "forced": [
     "10413"
    ],
    "noMale": true,
    "mustLive": [
     "10413"
    ],
    "levels": {
     "10413": 54
    },
    "maxGrade": "HIGH RARE"
   },
   "hero": [
    "10413"
   ],
   "bossId": "10475",
   "after": [
    {
     "speaker": "최윤아",
     "text": "...미안해, 윤희야.",
     "expr": "슬픔"
    }
   ],
   "afterTitle": "전투 후"
  },
  {
   "no": 8,
   "type": "normal",
   "enemyName": "독곰",
   "title": "흙투성이",
   "enemies": {
    "ids": [
     "10482",
     "10150",
     "10151",
     "10159",
     "10159"
    ],
    "boost": {
     "10482": {
      "HP": 524,
      "ATK": 126,
      "DEF": 105,
      "storyLv": 55,
      "power": 32287
     },
     "10150": {
      "HP": 312,
      "ATK": 62,
      "DEF": 52,
      "storyLv": 55,
      "power": 11546
     },
     "10151": {
      "HP": 524,
      "ATK": 79,
      "DEF": 79,
      "storyLv": 55,
      "power": 28509
     },
     "10159": {
      "HP": 208,
      "ATK": 42,
      "DEF": 33,
      "storyLv": 55,
      "power": 7211
     }
    }
   },
   "lines": {
    "default": [
     {
      "speaker": "내레이션",
      "text": "초겨울 저녁. 윤아와 윤정의 목소리가 골목을 헤맸다."
     },
     {
      "speaker": "최윤아",
      "text": "윤희야!!! 최윤희!!! 어디 있어!!!!",
      "expr": "놀람"
     },
     {
      "speaker": "내레이션",
      "text": "골목 끝. 흙투성이가 된 작은 몸이 웅크리고 있었다.",
      "image": "img/story/ch10-08.webp"
     },
     {
      "speaker": "최윤아",
      "text": "윤희야...윤희야, 눈 떠 봐! 언니야!!",
      "expr": "슬픔"
     },
     {
      "speaker": "최윤희",
      "text": "언니...언니...무서웠어...",
      "expr": "다침",
      "slug": "choi_yunhee_school"
     },
     {
      "speaker": "내레이션",
      "text": "윤희의 무릎은 까져 피가 배어 있었고, 교복은 흙으로 엉망이었다. 윤희는 언니 품에서 아이처럼 흐느꼈다.",
      "image": "img/story/ch10-09.webp"
     },
     {
      "speaker": "최윤희",
      "text": "그 사람이...사랑한대...앞으로 재밌어질 거래...언니...왜...?",
      "expr": "슬픔",
      "slug": "choi_yunhee_school"
     },
     {
      "speaker": "최윤아",
      "text": "미안해...미안해, 윤희야...다 나 때문이야...내가...",
      "expr": "슬픔"
     },
     {
      "speaker": "최윤정",
      "text": "최윤아. 지금은 아니야.",
      "expr": "분노"
     },
     {
      "speaker": "내레이션",
      "text": "윤아는 이를 악물었다. 골목 입구, 가로등 아래 그림자 하나가 천천히 사라졌다."
     }
    ]
   },
   "party": {
    "forced": [
     "10413"
    ],
    "noMale": true,
    "mustLive": [
     "10413"
    ],
    "levels": {
     "10413": 55
    },
    "maxGrade": "HIGH RARE"
   },
   "hero": [
    "10413"
   ],
   "bossId": "10482",
   "after": [
    {
     "speaker": "최윤아",
     "text": "(가만 안 둬. 절대로.)",
     "expr": "분노"
    }
   ],
   "afterTitle": "전투 후"
  },
  {
   "no": 9,
   "type": "normal",
   "enemyName": "마동철",
   "title": "차가운 창구",
   "enemies": {
    "ids": [
     "10480",
     "10481",
     "10151",
     "10160",
     "10160"
    ],
    "boost": {
     "10480": {
      "HP": 509,
      "ATK": 67,
      "DEF": 121,
      "storyLv": 57,
      "power": 28779
     },
     "10481": {
      "HP": 504,
      "ATK": 67,
      "DEF": 67,
      "storyLv": 57,
      "power": 25213
     },
     "10151": {
      "HP": 536,
      "ATK": 80,
      "DEF": 80,
      "storyLv": 57,
      "power": 29045
     },
     "10160": {
      "HP": 254,
      "ATK": 53,
      "DEF": 45,
      "storyLv": 57,
      "power": 9066
     }
    }
   },
   "lines": {
    "default": [
     {
      "speaker": "내레이션",
      "text": "다음 날 아침. 세 자매는 경찰서를 찾았다."
     },
     {
      "speaker": "최윤아",
      "text": "어젯밤 우리 동생이 골목에서 습격당했어요. 덩치 3명이랑, 금테 안경 쓴 남자요.",
      "expr": "분노"
     },
     {
      "speaker": "마동철",
      "text": "아...또 그 학생이네. 다친 데는? 크게 없잖아.",
      "expr": "보통"
     },
     {
      "speaker": "최윤정",
      "text": "흙바닥에 쓰러져서 기절했어요. 그게 안 다친 건가요?",
      "expr": "분노"
     },
     {
      "speaker": "구태만",
      "text": "학생, 솔직히 말해 봐. 평소 네 행실에 문제 있었던 거 아냐?",
      "expr": "기쁨"
     },
     {
      "speaker": "최윤희",
      "text": "...",
      "expr": "슬픔",
      "slug": "choi_yunhee_casual"
     },
     {
      "speaker": "마동철",
      "text": "그 남자도 너 좋다고 하는 건데, 한 번 만나 봐. 높은 분이야. 인생 펴질 수도 있어.",
      "expr": "기쁨"
     },
     {
      "speaker": "최윤아",
      "text": "지금 그걸 말이라고 해요!?",
      "expr": "분노",
      "image": "img/story/ch10-10.webp"
     },
     {
      "speaker": "구태만",
      "text": "목소리 낮춰, 최윤아. 위험인물 등급 주제에 경찰서에서 소리 지르면 어떻게 되는지 알아?",
      "expr": "분노"
     },
     {
      "speaker": "최윤정",
      "text": "...가자, 윤아야. 여긴 도와줄 곳이 아니야.",
      "expr": "보통"
     },
     {
      "speaker": "내레이션",
      "text": "경찰서 문을 나서는 순간, 윤희가 작게 중얼거렸다."
     },
     {
      "speaker": "최윤희",
      "text": "...언니들. 나 이제 아무한테도 도와달라고 안 할래.",
      "expr": "슬픔",
      "slug": "choi_yunhee_casual"
     }
    ]
   },
   "party": {
    "forced": [
     "10413"
    ],
    "noMale": true,
    "mustLive": [
     "10413"
    ],
    "levels": {
     "10413": 57
    },
    "maxGrade": "HIGH RARE"
   },
   "hero": [
    "10413"
   ],
   "bossId": "10480",
   "after": [
    {
     "speaker": "최윤아",
     "text": "(윤희야...그런 말 하지 마...)",
     "expr": "슬픔"
    }
   ],
   "afterTitle": "전투 후"
  },
  {
   "no": 10,
   "type": "normal",
   "enemyName": "백시훈",
   "title": "멈추지 않는 카운트다운",
   "enemies": {
    "ids": [
     "10475",
     "10160",
     "10161",
     "10152",
     "10152"
    ],
    "boost": {
     "10475": {
      "HP": 787,
      "ATK": 144,
      "DEF": 125,
      "storyLv": 58,
      "power": 71825
     },
     "10160": {
      "HP": 257,
      "ATK": 53,
      "DEF": 45,
      "storyLv": 58,
      "power": 9123
     },
     "10161": {
      "HP": 278,
      "ATK": 58,
      "DEF": 49,
      "storyLv": 58,
      "power": 10532
     },
     "10152": {
      "HP": 623,
      "ATK": 122,
      "DEF": 122,
      "storyLv": 58,
      "power": 40167
     }
    }
   },
   "lines": {
    "default": [
     {
      "speaker": "내레이션",
      "text": "메시지는 하루에도 몇 번씩 왔다."
     },
     {
      "speaker": "내레이션",
      "text": "[선택할 시간이 얼마 안 남았습니다. 째깍째깍.]"
     },
     {
      "speaker": "내레이션",
      "text": "[최윤정 씨 회사, 오늘부로 정리되었습니다.]"
     },
     {
      "speaker": "내레이션",
      "text": "[막내분, 오늘 학교 끝나고 혼자 걸어가시더군요.]"
     },
     {
      "speaker": "최윤아",
      "text": "...언니. 나 그냥 갈게. 용산. 그럼 다 끝나잖아.",
      "expr": "분노"
     },
     {
      "speaker": "최윤정",
      "text": "안 돼.",
      "expr": "분노"
     },
     {
      "speaker": "최윤아",
      "text": "왜!? 이러다 윤희 진짜 죽어! 언니도, 나도! 다 죽는다고!",
      "expr": "분노"
     },
     {
      "speaker": "최윤정",
      "text": "...이미 늦었어, 윤아야. 지금 가면 너는 인질이고, 우리는 너를 묶는 사슬이 돼. 그 사람들은 한 번 물면 안 놔.",
      "expr": "슬픔"
     },
     {
      "speaker": "최윤아",
      "text": "그럼...그럼 어떡해...",
      "expr": "슬픔"
     },
     {
      "speaker": "최윤정",
      "text": "도망칠 준비를 하고 있어. 배척지 쪽에 아는 사람이 있어. 이틀만 버텨.",
      "expr": "보통"
     }
    ]
   },
   "party": {
    "forced": [
     "10413"
    ],
    "noMale": true,
    "mustLive": [
     "10413"
    ],
    "levels": {
     "10413": 58
    },
    "maxGrade": "HIGH RARE"
   },
   "hero": [
    "10413"
   ],
   "bossId": "10475",
   "after": [
    {
     "speaker": "내레이션",
     "text": "Tick-tack. 멈추지 않는 카운트다운. 출구 없는 미로 속에서, 시계만 앞으로 갔다."
    }
   ],
   "afterTitle": "전투 후"
  },
  {
   "no": 11,
   "type": "normal",
   "enemyName": "불량배-J",
   "title": "마지막 저녁",
   "enemies": {
    "ids": [
     "10152",
     "10161",
     "10162",
     "10162",
     "10163"
    ],
    "boost": {
     "10152": {
      "HP": 637,
      "ATK": 125,
      "DEF": 125,
      "storyLv": 60,
      "power": 41109
     },
     "10161": {
      "HP": 283,
      "ATK": 59,
      "DEF": 50,
      "storyLv": 60,
      "power": 10724
     },
     "10162": {
      "HP": 327,
      "ATK": 65,
      "DEF": 57,
      "storyLv": 60,
      "power": 12204
     },
     "10163": {
      "HP": 499,
      "ATK": 83,
      "DEF": 72,
      "storyLv": 60,
      "power": 27547
     }
    }
   },
   "lines": {
    "default": [
     {
      "speaker": "내레이션",
      "text": "이틀 뒤. 짐은 작은 가방 3개로 줄었다."
     },
     {
      "speaker": "최윤희",
      "text": "언니들...우리 진짜 이사 가는 거야? 갑자기?",
      "expr": "보통",
      "slug": "choi_yunhee_home"
     },
     {
      "speaker": "최윤아",
      "text": "응! 더 좋은 데로. 거기 가면 언니가 윤희 테니스 가르쳐 줄게~",
      "expr": "기쁨"
     },
     {
      "speaker": "최윤희",
      "text": "에이, 나 운동 못하는 거 알잖아.",
      "expr": "기쁨",
      "slug": "choi_yunhee_home"
     },
     {
      "speaker": "최윤아",
      "text": "괜찮아. 공 100개만 치면 돼. 윤정 언니가 옛날에 나한테 그랬거든.",
      "expr": "기쁨"
     },
     {
      "speaker": "최윤정",
      "text": "...그때 넌 50개 치고 울었어.",
      "expr": "기쁨"
     },
     {
      "speaker": "최윤아",
      "text": "아 그건 왜 기억하는데!?",
      "expr": "분노"
     },
     {
      "speaker": "내레이션",
      "text": "오랜만에 셋이 함께 웃었다. 식탁엔 윤희가 만든 된장국이 김을 피워 올렸다."
     },
     {
      "speaker": "최윤희",
      "text": "(이런 저녁이...계속됐으면 좋겠다.)",
      "expr": "기쁨",
      "slug": "choi_yunhee_home"
     },
     {
      "speaker": "최윤정",
      "text": "...일찍 자. 내일 새벽 4시에 나간다.",
      "expr": "보통"
     },
     {
      "speaker": "내레이션",
      "text": "그날 밤 윤정은 처음으로, 동생들 앞에서 옅게 눈시울을 붉혔다. 윤아만 그걸 봤다."
     }
    ]
   },
   "party": {
    "forced": [
     "10413"
    ],
    "noMale": true,
    "mustLive": [
     "10413"
    ],
    "levels": {
     "10413": 60
    },
    "maxGrade": "HIGH RARE"
   },
   "hero": [
    "10413"
   ],
   "bossId": "10152",
   "after": [
    {
     "speaker": "최윤아",
     "text": "(언니...)",
     "expr": "슬픔"
    }
   ],
   "afterTitle": "전투 후"
  },
  {
   "no": 12,
   "type": "normal",
   "enemyName": "독곰",
   "title": "소리 없는 손님",
   "enemies": {
    "ids": [
     "10482",
     "10483",
     "10484",
     "10143",
     "10144"
    ],
    "boost": {
     "10482": {
      "HP": 560,
      "ATK": 134,
      "DEF": 112,
      "storyLv": 61,
      "power": 34443
     },
     "10483": {
      "HP": 622,
      "ATK": 126,
      "DEF": 84,
      "storyLv": 61,
      "power": 33149
     },
     "10484": {
      "HP": 672,
      "ATK": 140,
      "DEF": 70,
      "storyLv": 61,
      "power": 37871
     },
     "10143": {
      "HP": 80,
      "ATK": 18,
      "DEF": 13,
      "storyLv": 61,
      "power": 1094
     },
     "10144": {
      "HP": 80,
      "ATK": 19,
      "DEF": 14,
      "storyLv": 61,
      "power": 1126
     }
    }
   },
   "lines": {
    "default": [
     {
      "speaker": "내레이션",
      "text": "새벽 2시. 현관문은 부서지지 않았다. 누군가 열쇠로, 아주 조용히 열었다."
     },
     {
      "speaker": "내레이션",
      "text": "거실의 시계만이 그 발소리를 들었다. 똑딱. 똑딱."
     },
     {
      "speaker": "최윤아",
      "text": "(...뭐지. 이 시간에 계단 밑에서...)",
      "expr": "놀람"
     },
     {
      "speaker": "내레이션",
      "text": "물을 마시러 내려온 윤아의 눈앞에, 검은 옷의 거인 셋이 서 있었다."
     },
     {
      "speaker": "독곰",
      "text": "...깼네. 운도 없지.",
      "expr": "보통"
     },
     {
      "speaker": "최윤아",
      "text": "누구야...! 우리 집에서 나가!!",
      "expr": "분노"
     },
     {
      "speaker": "최윤정",
      "text": "윤아야? 무슨 소리...",
      "expr": "놀람"
     },
     {
      "speaker": "내레이션",
      "text": "윤정이 계단을 내려왔다. 그리고 단번에 모든 걸 알아챘다. 윤정은 가장 먼저, 2층으로 이어지는 계단을 등 뒤에 두었다."
     },
     {
      "speaker": "최윤정",
      "text": "...윤아야. 소리 지르지 마. 윤희 깨.",
      "expr": "보통"
     },
     {
      "speaker": "최윤아",
      "text": "언니, 뒤로 가! 내가 막을게!",
      "expr": "분노"
     },
     {
      "speaker": "쇳덩이",
      "text": "막아? 그 조그만 손으로?",
      "expr": "기쁨"
     },
     {
      "speaker": "내레이션",
      "text": "윤아는 벽에 기대 있던 라켓을 움켜쥐었다. 내일 새벽 4시, 들고 나가려던 단 하나의 짐이었다."
     },
     {
      "speaker": "최윤아",
      "text": "...베이스라인이야. 여기서부터는 한 발짝도 못 넘어가.",
      "expr": "분노",
      "image": "img/story/ch10-11.webp"
     },
     {
      "speaker": "내레이션",
      "text": "라켓이 바닥에 떨어지는 소리. 그리고 시계 소리만 남았다."
     },
     {
      "speaker": "내레이션",
      "text": "윤아는 마지막까지 윤정의 앞을 막아서 있었다. 윤정은 마지막까지 계단 앞을 비키지 않았다."
     },
     {
      "speaker": "최윤정",
      "text": "...윤...희는...건드리지...마...",
      "expr": "다침"
     },
     {
      "speaker": "바위",
      "text": "2층 막내는? 같이 정리해?",
      "expr": "보통"
     },
     {
      "speaker": "독곰",
      "text": "뭐...얘들만 처리하고 막내는 천천히 말려 죽이는 걸...각하가 더 좋아하실걸?",
      "expr": "기쁨"
     },
     {
      "speaker": "쇳덩이",
      "text": "하긴. 아침에 일어나서 이거 보면...그게 더 재밌겠네.",
      "expr": "기쁨"
     }
    ]
   },
   "party": {
    "forced": [
     "10413"
    ],
    "noMale": true,
    "mustLive": [
     "10413"
    ],
    "levels": {
     "10413": 61
    },
    "maxGrade": "HIGH RARE"
   },
   "hero": [
    "10413"
   ],
   "bossId": "10482",
   "after": [
    {
     "speaker": "내레이션",
     "text": "문이 다시, 아주 조용히 닫혔다. 2층에서는 작은 숨소리만이 고르게 이어지고 있었다."
    }
   ],
   "afterTitle": "전투 후"
  },
  {
   "no": 13,
   "type": "normal",
   "enemyName": "상급 몽마",
   "title": "악몽",
   "enemies": {
    "ids": [
     "10501",
     "10500",
     "10500",
     "10500",
     "10500"
    ],
    "boost": {
     "10501": {
      "HP": 603,
      "ATK": 109,
      "DEF": 109,
      "storyLv": 63,
      "power": 37593
     },
     "10500": {
      "HP": 273,
      "ATK": 60,
      "DEF": 60,
      "storyLv": 63,
      "power": 11654
     }
    }
   },
   "lines": {
    "default": [
     {
      "speaker": "내레이션",
      "text": "윤희는 꿈을 꾸고 있었다. 끝없는 테니스 코트. 하얀 선이 어둠 속으로 이어져 있었다."
     },
     {
      "speaker": "최윤희",
      "text": "윤아 언니! 윤정 언니! 기다려!",
      "expr": "기쁨",
      "slug": "choi_yunhee_home"
     },
     {
      "speaker": "내레이션",
      "text": "두 언니의 뒷모습이 멀어졌다. 아무리 뛰어도 거리는 줄어들지 않았다."
     },
     {
      "speaker": "최윤희",
      "text": "언니...왜 대답을 안 해...? 나 여기 있어...!",
      "expr": "슬픔",
      "slug": "choi_yunhee_home",
      "image": "img/story/ch10-12.webp"
     },
     {
      "speaker": "내레이션",
      "text": "코트 바닥이 검게 물들었다. 그 안에서 무언가가 기어 올라왔다. 얼굴 없는 그림자, 몽마."
     },
     {
      "speaker": "몽마",
      "text": "막내야...막내야...언니들은 이제 안 와...",
      "expr": "기쁨"
     },
     {
      "speaker": "최윤희",
      "text": "...거짓말. 언니들이 내일 새벽에 같이 가자고 했어. 이사 가는 거야.",
      "expr": "놀람",
      "slug": "choi_yunhee_home"
     },
     {
      "speaker": "몽마",
      "text": "이사? 그래, 멀리 갔지. 아주 멀리. 너만 두고.",
      "expr": "기쁨"
     },
     {
      "speaker": "몽마",
      "text": "네가 제일 약하니까. 네가 제일 쓸모없으니까. 다들 너 때문에 끝났어.",
      "expr": "분노"
     },
     {
      "speaker": "최윤희",
      "text": "아니야...아니야...!",
      "expr": "슬픔",
      "slug": "choi_yunhee_home"
     },
     {
      "speaker": "내레이션",
      "text": "몽마들이 하나, 둘, 다섯으로 늘어났다. 모두 윤희의 얼굴을 하고 웃고 있었다.",
      "image": "img/story/ch10-13.webp"
     }
    ]
   },
   "party": {
    "forced": [
     "10415"
    ],
    "noMale": true,
    "mustLive": [
     "10415"
    ],
    "levels": {
     "10415": 63
    },
    "maxGrade": "HIGH RARE"
   },
   "hero": [
    "10415"
   ],
   "bossId": "10501",
   "after": [
    {
     "speaker": "최윤희",
     "text": "...저리 가. 언니들이 그랬어. 웃으면서 살라고. 너희 같은 거한테 안 져.",
     "expr": "분노",
     "slug": "choi_yunhee_home"
    }
   ],
   "afterTitle": "전투 후"
  },
  {
   "no": 14,
   "type": "normal",
   "enemyName": "불량배-G",
   "title": "거실",
   "enemies": {
    "ids": [
     "10149",
     "10149",
     "10149",
     "10149",
     "10149"
    ],
    "boost": {
     "10149": {
      "HP": 251,
      "ATK": 46,
      "DEF": 34,
      "storyLv": 65,
      "power": 8778
     }
    }
   },
   "lines": {
    "default": [
     {
      "speaker": "내레이션",
      "text": "윤희는 숨을 헐떡이며 눈을 떴다. 새벽 5시. 전등은 켜져 있었다. 늘 그랬듯이."
     },
     {
      "speaker": "최윤희",
      "text": "(...4시에 나간다고 했는데. 왜 아무도 안 깨웠지.)",
      "expr": "놀람",
      "slug": "choi_yunhee_home"
     },
     {
      "speaker": "내레이션",
      "text": "집이 너무 조용했다. 윤정의 잔소리도, 윤아의 투덜거림도 들리지 않았다.",
      "image": "img/story/ch10-14.webp"
     },
     {
      "speaker": "최윤희",
      "text": "(이상해...가슴이 너무 답답해. 꿈 때문일 거야. 그냥 꿈...)",
      "expr": "슬픔",
      "slug": "choi_yunhee_home"
     },
     {
      "speaker": "내레이션",
      "text": "계단을 한 칸씩 내려갔다. 차가운 바닥이 맨발에 닿았다.",
      "image": "img/story/ch10-15-1.webp"
     },
     {
      "speaker": "내레이션",
      "text": "시계 소리만 들렸다. 똑딱. 똑딱.",
      "image": "img/story/ch10-15-2.webp"
     },
     {
      "speaker": "최윤희",
      "text": "언니...? 윤아 언니...? 윤정 언니...?",
      "expr": "보통",
      "slug": "choi_yunhee_home",
      "image": "img/story/ch10-16.webp"
     },
     {
      "speaker": "내레이션",
      "text": "거실. 두 사람은 거기 있었다. 서로를 감싸듯 나란히, 다시는 일어나지 않을 모습으로."
     },
     {
      "speaker": "내레이션",
      "text": "바닥엔 윤아의 라켓과, 풀어진 머리끈 하나가 떨어져 있었다."
     },
     {
      "speaker": "최윤희",
      "text": "...언니...? 장난이지...? 일어나...4시 지났어...",
      "expr": "놀람",
      "slug": "choi_yunhee_home"
     },
     {
      "speaker": "최윤희",
      "text": "언니...윤정 언니...눈 떠 봐...윤아 언니...대답해...제발...",
      "expr": "슬픔",
      "slug": "choi_yunhee_home"
     },
     {
      "speaker": "내레이션",
      "text": "대답은 없었다. 식탁 위에는 어젯밤 남은 된장국이 식어 있었다."
     },
     {
      "speaker": "최윤희",
      "text": "아...아아...아아아아아...!!!",
      "expr": "슬픔",
      "slug": "choi_yunhee_home"
     },
     {
      "speaker": "내레이션",
      "text": "윤희는 떨리는 손으로 윤아의 머리끈을 움켜쥐었다. 그리고, 그 집에서 도망쳤다.",
      "image": "img/story/ch10-17.webp"
     }
    ]
   },
   "party": {
    "forced": [
     "10415"
    ],
    "noMale": true,
    "mustLive": [
     "10415"
    ],
    "levels": {
     "10415": 63
    },
    "maxGrade": "HIGH RARE"
   },
   "hero": [
    "10415"
   ],
   "bossId": "10149"
  },
  {
   "no": 15,
   "type": "normal",
   "enemyName": "불량배-C",
   "title": "맨발",
   "enemies": {
    "ids": [
     "10145",
     "10146",
     "10153",
     "10153",
     "10154"
    ],
    "boost": {
     "10145": {
      "HP": 98,
      "ATK": 21,
      "DEF": 16,
      "storyLv": 65,
      "power": 1323
     },
     "10146": {
      "HP": 115,
      "ATK": 23,
      "DEF": 18,
      "storyLv": 65,
      "power": 1586
     },
     "10153": {
      "HP": 98,
      "ATK": 16,
      "DEF": 11,
      "storyLv": 65,
      "power": 1219
     },
     "10154": {
      "HP": 115,
      "ATK": 18,
      "DEF": 13,
      "storyLv": 65,
      "power": 1417
     }
    }
   },
   "lines": {
    "default": [
     {
      "speaker": "내레이션",
      "text": "맨발. 잠옷 차림. 윤희는 어디로 가는지도 모른 채 새벽 골목을 달렸다."
     },
     {
      "speaker": "최윤희",
      "text": "(어디로...어디로 가야 해...경찰은 안 도와줘...아무도 안 도와줘...)",
      "expr": "슬픔",
      "slug": "choi_yunhee_home"
     },
     {
      "speaker": "내레이션",
      "text": "발이 돌부리에 걸렸다. 윤희는 차가운 아스팔트 위로 그대로 쓰러졌다. 무릎에서 피가 배어 나왔다."
     },
     {
      "speaker": "최윤희",
      "text": "...아...",
      "expr": "다침",
      "slug": "choi_yunhee_home"
     },
     {
      "speaker": "내레이션",
      "text": "고개를 들자, 밤새 놀다 돌아가던 무리가 그녀를 내려다보고 있었다."
     },
     {
      "speaker": "불량배-C",
      "text": "뭐야, 이 시간에 맨발로? 너 그 위험인물 집 막내 아냐?"
     },
     {
      "speaker": "불량배-K",
      "text": "어머, 진짜네. 얼굴만 예쁘면 뭐 해. 꼴이 이게 뭐야."
     },
     {
      "speaker": "불량배-D",
      "text": "야, 그 손에 쥔 거 뭐야? 내놔 봐."
     },
     {
      "speaker": "최윤희",
      "text": "...만지지 마. 이건...이건 언니 거야.",
      "expr": "분노",
      "slug": "choi_yunhee_home"
     },
     {
      "speaker": "불량배-L",
      "text": "언니? 걔네 다 잡혀갔다며? 아직 모르나 봐. ㅋㅋ"
     }
    ]
   },
   "party": {
    "forced": [
     "10415"
    ],
    "noMale": true,
    "mustLive": [
     "10415"
    ],
    "levels": {
     "10415": 65
    },
    "maxGrade": "HIGH RARE"
   },
   "hero": [
    "10415"
   ],
   "bossId": "10145",
   "after": [
    {
     "speaker": "최윤희",
     "text": "...비켜. 제발...비켜 줘...!",
     "expr": "분노",
     "slug": "choi_yunhee_home"
    }
   ],
   "afterTitle": "전투 후"
  },
  {
   "no": 16,
   "type": "normal",
   "enemyName": "[염원] 최윤아",
   "title": "떨리는 손",
   "enemies": {
    "ids": [
     "10490",
     "10490",
     "10490"
    ],
    "boost": {
     "10490": {
      "HP": 1440,
      "ATK": 234,
      "DEF": 234,
      "storyLv": 66,
      "power": 168731
     }
    }
   },
   "lines": {
    "default": [
     {
      "speaker": "내레이션",
      "text": "무리가 흩어진 뒤. 윤희는 무너진 담벼락 아래 주저앉았다.",
      "image": "img/story/ch10-18.webp"
     },
     {
      "speaker": "내레이션",
      "text": "하늘이 조금씩 밝아 오고 있었다. 언니들이 기다리던 새벽이었다."
     },
     {
      "speaker": "최윤희",
      "text": "(언니들이 해가 뜨면 같이 가자고 했는데...해는 뜨는데...)",
      "expr": "슬픔",
      "slug": "choi_yunhee_home"
     },
     {
      "speaker": "최윤희",
      "text": "(나 혼자 어떻게 웃어...나 혼자 어떻게 살아...)",
      "expr": "슬픔",
      "slug": "choi_yunhee_home"
     },
     {
      "speaker": "내레이션",
      "text": "윤희는 머리끈을 쥔 두 손을 가슴 앞에 모았다. 손이 멈추지 않고 떨렸다."
     },
     {
      "speaker": "최윤희",
      "text": "신이시여 제발..",
      "expr": "슬픔",
      "slug": "choi_yunhee_home"
     },
     {
      "speaker": "최윤희",
      "text": "제 목소리가 들린다면 부디 이 떨리는 손을 잡아주세요..",
      "expr": "슬픔",
      "slug": "choi_yunhee_home"
     },
     {
      "speaker": "내레이션",
      "text": "작은 셋방. 윤희는 무릎을 끌어안고 웅크려 있었다. 손에는 윤아의 머리끈이 쥐어져 있었다."
     },
     {
      "speaker": "최윤희",
      "text": "언니...내가 웃으면서 살래...언니 몫까지...근데 어떻게 웃는지 모르겠어...",
      "expr": "슬픔",
      "slug": "choi_yunhee_home"
     },
     {
      "speaker": "최윤아",
      "text": "윤희야! 언니 여기 있어! 윤희야!!",
      "expr": "슬픔",
      "image": "img/story/ch10-19.webp"
     },
     {
      "speaker": "내레이션",
      "text": "윤아는 유리창을 두드렸다. 소리가 나지 않았다. 손이 유리를 그대로 통과했다."
     },
     {
      "speaker": "최윤아",
      "text": "...아. 그렇구나. 나...",
      "expr": "슬픔"
     },
     {
      "speaker": "내레이션",
      "text": "닿을 수 없었다. 한 뼘도 안 되는 거리인데, 영원처럼 멀었다."
     },
     {
      "speaker": "최윤아",
      "text": "Little one, don't cry...울지 마...제발...",
      "expr": "슬픔"
     }
    ]
   },
   "party": {
    "forced": [
     "10415"
    ],
    "noMale": true,
    "mustLive": [
     "10415"
    ],
    "levels": {
     "10415": 66
    },
    "maxGrade": "HIGH RARE"
   },
   "hero": [
    "10415"
   ],
   "bossId": "10490",
   "after": [
    {
     "speaker": "내레이션",
     "text": "창문에 비친 자신의 모습이 일렁였다. 그건 윤아가 아니라, 윤아의 미련이었다.",
     "image": "img/story/ch10-20.webp"
    }
   ],
   "afterTitle": "전투 후"
  },
  {
   "no": 17,
   "type": "boss",
   "enemyName": "[염원] 최윤아",
   "title": "곁에 있는 그림자",
   "enemies": {
    "ids": [
     "10490"
    ],
    "boost": {
     "10490": {
      "HP": 1664,
      "ATK": 270,
      "DEF": 270,
      "storyLv": 80,
      "power": 194858
     }
    }
   },
   "lines": {
    "default": [
     {
      "speaker": "내레이션",
      "text": "얼마나 지났을까. 윤아는 매일 밤 그 창문 앞에 서 있었다."
     },
     {
      "speaker": "내레이션",
      "text": "윤희는 매일 밤 불을 켠 채 잠들었다. 매일 밤 두 손을 모았다."
     },
     {
      "speaker": "최윤희",
      "text": "하느님...우리 언니들, 춥지 않게 해 주세요.",
      "expr": "슬픔",
      "slug": "choi_yunhee_home",
      "image": "img/story/ch10-21.webp"
     },
     {
      "speaker": "최윤아",
      "text": "...안 추워, 윤희야. 언니 하나도 안 추워.",
      "expr": "슬픔"
     },
     {
      "speaker": "내레이션",
      "text": "그때, 윤아는 느꼈다. 바로 옆. 아주 익숙한 기척."
     },
     {
      "speaker": "내레이션",
      "text": "차가운 유리창 위, 윤아의 그림자 옆에 또 하나의 그림자가 겹쳐 있었다."
     },
     {
      "speaker": "내레이션",
      "text": "곧게 편 등. 팔짱을 낀 손. 웃지 않는 입꼬리."
     },
     {
      "speaker": "최윤아",
      "text": "...언니?",
      "expr": "놀람"
     },
     {
      "speaker": "내레이션",
      "text": "대답은 없었다. 하지만 그 그림자는 아주 조금, 정말 아주 조금 고개를 끄덕였다."
     },
     {
      "speaker": "최윤아",
      "text": "...ㅎㅎ 역시 얼음공주. 먼저 와 있었구나.",
      "expr": "기쁨"
     },
     {
      "speaker": "최윤아",
      "text": "그럼 우리...끝까지 같이 있자. 윤희 옆에.",
      "expr": "기쁨",
      "image": "img/story/ch10-22.webp"
     },
     {
      "speaker": "최윤아",
      "text": "마지막까지.",
      "expr": "기쁨"
     },
     {
      "speaker": "내레이션",
      "text": "창문 안, 잠든 윤희의 입가에 아주 옅은 미소가 스쳤다."
     }
    ]
   },
   "party": {
    "forced": [
     "10413"
    ],
    "noMale": true,
    "mustLive": [
     "10413"
    ],
    "levels": {
     "10413": 70
    },
    "maxGrade": "HIGH RARE"
   },
   "hero": [
    "10413"
   ],
   "bossId": "10490",
   "after": [
    {
     "speaker": "내레이션",
     "text": "Chapter 10. fin"
    }
   ],
   "afterTitle": "전투 후",
   "final": true,
   "bossCdMinus": 1
  }
 ],
 "tagline": "",
 "warning": "이 챕터에는 괴롭힘·폭력·죽음 묘사가 포함되어 있습니다.",
 "start": [
  {
   "speaker": "내레이션",
   "text": "최윤아. 코트 위에선 누구도 그녀를 이길 수 없었다. 남자든, 여자든."
  },
  {
   "speaker": "내레이션",
   "text": "작은 키, 동그란 눈, 웃으면 사라지는 보조개. 하지만 라켓을 쥐는 순간 그녀는 괴물이 된다."
  },
  {
   "speaker": "내레이션",
   "text": "Tick-tack. 멈추지 않는 카운트다운."
  },
  {
   "speaker": "내레이션",
   "text": "그날, 그녀가 고개를 아주 작게 한 번 저었을 때...계절이 바뀌었다."
  },
  {
   "speaker": "최윤아",
   "text": "넘으면 안 되는 선이 있어. 베이스라인처럼.",
   "expr": "보통"
  },
  {
   "speaker": "최윤아",
   "text": "...그 선을 지키느라, 우리는 전부를 걸었어.",
   "expr": "보통"
  }
 ],
 "ending": [],
 "endingVideo": "1egJLy6rkPw"
});
