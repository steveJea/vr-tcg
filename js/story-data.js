// ===== 스토리 모드 데이터 (대사·챕터 구성) =====
// 대사는 여기만 고치면 됩니다. speaker: 화자 이름, portrait: 'starter'(고른 캐릭터) | 'enemy'(이번 페이즈 첫 적) | 카드 id | null(나레이션)
// lines.default 는 공통 대사, lines[카드id] 가 있으면 그 캐릭터를 골랐을 때 그 대사를 씁니다.
window.STORY_DATA = {
  // 오프닝: 메인 스토리 첫 진입 시 1번 재생. video 경로를 넣으면 영상, 비어 있으면 자리표시 화면
  opening: { video: '', poster: '', title: 'OPENING', text: '오프닝 영상이 들어갈 자리예요. (준비 중)' },
  starters: [
    { id: '2000600126', name: '문지예', tagline: '(소개 문구 준비 중)' },
    { id: '2000200044', name: '용지혜', tagline: '(소개 문구 준비 중)' },
    { id: '2001500294', name: '안리', tagline: '(소개 문구 준비 중)' },
  ],
  // 밸런스: 승리 시 스탯 포인트, 포인트 1당 상승량
  statPoints: { normal: 3, boss: 5 },
  statPerPoint: { ATK: 2, HP: 10, DEF: 2 },
  chapters: [
    {
      id: 1, title: 'CHAPTER 1', subtitle: '(챕터 제목 준비 중)',
      phases: [
        // enemyName: 전투 화면 상대 이름 / enemies: 노멀 카드 power 순위 구간 [from, to) 에서 count 장 / 또는 ids: ['카드id', ...] 로 직접 지정
        { no: 1, type: 'normal', enemyName: '적군', title: '(페이즈 1 제목)', tip: '카드를 소환하고 상대 카드를 공격해 보세요.', enemies: { count: 1, rank: [0, 30] },
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
        { no: 5, type: 'boss', enemyName: '보스', title: '(보스전 제목)', tip: '보스전! 상대 진영 HP를 0으로 만들면 승리해요.', enemies: { count: 4, rank: [120, 203] }, baseHp: 500,
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
          "text": "그럼 쓰러뜨리고 물어볼게요."
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
          "text": "거절할게요. 대신 이길게요."
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
          "text": "약속했잖아요!"
        },
        {
          "speaker": "정아영",
          "text": "배척지에서 약속 믿는 바보가 어딨어?"
        }
      ]
    },
    "5": {
      "title": "하이에나 굴",
      "enemyName": "오명준",
      "enemies": {
        "ids": [
          "1000600121",
          "2000600129",
          "2000600136",
          "2000600118"
        ]
      },
      "lines": [
        {
          "speaker": "정아영",
          "text": "크윽… 오명준 오빠한테 이를 거야!"
        },
        {
          "speaker": "내레이션",
          "text": "구로 배척지의 무력집단, 하이에나."
        },
        {
          "speaker": "오명준",
          "text": "여왕벌 막내가 우리 집엔 웬일이야?"
        },
        {
          "speaker": "문지예",
          "text": "USB를 찾으라고 시킨 사람, 누구죠?"
        },
        {
          "speaker": "오명준",
          "text": "알면 너도 그 남자처럼 될 텐데?"
        },
        {
          "speaker": "문지예",
          "text": "그래도 알아야겠어요."
        },
        {
          "speaker": "오명준",
          "text": "좋아. 무너뜨려 보든가!"
        }
      ],
      "leader": "1000600121"
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
      "text": "오빠, 그만해요! 사람 죽어요!"
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
      "speaker": "오명준",
      "text": "…강남. 압구정에서 내려온 일이야."
    },
    {
      "speaker": "오명준",
      "text": "우린 심부름꾼일 뿐이라고."
    },
    {
      "speaker": "문지예",
      "text": "이름은요?"
    },
    {
      "speaker": "오명준",
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
window.STORY_DATA.noPortrait = ['내레이션', '쓰러진 남자'];
