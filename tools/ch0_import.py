#!/usr/bin/env python3
"""챕터 0 (튜토리얼) 시트 CSV → js/story-data-ch0.js
사용: python3 tools/ch0_import.py <ch0.csv>
시트 열: phase, 제목, 강제배정, 대상(화자), 표정, 대화내용, 진행시점(전/후), 멀티미디어(CH00-xx → img/story/ch0-xx.webp), 적(리더)~적5, 전투조건, 승리조건, 패배조건, 튜토리얼
전투 규칙(레벨·보상·튜토리얼 id·각성 난입 등)은 아래 PHASE 에서 고칩니다. 합류 대사(JOIN)는 시트에 없어서 여기 따로 둡니다."""
import csv, json, os, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
YURI, AWAKE, YUNA, YEBO, JIA, NARI = '2000100001', '2000000008', '2000100006', '2000100004', '2000900206', '2000300083'
NPC = {'불량배L': '2000000024', '불량배K': '2000000023', '불량배Z': '2000000038', '오유나': YUNA, '임나리': NARI}
SPK = {'NA': '내레이션', '[각성]임유리': '[각성] 임유리'}
# 페이즈 전투 설정 (시트 밖)
PHASE = {
  1: dict(enemyName='오유나', tutorial='ch0_p1',
          party=dict(forced=[YURI], mustLive=[YURI], noExtra=True, auto=True, battleLevels={YURI: 2}),
          enemies=dict(boost={YUNA: dict(HP=700)}), fullMp=True),
  2: dict(enemyName='불량배L', tutorial='ch0_p2',
          party=dict(forced=[YURI], mustLive=[YURI], noExtra=True, auto=True), reserve=[YUNA]),
  3: dict(enemyName='임나리', tutorial='ch0_p3',
          party=dict(forced=[YURI], mustLive=[], fixedLevel={YURI: 1}, only=[YUNA, YEBO], guests=[YUNA, YEBO]),   # 강제 임유리 + 오유나·황보예만 고르기
          enemies=dict(storyLevels={NARI: 30, '2000000038': 30}, levels={NARI: 5, '2000000038': 3}),
          awaken=dict(on=YURI, id=AWAKE, storyLevel=100, battleLevel=10, line='....약해...', image='img/story/ch0-05.webp')),
}
REWARD = {1: YUNA, 2: YEBO, 3: JIA}
# 합류 대사 (사용자 동의, 최소) — 승리 후 대사 끝에 붙음
JOIN = {
  1: [{'speaker': '내레이션', 'text': '오유나가 동료가 되었다.'}],
  2: [{'speaker': '내레이션', 'text': '쓰러진 불량배들 뒤, 한 소녀가 유리를 올려다본다.'},
      {'speaker': '황보예', 'text': '저… 저도 데려가 주세요!'},
      {'speaker': '임유리', 'expr': '야비', 'text': '귀엽네. 따라와.'},
      {'speaker': '내레이션', 'text': '황보예가 동료가 되었다.'}],
  3: [{'speaker': '내레이션', 'text': '무너진 성 한쪽, 숨어 있던 소녀가 걸어 나온다.'},
      {'speaker': '송지아', 'text': '…방금 그거, 당신이 한 거야?'},
      {'speaker': '[각성] 임유리', 'expr': '싸늘', 'text': '…따라오든지.'},
      {'speaker': '내레이션', 'text': '송지아가 동료가 되었다.'}],
}
def main(path):
    rows = list(csv.reader(open(path, encoding='utf-8')))[1:]
    start, phases, cur, mode = [], {}, None, 'start'
    for r in rows:
        r = (r + [''] * 20)[:20]
        ph, title, spk, expr, text, when, media = r[0].strip(), r[1].strip(), r[3].strip(), r[4].strip(), r[5].strip(), r[6].strip(), r[7].strip()
        if ph.isdigit():
            cur = int(ph); mode = 'lines'
            phases[cur] = dict(no=cur, type='normal', title=title, enemies=dict(ids=[NPC[x.strip()] for x in r[8:13] if x.strip()]), lines=[], after=[])
        if when == '후': mode = 'after'
        if not text: continue
        L = {'speaker': SPK.get(spk, spk or '내레이션'), 'text': text}
        if expr: L['expr'] = expr
        if media.startswith('CH00-'): L['image'] = f"img/story/ch0-{media[5:]}.webp"
        if cur is None: start.append(L)
        else: phases[cur]['after' if mode == 'after' else 'lines'].append(L)
    out = []
    for no in sorted(phases):
        p = phases[no]; cfg = PHASE[no]
        e = {**p['enemies'], **cfg.get('enemies', {})}
        o = {k: v for k, v in dict(no=no, type='normal', enemyName=cfg['enemyName'], title=p['title'], enemies=e, lines={'default': p['lines']},
             after=[({**L, 'image': 'img/story/ch0-05.webp'} if no == 3 and i == 0 and not L.get('image') else L) for i, L in enumerate(p['after'])] + JOIN[no],   # CH00-05(각성 임유리): 3페이즈 클리어 후 첫 대사
             tutorial=cfg['tutorial'], party=cfg['party'], reserve=cfg.get('reserve'), awaken=cfg.get('awaken'), fullMp=cfg.get('fullMp')).items() if v is not None}
        out.append(o)
    ch = dict(id=0, title='CHAPTER 0', subtitle='공허한 여신', single=True, hero=YURI, tutorial=True, start=start, rewardCards={str(k): v for k, v in REWARD.items()}, phases=out)
    js = ('// ===== 스토리 챕터 0 「공허한 여신」 (튜토리얼 · 시트 → python3 tools/ch0_import.py <csv> 로 생성. 직접 고쳐도 됨) =====\n'
          '// 강제 출전 임유리. 페이즈별 tutorial(data/tutorials/<id>.json) · reserve(소환 대기) · awaken(임유리 쓰러지면 [각성] 임유리 난입)\n'
          'window.STORY_DATA.chapters.unshift(' + json.dumps(ch, ensure_ascii=False, indent=1) + ');\n')
    open(os.path.join(ROOT, 'js/story-data-ch0.js'), 'w', encoding='utf-8').write(js)
    print('ok', len(start), 'start lines', {k: (len(v['lines']), len(v['after'])) for k, v in phases.items()})
main(sys.argv[1] if len(sys.argv) > 1 else '/workspace/ch0.csv')
