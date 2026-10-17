// ===== 스토리 모드 데이터 (대사·챕터 구성) =====
// 대사는 여기만 고치면 됩니다. speaker: 화자 이름, portrait: 'starter'(고른 캐릭터) | 'enemy'(이번 페이즈 첫 적) | 카드 id | null(나레이션)
// lines.default 는 공통 대사, lines[카드id] 가 있으면 그 캐릭터를 골랐을 때 그 대사를 씁니다.
window.STORY_DATA = {
  // 오프닝: 메인 스토리 첫 진입 시 1번 재생. video 경로를 넣으면 영상, 비어 있으면 자리표시 화면
  opening: { video: 'video/opening.mp4', poster: 'img/story/opening_poster.webp', title: 'OPENING', text: '' },
  starters: [
    { id: '2000600126', name: '문지예', tagline: '(소개 문구 준비 중)' },
    { id: '2000200044', name: '용지혜', tagline: '(소개 문구 준비 중)' },
    { id: '2001500294', name: '안리', tagline: '(소개 문구 준비 중)' },
  ],
  // 밸런스: 승리 시 스탯 포인트, 포인트 1당 상승량
  statPoints: { normal: 3, boss: 5 },
  statPerPoint: { ATK: 2, HP: 10, DEF: 2 },
  // 스토리 전투: 출전 카드 최대 장수 (전부 필드에서 시작, 손패·드로우 없음)
  battleCards: 5,
  // 보스전 상대 진영 HP: 챕터 순서대로 (챕터 1 = 500, 이후 챕터 1의 +50%씩). 표보다 뒤 챕터는 마지막 값 + 250씩.
  // 페이즈에 baseHp 를 직접 적으면 그 값이 우선. 보스 카드는 페이즈의 bossId → enemyName 과 같은 이름의 카드 → (ids 지정 시) 첫 카드 → 가장 강한 카드 순으로 정함
  bossBaseHp: [500, 750, 1000, 1250, 1500],
  chapters: [
    {
      id: 1, title: 'CHAPTER 1', subtitle: '(챕터 제목 준비 중)',
      rewardCard: 'NORMAL',   // 페이즈 첫 클리어 시 무료 카드 등급. 없으면(챕터 2~) 스탯 포인트만
      phases: [
        // enemyName: 전투 화면 상대 이름 / enemies: 노멀 카드 power 순위 구간 [from, to) 에서 count 장 / 또는 ids: ['카드id', ...] 로 직접 지정
        { no: 1, type: 'normal', enemyName: '적군', title: '(페이즈 1 제목)', tip: '출전 카드가 모두 필드에서 시작해요. 내 카드를 누르고 상대 카드를 눌러 공격해 보세요.', enemies: { count: 1, rank: [0, 30] },
          lines: { default: [
            { speaker: null, portrait: null, text: '(나레이션 대사 자리)' },
            { speaker: 'starter', portrait: 'starter', text: '(주인공 대사 자리)' },
            { speaker: 'enemy', portrait: 'enemy', text: '(적 대사 자리)' },
          ] } },
        { no: 2, type: 'normal', enemyName: '적군', title: '(페이즈 2 제목)', tip: 'MP가 차면 스킬을 쓸 수 있어요. 카드를 눌러 확인해 보세요.', enemies: { count: 2, rank: [0, 50] },
          lines: { default: [ { speaker: 'starter', portrait: 'starter', text: '(대사 자리)' }, { speaker: 'enemy', portrait: 'enemy', text: '(대사 자리)' } ] } },
        { no: 3, type: 'normal', enemyName: '적군', title: '(페이즈 3 제목)', tip: '상대 카드를 쓰러뜨리면 상대 MP 일부를 흡수해요.', enemies: { count: 2, rank: [30, 90] },
          lines: { default: [ { speaker: 'starter', portrait: 'starter', text: '(대사 자리)' }, { speaker: 'enemy', portrait: 'enemy', text: '(대사 자리)' } ] } },
        { no: 4, type: 'normal', enemyName: '적군', title: '(페이즈 4 제목)', tip: '속성 상성을 이용하면 더 큰 피해를 줄 수 있어요.', enemies: { count: 3, rank: [50, 120] },
          lines: { default: [ { speaker: 'starter', portrait: 'starter', text: '(대사 자리)' }, { speaker: 'enemy', portrait: 'enemy', text: '(대사 자리)' } ] } },
        { no: 5, type: 'boss', enemyName: '보스', title: '(보스전 제목)', tip: '보스전! 👑 보스는 진영 안에 있어 쓰러지지 않아요. 다른 카드를 피하거나 쓰러뜨리고 상대 진영 HP를 0으로 만드세요.', enemies: { count: 4, rank: [120, 203] },
          lines: { default: [ { speaker: 'enemy', portrait: 'enemy', text: '(보스 대사 자리)' }, { speaker: 'starter', portrait: 'starter', text: '(대사 자리)' } ] } },
      ],
    },
  ],
};

