// ===== 스토리 챕터 9 「기도」 (시트 CH9 → python3 tools/ch9_11_import.py <csv9> <csv10> <csv11> 로 생성. 직접 고쳐도 됨) =====
// 단일 루트(single) · 페이즈 18개 (마지막 보스). 최윤희 복장 = 대사 slug. 적 레벨은 시트 값 → enemies.boost
window.STORY_DATA.chapters.push({
 "id": 9,
 "title": "CHAPTER 9",
 "subtitle": "기도",
 "rewardCard": null,
 "hero": "10415",
 "single": true,
 "phases": [
  {
   "no": 1,
   "type": "normal",
   "enemyName": "불량배-B",
   "title": "세 자매의 아침",
   "enemies": {
    "ids": [
     "10144",
     "10145",
     "10145",
     "10145",
     "10145"
    ],
    "boost": {
     "10144": {
      "HP": 70,
      "ATK": 17,
      "DEF": 13,
      "storyLv": 40,
      "power": 1003
     },
     "10145": {
      "HP": 83,
      "ATK": 18,
      "DEF": 14,
      "storyLv": 40,
      "power": 1131
     }
    }
   },
   "lines": {
    "default": [
     {
      "speaker": "내레이션",
      "text": "아침 6시. 부엌에서 된장국 냄새가 퍼졌다."
     },
     {
      "speaker": "최윤희",
      "text": "언니들~ 일어나! 오늘은 계란말이에 치즈도 넣었어!",
      "expr": "기쁨",
      "slug": "choi_yunhee_school"
     },
     {
      "speaker": "최윤아",
      "text": "으으...윤희야, 5분만...어제 훈련 너무 빡셌단 말이야...",
      "expr": "보통"
     },
     {
      "speaker": "최윤정",
      "text": "최윤아. 너 5분 소리만 오늘 3번째야. 일어나.",
      "expr": "보통"
     },
     {
      "speaker": "최윤아",
      "text": "아 언니는 무슨 6시에 벌써 정장을 입고 있어? 사람이야?",
      "expr": "분노"
     },
     {
      "speaker": "최윤정",
      "text": "사람이니까 출근을 하지. 윤희야, 국 간 좀 싱거워.",
      "expr": "보통"
     },
     {
      "speaker": "최윤희",
      "text": "헤헤, 언니 혈압 생각해서 일부러 싱겁게 한 거야~",
      "expr": "기쁨",
      "slug": "choi_yunhee_school"
     },
     {
      "speaker": "최윤아",
      "text": "와, 윤정 언니 막내한테 혼났다! ㅋㅋㅋ",
      "expr": "기쁨"
     },
     {
      "speaker": "최윤정",
      "text": "...맛있다고는 안 했어. 싱겁다고 했지. 근데 다 먹을 거야.",
      "expr": "보통"
     },
     {
      "speaker": "내레이션",
      "text": "얼음공주라 불리는 윤정의 입꼬리가 아주 조금 올라갔다. 윤희만 알아챌 수 있을 만큼."
     },
     {
      "speaker": "최윤희",
      "text": "(이런 아침이 매일 계속됐으면 좋겠다.)",
      "expr": "기쁨",
      "slug": "choi_yunhee_school"
     },
     {
      "speaker": "내레이션",
      "text": "등굣길. 골목 어귀에서 낯선 불량배들이 담배를 피우며 윤희를 훑어봤다."
     },
     {
      "speaker": "불량배-B",
      "text": "와...저 동네에 저런 애가 살았어?",
      "expr": "기쁨"
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
     "10415": 40
    }
   },
   "hero": [
    "10415"
   ],
   "bossId": "10144",
   "after": [
    {
     "speaker": "최윤희",
     "text": "(...빨리 지나가자.)",
     "expr": "보통",
     "slug": "choi_yunhee_school"
    }
   ],
   "afterTitle": "전투 후"
  },
  {
   "no": 2,
   "type": "normal",
   "enemyName": "불량배-C",
   "title": "윤희 지킴이",
   "enemies": {
    "ids": [
     "10145",
     "10153",
     "10153",
     "10144",
     "10144"
    ],
    "boost": {
     "10145": {
      "HP": 84,
      "ATK": 18,
      "DEF": 14,
      "storyLv": 41,
      "power": 1138
     },
     "10153": {
      "HP": 84,
      "ATK": 14,
      "DEF": 10,
      "storyLv": 41,
      "power": 1059
     },
     "10144": {
      "HP": 70,
      "ATK": 17,
      "DEF": 13,
      "storyLv": 41,
      "power": 1003
     }
    }
   },
   "lines": {
    "default": [
     {
      "speaker": "내레이션",
      "text": "윤희가 다니는 학교엔 비밀 아닌 비밀이 있다."
     },
     {
      "speaker": "내레이션",
      "text": "스스로를 [윤희 지킴이]라 부르는, 공식적으로는 존재하지 않는 팬클럽."
     },
     {
      "speaker": "한도겸",
      "text": "오늘 윤희님 등교 시간 7시 52분. 이상 없음. 날씨 맑음.",
      "expr": "기쁨"
     },
     {
      "speaker": "오세찬",
      "text": "오늘도 천사 같으셨다...아, 근데 아까 골목에 이상한 놈들 있었지?",
      "expr": "기쁨"
     },
     {
      "speaker": "한도겸",
      "text": "있었지. 이미 우리 3학년 형들이 '정중하게' 돌려보냈어.",
      "expr": "분노"
     },
     {
      "speaker": "최윤희",
      "text": "저기...혹시 너희가 맨날 내 뒤에서 걸어오는 애들이야?",
      "expr": "놀람",
      "slug": "choi_yunhee_school"
     },
     {
      "speaker": "오세찬",
      "text": "헉! 윤희님이 말을 거셨다!",
      "expr": "놀람"
     },
     {
      "speaker": "한도겸",
      "text": "아, 아니요! 저희는 그냥...그냥 같은 방향일 뿐입니다!",
      "expr": "놀람"
     },
     {
      "speaker": "최윤희",
      "text": "ㅎㅎ 고마워. 근데 나한테 존댓말 안 해도 돼. 우리 동갑이잖아.",
      "expr": "기쁨",
      "slug": "choi_yunhee_school"
     },
     {
      "speaker": "오세찬",
      "text": "그럴 순 없어요...윤희님은...윤희님이니까요...",
      "expr": "슬픔"
     },
     {
      "speaker": "최윤희",
      "text": "으...진짜 이상한 애들이야. 그래도 고마워. 이거 먹어, 내가 만든 쿠키야.",
      "expr": "기쁨",
      "slug": "choi_yunhee_school"
     },
     {
      "speaker": "한도겸",
      "text": "가보로 남기겠습니다.",
      "expr": "기쁨"
     },
     {
      "speaker": "오세찬",
      "text": "아니 먹어야지 이 병X아...",
      "expr": "기쁨"
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
     "10415": 41
    }
   },
   "hero": [
    "10415"
   ],
   "bossId": "10145",
   "after": [
    {
     "speaker": "내레이션",
     "text": "윤희는 웃었다. 이 작은 세상이, 윤희에겐 전부였다."
    }
   ],
   "afterTitle": "전투 후"
  },
  {
   "no": 3,
   "type": "normal",
   "enemyName": "불량배-K",
   "title": "코트 위의 천재",
   "enemies": {
    "ids": [
     "10153",
     "10154",
     "10154",
     "10145",
     "10145"
    ],
    "boost": {
     "10153": {
      "HP": 85,
      "ATK": 14,
      "DEF": 10,
      "storyLv": 43,
      "power": 1066
     },
     "10154": {
      "HP": 99,
      "ATK": 16,
      "DEF": 11,
      "storyLv": 43,
      "power": 1226
     },
     "10145": {
      "HP": 85,
      "ATK": 18,
      "DEF": 14,
      "storyLv": 43,
      "power": 1145
     }
    }
   },
   "lines": {
    "default": [
     {
      "speaker": "내레이션",
      "text": "주말. 지역 테니스 대회 결승전. 관중석 맨 앞줄에 윤희와 윤정이 앉아 있었다.",
      "image": "img/story/ch9-05.webp"
     },
     {
      "speaker": "최윤희",
      "text": "윤아 언니 파이팅!!! 최윤아 최고!!!",
      "expr": "기쁨",
      "slug": "choi_yunhee_casual"
     },
     {
      "speaker": "최윤정",
      "text": "윤희야, 목소리 좀...옆 사람들이 쳐다봐.",
      "expr": "보통"
     },
     {
      "speaker": "최윤희",
      "text": "언니도 같이 해! 최윤아 파이팅!",
      "expr": "기쁨",
      "slug": "choi_yunhee_casual"
     },
     {
      "speaker": "최윤정",
      "text": "...파이팅.",
      "expr": "보통"
     },
     {
      "speaker": "최윤아",
      "text": "ㅋㅋㅋ 윤정 언니 파이팅 들었다! 오늘 무조건 이긴다!",
      "expr": "기쁨"
     },
     {
      "speaker": "내레이션",
      "text": "윤아의 서브가 코트에 꽂혔다. 경기는 일방적이었다.",
      "image": "img/story/ch9-06.webp"
     },
     {
      "speaker": "내레이션",
      "text": "시상식이 끝나고, 정장 차림의 남자 둘이 윤아에게 다가왔다. 가슴엔 정부의 배지가 반짝였다."
     },
     {
      "speaker": "최윤아",
      "text": "...또 오셨네요. 대답은 저번에 드렸잖아요.",
      "expr": "놀람"
     },
     {
      "speaker": "내레이션",
      "text": "남자들이 무언가 낮게 속삭였다. 윤아의 얼굴이 굳었다."
     },
     {
      "speaker": "최윤아",
      "text": "싫다고요. 몇 번을 말해요. 저는 그런 자리 안 가요.",
      "expr": "분노"
     },
     {
      "speaker": "내레이션",
      "text": "멀리서 지켜보던 윤정의 눈빛이 차갑게 가라앉았다."
     },
     {
      "speaker": "최윤희",
      "text": "언니...저 사람들 누구야?",
      "expr": "놀람",
      "slug": "choi_yunhee_casual"
     },
     {
      "speaker": "최윤정",
      "text": "...스폰서 제안이래. 윤아가 워낙 잘하니까. 신경 쓰지 마.",
      "expr": "보통"
     }
    ]
   },
   "party": {
    "forced": [
     "10413"
    ],
    "exclude": [
     "10415"
    ],
    "mustLive": [
     "10413"
    ],
    "levels": {
     "10413": 43
    }
   },
   "hero": [
    "10413"
   ],
   "bossId": "10153",
   "after": [
    {
     "speaker": "최윤아",
     "text": "(그 사람한테 전해. 나는...절대 그 옆에 안 선다고.)",
     "expr": "분노"
    }
   ],
   "afterTitle": "전투 후"
  },
  {
   "no": 4,
   "type": "normal",
   "enemyName": "불량배-L",
   "title": "얼음공주의 밤",
   "enemies": {
    "ids": [
     "10154",
     "10155",
     "10155",
     "10153",
     "10153"
    ],
    "boost": {
     "10154": {
      "HP": 100,
      "ATK": 16,
      "DEF": 11,
      "storyLv": 44,
      "power": 1234
     },
     "10155": {
      "HP": 114,
      "ATK": 17,
      "DEF": 13,
      "storyLv": 44,
      "power": 1391
     },
     "10153": {
      "HP": 86,
      "ATK": 14,
      "DEF": 10,
      "storyLv": 44,
      "power": 1074
     }
    }
   },
   "lines": {
    "default": [
     {
      "speaker": "내레이션",
      "text": "그날 밤. 윤희가 잠든 뒤, 거실엔 두 언니만 남았다."
     },
     {
      "speaker": "최윤아",
      "text": "언니...이번엔 진짜 끈질겨. 그 사람 측근이 직접 왔어.",
      "expr": "슬픔"
     },
     {
      "speaker": "최윤정",
      "text": "알아. 이번 달만 3번째야. 우리 집 주소도 이미 알고 있겠지.",
      "expr": "보통"
     },
     {
      "speaker": "최윤아",
      "text": "그냥 한 번 가서 얼굴만 비추고 올까? 그럼 조용해지지 않을까?",
      "expr": "분노"
     },
     {
      "speaker": "최윤정",
      "text": "최윤아. 아빠가 어떻게 끌려갔는지 잊었어? 한 번 고개 숙이면, 평생 숙여야 돼.",
      "expr": "분노"
     },
     {
      "speaker": "최윤아",
      "text": "...알아. 근데 무서워. 나 말고...윤희한테 무슨 일 생기면...",
      "expr": "슬픔"
     },
     {
      "speaker": "최윤정",
      "text": "그래서 윤희는 몰라야 해. 아무것도.",
      "expr": "보통"
     },
     {
      "speaker": "내레이션",
      "text": "그때, 2층 계단에서 작은 발소리가 났다.",
      "image": "img/story/ch9-07.webp"
     },
     {
      "speaker": "최윤희",
      "text": "언니들...아직 안 자? 무슨 얘기해?",
      "expr": "놀람",
      "slug": "choi_yunhee_home"
     },
     {
      "speaker": "최윤아",
      "text": "아, 아냐아냐! 윤정 언니가 회사에서 또 상사 갈궜대! ㅋㅋㅋ",
      "expr": "기쁨"
     },
     {
      "speaker": "최윤정",
      "text": "...응. 그 사람이 좀 멍청해서. 얼른 자, 윤희야.",
      "expr": "기쁨"
     },
     {
      "speaker": "최윤희",
      "text": "으응...알았어. 언니들도 일찍 자~",
      "expr": "보통",
      "slug": "choi_yunhee_home"
     },
     {
      "speaker": "내레이션",
      "text": "윤희가 방으로 돌아가자, 윤정은 웃음을 거두고 창밖을 봤다."
     },
     {
      "speaker": "내레이션",
      "text": "길 건너 가로등 아래. 검은 승용차 한 대가 시동을 켠 채 서 있었다."
     }
    ]
   },
   "party": {
    "forced": [
     "10414"
    ],
    "exclude": [
     "10415"
    ],
    "mustLive": [
     "10414"
    ],
    "levels": {
     "10414": 44
    }
   },
   "hero": [
    "10414"
   ],
   "bossId": "10154",
   "after": [
    {
     "speaker": "최윤정",
     "text": "(...벌써 시작됐구나.)",
     "expr": "분노"
    }
   ],
   "afterTitle": "전투 후"
  },
  {
   "no": 5,
   "type": "normal",
   "enemyName": "장민규",
   "title": "사라진 지킴이",
   "enemies": {
    "ids": [
     "10478",
     "10144",
     "10144",
     "10145",
     "10145"
    ],
    "boost": {
     "10478": {
      "HP": 209,
      "ATK": 30,
      "DEF": 30,
      "storyLv": 45,
      "power": 7718
     },
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
     }
    }
   },
   "lines": {
    "default": [
     {
      "speaker": "내레이션",
      "text": "월요일 아침. 7시 52분. 윤희는 습관처럼 뒤를 돌아봤다."
     },
     {
      "speaker": "최윤희",
      "text": "...어? 오늘은 아무도 없네?",
      "expr": "놀람",
      "slug": "choi_yunhee_school"
     },
     {
      "speaker": "내레이션",
      "text": "다음 날도, 그 다음 날도. 늘 뒤에서 걸어오던 발소리가 사라졌다."
     },
     {
      "speaker": "최윤희",
      "text": "저기...혹시 도겸이 어디 갔는지 알아? 3반 한도겸 말이야.",
      "expr": "보통",
      "slug": "choi_yunhee_school"
     },
     {
      "speaker": "장민규",
      "text": "...!",
      "expr": "놀람"
     },
     {
      "speaker": "장민규",
      "text": "모, 몰라. 나한테 묻지 마. 미안, 나 바빠.",
      "expr": "슬픔"
     },
     {
      "speaker": "최윤희",
      "text": "어? 너도 지킴이였잖아. 왜 그래?",
      "expr": "놀람",
      "slug": "choi_yunhee_school"
     },
     {
      "speaker": "장민규",
      "text": "이제 그런 거 없어! 다 해체했어! 그러니까...나한테 말 걸지 마!",
      "expr": "분노"
     },
     {
      "speaker": "내레이션",
      "text": "민규는 도망치듯 자리를 떴다. 손목에 시퍼런 멍이 보였다."
     },
     {
      "speaker": "최윤희",
      "text": "(멍...? 쟤 왜 저렇게 겁먹은 거지...)",
      "expr": "놀람",
      "slug": "choi_yunhee_school"
     },
     {
      "speaker": "내레이션",
      "text": "그날 오후, 윤희는 도겸이 학교를 그만뒀다는 소식을 들었다. 이유는 아무도 몰랐다."
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
     "10415": 45
    }
   },
   "hero": [
    "10415"
   ],
   "bossId": "10478",
   "after": [
    {
     "speaker": "최윤희",
     "text": "(나 때문인가...? 아니야. 설마. 그냥 우연이겠지.)",
     "expr": "슬픔",
     "slug": "choi_yunhee_school"
    }
   ],
   "afterTitle": "전투 후"
  },
  {
   "no": 6,
   "type": "normal",
   "enemyName": "장민규",
   "title": "하얀 포장지",
   "enemies": {
    "ids": [
     "10478",
     "10479",
     "10145",
     "10153",
     "10153"
    ],
    "boost": {
     "10478": {
      "HP": 213,
      "ATK": 31,
      "DEF": 31,
      "storyLv": 47,
      "power": 7908
     },
     "10479": {
      "HP": 227,
      "ATK": 48,
      "DEF": 25,
      "storyLv": 47,
      "power": 8876
     },
     "10145": {
      "HP": 88,
      "ATK": 19,
      "DEF": 15,
      "storyLv": 47,
      "power": 1200
     },
     "10153": {
      "HP": 88,
      "ATK": 15,
      "DEF": 10,
      "storyLv": 47,
      "power": 1108
     }
    }
   },
   "lines": {
    "default": [
     {
      "speaker": "내레이션",
      "text": "저녁. 현관 앞에 작은 상자 하나가 놓여 있었다. 하얀 포장지에 분홍 리본."
     },
     {
      "speaker": "최윤희",
      "text": "어? 선물이다. 누가 두고 갔지? 혹시 지킴이 애들인가?",
      "expr": "기쁨",
      "slug": "choi_yunhee_home"
     },
     {
      "speaker": "내레이션",
      "text": "리본을 푸는 순간, 비릿한 냄새가 훅 올라왔다."
     },
     {
      "speaker": "최윤희",
      "text": "...!!!",
      "expr": "놀람",
      "slug": "choi_yunhee_home"
     },
     {
      "speaker": "내레이션",
      "text": "상자 안엔 비둘기 한 마리가 들어 있었다. 더 이상 날지 못하는."
     },
     {
      "speaker": "내레이션",
      "text": "그 아래, 반듯한 글씨의 카드 한 장. [너를 위해 준비했어. 예쁘지? 좋아해서 그래.]",
      "image": "img/story/ch9-08.webp"
     },
     {
      "speaker": "최윤희",
      "text": "으...으읍...!",
      "expr": "슬픔",
      "slug": "choi_yunhee_home"
     },
     {
      "speaker": "내레이션",
      "text": "윤희는 그 자리에 주저앉았다. 손이 덜덜 떨렸다."
     },
     {
      "speaker": "최윤아",
      "text": "윤희야? 왜 그래? ...이게 뭐야!!",
      "expr": "놀람"
     },
     {
      "speaker": "최윤아",
      "text": "어떤 개OO가 이딴 짓을...!",
      "expr": "분노"
     },
     {
      "speaker": "최윤희",
      "text": "언니...좋아해서 그렇대...좋아해서...",
      "expr": "슬픔",
      "slug": "choi_yunhee_home"
     },
     {
      "speaker": "최윤아",
      "text": "괜찮아, 괜찮아. 언니가 치울게. 보지 마. 응? 들어가 있어.",
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
     "10415": 47
    }
   },
   "hero": [
    "10415"
   ],
   "bossId": "10478",
   "after": [
    {
     "speaker": "내레이션",
     "text": "윤아는 상자를 든 채 골목을 노려봤다. 어둠 속 어딘가에서 누군가 웃는 것 같았다."
    }
   ],
   "afterTitle": "전투 후"
  },
  {
   "no": 7,
   "type": "normal",
   "enemyName": "백시훈",
   "title": "그림자",
   "enemies": {
    "ids": [
     "10475",
     "10479",
     "10478",
     "10144",
     "10145"
    ],
    "boost": {
     "10475": {
      "HP": 691,
      "ATK": 127,
      "DEF": 109,
      "storyLv": 48,
      "power": 63056
     },
     "10479": {
      "HP": 229,
      "ATK": 48,
      "DEF": 25,
      "storyLv": 48,
      "power": 8922
     },
     "10478": {
      "HP": 215,
      "ATK": 31,
      "DEF": 31,
      "storyLv": 48,
      "power": 7953
     },
     "10144": {
      "HP": 74,
      "ATK": 18,
      "DEF": 13,
      "storyLv": 48,
      "power": 1050
     },
     "10145": {
      "HP": 88,
      "ATK": 19,
      "DEF": 15,
      "storyLv": 48,
      "power": 1200
     }
    }
   },
   "lines": {
    "default": [
     {
      "speaker": "내레이션",
      "text": "그날 이후, 윤희는 길을 걸을 때마다 이상한 기분이 들었다."
     },
     {
      "speaker": "내레이션",
      "text": "또각. 또각. 윤희가 멈추면, 뒤의 발소리도 멈췄다."
     },
     {
      "speaker": "최윤희",
      "text": "(...누구야. 누가 따라오는 거야.)",
      "expr": "놀람",
      "slug": "choi_yunhee_casual"
     },
     {
      "speaker": "내레이션",
      "text": "뒤를 돌아보면 아무도 없었다. 가로등 아래 길게 늘어진 자신의 그림자뿐.",
      "image": "img/story/ch9-09.webp"
     },
     {
      "speaker": "최윤희",
      "text": "(내 그림자가...왜 이렇게 무섭지.)",
      "expr": "슬픔",
      "slug": "choi_yunhee_casual"
     },
     {
      "speaker": "내레이션",
      "text": "편의점 유리창에 비친 거리. 검은 코트를 입은 남자가 길 건너에서 윤희를 보고 있었다."
     },
     {
      "speaker": "내레이션",
      "text": "깔끔하게 넘긴 머리, 금테 안경, 온화한 미소."
     },
     {
      "speaker": "백시훈",
      "text": "...",
      "expr": "기쁨"
     },
     {
      "speaker": "최윤희",
      "text": "(저 사람...어제 학교 앞에도 있었어. 그저께는 버스 정류장에도...)",
      "expr": "놀람",
      "slug": "choi_yunhee_casual"
     },
     {
      "speaker": "내레이션",
      "text": "윤희가 다시 돌아봤을 때, 남자는 사라지고 없었다."
     },
     {
      "speaker": "내레이션",
      "text": "휴대폰이 울렸다. 모르는 번호. [오늘 노란 머리끈 잘 어울리더라.]"
     },
     {
      "speaker": "최윤희",
      "text": "...!",
      "expr": "놀람",
      "slug": "choi_yunhee_casual"
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
     "10415": 48
    }
   },
   "hero": [
    "10415"
   ],
   "bossId": "10475",
   "after": [
    {
     "speaker": "최윤희",
     "text": "(오늘 아침에...처음 한 건데...)",
     "expr": "슬픔",
     "slug": "choi_yunhee_casual"
    }
   ],
   "afterTitle": "전투 후"
  },
  {
   "no": 8,
   "type": "normal",
   "enemyName": "배현오",
   "title": "잠기지 않는 문",
   "enemies": {
    "ids": [
     "10479",
     "10478",
     "10153",
     "10154",
     "10154"
    ],
    "boost": {
     "10479": {
      "HP": 234,
      "ATK": 50,
      "DEF": 26,
      "storyLv": 50,
      "power": 9189
     },
     "10478": {
      "HP": 220,
      "ATK": 32,
      "DEF": 32,
      "storyLv": 50,
      "power": 8166
     },
     "10153": {
      "HP": 89,
      "ATK": 15,
      "DEF": 10,
      "storyLv": 50,
      "power": 1115
     },
     "10154": {
      "HP": 104,
      "ATK": 16,
      "DEF": 12,
      "storyLv": 50,
      "power": 1280
     }
    }
   },
   "lines": {
    "default": [
     {
      "speaker": "내레이션",
      "text": "윤희는 매일 밤 현관문을 3번씩 확인했다."
     },
     {
      "speaker": "최윤희",
      "text": "잠겼어...잠겼어...잠겼어...",
      "expr": "슬픔",
      "slug": "choi_yunhee_home"
     },
     {
      "speaker": "최윤정",
      "text": "윤희야. 너 지금 그거 몇 번째야?",
      "expr": "놀람"
     },
     {
      "speaker": "최윤희",
      "text": "아, 아냐 언니. 그냥 습관이야. 헤헤.",
      "expr": "기쁨",
      "slug": "choi_yunhee_home"
     },
     {
      "speaker": "최윤정",
      "text": "...요즘 밥도 반 공기밖에 안 먹잖아. 무슨 일 있으면 말해.",
      "expr": "보통"
     },
     {
      "speaker": "최윤희",
      "text": "아무 일 없어! 진짜야. 시험 기간이라 그래.",
      "expr": "기쁨",
      "slug": "choi_yunhee_home"
     },
     {
      "speaker": "내레이션",
      "text": "윤희는 웃었다. 언니들이 걱정하는 얼굴을, 더는 보고 싶지 않았다.",
      "image": "img/story/ch9-10.webp"
     },
     {
      "speaker": "최윤정",
      "text": "(...너도 우리처럼 웃는 법을 배웠구나. 그게 제일 싫었는데.)",
      "expr": "슬픔"
     },
     {
      "speaker": "내레이션",
      "text": "새벽 2시. 창밖에서 작은 불빛이 깜빡였다. 담뱃불이었다."
     },
     {
      "speaker": "최윤희",
      "text": "(누가...우리 집을 보고 있어.)",
      "expr": "놀람",
      "slug": "choi_yunhee_home"
     },
     {
      "speaker": "내레이션",
      "text": "윤희는 커튼을 꽉 닫고 이불 속으로 숨었다. 휴대폰 화면이 다시 켜졌다."
     },
     {
      "speaker": "내레이션",
      "text": "[잘 자, 윤희야. 커튼 색이 바뀌었네? 분홍색이 더 잘 어울리는데.]"
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
     "10415": 50
    }
   },
   "hero": [
    "10415"
   ],
   "bossId": "10479",
   "after": [
    {
     "speaker": "최윤희",
     "text": "...제발...그만해...",
     "expr": "슬픔",
     "slug": "choi_yunhee_home"
    }
   ],
   "afterTitle": "전투 후"
  },
  {
   "no": 9,
   "type": "normal",
   "enemyName": "배현오",
   "title": "거울 속의 나",
   "enemies": {
    "ids": [
     "10479",
     "10478",
     "10478",
     "10155",
     "10155"
    ],
    "boost": {
     "10479": {
      "HP": 236,
      "ATK": 50,
      "DEF": 26,
      "storyLv": 51,
      "power": 9234
     },
     "10478": {
      "HP": 222,
      "ATK": 32,
      "DEF": 32,
      "storyLv": 51,
      "power": 8211
     },
     "10155": {
      "HP": 120,
      "ATK": 18,
      "DEF": 14,
      "storyLv": 51,
      "power": 1471
     }
    }
   },
   "lines": {
    "default": [
     {
      "speaker": "내레이션",
      "text": "학교. 윤희는 쉬는 시간에도 자리에서 일어나지 않았다."
     },
     {
      "speaker": "서하늘",
      "text": "윤희야, 매점 같이 갈래?",
      "expr": "보통"
     },
     {
      "speaker": "최윤희",
      "text": "...! 아, 응? 아, 아니야. 난 괜찮아.",
      "expr": "놀람",
      "slug": "choi_yunhee_school"
     },
     {
      "speaker": "서하늘",
      "text": "너 요즘 왜 그래? 누가 말만 걸어도 깜짝깜짝 놀라고.",
      "expr": "놀람"
     },
     {
      "speaker": "최윤희",
      "text": "그, 그랬나? 잠을 좀 못 자서...헤헤.",
      "expr": "기쁨",
      "slug": "choi_yunhee_school"
     },
     {
      "speaker": "진다솜",
      "text": "얼굴 진짜 안 좋다. 보건실 가 봐.",
      "expr": "보통"
     },
     {
      "speaker": "내레이션",
      "text": "화장실 거울. 윤희는 자신의 얼굴을 한참 들여다봤다. 눈 밑이 검게 꺼져 있었다."
     },
     {
      "speaker": "최윤희",
      "text": "(이게 나야? 천사 같다던 최윤희?)",
      "expr": "슬픔",
      "slug": "choi_yunhee_school"
     },
     {
      "speaker": "내레이션",
      "text": "그때, 거울 구석. 화장실 문틈 사이로 누군가의 그림자가 스쳤다."
     },
     {
      "speaker": "최윤희",
      "text": "누구야!!!",
      "expr": "놀람",
      "slug": "choi_yunhee_school"
     },
     {
      "speaker": "내레이션",
      "text": "문을 열었다. 아무도 없었다. 복도 끝, 낯익은 지킴이 배현오의 등이 보인 것 같기도 했다."
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
     "10415": 51
    }
   },
   "hero": [
    "10415"
   ],
   "bossId": "10479",
   "after": [
    {
     "speaker": "최윤희",
     "text": "(내가...미쳐 가는 걸까. 아니면...정말 누가 있는 걸까.)",
     "expr": "슬픔",
     "slug": "choi_yunhee_school"
    }
   ],
   "afterTitle": "전투 후"
  },
  {
   "no": 10,
   "type": "normal",
   "enemyName": "마동철",
   "title": "차가운 말",
   "enemies": {
    "ids": [
     "10480",
     "10481",
     "10479",
     "10154",
     "10154"
    ],
    "boost": {
     "10480": {
      "HP": 486,
      "ATK": 64,
      "DEF": 115,
      "storyLv": 53,
      "power": 27447
     },
     "10481": {
      "HP": 481,
      "ATK": 64,
      "DEF": 64,
      "storyLv": 53,
      "power": 24070
     },
     "10479": {
      "HP": 241,
      "ATK": 51,
      "DEF": 27,
      "storyLv": 53,
      "power": 9447
     },
     "10154": {
      "HP": 106,
      "ATK": 17,
      "DEF": 12,
      "storyLv": 53,
      "power": 1314
     }
    }
   },
   "lines": {
    "default": [
     {
      "speaker": "내레이션",
      "text": "결국 윤희는 경찰서를 찾았다. 비둘기 사진, 문자 캡처를 꼭 쥔 채로."
     },
     {
      "speaker": "최윤희",
      "text": "저...누가 계속 저를 따라와요. 이상한 문자도 오고, 집 앞에...이런 것도...",
      "expr": "보통",
      "slug": "choi_yunhee_casual"
     },
     {
      "speaker": "마동철",
      "text": "흠...비둘기네. 고양이가 물어다 놓은 거 아냐?",
      "expr": "보통"
     },
     {
      "speaker": "최윤희",
      "text": "포장이 돼 있었어요! 카드도 있었고요!",
      "expr": "놀람",
      "slug": "choi_yunhee_casual"
     },
     {
      "speaker": "구태만",
      "text": "문자는 뭐, 협박은 아니네? '잘 어울린다' '잘 자'...이거 칭찬인데?",
      "expr": "보통"
     },
     {
      "speaker": "마동철",
      "text": "그냥 너 좋다고 하는 건데, 뭘 그렇게 예민하게 굴어. 한 번 만나 봐. 혹시 알아?",
      "expr": "기쁨"
     },
     {
      "speaker": "최윤희",
      "text": "...네?",
      "expr": "슬픔",
      "slug": "choi_yunhee_casual"
     },
     {
      "speaker": "구태만",
      "text": "근데 학생, 평소에 네 행실에 문제 있었던 거 아냐? 남자들한테 막 웃어 주고 그러지?",
      "expr": "보통"
     },
     {
      "speaker": "최윤희",
      "text": "그런 적 없어요! 저는 그냥...그냥 평범하게 지냈을 뿐이에요!",
      "expr": "분노",
      "slug": "choi_yunhee_casual"
     },
     {
      "speaker": "마동철",
      "text": "그럼 됐네. 평범하게 지내면 아무 일 없을 거야. 다음.",
      "expr": "보통"
     },
     {
      "speaker": "내레이션",
      "text": "도움을 청했지만, 돌아온 건 차가운 말뿐이었다."
     },
     {
      "speaker": "내레이션",
      "text": "경찰서를 나서는 윤희의 등 뒤로, 키득거리는 웃음소리가 들렸다."
     },
     {
      "speaker": "구태만",
      "text": "저 얼굴이면 따라다닐 만하지 않냐? ㅋㅋ",
      "expr": "기쁨"
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
     "10415": 53
    }
   },
   "hero": [
    "10415"
   ],
   "bossId": "10480",
   "after": [
    {
     "speaker": "최윤희",
     "text": "(...아무도...아무도 내 말을 안 들어 줘.)",
     "expr": "슬픔",
     "slug": "choi_yunhee_casual"
    }
   ],
   "afterTitle": "전투 후"
  },
  {
   "no": 11,
   "type": "normal",
   "enemyName": "구태만",
   "title": "두 번째 신고",
   "enemies": {
    "ids": [
     "10481",
     "10480",
     "10479",
     "10155",
     "10155"
    ],
    "boost": {
     "10481": {
      "HP": 487,
      "ATK": 65,
      "DEF": 65,
      "storyLv": 54,
      "power": 24398
     },
     "10480": {
      "HP": 492,
      "ATK": 65,
      "DEF": 117,
      "storyLv": 54,
      "power": 27839
     },
     "10479": {
      "HP": 243,
      "ATK": 52,
      "DEF": 27,
      "storyLv": 54,
      "power": 9546
     },
     "10155": {
      "HP": 122,
      "ATK": 18,
      "DEF": 14,
      "storyLv": 54,
      "power": 1486
     }
    }
   },
   "lines": {
    "default": [
     {
      "speaker": "내레이션",
      "text": "일주일 뒤. 윤희는 다시 경찰서를 찾았다. 이번엔 윤아가 함께였다."
     },
     {
      "speaker": "최윤아",
      "text": "우리 동생이 3주째 스토킹을 당하고 있다고요. 이번엔 사진도 있어요. 이 남자예요.",
      "expr": "분노",
      "image": "img/story/ch9-11.webp"
     },
     {
      "speaker": "내레이션",
      "text": "윤아가 내민 사진 속엔 금테 안경의 남자가 찍혀 있었다."
     },
     {
      "speaker": "내레이션",
      "text": "사진을 본 P2의 얼굴이 하얗게 질렸다."
     },
     {
      "speaker": "구태만",
      "text": "...이, 이분은...",
      "expr": "놀람"
     },
     {
      "speaker": "마동철",
      "text": "야, 그거 치워. 빨리.",
      "expr": "놀람"
     },
     {
      "speaker": "최윤아",
      "text": "왜요? 아는 사람이에요?",
      "expr": "분노"
     },
     {
      "speaker": "마동철",
      "text": "학생들. 괜히 일 크게 만들지 마. 이분 그냥 좋은 마음에 그러시는 거야. 단순한 호감이라고.",
      "expr": "분노"
     },
     {
      "speaker": "최윤희",
      "text": "...호감이요? 죽은 비둘기가요?",
      "expr": "놀람",
      "slug": "choi_yunhee_casual"
     },
     {
      "speaker": "구태만",
      "text": "증거 불충분이야. 그리고...최윤아 선수? 요즘 높은 데서 연락 오지 않아? 그거나 잘 생각해 봐.",
      "expr": "보통"
     },
     {
      "speaker": "최윤아",
      "text": "...!",
      "expr": "놀람"
     },
     {
      "speaker": "내레이션",
      "text": "윤아의 얼굴에서 핏기가 가셨다. 윤희는 그런 언니의 얼굴을 처음 봤다."
     },
     {
      "speaker": "최윤희",
      "text": "언니...? 저 사람이 무슨 말 하는 거야?",
      "expr": "놀람",
      "slug": "choi_yunhee_casual"
     },
     {
      "speaker": "최윤아",
      "text": "아, 아냐. 그냥...대회 얘기겠지. 가자, 윤희야.",
      "expr": "기쁨"
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
     "10415": 54
    }
   },
   "hero": [
    "10415"
   ],
   "bossId": "10481",
   "after": [
    {
     "speaker": "최윤아",
     "text": "(나 때문이야. 나 때문에...윤희가...)",
     "expr": "슬픔"
    }
   ],
   "afterTitle": "전투 후"
  },
  {
   "no": 12,
   "type": "normal",
   "enemyName": "백시훈",
   "title": "문자",
   "enemies": {
    "ids": [
     "10475",
     "10480",
     "10481",
     "10156",
     "10156"
    ],
    "boost": {
     "10475": {
      "HP": 768,
      "ATK": 141,
      "DEF": 122,
      "storyLv": 56,
      "power": 70152
     },
     "10480": {
      "HP": 504,
      "ATK": 66,
      "DEF": 119,
      "storyLv": 56,
      "power": 28420
     },
     "10481": {
      "HP": 498,
      "ATK": 66,
      "DEF": 66,
      "storyLv": 56,
      "power": 24884
     },
     "10156": {
      "HP": 140,
      "ATK": 20,
      "DEF": 16,
      "storyLv": 56,
      "power": 1798
     }
    }
   },
   "lines": {
    "default": [
     {
      "speaker": "내레이션",
      "text": "그날 밤부터 문자가 달라졌다."
     },
     {
      "speaker": "내레이션",
      "text": "[경찰서는 재밌었어? 그 사람들 내 말 잘 듣지?]"
     },
     {
      "speaker": "내레이션",
      "text": "[너희 언니 테니스 계속 하고 싶겠지? 손목은 소중하니까.]"
     },
     {
      "speaker": "내레이션",
      "text": "[너희 큰언니 회사, 이번에 감사 들어간대. 걱정되지?]"
     },
     {
      "speaker": "최윤희",
      "text": "...언니들까지...",
      "expr": "놀람",
      "slug": "choi_yunhee_home"
     },
     {
      "speaker": "내레이션",
      "text": "[무서워하지 마. 좋아해서 그래. 그냥 호감일 뿐이야.]"
     },
     {
      "speaker": "내레이션",
      "text": "[너만 착하게 굴면, 아무도 안 다쳐.]"
     },
     {
      "speaker": "최윤희",
      "text": "으...흐윽...왜...내가 뭘 했다고...",
      "expr": "슬픔",
      "slug": "choi_yunhee_home"
     },
     {
      "speaker": "내레이션",
      "text": "윤희는 휴대폰을 벽에 던졌다. 화면이 깨졌다. 깨진 화면 위로 새 문자가 또 떴다."
     },
     {
      "speaker": "내레이션",
      "text": "[화내는 얼굴도 예쁘다.]"
     },
     {
      "speaker": "최윤희",
      "text": "(...보고 있어. 지금, 이 순간에도.)",
      "expr": "놀람",
      "slug": "choi_yunhee_home",
      "image": "img/story/ch9-12.webp"
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
     "10415": 56
    }
   },
   "hero": [
    "10415"
   ],
   "bossId": "10475",
   "after": [
    {
     "speaker": "내레이션",
     "text": "윤희는 방의 불을 전부 껐다. 어둠 속에서, 창밖의 그림자가 천천히 손을 흔들었다."
    }
   ],
   "afterTitle": "전투 후"
  },
  {
   "no": 13,
   "type": "normal",
   "enemyName": "서하늘",
   "title": "남겨진 자리",
   "enemies": {
    "ids": [
     "10485",
     "10486",
     "10479",
     "10157",
     "10157"
    ],
    "boost": {
     "10485": {
      "HP": 208,
      "ATK": 45,
      "DEF": 34,
      "storyLv": 57,
      "power": 7265
     },
     "10486": {
      "HP": 235,
      "ATK": 53,
      "DEF": 38,
      "storyLv": 57,
      "power": 10484
     },
     "10479": {
      "HP": 250,
      "ATK": 53,
      "DEF": 28,
      "storyLv": 57,
      "power": 9804
     },
     "10157": {
      "HP": 156,
      "ATK": 22,
      "DEF": 17,
      "storyLv": 57,
      "power": 1985
     }
    }
   },
   "lines": {
    "default": [
     {
      "speaker": "내레이션",
      "text": "학교에 이상한 소문이 돌기 시작했다."
     },
     {
      "speaker": "내레이션",
      "text": "[최윤희가 높은 사람한테 꼬리 쳤다더라] [걔랑 엮이면 집안 망한대]"
     },
     {
      "speaker": "서하늘",
      "text": "...윤희야. 미안. 나 이제 너랑 같이 못 다니겠어.",
      "expr": "슬픔"
     },
     {
      "speaker": "최윤희",
      "text": "...왜? 나 뭐 잘못했어?",
      "expr": "놀람",
      "slug": "choi_yunhee_school"
     },
     {
      "speaker": "서하늘",
      "text": "아니. 근데 우리 아빠 가게에 어제 이상한 사람들이 왔어. 너랑 친하냐고 물어보더라.",
      "expr": "슬픔"
     },
     {
      "speaker": "진다솜",
      "text": "나도...우리 엄마가 너랑 연락하지 말래. 진짜 미안해.",
      "expr": "슬픔"
     },
     {
      "speaker": "최윤희",
      "text": "...아니야. 괜찮아. 나 때문에 너희까지 무서운 일 당하면 안 되지.",
      "expr": "슬픔",
      "slug": "choi_yunhee_school"
     },
     {
      "speaker": "진다솜",
      "text": "윤희야, 진짜 미안해...",
      "expr": "슬픔"
     },
     {
      "speaker": "내레이션",
      "text": "그날 점심, 윤희의 옆자리는 비어 있었다. 아무도 앉지 않았다."
     },
     {
      "speaker": "최윤희",
      "text": "(괜찮아. 괜찮아. 웃자. 언니들 앞에서처럼.)",
      "expr": "슬픔",
      "slug": "choi_yunhee_school"
     },
     {
      "speaker": "최윤희",
      "text": "...헤헤.",
      "expr": "기쁨",
      "slug": "choi_yunhee_school",
      "image": "img/story/ch9-13.webp"
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
     "10415": 57
    }
   },
   "hero": [
    "10415"
   ],
   "bossId": "10485",
   "after": [
    {
     "speaker": "내레이션",
     "text": "웃음은 금방 부서졌다. 윤희는 혼자 남은 교실에서 소리 없이 어깨를 떨었다."
    }
   ],
   "afterTitle": "전투 후"
  },
  {
   "no": 14,
   "type": "normal",
   "enemyName": "마동철",
   "title": "언니들의 침묵",
   "enemies": {
    "ids": [
     "10480",
     "10481",
     "10475",
     "10156",
     "10157"
    ],
    "boost": {
     "10480": {
      "HP": 521,
      "ATK": 68,
      "DEF": 123,
      "storyLv": 59,
      "power": 29360
     },
     "10481": {
      "HP": 515,
      "ATK": 68,
      "DEF": 68,
      "storyLv": 59,
      "power": 25699
     },
     "10475": {
      "HP": 797,
      "ATK": 146,
      "DEF": 126,
      "storyLv": 59,
      "power": 72698
     },
     "10156": {
      "HP": 142,
      "ATK": 21,
      "DEF": 16,
      "storyLv": 59,
      "power": 1834
     },
     "10157": {
      "HP": 158,
      "ATK": 22,
      "DEF": 17,
      "storyLv": 59,
      "power": 2001
     }
    }
   },
   "lines": {
    "default": [
     {
      "speaker": "내레이션",
      "text": "윤정은 회사 사무실에 홀로 남아 있었다. 책상 위엔 '감사 통보서'가 놓여 있었다."
     },
     {
      "speaker": "최윤정",
      "text": "(윤아를 겁주고, 나를 묶고, 윤희를 흔든다. 교과서 같네.)",
      "expr": "보통"
     },
     {
      "speaker": "내레이션",
      "text": "전화가 울렸다. 발신자 표시 없음."
     },
     {
      "speaker": "백시훈",
      "text": "안녕하세요, 최윤정 씨. 동생분이 참 예쁘더군요. 언니를 닮았나?",
      "expr": "기쁨"
     },
     {
      "speaker": "최윤정",
      "text": "...당신 누구야.",
      "expr": "분노"
     },
     {
      "speaker": "백시훈",
      "text": "윤희의 팬이죠. 아주 오래된. 걱정 마세요, 저는 그냥 좋아할 뿐이니까.",
      "expr": "기쁨"
     },
     {
      "speaker": "최윤정",
      "text": "내 동생 건드리면, 당신이 누구든 끝까지 찾아낼 거야.",
      "expr": "분노"
     },
     {
      "speaker": "백시훈",
      "text": "하하. 얼음공주라더니 진짜 차갑네요. 그 말, 둘째 동생한테도 전해 주세요. 대답은 아직 유효하다고.",
      "expr": "기쁨"
     },
     {
      "speaker": "내레이션",
      "text": "통화가 끊겼다. 윤정은 수화기를 쥔 채 한참을 움직이지 못했다."
     },
     {
      "speaker": "최윤정",
      "text": "(아빠...나 이번엔 어떻게 해야 돼...)",
      "expr": "슬픔"
     }
    ]
   },
   "party": {
    "forced": [
     "10414"
    ],
    "exclude": [
     "10415"
    ],
    "mustLive": [
     "10414"
    ],
    "levels": {
     "10414": 59
    }
   },
   "hero": [
    "10414"
   ],
   "bossId": "10480",
   "after": [
    {
     "speaker": "내레이션",
     "text": "윤정은 처음으로, 동생들 몰래 울었다. 그리고 눈물을 닦고 다시 얼음 같은 얼굴로 돌아왔다."
    }
   ],
   "afterTitle": "전투 후"
  },
  {
   "no": 15,
   "type": "normal",
   "enemyName": "독곰",
   "title": "초겨울 골목",
   "enemies": {
    "ids": [
     "10482",
     "10483",
     "10484",
     "10157",
     "10157"
    ],
    "boost": {
     "10482": {
      "HP": 554,
      "ATK": 133,
      "DEF": 111,
      "storyLv": 60,
      "power": 34119
     },
     "10483": {
      "HP": 615,
      "ATK": 125,
      "DEF": 83,
      "storyLv": 60,
      "power": 32803
     },
     "10484": {
      "HP": 665,
      "ATK": 138,
      "DEF": 69,
      "storyLv": 60,
      "power": 37416
     },
     "10157": {
      "HP": 159,
      "ATK": 22,
      "DEF": 17,
      "storyLv": 60,
      "power": 2009
     }
    }
   },
   "lines": {
    "default": [
     {
      "speaker": "내레이션",
      "text": "초겨울. 해가 일찍 졌다. 학원을 마친 윤희는 언니들의 문자를 확인했다."
     },
     {
      "speaker": "내레이션",
      "text": "[윤희야 언니 30분만 늦어. 큰길로만 와!] [윤희야, 집 앞에서 기다릴게. -윤정-]"
     },
     {
      "speaker": "최윤희",
      "text": "(언니들...고마워. 큰길로 가자.)",
      "expr": "기쁨",
      "slug": "choi_yunhee_school"
     },
     {
      "speaker": "내레이션",
      "text": "그런데 큰길은 공사 펜스로 막혀 있었다. 어제까진 없던 펜스였다."
     },
     {
      "speaker": "최윤희",
      "text": "...왜 막혀 있지. 어제까지 아무것도 없었는데.",
      "expr": "놀람",
      "slug": "choi_yunhee_school"
     },
     {
      "speaker": "내레이션",
      "text": "남은 길은 하나. 가로등이 2개뿐인 좁은 골목."
     },
     {
      "speaker": "최윤희",
      "text": "(괜찮아. 5분이면 집이야. 5분만...)",
      "expr": "슬픔",
      "slug": "choi_yunhee_school"
     },
     {
      "speaker": "내레이션",
      "text": "골목 중간쯤. 앞에서 거대한 그림자 셋이 걸어 나왔다."
     },
     {
      "speaker": "독곰",
      "text": "...최윤희?",
      "expr": "보통"
     },
     {
      "speaker": "최윤희",
      "text": "...!",
      "expr": "놀람",
      "slug": "choi_yunhee_school"
     },
     {
      "speaker": "내레이션",
      "text": "뒤를 돌아봤다. 뒤쪽 골목 입구에도 이미 누군가 서 있었다."
     },
     {
      "speaker": "쇳덩이",
      "text": "도망가 봐. 어디로 가는지 궁금하네.",
      "expr": "기쁨"
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
     "10415": 60
    }
   },
   "hero": [
    "10415"
   ],
   "bossId": "10482",
   "after": [
    {
     "speaker": "최윤희",
     "text": "(언니...언니...)",
     "expr": "슬픔",
     "slug": "choi_yunhee_school"
    }
   ],
   "afterTitle": "전투 후"
  },
  {
   "no": 16,
   "type": "normal",
   "enemyName": "쇳덩이",
   "title": "목소리",
   "enemies": {
    "ids": [
     "10483",
     "10482",
     "10484",
     "10475",
     "10157"
    ],
    "boost": {
     "10483": {
      "HP": 628,
      "ATK": 127,
      "DEF": 85,
      "storyLv": 62,
      "power": 33464
     },
     "10482": {
      "HP": 566,
      "ATK": 136,
      "DEF": 113,
      "storyLv": 62,
      "power": 34842
     },
     "10484": {
      "HP": 679,
      "ATK": 142,
      "DEF": 71,
      "storyLv": 62,
      "power": 38327
     },
     "10475": {
      "HP": 826,
      "ATK": 151,
      "DEF": 131,
      "storyLv": 62,
      "power": 75347
     },
     "10157": {
      "HP": 161,
      "ATK": 23,
      "DEF": 18,
      "storyLv": 62,
      "power": 2062
     }
    }
   },
   "lines": {
    "default": [
     {
      "speaker": "내레이션",
      "text": "윤희는 휴대폰을 꺼냈다. 손가락이 언니의 번호 위에서 미끄러졌다."
     },
     {
      "speaker": "바위",
      "text": "어디다 전화를 해.",
      "expr": "분노"
     },
     {
      "speaker": "내레이션",
      "text": "커다란 손이 휴대폰을 낚아챘다. 휴대폰이 바닥에 굴렀다."
     },
     {
      "speaker": "최윤희",
      "text": "놔요! 놓으라고요!! 살려 주세요!!!",
      "expr": "분노",
      "slug": "choi_yunhee_school"
     },
     {
      "speaker": "내레이션",
      "text": "또 다른 손이 윤희의 입을 틀어막았다. 숨이 막혔다.",
      "image": "img/story/ch9-14.webp"
     },
     {
      "speaker": "최윤희",
      "text": "으읍...! 으...읍...!",
      "expr": "다침",
      "slug": "choi_yunhee_school"
     },
     {
      "speaker": "독곰",
      "text": "조용히 해. 다치기 싫으면.",
      "expr": "보통"
     },
     {
      "speaker": "내레이션",
      "text": "윤희는 발버둥 쳤다. 하지만 거인들의 손은 바위처럼 꿈쩍도 하지 않았다."
     },
     {
      "speaker": "내레이션",
      "text": "시야가 흐려졌다. 다리에 힘이 풀렸다. 윤희는 차가운 바닥 위로 무너졌다."
     },
     {
      "speaker": "최윤희",
      "text": "(언니...나...그냥 웃으면서 살고 싶었을 뿐인데...)",
      "expr": "다침",
      "slug": "choi_yunhee_school"
     },
     {
      "speaker": "내레이션",
      "text": "그때, 아주 멀리서...익숙한 목소리가 들렸다."
     },
     {
      "speaker": "최윤아",
      "text": "윤희야!!! 최윤희!!! 어디 있어!!!!",
      "expr": "놀람"
     },
     {
      "speaker": "최윤정",
      "text": "윤희야!!! 대답해!!!",
      "expr": "놀람"
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
     "10415": 62
    }
   },
   "hero": [
    "10415"
   ],
   "bossId": "10483",
   "after": [
    {
     "speaker": "내레이션",
     "text": "언니들의 목소리가 골목에 울렸다. 하지만 아직은, 너무 멀었다."
    }
   ],
   "afterTitle": "전투 후"
  },
  {
   "no": 17,
   "type": "normal",
   "enemyName": "백시훈",
   "title": "사랑한다",
   "enemies": {
    "ids": [
     "10475",
     "10482",
     "10483",
     "10484",
     "10157"
    ],
    "boost": {
     "10475": {
      "HP": 835,
      "ATK": 153,
      "DEF": 132,
      "storyLv": 63,
      "power": 76168
     },
     "10482": {
      "HP": 572,
      "ATK": 137,
      "DEF": 114,
      "storyLv": 63,
      "power": 35166
     },
     "10483": {
      "HP": 635,
      "ATK": 129,
      "DEF": 86,
      "storyLv": 63,
      "power": 33883
     },
     "10484": {
      "HP": 686,
      "ATK": 143,
      "DEF": 72,
      "storyLv": 63,
      "power": 38703
     },
     "10157": {
      "HP": 162,
      "ATK": 23,
      "DEF": 18,
      "storyLv": 63,
      "power": 2070
     }
    }
   },
   "lines": {
    "default": [
     {
      "speaker": "내레이션",
      "text": "흐릿한 시야 속, 반짝이는 구두 한 켤레가 윤희 앞에 멈췄다."
     },
     {
      "speaker": "내레이션",
      "text": "금테 안경. 온화한 미소. 늘 거리 건너편에 서 있던 그 남자였다."
     },
     {
      "speaker": "백시훈",
      "text": "많이 놀랐지? 미안해. 이렇게 가까이서 보는 건 처음이네.",
      "expr": "기쁨"
     },
     {
      "speaker": "최윤희",
      "text": "...당신...누구...야...",
      "expr": "다침",
      "slug": "choi_yunhee_school"
     },
     {
      "speaker": "백시훈",
      "text": "글쎄. 네 그림자? 네가 웃을 때마다 뒤에서 지켜보던 사람.",
      "expr": "기쁨"
     },
     {
      "speaker": "최윤희",
      "text": "...왜...나한테...이래...",
      "expr": "분노",
      "slug": "choi_yunhee_school"
     },
     {
      "speaker": "백시훈",
      "text": "왜냐니. 좋아하니까. 그리고...너희 언니가 너무 고집이 세거든.",
      "expr": "보통"
     },
     {
      "speaker": "내레이션",
      "text": "남자가 몸을 숙였다. 얼음처럼 차가운 숨결이 귓가에 닿았다."
     },
     {
      "speaker": "백시훈",
      "text": "앞으로 정말 재밌어질 거야.",
      "expr": "기쁨"
     },
     {
      "speaker": "백시훈",
      "text": "사랑한다, 윤희야.",
      "expr": "기쁨"
     },
     {
      "speaker": "내레이션",
      "text": "발소리가 멀어졌다. 거인들도, 남자도, 어둠 속으로 녹아 사라졌다."
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
    }
   },
   "hero": [
    "10415"
   ],
   "bossId": "10475",
   "after": [
    {
     "speaker": "내레이션",
     "text": "남은 건 차가운 바닥과, 점점 가까워지는 언니들의 목소리뿐이었다."
    }
   ],
   "afterTitle": "전투 후"
  },
  {
   "no": 18,
   "type": "boss",
   "enemyName": "백시훈",
   "title": "기도",
   "enemies": {
    "ids": [
     "10475",
     "10482",
     "10483",
     "10484",
     "10480"
    ],
    "boost": {
     "10475": {
      "HP": 854,
      "ATK": 157,
      "DEF": 135,
      "storyLv": 65,
      "power": 77966
     },
     "10482": {
      "HP": 584,
      "ATK": 140,
      "DEF": 117,
      "storyLv": 65,
      "power": 35951
     },
     "10483": {
      "HP": 648,
      "ATK": 131,
      "DEF": 88,
      "storyLv": 65,
      "power": 34545
     },
     "10484": {
      "HP": 701,
      "ATK": 146,
      "DEF": 73,
      "storyLv": 65,
      "power": 39501
     },
     "10480": {
      "HP": 555,
      "ATK": 73,
      "DEF": 131,
      "storyLv": 65,
      "power": 31317
     }
    }
   },
   "lines": {
    "default": [
     {
      "speaker": "최윤아",
      "text": "윤희야!!! 윤희야, 눈 떠 봐! 언니야!!",
      "expr": "놀람"
     },
     {
      "speaker": "최윤정",
      "text": "윤희야...괜찮아. 언니들 왔어. 이제 괜찮아...",
      "expr": "슬픔"
     },
     {
      "speaker": "최윤희",
      "text": "언니...언니...",
      "expr": "다침",
      "slug": "choi_yunhee_home"
     },
     {
      "speaker": "내레이션",
      "text": "윤아는 윤희를 끌어안고 울었다. 윤정은 떨리는 손으로 윤희의 얼굴을 감쌌다.",
      "image": "img/story/ch9-15.webp"
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
      "speaker": "최윤희",
      "text": "...언니 때문이라니...무슨 말이야...?",
      "expr": "놀람",
      "slug": "choi_yunhee_home"
     },
     {
      "speaker": "내레이션",
      "text": "두 언니는 대답하지 않았다. 그 침묵이 윤희에겐 대답보다 무서웠다."
     },
     {
      "speaker": "내레이션",
      "text": "그날 밤. 윤희는 불을 켠 채 이불 속에서 두 손을 모았다."
     },
     {
      "speaker": "최윤희",
      "text": "하느님...저는 그냥, 평범하게 웃으면서 살고 싶었을 뿐이에요.",
      "expr": "슬픔",
      "slug": "choi_yunhee_home"
     },
     {
      "speaker": "최윤희",
      "text": "도움을 청해도...돌아오는 건 차가운 말뿐이었어요.",
      "expr": "슬픔",
      "slug": "choi_yunhee_home"
     },
     {
      "speaker": "최윤희",
      "text": "좋아해서 그래.' '그냥 호감일 뿐이야.'...그 말이, 이제 제일 무서워요.",
      "expr": "슬픔",
      "slug": "choi_yunhee_home"
     },
     {
      "speaker": "내레이션",
      "text": "창밖. 가로등 아래 그림자 하나가 서 있다가, 천천히 사라졌다."
     },
     {
      "speaker": "최윤희",
      "text": "(제발...우리 언니들만은...)",
      "expr": "슬픔",
      "slug": "choi_yunhee_home"
     },
     {
      "speaker": "내레이션",
      "text": "눈물로 젖은 윤희의 눈동자 깊은 곳에서, 아주 작은 불씨가 깜빡였다."
     },
     {
      "speaker": "최윤희",
      "text": "...다음엔...나도 가만히 있지 않을 거야.",
      "expr": "분노",
      "slug": "choi_yunhee_home",
      "image": "img/story/ch9-16.webp"
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
    }
   },
   "hero": [
    "10415"
   ],
   "bossId": "10475",
   "after": [
    {
     "speaker": "내레이션",
     "text": "..."
    },
    {
     "speaker": "내레이션",
     "text": "...!!!"
    },
    {
     "speaker": "내레이션",
     "text": "Chapter 9. fin"
    }
   ],
   "afterTitle": "전투 후",
   "final": true
  }
 ],
 "tagline": "",
 "warning": "이 챕터에는 괴롭힘·폭력·죽음 묘사가 포함되어 있습니다.",
 "start": [
  {
   "speaker": "내레이션",
   "text": "최윤희. 천사 같은 얼굴, 누구에게나 다정한 마음, 그리고 누구보다 성실한 소녀."
  },
  {
   "speaker": "내레이션",
   "text": "하지만 그녀의 뒤에는 언제나 그림자가 따라다녔다."
  },
  {
   "speaker": "최윤희",
   "text": "저는...그냥 평범하게 웃으면서 살고 싶었을 뿐이에요.",
   "expr": "보통",
   "slug": "choi_yunhee_school",
   "video": "video/story/ch9-01.mp4"
  },
  {
   "speaker": "내레이션",
   "text": "계엄 정부가 들어선 지 몇 년. B급 안전지대의 낡은 2층 주택에 세 자매가 산다."
  },
  {
   "speaker": "내레이션",
   "text": "첫째 최윤정. '얼음공주'라 불리는, 차갑고 비상한 머리의 맏언니.",
   "image": "img/story/ch9-02.webp"
  },
  {
   "speaker": "내레이션",
   "text": "둘째 최윤아. 코트 위의 천재. 라켓 하나로 모든 시선을 빼앗는 테니스 선수.",
   "image": "img/story/ch9-03.webp"
  },
  {
   "speaker": "내레이션",
   "text": "그리고 막내 최윤희.",
   "image": "img/story/ch9-04.webp"
  },
  {
   "speaker": "내레이션",
   "text": "교수였던 아버지는 [국가보안법] 위반으로 끌려가, 끝내 돌아오지 못했다."
  },
  {
   "speaker": "내레이션",
   "text": "유명 배우였던 어머니는 가난 속에서 버티다, 어느 비 오는 밤 차 사고로 세상을 떠났다."
  },
  {
   "speaker": "내레이션",
   "text": "재산이 몰수되기 직전, 윤정은 헐값에 모든 것을 정리하고 동생들을 데리고 이곳으로 왔다."
  },
  {
   "speaker": "최윤정",
   "text": "울지 마, 윤희야. 이제부터 우리 셋이면 충분해.",
   "expr": "보통"
  },
  {
   "speaker": "내레이션",
   "text": "그날 이후, 윤희는 한 번도 언니들 앞에서 울지 않았다."
  }
 ],
 "ending": [],
 "endingVideo": "SZOOuvc5nak"
});
