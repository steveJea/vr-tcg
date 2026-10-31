// ===== 스토리 모드 데이터 (대사·챕터 구성) =====
// 대사는 여기만 고치면 됩니다. speaker: 화자 이름, portrait: 'starter'(고른 캐릭터) | 'enemy'(이번 페이즈 첫 적) | 카드 id | null(나레이션)
// lines.default 는 공통 대사, lines[카드id] 가 있으면 그 캐릭터를 골랐을 때 그 대사를 씁니다.
window.STORY_DATA = {
  // 오프닝: 메인 스토리 첫 진입 시 1번 재생. video 경로를 넣으면 영상, 비어 있으면 자리표시 화면
  opening: { video: 'video/opening.mp4', poster: 'img/story/opening_poster.webp', title: 'OPENING', text: '' },
  starters: [
    { id: '10111', name: '문지예', tagline: '(소개 문구 준비 중)' },
    { id: '10265', name: '용지혜', tagline: '(소개 문구 준비 중)' },
    { id: '10224', name: '안리', tagline: '(소개 문구 준비 중)' },
  ],
  // 밸런스: 승리 시 스탯 포인트, 포인트 1당 상승량
  statPoints: { normal: 3, boss: 5 },
  statPerPoint: { ATK: 1, HP: 5, DEF: 1 },
  // 같은 스탯에 넣은 포인트: statFull 개까지는 위 상승량 그대로, 그 뒤로는 절반 (합계는 버림)
  // 한 스탯에는 그 카드에 넣은 포인트 합계의 절반(올림)까지만. 예) 합계 7 → 한 스탯 최대 4
  statFull: 5,
  // 스탯 규칙 버전. 2 = 위 규칙 (예전 분배는 한 번 전부 돌려줌)
  statRuleV: 2,
  // 기본 리더 스킬 (스토리 전용): 리더 카드의 속성(class) 효과 + 클래스(attribute) 효과를 더해 아군 전체에 적용 (리더가 필드에 있는 동안).
  // atk·def·hp = 아군 비율, eAtk·eDef = 적 전체 감소 비율. 리더가 쓰러지면 효과가 꺼지고 아군 진영 HP −30% (1전투 1번)
  leader: {
    deathPenalty: 0.3,
    el: {
      FIRE: { name: '불', atk: 0.05 }, ICE: { name: '얼음', def: 0.05 }, WIND: { name: '바람', hp: 0.05 },
      DARK: { name: '어둠', atk: 0.03, hp: 0.03 }, LIGHT: { name: '빛', def: 0.03, hp: 0.03 }, ABYSS: { name: '심연', atk: 0.04, def: 0.02 }, VOID: { name: '공허', atk: 0.05, def: 0.03 },
    },
    cls: {
      CHARGE: { name: '돌격', atk: 0.03 }, DEFENSE: { name: '방어', def: 0.04 }, CRUSH: { name: '분쇄', atk: 0.02, def: 0.02 }, SUPPORT: { name: '지원', hp: 0.04 },
      DISTURB: { name: '교란', eAtk: 0.03 }, FASCINATION: { name: '매혹', eDef: 0.03 },
      OVERWHELMING: { name: '압도', atk: 0.05, def: 0.05 }, FURIOUS: { name: '격노', atk: 0.05, eDef: 0.05 },
      PHENOMENAL: { name: '경이', atk: 0.03, def: 0.03, hp: 0.04 }, EXTERMINATE: { name: '섬멸', atk: 0.04, eDef: 0.03, eAtk: 0.02 },
      BALANCE: { name: '균형', def: 0.04, hp: 0.04 }, UNLIMITED: { name: '무한', atk: 0.06, eDef: 0.03 },
    },
  },
  // 스토리 전투: 출전 카드 최대 장수 (전부 필드에서 시작, 손패·드로우 없음)
  battleCards: 5,
  // 보스전 상대 진영 HP: 챕터 순서대로 (챕터 1 = 500, 이후 챕터 1의 +50%씩). 표보다 뒤 챕터는 마지막 값 + 250씩.
  // 페이즈에 baseHp 를 직접 적으면 그 값이 우선. 보스 카드는 페이즈의 bossId → enemyName 과 같은 이름의 카드 → (ids 지정 시) 첫 카드 → 가장 강한 카드 순으로 정함
  bossBaseHp: [500, 750, 1000, 1250, 1500],
  chapters: [
    {
      id: 1, title: 'CHAPTER 1', subtitle: '(챕터 제목 준비 중)',
      rewardCard: 'NORMAL',   // 페이즈 첫 클리어 시 무료 카드 등급. 없으면(챕터 2~) 스탯 포인트만
      // 페이즈 첫 클리어 고정 보상 카드 (모든 루트 동일, 이미 있으면 한 장 더). 서버: supabase/story_ch1_reward.sql
      rewardCards: { 1: '10248', 2: '10093', 3: '10185', 4: '10130', 5: '10308' },   // 예유진·남태은·선나영·반지아·이윤이
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
// 문지예 루트: 스토리 시트 CH1-2 탭 기준 (약자 M/M1=문지예, M2=문지철, S=수상한 남자, NA=내레이션, A~D·K·L=불량배 NPC)
window.STORY_DATA.chapters[0].byStarter = { '10111': {
  "subtitle": "브레이크",
  "phases": {
    "1": {
      "title": "수상한 남자",
      "enemyName": "수상한 남자",
      "enemies": {
        "ids": [
          "10210"
        ]
      },
      "lines": [
        {
          "speaker": "내레이션",
          "text": "생각보다 상대는 만만치 않다."
        },
        {
          "speaker": "내레이션",
          "text": "하지만 문지철, 이 괴물이 있다면 상대가 누구든 상관 없다."
        }
      ],
      "party": {
        "forced": [
          "10111",
          "10112"
        ]
      },
      "after": [
        {
          "speaker": "문지예",
          "text": "오빠..그만. 그러다 진짜 죽어요."
        },
        {
          "speaker": "문지철",
          "text": "헤헤...알았어. 그만할게요."
        },
        {
          "speaker": "수상한 남자",
          "text": "너희..생각보다 강하네..이거...받아라."
        },
        {
          "speaker": "문지예",
          "text": "이게 뭐죠?"
        },
        {
          "speaker": "내레이션",
          "text": "남자는 지예에게 수상한 USB를 건내주고 쩔뚝거리며 사라졌다."
        }
      ]
    },
    "2": {
      "title": "시비",
      "enemyName": "불량배-A",
      "enemies": {
        "ids": [
          "10143",
          "10144"
        ]
      },
      "lines": [
        {
          "speaker": "불량배-A",
          "text": "너 여왕벌 세컨이지?"
        },
        {
          "speaker": "문지예",
          "text": "응? 여왕벌클럽 소속인데..왜요?"
        },
        {
          "speaker": "불량배-B",
          "text": "야..우리도 거기 좀 들어갈 수 없냐?"
        },
        {
          "speaker": "문지예",
          "text": "움..근데 저희 언니 허락이 있어야 해요."
        },
        {
          "speaker": "불량배-B",
          "text": "에이..그럼 네가 한 번 테스트 해봐!"
        },
        {
          "speaker": "문지예",
          "text": "에? 저랑 싸우자고요? 싫은데..."
        }
      ],
      "party": {
        "forced": [
          "10111"
        ]
      }
    },
    "3": {
      "title": "단서",
      "enemyName": "불량배-K",
      "enemies": {
        "ids": [
          "10153",
          "10143",
          "10144"
        ]
      },
      "lines": [
        {
          "speaker": "불량배-A",
          "text": "와..너 되게 강하네. 우리가 졌다."
        },
        {
          "speaker": "문지예",
          "text": "응? 이렇게 쉽게 물러선다고???"
        },
        {
          "speaker": "내레이션",
          "text": "지혜는 주머니에 있던 USB가 사라진 걸 알았다."
        },
        {
          "speaker": "문지예",
          "text": "야!! 이 소매치기들아!!!!"
        },
        {
          "speaker": "내레이션",
          "text": "지혜는 불량배들을 급하게 쫓아갔다."
        },
        {
          "speaker": "불량배-K",
          "text": "멍청아! 잘 했어야지!"
        },
        {
          "speaker": "불량배-A",
          "text": "에이..진짜 실력 함 보여주지 뭐."
        },
        {
          "speaker": "문지예",
          "text": "흥! 진짜로 한 번 들어와 보세요!"
        }
      ],
      "party": {
        "forced": [
          "10111"
        ]
      },
      "after": [
        {
          "speaker": "불량배-K",
          "text": "아...되게 세다. 안되겠다."
        },
        {
          "speaker": "문지예",
          "text": "근데, 그걸 왜 가져가려고 했던 거죠?"
        }
      ]
    },
    "4": {
      "title": "잠긴 파일",
      "enemyName": "불량배-L",
      "enemies": {
        "ids": [
          "10154",
          "10153",
          "10143",
          "10144"
        ]
      },
      "lines": [
        {
          "speaker": "불량배-K",
          "text": "이거...사실 우리도 누가 가져오라고 했어"
        },
        {
          "speaker": "내레이션",
          "text": "저 멀리서 무섭게 생긴 여성이 다가온다."
        },
        {
          "speaker": "불량배-L",
          "text": "이년아! 그걸 말하면 어떡해?"
        },
        {
          "speaker": "불량배-K",
          "text": "아 언니..미안해요..."
        },
        {
          "speaker": "문지예",
          "text": "언니는 또 뭔가요?"
        },
        {
          "speaker": "불량배-L",
          "text": "애기야. 좋은 말로 할 때 그거 내놔라."
        },
        {
          "speaker": "문지예",
          "text": "그렇겐 안 되죠."
        }
      ],
      "party": {
        "forced": [
          "10111"
        ]
      }
    },
    "5": {
      "title": "비밀은 어디에?",
      "enemyName": "불량배-D",
      "enemies": {
        "ids": [
          "10146",
          "10153",
          "10143",
          "10144",
          "10145"
        ]
      },
      "lines": [
        {
          "speaker": "문지예",
          "text": "자, 이제 말씀해보세요."
        },
        {
          "speaker": "불량배-L",
          "text": "으윽..사실 이거...무서운 귀족이....헉!!"
        },
        {
          "speaker": "내레이션",
          "text": "누군가가 불량배 여성의 등에 칼을 꽂았고, 여성은 현장에서 사망했다."
        },
        {
          "speaker": "문지예",
          "text": "아악!! 이게 뭐 하는 짓이야!!"
        },
        {
          "speaker": "불량배-D",
          "text": "야야...그냥 내놓지 뭐 말이 많아? 너도 얘 같이 될거야."
        },
        {
          "speaker": "불량배-K",
          "text": "으으...언니..죽으면 안 돼"
        },
        {
          "speaker": "불량배-D",
          "text": "시끄럽고 쟤나 잡아."
        },
        {
          "speaker": "불량배-K",
          "text": "흑흑...네...."
        }
      ],
      "party": {
        "forced": [
          "10111"
        ]
      },
      "bossId": "10146"
    }
  },
  "intro": "구로 배척지 '여왕벌클럽'의 2인자.\n잔인한 언니와 오빠를 멈춰 세우는 단 하나의 브레이크.\n싸움은 약하지만, 사람의 마음을 읽는 데엔 누구보다 빠르다.",
  "start": [
    {
      "speaker": "내레이션",
      "text": "늦여름, 장마가 끝나지 않은 배척지 007 구역"
    },
    {
      "speaker": "내레이션",
      "text": "여왕벌클럽의 2인자와 3인자 뒤를 누군가가 따라온다."
    },
    {
      "speaker": "문지예",
      "text": "오빠...누가 미행하는데요?"
    },
    {
      "speaker": "문지철",
      "text": "응? 누가 우리 따라온다고요? 죽일까요?"
    },
    {
      "speaker": "문지예",
      "text": "오빠...사람 죽이는 거 아니랬잖아요!"
    },
    {
      "speaker": "문지철",
      "text": "헤헤..그럼 안죽이고 살해할게요."
    },
    {
      "speaker": "문지예",
      "text": "하아...저기요. 저희 미행하지 마세요."
    },
    {
      "speaker": "수상한 남자",
      "text": "쳇...눈치 챘구나."
    },
    {
      "speaker": "문지철",
      "text": "저...선글래스...갖고싶다!"
    }
  ],
  "ending": [
    {
      "speaker": "불량배-D",
      "text": "으윽...우린 그냥 심부름 꾼이다. 귀족이 시킨거다."
    },
    {
      "speaker": "문지예",
      "text": "귀족? 누구요?"
    },
    {
      "speaker": "불량배-D",
      "text": "하아...시X...말하면..안 되는데.."
    },
    {
      "speaker": "내레이션",
      "text": "지예는 불량배의 배를 걷어차며 소리쳤다."
    },
    {
      "speaker": "문지예",
      "text": "빨리 말 안해?"
    },
    {
      "speaker": "불량배-D",
      "text": "하아..유리님..SS의 귀족 임유리님이다."
    },
    {
      "speaker": "문지예",
      "text": "임유리? 그 유명한 임유리가? 왜??"
    }
  ]
} };
window.STORY_DATA.noPortrait = ['내레이션', '쓰러진 남자', '???'];

// ===== 안리 전용 챕터 1 「불안한 여운」 (스토리 시트 CH1-3 탭 기준: AN=안리, H=홍가영, NA=내레이션, A~D·K·L=불량배 NPC) =====
window.STORY_DATA.chapters[0].byStarter['10224'] = {
  "subtitle": "불안한 여운",
  "phases": {
    "1": {
      "title": "위험지대",
      "enemyName": "불량배-A",
      "enemies": {
        "ids": [
          "10143"
        ]
      },
      "lines": [
        {
          "speaker": "불량배-A",
          "text": "너 자신 있나봐? 운동 좀 했어?"
        },
        {
          "speaker": "안리",
          "text": "아뇨..근데 넌 죽일 수 있어요"
        },
        {
          "speaker": "홍가영",
          "text": "나랑 가위바위보로 하자."
        },
        {
          "speaker": "안리",
          "text": "아휴...가영아. 가위바위보!"
        },
        {
          "speaker": "홍가영",
          "text": "힝 졌네..."
        },
        {
          "speaker": "불량배-A",
          "text": "이것들이 장난하나?"
        }
      ],
      "party": {
        "forced": [
          "10224"
        ]
      }
    },
    "2": {
      "title": "들개들",
      "enemyName": "불량배-K",
      "enemies": {
        "ids": [
          "10153",
          "10143"
        ]
      },
      "lines": [
        {
          "speaker": "불량배-K",
          "text": "어후..저 병신들은 여자한테 맞고 다니네"
        },
        {
          "speaker": "불량배-A",
          "text": "누님..쟤 보통이 아니에요.."
        },
        {
          "speaker": "불량배-K",
          "text": "어이 예쁘니들! 꺵값 좀 내야겠는데?"
        },
        {
          "speaker": "안리",
          "text": "나도 받아야해요."
        },
        {
          "speaker": "불량배-K",
          "text": "엥? 무슨 말이야?"
        },
        {
          "speaker": "안리",
          "text": "너희 때문에 짜증나서 깽값 좀 받겠다고!!"
        }
      ],
      "party": {
        "forced": [
          "10224"
        ]
      }
    },
    "3": {
      "title": "안전지대?",
      "enemyName": "불량배-C",
      "enemies": {
        "ids": [
          "10145",
          "10144"
        ]
      },
      "lines": [
        {
          "speaker": "불량배-C",
          "text": "와...조그만 년들이 미쳐부럿네~"
        },
        {
          "speaker": "불량배-B",
          "text": "아따 형님. 진짜 저년들 패 죽여야겠슴둥~"
        },
        {
          "speaker": "안리",
          "text": "뭐야 저 찐따들은..."
        },
        {
          "speaker": "홍가영",
          "text": "ㅋㅋㅋ 말투 되게 구려!"
        },
        {
          "speaker": "불량배-C",
          "text": "아따, 니들 오늘 포 떠버릴 거구마~"
        },
        {
          "speaker": "불량배-B",
          "text": "저 애기들이 오늘 하직인사 하겟구먼유~"
        }
      ],
      "party": {
        "forced": [
          "10224"
        ]
      }
    },
    "4": {
      "title": "너희 좀비니?",
      "enemyName": "불량배-C",
      "enemies": {
        "ids": [
          "10145",
          "10154",
          "10153"
        ]
      },
      "lines": [
        {
          "speaker": "불량배-L",
          "text": "에휴..남자들..진짜...병신들의 합창이야?"
        },
        {
          "speaker": "불량배-K",
          "text": "ㅋㅋㅋ 언니. 말 너무 웃겨요"
        },
        {
          "speaker": "안리",
          "text": "하아..진짜 뭐 이렇게 계속 나와?"
        },
        {
          "speaker": "홍가영",
          "text": "진짜 좀비같아. 내가 도와줄까~"
        },
        {
          "speaker": "안리",
          "text": "아니아니..내가 할게. 저것들..에휴.."
        },
        {
          "speaker": "불량배-C",
          "text": "누님들. 저거 같이 조지시구마~~"
        }
      ],
      "party": {
        "forced": [
          "10224"
        ]
      }
    },
    "5": {
      "title": "이유..그리고 여운",
      "enemyName": "불량배-D",
      "enemies": {
        "ids": [
          "10146",
          "10153",
          "10154",
          "10145"
        ]
      },
      "lines": [
        {
          "speaker": "불량배-D",
          "text": "아그들아 괜찮나~"
        },
        {
          "speaker": "불량배-B",
          "text": "아 성님요..저것들이 말잉교...(우드득) 윽"
        },
        {
          "speaker": "내레이션",
          "text": "불량배는 부하의 목을 꺽어버렸다. 부하는 즉사했다."
        },
        {
          "speaker": "안리",
          "text": "아악!! 너희 지금 뭐하는거야? 죽었잖아!"
        },
        {
          "speaker": "불량배-D",
          "text": "여기서 사람 하나 죽는 게 뭐 대수라고?"
        },
        {
          "speaker": "안리",
          "text": "으아아악! 진짜 넌 용서 못하겠다!"
        }
      ],
      "party": {
        "forced": [
          "10224"
        ]
      },
      "bossId": "10146"
    }
  },
  "intro": "성동의 복싱 소녀, 전국체전 금메달리스트.\n유치원 때부터 함께한 단짝 가영과 매일 링에 오른다.\n짧고 묵직한 한 방. 시비는 사양하지만, 피하지도 않는다.",
  "start": [
    {
      "speaker": "내레이션",
      "text": "B급 안전지대. 하지만 사실상 모든 게 방치된 곳이다."
    },
    {
      "speaker": "홍가영",
      "text": "아..여기 진짜 안전지대 맞아?"
    },
    {
      "speaker": "안리",
      "text": "그러게말야...점점 더 척박해지는 거 같아."
    },
    {
      "speaker": "홍가영",
      "text": "정말...좀 무섭다."
    },
    {
      "speaker": "내레이션",
      "text": "저 멀리서 불량배들이 두 소녀를 보며 시비를 건다."
    },
    {
      "speaker": "불량배-A",
      "text": "어이~ 여기 통행료 있는 거 몰라? 지갑 다 털고 가라~"
    },
    {
      "speaker": "홍가영",
      "text": "하아..미친놈들"
    }
  ],
  "ending": [
    {
      "speaker": "불량배-D",
      "text": "크윽… 이, 이런 꼬맹이한테…."
    },
    {
      "speaker": "내레이션",
      "text": "불량배 대장은 부축을 받으며 도망쳤다."
    },
    {
      "speaker": "불량배-D",
      "text": "너… 후회할 거야."
    },
    {
      "speaker": "홍가영",
      "text": "뭐래? 저 등신은...ㅋㅋ"
    },
    {
      "speaker": "안리",
      "text": "흠...앞으로 더 귀찮아질 거 같네.."
    },
    {
      "speaker": "내레이션",
      "text": "그날 밤, 골목의 그림자는 더 짙어졌다."
    }
  ]
};

// ===== 용지혜 전용 챕터 1 「동생의 이름으로」 (원문: 사용자 확정 대본, 수정 금지) =====
// 용지혜 루트 「개미굴」: 스토리 시트 CH1 탭 기준 (약자 Y=용지혜, Y2=용지효, NA=내레이션, A~D·K·L=불량배 NPC)
window.STORY_DATA.chapters[0].byStarter['10265'] = {
  "subtitle": "개미굴",
  "phases": {
    "1": {
      "title": "배척지 입구",
      "enemyName": "불량배-A",
      "enemies": {
        "ids": [
          "10143"
        ]
      },
      "lines": [
        {
          "speaker": "불량배-A",
          "text": "어? 진짜 왔네. 겁도 없이."
        },
        {
          "speaker": "용지혜",
          "text": "우리 지효 어디 있나요?"
        },
        {
          "speaker": "불량배-A",
          "text": "알려 줄 것 같아? 꺼져."
        },
        {
          "speaker": "용지혜",
          "text": "(무서워… 그래도 물러설 수 없어.)"
        },
        {
          "speaker": "용지혜",
          "text": "비켜요. 안 비키면…진짜 죽일겁니다."
        }
      ],
      "party": {
        "forced": [
          "10265"
        ]
      }
    },
    "2": {
      "title": "사채업자",
      "enemyName": "불량배-K",
      "enemies": {
        "ids": [
          "10153",
          "10154"
        ]
      },
      "lines": [
        {
          "speaker": "불량배-K",
          "text": "야..니 동생이 우리한테 빚졌어. 평생 앵벌이로 갚아야 해."
        },
        {
          "speaker": "불량배-L",
          "text": "한..100년 걸릴걸? ㅋㅋㅋ"
        },
        {
          "speaker": "용지혜",
          "text": "지효가 빚을 질 애가 아니에요."
        },
        {
          "speaker": "불량배-K",
          "text": "그건 위에서 알아서 하는 거고~"
        },
        {
          "speaker": "용지혜",
          "text": "위? 그게 누군데요?"
        },
        {
          "speaker": "불량배-L",
          "text": "이게 뭐 알고 싶은 게 이렇게 많아?"
        },
        {
          "speaker": "용지혜",
          "text": "너희는 안 되겠다. 맞자."
        }
      ],
      "party": {
        "forced": [
          "10265"
        ]
      }
    },
    "3": {
      "title": "낡은 창고",
      "enemyName": "불량배-A",
      "enemies": {
        "ids": [
          "10143",
          "10144"
        ]
      },
      "lines": [
        {
          "speaker": "불량배-L",
          "text": "크윽… 창고. 창고로 데려갔어."
        },
        {
          "speaker": "내레이션",
          "text": "버려진 창고 앞, 불빛이 새어 나온다."
        },
        {
          "speaker": "불량배-B",
          "text": "여기까지 왔어? 끈질기네."
        },
        {
          "speaker": "불량배-A",
          "text": "아까 그년이야! 조심해!"
        },
        {
          "speaker": "용지혜",
          "text": "이번엔 안 봐줘요. 돌격!"
        }
      ],
      "party": {
        "forced": [
          "10265"
        ]
      }
    },
    "4": {
      "title": "텅 빈 의자",
      "enemyName": "불량배-C",
      "enemies": {
        "ids": [
          "10145",
          "10144",
          "10153"
        ]
      },
      "lines": [
        {
          "speaker": "내레이션",
          "text": "창고 안, 의자에 묶인 끈만 남아 있다."
        },
        {
          "speaker": "용지혜",
          "text": "지효는…? 지효 어디 갔어!"
        },
        {
          "speaker": "불량배-C",
          "text": "한발 늦었네. 대장한테 넘겼어."
        },
        {
          "speaker": "불량배-K",
          "text": "히히히...지금쯤...대장한테 제대로 교육받고 있을걸~"
        },
        {
          "speaker": "용지혜",
          "text": "...너희들 지금 장난해? 빨리 어디에 있는지 말 안 해?!"
        },
        {
          "speaker": "불량배-C",
          "text": "ㅋㅋㅋ 너도 같이 가자."
        }
      ],
      "party": {
        "forced": [
          "10265"
        ]
      }
    },
    "5": {
      "title": "개미굴",
      "enemyName": "불량배-D",
      "enemies": {
        "ids": [
          "10146",
          "10144",
          "10145",
          "10153",
          "10154"
        ]
      },
      "lines": [
        {
          "speaker": "용지효",
          "text": "언니...나.....미안..."
        },
        {
          "speaker": "용지혜",
          "text": "지효야!!!"
        },
        {
          "speaker": "내레이션",
          "text": "지혜는 쓰러진 지효에게 달려갔다. 지효의 몰골은 말이 아니었다."
        },
        {
          "speaker": "용지혜",
          "text": "비켜!!! 빨리 병원에!!!"
        },
        {
          "speaker": "불량배-D",
          "text": "감동의 재회네. 근데 내가 비킬리가 없겠지?"
        },
        {
          "speaker": "용지혜",
          "text": "꺼져! 이러다 지효 죽는다고!!!"
        },
        {
          "speaker": "불량배-D",
          "text": "능력 되면 우리 재끼고 가라."
        }
      ],
      "party": {
        "forced": [
          "10265"
        ]
      },
      "bossId": "10146",
      "after": [
        {
          "speaker": "용지혜",
          "text": "아아...빨리..."
        },
        {
          "speaker": "용지효",
          "text": "언니...미안..근데..나"
        },
        {
          "speaker": "용지혜",
          "text": "지효야 말 하지마. 괜찮아! 빨리 병원에 가자."
        },
        {
          "speaker": "용지효",
          "text": "언니..진짜..나 돈 안 빌렸..."
        },
        {
          "speaker": "내레이션",
          "text": "지효의 두 눈은 스르르 감겼고, 양 손은 힘 없이 쳐졌다.",
          "image": "img/story/ch1-5.webp"
        },
        {
          "speaker": "용지혜",
          "text": "안돼!!!!!!!!!!!!!!"
        }
      ]
    }
  },
  "intro": "강북의 주짓수 소녀. 시 대회 수상, 특기생 진학을 꿈꾼다.\n소심한 성격을 이기려고 매트 위에서 버텨 온 노력파.\n하나뿐인 동생 지효를 위해서라면, 두려움도 꺾는다.",
  "start": [
    {
      "speaker": "내레이션",
      "text": "B급 안전지대, 늦은 밤의 도장."
    },
    {
      "speaker": "용지혜",
      "text": "(지효가 왜 연락이 안 되지...)"
    },
    {
      "speaker": "내레이션",
      "text": "휴대폰이 울린다. 지효의 번호다."
    },
    {
      "speaker": "용지효",
      "text": "살려주세요!!"
    },
    {
      "speaker": "용지혜",
      "text": "지효야! 지효야!!!"
    },
    {
      "speaker": "???",
      "text": "야야...이거 이거...묻어버린다."
    },
    {
      "speaker": "용지혜",
      "text": "너 누구야!"
    },
    {
      "speaker": "???",
      "text": "느그 동생X 구하고 싶으면 배척지05 구역으로 와라. 혼자. ㅋㅋㅋ"
    },
    {
      "speaker": "내레이션",
      "text": "\"안돼! 언니 오면 안돼!!\" 지효의 외치는 소리가 들리며 전화가 끊겼다."
    },
    {
      "speaker": "용지혜",
      "text": "이...이 썩을놈들..!"
    }
  ]
};

// ===== 스토리 전용 초상화 (img/story/portraits/<slug>_<표정>.webp) =====
// 표정 파일: base(기본) · angry(화남/분노) · smile(웃음) · sad(슬픔/우울) · surprised(놀람) · playful(장난)
// 대사 표정: "expr" 또는 "face" 키 (한글·영문 모두), 또는 speaker를 '문지예(화남)'처럼. 비우면 기본.
// 그 표정 파일이 없으면 비슷한 표정(exprAlt: 웃음↔장난) → <slug>_base → 카드 그림 순으로 대체.
window.STORY_DATA.portraits = { '문지예': 'mun_jiye', '문지아': 'mun_jia', '용지혜': 'yong_jihye', '안리': 'an_ri', '이민채': 'lee_minchae', '홍가영': 'gayoung', '오명준': 'myungjun', '송철순': 'cheolsun', '문희찬': 'heechan', '곽재준': 'kwak_jaejun', '한겨울': 'han_gyeoul', '임유리': 'im_yuri', '진하린': 'jin_harin', '민유연': 'min_yuyeon', '민홍기': 'min_honggi', '유가을': 'yu_gaeul', '강태안': 'kang_taean', '강태준': 'kang_taejun', '이민수': 'lee_minsu', '김철민': 'kim_cheolmin', '유연 아버지': 'min_father', '유연 어머니': 'min_mother', '[각성] 임유리': 'im_yuri_awake', '오유나': 'o_yuna' };
window.STORY_DATA.exprSlug = { '기본': 'base', '보통': 'base', '화남': 'angry', '분노': 'angry', '웃음': 'smile', '슬픔': 'sad', '놀람': 'surprised', '장난': 'playful',
  base: 'base', normal: 'base', angry: 'angry', smile: 'smile', sad: 'sad', surprised: 'surprised', playful: 'playful',
  '미침': 'crazy', '싸늘': 'cold', '우울': 'sad', crazy: 'crazy', cold: 'cold',
  '하품': 'yawn', '야비': 'sneer', '야비한미소': 'sneer', '짜증': 'angry', '당황': 'surprised', yawn: 'yawn', sneer: 'sneer', '기쁨': 'smile', '다침': 'hurt', hurt: 'hurt' };   // 챕터 0 시트 표정 (하품·야비한미소 전용 그림: im_yuri_c0_yawn / im_yuri_c0_sneer)
// 챕터 0 전용: 새 임유리 초상화 (im_yuri_c0_*). 챕터 4·6 은 기존 im_yuri_* 그대로
// 황보예: 챕터 0 전용 (hwangbo_ye_c0_*). 챕터 4 는 기존대로 카드 그림
// 송지아: 챕터 0 전용 (song_jia_c0_*). 다른 챕터는 그대로
// 챕터 8 「주홍글씨」 전용: 안지윤 3버전(교복·10세·중딩) · [염원] 안지윤 · 안소라 · 학부모1~6(=가해자 부모, 주홍글씨1~6) · 친구1~2. 하급/상급 몽마는 카드 그림
window.STORY_DATA.chapterPortraits = { 0: { '임유리': 'im_yuri_c0', '황보예': 'hwangbo_ye_c0', '송지아': 'song_jia_c0' },
  8: { '안지윤': 'an_jiyun', '초등학생 안지윤': 'an_jiyun_c10', '중학생 안지윤': 'an_jiyun_ms', '[염원] 안지윤': 'an_jiyun_wish', '안소라': 'an_sora',
    ...Object.fromEntries([1, 2, 3, 4, 5, 6].flatMap(i => [[`학부모${i}`, `scarlet${i}`], [`가해자 부모${i}`, `scarlet${i}`]])), '친구1': 'an_jiyun_friend1', '친구2': 'an_jiyun_friend2', '친구3': 'an_jiyun_friend3'  },
  // 챕터 9~11: 최윤 세 자매 · [염원](유령) · 이지영 · 15인. 최윤희 복장은 대사 줄 slug (교복 기본 · 홈웨어 · 일상복 · 10장 1페이즈 딩초). 윤희 아버지·몽마는 카드 그림
  ...Object.fromEntries([9, 10, 11].map(c => [c, { '최윤희': 'choi_yunhee_school', '최윤아': 'choi_yuna', '최윤정': 'choi_yunjeong', '[염원] 최윤아': 'choi_yuna_wish', '[염원] 최윤정': 'choi_yunjeong_wish', '이지영': 'lee_jiyoung',
    '백시훈': 'baek_sihun', '한도겸': 'han_dogyeom', '오세찬': 'oh_sechan', '장민규': 'jang_mingyu', '배현오': 'bae_hyeono', '마동철': 'ma_dongcheol', '구태만': 'gu_taeman', '독곰': 'dokgom',
    '쇳덩이': 'soetdeongi', '바위': 'bawi', '서하늘': 'seo_haneul', '진다솜': 'jin_dasom', '권명호': 'kwon_myeongho', '남궁현': 'namgung_hyeon', '도강혁': 'do_ganghyeok' }])),
  // 챕터 12 「위대한 개츠비」: 김지수 · 김정란(할머니, 시트 화자 '루비에르 회장 김정란') · 김지우 · 안지수 · 안혜진 · 한서린 · 도예나 · 최태석 (그림순이 10/31)
  12: { '김지수': 'kim_jisu', '김정란': 'kim_jeongran', '루비에르 회장 김정란': 'kim_jeongran', '김지우': 'kim_jiwoo', '안지수': 'an_jisu', '안혜진': 'an_hyejin', '한서린': 'han_seorin', '도예나': 'do_yena', '최태석': 'choi_taeseok' } };
window.STORY_DATA.exprAlt = { smile: 'playful', playful: 'smile', crazy: 'playful', cold: 'angry', sneer: 'playful', yawn: 'base', hurt: 'sad' };

// ===== 일일 카드 뽑기 확률 (서버 supabase/gacha.sql 과 동일하게 유지) =====
window.STORY_DATA.gacha = { rates: [['NORMAL', 0.70], ['RARE', 0.20], ['HIGH RARE', 0.065], ['SUPER RARE', 0.03], ['ULTRA RARE', 0.005]],
  // 특수 뽑기 (소환권 1장 = 1회). 서버 supabase/story_gacha.sql 과 같게 유지. 10회는 HR 이상 1장 보장, 챕터 첫 클리어마다 소환권 +10
  special: [['NORMAL', 0.50], ['RARE', 0.30], ['HIGH RARE', 0.16], ['SUPER RARE', 0.032], ['ULTRA RARE', 0.008]], ticketsPerChapter: 10 };
window.rollGachaRarity = (r = Math.random(), rates = window.STORY_DATA.gacha.rates) => { let acc = 0; for (const [g, p] of rates) { acc += p; if (r < acc) return g; } return 'NORMAL'; };