// ===== 문지예 전용 챕터 1 「브레이크」 (원문: 사용자 확정 대본, 수정 금지) =====
// 고른 캐릭터가 문지예일 때만 위 기본값을 덮어씁니다. 화자 이름과 같은 카드가 있으면 그 카드가 초상화로 나옵니다.
window.STORY_DATA.chapters[0].byStarter = { '2000600126': {
  "subtitle": "브레이크",
  "phases": {
    "1": {
      "title": "빗속의 첫 주먹",
      "enemyName": "강지민",
      "enemies": {
        "ids": [
          "2000600118"
        ]
      },
      "lines": [
        {
          "speaker": "내레이션",
          "text": "귀갓길. 누군가 지예를 따라온다."
        },
        {
          "speaker": "강지민",
          "text": "야, 아까 그 남자한테 뭐 받았지?"
        },
        {
          "speaker": "문지예",
          "text": "…무슨 말인지 모르겠는데요."
        },
        {
          "speaker": "강지민",
          "text": "주머니 털어. 좋게 말할 때."
        },
        {
          "speaker": "문지예",
          "text": "(오빠는 없어. 이번엔 나 혼자야.)"
        },
        {
          "speaker": "문지예",
          "text": "미안해요. 이건 못 줘요."
        }
      ]
    },
    "2": {
      "title": "냄새나는 정보",
      "enemyName": "유진아",
      "enemies": {
        "ids": [
          "2000600136",
          "2000600118"
        ]
      },
      "lines": [
        {
          "speaker": "유진아",
          "text": "계집애 하나 못 잡고 뭐 했어?"
        },
        {
          "speaker": "강지민",
          "text": "걔 여왕벌 쪽이야. 조심해."
        },
        {
          "speaker": "문지예",
          "text": "누가 시켰어요? 이 USB 찾으라고."
        },
        {
          "speaker": "유진아",
          "text": "알아서 뭐 하게? 너도 곧 끝인데."
        },
        {
          "speaker": "문지예",
          "text": "그럼 쓰러뜨리고 물어볼게요.", "expr": "화남"
        },
        {
          "speaker": "유진아",
          "text": "…하, 웃기는 년이네. 덤벼!"
        }
      ]
    },
    "3": {
      "title": "쓰레기 산의 거래",
      "enemyName": "정아영",
      "enemies": {
        "ids": [
          "2000600129",
          "2000600136"
        ]
      },
      "lines": [
        {
          "speaker": "유진아",
          "text": "크윽… 정아영한테 가 봐. 걔가 알아."
        },
        {
          "speaker": "내레이션",
          "text": "안전지대에서 흘러온 오물이 쌓인 산."
        },
        {
          "speaker": "문지예",
          "text": "USB 안을 볼 수 있다고 들었어요."
        },
        {
          "speaker": "정아영",
          "text": "보여주면 반은 내 거야. 어때?"
        },
        {
          "speaker": "문지예",
          "text": "거절할게요. 대신 이길게요.", "expr": "웃음"
        },
        {
          "speaker": "정아영",
          "text": "말 한번 시원하네. 좋아, 붙자!"
        }
      ]
    },
    "4": {
      "title": "잠긴 파일",
      "enemyName": "정아영",
      "enemies": {
        "ids": [
          "2000600129",
          "2000600136",
          "2000600118"
        ]
      },
      "lines": [
        {
          "speaker": "정아영",
          "text": "…졌다. 약속대로 열어줄게."
        },
        {
          "speaker": "정아영",
          "text": "사진, 영상, 서류. 이거 진짜야?"
        },
        {
          "speaker": "문지예",
          "text": "비리 장부… 위에 누가 있어요."
        },
        {
          "speaker": "정아영",
          "text": "(이거면 한몫 크게 잡겠는데?)"
        },
        {
          "speaker": "정아영",
          "text": "얘들아, 나와! USB 뺏어!"
        },
        {
          "speaker": "문지예",
          "text": "약속했잖아요!", "expr": "화남"
        },
        {
          "speaker": "정아영",
          "text": "배척지에서 약속 믿는 바보가 어딨어?"
        }
      ]
    },
    "5": {
      "title": "하이에나 굴",
      "enemyName": "곽재준",
      "bossId": "1000300076",
      "enemies": {
        "ids": [
          "1000300076",
          "2000600129",
          "2000600136",
          "2000600118"
        ]
      },
      "lines": [
        {
          "speaker": "정아영",
          "text": "크윽… 곽재준 오빠한테 이를 거야!"
        },
        {
          "speaker": "내레이션",
          "text": "구로 배척지의 무력집단, 하이에나."
        },
        {
          "speaker": "곽재준",
          "text": "여왕벌 막내가 우리 집엔 웬일이야?", "expr": "웃음"
        },
        {
          "speaker": "문지예",
          "text": "USB를 찾으라고 시킨 사람, 누구죠?"
        },
        {
          "speaker": "곽재준",
          "text": "알면 너도 그 남자처럼 될 텐데?", "expr": "웃음"
        },
        {
          "speaker": "문지예",
          "text": "그래도 알아야겠어요.", "expr": "화남"
        },
        {
          "speaker": "곽재준",
          "text": "좋아. 무너뜨려 보든가!", "expr": "화남"
        }
      ],
      "leader": "1000300076"
    }
  },
  "intro": "구로 배척지 '여왕벌클럽'의 2인자.\n잔인한 언니와 오빠를 멈춰 세우는 단 하나의 브레이크.\n싸움은 약하지만, 사람의 마음을 읽는 데엔 누구보다 빠르다.",
  "start": [
    {
      "speaker": "내레이션",
      "text": "늦여름, 장마가 끝나지 않은 구로 배척지."
    },
    {
      "speaker": "내레이션",
      "text": "그날도 오빠는 멈추지 않았다."
    },
    {
      "speaker": "문지예",
      "text": "오빠, 그만해요! 사람 죽어요!", "expr": "화남"
    },
    {
      "speaker": "문지철",
      "text": "…우리 지예. 고마워요."
    },
    {
      "speaker": "내레이션",
      "text": "쓰러진 남자가 떨리는 손을 내밀었다."
    },
    {
      "speaker": "쓰러진 남자",
      "text": "119는 됐어. 이거나 가져가."
    },
    {
      "speaker": "쓰러진 남자",
      "text": "어차피… 이게 문제야."
    },
    {
      "speaker": "내레이션",
      "text": "손바닥 위에 남은 건, 작은 USB 하나."
    },
    {
      "speaker": "문지예",
      "text": "(이게 대체 뭐길래….)"
    }
  ],
  "ending": [
    {
      "speaker": "곽재준",
      "text": "…강남. 압구정에서 내려온 일이야."
    },
    {
      "speaker": "곽재준",
      "text": "우린 심부름꾼일 뿐이라고."
    },
    {
      "speaker": "문지예",
      "text": "이름은요?"
    },
    {
      "speaker": "곽재준",
      "text": "임… 유리. 열일곱 살짜리 꼬마래."
    },
    {
      "speaker": "문지예",
      "text": "(나보다 어린데… 얘가?)"
    },
    {
      "speaker": "내레이션",
      "text": "그리고 그 이름이, 지예의 다음 목적지가 되었다."
    }
  ]
} };
window.STORY_DATA.noPortrait = ['내레이션', '쓰러진 남자', '???'];

