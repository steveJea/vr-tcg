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
        // enemies: 노멀 카드 power 순위 구간 [from, to) 에서 count 장 / 또는 ids: ['카드id', ...] 로 직접 지정
        { no: 1, type: 'normal', title: '(페이즈 1 제목)', tip: '카드를 소환하고 상대 카드를 공격해 보세요.', enemies: { count: 1, rank: [0, 30] },
          lines: { default: [
            { speaker: null, portrait: null, text: '(나레이션 대사 자리)' },
            { speaker: 'starter', portrait: 'starter', text: '(주인공 대사 자리)' },
            { speaker: 'enemy', portrait: 'enemy', text: '(적 대사 자리)' },
          ] } },
        { no: 2, type: 'normal', title: '(페이즈 2 제목)', tip: 'MP가 차면 스킬을 쓸 수 있어요. 카드를 눌러 확인해 보세요.', enemies: { count: 2, rank: [0, 50] },
          lines: { default: [ { speaker: 'starter', portrait: 'starter', text: '(대사 자리)' }, { speaker: 'enemy', portrait: 'enemy', text: '(대사 자리)' } ] } },
        { no: 3, type: 'normal', title: '(페이즈 3 제목)', tip: '상대 카드를 쓰러뜨리면 상대 MP 일부를 흡수해요.', enemies: { count: 2, rank: [30, 90] },
          lines: { default: [ { speaker: 'starter', portrait: 'starter', text: '(대사 자리)' }, { speaker: 'enemy', portrait: 'enemy', text: '(대사 자리)' } ] } },
        { no: 4, type: 'normal', title: '(페이즈 4 제목)', tip: '속성 상성을 이용하면 더 큰 피해를 줄 수 있어요.', enemies: { count: 3, rank: [50, 120] },
          lines: { default: [ { speaker: 'starter', portrait: 'starter', text: '(대사 자리)' }, { speaker: 'enemy', portrait: 'enemy', text: '(대사 자리)' } ] } },
        { no: 5, type: 'boss', title: '(보스전 제목)', tip: '보스전! 상대 진영 HP를 0으로 만들면 승리해요.', enemies: { count: 4, rank: [120, 203] }, baseHp: 500,
          lines: { default: [ { speaker: 'enemy', portrait: 'enemy', text: '(보스 대사 자리)' }, { speaker: 'starter', portrait: 'starter', text: '(대사 자리)' } ] } },
      ],
    },
  ],
};
