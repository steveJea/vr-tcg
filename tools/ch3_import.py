#!/usr/bin/env python3
"""챕터 3 대본(md) → js/story-data-ch3.js
사용법: python3 tools/ch3_import.py <대본 파일 ch3_yunha.md>
단일 루트(주인공 조윤하). '적: 이름, 이름(L)' 의 (L) = 상대 리더(전투 화면 상대 이름, 보스전이면 보스 카드).
페이즈별 강제 배정·추가 조건은 아래 RULES 표 (구글 문서 '챕터 3 스토리' 표 기준).
"""
import csv, json, os, re, sys
ROOT = os.path.join(os.path.dirname(__file__), '..')
rows = list(csv.DictReader(open(os.path.join(ROOT, 'data/cards.csv'), encoding='utf-8-sig')))
ID = {r['name']: r['id'] for r in rows}
YH, YI = ID['조윤하'], ID['조윤이']
# 페이즈 → (필수 출전, 대사 왼쪽 주인공, 추가 조건)
#  party 조건: noMale(남성 출전 불가) · maxMor(필수 카드 제외 MOR 이 값 초과 불가) · maxGrade(이 등급까지만) · exclude(출전 불가 카드) · enemyFirst(적 선공)
RULES = {
  1: ([YH], {'noMale': True}),
  2: ([YH], {'maxMor': 49}),
  3: ([YI], {}),
  4: ([YH], {'exclude': [YI]}),
  5: ([YH], {'exclude': [YI]}),
  6: ([YH], {'exclude': [YI], 'maxGrade': 'HIGH RARE'}),
  7: ([YH, YI], {'enemyFirst': True}),
  8: ([YH], {'enemyFirst': True}),
  9: ([YI], {'maxGrade': 'SUPER RARE'}),
  10: ([YH], {}),
}
PHASE10 = ['송지은', '송지아', '박성관', '고정태', '소민섭']   # 사용자 확정 (문서 초안의 다른 목록 무시)
LINE = re.compile(r'^\[([^:\]]+?)\s*(?:\((기본|화남|웃음)\))?:\s*(.*)\]$')

def parse(path):
    secs, cur = [], None
    for raw in open(path, encoding='utf-8'):
        s = raw.strip()
        if s.startswith('## '): cur = {'head': s[3:].strip(), 'lines': [], 'after': None, 'text': [], 'enemies': None}; secs.append(cur); continue
        if cur is None or not s: continue
        if s.startswith('- 전투 승리 후'): cur['after'] = []; continue
        m = LINE.match(s)
        if m:
            L = {'speaker': m.group(1).strip(), 'text': m.group(3).strip()}
            if m.group(2) and m.group(2) != '기본': L['expr'] = m.group(2)
            (cur['after'] if cur['after'] is not None else cur['lines']).append(L); continue
        if s.startswith('적:'): cur['enemies'] = [n.strip() for n in s[2:].split(',') if n.strip()]; continue
        if not s.startswith('Chapter'): cur['text'].append(s)
    return secs

def main(src):
    secs = parse(src); ch = {'id': 3, 'title': 'CHAPTER 3', 'subtitle': 'Just For YOU', 'rewardCard': None, 'hero': YH, 'single': True, 'phases': []}
    missing = set()
    for s in secs:
        h = s['head']
        if h.startswith('조윤하'): continue
        if h.startswith('캐릭터 소개'): ch['tagline'] = '\n'.join(s['text']); continue
        if h.startswith('시작 스토리'): ch['start'] = s['lines']; continue
        if h.startswith('엔딩'): ch['ending'] = s['lines']; continue
        m = re.match(r'Phase\.(\d+)\s*「(.+?)」', h)
        if not m: continue
        no = int(m.group(1)); names = s['enemies']
        lead = next((n.replace('(L)', '').strip() for n in names if '(L)' in n), None)
        names = [n.replace('(L)', '').strip() for n in names]
        if no == 10: assert sorted(names) == sorted(PHASE10), names
        missing |= {n for n in names if n not in ID}
        forced, cond = RULES[no]
        p = {'no': no, 'type': 'boss' if no == 10 else 'normal', 'enemyName': lead or '적군', 'title': m.group(2), 'enemies': {'ids': [ID.get(n) for n in names]},
             'lines': {'default': s['lines']}, 'party': {'forced': forced, **{k: v for k, v in cond.items() if k != 'enemyFirst'}}, 'hero': forced}
        if lead: p['bossId'] = ID[lead]
        if cond.get('enemyFirst'): p['enemyFirst'] = True
        if s['after']: p['after'] = s['after']; p['afterTitle'] = '전투 후'
        ch['phases'].append(p)
    for L in [*ch.get('start', []), *ch.get('ending', []), *(x for p in ch['phases'] for x in p['lines']['default'] + p.get('after', []))]:
        if L['speaker'] != '내레이션' and L['speaker'] not in ID: missing.add(L['speaker'])
    if missing: raise SystemExit(f'카드 없음: {sorted(missing)}')
    assert len(ch['phases']) == 10 and all(len(p['enemies']['ids']) == 5 for p in ch['phases'])
    js = ('// ===== 스토리 챕터 3 「Just For YOU」 (대본: vroyale/story/ch3_yunha.md → python3 tools/ch3_import.py <파일> 로 생성. 직접 고쳐도 됨) =====\n'
          '// 단일 루트(single): 주인공 조윤하. 시작 스토리는 챕터 3 처음 들어갈 때 1번. 페이즈 party: forced(필수) · exclude · noMale · maxMor · maxGrade, enemyFirst = 적 선공\n'
          'window.STORY_DATA.chapters.push(' + json.dumps(ch, ensure_ascii=False, indent=1) + ');\n')
    open(os.path.join(ROOT, 'js/story-data-ch3.js'), 'w', encoding='utf-8').write(js)
    print('ok', len(ch['phases']), 'phases')

main(sys.argv[1] if len(sys.argv) > 1 else '/workspace/vroyale/story/ch3_yunha.md')