// ===== 안리 전용 챕터 1 「귀갓길 카운터」 (원문: 사용자 확정 대본, 수정 금지) =====
window.STORY_DATA.chapters[0].byStarter['2001500294'] = {
  "subtitle": "귀갓길 카운터",
  "phases": {
    "1": {
      "title": "눈 마주친 죄",
      "enemyName": "국태원",
      "enemies": {
        "ids": [
          "1001500301"
        ]
      },
      "lines": [
        {
          "speaker": "국태원",
          "text": "어이, 아가씨들. 어디 가?"
        },
        {
          "speaker": "국태원",
          "text": "운동했어? 나랑도 좀 해 볼래?"
        },
        {
          "speaker": "홍가영",
          "text": "안리야, 무시하고 가자."
        },
        {
          "speaker": "안리",
          "text": "비켜 줄래요? 집에 가는 길이라."
        },
        {
          "speaker": "국태원",
          "text": "싫은데? 어쩔 건데?"
        },
        {
          "speaker": "안리",
          "text": "…가영아, 가방 좀 들어줘."
        }
      ]
    },
    "2": {
      "title": "몰려든 하이에나",
      "enemyName": "추나리",
      "enemies": {
        "ids": [
          "2001500284",
          "1001500288"
        ]
      },
      "lines": [
        {
          "speaker": "추나리",
          "text": "태원이 저거 여자애한테 맞았냐?"
        },
        {
          "speaker": "사진태",
          "text": "쪽팔리게. 우리가 손봐 주자."
        },
        {
          "speaker": "홍가영",
          "text": "안리야, 점점 많아지는데?"
        },
        {
          "speaker": "안리",
          "text": "괜찮아. 다 한 방이면 돼.", "expr": "웃음"
        },
        {
          "speaker": "추나리",
          "text": "말이 세네? 그 입 다물게 해 줄게."
        }
      ]
    },
    "3": {
      "title": "골목의 덩치들",
      "enemyName": "박태욱",
      "enemies": {
        "ids": [
          "1001500289",
          "1001500300"
        ]
      },
      "lines": [
        {
          "speaker": "박태욱",
          "text": "우리 애들 건드린 게 너냐?"
        },
        {
          "speaker": "장승헌",
          "text": "조그만 게 손이 맵다며?"
        },
        {
          "speaker": "안리",
          "text": "먼저 건드린 건 그쪽이에요.", "expr": "화남"
        },
        {
          "speaker": "홍가영",
          "text": "나도 같이 할게! 은메달도 메달이야!", "expr": "웃음"
        },
        {
          "speaker": "안리",
          "text": "넌 뒤에 있어. 다치면 안 돼."
        },
        {
          "speaker": "박태욱",
          "text": "둘 다 오늘 집에 못 간다."
        }
      ]
    },
    "4": {
      "title": "끝없는 시비",
      "enemyName": "국태원",
      "enemies": {
        "ids": [
          "1001500301",
          "1001500288",
          "1001500289"
        ]
      },
      "lines": [
        {
          "speaker": "국태원",
          "text": "형님들 데려왔다! 이제 끝이야!"
        },
        {
          "speaker": "사진태",
          "text": "아까 건 운이야. 이번엔 다르다."
        },
        {
          "speaker": "안리",
          "text": "하… 진짜 끈질기네.", "expr": "화남"
        },
        {
          "speaker": "홍가영",
          "text": "이 동네 원래 이렇게 험했나?"
        },
        {
          "speaker": "안리",
          "text": "아니. 누가 뒤에서 부추기는 거야."
        },
        {
          "speaker": "안리",
          "text": "덤벼. 한 번에 정리해 줄게.", "expr": "화남"
        }
      ]
    },
    "5": {
      "title": "골목의 왕",
      "enemyName": "송철순",
      "enemies": {
        "ids": [
          "1001500287",
          "2001500284",
          "1001500300",
          "1001500288"
        ]
      },
      "lines": [
        {
          "speaker": "송철순",
          "text": "우리 구역에서 날뛰는 꼬맹이가 너냐?", "expr": "웃음"
        },
        {
          "speaker": "안리",
          "text": "그쪽이 대장이에요? 애들 좀 말려요.", "expr": "화남"
        },
        {
          "speaker": "송철순",
          "text": "내 애들을 팼으면 값을 치러야지.", "expr": "화남"
        },
        {
          "speaker": "홍가영",
          "text": "안리야, 저 사람은 진짜 위험해 보여."
        },
        {
          "speaker": "안리",
          "text": "걱정 마. 금메달은 그냥 딴 게 아니야.", "expr": "웃음"
        },
        {
          "speaker": "송철순",
          "text": "건방진 년. 오늘 버릇 고쳐 주마!", "expr": "화남"
        }
      ],
      "leader": "1001500287"
    }
  },
  "intro": "성동의 복싱 소녀, 전국체전 금메달리스트.\n유치원 때부터 함께한 단짝 가영과 매일 링에 오른다.\n짧고 묵직한 한 방. 시비는 사양하지만, 피하지도 않는다.",
  "start": [
    {
      "speaker": "내레이션",
      "text": "성동 배척지, 낡은 복싱 체육관."
    },
    {
      "speaker": "홍가영",
      "text": "안리야, 오늘 스파링 너무 빡셌어!", "expr": "웃음"
    },
    {
      "speaker": "안리",
      "text": "엄살은. 너 은메달리스트잖아.", "expr": "웃음"
    },
    {
      "speaker": "홍가영",
      "text": "금메달한테 듣고 싶지 않거든?", "expr": "화남"
    },
    {
      "speaker": "내레이션",
      "text": "해가 지는 귀갓길. 골목이 수상하다."
    },
    {
      "speaker": "안리",
      "text": "…오늘따라 이상한 놈들이 많네."
    },
    {
      "speaker": "홍가영",
      "text": "그냥 빨리 가자. 눈 마주치지 마."
    }
  ],
  "ending": [
    {
      "speaker": "송철순",
      "text": "크윽… 이, 이런 꼬맹이한테….", "expr": "화남"
    },
    {
      "speaker": "내레이션",
      "text": "송철순이 비틀거리며 골목 끝으로 달아난다."
    },
    {
      "speaker": "송철순",
      "text": "너… 후회할 거야.", "expr": "화남"
    },
    {
      "speaker": "홍가영",
      "text": "안리야… 괜찮은 거지?"
    },
    {
      "speaker": "안리",
      "text": "응. 근데 저 말, 왠지 신경 쓰이네."
    },
    {
      "speaker": "내레이션",
      "text": "그날 밤, 골목의 그림자는 더 짙어졌다."
    }
  ]
};

// ===== 용지혜 전용 챕터 1 「동생의 이름으로」 (원문: 사용자 확정 대본, 수정 금지) =====
window.STORY_DATA.chapters[0].byStarter['2000200044'] = {
  "subtitle": "동생의 이름으로",
  "phases": {
    "1": {
      "title": "골목 입구",
      "enemyName": "김준하",
      "enemies": {
        "ids": [
          "1000200032"
        ]
      },
      "lines": [
        {
          "speaker": "김준하",
          "text": "어? 진짜 왔네. 겁도 없이."
        },
        {
          "speaker": "용지혜",
          "text": "지효 어디 있어요?"
        },
        {
          "speaker": "김준하",
          "text": "알려 줄 것 같아? 꺼져."
        },
        {
          "speaker": "용지혜",
          "text": "(무서워… 그래도 물러설 수 없어.)"
        },
        {
          "speaker": "용지혜",
          "text": "비켜요. 안 비키면… 넘길 거예요.", "expr": "화남"
        }
      ]
    },
    "2": {
      "title": "빚쟁이들",
      "enemyName": "황예영",
      "enemies": {
        "ids": [
          "2000200051",
          "2000200029"
        ]
      },
      "lines": [
        {
          "speaker": "황예영",
          "text": "걔 동생이 우리한테 빚졌거든."
        },
        {
          "speaker": "서하윤",
          "text": "갚을 때까지 못 보내. 알지?"
        },
        {
          "speaker": "용지혜",
          "text": "지효가 빚을 질 애가 아니에요."
        },
        {
          "speaker": "황예영",
          "text": "그건 위에서 알아서 하는 거고~"
        },
        {
          "speaker": "용지혜",
          "text": "위? 그게 누군데요?"
        },
        {
          "speaker": "서하윤",
          "text": "이겨 보든가. 그럼 말해 줄게."
        }
      ]
    },
    "3": {
      "title": "낡은 창고",
      "enemyName": "채훈기",
      "enemies": {
        "ids": [
          "1000200047",
          "1000200032"
        ]
      },
      "lines": [
        {
          "speaker": "서하윤",
          "text": "크윽… 창고. 창고로 데려갔어."
        },
        {
          "speaker": "내레이션",
          "text": "버려진 창고 앞, 불빛이 새어 나온다."
        },
        {
          "speaker": "채훈기",
          "text": "여기까지 왔어? 끈질기네."
        },
        {
          "speaker": "김준하",
          "text": "아까 그년이야! 조심해!"
        },
        {
          "speaker": "용지혜",
          "text": "이번엔 안 봐줘요. 돌격!", "expr": "화남"
        }
      ]
    },
    "4": {
      "title": "텅 빈 의자",
      "enemyName": "선인구",
      "enemies": {
        "ids": [
          "1000200050",
          "1000200047",
          "2000200051"
        ]
      },
      "lines": [
        {
          "speaker": "내레이션",
          "text": "창고 안, 의자에 묶인 끈만 남아 있다."
        },
        {
          "speaker": "용지혜",
          "text": "지효는…? 지효 어디 갔어!", "expr": "화남"
        },
        {
          "speaker": "선인구",
          "text": "한발 늦었네. 대장한테 넘겼어."
        },
        {
          "speaker": "황예영",
          "text": "문희찬 오빠가 직접 데려갔지~"
        },
        {
          "speaker": "용지혜",
          "text": "…그 사람, 어디 있어요.", "expr": "화남"
        },
        {
          "speaker": "선인구",
          "text": "우리 셋을 넘으면 알려 주지."
        }
      ]
    },
    "5": {
      "title": "문희찬의 굴",
      "enemyName": "문희찬",
      "enemies": {
        "ids": [
          "1000200046",
          "1000200050",
          "2000200029",
          "1000200032"
        ]
      },
      "lines": [
        {
          "speaker": "용지효",
          "text": "언니!! 오지 말라니까!"
        },
        {
          "speaker": "용지혜",
          "text": "지효야! 괜찮아? 다친 데는?"
        },
        {
          "speaker": "문희찬",
          "text": "감동의 재회네. 근데 공짜는 없어.", "expr": "웃음"
        },
        {
          "speaker": "문희찬",
          "text": "네 동생은 남고은 누님 물건이야.", "expr": "웃음"
        },
        {
          "speaker": "용지혜",
          "text": "남고은…? 분홍 여우?"
        },
        {
          "speaker": "문희찬",
          "text": "알면 됐고. 동생 두고 꺼져.", "expr": "화남"
        },
        {
          "speaker": "용지혜",
          "text": "싫어요. 지효는 제가 데려가요.", "expr": "화남"
        }
      ],
      "leader": "1000200046"
    }
  },
  "intro": "강북의 주짓수 소녀. 시 대회 수상, 특기생 진학을 꿈꾼다.\n소심한 성격을 이기려고 매트 위에서 버텨 온 노력파.\n하나뿐인 동생 지효를 위해서라면, 두려움도 꺾는다.",
  "start": [
    {
      "speaker": "내레이션",
      "text": "강북 배척지, 늦은 밤의 도장."
    },
    {
      "speaker": "용지혜",
      "text": "(오늘도 지효는 연락이 없네….)"
    },
    {
      "speaker": "내레이션",
      "text": "휴대폰이 울린다. 지효의 번호다."
    },
    {
      "speaker": "용지효",
      "text": "언니… 미안해. 나 잡혀 왔어."
    },
    {
      "speaker": "???",
      "text": "동생 데려가고 싶으면 와 봐. ㅋㅋ"
    },
    {
      "speaker": "내레이션",
      "text": "전화가 끊겼다."
    },
    {
      "speaker": "용지혜",
      "text": "…지효야. 언니가 갈게."
    }
  ],
  "ending": [
    {
      "speaker": "문희찬",
      "text": "크윽… 누님이 가만 안 둘 거다.", "expr": "화남"
    },
    {
      "speaker": "용지효",
      "text": "언니… 고마워. 무서웠어."
    },
    {
      "speaker": "용지혜",
      "text": "괜찮아. 이제 집에 가자.", "expr": "웃음"
    },
    {
      "speaker": "내레이션",
      "text": "골목을 나서는 순간, 고급 세단이 지나간다."
    },
    {
      "speaker": "내레이션",
      "text": "뒷자리의 붉은 머리 남자와 눈이 마주쳤다."
    },
    {
      "speaker": "김성진",
      "text": "………"
    },
    {
      "speaker": "용지혜",
      "text": "(…몸이 안 움직여. 저 사람은 뭐야?)"
    },
    {
      "speaker": "내레이션",
      "text": "남자는 공허하게 웃고, 어둠 속으로 사라졌다."
    }
  ]
};

// ===== 스토리 전용 초상화 (img/story/portraits/<slug>_<base|angry|smile>.webp) =====
// 대사 표정: expr: '화남' | '웃음' (기본 '기본'), 또는 speaker를 '문지예(화남)'처럼 써도 됩니다. 초상화가 없는 인물은 카드 그림으로 대체.
window.STORY_DATA.portraits = { '문지예': 'jiye', '용지혜': 'jihye', '안리': 'anri', '홍가영': 'gayoung', '오명준': 'myungjun', '송철순': 'cheolsun', '문희찬': 'heechan' };
window.STORY_DATA.exprSlug = { '기본': 'base', '화남': 'angry', '웃음': 'smile' };

// ===== 일일 카드 뽑기 확률 (서버 supabase/gacha.sql 과 동일하게 유지) =====
window.STORY_DATA.gacha = { rates: [['NORMAL', 0.70], ['RARE', 0.20], ['HIGH RARE', 0.065], ['SUPER RARE', 0.03], ['ULTRA RARE', 0.005]] };
window.rollGachaRarity = (r = Math.random()) => { let acc = 0; for (const [g, p] of window.STORY_DATA.gacha.rates) { acc += p; if (r < acc) return g; } return 'NORMAL'; };
